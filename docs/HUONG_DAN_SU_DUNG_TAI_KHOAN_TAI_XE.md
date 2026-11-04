# HƯỚNG DẪN SỬ DỤNG DÀNH CHO TÀI KHOẢN TÀI XẾ
## Hệ thống Quản lý Vận tải & App Vận tải VinTrans

- **Phạm vi áp dụng**: 22 tài khoản tài xế xe nội bộ (loại hình Tài xế nhà tự chở - Nội bộ).
- **Nguồn đối chiếu**: tài liệu đặc tả `Dac_ta_app_tai_xe_Flutter.docx` (bản 2, ngày 10/10/2026), danh sách tài khoản `DANH_SACH_TAI_KHOAN_VA_MAT_KHAU.md`, mã nguồn app `app_tai_xe`.
- **Phiên bản tài liệu**: 1.0 - Ngày 30/10/2026.

---

## 1. TỔNG QUAN

Ứng dụng **SaoMai Tài xế** giúp tài xế thực hiện 4 nhóm công việc chính ngay trên điện thoại:

1. **Kiểm tra xe đầu ngày**: chụp đủ 5 ảnh kiểm tra xe theo khung mẫu để được duyệt nhận chuyến.
2. **Vận hành chuyến hàng**: chụp ảnh trước khi bơm, phiếu cân, ảnh đến điểm giao, phiếu giao hàng theo đúng 4 bước mốc giờ.
3. **Theo dõi công việc**: xem lịch trình xe, đơn hàng đã vận chuyển, hình chụp xe các ca.
4. **Báo hỏng**: báo cáo sự cố xe kèm ảnh cận cảnh cho điều phối và kỹ thuật.

> **Nguyên tắc quan trọng**: Xe chỉ được nhận chuyến và chạy khi đã có bộ 5 ảnh kiểm tra trong ngày VÀ điều phối đã bấm duyệt. Tài xế vi phạm (chạy xe khi chưa đủ 5 ảnh) sẽ bị hệ thống ghi nhận và ảnh hưởng phụ cấp tuân thủ tháng.

---

## 2. ĐĂNG NHẬP HỆ THỐNG

### 2.1. Các bước đăng nhập
1. Mở ứng dụng **SaoMai Tài xế** trên điện thoại (Android) hoặc máy tính (bản Windows/Linux).
2. Tại màn hình Đăng nhập, nhập **Tên đăng nhập** và **Mật khẩu**.
3. Bấm nút **Đăng nhập**.
4. Sau khi đăng nhập thành công, hệ thống đưa thẳng vào mục **Lịch trình xe** (theo dõi chuyến đi và mốc giờ của xe mình).

### 2.2. Danh sách tài khoản tài xế (mật khẩu mặc định: 123456)

| STT | Họ và Tên | Tên đăng nhập | Số điện thoại | Số xe (đầu kéo) | Số mooc |
|:---:|:---|:---|:---:|:---:|:---:|
| 1 | Kim Vết | taixe_kimvet | 0787825959 | 50H-449.66 | 50RM02927 |
| 2 | Nguyễn Văn Thảo | taixe_nguyenvanthao | 0972840341 | 50H-446.76 | 50RM03249 |
| 3 | Nguyễn Đình Lâm | taixe_nguyendinhlam | 0943765579 | 50H-457.21 | 50RM06757 |
| 4 | Trịnh Trung Đấu | taixe_trinhtrungdau | 0978784665 | 50H-914.39 | 50RM15623 |
| 5 | Bùi Văn Phong | taixe_buivanphong | 0853996963 | 50E-889.50 | 50RM-23607 |
| 6 | Nguyễn Viết Duy | taixe_nguyenvietduy | 0376977780 | 50H-540.41 | 50RM03696 |
| 7 | Ngô Tiến Đủ | taixe_ngotiendu | 0919541172 | 50H-538.61 | 50RM03898 |
| 8 | Đoàn Hoàng Anh | taixe_doanhoanganh | 0798482479 | 50E-329.52 | 50RM22993 |
| 9 | Vũ Tuấn Dương | taixe_vutuanduong | 0979319559 | 50H-919.49 | 50RM03075 |
| 10 | Lê Văn Tùng | taixe_levantung | 0877725078 | 50H-882.60 | 50RM10642 |
| 11 | Lê Văn Lương | taixe_levanluong | 0989463417 | 50E-480.24 | 50RM13758 |
| 12 | Tô Vân Sơn | taixe_tovanson | 0978199728 | 50H-900.32 | 50RM15117 |
| 13 | Phan Châu Khoa | taixe_phanchaukhoa | 0965551237 | 50E-147.73 | 50RM15113 |
| 14 | Nguyễn Thái Sơn | taixe_nguyenthaison | 0917970102 | 50H-162.27 | 50RM15112 |
| 15 | Nguyễn Ngọc Thiên | taixe_nguyenngocthien | 0965551237 | 50E-151.64 | 50RM15115 |
| 16 | Lê Văn Tuyến | taixe_levantuyen | 0899860400 | 51D-477.61 | 50RM-23606 |
| 17 | Lê Hoàng Hải | taixe_lehoanghai | 0858229225 | 51D-477.41 | 50RM-23605 |
| 18 | Kiều Thành Nghĩa | taixe_kieuthanhnghia | 0948518283 | 50H-891.21 | 50RM11007 |
| 19 | Đinh Mậu Quang | taixe_dinhmauquang | 0908207809 | 50E-477.23 | 50RM13757 |
| 20 | Nguyễn Văn Ngọc | taixe_nguyenvanngoc | 0386000448 | 50H-919.51 | 50RM06827 |
| 21 | Thái Thanh Sơn | taixe_thaithanhson | 0377121579 | 50E-074.57 | 50RM22994 |
| 22 | Nguyễn Văn Cường | taixe_nguyenvancuong | 0967792619 | 50E-075.43 | 50RM23073 |

### 2.3. Lưu ý khi đăng nhập
- Đăng nhập chỉ dùng **Tên đăng nhập** (không dùng số điện thoại).
- Khi đăng nhập, tài xế cần **chọn xe** đang phụ trách (mặc định là xe thường trực theo danh sách trên; nếu đổi xe phải chọn lại và chụp lại bộ 5 ảnh cho xe mới).
- Nên **đổi mật khẩu ngay sau lần đăng nhập đầu tiên** để bảo mật (thông báo cho quản trị IT nếu cần hỗ trợ).
- Không chia sẻ tài khoản cho người khác; mọi thao tác chụp ảnh, ghi giờ đều gắn mã tài xế và mã thiết bị.

---

## 3. GIAO DIỆN CHÍNH VÀ MENU DÀNH CHO TÀI XẾ

Sau khi đăng nhập, mở menu (biểu tượng ba gạch ở góc) sẽ thấy nhóm mục **DÀNH CHO TÀI XẾ** gồm:

| Mục | Chức năng |
|:---|:---|
| **Lịch trình xe** | Theo dõi chuyến đi, mốc giờ và thực hiện 4 bước chụp hình chuyến (Trước bơm, Phiếu cân, Đến điểm giao, Phiếu giao hàng). |
| **Đơn hàng** | Xem các đơn hàng xe đã vận chuyển, trạng thái từng đơn. |
| **Hình chụp xe** | Xem lại 5 ảnh kiểm tra xe các ca, lịch sử kiểm tra đầu ngày. |

Nút **Đăng xuất tài khoản** nằm ở chân menu; bấm để thoát tài khoản khi trả xe hoặc giao máy cho người khác.

---

## 4. KIỂM TRA XE ĐẦU NGÀY (BỘ 5 ẢNH)

### 4.1. Vì sao phải chụp
- Xe **chỉ được nhận chuyến khi đã có bộ 5 ảnh kiểm tra trong ngày**.
- Hệ thống đối chiếu ảnh hôm nay với ảnh cùng góc, cùng xe của ngày gần nhất để phát hiện sự cố: vệt ướt dưới gầm, khác biệt vùng lốp, vật thể lạ.
- Ảnh 5 (táp lô) được OCR đọc số km; số km này dùng để đối soát km GPS ngày trước (lệch trên 20 km sẽ gắn cờ).

### 4.2. Các bước thực hiện
1. Vào mục **Kiểm tra xe**, chọn đúng xe của mình (mặc định xe thường trực).
2. Bấm bắt đầu kiểm tra, màn hình camera hiện ra với **khung mẫu mờ (overlay)** theo loại xe (Howo, Shacman, Daewoo).
3. Chụp lần lượt **5 vị trí theo thứ tự cố định**:

   | Bước | Vị trí chụp | Ghi chú |
   |:---:|:---|:---|
   | 1 | **Gầm trước** (Cản và Trục lái) | Flash tự bật mặc định |
   | 2 | **Gầm sau** (Bầu vi sai) | Flash tự bật mặc định |
   | 3 | **Hông trái** (Lốp và Bồn) | Chụp đủ thấy lốp |
   | 4 | **Hông phải** (Bình dầu và Lốp) | Chụp đủ thấy lốp |
   | 5 | **Táp lô và Đồng hồ ODO** | Hệ thống OCR đọc số km, tài xế kiểm tra và xác nhận/sửa lại nếu sai |

4. Mỗi ảnh được tự động gắn: giờ máy (UTC+7), tọa độ GPS, độ chính xác GPS, biển số, mã tài xế, mã thiết bị và đóng dấu watermark.
5. Đủ 5 ảnh, trạng thái xe chuyển thành **Đã kiểm tra đầu ngày** và gửi cho điều phối duyệt.

### 4.3. Quy định về ảnh
- **Chỉ dùng camera trong app**, không được chọn ảnh từ thư viện điện thoại.
- Ảnh 1-2 bật flash mặc định (có thể tự bật/tắt, hệ thống ghi nhớ lựa chọn của tài xế).
- Ảnh quá tối, quá mờ hoặc **không có bánh xe trong khung**: hệ thống yêu cầu chụp lại.
- Ảnh được nén dưới 300 KB trước khi gửi; lưu trữ 12 tháng.

### 4.4. Nếu xe bị hỏng (Báo hỏng)
1. Bấm nút **Báo hỏng** (có ở mọi bước kiểm tra).
2. Chọn hạng mục hỏng: **Lốp xe / Rò rỉ dầu mỡ / Hệ thống nhíp / Bồn chứa, van xả / Điện / Khác**.
3. Chụp thêm ảnh cận cảnh vị trí hỏng, mô tả ngắn gọn (ví dụ: "Lốp sau nứt rách sâu").
4. Gửi đi: thông báo tự chuyển tới **điều phối và kỹ thuật**.
5. Chuyến đi bị giữ lại đến khi điều phối bấm **Cho chạy** hoặc **Đưa vào xưởng**.

---

## 5. VẬN HÀNH CHUYẾN HÀNG (4 BƯỚC MỐC GIỜ)

Vào mục **Lịch trình xe**, chọn đơn hàng đang chạy và thực hiện 4 bước chụp hình. **4 bước độc lập, không khóa chéo tuần tự**: tài xế chụp được bước nào chụp bước đó, nhưng phải đủ cả 4 bước trước khi hoàn tất chuyến.

| Bước | Tên bước | Khi nào chụp | Nút bấm |
|:---:|:---|:---|:---|
| 1 | **Chụp ảnh TRƯỚC KHI BƠM** | Chụp đồng hồ/vòi bơm **trước khi bơm** tại nơi nhận hàng | Trước bơm |
| 2 | **Chụp và Gửi Phiếu Cân** | Chụp phiếu cân **tại nơi nhận hàng**; hệ thống OCR đọc khối lượng và mã lệnh, tự đồng bộ Zalo OA | Cân |
| 3 | **Chụp ảnh ĐẾN ĐIỂM GIAO** | Chụp hiện trạng xe **khi vừa đến điểm giao hàng** | Đến giao |
| 4 | **Chụp và Gửi Phiếu Giao Hàng** | Chụp biên bản giao nhận hàng **sau khi giao xong**; tự động gửi vào nhóm Zalo khách hàng | Giao |

### 5.1. Quy định giờ và GPS
- Mỗi lần bấm, hệ thống tự ghi **giờ máy + tọa độ GPS** vào đúng mã lệnh lấy hàng; điều phối không phải gõ tay.
- Bước 3 (Đến giao): nếu GPS cách điểm giao **trên 2 km**, hệ thống hỏi xác nhận trước khi ghi nhận.
- Bước 2 (Phiếu cân): nếu thời gian từ Đến điểm giao đến Bơm xong **vượt 120 phút**, hệ thống bắt chọn nguyên nhân chờ từ danh mục.

### 5.2. Nhắc nhở tự động (tài xế cần lưu ý)
Hệ thống chạy nền và tự nhắc tài xế qua thông báo đẩy, điều phối không phải nhắc tay:

| Tình huống | Hệ thống phản hồi |
|:---|:---|
| Xe nổ máy / di chuyển quá 500 m mà **chưa đủ 5 ảnh** | Thông báo ngay, ghi 1 lần vi phạm "chạy chưa kiểm tra", báo điều phối ca trực |
| Dừng trong vùng điểm giao **15 phút** chưa bấm Đến giao | Nhắc lần 1 |
| Dừng trong vùng điểm giao **30 phút** chưa bấm Đến giao | Nhắc lần 2, hiện trên màn hình điều phối |
| Đã Đến giao **quá 120 phút** chưa Bơm xong | Nhắc chọn nguyên nhân chờ; quá 240 phút báo điều phối và trưởng BP |
| **60 phút sau giờ cân** chưa gửi phiếu cân | Nhắc tài xế |
| Đến thời điểm giao ca **19h và 07h** | Gộp mọi khoản còn thiếu thành 1 thông báo cho từng tài xế |
| Không phản hồi sau **2 lần nhắc** | Tự tạo sự cố "Tài xế không liên lạc được", điều phối trực ca xử lý |

---

## 6. THEO DÕI CÔNG VIỆC

### 6.1. Lịch trình xe
- Hiển thị mã lệnh (Mã lấy hàng), điểm giao khách hàng, nhà máy/trạm, sản phẩm (Tro bay, Xi măng rời, Xi măng bao, Phụ gia bê tông,...), khối lượng tấn.
- Xem trạng thái từng bước 1-4 đã chụp hay chưa, giờ đã ghi.

### 6.2. Đơn hàng
- Xem danh sách các đơn xe đã vận chuyển với trạng thái: **Đã phân công / Đang vận chuyển / Hoàn thành / Đã hủy**.
- Thông tin đơn: mã đơn, khách hàng, sản phẩm, khối lượng, điểm nhận - điểm giao, ảnh đính kèm.

### 6.3. Hình chụp xe
- Xem lại 5 ảnh kiểm tra đầu ngày theo từng ca, số km táp-lô đã xác nhận.

---

## 7. BÁO CÁO TUÂN THỦ VÀ PHỤ CẤP (TÀI XẾ CẦN BIẾT)

Cuối tháng, hệ thống thống kê theo từng tài xế:

- **Tỷ lệ ngày đủ 5 ảnh** trong tháng.
- Số lần bị nhắc, số lần "chạy chưa kiểm tra".
- **Mức phụ cấp tuân thủ theo tháng**: đủ 5 ảnh đầy đủ nhận 100%, thiếu một phần nhận 50%, vi phạm nhiều nhận 0%.

> Vì vậy, tài xế hãy hình thành thói quen: **Sáng mở app chụp đủ 5 ảnh trước khi nổ máy**, trong hành trình chụp đủ 4 bước mốc giờ ngay tại hiện trường.

---

## 8. CÂU HỎI THƯỜNG GẶP (FAQ)

**Hỏi: Chụp ảnh bị báo quá tối / quá mờ, phải làm sao?**
Đáp: Kiểm tra flash đã bật chưa (2 bước đầu mặc định bật), chụp lại ở nơi đủ sáng, đảm bảo khung mẫu chứa đủ bánh xe và không rung tay.

**Hỏi: Đã chụp đủ 5 ảnh nhưng vẫn chưa nhận được chuyến?**
Đáp: Bộ 5 ảnh phải được **điều phối duyệt** thì xe mới đủ điều kiện chạy. Liên hệ điều phối trực ca nếu quá lâu chưa được duyệt.

**Hỏi: OCR đọc sai số km trên táp lô?**
Đáp: Tại bước 5, tài xế được phép **xác nhận hoặc sửa lại** số km trước khi hoàn tất. Hãy đối chiếu kỹ đồng hồ ODO.

**Hỏi: Đổi xe mới thì làm sao?**
Đáp: Vào mục Kiểm tra xe, chọn lại xe; **phải chụp lại toàn bộ 5 ảnh** cho xe mới trước khi nhận chuyến.

**Hỏi: Quên mật khẩu?**
Đáp: Liên hệ quản trị IT (tài khoản admin) hoặc điều phối để được cấp lại mật khẩu mặc định `123456`, sau đó đổi mật khẩu mới ngay.

**Hỏi: Mất mạng 3G/4G khi ở hiện trường?**
Đáp: Vẫn chụp bình thường; giờ máy tài xế dùng khi offline và được hệ thống đánh dấu riêng, ảnh sẽ tự gửi khi có mạng trở lại.

---

## 9. LIÊN HỆ HỖ TRỢ

- **Vấn đề tài khoản, đăng nhập**: Quản trị IT (Duy IT - tài khoản `admin`).
- **Vấn đề chuyến hàng, duyệt chuyến, nguyên nhân chờ**: Điều phối trực ca (Ca ngày 07:00-19:00, Ca đêm 19:00-07:00).
- **Vấn đề kỹ thuật xe, sửa chữa**: Bộ phận Kỹ thuật (AZG/kho) qua chức năng Báo hỏng trong app.
