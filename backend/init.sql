-- Extension PostGIS cho xử lý địa lý và tọa độ GPS
CREATE EXTENSION IF NOT EXISTS postgis;

-- 1. Bảng Users (Bỏ role tĩnh, chuyển sang Dynamic RBAC)
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20) UNIQUE NOT NULL,
    driver_type VARCHAR(30) DEFAULT 'INTERNAL' CHECK (driver_type IN ('INTERNAL', 'RENTAL', 'CUSTOMER_SELF')),
    contractor_name VARCHAR(150),
    customer_name VARCHAR(150),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. Bảng Danh mục Roles (Vai trò động)
CREATE TABLE IF NOT EXISTS roles (
    id SERIAL PRIMARY KEY,
    code VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    is_system BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 3. Bảng Danh mục Permissions (Quyền hạt nhân động)
CREATE TABLE IF NOT EXISTS permissions (
    id SERIAL PRIMARY KEY,
    code VARCHAR(100) UNIQUE NOT NULL,
    module VARCHAR(50) NOT NULL,
    name VARCHAR(150) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 4. Bảng liên kết Role - Permission
CREATE TABLE IF NOT EXISTS role_permissions (
    role_id INT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id INT NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

-- 5. Bảng liên kết User - Role
CREATE TABLE IF NOT EXISTS user_roles (
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id INT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    assigned_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, role_id)
);

-- 6. Bảng Products (Quản lý sản phẩm: Tro bay, Xi măng rời, Xi măng bao...)
CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    code VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(150) NOT NULL,
    category VARCHAR(50) DEFAULT 'vat_lieu_xay_dung',
    unit VARCHAR(20) DEFAULT 'tan',
    standard_pump_time_minutes INT DEFAULT 90,
    density DOUBLE PRECISION,
    requires_air_pump BOOLEAN DEFAULT TRUE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 6b. Bảng Customers (Danh sách khách hàng)
CREATE TABLE IF NOT EXISTS customers (
    id SERIAL PRIMARY KEY,
    code VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    tax_code VARCHAR(50),
    contact_person VARCHAR(150),
    phone VARCHAR(30),
    email VARCHAR(150),
    address TEXT,
    note TEXT,
    source VARCHAR(20) DEFAULT 'manual',
    zalo_user_id VARCHAR(64),
    zalo_display_name VARCHAR(255),
    zalo_avatar TEXT,
    zalo_synced_at TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
-- Mỗi khách hàng Zalo OA có 1 ID riêng, không trùng
CREATE UNIQUE INDEX IF NOT EXISTS ux_customers_zalo_user_id ON customers(zalo_user_id) WHERE zalo_user_id IS NOT NULL;

-- 6c. Token Zalo OA (chỉ 1 dòng) và mã state OAuth tạm thời
CREATE TABLE IF NOT EXISTS zalo_oa_tokens (
    id INT PRIMARY KEY DEFAULT 1,
    oa_id VARCHAR(64),
    access_token TEXT NOT NULL,
    refresh_token TEXT NOT NULL,
    access_expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    refresh_expires_at TIMESTAMP WITH TIME ZONE,
    authorized_by VARCHAR(100),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CHECK (id = 1)
);
CREATE TABLE IF NOT EXISTS zalo_oa_oauth_states (
    state VARCHAR(100) PRIMARY KEY,
    code_verifier VARCHAR(200) NOT NULL,
    created_by VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 7. Bảng Vehicles (Danh mục phương tiện)
CREATE TABLE IF NOT EXISTS vehicles (
    plate_number VARCHAR(20) PRIMARY KEY,
    vehicle_type VARCHAR(50) NOT NULL,
    ownership_type VARCHAR(30) DEFAULT 'INTERNAL' CHECK (ownership_type IN ('INTERNAL', 'RENTAL', 'CUSTOMER_SELF')),
    owner_company VARCHAR(150),
    default_driver_id INT REFERENCES users(id),
    status VARCHAR(30) DEFAULT 'ready',
    last_gps_lat DOUBLE PRECISION,
    last_gps_lng DOUBLE PRECISION,
    last_gps_time TIMESTAMP WITH TIME ZONE,
    gps_provider VARCHAR(30),
    gps_vehicle_id VARCHAR(50),
    gps_driver_name VARCHAR(150),
    in_fleet BOOLEAN DEFAULT TRUE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
-- Mỗi phương tiện đi kèm đúng 1 tài khoản Tài xế (một tài xế không gắn với 2 xe)
CREATE UNIQUE INDEX IF NOT EXISTS uq_vehicles_default_driver ON vehicles(default_driver_id) WHERE default_driver_id IS NOT NULL;

-- 8. Bảng Gas Stations (Cây dầu hợp đồng)
CREATE TABLE IF NOT EXISTS gas_stations (
    id SERIAL PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    address TEXT NOT NULL,
    lat DOUBLE PRECISION NOT NULL,
    lng DOUBLE PRECISION NOT NULL,
    allowed_radius_meters INT DEFAULT 500,
    user_id INT REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 9. Bảng Orders (Đơn hàng và chuyến hàng)
CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    order_code VARCHAR(50) UNIQUE NOT NULL,
    factory_code VARCHAR(50) NOT NULL,
    product_id INT REFERENCES products(id),
    transport_type VARCHAR(30) DEFAULT 'INTERNAL' CHECK (transport_type IN ('INTERNAL', 'RENTAL', 'CUSTOMER_SELF')),
    customer_group_id VARCHAR(100),
    pickup_address TEXT NOT NULL,
    pickup_lat DOUBLE PRECISION,
    pickup_lng DOUBLE PRECISION,
    delivery_address TEXT NOT NULL,
    delivery_lat DOUBLE PRECISION,
    delivery_lng DOUBLE PRECISION,
    assigned_vehicle_plate VARCHAR(20) REFERENCES vehicles(plate_number),
    assigned_driver_id INT REFERENCES users(id),
    cargo_weight_tons DOUBLE PRECISION,
    status VARCHAR(30) DEFAULT 'assigned',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 10. Bảng KiemTraDauNgay (Kiểm tra xe 5 ảnh)
CREATE TABLE IF NOT EXISTS kiem_tra_dau_ngay (
    id SERIAL PRIMARY KEY,
    check_date DATE NOT NULL,
    plate_number VARCHAR(20) REFERENCES vehicles(plate_number),
    driver_id INT REFERENCES users(id),
    completed_at TIMESTAMP WITH TIME ZONE,
    img_front_underbody TEXT NOT NULL,
    img_rear_underbody TEXT NOT NULL,
    img_left_side TEXT NOT NULL,
    img_right_side TEXT NOT NULL,
    img_dashboard TEXT NOT NULL,
    gps_lat DOUBLE PRECISION,
    gps_lng DOUBLE PRECISION,
    gps_accuracy DOUBLE PRECISION,
    device_id VARCHAR(100),
    km_ocr DOUBLE PRECISION,
    km_confirmed DOUBLE PRECISION,
    flag_deviation_km BOOLEAN DEFAULT FALSE,
    has_abnormal_flag BOOLEAN DEFAULT FALSE,
    flag_reason TEXT,
    flag_status VARCHAR(30) DEFAULT 'none',
    flag_resolved_by INT REFERENCES users(id),
    flag_resolved_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 10b. Cột ảnh chứng từ & tọa độ GPS lúc chụp (2 ảnh bơm hàng do Tài xế chụp, phiếu cân, phiếu giao hàng, báo hỏng, sửa chữa, 5 ảnh kiểm tra xe)
ALTER TABLE orders ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pump_slip_before_photo_url TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pump_slip_before_time TIMESTAMP WITH TIME ZONE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pump_slip_before_by VARCHAR(150);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pump_slip_before_note TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pump_slip_photo_url TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pump_slip_time TIMESTAMP WITH TIME ZONE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pump_slip_by VARCHAR(150);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pump_slip_note TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS weigh_slip_photo_url TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS weigh_slip_time TIMESTAMP WITH TIME ZONE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS weigh_slip_tonnage DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS weigh_slip_code VARCHAR(100);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_slip_photo_url TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_slip_time TIMESTAMP WITH TIME ZONE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_slip_note TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS has_breakdown BOOLEAN DEFAULT FALSE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS breakdown_status VARCHAR(30);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS breakdown_photo_url TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS breakdown_reason TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS breakdown_location TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS breakdown_time TIMESTAMP WITH TIME ZONE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS breakdown_reported_by VARCHAR(150);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS repair_photo_url TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS repair_status VARCHAR(30);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS repair_note TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS repair_time TIMESTAMP WITH TIME ZONE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS repair_by VARCHAR(150);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pump_slip_before_gps_lat DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pump_slip_before_gps_lng DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pump_slip_before_gps_accuracy DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pump_slip_before_gps_captured_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pump_slip_gps_lat DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pump_slip_gps_lng DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pump_slip_gps_accuracy DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pump_slip_gps_captured_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS weigh_slip_gps_lat DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS weigh_slip_gps_lng DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS weigh_slip_gps_accuracy DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS weigh_slip_gps_captured_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_slip_gps_lat DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_slip_gps_lng DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_slip_gps_accuracy DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_slip_gps_captured_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS breakdown_gps_lat DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS breakdown_gps_lng DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS breakdown_gps_accuracy DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS breakdown_gps_captured_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS repair_gps_lat DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS repair_gps_lng DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS repair_gps_accuracy DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS repair_gps_captured_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE kiem_tra_dau_ngay ADD COLUMN IF NOT EXISTS photo_gps JSONB;

-- 11. Bảng CapDau (Vai trò Cây Dầu)
CREATE TABLE IF NOT EXISTS cap_dau (
    id SERIAL PRIMARY KEY,
    order_id INT REFERENCES orders(id),
    plate_number VARCHAR(20) REFERENCES vehicles(plate_number),
    driver_id INT REFERENCES users(id),
    gas_station_id INT REFERENCES gas_stations(id),
    fuel_type VARCHAR(20) DEFAULT 'diesel',
    liters_ocr DOUBLE PRECISION,
    liters_actual DOUBLE PRECISION NOT NULL,
    img_meter TEXT NOT NULL,
    img_receipt TEXT,
    gps_lat DOUBLE PRECISION NOT NULL,
    gps_lng DOUBLE PRECISION NOT NULL,
    flag_location_mismatch BOOLEAN DEFAULT FALSE,
    flag_quota_exceeded BOOLEAN DEFAULT FALSE,
    approval_status VARCHAR(20) DEFAULT 'approved',
    approved_by INT REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 12. Bảng MocChuyen (Mốc giờ chuyến)
CREATE TABLE IF NOT EXISTS moc_chuyen (
    id SERIAL PRIMARY KEY,
    order_id INT REFERENCES orders(id),
    plate_number VARCHAR(20) REFERENCES vehicles(plate_number),
    arrive_time TIMESTAMP WITH TIME ZONE,
    arrive_lat DOUBLE PRECISION,
    arrive_lng DOUBLE PRECISION,
    pump_done_time TIMESTAMP WITH TIME ZONE,
    pump_done_lat DOUBLE PRECISION,
    pump_done_lng DOUBLE PRECISION,
    wait_duration_minutes INT,
    wait_reason_code VARCHAR(20),
    wait_reason_note TEXT,
    source VARCHAR(20) DEFAULT 'app'
);

-- 13. Bảng ChungTuChuyen (Phiếu cân và Phiếu giao hàng)
CREATE TABLE IF NOT EXISTS chung_tu_chuyen (
    id SERIAL PRIMARY KEY,
    order_id INT REFERENCES orders(id),
    doc_type VARCHAR(30) NOT NULL CHECK (doc_type IN ('phieu_can', 'phieu_giao_hang')),
    img_url TEXT NOT NULL,
    ocr_order_code VARCHAR(50),
    ocr_tons DOUBLE PRECISION,
    ocr_weigh_time TIMESTAMP WITH TIME ZONE,
    zalo_status VARCHAR(30) DEFAULT 'pending_send',
    zalo_sent_at TIMESTAMP WITH TIME ZONE,
    zalo_group_id VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 14. Bảng BaoHong (Báo hỏng xe)
CREATE TABLE IF NOT EXISTS bao_hong (
    id SERIAL PRIMARY KEY,
    plate_number VARCHAR(20) REFERENCES vehicles(plate_number),
    driver_id INT REFERENCES users(id),
    category VARCHAR(50) NOT NULL,
    img_url TEXT NOT NULL,
    description TEXT,
    decision VARCHAR(30) DEFAULT 'pending',
    decided_by INT REFERENCES users(id),
    decided_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 15. Bảng NhacNho (Cảnh báo chạy nền)
CREATE TABLE IF NOT EXISTS nhac_nho (
    id SERIAL PRIMARY KEY,
    reminder_type VARCHAR(50) NOT NULL,
    driver_id INT REFERENCES users(id),
    plate_number VARCHAR(20) REFERENCES vehicles(plate_number),
    reminder_count INT DEFAULT 1,
    sent_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    responded_at TIMESTAMP WITH TIME ZONE,
    is_incident_created BOOLEAN DEFAULT FALSE
);

-- 16. Bảng DispatcherShifts (Ca trực điều phối & Nhận ca)
CREATE TABLE IF NOT EXISTS dispatcher_shifts (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id),
    shift_name VARCHAR(50) DEFAULT 'Ca ngày',
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    ended_at TIMESTAMP WITH TIME ZONE,
    status VARCHAR(20) DEFAULT 'active',
    note TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- DỮ LIỆU MẪU BAN ĐẦU (SEED DATA)
INSERT INTO roles (code, name, description, is_system) VALUES
('admin', 'Quản trị viên', 'Quản trị viên toàn quyền hệ thống', TRUE),
('driver', 'Tài xế', 'Tài xế lái xe, kiểm tra đầu ngày, bấm mốc giờ', TRUE),
('gas_station', 'Cây dầu', 'Nhân viên trạm cấp dầu ghi nhận số lít và vị trí', TRUE),
('dispatcher', 'Điều phối', 'Giao chuyến, duyệt cờ, theo dõi đơn hàng', TRUE),
('mechanic', 'Kỹ thuật', 'Kiểm tra hỏng hóc, so sánh ảnh gầm hông', TRUE),
('manager', 'Ban Giám Đốc / Trưởng BP', 'Xem báo cáo tuân thủ và chi phí nhiên liệu', TRUE)
ON CONFLICT (code) DO NOTHING;

INSERT INTO products (code, name, unit, standard_pump_time_minutes, requires_air_pump) VALUES
('TRO_BAY', 'Tro bay', 'tan', 90, TRUE),
('XI_MANG_ROI', 'Xi măng rời', 'tan', 90, TRUE),
('XI_MANG_BAO', 'Xi măng đóng bao', 'tan', 120, FALSE),
('XI_LO_CAO', 'Xỉ lò cao', 'tan', 90, TRUE),
('CLINKER', 'Clinker', 'tan', 60, FALSE)
ON CONFLICT (code) DO NOTHING;

-- SEED PERMISSIONS
INSERT INTO permissions (code, module, name) VALUES
('order:view', 'order', 'Xem danh sách và chi tiết đơn hàng'),
('order:create', 'order', 'Tạo mới và gán chuyến đơn hàng'),
('order:dispatch', 'order', 'Điều phối và đổi tài xế/xe'),
('order:update', 'order', 'Chỉnh sửa lộ trình và thông tin đơn hàng'),
('order:delete', 'order', 'Hủy / Xóa đơn hàng vận chuyển'),
('product:view', 'product', 'Xem danh mục sản phẩm & vật liệu'),
('product:create', 'product', 'Thêm mới sản phẩm & vật liệu'),
('product:update', 'product', 'Chỉnh sửa thông tin sản phẩm & vật liệu'),
('product:delete', 'product', 'Xóa sản phẩm & vật liệu'),
('vehicle:view', 'vehicle', 'Xem danh sách đội xe & thông tin phương tiện'),
('vehicle:create', 'vehicle', 'Thêm mới phương tiện xe vận tải'),
('vehicle:update', 'vehicle', 'Chỉnh sửa thông tin phương tiện & gán tài xế'),
('vehicle:delete', 'vehicle', 'Xóa phương tiện khỏi đội xe'),
('driver:view', 'driver', 'Xem hồ sơ danh sách tài xế'),
('driver:create', 'driver', 'Thêm mới hồ sơ tài xế vận chuyển'),
('driver:update', 'driver', 'Chỉnh sửa hồ sơ thông tin tài xế'),
('driver:delete', 'driver', 'Xóa / ngừng kích hoạt tài xế'),
('gas_station:view', 'fuel', 'Xem danh sách trạm cấp dầu & đối soát'),
('gas_station:create', 'fuel', 'Thêm mới cây dầu / trạm cấp nhiên liệu'),
('gas_station:update', 'fuel', 'Chỉnh sửa thông tin trạm cấp dầu & vị trí GPS'),
('gas_station:delete', 'fuel', 'Xóa trạm cấp dầu khỏi hệ thống'),
('fuel:confirm', 'fuel', 'Xác nhận cấp dầu và kiểm tra geofencing GPS'),
('inspection:view', 'inspection', 'Xem ảnh kiểm tra 5 ảnh đầu ngày'),
('inspection:approve', 'inspection', 'Phê duyệt cờ xe bất thường gầm/hông/táp-lô'),
('breakdown:resolve', 'maintenance', 'Xử lý báo hỏng và khóa/mở khóa xe'),
('report:view', 'report', 'Xem báo cáo KPI tuân thủ và giao hàng'),
('user:manage', 'system', 'Quản lý tài khoản người dùng và phân quyền RBAC')
ON CONFLICT (code) DO NOTHING;

-- SEED ROLE PERMISSIONS
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p WHERE r.code = 'admin'
ON CONFLICT DO NOTHING;

-- Bảng đăng ký thiết bị (device token) phục vụ push notification
CREATE TABLE IF NOT EXISTS device_tokens (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id),
    device_token TEXT UNIQUE NOT NULL,
    platform VARCHAR(20) DEFAULT 'android',
    device_name VARCHAR(100),
    app_version VARCHAR(20),
    last_seen_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
