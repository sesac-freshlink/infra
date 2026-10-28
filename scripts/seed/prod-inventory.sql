-- prod 시드 ④: 시연용 상품 30개 (ID 1~30, 전 점포 동일가)와 상품 이미지 주소.
-- dev DB를 복사하지 않고 이 파일로 넣는다. prod DB는 빈 채로 inventory V5가 돌아서 V5의 이미지 UPDATE가 아무 행도 바꾸지 못한다.
-- 그래서 이미지 주소(V5와 같은 CU 상품 이미지, 출처는 inventory-service README)를 여기서 같이 넣는다.
-- 재고 lot은 넣지 않는다. prod logistics-simulator 입고(INBOUND)로 생긴다.
-- 여러 번 돌려도 된다. 이미 있으면 값만 맞춘다.
SET NAMES utf8mb4;
START TRANSACTION;

INSERT INTO inventory.product (id, product_code, name, category, price, image_url) VALUES
  ( 1, 'P001', '제육볶음 도시락', '도시락', 4900,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8809196622070.jpg'),
  ( 2, 'P002', '치킨마요 도시락', '도시락', 4500,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8800361441359.jpg'),
  ( 3, 'P003', '불고기 도시락', '도시락', 5200,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8800387752798.jpg'),
  ( 4, 'P004', '참치마요 삼각김밥', '김밥', 1300,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8800279675761_2.png'),
  ( 5, 'P005', '전주비빔 삼각김밥', '김밥', 1300,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8800336397827_1.png'),
  ( 6, 'P006', '참치 김밥', '김밥', 3200,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8800336395403_1.png'),
  ( 7, 'P007', '햄치즈 샌드위치', '샌드위치', 3300,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8800271905354_1.png'),
  ( 8, 'P008', '에그마요 샌드위치', '샌드위치', 3100,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8800387751241.jpg'),
  ( 9, 'P009', '불고기 버거', '샌드위치', 3500,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8800336394567_1.png'),
  (10, 'P010', '닭가슴살 샐러드', '샐러드', 5500,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8809148599009.jpg'),
  (11, 'P011', '리코타치즈 샐러드', '샐러드', 5900,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8809148599016.png'),
  (12, 'P012', '흰 우유 500ml', '유제품', 1900,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8801115118169.jpg'),
  (13, 'P013', '바나나 우유 240ml', '유제품', 1700,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/0000088002798.png'),
  (14, 'P014', '플레인 요거트 400g', '유제품', 3500,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8809520491549.jpg'),
  (15, 'P015', '매운 컵라면 115g', '라면', 1700,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8801045823898.jpg'),
  (16, 'P016', '순한 컵라면 110g', '라면', 1500,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8801045643359.jpg'),
  (17, 'P017', '단팥빵', '빵', 1800,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8801068091632_1.png'),
  (18, 'P018', '소보로빵', '빵', 1800,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8809895798366_2.png'),
  (19, 'P019', '크림치즈 베이글', '빵', 2800,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8801065003188.jpg'),
  (20, 'P020', '초코 케이크 조각', '디저트', 3900,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8801121289105.jpg'),
  (21, 'P021', '우유 푸딩', '디저트', 2500,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8801115800521.jpg'),
  (22, 'P022', '컵 과일 (파인애플)', '과일', 3500,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8809064499933.jpg'),
  (23, 'P023', '바나나 2입', '과일', 2900,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8809918461024.jpg'),
  (24, 'P024', '아메리카노 컵커피 250ml', '음료', 2200,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8801069422664.jpg'),
  (25, 'P025', '오렌지 주스 350ml', '음료', 2500,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8801056071226.png'),
  (26, 'P026', '두부 1모', '신선식품', 2200,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8809387745878.png'),
  (27, 'P027', '계란 10구', '신선식품', 4800,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8801392194115.jpg'),
  (28, 'P028', '훈제 닭가슴살 100g', '신선식품', 2900,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8809216733885_1.png'),
  (29, 'P029', '어묵탕 컵', '즉석식품', 3000,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8809265025221.jpg'),
  (30, 'P030', '떡볶이 컵', '즉석식품', 3300,
   'https://tqklhszfkvzk6518638.edge.naverncp.com/product/8800336393997.jpg')
AS new
ON DUPLICATE KEY UPDATE product_code = new.product_code, name = new.name, category = new.category, price = new.price, image_url = new.image_url;

COMMIT;

SELECT COUNT(*) AS product_count, COUNT(image_url) AS with_image, MIN(id) AS first_id, MAX(id) AS last_id FROM inventory.product WHERE id BETWEEN 1 AND 30;
