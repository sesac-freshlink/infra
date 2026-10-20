# 환경 persistent apply 결과를 GitHub에 넣는다 (할 일 14·15). 값을 손으로 옮겨 적지 않게 terraform output에서 바로 읽는다.
#   infra 레포 Actions 비밀  AWS_<ENV>_CLUSTER_ROLE_ARN           켜고 끄기 워크플로가 맡는 Role
#   frontend 레포 Variables  <ENV>_COGNITO_USER_POOL_ID, <ENV>_COGNITO_CLIENT_ID,
#                            <ENV>_FRONTEND_BUCKET, <ENV>_FRONTEND_DISTRIBUTION_ID, <ENV>_FRONTEND_DEPLOY_ROLE_ARN
# 여러 번 돌려도 된다(같은 값으로 덮어쓴다).
#
# 준비: gh auth login 이 되어 있고 조직 sesac-freshlink 관리자 계정이어야 한다.
# 실행(infra 폴더, $env:AWS_PROFILE = "freshlink-admin"):
#   powershell -ExecutionPolicy Bypass -File .\scripts\set-github-values.ps1 -Env prod
param(
    [ValidateSet("dev", "prod")]
    [string]$Env = "prod",
    [string]$Org = "sesac-freshlink"
)
$ErrorActionPreference = "Stop"

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "gh가 없다. 'winget install --id GitHub.cli -e --source winget' 뒤 PowerShell 창을 새로 열고 gh auth login 을 한다."
}

$tfDir = Join-Path (Split-Path $PSScriptRoot -Parent) "envs\$Env\persistent"
$out = (terraform "-chdir=$tfDir" output -json | Out-String) | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $out.cluster_actions_role_arn) {
    throw "envs\$Env\persistent terraform output을 읽지 못했다. 그 폴더에서 init·apply를 먼저 한다."
}

$prefix = $Env.ToUpper()

function Invoke-Gh([string[]]$ghArgs, [string]$what) {
    & gh @ghArgs
    if ($LASTEXITCODE -ne 0) { throw "$what 실패" }
    Write-Host "  $what"
}

Write-Host "$Org/infra Actions 비밀"
Invoke-Gh @("secret", "set", "AWS_${prefix}_CLUSTER_ROLE_ARN", "--repo", "$Org/infra", "--body", $out.cluster_actions_role_arn.value) "AWS_${prefix}_CLUSTER_ROLE_ARN"

Write-Host "$Org/frontend Variables"
$vars = [ordered]@{
    "${prefix}_COGNITO_USER_POOL_ID"       = $out.cognito_user_pool_id.value
    "${prefix}_COGNITO_CLIENT_ID"          = $out.cognito_app_client_id.value
    "${prefix}_FRONTEND_BUCKET"            = $out.frontend_bucket.value
    "${prefix}_FRONTEND_DISTRIBUTION_ID"   = $out.frontend_distribution_id.value
    "${prefix}_FRONTEND_DEPLOY_ROLE_ARN"   = $out.frontend_deploy_role_arn.value
}
foreach ($k in $vars.Keys) {
    if (-not $vars[$k]) { throw "terraform output에 $k 값이 없다." }
    Invoke-Gh @("variable", "set", $k, "--repo", "$Org/frontend", "--body", $vars[$k]) "$k = $($vars[$k])"
}

Write-Host ""
Write-Host "완료: 위 6줄이 모두 나오면 성공이다. $Env 프론트 주소: $($out.frontend_url.value)"
