<#
Quick test script with curl examples (PowerShell). Replace <TOKEN> with a real JWT from login.

Run examples manually or paste commands in PowerShell.
#>

$BASE = "http://localhost:8080"

Write-Host "1) Health (gateway & services)"
Write-Host "curl $BASE/health"
curl "$BASE/health"; Write-Host "`n"

Write-Host "2) Register + Login to get JWT (auth)"
$reg = curl -s -X POST "$BASE/auth/register" -H 'Content-Type: application/json' -d '{"nombre":"Test","email":"test+1@example.com","password":"secret"}' | ConvertFrom-Json
Write-Host "registered id: $($reg.id)"
$login = curl -s -X POST "$BASE/auth/login" -H 'Content-Type: application/json' -d '{"email":"test+1@example.com","password":"secret"}' | ConvertFrom-Json
Write-Host "token sample: $($login.token.Substring(0,[Math]::Min(32,$login.token.Length)))"

Write-Host "3) Valet key (short-lived)"
 $valet = curl -s -X POST "$BASE/auth/valet" -H "Authorization: Bearer $($login.token)" -H 'Content-Type: application/json' -d '{"resource":"uploads/1"}' | ConvertFrom-Json
 Write-Host "valet: $($valet.token) expires: $($valet.expires_in)"

Write-Host "4) Cache-aside: create user, get user twice"
$u = curl -s -X POST "$BASE/usuarios/" -H 'Content-Type: application/json' -d '{"nombre":"CacheUser","email":"cache@example.com"}' | ConvertFrom-Json
Write-Host "created user id: $($u.id)"
Write-Host "GET first (cache miss)"
curl "$BASE/usuarios/$($u.id)"; Write-Host "`n"
Write-Host "GET second (should be cache hit)"
curl "$BASE/usuarios/$($u.id)"; Write-Host "`n"

Write-Host "5) Queue: create tarea (when USE_QUEUE=1 returns 202)"
 $taskResp = curl -s -X POST "$BASE/tareas/" -H "Authorization: Bearer $($login.token)" -H 'Content-Type: application/json' -d '{"proyecto_id":1,"titulo":"Tarea desde queue"}'
 Write-Host "resp: $taskResp"

Write-Host "6) To inspect Redis (if local): redis-cli -h 127.0.0.1 -p 6379 lrange tareas:queue 0 -1"
