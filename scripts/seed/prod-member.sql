-- prod 시드 ①·③: 시연용 점포 3개와 점주 member 행 (scripts/seed-db.ps1 -Env prod가 {{...}}를 채워 실행한다)
-- dev 값(dev-member.sql)을 복사하지 않는다. 시연 화면에 보이는 점포 이름·주소와 점주 이메일(seed-cognito.ps1 -Env prod)만 쓴다.
-- 순서와 제약은 dev-member.sql과 같다: 점포를 PENDING으로 넣고 → 점주 member 행(Cognito sub) → 점포에 점주 연결 + ACTIVE.
-- 여러 번 돌려도 된다. 이미 있으면 값만 맞춘다.
SET NAMES utf8mb4;
-- created_at·updated_at은 DB 기본값이 없어(V1) 직접 NOW(6)을 넣는다. 서비스처럼 KST 벽시계로 저장한다.
SET time_zone = '+09:00';
START TRANSACTION;

-- ① 점포 3개. ID 1~3 고정(Cognito custom:storeId와 같은 값), store_code S1~S3, 지역 SEOUL(비로그인 기본 지역)
INSERT INTO member.store (id, store_code, name, address, region, status, created_at, updated_at) VALUES
  (1, 'S1', '프레시링크 역삼역점', '서울 강남구 역삼로 180', 'SEOUL', 'PENDING', NOW(6), NOW(6)),
  (2, 'S2', '프레시링크 합정점', '서울 마포구 독막로 20', 'SEOUL', 'PENDING', NOW(6), NOW(6)),
  (3, 'S3', '프레시링크 성수점', '서울 성동구 성수이로 88', 'SEOUL', 'PENDING', NOW(6), NOW(6))
AS new
ON DUPLICATE KEY UPDATE store_code = new.store_code, name = new.name, address = new.address, region = new.region, updated_at = new.updated_at;

-- ③ 점주 member 행. id = Cognito sub (seed-cognito.ps1 -Env prod가 만든 계정)
INSERT INTO member.member (id, role, email, created_at, updated_at) VALUES
  ('{{OWNER1_SUB}}', 'OWNER', '{{OWNER1_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER2_SUB}}', 'OWNER', '{{OWNER2_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER3_SUB}}', 'OWNER', '{{OWNER3_EMAIL}}', NOW(6), NOW(6))
AS new
ON DUPLICATE KEY UPDATE role = new.role, email = new.email, updated_at = new.updated_at;

-- 점포에 점주 연결 + 운영 중
UPDATE member.store SET owner_member_id = '{{OWNER1_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 1;
UPDATE member.store SET owner_member_id = '{{OWNER2_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 2;
UPDATE member.store SET owner_member_id = '{{OWNER3_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 3;

COMMIT;

SELECT s.id, s.store_code, s.name, s.region, s.status, m.email AS owner_email
FROM member.store s LEFT JOIN member.member m ON m.id = s.owner_member_id
WHERE s.id IN (1, 2, 3) ORDER BY s.id;
