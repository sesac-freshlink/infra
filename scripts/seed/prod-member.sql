-- prod 시드 ①·③: 서울 점포 30개(문래 근처 10곳 포함)와 점주 member 행 (scripts/seed-db.ps1 -Env prod가 {{...}}를 채워 실행한다)
-- dev 값(dev-member.sql)을 복사하지 않는다. 시연 화면에 보이는 점포 이름·주소와 점주 이메일(seed-cognito.ps1 -Env prod)만 쓴다. 어디에도 test를 넣지 않는다.
-- 순서와 제약은 dev-member.sql과 같다: 점포를 PENDING으로 넣고 → 점주 member 행(Cognito sub) → 점포에 점주 연결 + ACTIVE.
-- 고객 100명 member 행은 seed-db.ps1이 seed-accounts 비밀(seed-cognito.ps1이 만든 sub)로 이 파일 뒤에 따로 넣는다.
-- 여러 번 돌려도 된다. 이미 있으면 값만 맞춘다.
--
-- 점포 목록은 .github docs/할일/3차멘토링-사람별-할일.md 1-1 표와 같다(2026-11-05). ID 4–13은 시연 장소
-- 청년취업사관학교 영등포캠퍼스(서울 영등포구 선유로9길 30, 대략 37.5197, 126.8936) 근처다.
-- 주소는 예시이고, 위도·경도는 근처 역 기준 대략값이다(지오코딩 API를 아직 쓰지 않았다). 지도 기능을 붙일 때
-- 카카오 주소 검색으로 바꾸면 이 파일의 값만 고치고 다시 돌리면 된다.
SET NAMES utf8mb4;
-- created_at·updated_at은 DB 기본값이 없어(V1) 직접 NOW(6)을 넣는다. 서비스처럼 KST 벽시계로 저장한다.
SET time_zone = '+09:00';
START TRANSACTION;

-- ① 점포 30개. ID 1~30 고정(Cognito custom:storeId와 같은 값), store_code S1~S30, 지역 SEOUL(비로그인 기본 지역), 위도·경도(V2)
INSERT INTO member.store (id, store_code, name, address, region, latitude, longitude, status, created_at, updated_at) VALUES
  ( 1, 'S1', '프레시링크 역삼역점', '서울 강남구 역삼로 180', 'SEOUL', 37.500600, 127.036400, 'PENDING', NOW(6), NOW(6)),
  ( 2, 'S2', '프레시링크 합정점', '서울 마포구 독막로 20', 'SEOUL', 37.549600, 126.913900, 'PENDING', NOW(6), NOW(6)),
  ( 3, 'S3', '프레시링크 성수점', '서울 성동구 성수이로 88', 'SEOUL', 37.544600, 127.055800, 'PENDING', NOW(6), NOW(6)),
  ( 4, 'S4', '프레시링크 문래역점', '서울 영등포구 당산로 30', 'SEOUL', 37.518000, 126.894800, 'PENDING', NOW(6), NOW(6)),
  ( 5, 'S5', '프레시링크 문래창작촌점', '서울 영등포구 도림로 428', 'SEOUL', 37.514600, 126.892500, 'PENDING', NOW(6), NOW(6)),
  ( 6, 'S6', '프레시링크 선유로점', '서울 영등포구 선유로 70', 'SEOUL', 37.517500, 126.890500, 'PENDING', NOW(6), NOW(6)),
  ( 7, 'S7', '프레시링크 문래공원점', '서울 영등포구 문래로 164', 'SEOUL', 37.516200, 126.897500, 'PENDING', NOW(6), NOW(6)),
  ( 8, 'S8', '프레시링크 양평역점', '서울 영등포구 양평로 30', 'SEOUL', 37.525400, 126.885700, 'PENDING', NOW(6), NOW(6)),
  ( 9, 'S9', '프레시링크 영등포구청역점', '서울 영등포구 당산로 120', 'SEOUL', 37.524800, 126.895800, 'PENDING', NOW(6), NOW(6)),
  (10, 'S10', '프레시링크 당산역점', '서울 영등포구 당산로 214', 'SEOUL', 37.534300, 126.902400, 'PENDING', NOW(6), NOW(6)),
  (11, 'S11', '프레시링크 도림점', '서울 영등포구 도림로 360', 'SEOUL', 37.509500, 126.899500, 'PENDING', NOW(6), NOW(6)),
  (12, 'S12', '프레시링크 영등포시장점', '서울 영등포구 영중로 9', 'SEOUL', 37.522600, 126.905000, 'PENDING', NOW(6), NOW(6)),
  (13, 'S13', '프레시링크 영등포역점', '서울 영등포구 경인로 846', 'SEOUL', 37.515700, 126.907300, 'PENDING', NOW(6), NOW(6)),
  (14, 'S14', '프레시링크 교대점', '서울 서초구 서초대로 294', 'SEOUL', 37.493400, 127.014200, 'PENDING', NOW(6), NOW(6)),
  (15, 'S15', '프레시링크 잠실점', '서울 송파구 올림픽로 240', 'SEOUL', 37.513300, 127.100100, 'PENDING', NOW(6), NOW(6)),
  (16, 'S16', '프레시링크 신촌점', '서울 서대문구 신촌로 83', 'SEOUL', 37.555200, 126.936900, 'PENDING', NOW(6), NOW(6)),
  (17, 'S17', '프레시링크 마곡점', '서울 강서구 마곡중앙로 161', 'SEOUL', 37.560200, 126.825400, 'PENDING', NOW(6), NOW(6)),
  (18, 'S18', '프레시링크 종각점', '서울 종로구 종로 51', 'SEOUL', 37.570200, 126.983200, 'PENDING', NOW(6), NOW(6)),
  (19, 'S19', '프레시링크 명동점', '서울 중구 명동길 14', 'SEOUL', 37.560900, 126.986300, 'PENDING', NOW(6), NOW(6)),
  (20, 'S20', '프레시링크 이태원점', '서울 용산구 이태원로 177', 'SEOUL', 37.534500, 126.994600, 'PENDING', NOW(6), NOW(6)),
  (21, 'S21', '프레시링크 건대입구점', '서울 광진구 아차산로 243', 'SEOUL', 37.540400, 127.069200, 'PENDING', NOW(6), NOW(6)),
  (22, 'S22', '프레시링크 노원점', '서울 노원구 상계로 69', 'SEOUL', 37.655100, 127.061300, 'PENDING', NOW(6), NOW(6)),
  (23, 'S23', '프레시링크 목동점', '서울 양천구 목동동로 257', 'SEOUL', 37.524500, 126.875000, 'PENDING', NOW(6), NOW(6)),
  (24, 'S24', '프레시링크 사당점', '서울 동작구 동작대로 9', 'SEOUL', 37.476500, 126.981600, 'PENDING', NOW(6), NOW(6)),
  (25, 'S25', '프레시링크 신림점', '서울 관악구 신림로 330', 'SEOUL', 37.484200, 126.929700, 'PENDING', NOW(6), NOW(6)),
  (26, 'S26', '프레시링크 구로디지털단지점', '서울 구로구 디지털로 300', 'SEOUL', 37.485200, 126.901500, 'PENDING', NOW(6), NOW(6)),
  (27, 'S27', '프레시링크 천호점', '서울 강동구 천호대로 1005', 'SEOUL', 37.538600, 127.123600, 'PENDING', NOW(6), NOW(6)),
  (28, 'S28', '프레시링크 수유점', '서울 강북구 도봉로 338', 'SEOUL', 37.637700, 127.025600, 'PENDING', NOW(6), NOW(6)),
  (29, 'S29', '프레시링크 청량리점', '서울 동대문구 왕산로 214', 'SEOUL', 37.580300, 127.046900, 'PENDING', NOW(6), NOW(6)),
  (30, 'S30', '프레시링크 불광점', '서울 은평구 통일로 714', 'SEOUL', 37.610400, 126.929800, 'PENDING', NOW(6), NOW(6))
AS new
ON DUPLICATE KEY UPDATE store_code = new.store_code, name = new.name, address = new.address, region = new.region,
  latitude = new.latitude, longitude = new.longitude, updated_at = new.updated_at;

-- ③ 점주 member 행. id = Cognito sub (seed-cognito.ps1 -Env prod가 만든 계정, 점포 n = OWNERn)
INSERT INTO member.member (id, role, email, created_at, updated_at) VALUES
  ('{{OWNER1_SUB}}', 'OWNER', '{{OWNER1_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER2_SUB}}', 'OWNER', '{{OWNER2_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER3_SUB}}', 'OWNER', '{{OWNER3_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER4_SUB}}', 'OWNER', '{{OWNER4_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER5_SUB}}', 'OWNER', '{{OWNER5_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER6_SUB}}', 'OWNER', '{{OWNER6_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER7_SUB}}', 'OWNER', '{{OWNER7_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER8_SUB}}', 'OWNER', '{{OWNER8_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER9_SUB}}', 'OWNER', '{{OWNER9_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER10_SUB}}', 'OWNER', '{{OWNER10_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER11_SUB}}', 'OWNER', '{{OWNER11_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER12_SUB}}', 'OWNER', '{{OWNER12_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER13_SUB}}', 'OWNER', '{{OWNER13_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER14_SUB}}', 'OWNER', '{{OWNER14_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER15_SUB}}', 'OWNER', '{{OWNER15_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER16_SUB}}', 'OWNER', '{{OWNER16_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER17_SUB}}', 'OWNER', '{{OWNER17_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER18_SUB}}', 'OWNER', '{{OWNER18_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER19_SUB}}', 'OWNER', '{{OWNER19_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER20_SUB}}', 'OWNER', '{{OWNER20_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER21_SUB}}', 'OWNER', '{{OWNER21_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER22_SUB}}', 'OWNER', '{{OWNER22_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER23_SUB}}', 'OWNER', '{{OWNER23_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER24_SUB}}', 'OWNER', '{{OWNER24_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER25_SUB}}', 'OWNER', '{{OWNER25_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER26_SUB}}', 'OWNER', '{{OWNER26_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER27_SUB}}', 'OWNER', '{{OWNER27_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER28_SUB}}', 'OWNER', '{{OWNER28_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER29_SUB}}', 'OWNER', '{{OWNER29_EMAIL}}', NOW(6), NOW(6)),
  ('{{OWNER30_SUB}}', 'OWNER', '{{OWNER30_EMAIL}}', NOW(6), NOW(6))
AS new
ON DUPLICATE KEY UPDATE role = new.role, email = new.email, updated_at = new.updated_at;

-- 점포에 점주 연결 + 운영 중
UPDATE member.store SET owner_member_id = '{{OWNER1_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 1;
UPDATE member.store SET owner_member_id = '{{OWNER2_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 2;
UPDATE member.store SET owner_member_id = '{{OWNER3_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 3;
UPDATE member.store SET owner_member_id = '{{OWNER4_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 4;
UPDATE member.store SET owner_member_id = '{{OWNER5_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 5;
UPDATE member.store SET owner_member_id = '{{OWNER6_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 6;
UPDATE member.store SET owner_member_id = '{{OWNER7_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 7;
UPDATE member.store SET owner_member_id = '{{OWNER8_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 8;
UPDATE member.store SET owner_member_id = '{{OWNER9_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 9;
UPDATE member.store SET owner_member_id = '{{OWNER10_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 10;
UPDATE member.store SET owner_member_id = '{{OWNER11_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 11;
UPDATE member.store SET owner_member_id = '{{OWNER12_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 12;
UPDATE member.store SET owner_member_id = '{{OWNER13_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 13;
UPDATE member.store SET owner_member_id = '{{OWNER14_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 14;
UPDATE member.store SET owner_member_id = '{{OWNER15_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 15;
UPDATE member.store SET owner_member_id = '{{OWNER16_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 16;
UPDATE member.store SET owner_member_id = '{{OWNER17_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 17;
UPDATE member.store SET owner_member_id = '{{OWNER18_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 18;
UPDATE member.store SET owner_member_id = '{{OWNER19_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 19;
UPDATE member.store SET owner_member_id = '{{OWNER20_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 20;
UPDATE member.store SET owner_member_id = '{{OWNER21_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 21;
UPDATE member.store SET owner_member_id = '{{OWNER22_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 22;
UPDATE member.store SET owner_member_id = '{{OWNER23_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 23;
UPDATE member.store SET owner_member_id = '{{OWNER24_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 24;
UPDATE member.store SET owner_member_id = '{{OWNER25_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 25;
UPDATE member.store SET owner_member_id = '{{OWNER26_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 26;
UPDATE member.store SET owner_member_id = '{{OWNER27_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 27;
UPDATE member.store SET owner_member_id = '{{OWNER28_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 28;
UPDATE member.store SET owner_member_id = '{{OWNER29_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 29;
UPDATE member.store SET owner_member_id = '{{OWNER30_SUB}}', status = 'ACTIVE', updated_at = NOW(6) WHERE id = 30;

COMMIT;

SELECT s.id, s.store_code, s.name, s.status, s.latitude, s.longitude, m.email AS owner_email
FROM member.store s LEFT JOIN member.member m ON m.id = s.owner_member_id
WHERE s.id BETWEEN 1 AND 30 ORDER BY s.id;
