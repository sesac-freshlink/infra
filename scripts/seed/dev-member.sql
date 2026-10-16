-- dev 시드 ①·③: 점포 3개와 점주 member 행 (scripts/seed-db.ps1이 {{...}}를 채워 실행한다)
-- 순서: 점포를 PENDING으로 넣고 → 점주 member 행(Cognito sub) → 점포에 점주 연결 + ACTIVE.
-- member V1의 "ACTIVE 점포는 점주가 있어야 한다" 제약과 AD-01 등록 순서(member M6)를 그대로 따른다.
-- 여러 번 돌려도 된다. 이미 있으면 값만 맞춘다.
-- 칼럼 이름은 김경우 member V1 기준. V1이 바뀌면 이 파일과 seed-db.ps1의 $expected를 같이 고친다.
SET NAMES utf8mb4;
START TRANSACTION;

-- ① 점포 3개. ID 1~3 고정(inventory·Cognito custom:storeId와 같은 값), 지역 SEOUL(비로그인 기본 지역)
INSERT INTO member.store (id, name, address, region, status) VALUES
  (1, '프레시 강남점', '서울 강남구 테헤란로 152', 'SEOUL', 'PENDING'),
  (2, '프레시 홍대점', '서울 마포구 양화로 160', 'SEOUL', 'PENDING'),
  (3, '프레시 잠실점', '서울 송파구 올림픽로 300', 'SEOUL', 'PENDING')
AS new
ON DUPLICATE KEY UPDATE name = new.name, address = new.address, region = new.region;

-- ③ 점주 member 행. id = Cognito sub (seed-cognito.ps1이 만든 계정)
INSERT INTO member.member (id, role, email) VALUES
  ('{{OWNER1_SUB}}', 'OWNER', '{{OWNER1_EMAIL}}'),
  ('{{OWNER2_SUB}}', 'OWNER', '{{OWNER2_EMAIL}}'),
  ('{{OWNER3_SUB}}', 'OWNER', '{{OWNER3_EMAIL}}')
AS new
ON DUPLICATE KEY UPDATE role = new.role, email = new.email;

-- 점포에 점주 연결 + 운영 중
UPDATE member.store SET owner_member_id = '{{OWNER1_SUB}}', status = 'ACTIVE' WHERE id = 1;
UPDATE member.store SET owner_member_id = '{{OWNER2_SUB}}', status = 'ACTIVE' WHERE id = 2;
UPDATE member.store SET owner_member_id = '{{OWNER3_SUB}}', status = 'ACTIVE' WHERE id = 3;

COMMIT;

SELECT s.id, s.name, s.region, s.status, m.email AS owner_email
FROM member.store s LEFT JOIN member.member m ON m.id = s.owner_member_id
WHERE s.id IN (1, 2, 3) ORDER BY s.id;
