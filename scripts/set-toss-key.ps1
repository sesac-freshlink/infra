# 토스페이먼츠 테스트 키를 Secrets Manager(freshlink-<env>-toss)에 넣고, 클라이언트 키를 frontend 레포 Variable에도 넣는다.
# 값은 Terraform·레포·화면 기록에 남지 않는다(시크릿 키는 입력할 때 화면에 보이지 않는다).
#   Secrets Manager  freshlink-<env>-toss  JSON clientKey·secretKey  → order-service 파드 TOSS_SECRET_KEY (gitops toss.secretName)
#   frontend Variable <ENV>_TOSS_CLIENT_KEY  클라이언트 키(공개돼도 되는 값)  → 프론트 빌드 VITE_TOSS_CLIENT_KEY
# 결제위젯 키(test_gck_·test_gsk_)와 API 개별 연동 키(test_ck_·test_sk_) 둘 다 받는다. 두 종류를 섞으면 토스가 INVALID_API_KEY로 거절하므로 막는다.
#
# 준비: gh auth login 이 되어 있어야 Variable까지 넣는다(없으면 Secrets Manager만 넣고 안내한다).
# 실행(infra 폴더, $env:AWS_PROFILE = "freshlink-admin"):
#   powershell -ExecutionPolicy Bypass -File .\scripts\set-toss-key.ps1
#   powershell -ExecutionPolicy Bypass -File .\scripts\set-toss-key.ps1 -Env prod
param(
    [ValidateSet("dev", "prod")]
    [string]$Env = "dev",
    [string]$Org = "sesac-freshlink"
)
$ErrorActionPreference = "Stop"

$clientKey = (Read-Host "클라이언트 키 (test_gck_ 또는 test_ck_로 시작)").Trim()
$secure = Read-Host "시크릿 키 (test_gsk_ 또는 test_sk_로 시작, 입력해도 화면에 보이지 않는다)" -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $secretKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr).Trim()
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}

if (-not $clientKey.StartsWith("test_") -or -not $secretKey.StartsWith("test_")) {
    throw "테스트 키(test_로 시작)만 넣는다."
}
$widget = $clientKey.StartsWith("test_gck_") -and $secretKey.StartsWith("test_gsk_")
$api = $clientKey.StartsWith("test_ck_") -and $secretKey.StartsWith("test_sk_")
if (-not ($widget -or $api)) {
    throw "키 쌍이 맞지 않는다. 클라이언트 키 칸에 gck(또는 ck), 시크릿 키 칸에 gsk(또는 sk)를 같은 종류로 넣는다."
}

$tmp = [System.IO.Path]::GetTempFileName()
try {
    $json = @{ clientKey = $clientKey; secretKey = $secretKey } | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($tmp, $json)   # BOM 없이 저장 (aws CLI가 BOM을 값에 넣지 않게)
    aws secretsmanager put-secret-value --secret-id "freshlink-$Env-toss" --secret-string "file://$tmp" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "put-secret-value 실패" }
} finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
Write-Host "완료: freshlink-$Env-toss 에 테스트 키를 넣었다."

$varName = "$($Env.ToUpper())_TOSS_CLIENT_KEY"
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Warning "gh가 없어 frontend Variable $varName 은 넣지 못했다. gh 설치·로그인 뒤 이 스크립트를 다시 돌린다(같은 값으로 덮어쓴다)."
    exit 0
}
& gh variable set $varName --repo "$Org/frontend" --body $clientKey
if ($LASTEXITCODE -ne 0) { throw "gh variable set $varName 실패 (gh auth login 확인)" }
Write-Host "완료: $Org/frontend Variable $varName 을 넣었다. 다음 프론트 배포부터 결제위젯이 이 키를 쓴다."
