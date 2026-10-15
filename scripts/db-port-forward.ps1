# RDS 포트 포워딩: 내 PC 127.0.0.1:<LocalPort> → SSM 접속용 인스턴스 → RDS 3306.
# 이 창은 접속하는 동안 열어 둔다. 끝내려면 Ctrl+C.
#
# 김진아(terraform 쓰는 PC, infra 폴더에서):
#   powershell -ExecutionPolicy Bypass -File .\scripts\db-port-forward.ps1
# 팀원(terraform 없이, 받은 값으로):
#   powershell -ExecutionPolicy Bypass -File .\db-port-forward.ps1 -InstanceId i-xxxx -DbHost freshlink-dev-mysql.xxxx.ap-northeast-2.rds.amazonaws.com
param(
    [string]$Env = "dev",
    [string]$InstanceId,
    [string]$DbHost,
    [int]$LocalPort = 3306
)
$ErrorActionPreference = "Stop"

if (-not $InstanceId -or -not $DbHost) {
    $tfDir = Join-Path (Split-Path $PSScriptRoot -Parent) "envs\$Env\persistent"
    $InstanceId = terraform "-chdir=$tfDir" output -raw ssm_access_instance_id
    $DbHost = terraform "-chdir=$tfDir" output -raw db_address
    if ($LASTEXITCODE -ne 0) { throw "terraform output을 읽지 못했다. infra 폴더에서 init·apply를 먼저 한다." }
}

Write-Host "포트 포워딩: 127.0.0.1:$LocalPort -> $DbHost`:3306 (경유 $InstanceId)"
Write-Host "'Waiting for connections...'가 나오면 성공이다. 이 창은 닫지 말고 다른 창에서 DB에 붙는다."

aws ssm start-session `
    --target $InstanceId `
    --document-name AWS-StartPortForwardingSessionToRemoteHost `
    --parameters "host=$DbHost,portNumber=3306,localPortNumber=$LocalPort"
