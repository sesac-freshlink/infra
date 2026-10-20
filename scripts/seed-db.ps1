# dev 시드 ①③④: 점포 3개 → 점주 member 행(Cognito sub) → 점주 연결·ACTIVE, 상품 30개.
# 테이블은 각 서비스 Flyway(V1)가 만든다. 그 전에 돌리면 무엇이 없는지 알려 주고 아무것도 넣지 않는다.
# 여러 번 돌려도 된다.
#
# 준비: 1) seed-cognito.ps1을 먼저 돌린다(member 행에 넣을 sub가 필요하다)
#       2) 다른 PowerShell 창에서 scripts\db-port-forward.ps1이 'Waiting for connections...' 상태여야 한다
# 실행(infra 폴더, $env:AWS_PROFILE = "freshlink-admin"):
#   powershell -ExecutionPolicy Bypass -File .\scripts\seed-db.ps1                     # 둘 다
#   powershell -ExecutionPolicy Bypass -File .\scripts\seed-db.ps1 -Part inventory     # 상품만 (member V1이 아직 없을 때)
param(
    [string]$Env = "dev",
    [int]$LocalPort = 3306,
    [ValidateSet("all", "member", "inventory")]
    [string]$Part = "all"
)
$ErrorActionPreference = "Stop"
# mysqlsh는 UTF-8로 출력한다. PowerShell 5.1 기본(CP949)으로 읽으면 결과 표의 한글이 깨져 보인다
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if (-not (Get-Command mysqlsh -ErrorAction SilentlyContinue)) {
    throw "mysqlsh가 없다. 'winget install --id Oracle.MySQLShell -e --source winget' 뒤 PowerShell 창을 새로 연다."
}

# 시드 SQL이 쓰는 칼럼. 표에 이 칼럼이 없거나, 이 밖의 NOT NULL·기본값 없는 칼럼이 있으면 멈춘다(V1과 어긋남)
$expected = [ordered]@{
    "member.store"      = @("id", "store_code", "name", "address", "region", "status", "owner_member_id", "created_at", "updated_at")
    "member.member"     = @("id", "role", "email", "created_at", "updated_at")
    "inventory.product" = @("id", "product_code", "name", "category", "price")
}
$files = [ordered]@{
    member    = @{ tables = @("member.store", "member.member"); sql = "dev-member.sql" }
    inventory = @{ tables = @("inventory.product"); sql = "dev-inventory.sql" }
}
$parts = if ($Part -eq "all") { @("member", "inventory") } else { @($Part) }

$tfDir = Join-Path (Split-Path $PSScriptRoot -Parent) "envs\$Env\persistent"
$out = (terraform "-chdir=$tfDir" output -json | Out-String) | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw "terraform output을 읽지 못했다. infra 폴더에서 init·apply를 먼저 한다." }

function Get-SecretString([string]$id) {
    $raw = aws secretsmanager get-secret-value --secret-id $id --query SecretString --output text
    if ($LASTEXITCODE -ne 0) { throw "비밀 $id 를 읽지 못했다." }
    return $raw
}

$master = (Get-SecretString $out.master_user_secret_arn.value) | ConvertFrom-Json
$mysqlArgs = @("--sql", "--host=127.0.0.1", "--port=$LocalPort", "--user=$($master.username)", "--password=$($master.password)")

function Invoke-MySql([string]$sqlText, [string[]]$extra) {
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($tmp, $sqlText, (New-Object System.Text.UTF8Encoding $false))
        $prev = $ErrorActionPreference
        $ErrorActionPreference = "Continue"   # mysqlsh 경고(stderr)에 멈추지 않게
        try {
            $res = & mysqlsh @mysqlArgs @extra "--file=$tmp" 2>&1
            $code = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $prev
        }
        $lines = @($res | ForEach-Object { "$_" } | Where-Object { $_ -notmatch "Using a password on the command line" })
        if ($code -ne 0) { throw ("SQL 실행 실패. 포트 포워딩 창과 RDS가 켜져 있는지 확인한다.`n" + ($lines -join "`n")) }
        return $lines
    } finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}

# 1) 표·칼럼 확인 (Flyway V1이 dev에 돌았는지, 칼럼 이름이 시드와 같은지)
$tables = @($parts | ForEach-Object { $files[$_].tables })
$inList = ($tables | ForEach-Object { $s, $t = $_.Split("."); "('$s','$t')" }) -join ","
$check = @"
SELECT CONCAT(table_schema, '.', table_name, '|', column_name, '|',
  IF(is_nullable = 'NO' AND column_default IS NULL AND extra NOT LIKE '%auto_increment%', 'required', 'optional'))
FROM information_schema.columns WHERE (table_schema, table_name) IN ($inList);
"@
$rows = Invoke-MySql $check @("--result-format=tabbed")
$columns = @{}
foreach ($line in $rows) {
    if ($line -notmatch "^([a-z_]+\.[a-z_]+)\|([a-z_0-9]+)\|(required|optional)$") { continue }
    if (-not $columns.ContainsKey($Matches[1])) { $columns[$Matches[1]] = @{} }
    $columns[$Matches[1]][$Matches[2]] = $Matches[3]
}

$problems = @()
foreach ($t in $tables) {
    if (-not $columns.ContainsKey($t)) {
        $problems += "표 $t 가 없다 (그 서비스 Flyway V1이 dev DB에 아직 안 돌았다)"
        continue
    }
    foreach ($c in $expected[$t]) {
        if (-not $columns[$t].ContainsKey($c)) { $problems += "$t 에 칼럼 $c 가 없다" }
    }
    foreach ($c in $columns[$t].Keys) {
        if ($columns[$t][$c] -eq "required" -and $expected[$t] -notcontains $c) {
            $problems += "$t.$c 는 NOT NULL·기본값 없음인데 시드가 넣지 않는다"
        }
    }
}
if ($problems.Count -gt 0) {
    Write-Host "멈춤: 시드 SQL과 dev DB 표가 맞지 않아 아무것도 넣지 않았다." -ForegroundColor Yellow
    $problems | ForEach-Object { Write-Host " - $_" }
    Write-Host "이 목록을 스레드에 붙여 넣는다. 한쪽 표만 준비됐으면 -Part member 또는 -Part inventory 로 그쪽만 넣을 수 있다."
    exit 1
}

# 2) 시드 SQL 실행
$seedDir = Join-Path $PSScriptRoot "seed"
foreach ($p in $parts) {
    $sql = Get-Content -Raw -Encoding UTF8 (Join-Path $seedDir $files[$p].sql)
    if ($p -eq "member") {
        $raw = Get-SecretString $out.seed_accounts_secret_name.value
        # PowerShell 5.1의 ConvertFrom-Json은 JSON 배열을 한 덩어리로 내보낸다. ForEach-Object로 풀어야 계정 하나씩 고를 수 있다
        $accounts = @($raw | ConvertFrom-Json | ForEach-Object { $_ })
        foreach ($n in 1..3) {
            $a = $accounts | Where-Object { $_.storeId -eq "$n" } | Select-Object -First 1
            if (-not $a -or -not ($a.sub -is [string]) -or $a.sub -notmatch "^[0-9a-f-]{36}$") {
                throw "점주 $n (storeId $n) 계정의 sub가 비밀에 없다. seed-cognito.ps1을 먼저 돌린다."
            }
            $sql = $sql.Replace("{{OWNER${n}_SUB}}", $a.sub).Replace("{{OWNER${n}_EMAIL}}", $a.email)
        }
    }
    Write-Host "== $($files[$p].sql)"
    Invoke-MySql $sql @("--result-format=table") | ForEach-Object { Write-Host $_ }
}

Write-Host ""
Write-Host "완료: member는 점포 1~3이 S1~S3·ACTIVE·점주 이메일과 함께, inventory는 product_count 30이 보이면 성공이다."
