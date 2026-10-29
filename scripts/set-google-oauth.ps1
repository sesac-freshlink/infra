# 구글 OAuth 클라이언트 ID·시크릿을 Secrets Manager(freshlink-<env>-google-oauth)에 넣는다.
# Terraform(envs/<env>/persistent의 Cognito 구글 IdP)이 이 비밀을 읽는다. 비밀이 있을 때 persistent apply를 하면 구글 IdP가 생긴다(README 4-17).
# 값은 Terraform 코드·레포·화면 기록에 남지 않는다(시크릿은 입력할 때 화면에 보이지 않는다).
#   Secrets Manager  freshlink-<env>-google-oauth  JSON clientId·clientSecret
# 비밀이 없으면 만들고, 있으면 값만 바꾼다. 값을 바꾼 뒤에는 persistent apply를 다시 해야 Cognito에 들어간다.
#
# 실행(infra 폴더, $env:AWS_PROFILE = "freshlink-admin"):
#   powershell -ExecutionPolicy Bypass -File .\scripts\set-google-oauth.ps1
#   powershell -ExecutionPolicy Bypass -File .\scripts\set-google-oauth.ps1 -Env prod
param(
    [ValidateSet("dev", "prod")]
    [string]$Env = "dev"
)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$clientId = (Read-Host "구글 클라이언트 ID (...apps.googleusercontent.com)").Trim()
if (-not ($clientId -match '^[0-9]+-[0-9a-z]+\.apps\.googleusercontent\.com$')) {
    throw "구글 클라이언트 ID 형식이 아니다. Google Auth Platform → 클라이언트 → 이 환경 클라이언트의 '클라이언트 ID'를 그대로 넣는다."
}

$secure = Read-Host "구글 클라이언트 보안 비밀번호 (GOCSPX-로 시작, 입력해도 화면에 보이지 않는다)" -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $clientSecret = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr).Trim()
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}
if ($clientSecret.Length -lt 20) {
    throw "보안 비밀번호가 너무 짧다. 클라이언트를 만들 때 받은 값(GOCSPX-...)을 그대로 넣는다."
}

$secretId = "freshlink-$Env-google-oauth"
$tmp = [System.IO.Path]::GetTempFileName()
try {
    $json = @{ clientId = $clientId; clientSecret = $clientSecret } | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($tmp, $json)   # BOM 없이 저장 (aws CLI가 BOM을 값에 넣지 않게)

    # 없으면 만들고, 있으면 값만 바꾼다
    # PowerShell 5.1은 Stop일 때 aws의 stderr(ResourceNotFound)를 오류로 멈춘다. 이 줄만 Continue로 부른다
    $ErrorActionPreference = "Continue"
    $null = aws secretsmanager describe-secret --secret-id $secretId 2>$null
    $exists = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = "Stop"
    if ($exists) {
        aws secretsmanager put-secret-value --secret-id $secretId --secret-string "file://$tmp" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "put-secret-value 실패 ($secretId)" }
        Write-Host "완료: $secretId 값을 바꿨다. persistent apply를 다시 해야 Cognito 구글 IdP에 들어간다."
    } else {
        aws secretsmanager create-secret --name $secretId `
            --description "Google OAuth client for Cognito freshlink-$Env-users (clientId, clientSecret). infra scripts/set-google-oauth.ps1" `
            --tags "Key=Project,Value=freshlink" "Key=Environment,Value=$Env" "Key=ManagedBy,Value=script" `
            --secret-string "file://$tmp" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "create-secret 실패 ($secretId). 프로필이 freshlink-admin인지 확인한다" }
        Write-Host "완료: $secretId 를 만들었다. 이제 envs/$Env/persistent apply를 하면 구글 IdP가 생긴다."
    }
} finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
