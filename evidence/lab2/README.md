# Bằng chứng cuối Bài 2

Xem [báo cáo](../../docs/lab-report.md) và [final/run.json](final/run.json): cả bốn test PASS. `final/` là lượt tự động tổng cuối; `browser/` là ảnh thật và kết quả Edge trong phiên sạch. `tc04/` chứng minh chạy TC04 độc lập tạo TC02 mới. Các thư mục `tc01/`, `tc02/`, `tc03/`, `identity-fix/`, `http-client-fix/`, `investigation/` là lịch sử triển khai; có FAIL được giữ để điều tra, không thay thế kết quả cuối.

Các JSON chỉ chứa trường cho phép, không có JWT/cookie/raw log/HAR. Request ID lab và transaction ID WAF được giữ để đối chiếu, không phải dữ liệu xác thực phiên. Phép xác minh hiện tại dùng Bearer token mới và Users API qua cùng cổng; whoami trong các snapshot đầu là phương pháp cũ, đã thay sau khi phát hiện CRS 932260 chặn nhầm.
