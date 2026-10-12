# HƯỚNG DẪN TRIỂN KHAI VÀ VẬN HÀNH HỆ THỐNG BACKEND API
DỰ ÁN: HỆ THỐNG ĐIỀU HÀNH VẬN TẢI & TÀI XẾ SAO MAI

Tài liệu này hướng dẫn chi tiết cách cài đặt môi trường, cấu hình đóng gói toàn bộ Backend API cùng Cơ sở dữ liệu và triển khai lên máy chủ Ubuntu thông qua Docker Compose và Cloudflare Tunnel.

---

## 1. CÁC THÀNH PHẦN HỆ THỐNG CẦN CÀI ĐẶT

### 1.1. Yêu cầu môi trường máy chủ (Ubuntu Server 20.04 / 22.04 / 24.04 LTS)
Hệ thống được đóng gói hoàn toàn trong Docker, vì vậy máy chủ chỉ cần cài đặt các gói cơ sở sau:

- **Git**: Quản lý phiên bản và kéo mã nguồn.
- **Docker Engine** (phiên bản 24.0+): Nền tảng chạy container.
- **Docker Compose Plugin** (phiên bản v2+): Quản lý và liên kết các cụm container.
- **Cloudflared** (tùy chọn / khuyến nghị): Nhận tunnel đưa API ra Internet không cần mở cổng modem/router.

### 1.2. Lệnh cài đặt công cụ nền tảng trên Ubuntu

Chạy lần lượt các lệnh sau trên terminal của Ubuntu:

```bash
# 1. Cập nhật hệ thống
sudo apt update && sudo apt upgrade -y

# 2. Cài đặt các gói phụ trợ
sudo apt install -y curl wget git ufw

# 3. Cài đặt Docker chính thức từ script Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# 4. Phân quyền người dùng hiện tại chạy Docker không cần sudo
sudo usermod -aG docker $USER
newgrp docker

# 5. Kiểm tra phiên bản Docker & Docker Compose
docker --version
docker compose version
```

---

## 2. KIẾN TRÚC ĐÓNG GÓI HỆ THỐNG (DOCKER COMPOSE)

Cụm dịch vụ được định nghĩa trong tệp `docker-compose.yml` gồm 3 thành phần chính:

| Tên Dịch Vụ | Tên Container | Nền Tảng / Image | Cổng Nội Bộ | Cổng Mở Ra Máy Chủ | Mục Đích |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **postgres** | `taxi-postgres` | `postgis/postgis:15-3.4` | `5432` | `5432:5432` | Lưu trữ dữ liệu quan hệ, tọa độ GPS không gian (PostGIS), bảng kiểm tra 5 ảnh, đơn hàng, tài xế. |
| **redis** | `taxi-redis` | `redis:7-alpine` | `6379` | `6389:6379` | Lưu cache phiên làm việc và hỗ trợ xếp hàng xử lý. |
| **backend** | `taxi-backend-api` | Python 3.11 Slim (FastAPI) | `8000` | `1133:8000` | Cung cấp RESTful API, xác thực JWT, nhận upload ảnh và nghiệp vụ điều hành xe. |

Dữ liệu của Database và các tệp hình ảnh được bảo vệ an toàn vĩnh viễn nhờ các Docker Volume độc lập:
- `postgres_data`: Lưu dữ liệu bảng biểu PostgreSQL.
- `redis_data`: Lưu dữ liệu cache Redis.
- `uploads_data`: Lưu toàn bộ 5 ảnh kiểm tra xe tài xế gửi lên (`/app/uploads`).

---

## 3. CÁC BƯỚC KHỞI ĐỘNG VÀ VẬN HÀNH HỆ THỐNG

### 3.1. Khởi động toàn bộ hệ thống API & Database

Tại thư mục gốc dự án:
```bash
cd /home/yenai/Documents/Projects/Taxi
docker compose up -d --build
```

- Cờ `-d`: Chạy ngầm trong nền (daemon).
- Cờ `--build`: Tự động biên dịch lại mã nguồn Python mới nhất nếu có cập nhật.

### 3.2. Kiểm tra trạng thái hoạt động

```bash
# Xem danh sách container đang chạy
docker compose ps

# Xem log trực tiếp của API FastAPI
docker compose logs -f backend

# Kiểm tra phản hồi trực tiếp qua cổng 1133
curl -I http://localhost:1133/docs
```
Khi nhận được kết quả `HTTP/1.1 200 OK`, API đã sẵn sàng nhận kết nối.

### 3.3. Các lệnh bảo trì thường dùng

- **Khởi động lại toàn bộ**:
  ```bash
  docker compose restart
  ```
- **Tạm dừng hệ thống**:
  ```bash
  docker compose stop
  ```
- **Tắt và dỡ bỏ container (dữ liệu DB trong volume vẫn được giữ nguyên)**:
  ```bash
  docker compose down
  ```
- **Khởi động lại riêng API sau khi sửa mã nguồn trong backend**:
  ```bash
  docker compose restart backend
  ```

---

## 4. TÍCH HỢP CLOUDFLARE TUNNEL (DOMAIN CÔNG KHAI)

Hệ thống được thiết kế để nhận truy cập trực tiếp từ Cloudflare Tunnel qua cổng cục bộ `1133`.

### 4.1. Cấu hình Tunnel trên Cloudflare Zero Trust Dashboard

1. Truy cập: [Cloudflare Zero Trust](https://one.dash.cloudflare.com/) > **Networks** > **Tunnels**.
2. Chọn tunnel của bạn > **Configure** > tab **Public Hostnames**.
3. Thêm hoặc cập nhật bản ghi Public Hostname:
   - **Subdomain**: `api`
   - **Domain**: `saomai.type.vn`
   - **Path**: để trống
   - **Type**: `HTTP`
   - **URL**: `localhost:1133` (hoặc `127.0.0.1:1133`)
4. Cài đặt SSL/TLS trên Cloudflare Dashboard:
   - Truy cập **SSL/TLS** > chọn chế độ mã hóa **Full** hoặc **Flexible**.

### 4.2. Kiểm tra kết nối từ ngoài Internet

Mở trình duyệt bất kỳ hoặc chạy lệnh curl từ máy khác:
```bash
curl -I https://api.saomai.type.vn/docs
```
Giao diện Swagger tài liệu API sẽ hiển thị đầy đủ và cho phép thử nghiệm các endpoint xác thực, kiểm tra xe và đơn hàng.

---

## 5. CẤU HÌNH TRÊN ỨNG DỤNG FLUTTER CLIENT

Khi hệ thống API đã chạy trên domain tunnel `https://api.saomai.type.vn`, các ứng dụng Flutter Client (Mobile Android/iOS & Desktop Linux) sẽ trỏ về địa chỉ này trong các tệp dịch vụ:

1. **Dịch vụ xác thực**: `app_tai_xe/lib/services/auth_service.dart`:
   ```dart
   static const String baseUrl = 'https://api.saomai.type.vn/api/v1/auth';
   ```

2. **Dịch vụ điều phối & kiểm tra xe**: `app_tai_xe/lib/services/admin_service.dart`:
   ```dart
   static const String baseUrl = 'https://api.saomai.type.vn/api/v1';
   ```

Tất cả các cuộc gọi API từ app tài xế ngoài đường dùng 4G hoặc app điều phối văn phòng sẽ kết nối trực tiếp đến server thông qua tunnel bảo mật HTTPS.
