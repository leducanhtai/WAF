# Bằng chứng Bài 2

Các thư mục `tc01`, `tc02`, `tc03`, `tc04` ghi nhận lượt kiểm tra theo tiến độ triển khai. Kết quả cuối cùng sẽ nằm trong `final`. Mỗi test dùng client mới, không lưu cookie; token chỉ tồn tại trong bộ nhớ và chỉ được gửi lại để xác minh danh tính của chính lượt đăng nhập đó.

Endpoint login được xác nhận từ bundle `main.js`, khai báo route `build/server.js` và `build/routes/login.js` trong container Juice Shop. Xác minh danh tính bằng `/rest/user/whoami?fields=id,email,role`; mã `build/routes/currentUser.js` xác nhận endpoint này đọc **cookie token**, không đọc Authorization. Chỉ các trường ID/email/role từ server được lưu. Không dùng nội dung JWT tự giải mã làm bằng chứng danh tính.

JSON bằng chứng lưu dữ liệu đầu vào lab, HTTP status, boolean có token và danh tính đã lọc; không lưu token, cookie, response body nguyên bản hay raw audit log.

Lượt TC01 triển khai: `powershell.exe -NoProfile -NonInteractive -File scripts/Test-Waf.ps1 -Test TC01 -OutputDirectory evidence/lab2/tc01`. Kết quả trong `tc01/TC01.json`: HTTP 200, server xác nhận user ID 1, `admin@juice-sh.op`, role `admin`.
