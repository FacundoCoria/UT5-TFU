param(
  [string]$Base = "http://localhost:8080",
  [int]$MaxRetries = 120,  # ~60s (120 * 500ms)
  [int]$DelayMs = 500
)

$ErrorActionPreference = "Stop"

function Try-Get200([string]$Url, [int]$Timeout = 3) {
  try {
    $resp = Invoke-WebRequest $Url -Method GET -UseBasicParsing -TimeoutSec $Timeout
    return @{ ok = ($resp.StatusCode -eq 200); status = $resp.StatusCode; body = $resp.Content }
  } catch {
    # devolver detalle mínimo, sin tirar excepción
    $code = $null
    $body = $null
    try { $code = [int]$_.Exception.Response.StatusCode } catch {}
    try {
      if ($_.Exception.Response -ne $null) {
        $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $body = $sr.ReadToEnd()
      }
    } catch {}
    return @{ ok = $false; status = $code; body = $body }
  }
}

function Wait-Service([string]$Name, [string[]]$HealthUrls, [int]$Retries, [int]$Delay) {
  Write-Host ("==> esperando {0} ({1})" -f $Name, ($HealthUrls -join " OR ")) -ForegroundColor Yellow
  for ($i=1; $i -le $Retries; $i++) {
    foreach ($u in $HealthUrls) {
      $r = Try-Get200 $u 3
      if ($r.ok) {
        Write-Host ("OK 200 {0}" -f $u) -ForegroundColor Green
        return $true
      } else {
        $st = if ($r.status) { $r.status } else { "ERR" }
        Write-Host ("[{0}/{1}] {2} => {3}" -f $i, $Retries, $u, $st) -ForegroundColor DarkGray
      }
    }
    Start-Sleep -Milliseconds $Delay
  }
  return $false
}

function Show-HttpErrorDetails([System.Management.Automation.ErrorRecord]$err) {
  try {
    $resp = $err.Exception.Response
    if ($resp -ne $null) {
      $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
      $body = $sr.ReadToEnd()
      Write-Host "Status: $([int]$resp.StatusCode) $($resp.StatusCode)" -ForegroundColor Red
      Write-Host "Body  : $body" -ForegroundColor Red
    } else {
      Write-Host "Sin Response en la excepción" -ForegroundColor Red
    }
  } catch {
    Write-Host "No se pudo leer el body del error" -ForegroundColor DarkRed
  }
}

Write-Host "==> (re)build + up" -ForegroundColor Cyan
docker compose up -d --build | Out-Null

# 1) Gateway
if (-not (Wait-Service "gateway" @("$Base/health") $MaxRetries $DelayMs)) {
  throw "Gateway no respondió /health"
}

# 2) Upstreams (para auth probamos health y diag)
$targets = @(
  @{ name="auth";      urls=@("$Base/auth/health", "$Base/auth/diag") },
  @{ name="usuarios";  urls=@("$Base/usuarios/health") },
  @{ name="proyectos"; urls=@("$Base/proyectos/health") },
  @{ name="tareas";    urls=@("$Base/tareas/health") }
)
foreach ($t in $targets) {
  if (-not (Wait-Service $t.name $t.urls $MaxRetries $DelayMs)) {
    Write-Host ("{0} no respondió" -f $t.name) -ForegroundColor Red
    Write-Host "`n==> Logs recientes gateway/auth/proyectos/tareas/usuarios (3m)" -ForegroundColor Yellow
    docker compose logs --no-color gateway       --since=3m
    docker compose logs --no-color auth-api      --since=3m
    docker compose logs --no-color proyectos-api --since=3m
    docker compose logs --no-color tareas-api    --since=3m
    docker compose logs --no-color usuarios-api  --since=3m
    throw ("Upstream no respondió: {0}" -f ($t.urls -join " OR "))
  }
}

# ===== flujo e2e =====
$Suffix = [Guid]::NewGuid().ToString("N").Substring(0,6)
$Email  = "linus+$Suffix@example.com"
$Pwd    = "secret"

try {
  Write-Host "==> Register ($Email)" -ForegroundColor Green
  $reg = Invoke-RestMethod "$Base/auth/register" -Method POST `
    -ContentType 'application/json' -Body (@{ nombre="Linus"; email=$Email; password=$Pwd } | ConvertTo-Json)
  if ($reg.id) { Write-Host ("Usuario id={0}" -f $reg.id) -ForegroundColor DarkGreen }
} catch {
  Write-Host "Register lanzó error:" -ForegroundColor DarkYellow
  Show-HttpErrorDetails $_
  throw
}

try {
  Write-Host "==> Login ($Email)" -ForegroundColor Green
  $login = Invoke-RestMethod "$Base/auth/login" -Method POST `
    -ContentType 'application/json' -Body (@{ email=$Email; password=$Pwd } | ConvertTo-Json)
  $Token = $login.token
  if (-not $Token) { throw "No se obtuvo token" }
  Write-Host ("TOKEN: {0}" -f $Token.Substring(0,[Math]::Min(16,$Token.Length))) -ForegroundColor DarkCyan
} catch {
  Write-Host "Login lanzó error:" -ForegroundColor Red
  Show-HttpErrorDetails $_
  throw
}

Write-Host "==> /auth/me" -ForegroundColor Green
Invoke-RestMethod "$Base/auth/me" -Headers @{ Authorization = "Bearer $Token" } | ConvertTo-Json -Depth 5 | Write-Output

# Crear proyecto
try {
  Write-Host "==> Crear proyecto" -ForegroundColor Green
  $proj = Invoke-RestMethod "$Base/proyectos/" -Method POST `
    -Headers @{ Authorization = "Bearer $Token" } `
    -ContentType 'application/json' `
    -Body '{"nombre":"Demo TFU","descripcion":"Proyecto demo"}'
  $ProjId = $proj.id
  if (-not $ProjId) { throw "No se obtuvo id de proyecto" }
  Write-Host ("Proyecto id={0}" -f $ProjId) -ForegroundColor DarkGreen
} catch {
  Write-Host "Crear proyecto lanzó error:" -ForegroundColor Red
  Show-HttpErrorDetails $_
  throw
}

# Crear tarea
try {
  Write-Host "==> Crear tarea" -ForegroundColor Green
  $bodyTask = "{`"proyecto_id`":$ProjId,`"titulo`":`"Primera tarea`"}"
  $t = Invoke-RestMethod "$Base/tareas/" -Method POST `
    -Headers @{ Authorization = "Bearer $Token" } `
    -ContentType 'application/json' `
    -Body $bodyTask
  $TaskId = $t.id
  if (-not $TaskId) { throw "No se obtuvo id de tarea" }
  Write-Host ("Tarea id={0}" -f $TaskId) -ForegroundColor DarkGreen
} catch {
  Write-Host "Crear tarea lanzó error:" -ForegroundColor Red
  Show-HttpErrorDetails $_
  throw
}

# Cambiar estado
try {
  Write-Host "==> Cambiar estado tarea -> done" -ForegroundColor Green
  Invoke-RestMethod "$Base/tareas/$TaskId/estado" -Method PATCH `
    -Headers @{ Authorization = "Bearer $Token" } `
    -ContentType 'application/json' `
    -Body '{"estado":"done"}' | Out-Null
} catch {
  Write-Host "Cambiar estado lanzó error:" -ForegroundColor Red
  Show-HttpErrorDetails $_
  throw
}

# Listar
Write-Host "==> Listar proyectos y tareas" -ForegroundColor Green
Invoke-RestMethod "$Base/proyectos/" -Headers @{ Authorization = "Bearer $Token" } | ConvertTo-Json -Depth 5 | Write-Output
Invoke-RestMethod "$Base/tareas/?proyecto_id=$ProjId" -Headers @{ Authorization = "Bearer $Token" } | ConvertTo-Json -Depth 5 | Write-Output

Write-Host "Demo E2E OK" -ForegroundColor Green
