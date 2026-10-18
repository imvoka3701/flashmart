-- ====================================================================
-- FLASHMART E-COMMERCE PLATFORM
-- ĐỀ TÀI: KHỦNG HOẢNG CHIẾN DỊCH MARKETING - GIẢI PHÁP TỐI ƯU HÓA LỆNH JOIN
-- Vị trí: Data Engineer
-- Hệ quản trị CSDL: MySQL 8.0+
-- File: flashmart_reports.sql
-- ====================================================================

-- -----------------------------------------------------
-- BƯỚC 0: TẠO VÀ CHỌN CSDL FLASHMART
-- -----------------------------------------------------
DROP DATABASE IF EXISTS flashmart_db;
CREATE DATABASE flashmart_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE flashmart_db;

-- -----------------------------------------------------
-- BƯỚC 1: KHỞI TẠO CẤU TRÚC BẢNG VÀ CHÈN DỮ LIỆU GỐC
-- -----------------------------------------------------
CREATE TABLE Customers (
    customer_id INT PRIMARY KEY,
    name        VARCHAR(50) NOT NULL
) ENGINE = InnoDB;

CREATE TABLE Products (
    product_id   INT PRIMARY KEY,
    product_name VARCHAR(50) NOT NULL
) ENGINE = InnoDB;

CREATE TABLE Orders (
    order_id    INT PRIMARY KEY,
    customer_id INT NOT NULL,
    product_id  INT NOT NULL,
    CONSTRAINT FK_Orders_Customers FOREIGN KEY (customer_id) 
        REFERENCES Customers(customer_id) ON DELETE CASCADE,
    CONSTRAINT FK_Orders_Products FOREIGN KEY (product_id) 
        REFERENCES Products(product_id) ON DELETE CASCADE
) ENGINE = InnoDB;

-- Chèn dữ liệu mẫu theo kịch bản:
INSERT INTO Customers VALUES 
    (1, 'Alice'),
    (2, 'Bob'),
    (3, 'Charlie'); -- GHI CHÚ: Charlie là khách hàng mới đăng ký, CHƯA TỪNG mua hàng

INSERT INTO Products VALUES 
    (101, 'Laptop'),
    (102, 'Mouse'),
    (103, 'Keyboard'); -- GHI CHÚ: Keyboard là sản phẩm tồn kho, CHƯA TỪNG được ai mua

INSERT INTO Orders VALUES 
    (1001, 1, 101), -- Alice mua Laptop
    (1002, 1, 102), -- Alice mua Mouse
    (1003, 2, 101); -- Bob mua Laptop


-- ====================================================================
-- PHÂN TÍCH VẤN ĐỀ TRONG LEGACY SCRIPT CỦA LẬP TRÌNH VIÊN TẬP SỰ
-- ====================================================================

/*
-- [LỖI 1: BÁO CÁO MARKETING (LEGACY SCRIPT GỐC)]
-- Vấn đề: Từ khóa 'JOIN' trong MySQL mặc định là 'INNER JOIN'.
-- INNER JOIN chỉ lấy phần giao (Intersection) của 2 tập hợp Customers và Orders.
-- Vì Charlie chưa có đơn hàng nào trong Orders, bản ghi Charlie bị loại bỏ hoàn toàn.
-- Kết quả sai: Chỉ trả về Alice (2 đơn) và Bob (1 đơn) -> Bỏ sót khách hàng mục tiêu để tặng Voucher 50%!

SELECT c.customer_id, c.name, COUNT(o.order_id) AS total_orders
FROM Customers c
JOIN Orders o ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.name;
*/

/*
-- [LỖI 2: BÁO CÁO KHO VẬN (LEGACY SCRIPT GỐC)]
-- Vấn đề: INNER JOIN loại bỏ tất cả các dòng không khớp trước khi mệnh đề WHERE được xét duyệt.
-- Do đó, trong tập kết quả của INNER JOIN, o.order_id LUÔN LUÔN CÓ GIÁ TRỊ (không bao giờ NULL).
-- Điều kiện 'WHERE o.order_id IS NULL' trở thành một điều kiện mâu thuẫn (Contradiction).
-- Kết quả sai: Trả về tập rỗng (0 dòng) -> Không tìm ra sản phẩm tồn kho Keyboard (103)!

SELECT p.product_id, p.product_name
FROM Products p
JOIN Orders o ON p.product_id = o.product_id
WHERE o.order_id IS NULL;
*/


-- ====================================================================
-- BƯỚC 2 & 3: CÁC CÂU TRUY VẤN ĐÃ ĐƯỢC TỐI ƯU HÓA (PRODUCTION READY)
-- ====================================================================

-- --------------------------------------------------------------------
-- GIẢI PHÁP 1: BÁO CÁO CHIẾN DỊCH MARKETING (SIÊU SALE CUỐI NĂM)
-- Mục tiêu: Lấy toàn bộ khách hàng (kể cả người chưa mua) + số lượng đơn hàng
-- Phân tích kỹ thuật:
--   - Sử dụng LEFT JOIN với Customers là Driving Table (Bảng gốc bên trái).
--   - BẮT BUỘC dùng COUNT(o.order_id) thay vì COUNT(*):
--       * Nếu dùng COUNT(*): Dòng của Charlie sau khi LEFT JOIN sẽ có dạng (3, 'Charlie', NULL, NULL, NULL),
--         COUNT(*) sẽ đếm dòng này và trả về 1 (SAI NGHIỆP VỤ!).
--       * Dùng COUNT(o.order_id): Hàm COUNT bỏ qua giá trị NULL, trả về 0 (CHÍNH XÁC!).
-- --------------------------------------------------------------------
SELECT 
    c.customer_id, 
    c.name, 
    COUNT(o.order_id) AS total_orders,
    CASE 
        WHEN COUNT(o.order_id) = 0 THEN 'Tặng Voucher 50% (Khách hàng tiềm năng)'
        ELSE 'Khách hàng thân thiết'
    END AS marketing_action
FROM Customers c
LEFT JOIN Orders o ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.name
ORDER BY c.customer_id ASC;

-- KẾT QUẢ MONG ĐỢI: 3 DÒNG
-- 1 | Alice   | 2 | Khách hàng thân thiết
-- 2 | Bob     | 1 | Khách hàng thân thiết
-- 3 | Charlie | 0 | Tặng Voucher 50% (Khách hàng tiềm năng)


-- --------------------------------------------------------------------
-- GIẢI PHÁP 2: BÁO CÁO THANH LÝ HÀNG TỒN KHO VẬN (KỸ THUẬT ANTI-JOIN)
-- Mục tiêu: Lấy danh sách sản phẩm CHƯA TỪNG được bán ra lần nào
-- Phân tích kỹ thuật:
--   - Sử dụng LEFT JOIN từ Products sang Orders.
--   - Bổ sung mệnh đề WHERE o.order_id IS NULL (hoặc khóa ngoại o.product_id IS NULL).
--   - MySQL Optimizer sẽ kích hoạt thuật toán Not-Exists / Anti-Join, dừng quét ngay
--     khi phát hiện một sản phẩm có xuất hiện trong Orders, giúp tối ưu tốc độ cực cao.
-- --------------------------------------------------------------------
SELECT 
    p.product_id, 
    p.product_name,
    'Chưa từng phát sinh giao dịch - Đề xuất thanh lý' AS inventory_status
FROM Products p
LEFT JOIN Orders o ON p.product_id = o.product_id
WHERE o.order_id IS NULL;

-- KẾT QUẢ MONG ĐỢI: 1 DÒNG
-- 103 | Keyboard | Chưa từng phát sinh giao dịch - Đề xuất thanh lý


-- ====================================================================
-- PHƯƠNG PHÁP THAY THẾ & MỞ RỘNG KIẾN THỨC NÂNG CAO (TUNING & SET THEORY)
-- ====================================================================

-- --------------------------------------------------------------------
-- Cách 2.2: Dùng NOT EXISTS (Khuyên dùng khi bảng Orders cực lớn và có Index)
-- --------------------------------------------------------------------
SELECT p.product_id, p.product_name
FROM Products p
WHERE NOT EXISTS (
    SELECT 1 FROM Orders o WHERE o.product_id = p.product_id
);

-- --------------------------------------------------------------------
-- Cách 2.3: Dùng NOT IN (Cảnh báo: Nếu Orders.product_id chứa NULL, NOT IN sẽ trả về RỖNG)
-- --------------------------------------------------------------------
SELECT p.product_id, p.product_name
FROM Products p
WHERE p.product_id NOT IN (
    SELECT o.product_id FROM Orders o WHERE o.product_id IS NOT NULL
);

-- --------------------------------------------------------------------
-- Mô phỏng FULL OUTER JOIN trong MySQL bằng LEFT JOIN UNION RIGHT JOIN:
-- --------------------------------------------------------------------
SELECT c.name AS customer_name, o.order_id, p.product_name
FROM Customers c
LEFT JOIN Orders o ON c.customer_id = o.customer_id
LEFT JOIN Products p ON o.product_id = p.product_id
UNION
SELECT c.name AS customer_name, o.order_id, p.product_name
FROM Customers c
RIGHT JOIN Orders o ON c.customer_id = o.customer_id
RIGHT JOIN Products p ON o.product_id = p.product_id;
