# 기준 데이터(점포·상품)를 dev DB에서 prod DB로 복사한다 (할 일 15).
# mysqldump로 member.store, inventory.product의 행만 뜬 뒤(표는 prod 서비스 Flyway가 이미 만들었다) prod에 넣는다.
# 주문·재고(로트·입고·예약·폐기·원장)·회원은 옮기지 않는다.
# 점포의 점주(owner_member_id)는 dev Cognito 사용자라 prod에서는 맞지 않는다. 그래서 넣은 뒤
#   prod member에 없는 점주는 비우고 PENDING으로 돌린 다음, seed-db.ps1 -Env prod -Part member로
#   prod Cognito 점주 owner1~3을 점포 1~3에 다시 잇는다(seed-cognito.ps1 -Env prod를 먼저 돌린다).
# 여러 번 돌려도 된다. prod에 이미 있는 점포·상품(같은 id·코드)은 건드리지 않는다(INSERT IGNORE).
#
# 준비: 1) prod 서비스가 한 번 떠서 Flyway 표가 있어야 한다(첫 release 머지 → prod ArgoCD 동기화 뒤)
#       2) PowerShell 창 두 개에서 포트 포워딩을 열어 둔다(둘 다 'Waiting for connections...')
#            powershell -ExecutionPolicy Bypass -File .\scripts\db-port-forward.ps1 -Env dev -LocalPort 3307
#            powershell -ExecutionPolicy Bypass -File .\scripts\db-port-forward.ps1 -Env prod -LocalPort 3308
#       3) mysqldump.exe·mysql.exe (MySQL Server 8.x를 설치한 PC면 C:\Program Files\MySQL\MySQL Server 8.0\bin에 있다)
# 실행(infra 폴더, $env:AWS_PROFILE = "freshlink-admin"):
#   powershell -ExecutionPolicy Bypass -File .\scripts\copy-reference-data.ps1
param(
    [int]$DevPort = 3307,
    [int]$ProdPort = 3308,
    [string]$MySqlBin   # mysqldump.exe가 있는 폴더. 비우면 PATH와 C:\Program Files\MySQL\MySQL Server *\bin에서 찾는다
)
$ErrorActionPreference = "Stop"
# mysql 클라이언트는 UTF-8로 출력한다. PowerShell 5.1 기본(CP949)으로 읽으면 한글이 깨져 보인다
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 옮길 표. 순서대로 넣는다
$tables = @(
    @{ schema = "member"; table = "store" },
    @{ schema = "inventory"; table = "product" }
)

# 1) mysqldump·mysql 찾기
function Find-MySqlBin {
    if ($MySqlBin) { return $MySqlBin }
    $cmd = Get-Command mysqldump -ErrorAction SilentlyContinue
    if ($cmd) { return (Split-Path $cmd.Source -Parent) }
    $found = Get-ChildItem "C:\Program Files\MySQL\MySQL Server *\bin\mysqldump.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if ($found) { return $found.DirectoryName }
    throw "mysqldump.exe를 찾지 못했다. MySQL Server의 bin 폴더를 -MySqlBin 'C:\...\bin' 으로 넘긴다."
}
$bin = Find-MySqlBin
$mysqldump = Join-Path $bin "mysqldump.exe"
$mysql = Join-Path $bin "mysql.exe"
foreach ($exe in @($mysqldump, $mysql)) {
    if (-not (Test-Path $exe)) { throw "$exe 가 없다." }
}
Write-Host "MySQL 클라이언트: $bin"

# 2) 두 환경의 RDS 관리자 계정 (terraform output → Secrets Manager)
$root = Split-Path $PSScriptRoot -Parent
function Get-Master([string]$envName) {
    $tfDir = Join-Path $root "envs\$envName\persistent"
    $out = (terraform "-chdir=$tfDir" output -json | Out-String) | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $out.master_user_secret_arn) {
        throw "envs\$envName\persistent terraform output을 읽지 못했다. 그 폴더에서 init을 먼저 한다."
    }
    $raw = aws secretsmanager get-secret-value --secret-id $out.master_user_secret_arn.value --query SecretString --output text
    if ($LASTEXITCODE -ne 0) { throw "$envName RDS 관리자 비밀을 읽지 못했다." }
    return $raw | ConvertFrom-Json
}
$conn = @{
    dev  = @{ port = $DevPort; master = (Get-Master "dev") }
    prod = @{ port = $ProdPort; master = (Get-Master "prod") }
}
function Get-ConnArgs([string]$envName) {
    $c = $conn[$envName]
    return @("--host=127.0.0.1", "--port=$($c.port)", "--user=$($c.master.username)", "--password=$($c.master.password)",
        "--default-character-set=utf8mb4")
}

# exe를 부르고 출력·종료 코드를 돌려준다. 비밀번호 경고(stderr)에 멈추지 않게 한다
function Invoke-Exe([string]$exe, [string[]]$exeArgs) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $res = & $exe @exeArgs 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prev
    }
    $lines = @($res | ForEach-Object { "$_" } | Where-Object { $_ -notmatch "Using a password on the command line" })
    return [pscustomobject]@{ Code = $code; Lines = $lines }
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("freshlink-copy-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null

# SQL 문장을 파일로 써서 mysql로 실행한다(PowerShell 따옴표 문제를 피한다)
function Invoke-Sql([string]$envName, [string]$sqlText, [string]$what) {
    $file = Join-Path $work ("q-" + [guid]::NewGuid().ToString("N") + ".sql")
    [System.IO.File]::WriteAllText($file, $sqlText, (New-Object System.Text.UTF8Encoding $false))
    $r = Invoke-Exe $mysql ((Get-ConnArgs $envName) + @("--batch", "--execute=source $($file.Replace('\', '/'))"))
    if ($r.Code -ne 0) { throw ("$what 실패 ($envName). 포트 포워딩 창과 RDS가 켜져 있는지 확인한다.`n" + ($r.Lines -join "`n")) }
    return $r.Lines
}

try {
    # 3) prod에 표가 있는지 (prod 서비스 Flyway가 돌았는지)
    $inList = ($tables | ForEach-Object { "('$($_.schema)','$($_.table)')" }) -join ","
    $have = Invoke-Sql "prod" "SELECT CONCAT(table_schema, '.', table_name) FROM information_schema.tables WHERE (table_schema, table_name) IN ($inList);" "prod 표 확인"
    $missing = @($tables | Where-Object { $have -notcontains "$($_.schema).$($_.table)" } | ForEach-Object { "$($_.schema).$($_.table)" })
    if ($missing.Count -gt 0) {
        Write-Host "멈춤: prod에 표가 없다: $($missing -join ', ')" -ForegroundColor Yellow
        Write-Host "prod ArgoCD에서 member-service·inventory-service가 Healthy인지(Flyway가 돌았는지) 먼저 본다. 아무것도 넣지 않았다."
        exit 1
    }

    # 4) dev에서 행만 뜨기 (표 정의·트리거·잠금 없이, 같은 키가 있으면 건너뛰는 INSERT IGNORE)
    foreach ($t in $tables) {
        $file = Join-Path $work "$($t.schema).$($t.table).sql"
        $dumpArgs = (Get-ConnArgs "dev") + @(
            "--no-create-info", "--skip-triggers", "--complete-insert", "--insert-ignore",
            "--single-transaction", "--set-gtid-purged=OFF", "--no-tablespaces", "--skip-add-locks",
            "--column-statistics=0", "--result-file=$file", $t.schema, $t.table
        )
        $r = Invoke-Exe $mysqldump $dumpArgs
        if ($r.Code -ne 0) { throw ("dev $($t.schema).$($t.table) mysqldump 실패.`n" + ($r.Lines -join "`n")) }
        Write-Host "dev $($t.schema).$($t.table) 덤프 완료"
        $t.file = $file
    }

    # 5) prod에 넣기
    foreach ($t in $tables) {
        $r = Invoke-Exe $mysql ((Get-ConnArgs "prod") + @($t.schema, "--execute=source $($t.file.Replace('\', '/'))"))
        if ($r.Code -ne 0) { throw ("prod $($t.schema).$($t.table) 복원 실패.`n" + ($r.Lines -join "`n")) }
        Write-Host "prod $($t.schema).$($t.table) 복원 완료"
    }

    # 6) dev 점주(prod member에 없는 사용자)를 떼고 PENDING으로 (V1 제약: ACTIVE 점포는 점주가 있어야 한다)
    $fix = @"
SET time_zone = '+09:00';
UPDATE member.store s LEFT JOIN member.member m ON m.id = s.owner_member_id
SET s.owner_member_id = NULL, s.status = 'PENDING', s.updated_at = NOW(6)
WHERE s.owner_member_id IS NOT NULL AND m.id IS NULL;
SELECT ROW_COUNT() AS unlinked;
"@
    $lines = Invoke-Sql "prod" $fix "점주 떼기"
    Write-Host "dev 점주를 뗀 점포: $($lines[-1])"

    # 7) prod Cognito 점주 owner1~3을 점포 1~3에 잇는다
    Write-Host ""
    Write-Host "== seed-db.ps1 -Env prod -Part member (점주 연결)"
    $global:LASTEXITCODE = 0
    & (Join-Path $PSScriptRoot "seed-db.ps1") -Env prod -LocalPort $ProdPort -Part member
    if ($LASTEXITCODE -ne 0) { throw "점주 연결(seed-db.ps1)이 실패했다. seed-cognito.ps1 -Env prod를 먼저 돌렸는지 본다." }

    # 8) 두 환경 건수 비교
    $count = "SELECT (SELECT COUNT(*) FROM member.store) AS stores, (SELECT COUNT(*) FROM member.store WHERE status = 'ACTIVE') AS active_stores, (SELECT COUNT(*) FROM inventory.product) AS products;"
    Write-Host ""
    Write-Host "== dev"
    Invoke-Sql "dev" $count "건수" | ForEach-Object { Write-Host $_ }
    Write-Host "== prod"
    Invoke-Sql "prod" $count "건수" | ForEach-Object { Write-Host $_ }
} finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "완료: prod의 stores·products가 dev와 같고, 점포 1~3이 ACTIVE면 성공이다(dev에서 시험으로 만든 점포는 prod에서 PENDING일 수 있다)."
