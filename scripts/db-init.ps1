# 서비스 스키마와 앱 DB 사용자를 만든다: member·inventory·orders·notification (여러 번 돌려도 된다. 비밀번호는 Secrets Manager 값으로 맞춘다).
# 테이블은 만들지 않는다. 각 서비스 Flyway가 만든다.
#
# 준비: 다른 PowerShell 창에서 scripts\db-port-forward.ps1이 'Waiting for connections...' 상태여야 한다.
# 실행(infra 폴더, $env:AWS_PROFILE = "freshlink-admin"):
#   powershell -ExecutionPolicy Bypass -File .\scripts\db-init.ps1
param(
    [string]$Env = "dev",
    [int]$LocalPort = 3306
)
$ErrorActionPreference = "Stop"

if (-not (Get-Command mysqlsh -ErrorAction SilentlyContinue)) {
    throw "mysqlsh가 없다. 'winget install --id Oracle.MySQLShell -e --source winget' 뒤 PowerShell 창을 새로 연다."
}

$tfDir = Join-Path (Split-Path $PSScriptRoot -Parent) "envs\$Env\persistent"
$out = (terraform "-chdir=$tfDir" output -json | Out-String) | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw "terraform output을 읽지 못했다. infra 폴더에서 init·apply를 먼저 한다." }

function Get-SecretJson([string]$id) {
    $raw = aws secretsmanager get-secret-value --secret-id $id --query SecretString --output text
    if ($LASTEXITCODE -ne 0) { throw "비밀 $id 를 읽지 못했다." }
    return $raw | ConvertFrom-Json
}

$master = Get-SecretJson $out.master_user_secret_arn.value

$sql = New-Object System.Collections.Generic.List[string]
foreach ($p in $out.app_databases.value.PSObject.Properties) {
    $svc = $p.Name
    $schema = $p.Value.schema
    $user = $p.Value.username
    $app = Get-SecretJson $out.app_db_secret_names.value.$svc
    $pw = $app.password

    $sql.Add('CREATE DATABASE IF NOT EXISTS `{0}` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;' -f $schema)
    $sql.Add(('CREATE USER IF NOT EXISTS ''{0}''@''%'' IDENTIFIED BY ''{1}'';' -f $user, $pw))
    $sql.Add(('ALTER USER ''{0}''@''%'' IDENTIFIED BY ''{1}'';' -f $user, $pw))
    $sql.Add(('GRANT ALL PRIVILEGES ON `{0}`.* TO ''{1}''@''%'';' -f $schema, $user))
}
$sql.Add("SELECT schema_name FROM information_schema.schemata WHERE schema_name IN ('member', 'inventory', 'orders', 'notification');")
$sql.Add("SELECT user, host FROM mysql.user WHERE user LIKE '%\_app';")

$tmp = [System.IO.Path]::GetTempFileName()
try {
    Set-Content -Path $tmp -Value $sql -Encoding Ascii
    mysqlsh --sql "--host=127.0.0.1" "--port=$LocalPort" "--user=$($master.username)" "--password=$($master.password)" "--file=$tmp"
    if ($LASTEXITCODE -ne 0) { throw "SQL 실행 실패. 포트 포워딩 창이 열려 있는지 확인한다." }
} finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "완료: 위에 스키마 4개(inventory, member, notification, orders)와 사용자 4개(*_app)가 보이면 성공이다."
