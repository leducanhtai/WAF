# Bài 2 — Kiểm thử WAF trên hệ thống Bài 1

## Kết quả thực tế

Bộ kết quả lưu trong báo cáo được chạy ngày **26/10/2026, 22:31:01–22:31:13, Asia/Bangkok (UTC+07:00)**: **TC01–TC04 PASS**, tiến trình PowerShell exit **0**. Nguồn chi tiết: [run.json](../evidence/lab2/final/run.json).

| Test | Thời điểm bắt đầu UTC+07 | URL / đầu vào | Kỳ vọng | Thực tế | Rule | Kết quả |
|---|---|---|---|---|---|---|
| TC01 | 22:31:08.573 | `http://localhost:3000/rest/user/login`; email `' OR 1=1--`, password `lab-password` | Đăng nhập admin | HTTP 200; API xác thực trả ID 1, `admin@juice-sh.op`, role `admin` | Không áp dụng: đi thẳng backend | PASS |
| TC02 | 22:31:10.889 | `http://localhost:8080/rest/user/login`; cùng đầu vào TC01 | 403, không token | HTTP 403; không token đăng nhập, không Set-Cookie | 942100, 949110, đối chiếu trong TC04 | PASS |
| TC03 | 22:31:12.965 | `http://localhost:8080/rest/user/login`; `admin@juice-sh.op` / `admin123` | Đăng nhập đúng danh tính | HTTP 200; API xác thực qua 8080 trả ID 1, email đúng, role `admin` | Không dùng rule để kết luận đăng nhập | PASS |
| TC04 | 22:31:13.067 | Log giao dịch TC02 ở trên | Rule 942100 đúng request mới | Audit JSON: 403, request ID và transaction ID khớp | 942100, 949110 | PASS |

Mỗi file [TC01](../evidence/lab2/final/TC01.json), [TC02](../evidence/lab2/final/TC02.json), [TC03](../evidence/lab2/final/TC03.json), [TC04](../evidence/lab2/final/TC04.json) ghi thời gian bắt đầu/kết thúc, URL, đầu vào, kỳ vọng/thực tế, HTTP status, danh tính nếu có, rule và trạng thái. Mảng rule rỗng của TC01/TC03 không khẳng định toàn bộ hoạt động trình duyệt không phát sinh cảnh báo.

## Môi trường và cách kiểm thử


Hai service chạy trên mapping `127.0.0.1:3000:3000` và `127.0.0.1:8080:8080`. Mỗi lượt tự động chạy readiness kiểm tra HTML Juice Shop qua cả hai cổng, kiểm tra biến môi trường và file cấu hình sinh trong container: `SecRuleEngine On`, blocking paranoia `1`. [runtime-config.json](../evidence/lab2/final/runtime-config.json) xác nhận Nginx nạp ModSecurity, `modsecurity on`, proxy tới `http://web:3000`. Digest hai image nằm trong [run.json](../evidence/lab2/final/run.json) và Compose; giữ nguyên phiên bản Bài 1 (Juice Shop 20.3.0, CRS 4.30.0).

Endpoint thực tế được xác nhận trong `build/server.js` của container: `POST /rest/user/login`. TC01 và TC02 dùng cùng chuỗi JSON UTF-8, phương thức POST, đường dẫn, Content-Type `application/json; charset=utf-8`, header đối chiếu `X-Lab-Request-Id`; chỉ đổi địa chỉ cổng. SHA-256 body của cả hai là `ecf2d37cbfb9e3a71561cb3274f65d64bb483a60492234c39f6526b059a3bacc`.

Mỗi test tạo HttpClient độc lập, tắt cookie tự động, proxy và redirect. Token mới chỉ tồn tại trong bộ nhớ. Sau đăng nhập, script đọc ID từ JWT để xác định tài nguyên, gửi Bearer token đến `GET /api/Users/1` **qua cùng cổng đang kiểm thử**, yêu cầu HTTP 200 và đối chiếu ID/email/role của server với claims. Việc decode JWT đơn lẻ không phải tiêu chí đạt. Dữ liệu tài khoản ngoài các trường danh tính được bỏ, không ghi response gốc ra đĩa.

HTTP 4xx được đọc như response bình thường; timeout HTTP mặc định 10 giây, mỗi lệnh Docker 15 giây, readiness 30 giây. Nếu preflight lỗi, các test được ghi NOT RUN với bước lỗi; lỗi khi thực thi test ghi FAIL. Một test không PASS làm exit code khác 0. Các lần thử lỗi vẫn được giữ riêng, không thay thế bằng kết quả cuối.

## Đối chiếu log TC04

Lượt cuối:

- Request ID: `lab2-95820a51a9fa47eab9a0f2fabe9f6d4d`.
- Cửa sổ log bắt đầu trước TC02 hai giây, dùng `docker compose logs --no-color --no-log-prefix --since <UTC> waf`.
- Transaction ID: `179302867231.886547`; audit time `Mon Oct 26 15:31:12 2026` UTC, tương ứng 22:31:12 UTC+07.
- Audit request là POST `/rest/user/login`, status 403, `942100` (libinjection phát hiện SQLi), `949110` (thực thi chặn theo điểm anomaly).

Script chỉ nhận JSON audit có header request ID ngẫu nhiên của lượt vừa chạy, đúng method và URI. Không lấy việc rule xuất hiện trong log cũ làm bằng chứng. Khi chạy riêng TC04, script tạo TC02 mới và lưu kết quả nguồn trong `sourceTest`: [bằng chứng TC04 độc lập](../evidence/lab2/tc04/TC04.json). TC02 và TC04 giữ hai tiêu chí riêng; HTTP 403 không tự làm TC04 PASS.

Logging hiện tại đủ: `RelevantOnly`, `Serial`, JSON, `/dev/stdout`; không cần chỉnh image logging hay Compose. Chỉ trích các trường được phép (thời gian, ID đối chiếu, URI, method, status, rule); không lưu raw log, cookie, JWT, Authorization, body response hoặc HAR. ID giao dịch WAF và ID đối chiếu lab không phải thông tin xác thực phiên.

## Điều tra và giới hạn còn lại

- Client .NET Framework tự thêm `Expect: 100-continue` có thể bị rule `920450` chặn trước khi kiểm tra SQLi. Script đã tắt header tự động này.
- Rule `932260` khớp tên đường dẫn `/rest/user/whoami`, gây chặn nhầm HTTP 403. Vì vậy script dùng Users API có xác thực để kiểm tra danh tính. Login và API Users qua WAF đều trả 200, nhưng menu Account trên giao diện không hiện email. Xem [log quan sát](../evidence/lab2/final/gui-whoami-observation.json).
- Socket.IO dạng `text/plain` cũng bị chặn bởi `920420` và `949110`. Kết quả PASS của TC03 chỉ xác nhận đăng nhập đúng danh tính, không có nghĩa mọi chức năng giao diện đều hoạt động bình thường.

## Demo bằng trình duyệt và ảnh thật

Đã chạy Edge headless bằng CDP, tạo context sạch riêng cho từng test, điền form và click nút login qua sự kiện chuột. `Network.responseReceived` ghi nhận status **200 / 403 / 200**. Token được xác minh qua API Users trong cùng context; không xuất token. Kết quả ngày 26/10/2026 khoảng **22:27:22–22:27:30 UTC+07** nằm trong [browser/results.json](../evidence/lab2/browser/results.json).

- [Ảnh TC01](../evidence/lab2/browser/TC01.png): menu Account có email admin.
- [Ảnh TC02](../evidence/lab2/browser/TC02.png): form hiển thị nội dung lỗi 403 từ Nginx.
- [Ảnh TC03](../evidence/lab2/browser/TC03.png): đăng nhập vào trang sản phẩm; ô email menu trống do giới hạn `/whoami` nêu trên.

Ảnh là ảnh chụp thật, đã xem lại; không có token/cookie trong ảnh. **Chưa kiểm chứng trực tiếp thao tác trên panel DevTools Network và chưa có ảnh panel này**; status đã xác nhận bằng sự kiện Network của trình duyệt.

Các bước demo:

1. Đóng toàn bộ cửa sổ InPrivate/Incognito trước mỗi test rồi mở một phiên mới. Cookie không tách theo cổng: không dùng chung phiên 3000 và 8080. Không bật Remember me.
2. Mở `http://localhost:3000/#/login` cho TC01, đóng Welcome bằng Dismiss và banner cookie. Nhập `' OR 1=1--` / `lab-password`; nhấn Log in; kiểm tra Account hiển thị admin.
3. Với phiên sạch khác, mở `http://localhost:8080/#/login`. Nhấn F12 → **Network**, chọn **Fetch/XHR**, bật Preserve log rồi xóa danh sách cũ; lọc `login`. Nhập đúng payload TC01 và nhấn Log in.
4. Chọn dòng **POST `/rest/user/login`**, xem **Headers → General → Status Code: 403 Forbidden**, Request URL là cổng 8080. Tab Payload cho thấy JSON đúng. Trang SPA có thể vẫn hiện form login; status của document không thay cho status request login. Không nhầm 403 của Socket.IO hoặc whoami với login.
5. Chụp riêng phần General/Status; không chụp Request Headers chứa cookie/Authorization. Không lưu HAR hoặc Response đăng nhập thành công chứa JWT.
6. Phiên sạch thứ ba: qua 8080 nhập `admin@juice-sh.op` / `admin123`; Network login trả 200. Menu email có thể trống do whoami 403; chạy TC03 tự động để kiểm chứng danh tính qua Users API, không xem menu trống là đăng nhập thất bại hay suy ra danh tính từ token tồn tại.
7. Chạy TC04 riêng để tạo request mới có ID và đối chiếu log. Đây là giao dịch tự động mới, không giả nhận là giao dịch GUI vừa click.

## Chạy lại

Từ thư mục repository:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/Test-Waf.ps1 -Test All
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/Test-Waf.ps1 -Test TC01
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/Test-Waf.ps1 -Test TC02
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/Test-Waf.ps1 -Test TC03
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/Test-Waf.ps1 -Test TC04
# Trong PowerShell cũng có thể truyền -Test TC01,TC02.
# Mặc định lưu evidence/lab2/latest, không ghi đè bộ bằng chứng final.
node scripts/Test-WafBrowser.cjs
```

Script GUI cần Node 22+ và Edge tại Program Files (x86), ghi đè thư mục `browser` khi chạy lại. CDP dùng cổng loopback tạm chỉ để điều khiển browser; các request lab vẫn chỉ đến localhost:3000/8080. Profile tạm ngoài repository được dọn sau khi kết thúc.

## Giải thích thiết kế

**Gatekeeper:** WAF đứng trước backend ở đường 8080, kiểm tra request và chặn SQLi trước khi chuyển tiếp. **Gateway Offloading:** việc kiểm tra HTTP bằng ModSecurity/CRS được đưa lên reverse proxy, tách khỏi xử lý nghiệp vụ Juice Shop. Cổng 3000 đi thẳng backend; 8080 qua Nginx + ModSecurity + CRS rồi mới tới backend nếu được cho phép.

WAF **không sửa lỗ hổng backend**: TC01 vẫn khai thác được SQLi khi đi thẳng. Cổng 3000 được giữ có chủ đích để đối chứng trong lab localhost, không phải kiến trúc triển khai Internet cho phép bỏ qua WAF. Kết quả chỉ chứng minh payload và phiên bản đang thử, không chứng minh chặn mọi SQLi; policy cũng có thể chặn nhầm như `/whoami`.
