# TỔNG HỢP BÀI GIẢNG: THIẾT KẾ CHO BẢO MẬT

> **Môn học:** Kiến trúc phần mềm  
> **Giảng viên:** ThS. Trần Mạnh Cường  
> **Nguồn:** *Thiết kế cho bảo mật – Design pattern*, 19 slide.  
> **Phạm vi:** Tổng hợp toàn bộ nội dung 19 slide, gồm khái niệm, sơ đồ, ưu/nhược điểm, ví dụ, phần thực hành WAF trên Nginx và bài tập về nhà.  
> **Quy ước:** Nội dung trong các mục chính bám theo slide. Những nhận xét bên ngoài bài giảng được ghi rõ **[Ghi chú bổ sung]**; không coi chúng là yêu cầu của giảng viên.

## Mục lục

1. [Đặt vấn đề và mục tiêu bài học](#1-đặt-vấn-đề-và-mục-tiêu-bài-học)
2. [Các mẫu thiết kế bảo vệ điểm truy cập và dữ liệu](#2-các-mẫu-thiết-kế-bảo-vệ-điểm-truy-cập-và-dữ-liệu)
3. [API Gateway và ba mẫu thiết kế](#3-api-gateway-và-ba-mẫu-thiết-kế)
4. [Kết hợp các mẫu trong thực tế](#4-kết-hợp-các-mẫu-trong-thực-tế)
5. [Thực hành WAF trên Nginx](#5-thực-hành-waf-trên-nginx)
6. [Bài tập về nhà](#6-bài-tập-về-nhà)
7. [Tổng kết để ôn tập](#7-tổng-kết-để-ôn-tập)
8. [Bảng đối chiếu slide](#8-bảng-đối-chiếu-slide)

---

## 1. Đặt vấn đề và mục tiêu bài học

**Nguồn: slide 1–3.**

### 1.1. Bài toán bảo mật trong hệ thống microservices

Giả sử hệ thống có **10 microservice**. Mỗi service tự thực hiện các việc:

- Kiểm tra token.
- Cấu hình HTTPS.
- Chặn spam hoặc request không hợp lệ.

Rủi ro: chỉ cần **một service bỏ sót một bước bảo mật** là có thể tạo lỗ hổng làm ảnh hưởng tới toàn hệ thống.

**Thông điệp của bài giảng:** *Bảo mật phải được thiết kế ở cấp kiến trúc, không để từng service tự lo toàn bộ.*

### 1.2. Hai nhóm kiến thức chính

| Nhóm | Mẫu/Pattern | Ý tưởng cốt lõi |
|---|---|---|
| Bảo vệ điểm truy cập và dữ liệu | Gatekeeper | Người gác cổng: kiểm tra, làm sạch request trước khi đi vào hệ thống |
| Bảo vệ điểm truy cập và dữ liệu | Valet Key | Cấp một chìa khóa có hạn để client truy cập trực tiếp tài nguyên |
| Bảo vệ điểm truy cập và dữ liệu | Sidecar | Tiến trình chạy kèm service, đảm nhiệm một phần bảo mật |
| API Gateway | Routing | Một địa chỉ vào, định tuyến request tới các service |
| API Gateway | Aggregation | Gọi nhiều service và gộp kết quả thành một phản hồi |
| API Gateway | Offloading | Gateway xử lý hộ TLS, xác thực, giới hạn tần suất, v.v. |

---

## 2. Các mẫu thiết kế bảo vệ điểm truy cập và dữ liệu

### 2.1. Gatekeeper Pattern — người gác cổng

**Nguồn: slide 4–5.**

**Ý tưởng:** Đặt một thành phần trung gian giữa client và ứng dụng để **kiểm tra, làm sạch request**, sau đó mới chuyển request được chấp nhận vào hệ thống.

Slide 4 minh họa một trang xác minh người dùng trước khi được đi tiếp, làm ví dụ trực quan về cơ chế gác cổng.

**Sơ đồ theo slide 5:**

```text
             VÙNG CÔNG KHAI                  VÙNG NỘI BỘ (TIN CẬY)
Client ───► Gatekeeper ────────────────────► Trusted host / service
Internet    kiểm tra và làm sạch                      │
            request                                ▼
                                            Dữ liệu và khóa

Gatekeeper không giữ khóa và không trực tiếp chạm vào dữ liệu nhạy cảm.
```

**Ưu điểm:**

- Thu hẹp bề mặt tấn công: Internet chỉ nhìn thấy Gatekeeper.
- Theo thiết kế mô tả trên slide, nếu Gatekeeper bị chiếm, khóa và dữ liệu nằm trong vùng nội bộ chưa nhất thiết bị lộ.

**Nhược điểm:**

- Tăng độ trễ và độ phức tạp.
- Có thể trở thành điểm nghẽn; nên dùng nhiều instance để tăng khả năng phục vụ.

**Ví dụ gắn với bài thực hành:** Nginx kết hợp WAF đứng trước ứng dụng web.

### 2.2. Valet Key Pattern — chìa khóa có giới hạn

**Nguồn: slide 6–7.**

Slide 6 minh họa chìa khóa xe như một cách hình dung về quyền truy cập có giới hạn.

**Ý tưởng:** Application Server cấp cho client một quyền truy cập **giới hạn về tài nguyên, thao tác và thời gian**, để client có thể làm việc trực tiếp với nơi lưu trữ thay vì chuyển file qua application server.

**Luồng xử lý trong ví dụ upload ảnh:**

```text
(1) Client ─── xin quyền upload ảnh ───► App Server
(2) Client ◄── URL ký số, chỉ cho ghi, hết hạn sau 10 phút
(3) Client ─── upload trực tiếp ───────────────────► Storage (Blob/S3)
```

Chi tiết:

1. Client (trình duyệt hoặc ứng dụng mobile) đề nghị được upload ảnh.
2. App Server cấp URL có chữ ký bằng khóa bí mật, cho phép **chỉ ghi** vào tài nguyên đã chỉ định và **hết hạn sau 10 phút** trong ví dụ trên slide.
3. Client dùng URL để upload trực tiếp lên storage.

**Ưu điểm:**

- App Server không phải gánh băng thông của file lớn.
- Thực hiện nguyên tắc quyền tối thiểu: giới hạn đến một tài nguyên, một thao tác và một thời hạn.

**Lưu ý:**

- Hạn dùng nên ngắn; có phương án thu hồi/vô hiệu hóa khi bị lộ.
- Vẫn phải kiểm tra file sau khi upload.

**Công nghệ ví dụ trong slide:** Azure SAS token, AWS S3 pre-signed URL.

> **Phân biệt thời gian:** Ví dụ lý thuyết ở slide 7 dùng **10 phút**; bài tập về nhà ở slide 19 yêu cầu **5 phút**.

### 2.3. Sidecar Pattern — tiến trình chạy kèm service

**Nguồn: slide 8–9.**

Slide 8 dùng hình ảnh xe có thùng phụ (sidecar) để minh họa khái niệm một thành phần đi kèm.

**Ý tưởng:** Mỗi service có một thành phần giống “thư ký riêng”. Sidecar kiểm tra bên gọi, xử lý giao tiếp bảo mật và ghi log; mã ứng dụng tập trung vào nghiệp vụ.

**Sơ đồ theo slide 9:**

```text
Giỏ hàng Service ───► [Sidecar của Đơn hàng] ───► Đơn hàng Service
                         │                           │
                         └ kiểm tra danh tính          └ tạo đơn, tính tiền
                           xử lý bảo mật, ghi sổ
```

**Ví dụ:** Khi Giỏ hàng gọi Đơn hàng, Sidecar xác nhận yêu cầu thực sự đến từ Giỏ hàng, xử lý lớp giao tiếp rồi mới đưa request cho code tạo đơn hàng.

**Ưu điểm:**

- Service tập trung vào logic nghiệp vụ, không phải tự gánh toàn bộ xử lý bảo mật.
- Thay đổi chính sách bảo mật tại Sidecar thay vì sửa mã nghiệp vụ của từng service.

**Lưu ý:**

- Mọi lời gọi qua Sidecar có thể tăng một ít độ trễ.
- Mỗi service có Sidecar làm tăng nhu cầu tài nguyên.

**Ví dụ trong slide:** Envoy; slide nêu Lyft là nơi tạo ra Envoy để phục vụ nhiều service.

### 2.4. So sánh Gatekeeper và Sidecar

**Nguồn: slide 10.**

Tình huống: người dùng bấm **Đặt hàng** trong một ứng dụng mua sắm.

```text
Điện thoại
    │
    ▼
Gatekeeper ──► Đơn hàng Service ──► Sidecar ⇄ Sidecar ──► Thanh toán Service
    │                                   
    └ kiểm tra truy cập từ bên ngoài       xác thực, mã hóa giao tiếp nội bộ
```

| Tiêu chí | Gatekeeper | Sidecar |
|---|---|---|
| Ví von | Bảo vệ ở cổng tòa nhà | Thư ký riêng từng phòng |
| Vị trí | Ranh giới đi vào hệ thống | Kèm theo từng service |
| Đối tượng kiểm tra chính trong ví dụ | Request từ bên ngoài | Lời gọi giữa các service |
| Ví dụ kiểm tra | Đã đăng nhập chưa, đơn hợp lệ không, có phải bot đặt hàng hàng loạt không | Khi Đơn hàng gọi Thanh toán: có đúng service Đơn hàng đang gọi không, giao tiếp có được mã hóa không |

**Kết luận:** Gatekeeper và Sidecar **không loại trừ nhau**. Một cái bảo vệ tại cổng vào, một cái giúp bảo vệ giao tiếp bên trong.

---

## 3. API Gateway và ba mẫu thiết kế

### 3.1. Vì sao cần API Gateway?

**Nguồn: slide 11.**

**Không có gateway:**

```text
             ┌──► Order
Client ──────┼──► User
             ├──► Payment
             └──► Review
```

Client phải biết nhiều địa chỉ service; mỗi service tự xử lý TLS, xác thực, và client phải gọi nhiều lần qua mạng.

**Có API Gateway:**

```text
                          ┌──► Order
Client ───► API Gateway ──┼──► User
                          ├──► Payment
                          └──► Review
```

Gateway tạo **một cửa vào duy nhất**, đảm nhiệm định tuyến, gộp các lượt gọi và xử lý chức năng bảo mật dùng chung.

### 3.2. Gateway Routing — định tuyến

**Nguồn: slide 12.**

**Ý tưởng:** Client chỉ cần một địa chỉ. Gateway xem đường dẫn hoặc header ở **Layer 7**, rồi chuyển request tới service phù hợp.

**Ví dụ trên slide:** Client dùng `api.shop.vn`.

```text
                           ┌── /orders: 90% ──► Order v1
Client ─► Gateway ──────────┼── /users ────────► User Service
                           └── /orders: 10% ──► Order v2
```

**Ưu điểm:**

- Ẩn kiến trúc địa chỉ nội bộ; client chỉ biết một địa chỉ.
- Có thể chuyển/đổi service, triển khai phiên bản mới mà client không phải thay đổi.

**Lưu ý:**

- Gateway có thể là điểm nghẽn hoặc điểm chết duy nhất; nên nhân bản gateway.
- Giữ luật định tuyến đơn giản.

**Ví dụ công nghệ:** Nginx, Kong, YARP, Azure Application Gateway.

### 3.3. Gateway Aggregation — gộp phản hồi

**Nguồn: slide 13.**

**Ý tưởng:** Client gửi **một request**, Gateway gọi **nhiều service song song** rồi gộp kết quả trả về một lần.

**Ví dụ trang sản phẩm:**

```text
                              ┌──► Sản phẩm Service ──┐
Client ── 1 request ──► Gateway ├──► Đánh giá Service ─┼──► 1 phản hồi tổng hợp
                              └──► Tồn kho Service ───┘
```

Từ góc nhìn client là **một request**; bên trong gateway có **ba lời gọi service**.

**Ưu điểm:**

- Giảm số lần gọi qua mạng từ client, đặc biệt hữu ích với thiết bị mobile hoặc mạng chậm.
- Client đơn giản hơn; thay đổi backend ít ảnh hưởng tới client.

**Lưu ý:**

- Nếu một service lỗi cần có timeout và phương án trả kết quả một phần.
- Không đưa logic nghiệp vụ vào Gateway.

**Ví dụ:** Backend for Frontend (BFF), GraphQL gateway.

### 3.4. Gateway Offloading — chuyển việc dùng chung lên gateway

**Nguồn: slide 14.**

**Ý tưởng:** Đưa các trách nhiệm dùng chung của nhiều service lên Gateway, để các service xử lý nghiệp vụ chính.

Các chức năng trên slide:

1. Kết thúc TLS (HTTPS).
2. Xác thực token (JWT).
3. Rate limit — giới hạn tần suất request.
4. Chặn IP / WAF.
5. Ghi log và giám sát.
6. Cache phản hồi.

```text
Client (HTTPS)
      │
      ▼
┌───────────────────────────────┐
│           GATEWAY             │
│  TLS | JWT | Rate limit | WAF  │
│  Logging / Monitoring | Cache │
└───────────────────────────────┘
      │
      ├──► Order Service   (nghiệp vụ)
      ├──► User Service    (nghiệp vụ)
      └──► Payment Service (nghiệp vụ)
```

**Ưu điểm:**

- Viết/cấu hình chức năng chung một lần cho nhiều service.
- Đội phát triển nghiệp vụ giảm gánh nặng quản lý chứng chỉ, khóa và các cấu hình liên quan.

**Lưu ý:**

- Không chứa logic nghiệp vụ tại Gateway.
- Sau gateway, giao tiếp và vùng nội bộ vẫn cần an toàn; bài giảng đề xuất kết hợp Sidecar.

**Công nghệ ví dụ:** Kong, Azure API Management, AWS API Gateway.

### 3.5. So sánh ba mẫu Gateway

**Nguồn: slide 15.**

| Mẫu | Vấn đề giải quyết | Quan hệ |
|---|---|---|
| **Gateway Routing** | Một địa chỉ, định tuyến tới nhiều service | 1 request → 1 service (chọn trong n) |
| **Gateway Aggregation** | Gộp nhiều lượt gọi thành một | 1 request → n service |
| **Gateway Offloading** | Gánh hộ TLS, xác thực, giới hạn tần suất | n service → 1 gateway thực hiện chức năng chung |

**Mẹo ghi nhớ của slide:**

- **Routing = chỉ đường.**
- **Aggregation = gom lại.**
- **Offloading = làm hộ.**

---

## 4. Kết hợp các mẫu trong thực tế

**Nguồn: slide 16.**

Các pattern thường được sử dụng **đồng thời**:

- **Gateway tại biên**: Routing + Offloading.
- **Sidecar giữa các service**: hỗ trợ giao tiếp và bảo mật nội bộ.
- **Valet Key cho file lớn**: client truy cập trực tiếp tài nguyên với quyền hạn phù hợp.

```text
Client ──► Gateway (Routing + Offloading) ──► Service A + Sidecar
              │                                   │
              │                                   ▼
              │                              Service B + Sidecar
              │
              └── Cấp quyền truy cập có hạn ──► Storage (Valet Key)
```

Sơ đồ trên là **diễn giải tổng hợp** từ slide 16, không phải sơ đồ nguyên bản trong slide.

---

## 5. Thực hành WAF trên Nginx

**Nguồn: slide 17–18.**

### 5.1. Đề bài và mục tiêu

Dựng một **Gatekeeper thực tế** bằng:

- **Nginx**.
- **ModSecurity**.
- **OWASP Core Rule Set (CRS)**.
- **OWASP Juice Shop** (ứng dụng bán hàng được cố ý xây dựng có lỗ hổng).

Sau đó kiểm thử yêu cầu đăng nhập có dấu hiệu tấn công và quan sát sự khác biệt **khi đi thẳng tới ứng dụng** so với **khi đi qua WAF**.

### 5.2. Vai trò từng thành phần

| Thành phần | Vai trò trong bài demo |
|---|---|
| Juice Shop (`web`) | Ứng dụng backend phục vụ thử nghiệm |
| Nginx (`waf`) | Nhận request từ client, chuyển tiếp request phù hợp tới backend |
| ModSecurity | Công cụ kiểm tra request và thực hiện hành động theo các luật |
| OWASP CRS | Bộ luật bảo mật, trong đó có luật nhận diện dấu hiệu SQL Injection |
| Docker Compose | Khởi chạy và kết nối hai container |

### 5.3. Sơ đồ luồng request

```text
                                 ┌──────────────────────┐
Client ───── localhost:3000 ────►│ OWASP Juice Shop     │
        (bỏ qua WAF)             │ web:3000             │
                                 └──────────────────────┘

Client ───── localhost:8080 ────► Nginx + ModSecurity + OWASP CRS
                                      │
                           Request đạt yêu cầu?
                               /           \
                            Có             Không
                             │                │
                             ▼                ▼
                       web:3000        Chặn request
                                      (VD: HTTP 403)
```

### 5.4. Cấu hình Docker Compose từ slide 17

Tên file: `docker-compose.yml`.

```yaml
services:
  web:
    image: bkimminich/juice-shop
    ports: ["3000:3000"]
  waf:
    image: owasp/modsecurity-crs:nginx
    ports: ["8080:8080"]
    environment:
      BACKEND: http://web:3000
      MODSEC_RULE_ENGINE: "On"
      BLOCKING_PARANOIA: "1"
```

> Đây là **cấu hình được chép lại từ slide**, chưa phải kết quả kiểm chứng chạy với image mới nhất.

### 5.5. Giải thích các biến cấu hình và cổng

| Cấu hình | Ý nghĩa theo slide |
|---|---|
| `BACKEND: http://web:3000` | URL backend mà WAF chuyển request hợp lệ tới |
| `MODSEC_RULE_ENGINE: "On"` | Bật chế độ kiểm tra và chặn |
| `MODSEC_RULE_ENGINE: "DetectionOnly"` | Chỉ phát hiện, ghi log, không chặn |
| `BLOCKING_PARANOIA: "1"` | Mức kiểm tra cơ bản trong khoảng 1–4; mức cao dễ chặn nhầm hơn |
| `3000:3000` | Client đi thẳng tới Juice Shop, không qua WAF |
| `8080:8080` | Client đi vào qua WAF theo cấu hình của slide |

### 5.6. Lệnh chạy

```bash
docker compose up -d
```

### 5.7. Bảng các trường hợp kiểm thử — slide 18

| Test | Thao tác | Kết quả **mong đợi trên slide** |
|---|---|---|
| **TC01 — Không có WAF** | Mở `http://localhost:3000` → Login. Email: `' OR 1=1--`; mật khẩu: bất kỳ | Vào được tài khoản admin |
| **TC02 — Có WAF** | Mở `http://localhost:8080`; dùng dữ liệu đăng nhập có dấu hiệu SQL Injection tương tự | HTTP **403 Forbidden**, bị chặn |
| **TC03 — Đăng nhập đúng** | Qua `http://localhost:8080` với `admin@juice-sh.op` / `admin123` | Đăng nhập bình thường |
| **TC04 — Xem lý do** | Chạy `docker compose logs waf` | Nhìn thấy luật **942100** (SQL Injection) |

**Payload xuất hiện trên slide:**

```text
' OR 1=1--
```

**Lệnh xem log từ slide:**

```bash
docker compose logs waf
```

**Ghi chú kết quả:** Đây đều là **kết quả kỳ vọng**, không phải bằng chứng đã chạy thành công. Tùy phiên bản Juice Shop/CRS, cấu hình và cách request được gửi, kết quả thực tế có thể khác.

### 5.8. Liên hệ lý thuyết với thực hành

- **Gatekeeper:** WAF kiểm tra request từ ngoài trước khi cho đến backend.
- **Gateway Offloading:** Kiểm tra và chặn request nguy hiểm được đảm nhiệm tại một lớp trung gian, thay vì sửa logic nghiệp vụ của Juice Shop.
- **Khác biệt giữa hai cổng:** `:3000` dùng để quan sát ứng dụng không có lớp WAF; `:8080` để quan sát lớp kiểm tra ở cổng vào.

### 5.9. [Ghi chú bổ sung] Những điều nên hiểu khi triển khai

Những điểm dưới đây **không phải yêu cầu trực tiếp từ slide**, nhưng hữu ích để diễn giải kết quả đúng:

- Ở bài demo, cổng `3000` được công khai có chủ đích để so sánh với đường qua WAF. Khi triển khai hệ thống thực, cần tránh để Internet có thể bỏ qua WAF và truy cập trực tiếp backend.
- Việc CRS phát hiện một dấu hiệu tấn công không tự động bảo đảm HTTP 403 trong mọi cấu hình; còn phụ thuộc chế độ luật, chính sách chặn và ngưỡng đánh giá.
- Không nên mặc định tài khoản/mật khẩu mẫu trong slide hoạt động với mọi phiên bản Juice Shop; cần thử và ghi nhận kết quả thực tế.
- Chỉ dùng ứng dụng thực hành cố ý có lỗ hổng hoặc môi trường được phép kiểm thử; không thử payload trên hệ thống không thuộc quyền kiểm soát.

---

## 6. Bài tập về nhà

**Nguồn: slide 19.**

### 6.1. Mô tả hệ thống phải xây dựng

Xây dựng hệ thống gồm:

- **User Service**.
- **Order Service**.
- **Một API Gateway**, ví dụ **Nginx**.

### 6.2. Năm yêu cầu bắt buộc

| STT | Yêu cầu | Pattern liên quan |
|---|---|---|
| 1 | Định tuyến `/users` và `/orders` đến đúng service | Gateway Routing |
| 2 | Kiểm tra JWT và giới hạn **10 request/giây** tại gateway | Gateway Offloading |
| 3 | Endpoint `/dashboard` gộp thông tin user và các đơn hàng của user đó | Gateway Aggregation |
| 4 | Upload ảnh đại diện lên **MinIO** bằng **pre-signed URL**, hết hạn sau **5 phút** | Valet Key |
| 5 | Đo và so sánh **độ trễ** khi qua gateway với khi gọi thẳng service | Đánh giá hiệu năng |

### 6.3. Sơ đồ chức năng gợi ý để đọc đề

```text
                           ┌──── /users ────────► User Service
Client ───► API Gateway ───┼──── /orders ───────► Order Service
            │              │
            │              └──── /dashboard ───► Tổng hợp User + Order
            │
            ├── Xác thực JWT
            └── Rate limit: 10 request/giây

Upload avatar:
Client ──► Xin pre-signed URL ──► Thành phần cấp URL
Client ──► Upload trực tiếp qua URL (hết hạn 5 phút) ──► MinIO
```

Sơ đồ này là **diễn giải để dễ lập kế hoạch triển khai**; slide 19 chỉ liệt kê đầu mục yêu cầu, không quy định cấu trúc thư mục, ngôn ngữ framework hoặc cách cài đặt cụ thể.

### 6.4. Danh sách kiểm tra hoàn thành

- [ ] Có User Service và Order Service.
- [ ] Gateway định tuyến `/users` chính xác.
- [ ] Gateway định tuyến `/orders` chính xác.
- [ ] Gateway kiểm tra JWT.
- [ ] Giới hạn 10 request/giây tại gateway.
- [ ] `/dashboard` trả thông tin user cùng đơn hàng tương ứng.
- [ ] Có luồng upload avatar tới MinIO bằng pre-signed URL.
- [ ] URL hết hạn sau 5 phút.
- [ ] Có kết quả đo độ trễ qua gateway.
- [ ] Có kết quả đo độ trễ gọi thẳng service để so sánh.

---

## 7. Tổng kết để ôn tập

### 7.1. Bảng tổng hợp toàn bài

| Pattern | Bảo vệ/xử lý ở đâu? | Mục tiêu | Ví dụ trong bài |
|---|---|---|---|
| Gatekeeper | Ranh giới public → internal | Lọc request trước khi vào hệ thống | Nginx + WAF |
| Valet Key | Quyền truy cập tới tài nguyên | Cấp quyền tối thiểu, có thời hạn | S3 pre-signed URL, MinIO trong BTVN |
| Sidecar | Cạnh từng service | Xử lý giao tiếp và bảo mật dùng chung | Envoy |
| Gateway Routing | Tại cổng API | Chọn đúng service | `/users`, `/orders` |
| Gateway Aggregation | Tại cổng API | Gộp kết quả của nhiều service | `/dashboard` |
| Gateway Offloading | Tại cổng API | Làm hộ TLS/JWT/Rate limit/WAF | WAF Nginx; xác thực JWT |

### 7.2. Các phân biệt dễ nhầm

**Gatekeeper vs. API Gateway**

- Gatekeeper nhấn mạnh nhiệm vụ **kiểm soát truy cập và lọc request**.
- API Gateway là **điểm truy cập API chung**, có thể định tuyến, tổng hợp kết quả và xử lý các chức năng dùng chung.
- Một API Gateway có WAF có thể đảm nhiệm cả hai vai trò.

**Gatekeeper vs. Sidecar**

- Gatekeeper bảo vệ **điểm vào chung**.
- Sidecar đi kèm **từng service**, hỗ trợ bảo vệ các giao tiếp riêng.

**Routing vs. Aggregation vs. Offloading**

- Routing: chuyển request tới đúng nơi.
- Aggregation: gọi nhiều nơi rồi gộp kết quả.
- Offloading: gateway làm hộ những việc dùng chung.

**Valet Key vs. upload qua app server**

- Valet Key: cấp quyền giới hạn để **client thao tác trực tiếp lên storage**.
- Không cần chuyển toàn bộ file qua application server.

### 7.3. Câu hỏi tự ôn tập

1. Vì sao hệ thống có nhiều microservice nên thiết kế bảo mật ở cấp kiến trúc?
2. Gatekeeper đặt ở đâu và giải quyết vấn đề gì?
3. Vì sao ví dụ Gatekeeper trên slide không giữ khóa hay dữ liệu nhạy cảm?
4. Valet Key có thể giới hạn những loại quyền nào?
5. Sidecar giúp code nghiệp vụ đơn giản hơn như thế nào?
6. Khi Đơn hàng gọi Thanh toán, Gatekeeper hay Sidecar phù hợp với kiểm tra giao tiếp nội bộ?
7. Vì sao API Gateway giúp client trên mạng di động?
8. Khác nhau giữa Routing, Aggregation và Offloading?
9. Tại sao Gateway có thể thành điểm nghẽn hoặc điểm chết duy nhất?
10. Trong bài WAF, cổng 3000 và 8080 có ý nghĩa khác nhau ra sao?
11. `MODSEC_RULE_ENGINE: On` khác `DetectionOnly` thế nào?
12. Luật 942100 được kỳ vọng cho thấy điều gì trong log?
13. Bài tập về nhà yêu cầu giới hạn bao nhiêu request/giây?
14. Bài tập về nhà yêu cầu pre-signed URL MinIO hết hạn sau bao lâu?
15. Vì sao cần so sánh độ trễ gọi qua gateway và gọi thẳng service?

---

## 8. Bảng đối chiếu slide

| Slide | Tiêu đề/nội dung | Vị trí trong tài liệu này |
|---|---|---|
| 1 | Kiến trúc phần mềm — Thiết kế cho bảo mật; giảng viên | Thông tin đầu tài liệu |
| 2 | Đặt vấn đề: 10 microservice, một service sai có thể gây rủi ro | §1.1 |
| 3 | Nội dung: Gatekeeper, Valet Key, Sidecar, ba mẫu Gateway | §1.2 |
| 4 | Gatekeeper: hình minh họa xác minh truy cập | §2.1 |
| 5 | Gatekeeper: luồng, ưu điểm, nhược điểm | §2.1 |
| 6 | Valet Key: hình minh họa chìa khóa | §2.2 |
| 7 | Valet Key: URL ký số, upload trực tiếp, 10 phút | §2.2 |
| 8 | Sidecar: hình minh họa sidecar | §2.3 |
| 9 | Sidecar: thư ký, xử lý giao tiếp, Envoy | §2.3 |
| 10 | Gatekeeper vs. Sidecar với ví dụ đặt hàng | §2.4 |
| 11 | API Gateway: vì sao cần | §3.1 |
| 12 | Gateway Routing, 90% v1 / 10% v2 | §3.2 |
| 13 | Gateway Aggregation, 3 service | §3.3 |
| 14 | Gateway Offloading: TLS, JWT, rate limit, WAF... | §3.4 |
| 15 | Bảng so sánh ba kiểu Gateway | §3.5 |
| 16 | Kết hợp các mẫu ngoài thực tế | §4 |
| 17 | Thực hành WAF trên Nginx: Docker Compose | §5.1–§5.6 |
| 18 | Thực hành WAF: 4 tình huống kiểm thử | §5.7–§5.9 |
| 19 | BTVN: 2 service + Gateway + JWT + MinIO + benchmark | §6 |

---

**Kết luận của bài giảng:** Bảo mật là quyết định **kiến trúc hệ thống**, không chỉ là các lệnh kiểm tra rải rác trong code. Gatekeeper bảo vệ cổng vào; Sidecar hỗ trợ giao tiếp giữa service; Valet Key cấp quyền truy cập tài nguyên có giới hạn; API Gateway tổ chức Routing, Aggregation và Offloading. Bài thực hành Nginx WAF cụ thể hóa nguyên tắc bảo vệ ở cổng vào, còn bài tập về nhà yêu cầu kết hợp các pattern trong một hệ thống nhỏ.
