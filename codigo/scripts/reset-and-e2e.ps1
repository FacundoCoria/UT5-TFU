param(
  [string]$Base = "http://localhost:8080",
  [int]$MaxRetries = 120,   # para health checks (auth a veces tarda)
  [int]$DelayMs = 1000,     # 1s entre reintentos
  [switch]$NoRebuild        # si querés evitar --build
)

$ErrorActionPreference = "Stop"

function Write-Phase($text) { Write-Host "`n=== $text ===" -ForegroundColor Cyan }

function Wait-For-Http200([string]$Url, [int]$Retries, [int]$Delay) {
  for ($i=1; $i -le $Retries; $i++) {
    try {
      $resp = Invoke-WebRequest $Url -Method GET -UseBasicParsing -TimeoutSec 2
      if ($resp.StatusCode -eq 200) {
        Write-Host "OK $($resp.StatusCode) $Url" -ForegroundColor Green
        return $true
      }
      Write-Host "[$i/$Retries] $Url => $($resp.StatusCode)" -ForegroundColor DarkYellow
    } catch {
      $code = $_.Exception.Response.StatusCode.value__
      if ($code) {
        Write-Host "[$i/$Retries] $Url => $code" -ForegroundColor DarkYellow
      } else {
        Write-Host "[$i/$Retries] $Url => ERROR" -ForegroundColor DarkYellow
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
      Write-Host "Status: $($resp.StatusCode) $([int]$resp.StatusCode)" -ForegroundColor Red
      Write-Host "Body  : $body" -ForegroundColor Red
    } else {
      Write-Host "Sin Response en la excepción" -ForegroundColor Red
    }
  } catch {
    Write-Host "No se pudo leer el body del error" -ForegroundColor DarkRed
  }
}

function Invoke-WithRetry([scriptblock]$Call, [int]$Retries = 8, [int]$Delay = 750, [string]$Label = "") {
  for ($i=1; $i -le $Retries; $i++) {
    try {
      return & $Call
    } catch {
      Write-Host ("{0} fallo [{1}/{2}] -> retry en {3}ms" -f $Label,$i,$Retries,$Delay) -ForegroundColor DarkYellow
      Show-HttpErrorDetails $_
      Start-Sleep -Milliseconds $Delay
    }
  }
  throw "Max reintentos agotados para: $Label"
}

function Save-Logs {
  New-Item -ItemType Directory -Force -Path .\scripts\logs | Out-Null
  docker compose logs --no-color gateway        --since=15m | Out-File .\scripts\logs\gateway.snapshot.log        -Encoding UTF8
  docker compose logs --no-color auth-api       --since=15m | Out-File .\scripts\logs\auth-api.snapshot.log       -Encoding UTF8
  docker compose logs --no-color proyectos-api  --since=15m | Out-File .\scripts\logs\proyectos-api.snapshot.log  -Encoding UTF8
  docker compose logs --no-color tareas-api     --since=15m | Out-File .\scripts\logs\tareas-api.snapshot.log     -Encoding UTF8
  docker compose logs --no-color usuarios-api   --since=15m | Out-File .\scripts\logs\usuarios-api.snapshot.log   -Encoding UTF8
  Write-Host "Logs guardados en: $(Resolve-Path .\scripts\logs)" -ForegroundColor Cyan
}

# ========== 1) Tear down + DB solo ==========
Write-Phase "Bajando stack y borrando volúmenes"
docker compose down --volumes --remove-orphans | Out-Null

Write-Phase "Subiendo SOLO la DB"
docker compose up -d db | Out-Null

# Esperar a que MySQL acepte conexiones
Write-Host "Esperando DB (SELECT 1)..." -ForegroundColor Yellow
for ($i=1; $i -le 60; $i++) {
  try {
    docker exec -i unidad3-db-1 mysql -uroot -proot -e "SELECT 1" | Out-Null
    Write-Host "DB OK" -ForegroundColor Green
    break
  } catch {
    if ($i -eq 60) { throw "MySQL no respondió a tiempo" }
    Start-Sleep -Milliseconds 1000
  }
}

# ========== 2) Repoblar DB ==========
Write-Phase "Repoblando DB con db/init.sql"
docker cp .\db\init.sql unidad3-db-1:/init.tmp.sql | Out-Null
docker exec -i unidad3-db-1 mysql -uroot -proot -e "source /init.tmp.sql"

# ========== 3) Subir el resto del stack ==========
Write-Phase "Levantando servicios"
if ($NoRebuild) {
  docker compose up -d | Out-Null
} else {
  docker compose up -d --build | Out-Null
}

# ========== 4) Wait gateway + upstreams ==========
Write-Phase "Esperando gateway /health"
if (-not (Wait-For-Http200 "$Base/health" 60 500)) {
  Write-Host "Gateway no respondió" -ForegroundColor Red
  Save-Logs; exit 1
}

Write-Phase "Esperando upstreams /health (con backoff para auth)"
# auth puede demorar un toque por el arranque de Node
$authReady = $false
for ($i=1; $i -le $MaxRetries; $i++) {
  $ok1 = Wait-For-Http200 "$Base/auth/health" 1 1
  $ok2 = Wait-For-Http200 "$Base/auth/diag"   1 1
  if ($ok1 -or $ok2) { $authReady = $true; break }
  Start-Sleep -Milliseconds $DelayMs
}
if (-not $authReady) { Write-Host "auth no levantó" -ForegroundColor Red; Save-Logs; exit 1 }

if (-not (Wait-For-Http200 "$Base/usuarios/health" 30 500)) { Save-Logs; exit 1 }
if (-not (Wait-For-Http200 "$Base/proyectos/health" 30 500)) { Save-Logs; exit 1 }
if (-not (Wait-For-Http200 "$Base/tareas/health"    30 500)) { Save-Logs; exit 1 }

# ========== 5) Flujo E2E ==========
Write-Phase "E2E: registro + login"
$Suffix = [Guid]::NewGuid().ToString("N").Substring(0,6)
$Email  = "linus+$Suffix@example.com"
$Pwd    = "secret"

try {
  $reg = Invoke-RestMethod "$Base/auth/register" -Method POST -ContentType 'application/json' -Body (@{
    nombre = "Linus"; email = $Email; password = $Pwd } | ConvertTo-Json)
  Write-Host ("Usuario id={0}" -f $reg.id) -ForegroundColor DarkGreen
} catch {
  Write-Host "Register lanzó error (puede ser idempotente):" -ForegroundColor DarkYellow
  Show-HttpErrorDetails $_
}

$login = Invoke-RestMethod "$Base/auth/login" -Method POST -ContentType 'application/json' -Body (@{
  email = $Email; password = $Pwd } | ConvertTo-Json)
$Token = $login.token
Write-Host ("TOKEN: {0}" -f $Token.Substring(0,[Math]::Min(16,$Token.Length))) -ForegroundColor DarkCyan

Write-Phase "/auth/me"
Invoke-RestMethod "$Base/auth/me" -Headers @{ Authorization = "Bearer $Token" } | ConvertTo-Json -Depth 5 | Write-Output

Write-Phase "Crear proyecto"
$proj = Invoke-RestMethod "$Base/proyectos/" -Method POST `
  -Headers @{ Authorization = "Bearer $Token" } `
  -ContentType 'application/json' -Body '{"nombre":"Demo Reset","descripcion":"Proyecto desde reset-and-e2e.ps1"}'
$ProjId = $proj.id
Write-Host ("Proyecto id={0}" -f $ProjId) -ForegroundColor DarkGreen

Write-Phase "Crear tarea (con reintentos)"
$bodyTask = "{`"proyecto_id`":$ProjId,`"titulo`":`"Primera tarea`"}"
$t = Invoke-WithRetry { 
  Invoke-RestMethod "$Base/tareas/" -Method POST `
    -Headers @{ Authorization = "Bearer $Token" } `
    -ContentType 'application/json' -Body $bodyTask
} 8 750 "POST /tareas/"

if ($t -and $t.id) {
  $TaskId = $t.id
  Write-Host ("Tarea id={0}" -f $TaskId) -ForegroundColor DarkGreen
} elseif ($t -and $t.enqueued) {
  Write-Host "Tarea encolada; esperando worker la procese..." -ForegroundColor Yellow
  # Poll tareas list until task with expected title appears (timeout)
  $expectedTitle = 'Primera tarea'
  $found = $null
  for ($i=1; $i -le 60; $i++) {
    try {
      $list = Invoke-RestMethod "$Base/tareas/?proyecto_id=$ProjId" -Headers @{ Authorization = "Bearer $Token" }
      $found = $list | Where-Object { $_.titulo -eq $expectedTitle }
      if ($found) { break }
    } catch {
      # ignore and retry
    }
    Start-Sleep -Milliseconds 1000
  }
  if (-not $found) { Write-Host "Worker no procesó la tarea en tiempo" -ForegroundColor Red; Save-Logs; exit 1 }
  $TaskId = $found[0].id
  Write-Host ("Tarea id={0} (post-queue)" -f $TaskId) -ForegroundColor DarkGreen
} else {
  Write-Host "Respuesta inesperada al crear tarea:" -ForegroundColor Red; Write-Output $t; Save-Logs; exit 1
}

Write-Phase "Cambiar estado -> done"
Invoke-RestMethod "$Base/tareas/$TaskId/estado" -Method PATCH `
  -Headers @{ Authorization = "Bearer $Token" } `
  -ContentType 'application/json' -Body '{"estado":"done"}' | Out-Null

Write-Phase "Listar proyectos y tareas"
Invoke-RestMethod "$Base/proyectos/" -Headers @{ Authorization = "Bearer $Token" } | ConvertTo-Json -Depth 5 | Write-Output
Invoke-RestMethod "$Base/tareas/?proyecto_id=$ProjId" -Headers @{ Authorization = "Bearer $Token" } | ConvertTo-Json -Depth 5 | Write-Output

Write-Host "`n>>> E2E OK" -ForegroundColor Green
