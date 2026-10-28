# 시드 ②: Cognito 관리자 1·점주 3 계정을 만들고 자격(이메일·비밀번호·sub·storeId)을 Secrets Manager에 넣는다.
# 이메일 인증 완료·영구 비밀번호로 만든다(member M5·M6). 메일은 보내지 않는다(--message-action SUPPRESS).
# 여러 번 돌려도 된다. 이미 있는 계정은 비밀번호·그룹·storeId만 비밀 값에 맞춘다.
#
# 준비: envs/<env>/persistent apply가 끝나 있어야 한다. RDS·포트 포워딩은 필요 없다.
# 실행(infra 폴더, $env:AWS_PROFILE = "freshlink-admin"):
#   powershell -ExecutionPolicy Bypass -File .\scripts\seed-cognito.ps1
#   powershell -ExecutionPolicy Bypass -File .\scripts\seed-cognito.ps1 -Env prod   # prod 시연 계정 (점주 yeoksam·hapjeong·seongsu)
param(
    [string]$Env = "dev",
    [string]$EmailDomain = "freshlink.test"   # 예약 도메인(.test). 메일을 보내지 않으므로 받을 수 없어도 된다
)
$ErrorActionPreference = "Stop"

# aws CLI를 부르고 표준 출력·오류·종료 코드를 따로 돌려준다(Windows PowerShell은 stderr를 오류로 바꿔 멈추기 때문)
function Invoke-Aws([string[]]$AwsArgs) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $all = & aws @AwsArgs 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prev
    }
    $out = ($all | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" }) -join "`n"
    $err = ($all | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" }) -join "`n"
    return [pscustomobject]@{ Code = $code; Out = $out; Err = $err }
}

function Assert-Aws($r, [string]$what) {
    if ($r.Code -ne 0) { throw "$what 실패: $($r.Err)" }
}

# 비밀번호 규칙(8자 이상, 대·소문자·숫자·특수문자)을 넘는 16자. PowerShell·CLI 인자에서 문제없는 특수문자만 쓴다
function New-SeedPassword {
    $upper = "ABCDEFGHJKLMNPQRSTUVWXYZ".ToCharArray()
    $lower = "abcdefghijkmnopqrstuvwxyz".ToCharArray()
    $digit = "23456789".ToCharArray()
    $symbol = "!@#%^*-_=+".ToCharArray()
    $all = $upper + $lower + $digit + $symbol
    $chars = @(
        (Get-Random -InputObject $upper), (Get-Random -InputObject $lower),
        (Get-Random -InputObject $digit), (Get-Random -InputObject $symbol)
    )
    $chars += 1..12 | ForEach-Object { Get-Random -InputObject $all }
    return -join ($chars | Sort-Object { Get-Random })
}

$tfDir = Join-Path (Split-Path $PSScriptRoot -Parent) "envs\$Env\persistent"
$out = (terraform "-chdir=$tfDir" output -json | Out-String) | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $out.cognito_user_pool_id) {
    throw "terraform output에 cognito_user_pool_id가 없다. envs\$Env\persistent init·apply를 먼저 한다."
}
$poolId = $out.cognito_user_pool_id.value
$secretName = $out.seed_accounts_secret_name.value

# 이전에 넣은 비밀 값이 있으면 비밀번호를 그대로 쓴다(다시 돌려도 비밀번호가 바뀌지 않게)
$previous = @{}
$r = Invoke-Aws @("secretsmanager", "get-secret-value", "--secret-id", $secretName, "--query", "SecretString", "--output", "text")
if ($r.Code -eq 0 -and $r.Out) {
    foreach ($a in ($r.Out | ConvertFrom-Json)) { $previous[$a.email] = $a.password }
}

# 점주 이메일 앞부분. prod는 dev 값을 쓰지 않고 시연 화면에 보이는 점포 이름(scripts\seed\prod-member.sql)에 맞춘다
$ownerNames = if ($Env -eq "prod") { @("yeoksam", "hapjeong", "seongsu") } else { @("owner1", "owner2", "owner3") }
$accounts = @(
    [pscustomobject]@{ key = "admin";  email = "admin@$EmailDomain";  group = "ADMIN"; storeId = $null }
    [pscustomobject]@{ key = "owner1"; email = "$($ownerNames[0])@$EmailDomain"; group = "OWNER"; storeId = "1" }
    [pscustomobject]@{ key = "owner2"; email = "$($ownerNames[1])@$EmailDomain"; group = "OWNER"; storeId = "2" }
    [pscustomobject]@{ key = "owner3"; email = "$($ownerNames[2])@$EmailDomain"; group = "OWNER"; storeId = "3" }
)

$result = @()
foreach ($a in $accounts) {
    $password = $previous[$a.email]
    if (-not $password) { $password = New-SeedPassword }

    $attrs = @("Name=email,Value=$($a.email)", "Name=email_verified,Value=true")
    if ($a.storeId) { $attrs += "Name=custom:storeId,Value=$($a.storeId)" }

    $get = Invoke-Aws @("cognito-idp", "admin-get-user", "--user-pool-id", $poolId, "--username", $a.email)
    if ($get.Code -ne 0) {
        if ($get.Err -notmatch "UserNotFoundException") { throw "admin-get-user 실패: $($get.Err)" }
        $c = Invoke-Aws (@("cognito-idp", "admin-create-user", "--user-pool-id", $poolId, "--username", $a.email,
                "--message-action", "SUPPRESS", "--user-attributes") + $attrs)
        Assert-Aws $c "$($a.email) 계정 만들기"
        Write-Host "만듦: $($a.email)"
    } else {
        $u = Invoke-Aws (@("cognito-idp", "admin-update-user-attributes", "--user-pool-id", $poolId, "--username", $a.email,
                "--user-attributes") + $attrs)
        Assert-Aws $u "$($a.email) 속성 맞추기"
        Write-Host "있음: $($a.email) (속성·비밀번호·그룹만 맞춘다)"
    }

    $p = Invoke-Aws @("cognito-idp", "admin-set-user-password", "--user-pool-id", $poolId, "--username", $a.email,
        "--password", $password, "--permanent")
    Assert-Aws $p "$($a.email) 영구 비밀번호"

    $g = Invoke-Aws @("cognito-idp", "admin-add-user-to-group", "--user-pool-id", $poolId, "--username", $a.email,
        "--group-name", $a.group)
    Assert-Aws $g "$($a.email) 그룹 $($a.group)"

    $s = Invoke-Aws @("cognito-idp", "admin-get-user", "--user-pool-id", $poolId, "--username", $a.email,
        "--query", "UserAttributes[?Name=='sub'].Value | [0]", "--output", "text")
    Assert-Aws $s "$($a.email) sub 읽기"

    $result += [pscustomobject]@{
        key      = $a.key
        email    = $a.email
        password = $password
        group    = $a.group
        storeId  = $a.storeId
        sub      = $s.Out.Trim()
    }
}

$tmp = [System.IO.Path]::GetTempFileName()
try {
    $json = ConvertTo-Json -InputObject @($result) -Compress
    [System.IO.File]::WriteAllText($tmp, $json)   # BOM 없이 저장 (aws CLI가 BOM을 값에 넣지 않게)
    $w = Invoke-Aws @("secretsmanager", "put-secret-value", "--secret-id", $secretName, "--secret-string", "file://$tmp")
    Assert-Aws $w "비밀 $secretName 저장"
} finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}

$result | Select-Object email, group, storeId, sub | Format-Table -AutoSize | Out-String | Write-Host
Write-Host "완료: 위에 계정 4줄(ADMIN 1, OWNER 3)과 sub가 보이면 성공이다. 비밀번호는 비밀 $secretName 에 있다."
