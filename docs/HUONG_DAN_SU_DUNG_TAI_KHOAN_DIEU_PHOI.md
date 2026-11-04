# HƯỚNG DẪN SỬ DỤNG TÀI KHOẢN ĐIỀU PHỐI

Ứng dụng: **App Quản Lý Vận Tải VinTrans** (Flutter - app_tai_xe)
Đối tượng: **Điều phối viên** (vai trò `dispatcher`)
Nguồn chuẩn: `docs/Dac_ta_app_tai_xe_Flutter.docx`, `docs/DS DIEU PHOI_TAI XE.xlsx`, `docs/DANH_SACH_TAI_KHOAN_VA_MAT_KHAU.md`, mã nguồn `app_tai_xe/lib`
Cập nhật: theo đặc tả ngày 30/10/2026

---

## 1. TỔNG QUAN VAI TRÒ ĐIỀU PHỐI

Điều phối viên là "bộ não vận hành" của chuyến hàng trong ngày. Công việc chính gồm 4 nhóm:

| Nhóm công việc | Mục đích |
|---|---|
| **Trực ca điều phối** | Nhận ca, đồng hành trực tuyến cùng các điều phối viên khác, bàn giao ca có ghi chú |
| **Duyệt 5 ảnh đầu ngày & xử lý báo hỏng** | Xác nhận bộ 5 ảnh kiểm tra xe hợp lệ thì duyệt; tài xế báo hỏng thì quyết định "Cho chạy" hoặc "Đưa vào xưởng" |
| **Quản lý đơn hàng vận tải** | Theo dõi 4 mốc giờ (Trước bơm - Cân - Đến giao - Giao), nhắc tài xế, tạo và điều phối đơn |
| **Giám sát tổng thể** | Bản đồ GPS toàn đội xe, tỷ lệ tuân thủ 5 ảnh, cảnh báo sự cố theo thời gian thực |

**Nguyên tắc vàng của Điều phối:**

- Tài xế **chỉ được chạy chuyến khi đã gửi đủ 5 ảnh VÀ Điều phối bấm Duyệt**. Thiếu một trong hai, xe ở trạng thái chờ.
- Chuyến có **Báo hỏng sẽ bị giữ trên hệ thống** cho tới khi Điều phối bấm "Cho chạy" hoặc "Đưa vào xưởng".
- Ảnh **lệch ODO > 20 km** so với chuyến trước sẽ tự gắn **CỜ BẤT THƯỜNG** và chuyển về màn hình Kiểm tra xe để Điều phối/Kỹ thuật xem xét.
- GPS lệch quá **2 km** so với điểm giao hoặc tài xế **chờ bồn quá 120 phút** sẽ sinh vi phạm tự động, hiện trong khối cảnh báo và báo cáo tuân thủ.

---

## 2. ĐĂNG NHẬP HỆ THỐNG

### 2.1. Các bước đăng nhập

1. Mở ứng dụng trên máy tính bảng/điện thoại dùng chung tại phòng điều phối.
2. Tại màn hình đăng nhập, nhập **Tên đăng nhập** và **Mật khẩu**.
3. Bấm nút **Đăng nhập**. Hệ thống tự nhận diện vai trò Điều phối và vào thẳng màn hình **Tổng Quan & Báo Cáo Tuân Thủ**.
4. Kết thúc ca: bấm **Đăng xuất tài khoản** ở menu bên.

### 2.2. Danh sách tài khoản Điều phối

Nguồn chuẩn: `docs/DS DIEU PHOI_TAI XE.xlsx` - mật khẩu mặc định chung: `123456`

| STT | Họ và tên | Tên đăng nhập | SĐT | Mật khẩu mặc định |
|---|---|---|---|---|
| 1 | Nguyễn Văn Tân | `dieuphoi_nguyenvantan` | 0984549998 | `123456` |
| 2 | Vũ Hoàng Quân | `dieuphoi_vuhoangquan` | 0965778885 | `123456` |
| 3 | Triệu Thị Huệ | `dieuphoi_trieuthihue` | 0988498885 | `123456` |

**Lưu ý:**

- Nên **đổi mật khẩu ngay sau lần đăng nhập đầu tiên** (liên hệ Admin - Duy IT khi cần hỗ trợ).
- Mỗi điều phối viên dùng **tài khoản riêng**, tuyệt đối không dùng chung, vì lịch sử ca trực, duyệt ảnh, duyệt chuyến đều gắn với tài khoản cá nhân.
- Hệ thống **cho phép nhiều điều phối viên cùng nhận ca và đồng hành trực tuyến**; vẫn phải nhận ca riêng cho từng người.

---

## 3. GIAO DIỆN CHÍNH VÀ MENU

### 3.1. Menu bên (Drawer) của tài khoản Điều phối

Sau khi đăng nhập, bấm biểu tượng menu (3 gạch ngang) ở góc trái màn hình để mở Drawer. Các mục dành cho Điều phối:

**Nhóm giám sát và điều hành:**

| Mục menu | Chức năng |
|---|---|
| **Bản đồ Giám sát GPS** | Theo dõi vị trí toàn đội xe thời gian thực |
| **Kiểm tra xe** | Kiểm tra chất lượng xe qua 5 ảnh giao ca, duyệt hoặc yêu cầu chụp lại |
| **Đơn hàng vận tải** | Danh sách đơn, tuyến đường giao, tạo đơn mới |

**Nhóm "HỆ THỐNG QUẢN TRỊ DỰ ÁN":**

| Mục menu | Chức năng |
|---|---|
| **Tổng quan & Báo cáo** | Chỉ số vận hành, tỷ lệ tuân thủ |
| **Khách hàng** | Danh sách khách hàng, liên hệ |
| **Điểm nhận / giao** | Kho, cảng, gợi ý từ GPS |

**Nhóm cấu hình (mở rộng):**

| Mục menu | Chức năng |
|---|---|
| **Cấu Hình Vai Trò & Quyền** | Xem cấu hình phân quyền hệ thống |
| **Cấu Hình Nhắc Nhở & Kịch Bản Nền** | Định cấu hình ngưỡng vi phạm GPS/thời gian chờ bồn, kịch bản nhắc nhở |
| **Cấu Hình Proxy AI & Trợ Lý Thông Minh** | Cấu hình OpenAI API / Vision Audit / Voice Assistant |

### 3.2. Những mục Điều phối KHÔNG nhìn thấy (phân quyền)

Theo mã nguồn, các mục sau **chỉ dành cho Admin và Quản lý/Giám đốc**, tài khoản Điều phối không truy cập được:

- **Đội xe & Tài xế** (gán tài xế - mooc)
- **Cây dầu & Đối soát** (định mức tiêu hao, công nợ cấp phát)
- **Sản phẩm & Vật liệu** (danh mục hàng hóa)
- **Quản lý Tài khoản** (tạo/sửa tài khoản nhân viên)
- Nhóm "DÀNH CHO TÀI XẾ" (Lịch trình xe, Đơn hàng, Hình chụp xe của tài xế)

Nếu gặp nhu cầu liên quan các mục này (ví dụ xe chưa được gán tài xế phụ trách), liên hệ **Admin (Duy IT)** hoặc Quản lý để xử lý.

### 3.3. Màn hình Điều phối chính

Đây là màn hình làm việc chính với các tab nội bộ:

1. **Tổng quan điều hành & Báo cáo tuân thủ**
2. **Đơn hàng vận tải** (Bộ lọc đa tiêu chí, bảng dữ liệu & phân trang)
3. **Đội xe & Phương tiện** *(chỉ Admin/Quản lý)*
4. **Quản lý Tài khoản & Phân quyền** *(chỉ Admin/Quản lý)*
5. **Cây dầu & Đối soát nhiên liệu** *(chỉ Admin/Quản lý)*
6. **Sản phẩm & Vật liệu xây dựng** *(chỉ Admin/Quản lý)*
7. **Cấu hình Nhắc nhở & Kịch bản Nền**
8. **Cấu hình Proxy AI**

Phía trên các tab có **khối "Điều phối viên Đang trực ca"** (biểu tượng tai nghe) hiển thị trạng thái ca và các nút nhận/bàn giao ca - xem mục 4.

---

## 4. TRỰC CA ĐIỀU PHỐI (NHẬN CA - BÀN GIAO CA)

Khối **"Điều phối viên Đang trực ca"** nằm ở đầu màn hình Điều phối, kèm chú thích: *"Hệ thống cho phép nhiều điều phối viên cùng nhận ca và đồng hành trực tuyến"*.

### 4.1. Nhận ca trực

1. Đăng nhập bằng tài khoản điều phối của mình.
2. Ở khối "Điều phối viên Đang trực ca", bấm nút **Nhận ca trực**.
3. Cửa sổ **"Nhận ca trực điều phối"** hiện ra: chọn **ca trực** phù hợp (ca ngày/ca đêm) trong mục "Chọn ca trực", nhập ghi chú nếu cần.
4. Xác nhận. Hệ thống báo **"Đã nhận ca trực thành công! Trạng thái đang làm việc đã được cập nhật."**

**Lưu ý:** Nút **Nhận ca trực chỉ hiển thị với tài khoản Điều phối**. Admin và Quản lý/Giám đốc chỉ được xem, không bấm được nút này.

### 4.2. Bàn giao ca trực và kết thúc ca

1. Cuối ca, ở khối đang trực ca bấm **Bàn giao ca trực & Kết thúc**.
2. Hệ thống hỏi xác nhận: *"Bạn có chắc muốn kết thúc ca trực hiện tại? Hãy nhập ghi chú bàn giao cho các điều phối viên ca tiếp theo nếu có."*
3. **Nhập ghi chú bàn giao**: các đơn dở dang, chuyến đang chờ duyệt ảnh, sự cố chưa xử lý xong, tồn bồn...
4. Xác nhận. Hệ thống báo **"Đã bàn giao và kết thúc ca trực thành công!"**

### 4.3. Nhật ký và Lịch sử ca trực

- Mục **"Nhật ký & Lịch sử ca trực Điều phối viên"** lưu toàn bộ lịch sử nhận ca, bàn giao ca kèm ghi chú.
- Có thể **lọc theo điều phối viên** và **lọc theo ngày** để tra cứu.
- Nếu chưa từng nhận ca, hệ thống hiển thị: *"Chưa có dữ liệu lịch sử ca trực nào được ghi nhận."*
- **Riêng Admin** được quyền **đóng ca trực của điều phối viên khác** vào bất kỳ lúc nào (quên bàn giao, quên đăng xuất...); ca trực đó kết thúc ngay lập tức.

---

## 5. DUYỆT 5 ẢNH ĐẦU NGÀY VÀ XỬ LÝ BÁO HỎNG

Đây là việc **bắt buộc phải làm sớm mỗi sáng**: tài xế gửi 5 ảnh kiểm tra xe, Điều phối duyệt thì xe mới chuyển trạng thái **"Đủ điều kiện chạy"**.

### 5.1. Quy trình duyệt 5 ảnh

1. Vào menu **Kiểm tra xe**.
2. Xem bộ 5 ảnh từng xe: Gầm trước - Gầm sau - Hông trái - Hông phải - Táp lô/ODO.
3. Đối chiếu:
   - Ảnh có rõ, đủ sáng, đúng vị trí không?
   - Số km (ODO) đọc được từ ảnh có khớp lịch trình không? (Lệch > 20 km sẽ có **CỜ BẤT THƯỜNG**)
   - Có hư hỏng mới (cản nứt, rò rỉ dầu, lốp non...) không?
4. Bấm **Duyệt** nếu hợp lệ, hoặc **Từ chối/Yêu cầu chụp lại** kèm **"Ghi chú kiểm tra của Điều phối"** (ví dụ: cản nứt, lệch km hành trình, ảnh mờ...).
5. Tài xế bên kia nhận được kết quả sau tối đa **30 giây** (app tài xế tự đồng bộ trạng thái duyệt định kỳ 30 giây/lần).

**Phân loại phụ cấp tuân thủ (theo báo cáo):**

| Tỷ lệ ngày đủ 5 ảnh trong tháng | Phụ cấp tuân thủ |
|---|---|
| Từ 90% trở lên | 100% |
| Từ 70% đến dưới 90% | 50% |
| Dưới 70% | 0% |

### 5.2. Xử lý Báo hỏng từ tài xế

Khi tài xế báo hỏng trong lúc kiểm tra 5 ảnh (6 hạng mục: Lốp xe, Rò rỉ dầu mỡ, Hệ thống nhíp, Bồn chứa/van xả, Điện, Khác), chuyến bị **giữ trên hệ thống** cho tới khi Điều phối ra quyết định:

| Quyết định | Khi nào chọn | Hệ quả |
|---|---|---|
| **Cho chạy** | Hư hỏng nhỏ, không ảnh hưởng an toàn (ví dụ đèn phụ, vết trầy xước nhỏ) | Chuyến được mở khóa, tài xế vận hành bình thường |
| **Đưa vào xưởng** | Hư hỏng ảnh hưởng an toàn hoặc chuyên chở (nổ lốp, rò rỉ dầu, nhíp hỏng) | Xe rút khỏi chuyến; Điều phối gán đơn cho xe khác còn "Đủ điều kiện chạy" |

Các bước xử lý:

1. Vào **Kiểm tra xe** (hoặc khối cảnh báo ở Tổng quan), tìm xe có **Báo hỏng đang chờ**.
2. Xem lại ảnh và mô tả hư hỏng của tài xế.
3. Bấm **Cho chạy** hoặc **Đưa vào xưởng**.
4. Nếu cần đổi xe: tạo/gán lại đơn hàng cho xe khác **đã được duyệt 5 ảnh trong ngày** (hệ thống chỉ gợi ý những xe này).

---

## 6. QUẢN LÝ ĐƠN HÀNG VẬN TẢI

### 6.1. Theo dõi 4 mốc giờ của chuyến

Mỗi chuyến có 4 mốc giờ độc lập, tài xế tự bấm, Điều phối giám sát và nhắc:

| Bước | Tên mốc trong app tài xế | Điều phối cần làm gì |
|---|---|---|
| 1 | **Trước bơm** | Nhắc tài xế bấm trước khi vào bồn; kiểm tra xe đã "Đủ điều kiện chạy" |
| 2 | **Cân** | Nhắc bấm tại trạm cân; đối chiếu khối lượng |
| 3 | **Đến giao** | GPS phải cách điểm giao **dưới 2 km** mới cho bấm; quá xa sẽ sinh vi phạm |
| 4 | **Giao** | Nhắc bấm ngay khi trả hàng xong; chênh lệch lớn giữa 2 mốc (> 120 phút) sinh cảnh báo |

Các mốc hiện trong **khối LIVE** ở màn hình Tổng quan với chú thích: *"Cập nhật tức thời các mốc nhận chuyến, giao hàng, kiểm tra 5 ảnh đầu ngày và cảnh báo sự cố từ tài xế"*. Bấm nút **Làm mới** để tải dữ liệu mới nhất.

### 6.2. Bộ lọc và tra cứu đơn

Trong tab **Đơn hàng vận tải** có bộ lọc đa tiêu chí:

- **Ngày tháng** (khoảng ngày)
- **Mã đơn**
- **Sản phẩm**
- **Xe**
- **Tài xế**
- **Nơi nhận**, **Điểm giao**
- **Loại xe**

Bảng dữ liệu hỗ trợ **phân trang**; kết hợp nhiều tiêu chí để thu hẹp kết quả khi tra cứu.

### 6.3. Tạo đơn hàng mới

1. Vào tab **Đơn hàng vận tải**, bấm nút **Tạo đơn hàng**.
2. Điền thông tin: **Mã đơn hàng để trống** nếu muốn hệ thống tự sinh, hoặc **tự nhập** mã theo quy ước doanh nghiệp.
3. **Hàng hóa**: chọn từ danh mục có sẵn; mục **Sản phẩm** điều phối có thể nhập tay.
4. Chọn **xe** và **tài xế**:
   - Hệ thống **chỉ gợi ý xe đang rảnh + đã gửi đủ 5 ảnh và được Điều phối duyệt trong ngày**.
   - Nếu xe **chưa được gán tài xế phụ trách**, hệ thống chặn và yêu cầu vào "Đội xe & Tài xế để gán trước" - mục này Điều phối không có quyền, liên hệ **Admin/Quản lý**.
5. Xác nhận tạo. Đơn xuất hiện trong danh sách và trên lịch trình của tài xế.

---

## 7. TỔNG QUAN VÀ BÁO CÁO TUÂN THỦ

Tab **Tổng quan điều hành & Báo cáo tuân thủ** gồm:

### 7.1. Các thẻ chỉ số (bấm để đi tới chi tiết)

| Thẻ | Nội dung | Bấm vào sẽ |
|---|---|---|
| **Tổng phương tiện** | Tổng số xe trong hệ thống | Mở tab Đội xe & Phương tiện |
| **Đơn hàng hôm nay** | Số đơn trong ngày | Mở tab Đơn hàng vận tải |
| **Tỷ lệ tuân thủ 5 ảnh** | Tỷ lệ xe gửi đủ 5 ảnh được duyệt | Mở màn hình Kiểm tra xe |
| **Tổng người dùng** *(chỉ Admin/Quản lý)* | Tổng tài khoản hệ thống | Mở Quản lý Tài khoản |

### 7.2. Khối LIVE - Báo cáo trạng thái realtime

Tổng hợp báo cáo trạng thái của tài xế từ 4 nguồn: **Đơn hàng, Kiểm tra 5 ảnh, Đội xe và Cảnh báo**, gồm:

- Các mốc nhận chuyến, giao hàng mới nhất
- Kết quả kiểm tra 5 ảnh đầu ngày
- Cảnh báo sự cố từ tài xế (báo hỏng, cờ bất thường, lệch GPS)

Kèm phân trang *"Hiển thị x - y trên tổng số z báo cáo"* và nút **Làm mới**.

### 7.3. Cảnh báo tự động Điều phối cần theo dõi

| Cảnh báo | Ngưỡng | Cách xử lý |
|---|---|---|
| GPS lệch điểm giao | > 2 km | Gọi xác nhận vị trí tài xế, hướng dẫn di chuyển đúng điểm |
| Chờ tại bồn quá lâu | > 120 phút | Liên hệ trạm/bồn, nhắc tài xế cập nhật mốc giờ |
| ODO lệch bất thường | > 20 km | Kiểm tra lại ảnh táp lô, yêu cầu chụp lại nếu mờ/sai |
| Báo hỏng xe | Khi có | Quyết định "Cho chạy" hoặc "Đưa vào xưởng" |

---

## 8. CÁC MÀN HÌNH HỖ TRỢ KHÁC

### 8.1. Bản đồ Giám sát GPS

- Hiển thị **vị trí toàn đội xe thời gian thực** trên bản đồ.
- Dùng để: xác minh vị trí trước mốc "Đến giao", tra cứu xe đứng yên lâu, hỗ trợ điều phối xe gần điểm nhận nhất.

### 8.2. Khách hàng

- Danh sách khách hàng, thông tin liên hệ; tra cứu nhanh khi tạo đơn hoặc xử lý sự cố giao nhận.

### 8.3. Điểm nhận / giao

- Danh mục kho, cảng, điểm nhận/giao hàng; có **gợi ý từ GPS**.
- Là cơ sở để hệ thống tính khoảng cách GPS 2 km tại mốc "Đến giao" - cần báo Admin cập nhật khi có điểm giao mới.

### 8.4. Cấu hình Nhắc nhở & Kịch bản Nền

- Theo dõi các **quy tắc kiểm tra tự động chạy nền** (nhắc mốc giờ, kiểm tra GPS, thời gian chờ bồn).
- **Định cấu hình ngưỡng vi phạm** GPS/thời gian chờ bồn.
- **Chạy kiểm thử mô phỏng** các kịch bản thực tế gửi về thiết bị tài xế (dùng để kiểm tra thông báo trước khi áp dụng thật).

### 8.5. Cấu hình Proxy AI

- Cấu hình **OpenAI API** cho các tính năng: **Vision Audit** (kiểm duyệt ảnh tự động), **Voice Assistant** (trợ lý thông minh).
- Chỉ thay đổi khi có chỉ đạo của Admin/IT; cấu hình sai có thể làm gián đoạn kiểm duyệt ảnh.

---

## 9. CÂU HỎI THƯỜNG GẶP (FAQ)

**Hỏi: Tôi bấm Duyệt rồi nhưng tài xế bảo máy tài xế chưa thấy "Đủ điều kiện chạy"?**
Đáp: App tài xế tự đồng bộ trạng thái duyệt **mỗi 30 giây/lần**. Chờ khoảng nửa phút; nếu quá 2 phút vẫn chưa cập nhật, yêu cầu tài xế kéo làm mới hoặc kiểm tra mạng, sau đó bấm Duyệt lại.

**Hỏi: Tài xế báo hỏng nhưng tôi không chắc nên "Cho chạy" hay "Đưa vào xưởng"?**
Đáp: Nguyên tắc an toàn trước hết - hư hỏng liên quan lốp, dầu mỡ, nhíp, bồn/van, điện thì chọn "Đưa vào xưởng". Không chắc chắn thì liên hệ Kỹ thuật trước khi quyết định; chuyến vẫn được giữ an toàn trên hệ thống.

**Hỏi: Xe có CỜ BẤT THƯỜNG (lệch ODO > 20 km) thì xử lý sao?**
Đáp: Vào Kiểm tra xe, xem ảnh táp lô/ODO mới nhất, đối chiếu lịch sử chuyến. Ảnh mờ/sai thì từ chối và yêu cầu chụp lại kèm ghi chú; số km thật sự tăng bất thường thì treo xe và báo Kỹ thuật.

**Hỏi: Tạo đơn mà không chọn được xe nào?**
Đáp: Danh sách gợi ý chỉ gồm xe **rảnh + đã duyệt 5 ảnh trong ngày**. Nếu trống: (1) duyệt nốt các bộ 5 ảnh đang chờ, hoặc (2) xe đang chạy đơn khác - chờ hoàn tất, hoặc (3) xe chưa được gán tài xế - liên hệ Admin/Quản lý gán xe - tài xế.

**Hỏi: Tôi quên nhận ca, cuối ca muốn bàn giao thì làm sao?**
Đáp: Vẫn vào khối "Điều phối viên Đang trực ca" bấm **Nhận ca trực** rồi ngay lập tức **Bàn giao ca trực & Kết thúc** kèm ghi chú, để nhật ký ca trực đầy đủ. Trường hợp quên đăng xuất hoàn toàn, Admin có thể đóng ca giúp.

**Hỏi: Nhiều điều phối viên cùng ca có sao không?**
Đáp: Không. Hệ thống **cho phép nhiều điều phối viên cùng nhận ca và đồng hành trực tuyến**; mỗi người vẫn nhận ca bằng tài khoản riêng để lịch sử minh bạch.

**Hỏi: Quên mật khẩu?**
Đáp: Liên hệ Admin (Duy IT) để đặt lại mật khẩu mặc định `123456`, sau đó đăng nhập và đổi lại ngay.

---

## 10. LIÊN HỆ HỖ TRỢ

| Vấn đề | Người hỗ trợ |
|---|---|
| Lỗi ứng dụng, tài khoản, mật khẩu, cấu hình AI | **Duy IT** (Admin) |
| Nghiệp vụ chuyến hàng, xử lý báo hỏng, đổi xe | Điều phối trực ca tiếp theo (qua ghi chú bàn giao ca) |
| Hư hỏng xe, quyết định kỹ thuật | Bộ phận Kỹ thuật |
| Quy định chung | Quản lý / Ban Giám đốc: Cao Sông Lam (0989077998), Ngô Thị Kiều Oanh (0969845554) |

---

*Lưu ý: Tài liệu này biên soạn theo đặc tả `Dac_ta_app_tai_xe_Flutter.docx` và tên nhãn thực tế trong mã nguồn `app_tai_xe`. Khi ứng dụng cập nhật giao diện, tài liệu sẽ được rà soát và chỉnh sửa kịp thời.*
