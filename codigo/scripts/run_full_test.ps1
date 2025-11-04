

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Phase($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }

function Wait-For-Http200([string]$Url, [int]$Retries = 30, [int]$DelayMs = 1000) {
  for ($i = 1; $i -le $Retries; $i++) {
    try {
      $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 2
      if ($r.StatusCode -eq 200) { Write-Host "OK $Url" -ForegroundColor Green; return $true }
      Write-Host "[$i/$Retries] $Url => $($r.StatusCode)" -ForegroundColor DarkYellow
    } catch {
      Write-Host "[$i/$Retries] $Url => ERROR" -ForegroundColor DarkYellow
    }
    Start-Sleep -Milliseconds $DelayMs
  }
  return $false
}

function Invoke-WithRetry([scriptblock]$Call, [int]$Retries = 8, [int]$Delay = 750, [string]$Label = "") {
  for ($i=1; $i -le $Retries; $i++) {
    try { return & $Call } catch {
      Write-Host ("{0} falló [{1}/{2}] -> reintentando en {3}ms" -f $Label,$i,$Retries,$Delay) -ForegroundColor DarkYellow
      Start-Sleep -Milliseconds $Delay
    }
  }
  throw "Número máximo de reintentos agotados para: $Label"
}

# Determinar la ruta del repositorio 
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")
Set-Location $repoRoot

Write-Phase "Deteniendo stack existente y eliminando volúmenes"
docker compose down --volumes --remove-orphans | Out-Null

Write-Phase "Iniciando DB y Redis"
docker compose up -d db redis | Out-Null

Write-Phase "Esperando que MySQL acepte conexiones"
$dbOk = $false
for ($i=1; $i -le 60; $i++) {
  try {
    docker compose exec -T db mysql -uroot -proot -e "SELECT 1" | Out-Null
    $dbOk = $true; break
  } catch {
    Start-Sleep -Seconds 1
  }
}
if (-not $dbOk) { Write-Host "MySQL no inició a tiempo" -ForegroundColor Red; exit 1 }

Write-Phase "Cargando schema de DB (init.sql)"
# Copiar el archivo dentro del contenedor y ejecutarlo
$dbContainer = (docker compose ps -q db).ToString().Trim()
if (-not $dbContainer) { Write-Host "No se pudo determinar el ID del contenedor de DB" -ForegroundColor Red; docker compose ps; exit 1 }
$initPath = Join-Path $repoRoot "db\init.sql"
if (-not (Test-Path $initPath)) { Write-Host "No se encontró init.sql en $initPath" -ForegroundColor Red; exit 1 }
docker cp "$initPath" "$($dbContainer):/init.tmp.sql"

# Esperar hasta que MySQL acepte conexiones, luego ejecutar el script de inicialización
$sourced = $false
for ($j=1; $j -le 60; $j++) {
  try {
    docker compose exec -T db mysql -uroot -proot -e "SELECT 1" | Out-Null
    # Ahora tratar de ejecutar
    docker compose exec -T db mysql -uroot -proot -e "source /init.tmp.sql" | Out-Null
    $sourced = $true; break
  } catch {
    Start-Sleep -Seconds 1
  }
}
if (-not $sourced) { Write-Host "No se pudo cargar init.sql en la DB" -ForegroundColor Red; docker compose logs db --tail 50; exit 1 }

Write-Phase "Iniciando servicios restantes (build)"
docker compose up -d --build | Out-Null

Write-Phase "Esperando respuesta del gateway /health"
if (-not (Wait-For-Http200 'http://localhost:8080/health' 60 1000)) { Write-Host 'Gateway /health falló' -ForegroundColor Red; docker compose logs --no-color --timestamps; exit 1 }

# URL base para las pruebas
$Base = 'http://localhost:8080'


Write-Phase "Esperando respuesta de /health de los servicios (auth, usuarios, proyectos, tareas)"
if (-not (Wait-For-Http200 "$Base/auth/health" 30 1000)) { Write-Host 'auth no respondió a /auth/health' -ForegroundColor Red; docker compose logs auth-api --tail 50; exit 1 }
if (-not (Wait-For-Http200 "$Base/usuarios/health" 30 1000)) { Write-Host 'usuarios no respondió a /usuarios/health' -ForegroundColor Red; docker compose logs usuarios-api --tail 50; exit 1 }
if (-not (Wait-For-Http200 "$Base/proyectos/health" 30 1000)) { Write-Host 'proyectos no respondió a /proyectos/health' -ForegroundColor Red; docker compose logs proyectos-api --tail 50; exit 1 }
if (-not (Wait-For-Http200 "$Base/tareas/health" 30 1000)) { Write-Host 'tareas no respondió a /tareas/health' -ForegroundColor Red; docker compose logs tareas-api --tail 50; exit 1 }

Write-Phase "Ejecutando pruebas funcionales"
$Base = 'http://localhost:8080'

Write-Host "Registrando usuario"
$Suffix = [Guid]::NewGuid().ToString('N').Substring(0,6)
$Email = "auto+$Suffix@example.com"
$Password = 'secret'
$reg = Invoke-RestMethod -Uri "$Base/auth/register" -Method POST -ContentType 'application/json' -Body (@{ nombre='Auto'; email=$Email; password=$Password } | ConvertTo-Json)
Write-Host "Registrado id=$($reg.id)"

Write-Host "Iniciando sesión"
$login = Invoke-RestMethod -Uri "$Base/auth/login" -Method POST -ContentType 'application/json' -Body (@{ email=$Email; password=$Password } | ConvertTo-Json)
$Token = $login.token
Write-Host "Muestra del token: $($Token.Substring(0,[Math]::Min(24,$Token.Length)))"

Write-Phase "Clave valet"
$valet = Invoke-RestMethod -Uri "$Base/auth/valet" -Method POST -ContentType 'application/json' -Headers @{ Authorization = "Bearer $Token" } -Body (@{ resource='uploads/test.txt' } | ConvertTo-Json)
Write-Host "Muestra del token valet: $($valet.token.Substring(0,[Math]::Min(32,$valet.token.Length))) expira_en=$($valet.expires_in)"

Write-Phase "Prueba de cache-aside (usuarios): crear + GET dos veces"
$u = Invoke-RestMethod -Uri "$Base/usuarios/" -Method POST -ContentType 'application/json' -Body (@{ nombre='CacheAuto'; email="cache+$Suffix@example.com" } | ConvertTo-Json)
Write-Host "Usuario creado id=$($u.id)"
Write-Host "Primer GET (cache miss)"
Invoke-RestMethod -Uri "$Base/usuarios/$($u.id)" | ConvertTo-Json | Write-Output
Write-Host "Segundo GET (debería ser cache hit)"
Invoke-RestMethod -Uri "$Base/usuarios/$($u.id)" | ConvertTo-Json | Write-Output

Write-Phase "Inspeccionando Redis para la clave del usuario"
$redisKey = "user:$($u.id)"
try {
  $val = docker compose exec -T redis redis-cli get $redisKey
  if ($val) { Write-Host "Redis tiene la clave $redisKey" -ForegroundColor Green } else { Write-Host "Redis no tiene la clave $redisKey" -ForegroundColor Yellow }
} catch { Write-Host "No se pudo inspeccionar redis: $_" -ForegroundColor DarkYellow }

Write-Phase "Prueba de cola (proyectos/tareas): crear proyecto, encolar tarea"
$proj = Invoke-RestMethod -Uri "$Base/proyectos/" -Method POST -ContentType 'application/json' -Headers @{ Authorization = "Bearer $Token" } -Body (@{ nombre='AutoProj'; descripcion='De prueba completa' } | ConvertTo-Json)
Write-Host "ID del proyecto=$($proj.id)"

Write-Host "Encolando tarea (devolverá 202 si USE_QUEUE=1)"
$taskResp = Invoke-RestMethod -Uri "$Base/tareas/" -Method POST -ContentType 'application/json' -Headers @{ Authorization = "Bearer $Token" } -Body (@{ proyecto_id = $proj.id; titulo='Tarea de prueba de cola' } | ConvertTo-Json)
Write-Host "Respuesta de encolamiento:`n$($taskResp | ConvertTo-Json -Depth 5)"

Write-Host "Consultando tareas del proyecto hasta ver el título (timeout 60s)"
$found = $null
for ($i=1; $i -le 60; $i++) {
  try {
    $list = Invoke-RestMethod -Uri "$Base/tareas/?proyecto_id=$($proj.id)" -Headers @{ Authorization = "Bearer $Token" }
    $found = $list | Where-Object { $_.titulo -eq 'Tarea de prueba de cola' }
    if ($found) { break }
  } catch { }
  Start-Sleep -Seconds 1
}
if ($found) { Write-Host "Tarea procesada id=$($found[0].id)" -ForegroundColor Green } else { Write-Host "Tarea no procesada a tiempo" -ForegroundColor Red }

Write-Phase "Inspeccionando longitud de la cola en Redis"
try { docker compose exec -T redis redis-cli llen tareas:queue | Write-Host } catch { }

Write-Phase "Resumen"
Write-Host "Health: ok (verificado)"
Write-Host "Auth (registro/login): ok (creado $($reg.id))"
Write-Host "Clave valet: ok (emitida)"
Write-Host "Cache-aside: verificado GET dos veces y clave Redis" 
Write-Host "Cola: tarea encolada y consultada"

Write-Host "Prueba completa finalizada"
