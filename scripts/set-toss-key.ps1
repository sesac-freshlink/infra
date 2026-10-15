# 토스페이먼츠 테스트 키를 Secrets Manager(freshlink-<env>-toss)에 넣는다. 값은 Terraform·레포에 남지 않는다.
# 실행(infra 폴더, $env:AWS_PROFILE = "freshlink-admin"):
#   powershell -ExecutionPolicy Bypass -File .\scripts\set-toss-key.ps1
param([string]$Env = "dev")
$ErrorActionPreference = "Stop"

$clientKey = Read-Host "클라이언트 키 (test_ck_로 시작)"
$secretKey = Read-Host "시크릿 키 (test_sk_로 시작)"
if (-not $clientKey.StartsWith("test_") -or -not $secretKey.StartsWith("test_")) {
    throw "테스트 키(test_로 시작)만 넣는다."
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
