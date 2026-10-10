# QUY CHUẨN THIẾT KẾ VÀ PHONG CÁCH GIAO DIỆN (UI/UX STYLE GUIDE)
HỆ THỐNG QUẢN LÝ ĐIỀU PHỐI VẬN TẢI & TÀI XẾ SAO MAI

Tài liệu này xác lập các tiêu chuẩn kỹ thuật thiết kế giao diện (UI) và trải nghiệm người dùng (UX) áp dụng cho ứng dụng Flutter Client (Desktop Linux & Mobile) thuộc dự án Taxi/Sao Mai Logistics.

---

## 1. HỆ THỐNG BO GÓC (BORDER RADIUS)

- **Quy chuẩn bắt buộc**: Áp dụng chuẩn `rounded-sm` (bán kính `BorderRadius.circular(4)` hoặc `4px`) đồng bộ cho toàn bộ hệ thống.
- **Phạm vi áp dụng**:
  - Hộp thoại cảnh báo, xác nhận, biểu mẫu: `Dialog`, `AlertDialog`.
  - Khối nội dung, thẻ tóm tắt: `Card`, `Container`.
  - Nút bấm: `ElevatedButton`, `OutlinedButton`, `TextButton`.
  - Ô nhập liệu và danh sách chọn: `TextField`, `TextFormField`, `DropdownButtonFormField`.
  - Nhãn hiển thị trạng thái: Tag trạng thái vai trò, loại đối tượng, loại đơn hàng.
- **Tuyệt đối không dùng**: Bán kính bo góc lớn theo phong cách bo tròn điện thoại (`12px`, `16px`, `24px` hoặc `StadiumBorder`) trên ứng dụng quản trị điều hành máy tính để bàn.

---

## 2. QUY CHUẨN CHIỀU CAO VÀ KÍCH THƯỚC (HEIGHT & SIZING)

### 2.1. Thành phần nhập liệu (Input & Select)
- **Chiều cao chuẩn chính**: `44px`.
- **Cấu hình Theme (`InputDecorationTheme`)**:
  - `isDense: true`
  - `contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 11)`
  - `prefixIconConstraints: BoxConstraints(minWidth: 40, minHeight: 44, maxHeight: 44)`
  - `suffixIconConstraints: BoxConstraints(minWidth: 40, minHeight: 44, maxHeight: 44)`
- **Mục đích & Lưu ý kỹ thuật**:
  - Khóa chặn việc biểu tượng (`prefixIcon` / `suffixIcon`) tự động kéo dãn chiều cao của `TextField` vượt mức cho phép.
  - Đối với `DropdownButtonFormField`: Để chiều cao tính toán tự nhiên theo `InputDecorationTheme`. Tuyệt đối không bọc cứng bằng `SizedBox(height: 44)` kèm `contentPadding: EdgeInsets.symmetric(vertical: 0)` vì cơ chế căn chỉnh nhãn nổi (`floatingLabel`) và mũi tên xổ xuống sẽ bị nén nghẹt (xẹp) khung hiển thị.

### 2.2. Nút bấm (Button Hierarchy)
- **Nút hành động chính (Primary Action Button)**:
  - Ví dụ: "Lưu thay đổi", "Tạo tài khoản", "Xác nhận", "Đăng nhập".
  - Chiều cao: `44px` (`minimumSize: Size(64, 44)`).
  - Cỡ chữ: `14px`, `FontWeight.bold`.
  - Màu nền: `Colors.blue.shade800` hoặc màu thương hiệu chủ đạo.
- **Nút hành động phụ / Nút nội dòng (Secondary / Inline Form Button)**:
  - Ví dụ: Nút "Chọn & Tải lên" cạnh ô nhập URL ảnh, nút "Duyệt tệp".
  - Chiều cao: Nhỏ hơn hoặc bằng `38px` (`SizedBox(height: 38)`).
  - Cấu hình bắt buộc: `minimumSize: Size.zero`, `tapTargetSize: MaterialTapTargetSize.shrinkWrap`, `padding: EdgeInsets.symmetric(horizontal: 12)`.
  - Cỡ chữ: `12px` - `13px`, `FontWeight.w600`.
  - Mục đích: Không lấn át thị giác và kích thước của nút hành động chính của toàn bộ form hoặc dialog.

---

## 3. BỐ CỤC ĐIỀU HƯỚNG VÀ VỊ TRÍ ĐẶT THÀNH PHẦN (LAYOUT & POSITIONING)

### 3.1. Thanh điều hướng Tab phụ (Sub-navigation Tabs)
- **Vị trí bắt buộc**: Đặt cố định ở khu vực đáy (Footer) của khung hiển thị nội dung phân mục.
- **Cấu trúc kỹ thuật**:
  - Phần hiển thị dữ liệu bảng biểu/danh sách (`TabBarView`) bọc trong `Expanded` chiếm trọn không gian phía trên.
  - Khối `TabBar` được bọc bên trong một `Container` đặt ở cuối `Column`.
  - Khối `Container` chân trang phải có đường viền trên (`Border(top: BorderSide(color: Colors.grey.shade300, width: 1))`) và đổ bóng nhẹ ngược lên trên để ngăn cách trực quan với bảng dữ liệu.

### 3.2. Cấu trúc Sidebar điều hướng chính
- **Khu vực chân Sidebar (Sidebar Footer)** cố định theo thứ tự từ trên xuống dưới:
  1. Tên doanh nghiệp: "Công ty CP TM Xi Măng Sao Mai" (dạng văn bản thuần, không viền khung).
  2. Thông tin phiên bản hệ thống: "Phiên bản hệ thống v1.0.0 (Bản quyền thuộc Sao Mai Group)" (màu ghi xám `Colors.grey.shade500`, cỡ chữ nhỏ `11px`).
  3. Nút Đăng xuất tài khoản.

### 3.3. Đường viền dưới thanh tiêu đề Header (Header Border Bottom)
- **Quy chuẩn bắt buộc**: Thanh `AppBar` hiển thị tiêu đề các phân hệ quản lý (như "Tổng Quan & Báo Cáo Tuân Thủ", "Quản Lý Đơn Hàng Vận Tải", ...) bắt buộc phải có đường kẻ viền dưới `bottom: PreferredSize(preferredSize: Size.fromHeight(1), child: Container(color: Colors.grey.shade300, height: 1))`.
- **Mục đích**: Phân tách dứt khoát khu vực nhận diện phân hệ với không gian hiển thị nội dung và bộ lọc dữ liệu bên dưới, tạo độ ngăn nắp chuyên nghiệp trên màn hình quản trị desktop.

### 3.4. Thanh điều hướng phân trang (Pagination Bar)
- **Vị trí bắt buộc**: Đặt cố định ở cuối danh sách (ngay trên thanh Tab footer nếu có), bọc trong `Container(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade300, width: 1)))`.
- **Cấu phần tiêu chuẩn**:
  - Bên trái: Văn bản thống kê trạng thái hiển thị (`Hiển thị X - Y trên tổng số Z bản ghi`).
  - Bên phải:
    - Dropdown chọn số dòng trên một trang: `5`, `10`, `20`, `50` dòng/trang (mặc định là `10`).
    - Nút chuyển đến Trang đầu (`Icons.first_page`) và Trang trước (`Icons.chevron_left`).
    - Hộp hiển thị số trang hiện hành: `Trang hiện_tại / tổng_số_trang` (`color: Colors.blue.shade50`, chữ đậm màu `blue.shade800`).
    - Nút chuyển đến Trang sau (`Icons.chevron_right`) và Trang cuối (`Icons.last_page`).
  - Khi thay đổi từ khóa tìm kiếm hoặc bộ lọc: Tự động đưa trang hiện hành trở về `Trang 1`.

---

## 4. TƯƠNG TÁC CHUỘT VÀ TRẠNG THÁI (HOVER & FOCUS STATES)

- **Các khối danh sách chuyển đổi (Switch / Checkbox / Radio List Tile)**:
  - Thiết lập `hoverColor: Colors.transparent`.
  - Không để lại mảng màu xám chữ nhật khi rê con trỏ chuột qua khu vực chữ của Switch/Checkbox trong Dialog hoặc Form nhập liệu.
- **Con trỏ chuột (Mouse Cursor)**:
  - Tự động hiển thị `SystemMouseCursors.click` khi rê vào bất kỳ nút bấm, mục tab hoặc switch có thể tương tác.

---

## 5. PHÂN BỔ MÀU SẮC (COLOR PALETTE)

- **Màu chủ đạo (Primary)**: `Colors.blue` (`seedColor`), các sắc thái `blue.shade700` đến `blue.shade800` cho nút chính và thanh điều hướng.
- **Màu nền trung tính (Neutral)**: `Colors.grey.shade50` đến `grey.shade200` cho nền bảng dữ liệu và đường viền phân tách.
- **Màu trạng thái cảnh báo/nguy hiểm (Danger)**: `Colors.red.shade700` cho các nút xác nhận xóa dữ liệu vĩnh viễn hoặc cảnh báo mất dữ liệu.
- **Màu trạng thái thành công/hoạt động (Success)**: `Colors.green.shade600` cho công tắc kích hoạt hoạt động (`is_active = true`) và thông báo hoàn tất thao tác.

---

## 6. DANH MỤC THAM CHIẾU MÃ NGUỒN LIÊN QUAN

- Cấu hình Theme tổng thể: `app_tai_xe/lib/main.dart` (ThemeData, InputDecorationTheme, ButtonThemeData, CardThemeData).
- Màn hình điều phối và quản trị: `app_tai_xe/lib/screens/dispatch_supervisor_screen.dart`.
- Quản trị dịch vụ máy chủ độc lập: `systemd --user` (`app-tai-xe.service`).
