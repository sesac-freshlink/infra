# Discord DLQ 채널 웹훅 주소를 Secrets Manager(freshlink-<env>-dlq-webhook)에 넣고, 시험 메시지를 한 번 보낸다.
# 값은 Terraform·레포·화면 기록에 남지 않는다(주소는 입력할 때 화면에 보이지 않는다).
#   Secrets Manager  freshlink-<env>-dlq-webhook  JSON url  → Lambda freshlink-<env>-dlq-alert가 읽는다
# 배포 알림 웹훅(GitHub 비밀 DEPLOY_WEBHOOK_URL)과는 다른 채널·다른 주소다. 이 알림은 AWS 안에서 나가서 GitHub 비밀을 못 쓴다.
#
# 준비: envs/<env>/persistent apply가 끝나 비밀이 있어야 한다(README 4-16).
# 실행(infra 폴더, $env:AWS_PROFILE = "freshlink-admin"):
#   powershell -ExecutionPolicy Bypass -File .\scripts\set-dlq-webhook.ps1
#   powershell -ExecutionPolicy Bypass -File .\scripts\set-dlq-webhook.ps1 -Env prod
#   powershell -ExecutionPolicy Bypass -File .\scripts\set-dlq-webhook.ps1 -SkipTest   # 시험 메시지 없이 넣기만
param(
    [ValidateSet("dev", "prod")]
    [string]$Env = "dev",
    [switch]$SkipTest
)
$ErrorActionPreference = "Stop"

$secure = Read-Host "Discord 웹훅 주소 (https://discord.com/api/webhooks/로 시작, 입력해도 화면에 보이지 않는다)" -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $url = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr).Trim()
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}

if (-not ($url -match '^https://(discord\.com|discordapp\.com)/api/webhooks/\d+/[\w-]+$')) {
    throw "Discord 웹훅 주소 형식이 아니다. 채널 설정 → 연동 → 웹후크 → 웹후크 URL 복사 값을 그대로 넣는다."
}

$secretId = "freshlink-$Env-dlq-webhook"
$tmp = [System.IO.Path]::GetTempFileName()
try {
    $json = @{ url = $url } | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($tmp, $json)   # BOM 없이 저장 (aws CLI가 BOM을 값에 넣지 않게)
    aws secretsmanager put-secret-value --secret-id $secretId --secret-string "file://$tmp" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "put-secret-value 실패 ($secretId 가 있는지, persistent apply를 했는지 확인)" }
} finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
Write-Host "완료: $secretId 에 웹훅 주소를 넣었다."

if ($SkipTest) { exit 0 }

# 시험 메시지는 Lambda를 거치지 않고 이 PC에서 바로 보낸다(주소가 맞는지만 본다).
$body = @{ content = ":test_tube: [$Env] DLQ 알림 채널 연결 시험입니다. 이 메시지가 보이면 성공입니다." } | ConvertTo-Json -Compress
Invoke-RestMethod -Method Post -Uri $url -ContentType "application/json; charset=utf-8" `
    -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) | Out-Null
Write-Host "완료: Discord 채널에 시험 메시지를 보냈다. 채널에서 확인한다."
