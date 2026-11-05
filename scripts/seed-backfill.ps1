# 시드 ⑤ (3차 할 일 1-4): 지난 N일(기본 30일) 데모 기록을 **한 번만** 채운다. 그 뒤로는 logistics-simulator 매일 시나리오가 쌓는다.
# 판매 순위·통계·추천순·소진 예상은 inventory 원장(ledger) 판매 기록으로 계산하므로 order와 inventory를 같은 주문 ID로 같이 넣는다.
#   inventory: inbound(SHP-<날짜>-AM-S<점포>) → inventory_lot(기한은 지난 날짜, 남은 수량 0, EXPIRED) → ledger INBOUND·SALE·DISPOSE
#   orders:    orders(PICKED_UP, 결제·픽업 시각은 과거) → payment(SIM-BF-…, 토스 없음) → order_lot
# lot마다 SUM(ledger.quantity) = inventory_lot.quantity(0)이 맞고, 지난 주문은 모두 픽업 완료라 취소·환불이 되지 않는다.
# 점포 이름·상품 이름·가격은 DB(member.store, inventory.product)에서 읽는다. 고객은 seed-accounts 비밀의 CUSTOMER(단골 점포)다.
#
# 준비: 1) seed-cognito.ps1 → seed-db.ps1을 먼저 돌린다(점포·상품·고객 member 행)
#       2) 다른 PowerShell 창에서 scripts\db-port-forward.ps1 -Env prod -LocalPort 3308 이 'Waiting for connections...' 상태
# 실행(infra 폴더, $env:AWS_PROFILE = "freshlink-admin"):
#   powershell -ExecutionPolicy Bypass -File .\scripts\seed-backfill.ps1 -Env prod -LocalPort 3308
#   ... -DryRun   # DB에 넣지 않고 만들 SQL만 scripts\seed\backfill-<env>.sql로 저장한다(확인용, 커밋하지 않는다)
# 이미 채웠으면(SIM-BF- 결제가 있으면) 아무것도 하지 않고 멈춘다.
param(
    [string]$Env = "prod",
    [int]$LocalPort = 3308,
    [int]$Days = 30,
    [switch]$DryRun,
    # 시험용: AWS 없이 고객 목록(seed-accounts 비밀과 같은 JSON)과 기준 날짜로 SQL만 만든다
    [string]$AccountsFile = "",
    [string]$Today = ""
)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 상품 ID 1–30 = P001–P030 (scripts\seed\<env>-inventory.sql). 분류별 유통기한 일수는 logistics-simulator Catalog와 같다
$categories = @("도시락","도시락","도시락","김밥","김밥","김밥","샌드위치","샌드위치","샌드위치","샐러드","샐러드",
    "유제품","유제품","유제품","라면","라면","빵","빵","빵","디저트","디저트","과일","과일","음료","음료",
    "신선식품","신선식품","신선식품","즉석식품","즉석식품")
function Get-ShelfDays([string]$c) {
    switch ($c) {
        { $_ -in "도시락","김밥","샌드위치","샐러드" } { return @(0, 1) }
        { $_ -in "유제품","디저트" } { return @(3, 10) }
        "빵" { return @(2, 4) }
        { $_ -in "과일","신선식품" } { return @(3, 7) }
        "음료" { return @(30, 90) }
        default { return @(90, 180) }
    }
}

$offline = [bool]$AccountsFile
if (-not $offline) {
    if (-not (Get-Command mysqlsh -ErrorAction SilentlyContinue)) {
        throw "mysqlsh가 없다. 'winget install --id Oracle.MySQLShell -e --source winget' 뒤 PowerShell 창을 새로 연다."
    }
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
    $accountsJson = Get-SecretString $out.seed_accounts_secret_name.value
} else {
    $accountsJson = Get-Content -Raw -Encoding UTF8 $AccountsFile
}

function Invoke-MySql([string]$sqlText, [string]$format = "tabbed") {
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($tmp, $sqlText, (New-Object System.Text.UTF8Encoding $false))
        $prev = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $res = & mysqlsh @mysqlArgs "--result-format=$format" "--file=$tmp" 2>&1
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

# 고객과 단골 점포
$customers = @($accountsJson | ConvertFrom-Json | ForEach-Object { $_ } | Where-Object { $_.group -eq "CUSTOMER" -and $_.sub })
if ($customers.Count -eq 0) { throw "seed-accounts 비밀에 고객이 없다. seed-cognito.ps1을 먼저 돌린다." }
$regulars = @{}
foreach ($c in $customers) {
    foreach ($s in @($c.stores)) {
        $k = [int64]$s
        if (-not $regulars.ContainsKey($k)) { $regulars[$k] = New-Object System.Collections.ArrayList }
        [void]$regulars[$k].Add($c.sub)
    }
}
$stores = @($regulars.Keys | Sort-Object)

# 이미 채웠는지, 이미 있는 lot(점포·상품·기한)은 무엇인지 (유일 키가 겹치지 않게 피한다)
$used = New-Object 'System.Collections.Generic.HashSet[string]'
if (-not $offline) {
    $done = Invoke-MySql "SELECT CONCAT('BF|', COUNT(*)) FROM orders.payment WHERE payment_key LIKE 'SIM-BF-%';"
    $n = ($done | Where-Object { $_ -match "^BF\|(\d+)$" } | ForEach-Object { [int]$Matches[1] } | Select-Object -First 1)
    if ($n -gt 0) {
        Write-Host "멈춤: 이미 지난 기록을 채웠다(SIM-BF- 결제 $n 건). 다시 넣지 않는다." -ForegroundColor Yellow
        exit 0
    }
    $lots = Invoke-MySql "SELECT CONCAT('LOT|', store_id, '|', product_id, '|', DATE_FORMAT(expiry_date, '%Y-%m-%d')) FROM inventory.inventory_lot;"
    foreach ($l in $lots) { if ($l -match "^LOT\|(.+)$") { [void]$used.Add($Matches[1]) } }
}

$baseDay = if ($Today) { [datetime]::ParseExact($Today, "yyyy-MM-dd", $null) } else { [datetime]::Today }
$rnd = New-Object System.Random 20261105
# 시각 고르기: 10:00–20:00, 점심 11:30–13:30·저녁 17:30–19:30은 두 배
$minutes = New-Object System.Collections.ArrayList
for ($m = 600; $m -lt 1200; $m++) {
    [void]$minutes.Add($m)
    if (($m -ge 690 -and $m -lt 810) -or ($m -ge 1050 -and $m -lt 1170)) { [void]$minutes.Add($m) }
}
function Fmt([datetime]$t) { $t.ToString("yyyy-MM-dd HH:mm:ss.ffffff", [Globalization.CultureInfo]::InvariantCulture) }

$lotRows = New-Object System.Collections.ArrayList
$orderRows = New-Object System.Collections.ArrayList
for ($d = $Days; $d -ge 1; $d--) {
    $day = $baseDay.AddDays(-$d)
    $ymd = $day.ToString("yyyyMMdd")
    foreach ($store in $stores) {
        $received = $day.AddHours(9).AddMinutes(20)
        # 그날 들어온 상품 3–6개 (폐기율이 너무 높지 않게 판매량에 맞춘다)
        $pool = @(1..30 | Sort-Object { $rnd.Next() })
        $picked = @($pool[0..(2 + $rnd.Next(4))])
        $sold = @{}
        foreach ($p in $picked) { $sold[$p] = 0 }
        # 그날 주문 3–6건 (단골 고객, 들어온 상품 1개, 1–3개)
        $orders = New-Object System.Collections.ArrayList
        $count = 3 + $rnd.Next(4)
        for ($i = 0; $i -lt $count; $i++) {
            $sub = $regulars[[int64]$store][$rnd.Next($regulars[[int64]$store].Count)]
            $p = $picked[$rnd.Next($picked.Count)]
            $q = 1 + $rnd.Next(3)
            $sold[$p] += $q
            $paid = $day.AddMinutes($minutes[$rnd.Next($minutes.Count)]).AddSeconds($rnd.Next(60))
            [void]$orders.Add(@{ sub = $sub; product = $p; qty = $q; paid = $paid; pickup = $paid.AddMinutes(15 + $rnd.Next(46)) })
        }
        foreach ($p in $picked) {
            # 기한: 그날 + 분류별 며칠, 단 오늘보다 앞(d-1일까지). 이미 있는 (점포, 상품, 기한)이면 하루씩 당긴다
            $range = Get-ShelfDays $categories[$p - 1]
            $k = [Math]::Min($range[0] + $rnd.Next($range[1] - $range[0] + 1), $d - 1)
            $expiry = $null
            $tries = @($k..0)
            if ($k + 1 -le $d - 1) { $tries += @(($k + 1)..($d - 1)) }
            foreach ($try in $tries) {
                $key = "$store|$p|$($day.AddDays($try).ToString('yyyy-MM-dd'))"
                if ($used.Add($key)) { $expiry = $day.AddDays($try); break }
            }
            if (-not $expiry) {
                # 기한을 정할 수 없으면 그 상품 주문을 빼고 lot도 넣지 않는다
                foreach ($o in @($orders | Where-Object { $_.product -eq $p })) { $orders.Remove($o) }
                continue
            }
            $expiryAt = $expiry.AddHours(23).AddMinutes(59).AddSeconds(59)
            $inbound = if ($sold[$p] -gt 0) { $sold[$p] + $rnd.Next(2) } else { 1 + $rnd.Next(2) }   # 남는 것 0–1개, 안 팔린 상품 1–2개는 폐기
            $disposeAt = $expiry.AddDays(1).AddMinutes(10)
            [void]$lotRows.Add("($store, $p, '$(Fmt $expiryAt)', $inbound, $($sold[$p]), $($inbound - $sold[$p]), 'SHP-$ymd-AM-S$store', '$(Fmt $received)', '$(Fmt $disposeAt)')")
            foreach ($o in @($orders | Where-Object { $_.product -eq $p })) {
                $o.expiry = $expiryAt
                if ($o.pickup -gt $expiryAt) { $o.pickup = $expiryAt.AddMinutes(-1) }
            }
        }
        foreach ($o in $orders) {
            $req = [guid]::NewGuid().ToString()
            $created = $o.paid.AddSeconds(-70)
            [void]$orderRows.Add("('$req', '$($o.sub)', $store, $($o.product), $($o.qty), '$(Fmt $created)', '$(Fmt $created.AddSeconds(5))', '$(Fmt $o.paid)', '$(Fmt $o.expiry)', '$(Fmt $o.pickup)')")
        }
    }
}

function Join-Chunks([System.Collections.ArrayList]$rows, [string]$head) {
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $rows.Count; $i += 500) {
        $chunk = $rows.GetRange($i, [Math]::Min(500, $rows.Count - $i))
        [void]$sb.AppendLine("$head VALUES")
        [void]$sb.AppendLine(($chunk -join ",`n") + ";")
    }
    return $sb.ToString()
}

$sql = @"
-- seed-backfill.ps1이 만든 SQL ($Env, $($baseDay.AddDays(-$Days).ToString('yyyy-MM-dd')) ~ $($baseDay.AddDays(-1).ToString('yyyy-MM-dd'))). 커밋하지 않는다.
SET NAMES utf8mb4;
SET time_zone = '+09:00';
START TRANSACTION;

CREATE TEMPORARY TABLE inventory.bf_lot (
  store_id BIGINT, product_id BIGINT, expiry_date DATETIME, inbound_qty INT, sold_qty INT, dispose_qty INT,
  shipment_id VARCHAR(64), received_at DATETIME(3), dispose_at DATETIME(3));
$(Join-Chunks $lotRows "INSERT INTO inventory.bf_lot (store_id, product_id, expiry_date, inbound_qty, sold_qty, dispose_qty, shipment_id, received_at, dispose_at)")
CREATE TEMPORARY TABLE orders.bf_order (
  request_id VARCHAR(36), customer_id VARCHAR(36), store_id BIGINT, product_id BIGINT, quantity INT,
  created_at DATETIME(6), waiting_at DATETIME(6), paid_at DATETIME(6), expiry_at DATETIME(6), picked_up_at DATETIME(6)
) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci; -- orders.orders와 같은 정렬 규칙(문자열 JOIN)
$(Join-Chunks $orderRows "INSERT INTO orders.bf_order (request_id, customer_id, store_id, product_id, quantity, created_at, waiting_at, paid_at, expiry_at, picked_up_at)")

-- inventory: 입고 기록 → lot(남은 0, EXPIRED) → 원장 INBOUND·DISPOSE
INSERT IGNORE INTO inventory.inbound (shipment_id, store_id, received_at)
SELECT shipment_id, store_id, MIN(received_at) FROM inventory.bf_lot GROUP BY shipment_id, store_id;
INSERT INTO inventory.inventory_lot (store_id, product_id, expiry_date, quantity, reserved_quantity, status, created_at, updated_at, version)
SELECT store_id, product_id, expiry_date, 0, 0, 'EXPIRED', received_at, dispose_at, 0 FROM inventory.bf_lot;
INSERT INTO inventory.ledger (store_id, lot_id, type, quantity, ref_id, created_at)
SELECT l.store_id, l.id, 'INBOUND', b.inbound_qty, b.shipment_id, b.received_at
FROM inventory.bf_lot b JOIN inventory.inventory_lot l
  ON l.store_id = b.store_id AND l.product_id = b.product_id AND l.expiry_date = b.expiry_date;
INSERT INTO inventory.ledger (store_id, lot_id, type, quantity, ref_id, created_at)
SELECT l.store_id, l.id, 'DISPOSE', -b.dispose_qty, 'BACKFILL', b.dispose_at
FROM inventory.bf_lot b JOIN inventory.inventory_lot l
  ON l.store_id = b.store_id AND l.product_id = b.product_id AND l.expiry_date = b.expiry_date
WHERE b.dispose_qty > 0;

-- orders: 주문(픽업 완료) → 주문번호 → 결제(SIM-BF-) → 주문 lot. 점포 이름·상품 이름·가격은 DB 값
INSERT INTO orders.orders (customer_id, request_id, store_id, store_name, product_id, product_name, quantity, unit_price, amount,
  status, payment_waiting_at, payment_expires_at, paid_at, pickup_deadline, picked_up_at, refund_status, created_at, updated_at)
SELECT b.customer_id, b.request_id, b.store_id, s.name, b.product_id, p.name, b.quantity, p.price, p.price * b.quantity,
  'PICKED_UP', b.waiting_at, DATE_ADD(b.waiting_at, INTERVAL 10 MINUTE), b.paid_at, b.expiry_at, b.picked_up_at, 'NONE',
  b.created_at, b.picked_up_at
FROM orders.bf_order b JOIN member.store s ON s.id = b.store_id JOIN inventory.product p ON p.id = b.product_id;
UPDATE orders.orders o JOIN orders.bf_order b ON o.customer_id = b.customer_id AND o.request_id = b.request_id
SET o.order_no = CONCAT('FL-', DATE_FORMAT(b.created_at, '%Y%m%d'), '-', LPAD(o.id, 6, '0'));
INSERT INTO orders.payment (order_id, payment_key, toss_idempotency_key, amount, status, toss_status, method, approved_at,
  sync_attempts, created_at, updated_at)
SELECT o.id, CONCAT('SIM-BF-', b.request_id), UUID(), o.amount, 'DONE', 'DONE', '카드', b.paid_at, 0, b.paid_at, b.paid_at
FROM orders.bf_order b JOIN orders.orders o ON o.customer_id = b.customer_id AND o.request_id = b.request_id;
INSERT INTO orders.order_lot (order_id, lot_id, quantity, expiry_at, created_at)
SELECT o.id, l.id, b.quantity, b.expiry_at, b.paid_at
FROM orders.bf_order b JOIN orders.orders o ON o.customer_id = b.customer_id AND o.request_id = b.request_id
JOIN inventory.inventory_lot l ON l.store_id = b.store_id AND l.product_id = b.product_id AND l.expiry_date = b.expiry_at;

-- inventory 원장 SALE: ref_id = 같은 주문 ID, 시각 = 결제 시각
INSERT INTO inventory.ledger (store_id, lot_id, type, quantity, ref_id, created_at)
SELECT l.store_id, l.id, 'SALE', -b.quantity, CAST(o.id AS CHAR), b.paid_at
FROM orders.bf_order b JOIN orders.orders o ON o.customer_id = b.customer_id AND o.request_id = b.request_id
JOIN inventory.inventory_lot l ON l.store_id = b.store_id AND l.product_id = b.product_id AND l.expiry_date = b.expiry_at;

COMMIT;

-- 확인: 넣은 수, lot마다 원장 합계 = lot 수량(0)이 아닌 lot 수(0이어야 한다)
SELECT (SELECT COUNT(*) FROM inventory.bf_lot) AS lots, (SELECT COUNT(*) FROM orders.bf_order) AS orders,
  (SELECT COUNT(*) FROM orders.payment WHERE payment_key LIKE 'SIM-BF-%') AS payments,
  (SELECT COUNT(*) FROM inventory.inventory_lot l
     JOIN (SELECT lot_id, SUM(quantity) AS total FROM inventory.ledger GROUP BY lot_id) x ON x.lot_id = l.id
   WHERE x.total <> l.quantity) AS ledger_mismatch;
"@

$sqlFile = Join-Path $PSScriptRoot "seed\backfill-$Env.sql"
if ($DryRun) {
    [System.IO.File]::WriteAllText($sqlFile, $sql, (New-Object System.Text.UTF8Encoding $false))
    Write-Host "DryRun: lot $($lotRows.Count)개, 주문 $($orderRows.Count)건 SQL을 $sqlFile 에 저장했다(DB에는 넣지 않았다)."
    exit 0
}
Write-Host "지난 $Days 일: lot $($lotRows.Count)개, 주문 $($orderRows.Count)건을 넣는다 (1–2분)"
Invoke-MySql $sql "table" | ForEach-Object { Write-Host $_ }
Write-Host ""
Write-Host "완료: 마지막 표의 orders와 payments가 같고 ledger_mismatch가 0이면 성공이다."
Write-Host "      점주 대시보드(매출·판매 순위)와 고객 주문 내역에 지난 30일 기록이 보인다."
