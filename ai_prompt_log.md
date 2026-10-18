# Nhật Ký Tương Tác AI (AI Prompt Log) - Tối Ưu Hóa Truy Vấn JOIN Tại FlashMart

Dự án: **FlashMart E-Commerce Platform**  
Vai trò: **Data Engineer & SQL Tuning Specialist**  
Trợ lý AI: **SQL Tuning Assistant & Optimizer Expert**  

---

## 📌 Prompt 1: Hành vi mặc định của từ khóa `JOIN` trong MySQL & Lý thuyết tập hợp

### 💬 Câu hỏi (Data Engineer):
> *"Trong cơ sở dữ liệu MySQL, mặc định từ khóa `JOIN` (khi không ghi rõ `LEFT` hay `RIGHT`) sẽ hoạt động như thế nào? Nó sẽ bỏ qua hay giữ lại các bản ghi không có sự trùng khớp ở cả hai bảng? Hãy giải thích dưới góc nhìn của Lý thuyết tập hợp (Set Theory)."*

### 🤖 Phản hồi của Trợ lý AI:
* Trong chuẩn SQL và cụ thể là hệ quản trị MySQL, từ khóa `JOIN` đứng độc lập (không có tiền tố `LEFT`, `RIGHT`, `FULL` hay `CROSS`) tương đương tuyệt đối với **`INNER JOIN`**.
* **Theo Lý thuyết tập hợp:**
  * Giả sử bảng $A$ (khách hàng) và bảng $B$ (đơn hàng). `INNER JOIN` đại diện cho **phép giao (Intersection)**: $A \cap B$.
  * Phép toán này chỉ giữ lại những dòng mà điều kiện liên kết (ví dụ: `A.customer_id = B.customer_id`) thỏa mãn chân trị `TRUE`.
  * Nếu một bản ghi trong bảng $A$ không có bất kỳ dòng tương ứng nào trong bảng $B$ (hoặc ngược lại), bản ghi đó sẽ bị **loại bỏ hoàn toàn** khỏi tập kết quả.
* **Hệ quả trong bài toán FlashMart:** Vì khách hàng Charlie chưa từng phát sinh đơn hàng trong `Orders`, `INNER JOIN` đã triệt tiêu Charlie khỏi danh sách Marketing. Để giữ lại 100% khách hàng, ta buộc phải dùng `LEFT JOIN` (Left Outer Join: $A \cup (A \cap B)$) để lấy toàn bộ tập $A$ làm bảng định hướng (Driving Table).

---

## 📌 Prompt 2: Cơ chế tính toán của `COUNT(*)` vs `COUNT(cột)` khi kết hợp `LEFT JOIN`

### 💬 Câu hỏi (Data Engineer):
> *"Khi tôi sử dụng `LEFT JOIN` và đếm số lượng đơn hàng bằng hàm `COUNT`, tôi nên dùng `COUNT(*)` hay `COUNT(tên_cột_khóa_chính_bảng_order)`? Sự khác biệt khi kết quả trả về `NULL` là gì?"*

### 🤖 Phản hồi của Trợ lý AI:
* Đây là một trong những cạm bẫy kinh điển nhất trong kỹ thuật SQL Data Warehousing.
* Khi thực hiện `Customers LEFT JOIN Orders`:
  * Đối với khách hàng đã mua (Alice, Bob): Mỗi đơn hàng là một dòng với dữ liệu thật.
  * Đối với khách hàng chưa mua (Charlie): Dòng dữ liệu được sinh ra có dạng:
    `customer_id: 3 | name: 'Charlie' | order_id: NULL | product_id: NULL`
* **So sánh hai cách đếm:**
  1. **`COUNT(*)`:** Đếm **tổng số hàng vật lý** tồn tại trong nhóm `GROUP BY`. Vì dòng của Charlie vẫn tồn tại sau phép `LEFT JOIN`, `COUNT(*)` sẽ đếm dòng đó và cho ra kết quả **1** (Sai nghiêm trọng: Charlie chưa mua hàng mà báo cáo ghi là 1 đơn).
  2. **`COUNT(o.order_id)`:** Đếm số lượng giá trị **khác NULL** tại cột được chỉ định. Vì `o.order_id` của Charlie là `NULL`, hàm `COUNT` sẽ bỏ qua giá trị này và trả về chính xác số lượng là **0**.
* **Quy tắc vàng:** Trong các phép tính thống kê với `LEFT JOIN`, luôn luôn thực hiện hàm tổng hợp (`COUNT`, `SUM`, `AVG`) trên các cột thuộc bảng phụ (bảng bên phải).

---

## 📌 Prompt 3: So sánh hiệu năng Anti-Join (`LEFT JOIN ... IS NULL`) vs `NOT EXISTS` vs `NOT IN`

### 💬 Câu hỏi (Data Engineer):
> *"Hãy phân tích hiệu năng (Performance) của việc dùng `LEFT JOIN` kết hợp `WHERE IS NULL` so với việc dùng subquery `NOT EXISTS` và `NOT IN` khi muốn tìm kiếm các bản ghi không tồn tại trong bảng khác trên MySQL 8.0."*

### 🤖 Phản hồi của Trợ lý AI:
Khi lọc các bản ghi mồ côi (chẳng hạn tìm sản phẩm chưa từng bán ra), có 3 kỹ thuật chính:

| Kỹ thuật | Cú pháp | Ưu điểm & Hành vi MySQL Optimizer | Nhược điểm / Rủi ro |
| :--- | :--- | :--- | :--- |
| **1. Anti-Join (`LEFT JOIN ... WHERE IS NULL`)** | `FROM Products p LEFT JOIN Orders o ON p.id = o.product_id WHERE o.id IS NULL` | Rất trực quan; MySQL Optimizer áp dụng kỹ thuật **Not-Exists Optimization**: Dừng tìm kiếm ngay khi tìm thấy dòng đầu tiên khớp trong bảng phụ. | Cú pháp hơi dài; dễ nhầm lẫn nếu chọn nhầm cột trong mệnh đề `WHERE`. |
| **2. `NOT EXISTS` (Bán nối phủ định)** | `FROM Products p WHERE NOT EXISTS (SELECT 1 FROM Orders o WHERE o.product_id = p.id)` | Rất an toàn với giá trị `NULL`; MySQL 8.0 tự động chuyển đổi thành Anti-Join execution plan; hiệu năng tương đương hoặc vượt trội khi có Index. | Phải viết subquery tương quan (Correlated Subquery). |
| **3. `NOT IN`** | `FROM Products p WHERE p.id NOT IN (SELECT product_id FROM Orders)` | Ngắn gọn nhất về mặt câu chữ. | **CỰC KỲ NGUY HIỂM:** Trong logic 3 giá trị (3VL) của SQL, nếu subquery trả về dù chỉ **1 giá trị NULL**, toàn bộ biểu thức `NOT IN` sẽ trả về `UNKNOWN`, làm cho câu lệnh trả về **0 dòng (tập rỗng)**. |

* **Khuyến nghị kiến trúc:** Luôn ưu tiên dùng `LEFT JOIN ... WHERE IS NULL` hoặc `NOT EXISTS`. Hạn chế dùng `NOT IN` trừ khi chắc chắn 100% cột tham chiếu có ràng buộc `NOT NULL`.

---

## 📌 Prompt 4: Mô phỏng `FULL OUTER JOIN` trong MySQL

### 💬 Câu hỏi (Data Engineer):
> *"Có cú pháp SQL nào cho phép tôi kết hợp kết quả của một `LEFT JOIN` và một `RIGHT JOIN` để giả lập tính năng `FULL OUTER JOIN` trong MySQL không?"*

### 🤖 Phản hồi của Trợ lý AI:
MySQL không hỗ trợ trực tiếp từ khóa `FULL OUTER JOIN` như PostgreSQL hay Oracle/SQL Server. Tuy nhiên, ta có thể mô phỏng chính xác bằng cách kết hợp **`LEFT JOIN`** và **`RIGHT JOIN`** thông qua toán tử **`UNION`**:

```sql
-- 1. Lấy tất cả bản ghi từ bảng Trái (kể cả không có bên Phải)
SELECT c.name, o.order_id, p.product_name
FROM Customers c
LEFT JOIN Orders o ON c.customer_id = o.customer_id
LEFT JOIN Products p ON o.product_id = p.product_id

UNION -- Tự động loại bỏ các dòng trùng lặp giữa 2 tập hợp

-- 2. Lấy tất cả bản ghi từ bảng Phải (kể cả không có bên Trái)
SELECT c.name, o.order_id, p.product_name
FROM Customers c
RIGHT JOIN Orders o ON c.customer_id = o.customer_id
RIGHT JOIN Products p ON o.product_id = p.product_id;
```
Toán tử `UNION` (ngược với `UNION ALL`) sẽ thực hiện loại bỏ trùng lặp (Deduplication) ở phần giao, tạo nên một kết quả tập hợp hợp nhất hoàn chỉnh ($A \cup B$).

---

## 📌 Prompt 5 (Mở rộng chuyên sâu): Cơ chế MySQL Optimizer & Thuật toán thực thi JOIN

### 💬 Câu hỏi (Data Engineer):
> *"Hãy giải thích cách MySQL Optimizer thực thi và tối ưu hóa các lệnh JOIN bằng các thuật toán Nested-Loop Join (Simple Nested-Loop, Block Nested-Loop, Index Nested-Loop) và Hash Join trong MySQL 8.0?"*

### 🤖 Phản hồi của Trợ lý AI:
Trong nội bộ MySQL, công cụ tối ưu hóa truy vấn (Cost-Based Optimizer - CBO) sử dụng các thuật toán sau để thực thi phép nối:

1. **Simple Nested-Loop Join (SNLL):**
   * Quét từng dòng của bảng ngoài (Outer Table), với mỗi dòng lại quét toàn bộ bảng trong (Inner Table).
   * Độ phức tạp: $\mathcal{O}(M \times N)$. Cực kỳ chậm trên tập dữ liệu lớn.
2. **Index Nested-Loop Join (INLJ):**
   * Bảng trong có Index trên cột nối (ví dụ `Orders.customer_id` có B-Tree Index).
   * Khi duyệt bảng ngoài, MySQL dùng Index để tra cứu trực tiếp dòng tương ứng của bảng trong.
   * Độ phức tạp: $\mathcal{O}(M \times \log N)$. Đây là trạng thái tối ưu nhất của vòng lặp lồng.
3. **Block Nested-Loop Join (BNL) - MySQL 5.7 trở về trước:**
   * Nạp một khối các dòng từ bảng ngoài vào bộ nhớ đệm (Join Buffer), sau đó quét bảng trong một lần để đối chiếu với toàn bộ khối, giảm số lần đọc I/O đĩa.
4. **Hash Join (Từ MySQL 8.0.18 trở lên):**
   * MySQL 8.0 đã chính thức thay thế BNL bằng **Hash Join** cho các phép nối bằng (`Equi-join`) không có Index.
   * **Giai đoạn Build:** Đọc bảng nhỏ hơn vào bộ nhớ và xây dựng một Bảng băm (In-memory Hash Table) dựa trên khóa nối.
   * **Giai đoạn Probe:** Quét bảng lớn hơn, băm từng khóa nối và tra cứu trong Hash Table với thời gian trung bình $\mathcal{O}(1)$.
   * Độ phức tạp tổng: $\mathcal{O}(M + N)$ — cải thiện hiệu năng gấp hàng chục đến hàng trăm lần so với BNL truyền thống!
