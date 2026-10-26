# Kế hoạch kiểm thử Bài 2 — slide 18

**Đã thực hiện ngày 26/10/2026: TC01–TC04 PASS ở lượt cuối.** Xem [báo cáo](lab-report.md) và [bằng chứng cuối](../evidence/lab2/final/run.json). Ma trận dưới giữ nguyên tiêu chí từ Bài 1; trạng thái NOT RUN ban đầu đã được thay bằng kết quả thực tế.

## Điều kiện và cách ghi nhận

- Bài 1 đạt readiness; WAF ở `MODSEC_RULE_ENGINE=On`, `BLOCKING_PARANOIA=1`.
- TC01/TC02 dùng cùng payload, mật khẩu cố định, phương thức, đường dẫn và Content-Type; chỉ khác cổng truy cập.
- Dùng phiên trình duyệt sạch cho mỗi test, không dùng token từ lần trước.
- Ghi thời gian và múi giờ, image digest, HTTP status thực tế, danh tính nếu đăng nhập được, rule ID và bằng chứng đã che token/cookie.
- HTTP 200 đơn lẻ không đủ chứng minh đã đăng nhập vào admin.
- Với SPA, xem status của request đăng nhập trong tab Network; trang có thể vẫn hiển thị giao diện khi request login trả 403.

## Ma trận

| ID | Thao tác | Kỳ vọng theo slide | Thực tế | Trạng thái |
|---|---|---|---|---|
| TC01 | `http://localhost:3000` → Login; email `' OR 1=1--`; password `lab-password` | Đăng nhập thành công vào tài khoản admin; xác minh danh tính thực tế | 200; Users API xác nhận ID 1, admin@juice-sh.op, role admin | PASS |
| TC02 | `http://localhost:8080` → Login; cùng dữ liệu TC01 | Request login trả HTTP 403, không nhận token đăng nhập | 403; không token hoặc Set-Cookie | PASS |
| TC03 | Qua cổng 8080; `admin@juice-sh.op` / `admin123` | Đăng nhập thành công, danh tính đúng | 200; Users API qua 8080 xác nhận admin; GUI có giới hạn whoami | PASS |
| TC04 | `docker compose logs waf`; đối chiếu giao dịch TC02 bằng timestamp/transaction ID nếu có | Thấy rule `942100` gắn với request TC02 | Request ID mới khớp transaction có 942100 và 949110 | PASS |

## Quy tắc kết luận

Kết quả trên slide là kỳ vọng, không phải bằng chứng chạy. Nếu TC02 bị chặn nhưng không thấy `942100`, đánh giá TC02 và TC04 riêng, điều tra cấu hình/phiên bản/log thay vì tự thay đổi tiêu chí. Không tắt WAF hoặc thêm rule giả để ép kết quả. TC04 phải liên hệ đúng giao dịch vừa thử, không chỉ tìm rule trong log cũ.

Ảnh giao diện, status Network và trích đoạn log chỉ được bổ sung sau khi thực hiện thật. Bằng chứng Bài 1 nằm tại `evidence/lab1`, không được dùng thay bằng chứng Bài 2.
