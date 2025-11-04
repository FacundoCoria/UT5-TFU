param(
  [switch]$SetupOnly,
  [string]$Base = "http://localhost:8080",
  [int]$MaxRetries = 40,   # ~20s (40 * 500ms)
  [int]$DelayMs = 500
)

$ErrorActionPreference = "Stop"

function Wait-For-Http200([string]$Url, [int]$Retries, [int]$Delay) {
  for ($i=1; $i -le $Retries; $i++) {
    try {
      $resp = Invoke-WebRequest $Url -Method GET -UseBasicParsing -TimeoutSec 2
      if ($resp.StatusCode -eq 200) {
        Write-Host "OK $($resp.StatusCode) $Url" -ForegroundColor Green
        return $true
      }
    } catch {
      Start-Sleep -Milliseconds $Delay
    }
  }
  return $false
}

Write-Host "Levantando (build + up)..." -ForegroundColor Cyan
docker compose up -d --build | Out-Null

if ($SetupOnly) {
  Write-Host "Ambiente listo (SetupOnly)."
  exit 0
}

Write-Host "Esperando gateway en $Base/health ..." -ForegroundColor Yellow
if (-not (Wait-For-Http200 "$Base/health" $MaxRetries $DelayMs)) {
  Write-Error "Gateway no respondió en tiempo. Revisá: docker compose logs -f gateway"
}

# 1) Register (idempotente)
Write-Host "==> Register" -ForegroundColor Green
try {
  $reg = Invoke-RestMethod "$Base/auth/register" -Method POST -ContentType 'application/json' -Body '{"nombre":"Linus","email":"linus@example.com","password":"secret"}'
  if ($reg.id) { Write-Host ("Usuario creado id={0}" -f $reg.id) -ForegroundColor DarkGreen }
} catch {
  Write-Host "Registro omitido (posible email existente)" -ForegroundColor DarkYellow
}

# 2) Login
Write-Host "==> Login" -ForegroundColor Green
$login = Invoke-RestMethod "$Base/auth/login" -Method POST -ContentType 'application/json' -Body '{"email":"linus@example.com","password":"secret"}'
$Token = $login.token
if (-not $Token) { Write-Error "No se obtuvo token" }
Write-Host ("TOKEN: {0}" -f $Token.Substring(0,[Math]::Min(16,$Token.Length))) -ForegroundColor DarkCyan

# 3) /auth/me
Write-Host "==> /auth/me" -ForegroundColor Green
Invoke-RestMethod "$Base/auth/me" -Headers @{ Authorization = "Bearer $Token" } | ConvertTo-Json -Depth 5 | Write-Output

# 4) Crear proyecto
Write-Host "==> Crear proyecto" -ForegroundColor Green
$proj = Invoke-RestMethod "$Base/proyectos/" -Method POST `
  -Headers @{ Authorization = "Bearer $Token" } `
  -ContentType 'application/json' -Body '{"nombre":"Demo TFU","descripcion":"Proyecto demo"}'
$ProjId = $proj.id
if (-not $ProjId) { Write-Error "No se obtuvo id de proyecto" }
Write-Host ("Proyecto id={0}" -f $ProjId) -ForegroundColor DarkGreen

# 5) Crear tarea
Write-Host "==> Crear tarea" -ForegroundColor Green
$bodyTask = "{`"proyecto_id`":$ProjId,`"titulo`":`"Primera tarea`"}"
$t = Invoke-RestMethod "$Base/tareas/" -Method POST -Headers @{ Authorization = "Bearer $Token" } -ContentType 'application/json' -Body $bodyTask
$TaskId = $t.id
if (-not $TaskId) { Write-Error "No se obtuvo id de tarea" }
Write-Host ("Tarea id={0}" -f $TaskId) -ForegroundColor DarkGreen

# 6) Cambiar estado -> done
Write-Host "==> Cambiar estado tarea -> done" -ForegroundColor Green
Invoke-RestMethod "$Base/tareas/$TaskId/estado" -Method PATCH `
  -Headers @{ Authorization = "Bearer $Token" } `
  -ContentType 'application/json' -Body '{"estado":"done"}' | Out-Null

# 7) Listados
Write-Host "==> Listar proyectos y tareas" -ForegroundColor Green
Invoke-RestMethod "$Base/proyectos/" -Headers @{ Authorization = "Bearer $Token" } | ConvertTo-Json -Depth 5 | Write-Output
Invoke-RestMethod "$Base/tareas/?proyecto_id=$ProjId" -Headers @{ Authorization = "Bearer $Token" } | ConvertTo-Json -Depth 5 | Write-Output

Write-Host "Demo OK" -ForegroundColor Green
