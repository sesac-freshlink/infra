# RDS 포트 포워딩: 내 PC 127.0.0.1:<LocalPort> → SSM 접속용 인스턴스 → RDS 3306.
# 이 창은 접속하는 동안 열어 둔다. 끝내려면 Ctrl+C.
#
# 김진아(terraform 쓰는 PC, infra 폴더에서):
#   powershell -ExecutionPolicy Bypass -File .\scripts\db-port-forward.ps1
# 팀원(terraform 없이. 지금 인스턴스 ID·DB 주소를 SSM 파라미터 /freshlink/<env>/...에서 읽는다):
#   powershell -ExecutionPolicy Bypass -File .\scripts\db-port-forward.ps1 -AwsProfile freshlink-dev
param(
    [string]$Env = "dev",
    [string]$InstanceId,
    [string]$DbHost,
    [int]$LocalPort = 3306,
    [string]$AwsProfile
)
$ErrorActionPreference = "Stop"

$awsArgs = @()
if ($AwsProfile) { $awsArgs = @("--profile", $AwsProfile) }

if (-not $InstanceId -or -not $DbHost) {
    # 1) terraform output (state를 읽을 수 있는 김진아 PC)
    $tfOk = $false
    $tfDir = Join-Path (Split-Path $PSScriptRoot -Parent) "envs\$Env\persistent"
    try {
        $tfId = terraform "-chdir=$tfDir" output -raw ssm_access_instance_id 2>$null
        $tfOk = ($LASTEXITCODE -eq 0)
        $tfHost = terraform "-chdir=$tfDir" output -raw db_address 2>$null
        $tfOk = $tfOk -and ($LASTEXITCODE -eq 0)
    } catch { $tfOk = $false }

    if ($tfOk -and $tfId -and $tfHost) {
        if (-not $InstanceId) { $InstanceId = $tfId }
        if (-not $DbHost) { $DbHost = $tfHost }
    } else {
        # 2) SSM 파라미터 (팀원. 인스턴스가 다시 만들어져도 지금 값이 들어 있다)
        if (-not $InstanceId) {
            $InstanceId = aws ssm get-parameter --name "/freshlink/$Env/ssm-access-instance-id" --query Parameter.Value --output text @awsArgs
            if ($LASTEXITCODE -ne 0) { throw "SSM 파라미터 /freshlink/$Env/ssm-access-instance-id 를 읽지 못했다. -AwsProfile freshlink-dev 를 붙였는지 본다." }
        }
        if (-not $DbHost) {
            $DbHost = aws ssm get-parameter --name "/freshlink/$Env/db-address" --query Parameter.Value --output text @awsArgs
            if ($LASTEXITCODE -ne 0) { throw "SSM 파라미터 /freshlink/$Env/db-address 를 읽지 못했다." }
        }
    }
}

Write-Host "포트 포워딩: 127.0.0.1:$LocalPort -> $DbHost`:3306 (경유 $InstanceId)"
Write-Host "'Waiting for connections...'가 나오면 성공이다. 이 창은 닫지 말고 다른 창에서 DB에 붙는다."

aws ssm start-session @awsArgs `
    --target $InstanceId `
    --document-name AWS-StartPortForwardingSessionToRemoteHost `
    --parameters "host=$DbHost,portNumber=3306,localPortNumber=$LocalPort"
