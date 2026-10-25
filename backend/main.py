import base64
import os
import math
import uuid
import shutil
import hashlib
import hmac
import html
import json
import asyncio
import secrets
import threading
import unicodedata
from urllib.parse import urlencode
import requests
from datetime import datetime, timedelta, timezone
from typing import Optional, List, Any
import psycopg2
from psycopg2.extras import RealDictCursor
from fastapi import FastAPI, HTTPException, Depends, status, UploadFile, File, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from pydantic import BaseModel, ConfigDict, model_validator
from jose import JWTError, jwt
import bcrypt

SECRET_KEY = os.getenv("JWT_SECRET_KEY", "super-secret-taxi-logistics-key-2026")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7 # Token có thời hạn 7 ngày

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/token")

def verify_password(plain_password: str, hashed_password: str) -> bool:
    try:
        return bcrypt.checkpw(plain_password.encode('utf-8'), hashed_password.encode('utf-8'))
    except Exception:
        return False

def get_password_hash(password: str) -> str:
    salt = bcrypt.gensalt()
    return bcrypt.hashpw(password.encode('utf-8'), salt).decode('utf-8')

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.now(timezone.utc) + expires_delta
    else:
        expire = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

from fastapi.middleware.cors import CORSMiddleware

# ----------------- FASTAPI INIT -----------------
app = FastAPI(
    title="Hệ thống Quản lý Vận tải & App Tài xế (Taxi Logistics API)",
    description="API nghiệp vụ: Xác thực JWT cho mọi phiên đăng nhập, Kiểm tra xe 5 ảnh, Cây dầu đối soát nhiên liệu, Mốc giờ chuyến, Sản phẩm & RBAC động",
    version="2.1.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

UPLOAD_DIR = os.getenv("UPLOAD_DIR", "/app/uploads")
os.makedirs(UPLOAD_DIR, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=UPLOAD_DIR), name="uploads")

DB_URL = os.getenv("DATABASE_URL", "postgres://taxi_user:taxi_password_2026@postgres:5432/taxi_logistics")

def get_db():
    conn = psycopg2.connect(DB_URL, cursor_factory=RealDictCursor)
    return conn

# Helper tính khoảng cách Haversine (mét) giữa 2 tọa độ
def haversine_distance(lat1, lon1, lat2, lon2):
    R = 6371000
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    a = math.sin(delta_phi / 2.0) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2.0) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

# ----------------- PYDANTIC SCHEMAS -----------------
class Token(BaseModel):
    access_token: str
    token_type: str
    user_id: int
    username: str
    full_name: str
    roles: List[str]
    driver_type: Optional[str] = None

class LoginRequest(BaseModel):
    model_config = ConfigDict(extra="allow")

    username: str
    password: str
    device_token: Optional[str] = None
    platform: Optional[str] = "android"
    device_name: Optional[str] = None
    app_version: Optional[str] = None

    @model_validator(mode="before")
    @classmethod
    def extract_aliases(cls, data: Any) -> Any:
        if isinstance(data, dict):
            # Tự động nhận diện device_token từ mọi kiểu đặt tên phổ biến
            if not data.get("device_token"):
                for key in ["deviceToken", "fcm_token", "fcmToken", "push_token", "pushToken", "registration_token", "registrationToken", "token"]:
                    val = data.get(key)
                    if val and isinstance(val, str) and val.strip():
                        data["device_token"] = val.strip()
                        break
            # Tự động nhận diện platform
            if not data.get("platform"):
                for key in ["os", "os_name", "osName", "device_os"]:
                    val = data.get(key)
                    if val and isinstance(val, str) and val.strip():
                        data["platform"] = val.strip().lower()
                        break
            # Tự động nhận diện device_name
            if not data.get("device_name"):
                for key in ["deviceName", "device_model", "deviceModel", "model"]:
                    val = data.get(key)
                    if val and isinstance(val, str) and val.strip():
                        data["device_name"] = val.strip()
                        break
            # Tự động nhận diện app_version
            if not data.get("app_version"):
                for key in ["appVersion", "version", "buildNumber"]:
                    val = data.get(key)
                    if val and isinstance(val, str) and val.strip():
                        data["app_version"] = val.strip()
                        break
        return data

class UserCreate(BaseModel):
    username: str
    password: str
    full_name: str
    phone: str
    driver_type: Optional[str] = None # INTERNAL, RENTAL, CUSTOMER_SELF (Chỉ dành cho tài xế)
    contractor_name: Optional[str] = None
    customer_name: Optional[str] = None
    role_codes: Optional[List[str]] = ["driver"]
    avatar_url: Optional[str] = None
    id_card_front_url: Optional[str] = None
    id_card_back_url: Optional[str] = None
    address: Optional[str] = None
    email: Optional[str] = None
    age: Optional[int] = None
    gender: Optional[str] = None
    notes: Optional[str] = None

class RoleCreate(BaseModel):
    code: str
    name: str
    description: Optional[str] = None
    permission_codes: Optional[List[str]] = []

class RoleUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    permission_codes: Optional[List[str]] = None

class UserRoleAssign(BaseModel):
    user_id: int
    role_id: int

class ProductCreate(BaseModel):
    code: str
    name: str
    category: Optional[str] = "vat_lieu_xay_dung"
    unit: Optional[str] = "tan"
    standard_pump_time_minutes: Optional[int] = 90
    requires_air_pump: Optional[bool] = True

class ProductUpdate(BaseModel):
    code: Optional[str] = None
    name: Optional[str] = None
    category: Optional[str] = None
    unit: Optional[str] = None
    standard_pump_time_minutes: Optional[int] = None
    requires_air_pump: Optional[bool] = None

class CustomerCreate(BaseModel):
    code: str
    name: str
    tax_code: Optional[str] = None
    contact_person: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    address: Optional[str] = None
    note: Optional[str] = None

class CustomerUpdate(BaseModel):
    code: Optional[str] = None
    name: Optional[str] = None
    tax_code: Optional[str] = None
    contact_person: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    address: Optional[str] = None
    note: Optional[str] = None

CUSTOMER_FIELDS = ["code", "name", "tax_code", "contact_person", "phone", "email", "address", "note"]

class LocationCreate(BaseModel):
    name: str
    address: Optional[str] = None
    kind: Optional[str] = "BOTH"  # PICKUP | DELIVERY | BOTH
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    radius_m: Optional[int] = None
    note: Optional[str] = None

class LocationUpdate(BaseModel):
    name: Optional[str] = None
    address: Optional[str] = None
    kind: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    radius_m: Optional[int] = None
    note: Optional[str] = None

class LocationSuggestionApprove(BaseModel):
    name: Optional[str] = None
    address: Optional[str] = None
    kind: Optional[str] = "BOTH"
    note: Optional[str] = None

class LocationSuggestionBulkApprove(BaseModel):
    ids: List[int]
    kind: Optional[str] = "BOTH"

class LocationScanRequest(BaseModel):
    vietmap_days: Optional[int] = 30
    binhanh_days: Optional[int] = 7
    min_stop_minutes: Optional[int] = 15
    min_visits: Optional[int] = 1  # Không còn dùng: mọi chỗ dừng đều thành gợi ý


def _clean(value) -> Optional[str]:
    """Bỏ khoảng trắng thừa; chuỗi rỗng coi như không có (None)."""
    if value is None:
        return None
    text = str(value).strip()
    return text or None

class VehicleCreate(BaseModel):
    plate_number: str
    vehicle_type: str
    ownership_type: Optional[str] = "INTERNAL"
    default_driver_id: Optional[int] = None
    owner_company: Optional[str] = "Sao Mai Logistics"
    status: Optional[str] = "ready"

class VehicleUpdate(BaseModel):
    vehicle_type: Optional[str] = None
    ownership_type: Optional[str] = None
    default_driver_id: Optional[int] = None
    owner_company: Optional[str] = None
    status: Optional[str] = None

class GasStationCreate(BaseModel):
    name: str
    address: str
    lat: float
    lng: float
    allowed_radius_meters: Optional[int] = 500
    user_id: Optional[int] = None

class GasStationUpdate(BaseModel):
    name: Optional[str] = None
    address: Optional[str] = None
    lat: Optional[float] = None
    lng: Optional[float] = None
    allowed_radius_meters: Optional[int] = None
    user_id: Optional[int] = None

class OrderCreate(BaseModel):
    order_code: str
    customer_code: Optional[str] = None
    factory_code: str
    product_id: int
    product_detail: Optional[str] = None
    transport_type: Optional[str] = "INTERNAL"
    carrier_name: Optional[str] = None
    customer_group_id: Optional[str] = None
    pickup_address: str
    pickup_lat: Optional[float] = None
    pickup_lng: Optional[float] = None
    delivery_address: str
    delivery_lat: Optional[float] = None
    delivery_lng: Optional[float] = None
    pickup_radius_m: Optional[int] = None
    delivery_radius_m: Optional[int] = None
    assigned_vehicle_plate: str
    # Không còn chọn tay: tài xế lấy theo tài xế phụ trách của xe (vehicles.default_driver_id)
    assigned_driver_id: Optional[int] = None
    cargo_weight_tons: float

class OrderUpdate(BaseModel):
    order_code: Optional[str] = None
    customer_code: Optional[str] = None
    factory_code: Optional[str] = None
    product_id: Optional[int] = None
    product_detail: Optional[str] = None
    transport_type: Optional[str] = None
    carrier_name: Optional[str] = None
    customer_group_id: Optional[str] = None
    pickup_address: Optional[str] = None
    pickup_lat: Optional[float] = None
    pickup_lng: Optional[float] = None
    delivery_address: Optional[str] = None
    delivery_lat: Optional[float] = None
    delivery_lng: Optional[float] = None
    pickup_radius_m: Optional[int] = None
    delivery_radius_m: Optional[int] = None
    assigned_vehicle_plate: Optional[str] = None
    assigned_driver_id: Optional[int] = None
    cargo_weight_tons: Optional[float] = None
    status: Optional[str] = None

class InspectionSubmit(BaseModel):
    check_date: str
    plate_number: str
    img_front_underbody: str
    img_rear_underbody: str
    img_left_side: str
    img_right_side: str
    img_dashboard: str
    gps_lat: float
    gps_lng: float
    gps_accuracy: float
    device_id: str
    km_ocr: float
    km_confirmed: float
    # GPS riêng của từng ảnh: [{"step": 1, "lat":..., "lng":..., "accuracy":..., "captured_at": "..."}]
    photo_gps: Optional[List[dict]] = None

class InspectionReview(BaseModel):
    flag_status: str # 'approved', 'rejected', 'monitored'
    flag_reason: Optional[str] = None

class ShiftCheckin(BaseModel):
    shift_name: Optional[str] = "Ca ngày"
    note: Optional[str] = None

class ShiftCheckout(BaseModel):
    note: Optional[str] = None

class FuelConfirm(BaseModel):
    order_id: int
    plate_number: str
    gas_station_id: int
    fuel_type: Optional[str] = "diesel"
    liters_ocr: Optional[float] = None
    liters_actual: float
    img_meter: str
    img_receipt: Optional[str] = None
    gps_lat: float
    gps_lng: float

class MilestoneArrive(BaseModel):
    order_id: int
    plate_number: str
    arrive_lat: float
    arrive_lng: float

class MilestonePumpDone(BaseModel):
    order_id: int
    plate_number: str
    pump_done_lat: float
    pump_done_lng: float
    wait_reason_code: Optional[str] = None
    wait_reason_note: Optional[str] = None

class OrderAttachmentSubmit(BaseModel):
    # Hình chụp chứng từ / sự cố gắn vào đơn hàng (POST /api/v1/orders/{order_id}/attachment)
    # pump_slip_before (Trước khi bơm) | pump_slip (Đã bơm xong) | weigh_slip | delivery_slip | breakdown | repair
    photo_type: str
    photo_base64: str
    note: Optional[str] = None
    tonnage: Optional[float] = None
    slip_code: Optional[str] = None
    location: Optional[str] = None
    repair_status: Optional[str] = None  # fixed | repairing
    # Tọa độ GPS thực tế của thiết bị lúc chụp ảnh
    gps_lat: Optional[float] = None
    gps_lng: Optional[float] = None
    gps_accuracy: Optional[float] = None
    gps_captured_at: Optional[str] = None

# ----------------- XÁC THỰC PHIÊN ĐĂNG NHẬP VỚI JWT -----------------
def get_current_user(token: str = Depends(oauth2_scheme)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Phiên đăng nhập không hợp lệ hoặc đã hết hạn. Vui lòng đăng nhập lại.",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT * FROM users WHERE username = %s AND is_active = TRUE", (username,))
    user = cur.fetchone()
    if user is None:
        cur.close()
        conn.close()
        raise credentials_exception

    # Lấy danh sách Roles động của User
    cur.execute("""
        SELECT r.code 
        FROM roles r 
        JOIN user_roles ur ON r.id = ur.role_id 
        WHERE ur.user_id = %s
    """, (user["id"],))
    roles = [r["code"] for r in cur.fetchall()]
    user["roles"] = roles

    # Lấy danh sách Permissions động của User
    cur.execute("""
        SELECT DISTINCT p.code
        FROM permissions p
        JOIN role_permissions rp ON p.id = rp.permission_id
        JOIN user_roles ur ON rp.role_id = ur.role_id
        WHERE ur.user_id = %s
    """, (user["id"],))
    perms = [p["code"] for p in cur.fetchall()]
    user["permissions"] = perms
    cur.close()
    conn.close()
    return user

def require_admin(current_user: dict = Depends(get_current_user)):
    # Chỉ tài khoản admin tối cao mới có quyền thực hiện
    if current_user["username"] != "admin" and "admin" not in current_user.get("roles", []):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Chỉ Quản trị viên (admin) tối cao mới có quyền thực hiện thao tác này"
        )
    return current_user

def require_admin_or_manager(current_user: dict = Depends(get_current_user)):
    # Chỉ tài khoản Admin và Giám đốc (manager) mới có quyền quản lý người dùng
    user_roles = [r.lower() for r in current_user.get("roles", [])]
    if current_user["username"] != "admin" and not any(r in ("admin", "manager") for r in user_roles):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Chỉ Quản trị viên (admin) và Giám đốc (manager) mới có quyền quản lý người dùng"
        )
    return current_user

def require_dispatch_staff(current_user: dict = Depends(get_current_user)):
    # Điều phối viên (dispatcher), Quản lý / Giám đốc (manager) và Admin
    user_roles = [r.lower() for r in current_user.get("roles", [])]
    if current_user["username"] != "admin" and not any(r in ("admin", "manager", "dispatcher") for r in user_roles):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Chỉ Điều phối viên, Quản lý và Quản trị viên mới có quyền thực hiện thao tác này"
        )
    return current_user

CUSTOMERS_DDL = """
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
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
)
"""

ZALO_OA_DDL = [
    # Mỗi khách hàng đồng bộ từ Zalo OA giữ 1 ID riêng (user_id của Zalo), không trùng
    "ALTER TABLE customers ADD COLUMN IF NOT EXISTS zalo_user_id VARCHAR(64)",
    "ALTER TABLE customers ADD COLUMN IF NOT EXISTS zalo_display_name VARCHAR(255)",
    "ALTER TABLE customers ADD COLUMN IF NOT EXISTS zalo_avatar TEXT",
    "ALTER TABLE customers ADD COLUMN IF NOT EXISTS zalo_synced_at TIMESTAMP WITH TIME ZONE",
    "ALTER TABLE customers ADD COLUMN IF NOT EXISTS source VARCHAR(20) DEFAULT 'manual'",
    "CREATE UNIQUE INDEX IF NOT EXISTS ux_customers_zalo_user_id ON customers(zalo_user_id) WHERE zalo_user_id IS NOT NULL",
    """CREATE TABLE IF NOT EXISTS zalo_oa_tokens (
        id INT PRIMARY KEY DEFAULT 1,
        oa_id VARCHAR(64),
        access_token TEXT NOT NULL,
        refresh_token TEXT NOT NULL,
        access_expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
        refresh_expires_at TIMESTAMP WITH TIME ZONE,
        authorized_by VARCHAR(100),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        CHECK (id = 1)
    )""",
    """CREATE TABLE IF NOT EXISTS zalo_oa_oauth_states (
        state VARCHAR(100) PRIMARY KEY,
        code_verifier VARCHAR(200) NOT NULL,
        created_by VARCHAR(100),
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    )""",
]

# Loại ảnh gắn vào đơn hàng -> tiền tố cột trong bảng orders
ORDER_PHOTO_PREFIX = {
    "pump_slip_before": "pump_slip_before",  # Bơm hàng - Trước khi bơm (Tài xế)
    "pump_slip": "pump_slip",                # Bơm hàng - Đã bơm xong (Tài xế)
    "weigh_slip": "weigh_slip",
    "delivery_slip": "delivery_slip",
    "breakdown": "breakdown",
    "repair": "repair",
}

ORDER_ATTACHMENT_DDL = [
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP",
    # Mã khách hàng (liên kết mềm với customers.code), không bắt buộc
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_code VARCHAR(50)",
    # Sản phẩm do điều phối nhập tay (bên cạnh Hàng hóa chọn từ danh mục products)
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS product_detail VARCHAR(255)",
    # Bán kính (mét) cho phép khi đối chiếu GPS ảnh với Nơi nhận hàng / Điểm giao hàng
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS pickup_radius_m INTEGER",
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_radius_m INTEGER",
    # Đơn vị vận chuyển do điều phối nhập tay khi chọn Xe thuê ngoài (RENTAL)
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS carrier_name VARCHAR(255)",
    # Phiếu bơm hàng: 2 ảnh bắt buộc do Tài xế chụp
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS pump_slip_before_photo_url TEXT",
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS pump_slip_before_time TIMESTAMP WITH TIME ZONE",
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS pump_slip_before_by VARCHAR(150)",
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS pump_slip_before_note TEXT",
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS pump_slip_photo_url TEXT",
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS pump_slip_time TIMESTAMP WITH TIME ZONE",
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS pump_slip_by VARCHAR(150)",
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS pump_slip_note TEXT",
    # Phiếu cân
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS weigh_slip_photo_url TEXT",
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS weigh_slip_time TIMESTAMP WITH TIME ZONE",
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS weigh_slip_tonnage DOUBLE PRECISION",
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS weigh_slip_code VARCHAR(100)",
    # Phiếu giao hàng
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_slip_photo_url TEXT",
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_slip_time TIMESTAMP WITH TIME ZONE",
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_slip_note TEXT",
    # Báo hỏng xe
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS has_breakdown BOOLEAN DEFAULT FALSE",
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS breakdown_status VARCHAR(30)",
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS breakdown_photo_url TEXT",
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS breakdown_reason TEXT",
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS breakdown_location TEXT",
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS breakdown_time TIMESTAMP WITH TIME ZONE",
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS breakdown_reported_by VARCHAR(150)",
    # Sửa chữa
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS repair_photo_url TEXT",
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS repair_status VARCHAR(30)",
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS repair_note TEXT",
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS repair_time TIMESTAMP WITH TIME ZONE",
    "ALTER TABLE orders ADD COLUMN IF NOT EXISTS repair_by VARCHAR(150)",
]
# Tọa độ GPS thực tế lúc chụp cho từng loại ảnh
for _prefix in ORDER_PHOTO_PREFIX.values():
    ORDER_ATTACHMENT_DDL += [
        f"ALTER TABLE orders ADD COLUMN IF NOT EXISTS {_prefix}_gps_lat DOUBLE PRECISION",
        f"ALTER TABLE orders ADD COLUMN IF NOT EXISTS {_prefix}_gps_lng DOUBLE PRECISION",
        f"ALTER TABLE orders ADD COLUMN IF NOT EXISTS {_prefix}_gps_accuracy DOUBLE PRECISION",
        f"ALTER TABLE orders ADD COLUMN IF NOT EXISTS {_prefix}_gps_captured_at TIMESTAMP WITH TIME ZONE",
    ]
# GPS riêng của từng ảnh trong 5 ảnh kiểm tra xe
ORDER_ATTACHMENT_DDL.append(
    "ALTER TABLE kiem_tra_dau_ngay ADD COLUMN IF NOT EXISTS photo_gps JSONB"
)

def ensure_order_attachment_columns():
    # Bổ sung các cột ảnh chứng từ & GPS cho DB cũ. Mỗi lệnh chạy riêng để
    # một lệnh lỗi (VD bảng chưa tồn tại) không chặn các lệnh khác.
    try:
        conn = get_db()
    except Exception as e:
        print(f"[orders] Không kết nối được DB để bổ sung cột: {e}")
        return
    cur = conn.cursor()
    for ddl in ORDER_ATTACHMENT_DDL:
        try:
            cur.execute(ddl)
            conn.commit()
        except Exception as e:
            conn.rollback()
            print(f"[orders] Lỗi bổ sung cột ({ddl}): {e}")
    cur.close()
    conn.close()

def _validate_gps(lat, lng, label: str = "Ảnh"):
    # Mọi ảnh của tài xế bắt buộc phải có tọa độ GPS thật
    if lat is None or lng is None:
        raise HTTPException(
            status_code=400,
            detail=f"{label} thiếu tọa độ GPS. Vui lòng bật định vị và chụp lại.",
        )
    if not (-90 <= lat <= 90 and -180 <= lng <= 180) or (lat == 0 and lng == 0):
        raise HTTPException(status_code=400, detail=f"{label} có tọa độ GPS không hợp lệ.")

def _parse_gps_time(value: Optional[str]):
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None

DEFAULT_ORDER_POINT_RADIUS_M = 100

# Loại ảnh -> nhãn hiển thị, dùng khi đối chiếu GPS ảnh với Nơi nhận / Điểm giao
ORDER_PHOTO_GEO_LABELS = {
    "pump_slip_before": "Bơm hàng - Trước khi bơm",
    "pump_slip": "Bơm hàng - Đã bơm xong",
    "weigh_slip": "Phiếu cân",
    "delivery_slip": "Phiếu giao hàng",
    "breakdown": "Báo hỏng xe",
    "repair": "Sửa chữa xe",
}

def _validate_order_point(lat, lng, label: str):
    # Tọa độ điểm của đơn không bắt buộc, nhưng đã nhập thì phải nhập đủ cặp và hợp lệ
    if lat is None and lng is None:
        return
    if lat is None or lng is None:
        raise HTTPException(status_code=400, detail=f"{label}: phải nhập đủ cả Vĩ độ và Kinh độ")
    if not (-90 <= lat <= 90 and -180 <= lng <= 180) or (lat == 0 and lng == 0):
        raise HTTPException(status_code=400, detail=f"{label}: tọa độ không hợp lệ")

def _as_float(v):
    try:
        return None if v is None else float(v)
    except (TypeError, ValueError):
        return None

def _attach_photo_geo_check(order):
    """Gắn photo_geo_check vào đơn: với mỗi ảnh đã có GPS, tính khoảng cách tới
    Nơi nhận hàng và Điểm giao hàng (mét) và cho biết ảnh có nằm trong bán kính không."""
    if not order:
        return order
    o = dict(order)
    points = {}
    for key in ("pickup", "delivery"):
        lat = _as_float(o.get(f"{key}_lat"))
        lng = _as_float(o.get(f"{key}_lng"))
        if lat is None or lng is None:
            continue
        radius = o.get(f"{key}_radius_m") or DEFAULT_ORDER_POINT_RADIUS_M
        points[key] = (lat, lng, int(radius))

    checks = {}
    for ptype, label in ORDER_PHOTO_GEO_LABELS.items():
        plat = _as_float(o.get(f"{ptype}_gps_lat"))
        plng = _as_float(o.get(f"{ptype}_gps_lng"))
        if plat is None or plng is None:
            continue
        item = {"label": label, "gps_lat": plat, "gps_lng": plng,
                "gps_accuracy": _as_float(o.get(f"{ptype}_gps_accuracy"))}
        nearest = None
        for key, (lat, lng, radius) in points.items():
            dist = round(haversine_distance(plat, plng, lat, lng))
            item[f"{key}_distance_m"] = dist
            item[f"{key}_radius_m"] = radius
            item[f"at_{key}"] = dist <= radius
            if dist <= radius and (nearest is None or dist < nearest[1]):
                nearest = (key, dist)
        # matched: PICKUP | DELIVERY | NONE (có tọa độ điểm nhưng ngoài bán kính) | UNKNOWN (đơn chưa có tọa độ)
        item["matched"] = nearest[0].upper() if nearest else ("NONE" if points else "UNKNOWN")
        checks[ptype] = item
    o["photo_geo_check"] = checks
    return o

def ensure_customers_table():
    # Tự tạo bảng customers khi server khởi động (DB cũ chưa có bảng này)
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute(CUSTOMERS_DDL)
        for ddl in ZALO_OA_DDL:
            cur.execute(ddl)
        conn.commit()
        cur.close()
        conn.close()
    except Exception as e:
        print(f"[customers] Không tạo được bảng customers: {e}")

VEHICLE_GPS_DDL = [
    "ALTER TABLE vehicles ADD COLUMN IF NOT EXISTS gps_provider VARCHAR(30)",
    "ALTER TABLE vehicles ADD COLUMN IF NOT EXISTS gps_vehicle_id VARCHAR(50)",
    "ALTER TABLE vehicles ADD COLUMN IF NOT EXISTS gps_driver_name VARCHAR(150)",
    # TRUE = xe đang có trên Vietmap hoặc Bình Anh; FALSE = đã ẩn (giữ lại vì có lịch sử)
    "ALTER TABLE vehicles ADD COLUMN IF NOT EXISTS in_fleet BOOLEAN DEFAULT TRUE",
    # Mỗi phương tiện đi kèm đúng 1 tài khoản Tài xế: một tài xế không được gắn với 2 xe
    "CREATE UNIQUE INDEX IF NOT EXISTS uq_vehicles_default_driver ON vehicles(default_driver_id) WHERE default_driver_id IS NOT NULL",
]

def ensure_vehicle_gps_columns():
    try:
        conn = get_db()
        cur = conn.cursor()
        for ddl in VEHICLE_GPS_DDL:
            cur.execute(ddl)
        conn.commit()
        cur.close()
        conn.close()
    except Exception as e:
        print(f"[vehicles] Không thêm được cột GPS cho bảng vehicles: {e}")

LOCATIONS_DDL = [
    """
    CREATE TABLE IF NOT EXISTS locations (
        id SERIAL PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        address TEXT,
        kind VARCHAR(20) DEFAULT 'BOTH',
        latitude DOUBLE PRECISION,
        longitude DOUBLE PRECISION,
        radius_m INTEGER DEFAULT 100,
        note TEXT,
        source VARCHAR(30) DEFAULT 'MANUAL',
        is_active BOOLEAN DEFAULT TRUE,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS location_suggestions (
        id SERIAL PRIMARY KEY,
        providers VARCHAR(50),
        address TEXT,
        station_name VARCHAR(255),
        latitude DOUBLE PRECISION NOT NULL,
        longitude DOUBLE PRECISION NOT NULL,
        visit_count INTEGER DEFAULT 0,
        total_minutes INTEGER DEFAULT 0,
        vehicle_count INTEGER DEFAULT 0,
        vehicles TEXT,
        first_seen TIMESTAMP,
        last_seen TIMESTAMP,
        status VARCHAR(20) DEFAULT 'PENDING',
        location_id INTEGER REFERENCES locations(id) ON DELETE SET NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    )
    """,
    "CREATE INDEX IF NOT EXISTS ix_location_suggestions_status ON location_suggestions(status)",
    # Bán kính nhận diện mặc định của điểm nhận / giao: 50 m
    "ALTER TABLE locations ALTER COLUMN radius_m SET DEFAULT 100",
]

def ensure_locations_tables():
    try:
        conn = get_db()
        cur = conn.cursor()
        for ddl in LOCATIONS_DDL:
            cur.execute(ddl)
        conn.commit()
        cur.close()
        conn.close()
    except Exception as e:
        print(f"[locations] Không tạo được bảng locations: {e}")

@app.on_event("startup")
def _startup_ensure_customers():
    ensure_customers_table()
    ensure_order_attachment_columns()
    ensure_vehicle_gps_columns()
    ensure_locations_tables()

# ----------------- REALTIME WEBSOCKET & DEVICE TOKEN (PUSH NOTIFICATION) -----------------

class ConnectionManager:
    # Quan ly ket noi WebSocket theo user_id de day su kien realtime
    def __init__(self):
        self.active = {}

    async def connect(self, user_id, ws):
        global main_loop
        if main_loop is None or not main_loop.is_running():
            try:
                main_loop = asyncio.get_running_loop()
            except RuntimeError:
                pass
        await ws.accept()
        self.active.setdefault(user_id, set()).add(ws)

    def disconnect(self, user_id, ws):
        try:
            self.active.get(user_id, set()).discard(ws)
            if user_id in self.active and not self.active[user_id]:
                self.active.pop(user_id, None)
        except Exception:
            pass

    async def send_to_user(self, user_id, payload):
        for ws in list(self.active.get(user_id, set())):
            try:
                await ws.send_text(json.dumps(payload, ensure_ascii=False, default=str))
            except Exception:
                self.disconnect(user_id, ws)

    async def broadcast(self, payload):
        for uid in list(self.active.keys()):
            await self.send_to_user(uid, payload)

manager = ConnectionManager()

main_loop = None

@app.on_event("startup")
async def startup_event():
    global main_loop
    main_loop = asyncio.get_running_loop()

def _emit_event(event, data, target_user_id=None):
    payload = {"event": event, "data": data, "sent_at": datetime.now(timezone.utc).isoformat()}
    global main_loop
    coro = manager.broadcast(payload) if target_user_id is None else manager.send_to_user(target_user_id, payload)
    try:
        loop = asyncio.get_running_loop()
        loop.create_task(coro)
    except RuntimeError:
        if main_loop and main_loop.is_running():
            asyncio.run_coroutine_threadsafe(coro, main_loop)

class DeviceRegister(BaseModel):
    model_config = ConfigDict(extra="allow")

    device_token: str
    platform: Optional[str] = "android"
    device_name: Optional[str] = None
    app_version: Optional[str] = None

    @model_validator(mode="before")
    @classmethod
    def extract_aliases(cls, data: Any) -> Any:
        if isinstance(data, dict):
            if not data.get("device_token"):
                for key in ["deviceToken", "fcm_token", "fcmToken", "push_token", "pushToken", "registration_token", "registrationToken", "token"]:
                    val = data.get(key)
                    if val and isinstance(val, str) and val.strip():
                        data["device_token"] = val.strip()
                        break
            if not data.get("platform"):
                for key in ["os", "os_name", "osName", "device_os"]:
                    val = data.get(key)
                    if val and isinstance(val, str) and val.strip():
                        data["platform"] = val.strip().lower()
                        break
            if not data.get("device_name"):
                for key in ["deviceName", "device_model", "deviceModel", "model"]:
                    val = data.get(key)
                    if val and isinstance(val, str) and val.strip():
                        data["device_name"] = val.strip()
                        break
            if not data.get("app_version"):
                for key in ["appVersion", "version", "buildNumber"]:
                    val = data.get(key)
                    if val and isinstance(val, str) and val.strip():
                        data["app_version"] = val.strip()
                        break
        return data

_DEVICE_UPSERT_SQL = (
    "INSERT INTO device_tokens (user_id, device_token, platform, device_name, app_version, last_seen_at, is_active) "
    "VALUES (%s, %s, %s, %s, %s, CURRENT_TIMESTAMP, TRUE) "
    "ON CONFLICT (device_token) DO UPDATE "
    "SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform, device_name = EXCLUDED.device_name, "
    "app_version = EXCLUDED.app_version, last_seen_at = CURRENT_TIMESTAMP, is_active = TRUE "
    "RETURNING id, user_id, device_token, platform, last_seen_at"
)

@app.post("/api/v1/devices/register")
def register_device(dev: DeviceRegister, current_user: dict = Depends(get_current_user)):
    # Dang ky device token cua thiet bi de push notification (goi khi mo app)
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute(_DEVICE_UPSERT_SQL, (current_user["id"], dev.device_token, dev.platform, dev.device_name, dev.app_version))
        conn.commit()
        row = cur.fetchone()
        cur.close()
        conn.close()
        print(f"[DEVICE_REGISTER] User {current_user['id']} ('{current_user.get('username')}') successfully registered device_token='{dev.device_token[:15]}...', platform='{dev.platform}', device_name='{dev.device_name}'", flush=True)
        return {"status": "success", "device": row}
    except Exception as e:
        conn.rollback()
        cur.close()
        conn.close()
        print(f"[DEVICE_REGISTER] Error registering device for user {current_user['id']}: {e}", flush=True)
        raise HTTPException(status_code=400, detail=str(e))

@app.websocket("/api/v1/ws/{user_id}")
async def ws_endpoint(ws: WebSocket, user_id: int, token: Optional[str] = None):
    # Xac thuc JWT truoc khi chap nhan ket noi
    try:
        payload_jwt = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        if payload_jwt.get("sub") is None:
            raise JWTError()
    except JWTError:
        await ws.close(code=4401)
        return
    await manager.connect(user_id, ws)
    try:
        while True:
            raw = await ws.receive_text()
            try:
                msg = json.loads(raw)
            except Exception:
                continue
            if msg.get("type") == "register_device":
                try:
                    conn = get_db()
                    cur = conn.cursor()
                    cur.execute(_DEVICE_UPSERT_SQL, (user_id, msg.get("device_token"), msg.get("platform"), msg.get("device_name"), msg.get("app_version")))
                    conn.commit()
                    cur.close()
                    conn.close()
                    await ws.send_text(json.dumps({"event": "register_device_ok", "data": {"device_token": msg.get("device_token")}}, ensure_ascii=False))
                except Exception as e:
                    try:
                        await ws.send_text(json.dumps({"event": "register_device_error", "data": {"detail": str(e)}}, ensure_ascii=False))
                    except Exception:
                        pass
            elif msg.get("type") == "ping":
                await ws.send_text(json.dumps({"event": "pong"}))
    except WebSocketDisconnect:
        manager.disconnect(user_id, ws)
    except Exception:
        manager.disconnect(user_id, ws)

# ----------------- API ENDPOINTS -----------------

@app.get("/")
def health_check():
    return {
        "status": "online",
        "service": "Taxi Logistics Backend API",
        "auth": "JWT Bearer Token Enabled",
        "database": "PostgreSQL with PostGIS",
        "message": "Hệ thống sẵn sàng phục vụ các vai trò với phiên đăng nhập an toàn"
    }

# Endpoint Upload hình ảnh lưu trữ trên server
@app.post("/api/v1/upload/image")
async def upload_image(file: UploadFile = File(...)):
    try:
        ext = os.path.splitext(file.filename)[1].lower() if file.filename else ".jpg"
        if not ext or ext not in [".jpg", ".jpeg", ".png", ".webp"]:
            ext = ".jpg"
        unique_name = f"{uuid.uuid4().hex}{ext}"
        target_path = os.path.join(UPLOAD_DIR, unique_name)

        with open(target_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        # Trả về đường dẫn truy cập ảnh qua static files
        url = f"/uploads/{unique_name}"
        return {
            "status": "success",
            "filename": unique_name,
            "url": url,
            "message": "Tải ảnh lên máy chủ thành công"
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Lỗi tải ảnh: {str(e)}")

# 1. API Đăng nhập cấp Token cho mỗi phiên
@app.post("/api/v1/auth/login", response_model=Token)
def login(creds: LoginRequest):
    extra_info = creds.__pydantic_extra__ if creds.__pydantic_extra__ else {}
    print(
        f"[AUTH_LOGIN] Attempt login for username='{creds.username}' | "
        f"device_token={'YES (' + creds.device_token[:15] + '...)' if creds.device_token else 'NONE'} | "
        f"platform='{creds.platform}' | device_name='{creds.device_name}' | app_version='{creds.app_version}' | "
        f"extra_keys={list(extra_info.keys())}",
        flush=True
    )

    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT * FROM users WHERE username = %s AND is_active = TRUE", (creds.username,))
    user = cur.fetchone()
    if not user or not verify_password(creds.password, user["password_hash"]):
        cur.close()
        conn.close()
        print(f"[AUTH_LOGIN] FAILED login for username='{creds.username}' (invalid credentials)", flush=True)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Tên đăng nhập hoặc mật khẩu không chính xác"
        )

    # Lấy danh sách roles
    cur.execute("""
        SELECT r.code 
        FROM roles r 
        JOIN user_roles ur ON r.id = ur.role_id 
        WHERE ur.user_id = %s
    """, (user["id"],))
    roles = [r["code"] for r in cur.fetchall()]

    # Tự động lưu / cập nhật device token nếu client gửi kèm khi đăng nhập
    if creds.device_token:
        try:
            cur.execute(
                _DEVICE_UPSERT_SQL,
                (user["id"], creds.device_token, creds.platform or "android", creds.device_name, creds.app_version)
            )
            conn.commit()
            print(f"[AUTH_LOGIN] SUCCESS: Upserted device token for user_id={user['id']} ('{user['username']}').", flush=True)
        except Exception as e:
            conn.rollback()
            print(f"[AUTH_LOGIN] ERROR: Failed to upsert device token for user_id={user['id']}: {e}", flush=True)
    else:
        print(f"[AUTH_LOGIN] NOTICE: No device token provided for user_id={user['id']} ('{user['username']}').", flush=True)

    cur.close()
    conn.close()

    access_token = create_access_token(data={
        "sub": user["username"],
        "user_id": user["id"],
        "roles": roles,
        "driver_type": user["driver_type"]
    })

    return {
        "access_token": access_token,
        "token_type": "bearer",
        "user_id": user["id"],
        "username": user["username"],
        "full_name": user["full_name"],
        "roles": roles,
        "driver_type": user["driver_type"]
    }

# Endpoint tương thích với Swagger UI OAuth2
@app.post("/api/v1/auth/token", response_model=Token)
def login_for_access_token(form_data: OAuth2PasswordRequestForm = Depends()):
    return login(LoginRequest(username=form_data.username, password=form_data.password))

@app.get("/api/v1/auth/me")
def get_my_profile(current_user: dict = Depends(get_current_user)):
    return {
        "id": current_user["id"],
        "username": current_user["username"],
        "full_name": current_user["full_name"],
        "phone": current_user["phone"],
        "driver_type": current_user["driver_type"],
        "contractor_name": current_user["contractor_name"],
        "customer_name": current_user["customer_name"],
        "roles": current_user["roles"]
    }

# 2. Quản lý Người dùng & Tạo tài khoản mới (Chỉ admin tối cao mới có quyền Quản lý Tài khoản & Phân quyền)
@app.post("/api/v1/users", status_code=status.HTTP_201_CREATED)
def create_user(user: UserCreate, current_user: dict = Depends(require_admin_or_manager)):
    conn = get_db()
    cur = conn.cursor()
    hashed_pwd = get_password_hash(user.password)
    try:
        cur.execute(
            """INSERT INTO users (username, password_hash, full_name, phone, driver_type, contractor_name, customer_name,
                                  avatar_url, id_card_front_url, id_card_back_url, address, email, age, gender, notes)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
               RETURNING id, username, full_name, phone, driver_type""",
            (user.username, hashed_pwd, user.full_name, user.phone, user.driver_type, user.contractor_name, user.customer_name,
             user.avatar_url, user.id_card_front_url, user.id_card_back_url, user.address, user.email, user.age, user.gender, user.notes)
        )
        created_user = cur.fetchone()

        # Gán roles mặc định
        if user.role_codes:
            for r_code in user.role_codes:
                cur.execute("SELECT id FROM roles WHERE code = %s", (r_code,))
                r_row = cur.fetchone()
                if r_row:
                    cur.execute(
                        "INSERT INTO user_roles (user_id, role_id) VALUES (%s, %s) ON CONFLICT DO NOTHING",
                        (created_user["id"], r_row["id"])
                    )

        conn.commit()
        cur.close()
        conn.close()
        return created_user
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

class UserUpdate(BaseModel):
    full_name: Optional[str] = None
    phone: Optional[str] = None
    driver_type: Optional[str] = None
    contractor_name: Optional[str] = None
    customer_name: Optional[str] = None
    role_codes: Optional[List[str]] = None
    is_active: Optional[bool] = None
    avatar_url: Optional[str] = None
    id_card_front_url: Optional[str] = None
    id_card_back_url: Optional[str] = None
    address: Optional[str] = None
    email: Optional[str] = None
    age: Optional[int] = None
    gender: Optional[str] = None
    notes: Optional[str] = None

class PasswordChangeRequest(BaseModel):
    new_password: str

@app.put("/api/v1/users/{user_id}")
def update_user(user_id: int, req: UserUpdate, current_user: dict = Depends(require_admin_or_manager)):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT id FROM users WHERE id = %s", (user_id,))
        if not cur.fetchone():
            raise HTTPException(status_code=404, detail="Không tìm thấy người dùng")

        fields = []
        values = []
        if req.full_name is not None:
            fields.append("full_name = %s")
            values.append(req.full_name)
        if req.phone is not None:
            fields.append("phone = %s")
            values.append(req.phone)
        if req.driver_type is not None:
            fields.append("driver_type = %s")
            values.append(req.driver_type)
        if req.contractor_name is not None:
            fields.append("contractor_name = %s")
            values.append(req.contractor_name)
        if req.customer_name is not None:
            fields.append("customer_name = %s")
            values.append(req.customer_name)
        if req.is_active is not None:
            fields.append("is_active = %s")
            values.append(req.is_active)
        if req.avatar_url is not None:
            fields.append("avatar_url = %s")
            values.append(req.avatar_url)
        if req.id_card_front_url is not None:
            fields.append("id_card_front_url = %s")
            values.append(req.id_card_front_url)
        if req.id_card_back_url is not None:
            fields.append("id_card_back_url = %s")
            values.append(req.id_card_back_url)
        if req.address is not None:
            fields.append("address = %s")
            values.append(req.address)
        if req.email is not None:
            fields.append("email = %s")
            values.append(req.email)
        if req.age is not None:
            fields.append("age = %s")
            values.append(req.age)
        if req.gender is not None:
            fields.append("gender = %s")
            values.append(req.gender)
        if req.notes is not None:
            fields.append("notes = %s")
            values.append(req.notes)

        if fields:
            values.append(user_id)
            query = f"UPDATE users SET {', '.join(fields)} WHERE id = %s"
            cur.execute(query, tuple(values))

        if req.role_codes is not None:
            cur.execute("DELETE FROM user_roles WHERE user_id = %s", (user_id,))
            for r_code in req.role_codes:
                cur.execute("SELECT id FROM roles WHERE code = %s", (r_code,))
                r_row = cur.fetchone()
                if r_row:
                    cur.execute(
                        "INSERT INTO user_roles (user_id, role_id) VALUES (%s, %s) ON CONFLICT DO NOTHING",
                        (user_id, r_row["id"])
                    )

        conn.commit()
        cur.close()
        conn.close()
        return {"status": "success", "message": "Cập nhật tài khoản thành công"}
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.put("/api/v1/users/{user_id}/password")
def change_user_password(user_id: int, req: PasswordChangeRequest, current_user: dict = Depends(require_admin_or_manager)):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT id FROM users WHERE id = %s", (user_id,))
        if not cur.fetchone():
            raise HTTPException(status_code=404, detail="Không tìm thấy người dùng")

        hashed_pwd = get_password_hash(req.new_password)
        cur.execute("UPDATE users SET password_hash = %s WHERE id = %s", (hashed_pwd, user_id))
        conn.commit()
        cur.close()
        conn.close()
        return {"status": "success", "message": "Đổi mật khẩu thành công"}
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.delete("/api/v1/users/{user_id}")
def delete_user(user_id: int, current_user: dict = Depends(require_admin_or_manager)):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT id, username FROM users WHERE id = %s", (user_id,))
        target_user = cur.fetchone()
        if not target_user:
            raise HTTPException(status_code=404, detail="Không tìm thấy người dùng")
        if target_user["username"] == "admin":
            raise HTTPException(status_code=400, detail="Không thể xóa tài khoản Quản Trị Viên hệ thống")

        cur.execute("DELETE FROM user_roles WHERE user_id = %s", (user_id,))
        cur.execute("DELETE FROM users WHERE id = %s", (user_id,))
        conn.commit()
        cur.close()
        conn.close()
        return {"status": "success", "message": "Đã xóa tài khoản thành công"}
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.get("/api/v1/users")
def get_all_users(current_user: dict = Depends(require_admin_or_manager)):
    conn = get_db()
    cur = conn.cursor()
    cur.execute("""
        SELECT u.id, u.username, u.full_name, u.phone, u.driver_type, u.contractor_name, u.customer_name, u.is_active,
               u.avatar_url, u.id_card_front_url, u.id_card_back_url, u.address, u.email, u.age, u.gender, u.notes,
               COALESCE(ARRAY_AGG(r.name) FILTER (WHERE r.name IS NOT NULL), '{}') as role_names,
               COALESCE(ARRAY_AGG(r.code) FILTER (WHERE r.code IS NOT NULL), '{}') as role_codes
        FROM users u
        LEFT JOIN user_roles ur ON u.id = ur.user_id
        LEFT JOIN roles r ON ur.role_id = r.id
        GROUP BY u.id
        ORDER BY u.id ASC
    """)
    users = cur.fetchall()
    cur.close()
    conn.close()
    return users

@app.get("/api/v1/drivers")
def get_drivers(driver_type: Optional[str] = None, current_user: dict = Depends(get_current_user)):
    conn = get_db()
    cur = conn.cursor()
    if driver_type:
        cur.execute("SELECT id, username, full_name, phone, driver_type, contractor_name, customer_name FROM users WHERE driver_type = %s", (driver_type,))
    else:
        cur.execute("SELECT id, username, full_name, phone, driver_type, contractor_name, customer_name FROM users")
    drivers = cur.fetchall()
    cur.close()
    conn.close()
    return drivers

# 3. Quản lý Sản phẩm (Tro bay, Xi măng rời...)
@app.get("/api/v1/products")
def get_products(current_user: dict = Depends(get_current_user)):
    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT * FROM products WHERE is_active = TRUE ORDER BY id ASC")
    products = cur.fetchall()
    cur.close()
    conn.close()
    return products

@app.post("/api/v1/products", status_code=status.HTTP_201_CREATED)
def create_product(product: ProductCreate, current_user: dict = Depends(get_current_user)):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute(
            """INSERT INTO products (code, name, category, unit, standard_pump_time_minutes, requires_air_pump)
               VALUES (%s, %s, %s, %s, %s, %s) RETURNING *""",
            (product.code, product.name, product.category, product.unit, product.standard_pump_time_minutes, product.requires_air_pump)
        )
        conn.commit()
        created = cur.fetchone()
        cur.close()
        conn.close()
        return created
    except HTTPException:
        conn.rollback()
        conn.close()
        raise
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.put("/api/v1/products/{product_id}")
def update_product(product_id: int, product: ProductUpdate, current_user: dict = Depends(get_current_user)):
    roles = current_user.get("roles", [])
    username = current_user.get("username", "")
    allowed = (username == "admin" or any(r in ["admin", "manager", "dispatcher"] for r in roles))
    if not allowed:
        raise HTTPException(status_code=403, detail="Chi Quan ly va Dieu phoi vi moi co quyen cap nhat san pham")

    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT * FROM products WHERE id = %s", (product_id,))
        existing = cur.fetchone()
        if not existing:
            raise HTTPException(status_code=404, detail="Khong tim thay san pham")

        fields = []
        values = []
        if product.code is not None:
            fields.append("code = %s"); values.append(product.code.strip())
        if product.name is not None:
            fields.append("name = %s"); values.append(product.name.strip())
        if product.category is not None:
            fields.append("category = %s"); values.append(product.category)
        if product.unit is not None:
            fields.append("unit = %s"); values.append(product.unit)
        if product.standard_pump_time_minutes is not None:
            fields.append("standard_pump_time_minutes = %s"); values.append(product.standard_pump_time_minutes)
        if product.requires_air_pump is not None:
            fields.append("requires_air_pump = %s"); values.append(product.requires_air_pump)

        if not fields:
            raise HTTPException(status_code=400, detail="Khong co du lieu cap nhat")
        fields.append("updated_at = NOW()")
        values.append(product_id)

        cur.execute(f"UPDATE products SET {', '.join(fields)} WHERE id = %s RETURNING *", values)
        conn.commit()
        updated = cur.fetchone()
        cur.close()
        conn.close()
        return updated
    except HTTPException:
        conn.rollback(); conn.close(); raise
    except Exception as e:
        conn.rollback(); conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.delete("/api/v1/products/{product_id}")
def delete_product(product_id: int, current_user: dict = Depends(get_current_user)):
    roles = current_user.get("roles", [])
    username = current_user.get("username", "")
    allowed = (username == "admin" or any(r in ["admin", "manager", "dispatcher"] for r in roles))
    if not allowed:
        raise HTTPException(status_code=403, detail="Chi Quan ly va Dieu phoi vi moi co quyen xoa san pham")

    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT COUNT(*) AS cnt FROM orders WHERE product_id = %s", (product_id,))
        order_count = cur.fetchone()["cnt"]
        if order_count > 0:
            raise HTTPException(status_code=400, detail=f"Khong the xoa: san pham dang co {order_count} don hang lien quan. Hay su dung trang thai 'Ngung hoat dong' thay vi xoa.")

        cur.execute("SELECT name FROM products WHERE id = %s", (product_id,))
        existing = cur.fetchone()
        if not existing:
            raise HTTPException(status_code=404, detail="Khong tim thay san pham")

        cur.execute("DELETE FROM products WHERE id = %s", (product_id,))
        conn.commit()
        cur.close()
        conn.close()
        return {"success": True, "message": f"Da xoa san pham '{existing['name']}'", "deleted_id": product_id}
    except HTTPException:
        conn.rollback(); conn.close(); raise
    except Exception as e:
        conn.rollback(); conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.get("/api/v1/customers")
def get_customers(current_user: dict = Depends(require_dispatch_staff)):
    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT * FROM customers WHERE is_active = TRUE ORDER BY name ASC, id ASC")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return rows

@app.post("/api/v1/customers", status_code=status.HTTP_201_CREATED)
def create_customer(customer: CustomerCreate, current_user: dict = Depends(require_dispatch_staff)):
    code = _clean(customer.code)
    name = _clean(customer.name)
    if not code or not name:
        raise HTTPException(status_code=400, detail="Mã khách hàng và Tên khách hàng là bắt buộc")
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT id, is_active FROM customers WHERE LOWER(code) = LOWER(%s)", (code,))
        dup = cur.fetchone()
        values = [code, name] + [_clean(getattr(customer, f)) for f in CUSTOMER_FIELDS[2:]]
        if dup and dup["is_active"]:
            raise HTTPException(status_code=400, detail=f"Mã khách hàng '{code}' đã tồn tại")
        if dup:
            # Mã từng bị xóa mềm: kích hoạt lại với thông tin mới
            cur.execute(
                f"""UPDATE customers SET {', '.join(f + ' = %s' for f in CUSTOMER_FIELDS)},
                    is_active = TRUE, updated_at = CURRENT_TIMESTAMP WHERE id = %s RETURNING *""",
                values + [dup["id"]]
            )
        else:
            cur.execute(
                f"""INSERT INTO customers ({', '.join(CUSTOMER_FIELDS)})
                    VALUES ({', '.join(['%s'] * len(CUSTOMER_FIELDS))}) RETURNING *""",
                values
            )
        created = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()
        return created
    except HTTPException:
        conn.rollback()
        conn.close()
        raise
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.put("/api/v1/customers/{customer_id}")
def update_customer(customer_id: int, customer: CustomerUpdate, current_user: dict = Depends(require_dispatch_staff)):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT id FROM customers WHERE id = %s AND is_active = TRUE", (customer_id,))
        if not cur.fetchone():
            raise HTTPException(status_code=404, detail="Không tìm thấy khách hàng")
        fields, params = [], []
        for f in CUSTOMER_FIELDS:
            raw = getattr(customer, f)
            if raw is None:
                continue
            val = _clean(raw)
            if f in ("code", "name") and not val:
                raise HTTPException(status_code=400, detail="Mã khách hàng và Tên khách hàng không được để trống")
            fields.append(f"{f} = %s")
            params.append(val)
        if "code = %s" in fields:
            new_code = params[fields.index("code = %s")]
            cur.execute("SELECT id FROM customers WHERE LOWER(code) = LOWER(%s) AND id <> %s", (new_code, customer_id))
            if cur.fetchone():
                raise HTTPException(status_code=400, detail=f"Mã khách hàng '{new_code}' đã tồn tại")
        if not fields:
            cur.execute("SELECT * FROM customers WHERE id = %s", (customer_id,))
        else:
            params.append(customer_id)
            cur.execute(
                f"UPDATE customers SET {', '.join(fields)}, updated_at = CURRENT_TIMESTAMP WHERE id = %s RETURNING *",
                params
            )
        updated = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()
        return updated
    except HTTPException:
        conn.rollback()
        conn.close()
        raise
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.delete("/api/v1/customers/{customer_id}")
def delete_customer(customer_id: int, current_user: dict = Depends(require_dispatch_staff)):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT id, name FROM customers WHERE id = %s AND is_active = TRUE", (customer_id,))
        existing = cur.fetchone()
        if not existing:
            raise HTTPException(status_code=404, detail="Không tìm thấy khách hàng")
        # Xóa mềm để giữ lịch sử
        cur.execute("UPDATE customers SET is_active = FALSE, updated_at = CURRENT_TIMESTAMP WHERE id = %s", (customer_id,))
        conn.commit()
        cur.close()
        conn.close()
        return {"message": f"Đã xóa khách hàng '{existing['name']}'"}
    except HTTPException:
        conn.rollback()
        conn.close()
        raise
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

# 3c. Đồng bộ Khách hàng từ Zalo OA (Điều phối, Quản lý, Admin)
# Cấu hình bằng biến môi trường:
#   ZALO_APP_ID, ZALO_APP_SECRET : lấy ở developers.zalo.me
#   ZALO_REDIRECT_URI            : https://saomai-api.type.vn/api/v1/zalo-oa/callback (phải khai báo y hệt trên Zalo)
ZALO_APP_ID = os.getenv("ZALO_APP_ID", "").strip()
ZALO_APP_SECRET = os.getenv("ZALO_APP_SECRET", "").strip()
ZALO_REDIRECT_URI = os.getenv("ZALO_REDIRECT_URI", "https://saomai-api.type.vn/api/v1/zalo-oa/callback").strip()
ZALO_OAUTH_BASE = os.getenv("ZALO_OAUTH_BASE", "https://oauth.zaloapp.com").rstrip("/")
ZALO_OPENAPI_BASE = os.getenv("ZALO_OPENAPI_BASE", "https://openapi.zalo.me").rstrip("/")
ZALO_PAGE_SIZE = 50  # Zalo cho tối đa 50 người mỗi trang

_zalo_lock = threading.Lock()
_zalo_sync = {"running": False}


class ZaloAuthRequired(Exception):
    pass


def _zalo_configured() -> bool:
    return bool(ZALO_APP_ID and ZALO_APP_SECRET and ZALO_REDIRECT_URI)


def _zalo_token_row(cur):
    cur.execute("SELECT * FROM zalo_oa_tokens WHERE id = 1")
    return cur.fetchone()


def _zalo_save_token(cur, data: dict, oa_id=None, authorized_by=None):
    access = data.get("access_token")
    refresh = data.get("refresh_token")
    if not access or not refresh:
        raise ZaloAuthRequired(data.get("error_description") or data.get("error_name") or "Zalo không trả về token")
    try:
        ttl = int(data.get("expires_in") or 90000)
    except (TypeError, ValueError):
        ttl = 90000
    now = datetime.now(timezone.utc)
    cur.execute(
        """INSERT INTO zalo_oa_tokens (id, oa_id, access_token, refresh_token, access_expires_at, refresh_expires_at, authorized_by, updated_at)
           VALUES (1, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
           ON CONFLICT (id) DO UPDATE SET
             oa_id = COALESCE(EXCLUDED.oa_id, zalo_oa_tokens.oa_id),
             access_token = EXCLUDED.access_token,
             refresh_token = EXCLUDED.refresh_token,
             access_expires_at = EXCLUDED.access_expires_at,
             refresh_expires_at = EXCLUDED.refresh_expires_at,
             authorized_by = COALESCE(EXCLUDED.authorized_by, zalo_oa_tokens.authorized_by),
             updated_at = CURRENT_TIMESTAMP""",
        (oa_id, access, refresh, now + timedelta(seconds=max(ttl - 300, 60)), now + timedelta(days=90), authorized_by),
    )


def _zalo_access_token() -> str:
    """Lấy access token còn hạn, tự làm mới bằng refresh token nếu đã hết hạn."""
    conn = get_db()
    cur = conn.cursor()
    try:
        row = _zalo_token_row(cur)
        if not row:
            raise ZaloAuthRequired("OA chưa được cấp quyền")
        if row["access_expires_at"] > datetime.now(timezone.utc):
            return row["access_token"]
        res = requests.post(
            f"{ZALO_OAUTH_BASE}/v4/oa/access_token",
            headers={"secret_key": ZALO_APP_SECRET},
            data={"refresh_token": row["refresh_token"], "app_id": ZALO_APP_ID, "grant_type": "refresh_token"},
            timeout=20,
        )
        data = res.json()
        if not data.get("access_token"):
            # Refresh token hết hạn hoặc đã bị thu hồi: phải cấp quyền lại
            cur.execute("DELETE FROM zalo_oa_tokens WHERE id = 1")
            conn.commit()
            raise ZaloAuthRequired(data.get("error_description") or "Refresh token Zalo không còn hiệu lực")
        _zalo_save_token(cur, data)  # Refresh token của Zalo chỉ dùng được 1 lần, phải lưu bản mới
        conn.commit()
        return data["access_token"]
    finally:
        cur.close()
        conn.close()


def _zalo_appsecret_proof(token: str) -> str:
    # Ứng dụng Zalo bật "appsecret_proof" thì mọi lời gọi OpenAPI phải kèm HMAC-SHA256(access_token, app_secret)
    return hmac.new(ZALO_APP_SECRET.encode(), token.encode(), hashlib.sha256).hexdigest()


def _zalo_get(path: str, payload: dict, token: str) -> dict:
    res = requests.get(
        f"{ZALO_OPENAPI_BASE}{path}",
        headers={"access_token": token, "appsecret_proof": _zalo_appsecret_proof(token)},
        params={"data": json.dumps(payload)},
        timeout=20,
    )
    body = res.json()
    err = body.get("error", 0)
    if err in (-216, -124, -14014):  # token không hợp lệ / hết hạn / bị thu hồi
        raise ZaloAuthRequired(body.get("message") or "Access token Zalo không hợp lệ")
    if err != 0:
        raise RuntimeError(f"Zalo trả lỗi {err}: {body.get('message')}")
    return body.get("data") or {}


def _norm_phone(p) -> str:
    digits = "".join(ch for ch in str(p or "") if ch.isdigit())
    if digits.startswith("84") and len(digits) >= 11:
        digits = "0" + digits[2:]
    return digits


def _zalo_upsert_customer(cur, info: dict) -> str:
    uid = str(info.get("user_id") or "").strip()
    if not uid:
        return "skipped"
    shared = info.get("shared_info") or {}
    display = _clean(info.get("display_name")) or _clean(info.get("user_alias"))
    name = _clean(shared.get("name")) or display or f"Zalo {uid[-6:]}"
    phone = _norm_phone(shared.get("phone")) or None
    address = ", ".join(x for x in [_clean(shared.get("address")), _clean(shared.get("district")), _clean(shared.get("city"))] if x) or None
    avatar = _clean(info.get("avatar"))

    cur.execute("SELECT id, is_active FROM customers WHERE zalo_user_id = %s", (uid,))
    row = cur.fetchone()
    if row:
        if not row["is_active"]:
            return "skipped"  # Khách đã bị xóa tay thì không tự hồi sinh
        # Chỉ ghi đè thông tin Zalo, các trường người dùng đã sửa tay chỉ được điền khi đang trống
        cur.execute(
            """UPDATE customers SET zalo_display_name = %s, zalo_avatar = %s, zalo_synced_at = CURRENT_TIMESTAMP,
                   phone = COALESCE(NULLIF(phone, ''), %s), address = COALESCE(NULLIF(address, ''), %s),
                   updated_at = CURRENT_TIMESTAMP
               WHERE id = %s""",
            (display, avatar, phone, address, row["id"]),
        )
        return "updated"

    if phone:
        # Gắn ID Zalo vào khách hàng tạo tay có cùng số điện thoại (chỉ khi khớp đúng 1 khách)
        cur.execute(
            """SELECT id, phone FROM customers WHERE is_active = TRUE AND zalo_user_id IS NULL
               AND phone IS NOT NULL AND phone <> ''""")
        same = [r["id"] for r in cur.fetchall() if _norm_phone(r["phone"]) == phone]
        if len(same) == 1:
            cur.execute(
                """UPDATE customers SET zalo_user_id = %s, zalo_display_name = %s, zalo_avatar = %s,
                       zalo_synced_at = CURRENT_TIMESTAMP, address = COALESCE(NULLIF(address, ''), %s),
                       updated_at = CURRENT_TIMESTAMP WHERE id = %s""",
                (uid, display, avatar, address, same[0]),
            )
            return "linked"

    code = f"ZL{uid}"[:50]
    cur.execute("SELECT id FROM customers WHERE LOWER(code) = LOWER(%s)", (code,))
    if cur.fetchone():
        return "skipped"
    cur.execute(
        """INSERT INTO customers (code, name, phone, address, note, source, zalo_user_id, zalo_display_name, zalo_avatar, zalo_synced_at)
           VALUES (%s, %s, %s, %s, %s, 'zalo_oa', %s, %s, %s, CURRENT_TIMESTAMP)""",
        (code, name, phone, address, "Đồng bộ từ Zalo OA", uid, display, avatar),
    )
    return "created"


def _zalo_run_sync(started_by: str):
    stats = {"total": 0, "processed": 0, "created": 0, "updated": 0, "linked": 0, "skipped": 0, "failed": 0}
    error = None
    needs_auth = False
    try:
        token = _zalo_access_token()
        user_ids, offset = [], 0
        while True:
            page = _zalo_get("/v3.0/oa/user/getlist",
                             {"offset": offset, "count": ZALO_PAGE_SIZE, "tag_name": "", "is_follower": "true"}, token)
            users = page.get("users") or []
            stats["total"] = int(page.get("total") or 0)
            user_ids += [str(u.get("user_id")) for u in users if u.get("user_id")]
            with _zalo_lock:
                _zalo_sync.update(stats)
            offset += ZALO_PAGE_SIZE
            if not users or offset >= stats["total"]:
                break
        stats["total"] = len(user_ids)
        conn = get_db()
        cur = conn.cursor()
        try:
            for uid in user_ids:
                try:
                    info = _zalo_get("/v3.0/oa/user/detail", {"user_id": uid}, token)
                    info.setdefault("user_id", uid)
                    result = _zalo_upsert_customer(cur, info)
                    conn.commit()
                    stats[result] += 1
                except ZaloAuthRequired:
                    raise
                except Exception as e:
                    conn.rollback()
                    stats["failed"] += 1
                    print(f"[zalo-oa] Lỗi đồng bộ user {uid}: {e}")
                stats["processed"] += 1
                with _zalo_lock:
                    _zalo_sync.update(stats)
        finally:
            cur.close()
            conn.close()
    except ZaloAuthRequired as e:
        needs_auth, error = True, f"Cần cấp quyền Zalo OA lại: {e}"
    except Exception as e:
        error = f"Đồng bộ thất bại: {e}"
    with _zalo_lock:
        _zalo_sync.update(stats)
        _zalo_sync.update({"running": False, "error": error, "needs_auth": needs_auth,
                           "finished_at": datetime.now(timezone.utc).isoformat(), "started_by": started_by})


def _zalo_status_payload():
    conn = get_db()
    cur = conn.cursor()
    row = _zalo_token_row(cur)
    cur.close()
    conn.close()
    with _zalo_lock:
        sync = dict(_zalo_sync)
    return {
        "configured": _zalo_configured(),
        "connected": bool(row),
        "oa_id": row["oa_id"] if row else None,
        "authorized_by": row["authorized_by"] if row else None,
        "sync": sync,
    }


@app.get("/api/v1/zalo-oa/status")
def zalo_oa_status(current_user: dict = Depends(require_dispatch_staff)):
    return _zalo_status_payload()


@app.post("/api/v1/zalo-oa/authorize-url")
def zalo_oa_authorize_url(current_user: dict = Depends(require_dispatch_staff)):
    if not _zalo_configured():
        raise HTTPException(status_code=503, detail="Máy chủ chưa cấu hình ZALO_APP_ID / ZALO_APP_SECRET")
    verifier = secrets.token_urlsafe(48)[:64]
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode("ascii")).digest()).decode().rstrip("=")
    state = secrets.token_urlsafe(24)
    conn = get_db()
    cur = conn.cursor()
    cur.execute("DELETE FROM zalo_oa_oauth_states WHERE created_at < NOW() - INTERVAL '30 minutes'")
    cur.execute("INSERT INTO zalo_oa_oauth_states (state, code_verifier, created_by) VALUES (%s, %s, %s)",
                (state, verifier, current_user["username"]))
    conn.commit()
    cur.close()
    conn.close()
    query = urlencode({"app_id": ZALO_APP_ID, "redirect_uri": ZALO_REDIRECT_URI,
                       "code_challenge": challenge, "state": state})
    return {"authorize_url": f"{ZALO_OAUTH_BASE}/v4/oa/permission?{query}", "expires_in": 1800}


def _zalo_html(title: str, message: str, ok: bool) -> HTMLResponse:
    color = "#15803d" if ok else "#b91c1c"
    body = f"""<!doctype html><html lang="vi"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>{html.escape(title)}</title></head>
<body style="font-family:sans-serif;max-width:480px;margin:60px auto;padding:0 16px;text-align:center">
<h2 style="color:{color}">{html.escape(title)}</h2><p>{html.escape(message)}</p>
<p style="color:#555">Bạn có thể đóng trang này và quay lại ứng dụng Vận tải VinTrans.</p></body></html>"""
    return HTMLResponse(body, status_code=200 if ok else 400)


@app.get("/api/v1/zalo-oa/callback", include_in_schema=False)
def zalo_oa_callback(code: Optional[str] = None, state: Optional[str] = None, oa_id: Optional[str] = None,
                     error: Optional[str] = None, error_description: Optional[str] = None):
    # Zalo chuyển trình duyệt về đây sau khi chủ OA đồng ý; bảo vệ bằng mã state dùng 1 lần
    if error or not code or not state:
        return _zalo_html("Chưa cấp quyền Zalo OA", error_description or error or "Thiếu mã xác thực từ Zalo", False)
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("DELETE FROM zalo_oa_oauth_states WHERE state = %s AND created_at > NOW() - INTERVAL '30 minutes' RETURNING *",
                    (state,))
        st = cur.fetchone()
        conn.commit()
        if not st:
            return _zalo_html("Liên kết đã hết hạn", "Hãy bấm lại nút Đồng bộ Zalo OA trong ứng dụng.", False)
        res = requests.post(
            f"{ZALO_OAUTH_BASE}/v4/oa/access_token",
            headers={"secret_key": ZALO_APP_SECRET},
            data={"code": code, "app_id": ZALO_APP_ID, "grant_type": "authorization_code",
                  "code_verifier": st["code_verifier"]},
            timeout=20,
        )
        _zalo_save_token(cur, res.json(), oa_id=oa_id, authorized_by=st["created_by"])
        conn.commit()
        return _zalo_html("Đã cấp quyền Zalo OA", "Ứng dụng sẽ tự bắt đầu đồng bộ danh sách khách hàng.", True)
    except Exception as e:
        conn.rollback()
        return _zalo_html("Cấp quyền thất bại", str(e), False)
    finally:
        cur.close()
        conn.close()


@app.post("/api/v1/zalo-oa/sync", status_code=status.HTTP_202_ACCEPTED)
def zalo_oa_sync(current_user: dict = Depends(require_dispatch_staff)):
    if not _zalo_configured():
        raise HTTPException(status_code=503, detail="Máy chủ chưa cấu hình ZALO_APP_ID / ZALO_APP_SECRET")
    status_now = _zalo_status_payload()
    if not status_now["connected"]:
        raise HTTPException(status_code=409, detail="Zalo OA chưa được cấp quyền")
    with _zalo_lock:
        if _zalo_sync.get("running"):
            return {"message": "Đang đồng bộ", "sync": dict(_zalo_sync)}
        _zalo_sync.clear()
        _zalo_sync.update({"running": True, "total": 0, "processed": 0, "created": 0, "updated": 0, "linked": 0,
                           "skipped": 0, "failed": 0, "error": None, "needs_auth": False,
                           "started_at": datetime.now(timezone.utc).isoformat(),
                           "started_by": current_user["username"]})
        snapshot = dict(_zalo_sync)
    threading.Thread(target=_zalo_run_sync, args=(current_user["username"],), daemon=True).start()
    return {"message": "Đã bắt đầu đồng bộ", "sync": snapshot}


# 4. Quản lý Roles & Permissions (Dynamic RBAC - Chỉ Admin tối cao)
@app.get("/api/v1/rbac/roles")
def get_roles(current_user: dict = Depends(require_admin_or_manager)):
    conn = get_db()
    cur = conn.cursor()
    cur.execute("""
        SELECT r.*,
               COALESCE(ARRAY_AGG(p.code) FILTER (WHERE p.code IS NOT NULL), '{}') as permission_codes,
               COALESCE(ARRAY_AGG(p.name) FILTER (WHERE p.name IS NOT NULL), '{}') as permission_names
        FROM roles r
        LEFT JOIN role_permissions rp ON r.id = rp.role_id
        LEFT JOIN permissions p ON rp.permission_id = p.id
        GROUP BY r.id
        ORDER BY r.id ASC
    """)
    roles = cur.fetchall()
    cur.close()
    conn.close()
    return roles

@app.get("/api/v1/rbac/permissions")
def get_permissions(current_user: dict = Depends(require_admin)):
    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT * FROM permissions ORDER BY module, id ASC")
    permissions = cur.fetchall()
    cur.close()
    conn.close()
    return permissions

@app.post("/api/v1/rbac/roles", status_code=status.HTTP_201_CREATED)
def create_role(role: RoleCreate, current_user: dict = Depends(require_admin)):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute(
            "INSERT INTO roles (code, name, description, is_system) VALUES (%s, %s, %s, FALSE) RETURNING *",
            (role.code.strip(), role.name.strip(), role.description)
        )
        created = cur.fetchone()
        role_id = created["id"]

        if role.permission_codes:
            for p_code in role.permission_codes:
                # Quyền user:manage chỉ dành riêng cho vai trò admin
                if p_code == "user:manage" and role.code.strip() != "admin":
                    continue
                cur.execute("SELECT id FROM permissions WHERE code = %s", (p_code,))
                p_row = cur.fetchone()
                if p_row:
                    cur.execute(
                        "INSERT INTO role_permissions (role_id, permission_id) VALUES (%s, %s) ON CONFLICT DO NOTHING",
                        (role_id, p_row["id"])
                    )

        conn.commit()
        cur.close()
        conn.close()
        return created
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.put("/api/v1/rbac/roles/{role_id}")
def update_role(role_id: int, req: RoleUpdate, current_user: dict = Depends(require_admin)):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT * FROM roles WHERE id = %s", (role_id,))
        role = cur.fetchone()
        if not role:
            raise HTTPException(status_code=404, detail="Không tìm thấy vai trò")

        fields = []
        values = []
        if req.name is not None:
            fields.append("name = %s")
            values.append(req.name.strip())
        if req.description is not None:
            fields.append("description = %s")
            values.append(req.description)

        if fields:
            values.append(role_id)
            cur.execute(f"UPDATE roles SET {', '.join(fields)} WHERE id = %s", tuple(values))

        if req.permission_codes is not None:
            cur.execute("DELETE FROM role_permissions WHERE role_id = %s", (role_id,))
            for p_code in req.permission_codes:
                # Quyền user:manage chỉ dành riêng cho vai trò admin
                if p_code == "user:manage" and role["code"] != "admin":
                    continue
                cur.execute("SELECT id FROM permissions WHERE code = %s", (p_code,))
                p_row = cur.fetchone()
                if p_row:
                    cur.execute(
                        "INSERT INTO role_permissions (role_id, permission_id) VALUES (%s, %s) ON CONFLICT DO NOTHING",
                        (role_id, p_row["id"])
                    )

        conn.commit()
        cur.close()
        conn.close()
        return {"status": "success", "message": "Cập nhật vai trò và quyền thành công"}
    except HTTPException:
        conn.rollback()
        conn.close()
        raise
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.delete("/api/v1/rbac/roles/{role_id}")
def delete_role(role_id: int, current_user: dict = Depends(require_admin)):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT * FROM roles WHERE id = %s", (role_id,))
        role = cur.fetchone()
        if not role:
            raise HTTPException(status_code=404, detail="Không tìm thấy vai trò")

        if role["is_system"] is True or role["code"] in ['admin', 'driver', 'dispatcher', 'gas_station', 'mechanic', 'manager']:
            raise HTTPException(status_code=400, detail="Không thể xóa vai trò hệ thống cốt lõi")

        # Kiểm tra xem có người dùng nào đang giữ role này không
        cur.execute("SELECT COUNT(*) as count FROM user_roles WHERE role_id = %s", (role_id,))
        cnt = cur.fetchone()["count"]
        if cnt > 0:
            raise HTTPException(status_code=400, detail=f"Không thể xóa vai trò đang được gán cho {cnt} người dùng")

        cur.execute("DELETE FROM role_permissions WHERE role_id = %s", (role_id,))
        cur.execute("DELETE FROM roles WHERE id = %s", (role_id,))
        conn.commit()
        cur.close()
        conn.close()
        return {"status": "success", "message": "Đã xóa vai trò thành công"}
    except HTTPException:
        conn.rollback()
        conn.close()
        raise
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

# 5. Quản lý Phương tiện & Cây dầu
def _validate_vehicle_driver(cur, driver_id: int, plate_number: Optional[str]):
    """Tài khoản phải có vai trò Tài xế, đang hoạt động và chưa gắn với xe khác."""
    cur.execute("""
        SELECT u.id, u.full_name, u.is_active FROM users u
        JOIN user_roles ur ON ur.user_id = u.id
        JOIN roles r ON r.id = ur.role_id
        WHERE u.id = %s AND r.code = 'driver'
    """, (driver_id,))
    drv = cur.fetchone()
    if not drv:
        raise HTTPException(status_code=400, detail="Tài khoản được chọn không phải tài khoản Tài xế")
    if drv.get("is_active") is False:
        raise HTTPException(status_code=400, detail="Tài khoản Tài xế này đang bị khóa")
    cur.execute(
        "SELECT plate_number FROM vehicles WHERE default_driver_id = %s AND plate_number <> %s",
        (driver_id, plate_number or ""),
    )
    other = cur.fetchone()
    if other:
        raise HTTPException(
            status_code=409,
            detail=f"Tài xế {drv['full_name']} đã được gắn với xe {other['plate_number']}. "
                   f"Mỗi tài xế chỉ đi kèm 1 phương tiện, hãy bỏ gán ở xe đó trước.",
        )

@app.get("/api/v1/vehicles")
def get_vehicles(include_inactive: bool = False, current_user: dict = Depends(get_current_user)):
    # Đội xe = đúng các xe trên Vietmap + Bình Anh (lỗi nhà cung cấp không làm hỏng danh sách).
    # include_inactive=true (màn Đội xe): trả thêm xe Tạm ngừng hoạt động (đã từng có trên
    # Vietmap / Bình Anh nhưng nay không còn). Mặc định chỉ trả xe đang hoạt động,
    # để các ô chọn xe khi tạo đơn hàng không hiện xe đã ngừng.
    sync_fleet_vehicles()
    conn = get_db()
    cur = conn.cursor()
    where = ("v.gps_provider IS NOT NULL" if include_inactive
             else "COALESCE(v.in_fleet, TRUE) = TRUE")
    cur.execute(f"""
        SELECT v.*, u.full_name as driver_name, u.username as driver_username, u.phone as driver_phone 
        FROM vehicles v 
        LEFT JOIN users u ON v.default_driver_id = u.id 
        WHERE {where}
        ORDER BY COALESCE(v.in_fleet, TRUE) DESC, v.plate_number ASC
    """)
    vehicles = cur.fetchall()
    cur.close()
    conn.close()
    return vehicles

@app.post("/api/v1/vehicles/sync")
def sync_vehicles_now(current_user: dict = Depends(get_current_user)):
    """Nút "Tải lại danh sách": gọi ngay Vietmap + Bình Anh để đối chiếu và đồng bộ đội xe."""
    roles = current_user.get("roles") or []
    if current_user["username"] != "admin" and not any(r in ("admin", "manager") for r in roles):
        raise HTTPException(status_code=403, detail="Chỉ Admin và Quản lý được đồng bộ đội xe")
    stats = sync_fleet_vehicles(force=True)
    if stats is None:
        raise HTTPException(status_code=409, detail="Đang có lượt đồng bộ khác, vui lòng thử lại sau ít giây")
    if not any(p.get("ok") for p in stats["providers"].values()):
        raise HTTPException(status_code=502, detail="Không kết nối được Vietmap và Bình Anh, danh sách xe giữ nguyên")
    return stats

@app.post("/api/v1/vehicles", status_code=status.HTTP_201_CREATED)
def create_vehicle(v: VehicleCreate, current_user: dict = Depends(get_current_user)):
    conn = get_db()
    cur = conn.cursor()
    try:
        if v.default_driver_id and v.default_driver_id > 0:
            _validate_vehicle_driver(cur, v.default_driver_id, v.plate_number)
        else:
            v.default_driver_id = None
        cur.execute(
            "INSERT INTO vehicles (plate_number, vehicle_type, ownership_type, default_driver_id, owner_company, status) VALUES (%s, %s, %s, %s, %s, %s) RETURNING *",
            (v.plate_number, v.vehicle_type, v.ownership_type, v.default_driver_id, v.owner_company or "Sao Mai Logistics", v.status or "ready")
        )
        conn.commit()
        created = cur.fetchone()
        cur.close()
        conn.close()
        return created
    except HTTPException:
        conn.rollback()
        conn.close()
        raise
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.put("/api/v1/vehicles/{plate_number}")
def update_vehicle(plate_number: str, v: VehicleUpdate, current_user: dict = Depends(get_current_user)):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT * FROM vehicles WHERE plate_number = %s", (plate_number,))
        exist = cur.fetchone()
        if not exist:
            cur.close()
            conn.close()
            raise HTTPException(status_code=404, detail="Không tìm thấy phương tiện")

        updates = []
        params = []
        if v.vehicle_type is not None:
            updates.append("vehicle_type = %s")
            params.append(v.vehicle_type)
        if v.ownership_type is not None:
            updates.append("ownership_type = %s")
            params.append(v.ownership_type)
        if v.default_driver_id is not None:
            if v.default_driver_id == 0 or v.default_driver_id == -1:
                updates.append("default_driver_id = NULL")
            else:
                _validate_vehicle_driver(cur, v.default_driver_id, plate_number)
                updates.append("default_driver_id = %s")
                params.append(v.default_driver_id)
        if v.owner_company is not None:
            updates.append("owner_company = %s")
            params.append(v.owner_company)
        if v.status is not None:
            updates.append("status = %s")
            params.append(v.status)

        if updates:
            updates.append("updated_at = CURRENT_TIMESTAMP")
            sql = f"UPDATE vehicles SET {', '.join(updates)} WHERE plate_number = %s RETURNING *"
            params.append(plate_number)
            cur.execute(sql, tuple(params))
            conn.commit()
            updated = cur.fetchone()
        else:
            updated = exist

        cur.close()
        conn.close()
        return updated
    except HTTPException:
        raise
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

# ----------------- DỊCH VỤ GPS BÌNH ANH -----------------
# Tài liệu: docs/Vintrans.pdf. Xác thực Basic Auth: CustomerCode / Key.
# Thông tin đăng nhập lấy từ biến môi trường, không ghi cứng trong code.
BINHANH_BASE_URL = os.getenv("BINHANH_BASE_URL", "https://apigps.binhanh.vn/apiwba/gps").rstrip("/")
BINHANH_CUSTOMER_CODE = os.getenv("BINHANH_CUSTOMER_CODE", "").strip()
BINHANH_KEY = os.getenv("BINHANH_KEY", "").strip()
BINHANH_TRACKING_CACHE_SECONDS = 20
_binhanh_tracking_cache = {"at": None, "data": None}
_binhanh_lock = threading.Lock()

BINHANH_STATE_LABELS = {
    0: "Không xác định",
    1: "Dừng đỗ tắt máy",
    2: "Dừng đỗ bật máy",
    3: "Di chuyển",
    4: "Quá tốc độ",
    5: "Mất GPS",
    6: "Mất tín hiệu",
}

def _normalize_plate(plate) -> str:
    # 50H-166.27 và 50H16627 được coi là cùng một xe
    return "".join(ch for ch in str(plate or "").upper() if ch.isalnum())

def _binhanh_post(path: str, payload: dict, timeout: int = 40) -> dict:
    if not BINHANH_CUSTOMER_CODE or not BINHANH_KEY:
        raise HTTPException(
            status_code=503,
            detail="Máy chủ chưa cấu hình tài khoản Bình Anh (BINHANH_CUSTOMER_CODE, BINHANH_KEY).",
        )
    try:
        res = requests.post(
            f"{BINHANH_BASE_URL}/{path}",
            json=payload,
            auth=(BINHANH_CUSTOMER_CODE, BINHANH_KEY),
            timeout=timeout,
        )
    except requests.RequestException as e:
        raise HTTPException(status_code=502, detail=f"Không kết nối được dịch vụ Bình Anh: {e}")
    if res.status_code != 200:
        raise HTTPException(status_code=502, detail=f"Dịch vụ Bình Anh trả về lỗi HTTP {res.status_code}")
    try:
        data = res.json()
    except ValueError:
        raise HTTPException(status_code=502, detail="Dịch vụ Bình Anh trả về dữ liệu không hợp lệ")
    message = str(data.get("MessageResult") or "").strip()
    # Bình Anh trả về các biến thể "Success", "Success!", "Success with no data"...
    if not message.lower().startswith("success"):
        raise HTTPException(status_code=502, detail=f"Bình Anh: {message or 'Lỗi không xác định'}")
    return data

def _fleet_plate_map() -> dict:
    # Biển số chuẩn hóa -> biển số trong bảng vehicles
    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT plate_number FROM vehicles")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return {_normalize_plate(r["plate_number"]): r["plate_number"] for r in rows}

QUANLYXE_BASE_URL = os.getenv("QUANLYXE_BASE_URL", "https://client-api.quanlyxe.vn/v3/tracking").rstrip("/")
QUANLYXE_API_KEY = os.getenv("QUANLYXE_API_KEY", "").strip()

FLEET_SYNC_SECONDS = 60
_fleet_sync = {"at": None}
_fleet_sync_lock = threading.Lock()

def _format_binhanh_plate(plate: str) -> str:
    # 50H16627 -> 50H-166.27 (cùng kiểu biển số đang dùng trong Đội xe)
    p = _normalize_plate(plate)
    i = 0
    while i < len(p) and p[i].isdigit():
        i += 1
    j = i
    while j < len(p) and p[j].isalpha():
        j += 1
    head, digits = p[:j], p[j:]
    if i == 2 and j > i and digits.isdigit() and len(digits) == 5:
        return f"{head}-{digits[:3]}.{digits[3:]}"
    return p

def _fetch_vietmap_vehicles() -> list:
    """Danh sách xe trên Vietmap (quanlyxe.vn). Lỗi thì ném exception."""
    if not QUANLYXE_API_KEY:
        raise RuntimeError("chưa cấu hình QUANLYXE_API_KEY")
    res = requests.get(f"{QUANLYXE_BASE_URL}/getvehicles", params={"apikey": QUANLYXE_API_KEY}, timeout=6)
    res.raise_for_status()
    data = res.json()
    rows = data.get("Data")
    if not isinstance(rows, list) or not rows:
        raise RuntimeError("Vietmap trả về danh sách rỗng hoặc không hợp lệ")
    out = []
    for v in rows:
        plate = str(v.get("Plate") or "").strip()
        if not plate:
            continue
        out.append({
            "plate": plate,
            "vehicle_id": str(v.get("Id") or ""),
            "vehicle_type": (v.get("VehicleTypeName") or "").strip() or None,
            "driver_name": None,
            "lat": None,
            "lng": None,
            "gps_time": None,
        })
    return out

def _fetch_binhanh_vehicles() -> list:
    """Danh sách xe trên Bình Anh. Lỗi thì ném exception."""
    if not BINHANH_CUSTOMER_CODE or not BINHANH_KEY:
        raise RuntimeError("chưa cấu hình BINHANH_CUSTOMER_CODE / BINHANH_KEY")
    raw = _binhanh_post("tracking", {"IsFuel": True}, timeout=6).get("Vehicles") or []
    if not raw:
        raise RuntimeError("Bình Anh trả về danh sách rỗng")
    now = datetime.now(timezone.utc)
    with _binhanh_lock:
        _binhanh_tracking_cache["at"] = now
        _binhanh_tracking_cache["data"] = raw
    out = []
    for v in raw:
        provider_plate = v.get("VehiclePlate")
        if not provider_plate:
            continue
        gps_time = None
        if v.get("UTCTime"):
            try:
                gps_time = datetime.fromisoformat(str(v["UTCTime"])).replace(tzinfo=timezone.utc)
            except ValueError:
                gps_time = None
        out.append({
            "plate": _format_binhanh_plate(provider_plate),
            "vehicle_id": str(v.get("VehicleID") or ""),
            "vehicle_type": None,
            "driver_name": v.get("DriverName"),
            "lat": v.get("Latitude"),
            "lng": v.get("Longitude"),
            "gps_time": gps_time,
        })
    return out

VEHICLE_STATUS_INACTIVE = "inactive"  # Tạm ngừng hoạt động (không còn trên Vietmap / Bình Anh)

def sync_fleet_vehicles(force: bool = False):
    """Đối chiếu đội xe với Vietmap + Bình Anh.
    - Xe có trên nhà cung cấp mà chưa có trong bảng vehicles: thêm mới.
    - Xe không còn trên nhà cung cấp nào: in_fleet = FALSE, status = 'inactive'
      (Tạm ngừng hoạt động). Không xóa để giữ lịch sử đơn hàng, kiểm tra xe.
    - Xe đang Tạm ngừng mà xuất hiện lại: chuyển về 'ready'.
    - Nhà cung cấp nào lỗi thì giữ nguyên các xe của nhà cung cấp đó, không đổi nhầm.
    Tự động: tối đa 1 lần mỗi 60 giây. force=True (nút Tải lại danh sách): chạy ngay.
    Trả về thống kê, hoặc None nếu bỏ qua do chưa tới lượt / đang có lượt khác chạy."""
    if not _fleet_sync_lock.acquire(blocking=force, timeout=30 if force else -1):
        return None
    try:
        now = datetime.now(timezone.utc)
        last = _fleet_sync["at"]
        if not force and last is not None and (now - last).total_seconds() < FLEET_SYNC_SECONDS:
            return None
        _fleet_sync["at"] = now

        stats = {
            "providers": {},
            "added": [],
            "deactivated": [],
            "reactivated": [],
            "total_active": 0,
            "total_inactive": 0,
        }
        fetched = {}
        for provider, fetch in (("vietmap", _fetch_vietmap_vehicles), ("binhanh", _fetch_binhanh_vehicles)):
            try:
                fetched[provider] = fetch()
                stats["providers"][provider] = {"ok": True, "count": len(fetched[provider])}
            except Exception as e:
                detail = getattr(e, "detail", None) or str(e)
                print(f"[fleet] Không lấy được xe {provider}: {detail}")
                stats["providers"][provider] = {"ok": False, "error": str(detail)}

        if not fetched:
            return stats  # cả hai nguồn đều lỗi: giữ nguyên danh sách hiện tại

        conn = get_db()
        cur = conn.cursor()
        try:
            cur.execute("SELECT plate_number, gps_provider, in_fleet, status FROM vehicles")
            existing = {_normalize_plate(r["plate_number"]): r for r in cur.fetchall()}
            seen = set()  # biển số chuẩn hóa đã có trên nhà cung cấp lấy được
            for provider in ("vietmap", "binhanh"):
                for v in fetched.get(provider, []):
                    key = _normalize_plate(v["plate"])
                    if not key or key in seen:
                        continue  # trùng biển giữa 2 nguồn: ưu tiên Vietmap
                    seen.add(key)
                    row = existing.get(key)
                    if row is None:
                        cur.execute(
                            """INSERT INTO vehicles (plate_number, vehicle_type, ownership_type, status)
                               VALUES (%s, %s, 'INTERNAL', 'ready')
                               ON CONFLICT (plate_number) DO NOTHING""",
                            (v["plate"], v["vehicle_type"] or "Chưa phân loại"),
                        )
                        plate = v["plate"]
                        if cur.rowcount:
                            stats["added"].append({"plate_number": plate, "provider": provider})
                        existing[key] = {"plate_number": plate, "gps_provider": provider,
                                         "in_fleet": True, "status": "ready"}
                    else:
                        plate = row["plate_number"]
                        if row.get("in_fleet") is False or row.get("status") == VEHICLE_STATUS_INACTIVE:
                            stats["reactivated"].append({"plate_number": plate, "provider": provider})
                    cur.execute(
                        """UPDATE vehicles SET in_fleet = TRUE, gps_provider = %s, gps_vehicle_id = %s,
                               status = CASE WHEN COALESCE(in_fleet, TRUE) = FALSE AND status = 'inactive' THEN 'ready' ELSE status END,
                               gps_driver_name = COALESCE(%s, gps_driver_name),
                               last_gps_lat = COALESCE(%s, last_gps_lat),
                               last_gps_lng = COALESCE(%s, last_gps_lng),
                               last_gps_time = COALESCE(%s, last_gps_time)
                           WHERE plate_number = %s""",
                        (provider, v["vehicle_id"], v["driver_name"], v["lat"], v["lng"], v["gps_time"], plate),
                    )

            # Xe không còn trên nhà cung cấp nào: Tạm ngừng hoạt động
            for key, row in existing.items():
                if key in seen:
                    continue
                prov = row.get("gps_provider")
                if len(fetched) == 2 or (prov in fetched):
                    # Đủ 2 nguồn: mọi xe thừa đều Tạm ngừng.
                    # Thiếu 1 nguồn: chỉ xét xe thuộc nguồn lấy được, xe của nguồn lỗi giữ nguyên.
                    if prov and (row.get("in_fleet") is not False or row.get("status") != VEHICLE_STATUS_INACTIVE):
                        stats["deactivated"].append({"plate_number": row["plate_number"], "provider": prov})
                    cur.execute(
                        "UPDATE vehicles SET in_fleet = FALSE, status = %s WHERE plate_number = %s",
                        (VEHICLE_STATUS_INACTIVE, row["plate_number"]),
                    )
            conn.commit()
            cur.execute(
                """SELECT COUNT(*) FILTER (WHERE in_fleet = TRUE) AS active,
                          COUNT(*) FILTER (WHERE in_fleet = FALSE) AS inactive
                   FROM vehicles WHERE gps_provider IS NOT NULL"""
            )
            cnt = cur.fetchone()
            stats["total_active"] = cnt["active"]
            stats["total_inactive"] = cnt["inactive"]
            return stats
        except Exception as e:
            conn.rollback()
            print(f"[fleet] Đồng bộ đội xe lỗi: {e}")
            stats["error"] = str(e)
            return stats
        finally:
            cur.close()
            conn.close()
    finally:
        _fleet_sync_lock.release()

def _parse_binhanh_range(from_date: str, to_date: str, max_hours: int):
    try:
        start = datetime.fromisoformat(from_date.strip())
        end = datetime.fromisoformat(to_date.strip())
    except (ValueError, AttributeError):
        raise HTTPException(status_code=400, detail="Thời gian không hợp lệ, dùng định dạng YYYY-MM-DDTHH:MM:SS")
    start = start.replace(tzinfo=None)
    end = end.replace(tzinfo=None)
    if start >= end:
        raise HTTPException(status_code=400, detail="Thời gian bắt đầu phải nhỏ hơn thời gian kết thúc")
    if end - start > timedelta(hours=max_hours):
        raise HTTPException(status_code=400, detail=f"Chỉ được lấy dữ liệu tối đa {max_hours} giờ liên tiếp")
    return start.strftime("%Y-%m-%dT%H:%M:%S"), end.strftime("%Y-%m-%dT%H:%M:%S")

@app.get("/api/v1/binhanh/status")
def binhanh_status(current_user: dict = Depends(require_admin_or_manager)):
    return {
        "configured": bool(BINHANH_CUSTOMER_CODE and BINHANH_KEY),
        "customer_code": BINHANH_CUSTOMER_CODE or None,
    }

@app.get("/api/v1/binhanh/tracking")
def binhanh_tracking(refresh: bool = False, current_user: dict = Depends(require_admin_or_manager)):
    # 1. Dữ liệu trực tuyến của toàn bộ xe Bình Anh, gắn với xe trong Đội xe theo biển số
    now = datetime.now(timezone.utc)
    with _binhanh_lock:
        cached_at = _binhanh_tracking_cache["at"]
        if (
            not refresh
            and cached_at is not None
            and (now - cached_at).total_seconds() < BINHANH_TRACKING_CACHE_SECONDS
        ):
            raw = _binhanh_tracking_cache["data"]
        else:
            raw = _binhanh_post("tracking", {"IsFuel": True}).get("Vehicles") or []
            _binhanh_tracking_cache["at"] = now
            _binhanh_tracking_cache["data"] = raw
            cached_at = now

    fleet = _fleet_plate_map()
    vehicles = []
    for v in raw:
        state = v.get("State")
        vehicles.append({
            "provider_plate": v.get("VehiclePlate"),
            "fleet_plate": fleet.get(_normalize_plate(v.get("VehiclePlate"))),
            "vehicle_id": v.get("VehicleID"),
            "utc_time": v.get("UTCTime"),
            "local_time": v.get("LocalTime"),
            "latitude": v.get("Latitude"),
            "longitude": v.get("Longitude"),
            "speed": v.get("Speed"),
            "direction": v.get("Direction"),
            "address": v.get("Address"),
            "temperature": v.get("Temperature"),
            "total_km_today": v.get("TotalKm"),
            "state": state,
            "state_label": BINHANH_STATE_LABELS.get(state, "Không xác định"),
            "minutes_driving_continuous": v.get("MinutesOfDrivingTimeContinuous"),
            "minutes_driving_today": v.get("MinutesOfDrivingTimeInDay"),
            "driver_name": v.get("DriverName"),
            "driver_license": v.get("DriverLicense"),
            "fuels": v.get("Fuels") or [],
            "door_closed": v.get("DoorClosed"),
            "soc": v.get("SOC"),
            "soh": v.get("SOH"),
        })
    return {
        "fetched_at": cached_at.isoformat(),
        "total": len(vehicles),
        "matched": sum(1 for x in vehicles if x["fleet_plate"]),
        "vehicles": vehicles,
    }

@app.get("/api/v1/binhanh/route")
def binhanh_route(plate: str, from_date: str, to_date: str, current_user: dict = Depends(require_admin_or_manager)):
    # 2. Dữ liệu lộ trình của 1 xe, tối đa 24 giờ liên tiếp
    plate_code = _normalize_plate(plate)
    if not plate_code:
        raise HTTPException(status_code=400, detail="Thiếu biển số xe")
    start, end = _parse_binhanh_range(from_date, to_date, 24)
    routes = _binhanh_post("route", {"vehiclePlate": plate_code, "fromDate": start, "toDate": end}).get("Routes") or []
    points = [
        {
            "utc_time": r.get("UTCTime"),
            "local_time": r.get("LocalTime"),
            "latitude": r.get("Latitude"),
            "longitude": r.get("Longitude"),
            "speed": r.get("Speed"),
            "address": r.get("Address"),
            "km_gps": r.get("Kmgps"),
            "is_machine_on": r.get("IsMachineOn"),
        }
        for r in routes
    ]
    return {
        "plate": plate_code,
        "from_date": start,
        "to_date": end,
        "total_points": len(points),
        "total_km": points[-1]["km_gps"] if points else 0,
        "points": points,
    }

@app.get("/api/v1/binhanh/activity")
def binhanh_activity(
    plates: str,
    from_date: str,
    to_date: str,
    is_group_km: bool = False,
    min_time: int = 0,
    current_user: dict = Depends(require_admin_or_manager),
):
    # 3. Báo cáo chi tiết hoạt động (các cuốc xe) của 1 hoặc nhiều xe
    plate_list = [p for p in (_normalize_plate(x) for x in plates.split(",")) if p]
    if not plate_list:
        raise HTTPException(status_code=400, detail="Thiếu biển số xe")
    start, end = _parse_binhanh_range(from_date, to_date, 24 * 31)
    data = _binhanh_post(
        "rpactdetails",
        {
            "VehiclePlate": ",".join(plate_list),
            "fromDate": start,
            "toDate": end,
            "isGroupKm": is_group_km,
            "minTime": max(0, min_time),
        },
        timeout=90,
    )
    rows = data.get("BAReportActivityDetails") or []
    items = [
        {
            "vehicle_type_name": r.get("VehicleTypeName"),
            "plate": r.get("VehiclePlate"),
            "report_date": r.get("ReportDate"),
            "start_time": r.get("StartTime"),
            "end_time": r.get("EndTime"),
            "total_minutes": r.get("TotalTime"),
            "km_gps": r.get("KmGPS"),
            "km_mechanical": r.get("KmOfPulseMechanical"),
            "constant_norms": r.get("ConstantNorms"),
            "norms": r.get("Norms"),
            "start_address": r.get("StartAddress"),
            "end_address": r.get("EndAddress"),
            "is_supplemental": r.get("IsSupplemental"),
            "start_latitude": r.get("StartLatitude"),
            "start_longitude": r.get("StartLongitude"),
            "end_latitude": r.get("EndLatitude"),
            "end_longitude": r.get("EndLongitude"),
        }
        for r in rows
    ]
    return {
        "message": data.get("MessageResult"),
        "from_date": start,
        "to_date": end,
        "total": len(items),
        "items": items,
    }


# ----------------- ĐIỂM NHẬN / GIAO HÀNG -----------------
# Danh mục do người dùng quản lý (bảng locations) + gợi ý tự gom từ lịch sử dừng đỗ
# của Vietmap (GetVehicleStopReports) và Bình Anh (route, tự tính đoạn tốc độ 0).
LOCATION_KINDS = ("PICKUP", "DELIVERY", "BOTH")
LOCATION_CLUSTER_METERS = 250
_location_scan = {"running": False, "started_at": None, "finished_at": None,
                  "progress": "", "result": None, "error": None}
_location_scan_lock = threading.Lock()

def _clean_kind(kind: Optional[str]) -> str:
    k = (kind or "BOTH").strip().upper()
    if k not in LOCATION_KINDS:
        raise HTTPException(status_code=400, detail="Loại điểm phải là PICKUP, DELIVERY hoặc BOTH")
    return k

def _check_lat_lng(lat, lng):
    if (lat is None) != (lng is None):
        raise HTTPException(status_code=400, detail="Phải nhập đủ cả vĩ độ và kinh độ")
    if lat is not None and not (-90 <= lat <= 90 and -180 <= lng <= 180):
        raise HTTPException(status_code=400, detail="Tọa độ không hợp lệ")

@app.get("/api/v1/locations")
def get_locations(kind: Optional[str] = None, current_user: dict = Depends(require_dispatch_staff)):
    conn = get_db()
    cur = conn.cursor()
    if kind:
        k = _clean_kind(kind)
        cur.execute(
            "SELECT * FROM locations WHERE is_active = TRUE AND (kind = %s OR kind = 'BOTH') ORDER BY name ASC, id ASC",
            (k,),
        )
    else:
        cur.execute("SELECT * FROM locations WHERE is_active = TRUE ORDER BY name ASC, id ASC")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return rows

@app.post("/api/v1/locations", status_code=status.HTTP_201_CREATED)
def create_location(loc: LocationCreate, current_user: dict = Depends(require_dispatch_staff)):
    name = _clean(loc.name)
    if not name:
        raise HTTPException(status_code=400, detail="Tên điểm là bắt buộc")
    kind = _clean_kind(loc.kind)
    _check_lat_lng(loc.latitude, loc.longitude)
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT id FROM locations WHERE is_active = TRUE AND LOWER(name) = LOWER(%s)", (name,))
        if cur.fetchone():
            raise HTTPException(status_code=400, detail=f"Điểm '{name}' đã có trong danh mục")
        cur.execute(
            """INSERT INTO locations (name, address, kind, latitude, longitude, radius_m, note, source)
               VALUES (%s, %s, %s, %s, %s, %s, %s, 'MANUAL') RETURNING *""",
            (name, _clean(loc.address), kind, loc.latitude, loc.longitude, loc.radius_m or DEFAULT_ORDER_POINT_RADIUS_M, _clean(loc.note)),
        )
        row = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()
        return row
    except HTTPException:
        conn.rollback(); conn.close(); raise
    except Exception as e:
        conn.rollback(); conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.put("/api/v1/locations/{location_id}")
def update_location(location_id: int, loc: LocationUpdate, current_user: dict = Depends(require_dispatch_staff)):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT * FROM locations WHERE id = %s AND is_active = TRUE", (location_id,))
        current = cur.fetchone()
        if not current:
            raise HTTPException(status_code=404, detail="Không tìm thấy điểm")
        fields, params = [], []
        if loc.name is not None:
            name = _clean(loc.name)
            if not name:
                raise HTTPException(status_code=400, detail="Tên điểm không được để trống")
            cur.execute(
                "SELECT id FROM locations WHERE is_active = TRUE AND LOWER(name) = LOWER(%s) AND id <> %s",
                (name, location_id),
            )
            if cur.fetchone():
                raise HTTPException(status_code=400, detail=f"Điểm '{name}' đã có trong danh mục")
            fields.append("name = %s"); params.append(name)
        if loc.address is not None:
            fields.append("address = %s"); params.append(_clean(loc.address))
        if loc.kind is not None:
            fields.append("kind = %s"); params.append(_clean_kind(loc.kind))
        lat = loc.latitude if loc.latitude is not None else current["latitude"]
        lng = loc.longitude if loc.longitude is not None else current["longitude"]
        if loc.latitude is not None or loc.longitude is not None:
            _check_lat_lng(lat, lng)
            fields.append("latitude = %s"); params.append(lat)
            fields.append("longitude = %s"); params.append(lng)
        if loc.radius_m is not None:
            fields.append("radius_m = %s"); params.append(max(50, int(loc.radius_m)))
        if loc.note is not None:
            fields.append("note = %s"); params.append(_clean(loc.note))
        if fields:
            params.append(location_id)
            cur.execute(
                f"UPDATE locations SET {', '.join(fields)}, updated_at = CURRENT_TIMESTAMP WHERE id = %s RETURNING *",
                params,
            )
            current = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()
        return current
    except HTTPException:
        conn.rollback(); conn.close(); raise
    except Exception as e:
        conn.rollback(); conn.close()
        raise HTTPException(status_code=400, detail=str(e))

class LocationBulkDelete(BaseModel):
    ids: List[int]

@app.post("/api/v1/locations/bulk-delete")
def bulk_delete_locations(body: LocationBulkDelete, current_user: dict = Depends(require_dispatch_staff)):
    """Xóa nhiều điểm cùng lúc (giống nút Xóa từng dòng): ẩn điểm, gợi ý GPS đã duyệt thành điểm đó quay về Chờ duyệt."""
    ids = list(dict.fromkeys(int(i) for i in (body.ids or [])))
    if not ids:
        raise HTTPException(status_code=400, detail="Chưa chọn điểm nào")
    if len(ids) > 1000:
        raise HTTPException(status_code=400, detail="Mỗi lần xóa tối đa 1000 điểm")
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT id FROM locations WHERE is_active = TRUE AND id = ANY(%s)", (ids,))
        found = [r["id"] for r in cur.fetchall()]
        if found:
            cur.execute("UPDATE locations SET is_active = FALSE, updated_at = CURRENT_TIMESTAMP WHERE id = ANY(%s)", (found,))
            cur.execute(
                "UPDATE location_suggestions SET status = 'PENDING', location_id = NULL, updated_at = CURRENT_TIMESTAMP WHERE location_id = ANY(%s)",
                (found,),
            )
        conn.commit()
        cur.close()
        conn.close()
        return {"deleted": len(found), "skipped": len(ids) - len(found)}
    except HTTPException:
        conn.rollback(); conn.close(); raise
    except Exception as e:
        conn.rollback(); conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.delete("/api/v1/locations/{location_id}")
def delete_location(location_id: int, current_user: dict = Depends(require_dispatch_staff)):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT id, name FROM locations WHERE id = %s AND is_active = TRUE", (location_id,))
        existing = cur.fetchone()
        if not existing:
            raise HTTPException(status_code=404, detail="Không tìm thấy điểm")
        cur.execute("UPDATE locations SET is_active = FALSE, updated_at = CURRENT_TIMESTAMP WHERE id = %s", (location_id,))
        # Gợi ý đã duyệt thành điểm này được trả về hàng chờ để có thể duyệt lại
        cur.execute(
            "UPDATE location_suggestions SET status = 'PENDING', location_id = NULL, updated_at = CURRENT_TIMESTAMP WHERE location_id = %s",
            (location_id,),
        )
        conn.commit()
        cur.close()
        conn.close()
        return {"message": f"Đã xóa điểm '{existing['name']}'"}
    except HTTPException:
        conn.rollback(); conn.close(); raise
    except Exception as e:
        conn.rollback(); conn.close()
        raise HTTPException(status_code=400, detail=str(e))

def _vietmap_stops(days: int, min_stop_minutes: int, progress) -> list:
    """Các lần dừng đỗ của toàn bộ xe Vietmap trong `days` ngày gần nhất (tối đa 31 ngày)."""
    vehicles = _fetch_vietmap_vehicles()
    end = datetime.now(timezone(timedelta(hours=7))).date()
    start = end - timedelta(days=max(1, min(days, 31)) - 1)
    stops = []
    for i, v in enumerate(vehicles, 1):
        progress(f"Vietmap: xe {v['plate']} ({i}/{len(vehicles)})")
        try:
            # Lưu ý: from/to phải là YYYY-MM-DD, truyền kèm giờ sẽ nhận 204NoContent
            res = requests.get(
                f"{QUANLYXE_BASE_URL}/GetVehicleStopReports",
                params={"plate": v["plate"], "from": start.isoformat(), "to": end.isoformat(),
                        "duration": min_stop_minutes * 60, "apikey": QUANLYXE_API_KEY},
                timeout=60,
            )
            rows = res.json().get("Data") or []
        except Exception as e:
            print(f"[locations] Vietmap {v['plate']}: {e}")
            continue
        for r in rows:
            lat, lng = r.get("Y"), r.get("X")  # X = kinh độ, Y = vĩ độ
            if not lat or not lng:
                continue
            stops.append({
                "provider": "vietmap", "plate": v["plate"], "lat": float(lat), "lng": float(lng),
                "address": (r.get("Address") or "").strip(), "station": (r.get("Station") or "").strip(),
                "minutes": int((r.get("Duration") or 0) / 60),
                "from": r.get("FromTime"), "to": r.get("ToTime"),
            })
    return stops

def _binhanh_stops(days: int, min_stop_minutes: int, progress) -> list:
    """Tự tính các lần dừng từ lộ trình Bình Anh: chuỗi điểm liên tiếp có tốc độ 0, đứng gần nhau."""
    raw = _binhanh_post("tracking", {"IsFuel": True}, timeout=20).get("Vehicles") or []
    plates = [_normalize_plate(v.get("VehiclePlate")) for v in raw if v.get("VehiclePlate")]
    today = datetime.now(timezone(timedelta(hours=7))).replace(tzinfo=None, hour=0, minute=0, second=0, microsecond=0)
    n_days = max(1, min(days, 31))
    stops = []

    def flush(seg, plate):
        if not seg:
            return
        t0 = datetime.fromisoformat(seg[0]["LocalTime"])
        t1 = datetime.fromisoformat(seg[-1]["LocalTime"])
        minutes = int((t1 - t0).total_seconds() / 60)
        if minutes < min_stop_minutes:
            return
        mid = seg[len(seg) // 2]
        stops.append({
            "provider": "binhanh", "plate": _format_binhanh_plate(plate),
            "lat": float(mid["Latitude"]), "lng": float(mid["Longitude"]),
            "address": (mid.get("Address") or "").strip(), "station": "",
            "minutes": minutes, "from": seg[0]["LocalTime"], "to": seg[-1]["LocalTime"],
        })

    for i, plate in enumerate(plates, 1):
        for d in range(n_days):
            day = today - timedelta(days=d)
            progress(f"Bình Anh: xe {_format_binhanh_plate(plate)} ({i}/{len(plates)}), ngày {day:%d/%m}")
            try:
                routes = _binhanh_post("route", {
                    "vehiclePlate": plate,
                    "fromDate": day.strftime("%Y-%m-%dT00:00:00"),
                    "toDate": day.strftime("%Y-%m-%dT23:59:59"),
                }, timeout=90).get("Routes") or []
            except HTTPException as e:
                print(f"[locations] Bình Anh {plate} {day:%Y-%m-%d}: {e.detail}")
                continue
            seg = []
            for r in routes:
                if not r.get("Latitude") or not r.get("Longitude") or not r.get("LocalTime"):
                    continue
                still = (r.get("Speed") or 0) <= 2
                if still and (not seg or haversine_distance(
                        seg[0]["Latitude"], seg[0]["Longitude"], r["Latitude"], r["Longitude"]) <= 150):
                    seg.append(r)
                else:
                    flush(seg, plate)
                    seg = [r] if still else []
            flush(seg, plate)
    return stops

def _cluster_stops(stops: list) -> list:
    """Gom các lần dừng cách nhau không quá LOCATION_CLUSTER_METERS thành một cụm."""
    clusters = []
    for st in sorted(stops, key=lambda x: -x["minutes"]):
        target = None
        for c in clusters:
            if haversine_distance(c["lat"], c["lng"], st["lat"], st["lng"]) <= LOCATION_CLUSTER_METERS:
                target = c
                break
        if target is None:
            target = {"lat": st["lat"], "lng": st["lng"], "stops": []}
            clusters.append(target)
        target["stops"].append(st)
    out = []
    for c in clusters:
        ss = c["stops"]
        addr_count, station_count = {}, {}
        for s_ in ss:
            if s_["address"]:
                addr_count[s_["address"]] = addr_count.get(s_["address"], 0) + 1
            if s_["station"]:
                station_count[s_["station"]] = station_count.get(s_["station"], 0) + 1
        times = [t for s_ in ss for t in (s_["from"], s_["to"]) if t]
        out.append({
            "lat": c["lat"], "lng": c["lng"],
            "address": max(addr_count, key=addr_count.get) if addr_count else None,
            "station": max(station_count, key=station_count.get) if station_count else None,
            "visit_count": len(ss),
            "total_minutes": sum(s_["minutes"] for s_ in ss),
            "vehicles": sorted({s_["plate"] for s_ in ss}),
            "first_seen": min(times)[:19] if times else None,
            "last_seen": max(times)[:19] if times else None,
        })
    return out

def _address_key(value) -> str:
    """Khóa so trùng địa chỉ: chuẩn Unicode, chữ thường, bỏ dấu câu và khoảng trắng thừa."""
    if not value:
        return ""
    text = unicodedata.normalize("NFC", str(value)).lower()
    text = "".join(ch if ch.isalnum() else " " for ch in text)
    return " ".join(text.split())

def _merge_clusters_by_address(clusters: list) -> list:
    """Các cụm có cùng địa chỉ được gộp làm một, lấy tọa độ của cụm xe dừng nhiều nhất."""
    merged, order = {}, []
    for c in sorted(clusters, key=lambda x: (-x["visit_count"], -x["total_minutes"])):
        key = _address_key(c["address"])
        if not key:
            order.append(c)
            continue
        m = merged.get(key)
        if m is None:
            m = dict(c, vehicles=list(c["vehicles"]))
            merged[key] = m
            order.append(m)
            continue
        m["visit_count"] += c["visit_count"]
        m["total_minutes"] += c["total_minutes"]
        m["vehicles"] = sorted(set(m["vehicles"]) | set(c["vehicles"]))
        m["station"] = m["station"] or c["station"]
        firsts = [t for t in (m["first_seen"], c["first_seen"]) if t]
        lasts = [t for t in (m["last_seen"], c["last_seen"]) if t]
        m["first_seen"] = min(firsts) if firsts else None
        m["last_seen"] = max(lasts) if lasts else None
    return order

def _save_location_suggestions(clusters: list) -> dict:
    conn = get_db()
    cur = conn.cursor()
    try:
        # Địa chỉ / tên đã có trong danh mục điểm
        cur.execute("SELECT name, address, latitude, longitude, radius_m FROM locations WHERE is_active = TRUE")
        catalog = cur.fetchall()
        catalog_keys = {k for l in catalog for k in (_address_key(l["address"]), _address_key(l["name"])) if k}
        catalog_coords = [l for l in catalog if l["latitude"] is not None and l["longitude"] is not None]
        # Gợi ý đã từng lưu (mọi trạng thái: chờ duyệt, đã duyệt, đã bỏ qua)
        cur.execute("SELECT address, station_name, latitude, longitude FROM location_suggestions")
        existing = cur.fetchall()
        existing_keys = {_address_key(e["address"]) for e in existing if _address_key(e["address"])}
        existing_no_addr = [e for e in existing if not _address_key(e["address"])]
        inserted = skipped_catalog = skipped_existing = 0
        for c in _merge_clusters_by_address(clusters):
            key = _address_key(c["address"])
            if key and key in catalog_keys:
                skipped_catalog += 1
                continue
            if any(haversine_distance(l["latitude"], l["longitude"], c["lat"], c["lng"])
                   <= max(l["radius_m"] or DEFAULT_ORDER_POINT_RADIUS_M, LOCATION_CLUSTER_METERS) for l in catalog_coords):
                skipped_catalog += 1
                continue
            if key:
                if key in existing_keys:
                    skipped_existing += 1
                    continue
            elif any(haversine_distance(e["latitude"], e["longitude"], c["lat"], c["lng"])
                     <= LOCATION_CLUSTER_METERS for e in existing_no_addr):
                # Không có địa chỉ để so thì so theo tọa độ
                skipped_existing += 1
                continue
            cur.execute(
                """INSERT INTO location_suggestions (address, station_name, visit_count, total_minutes,
                   vehicle_count, vehicles, first_seen, last_seen, latitude, longitude)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
                (c["address"], c["station"], c["visit_count"], c["total_minutes"], len(c["vehicles"]),
                 ", ".join(c["vehicles"]), c["first_seen"], c["last_seen"], c["lat"], c["lng"]),
            )
            if key:
                existing_keys.add(key)
            else:
                existing_no_addr.append({"latitude": c["lat"], "longitude": c["lng"]})
            inserted += 1
        conn.commit()
        return {"inserted": inserted, "skipped_in_catalog": skipped_catalog, "skipped_existing": skipped_existing}
    finally:
        cur.close()
        conn.close()

def _run_location_scan(req: LocationScanRequest):
    def progress(msg):
        _location_scan["progress"] = msg
    result = {"stops": 0, "errors": []}
    try:
        stops = []
        if (req.vietmap_days or 0) > 0:
            try:
                vm = _vietmap_stops(req.vietmap_days, req.min_stop_minutes or 15, progress)
                stops += vm
            except Exception as e:
                result["errors"].append(f"Vietmap: {getattr(e, 'detail', e)}")
        if (req.binhanh_days or 0) > 0:
            try:
                ba = _binhanh_stops(req.binhanh_days, req.min_stop_minutes or 15, progress)
                stops += ba
            except Exception as e:
                result["errors"].append(f"Bình Anh: {getattr(e, 'detail', e)}")
        result["stops"] = len(stops)
        progress("Đang gom cụm và lưu gợi ý")
        clusters = _cluster_stops(stops)
        result["clusters"] = len(clusters)
        result.update(_save_location_suggestions(clusters))
        _location_scan["result"] = result
    except Exception as e:
        _location_scan["error"] = str(e)
        _location_scan["result"] = result
    finally:
        _location_scan["running"] = False
        _location_scan["finished_at"] = datetime.now(timezone.utc).isoformat()
        _location_scan["progress"] = "Hoàn tất" if not _location_scan["error"] else "Lỗi"

@app.post("/api/v1/locations/scan")
def start_location_scan(req: LocationScanRequest, current_user: dict = Depends(require_dispatch_staff)):
    with _location_scan_lock:
        if _location_scan["running"]:
            return {"started": False, "message": "Đang có một lượt quét chạy, vui lòng chờ", **_location_scan}
        _location_scan.update({"running": True, "started_at": datetime.now(timezone.utc).isoformat(),
                               "finished_at": None, "progress": "Bắt đầu quét", "result": None, "error": None})
    threading.Thread(target=_run_location_scan, args=(req,), daemon=True).start()
    return {"started": True, "message": "Đã bắt đầu quét lịch sử dừng đỗ", **_location_scan}

@app.get("/api/v1/locations/scan/status")
def location_scan_status(current_user: dict = Depends(require_dispatch_staff)):
    return dict(_location_scan)

@app.get("/api/v1/location-suggestions")
def get_location_suggestions(status_filter: Optional[str] = "PENDING", current_user: dict = Depends(require_dispatch_staff)):
    conn = get_db()
    cur = conn.cursor()
    st = (status_filter or "").strip().upper()
    if st in ("PENDING", "APPROVED", "IGNORED"):
        cur.execute("SELECT * FROM location_suggestions WHERE status = %s ORDER BY visit_count DESC, total_minutes DESC", (st,))
    else:
        cur.execute("SELECT * FROM location_suggestions ORDER BY visit_count DESC, total_minutes DESC")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return rows

@app.post("/api/v1/location-suggestions/bulk-approve")
def bulk_approve_location_suggestions(body: LocationSuggestionBulkApprove,
                                      current_user: dict = Depends(require_dispatch_staff)):
    """Duyệt nhiều gợi ý cùng lúc. Tên điểm = tên trạm hoặc địa chỉ GPS.
    Gợi ý nào lỗi (đã duyệt, trùng tên trong danh mục...) thì bỏ qua, các gợi ý khác vẫn được duyệt."""
    ids = list(dict.fromkeys(int(i) for i in (body.ids or [])))
    if not ids:
        raise HTTPException(status_code=400, detail="Chưa chọn gợi ý nào")
    if len(ids) > 1000:
        raise HTTPException(status_code=400, detail="Mỗi lần duyệt tối đa 1000 gợi ý")
    kind = _clean_kind(body.kind)
    conn = get_db()
    cur = conn.cursor()
    approved, skipped = [], []
    try:
        for sid in ids:
            cur.execute("SAVEPOINT bulk_item")
            try:
                cur.execute("SELECT * FROM location_suggestions WHERE id = %s", (sid,))
                sug = cur.fetchone()
                if not sug:
                    skipped.append({"id": sid, "reason": "Không tìm thấy gợi ý"}); cur.execute("RELEASE SAVEPOINT bulk_item"); continue
                if sug["status"] != "PENDING":
                    skipped.append({"id": sid, "reason": "Gợi ý không còn ở trạng thái chờ duyệt"}); cur.execute("RELEASE SAVEPOINT bulk_item"); continue
                name = _clean(sug["station_name"]) or _clean(sug["address"])
                if not name:
                    skipped.append({"id": sid, "reason": "Gợi ý không có tên hoặc địa chỉ"}); cur.execute("RELEASE SAVEPOINT bulk_item"); continue
                cur.execute("SELECT id FROM locations WHERE is_active = TRUE AND LOWER(name) = LOWER(%s)", (name,))
                if cur.fetchone():
                    skipped.append({"id": sid, "name": name, "reason": f"Điểm '{name}' đã có trong danh mục"}); cur.execute("RELEASE SAVEPOINT bulk_item"); continue
                cur.execute(
                    """INSERT INTO locations (name, address, kind, latitude, longitude, radius_m, note, source)
                       VALUES (%s, %s, %s, %s, %s, %s, NULL, %s) RETURNING id""",
                    (name, _clean(sug["address"]), kind, sug["latitude"], sug["longitude"], DEFAULT_ORDER_POINT_RADIUS_M, "GPS"),
                )
                loc_id = cur.fetchone()["id"]
                cur.execute(
                    "UPDATE location_suggestions SET status = 'APPROVED', location_id = %s, updated_at = CURRENT_TIMESTAMP WHERE id = %s",
                    (loc_id, sid),
                )
                cur.execute("RELEASE SAVEPOINT bulk_item")
                approved.append({"id": sid, "location_id": loc_id, "name": name})
            except Exception as e:
                cur.execute("ROLLBACK TO SAVEPOINT bulk_item")
                skipped.append({"id": sid, "reason": str(e)})
        conn.commit()
        cur.close()
        conn.close()
        return {"approved": len(approved), "skipped": len(skipped),
                "approved_items": approved, "skipped_items": skipped}
    except HTTPException:
        conn.rollback(); conn.close(); raise
    except Exception as e:
        conn.rollback(); conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.post("/api/v1/location-suggestions/{suggestion_id}/approve", status_code=status.HTTP_201_CREATED)
def approve_location_suggestion(suggestion_id: int, body: LocationSuggestionApprove,
                                current_user: dict = Depends(require_dispatch_staff)):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT * FROM location_suggestions WHERE id = %s", (suggestion_id,))
        sug = cur.fetchone()
        if not sug:
            raise HTTPException(status_code=404, detail="Không tìm thấy gợi ý")
        if sug["status"] == "APPROVED" and sug["location_id"]:
            raise HTTPException(status_code=400, detail="Gợi ý này đã được duyệt")
        name = _clean(body.name) or sug["station_name"] or sug["address"]
        if not name:
            raise HTTPException(status_code=400, detail="Tên điểm là bắt buộc")
        cur.execute("SELECT id FROM locations WHERE is_active = TRUE AND LOWER(name) = LOWER(%s)", (name,))
        if cur.fetchone():
            raise HTTPException(status_code=400, detail=f"Điểm '{name}' đã có trong danh mục")
        cur.execute(
            """INSERT INTO locations (name, address, kind, latitude, longitude, radius_m, note, source)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s) RETURNING *""",
            (name, _clean(body.address) or sug["address"], _clean_kind(body.kind),
             sug["latitude"], sug["longitude"], DEFAULT_ORDER_POINT_RADIUS_M, _clean(body.note), "GPS"),
        )
        loc = cur.fetchone()
        cur.execute(
            "UPDATE location_suggestions SET status = 'APPROVED', location_id = %s, updated_at = CURRENT_TIMESTAMP WHERE id = %s",
            (loc["id"], suggestion_id),
        )
        conn.commit()
        cur.close()
        conn.close()
        return loc
    except HTTPException:
        conn.rollback(); conn.close(); raise
    except Exception as e:
        conn.rollback(); conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.post("/api/v1/location-suggestions/{suggestion_id}/ignore")
def ignore_location_suggestion(suggestion_id: int, current_user: dict = Depends(require_dispatch_staff)):
    conn = get_db()
    cur = conn.cursor()
    cur.execute(
        "UPDATE location_suggestions SET status = 'IGNORED', updated_at = CURRENT_TIMESTAMP WHERE id = %s AND status = 'PENDING' RETURNING id",
        (suggestion_id,),
    )
    row = cur.fetchone()
    conn.commit()
    cur.close()
    conn.close()
    if not row:
        raise HTTPException(status_code=404, detail="Không tìm thấy gợi ý đang chờ duyệt")
    return {"message": "Đã bỏ qua gợi ý"}

@app.post("/api/v1/location-suggestions/{suggestion_id}/restore")
def restore_location_suggestion(suggestion_id: int, current_user: dict = Depends(require_dispatch_staff)):
    conn = get_db()
    cur = conn.cursor()
    cur.execute(
        "UPDATE location_suggestions SET status = 'PENDING', updated_at = CURRENT_TIMESTAMP WHERE id = %s AND status = 'IGNORED' RETURNING id",
        (suggestion_id,),
    )
    row = cur.fetchone()
    conn.commit()
    cur.close()
    conn.close()
    if not row:
        raise HTTPException(status_code=404, detail="Không tìm thấy gợi ý đã bỏ qua")
    return {"message": "Đã đưa gợi ý về hàng chờ duyệt"}

@app.get("/api/v1/gas-stations")
def get_gas_stations(current_user: dict = Depends(get_current_user)):
    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT * FROM gas_stations ORDER BY id ASC")
    stations = cur.fetchall()
    cur.close()
    conn.close()
    return stations

@app.post("/api/v1/gas-stations", status_code=status.HTTP_201_CREATED)
def create_gas_station(gs: GasStationCreate, current_user: dict = Depends(get_current_user)):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute(
            """INSERT INTO gas_stations (name, address, lat, lng, allowed_radius_meters, user_id)
               VALUES (%s, %s, %s, %s, %s, %s) RETURNING *""",
            (gs.name, gs.address, gs.lat, gs.lng, gs.allowed_radius_meters, gs.user_id)
        )
        conn.commit()
        created = cur.fetchone()
        cur.close()
        conn.close()
        return created
    except HTTPException:
        conn.rollback()
        conn.close()
        raise
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.put("/api/v1/gas-stations/{station_id}")
def update_gas_station(station_id: int, gs: GasStationCreate, current_user: dict = Depends(get_current_user)):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute(
            """UPDATE gas_stations
               SET name = %s, address = %s, lat = %s, lng = %s, allowed_radius_meters = %s
               WHERE id = %s RETURNING *""",
            (gs.name, gs.address, gs.lat, gs.lng, gs.allowed_radius_meters, station_id)
        )
        conn.commit()
        updated = cur.fetchone()
        cur.close()
        conn.close()
        if not updated:
            raise HTTPException(status_code=404, detail="Khong tim thay cay dau")
        return updated
    except HTTPException:
        raise
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.delete("/api/v1/gas-stations/{station_id}")
def delete_gas_station(station_id: int, current_user: dict = Depends(get_current_user)):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT * FROM gas_stations WHERE id = %s", (station_id,))
        existing = cur.fetchone()
        if not existing:
            cur.close()
            conn.close()
            raise HTTPException(status_code=404, detail="Khong tim thay cay dau")
        cur.execute("DELETE FROM gas_stations WHERE id = %s", (station_id,))
        conn.commit()
        cur.close()
        conn.close()
        return {"success": True, "deleted_id": station_id}
    except HTTPException:
        raise
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.get("/api/v1/reports/summary")
def get_reports_summary(current_user: dict = Depends(get_current_user)):
    sync_fleet_vehicles()
    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) as total_vehicles FROM vehicles WHERE COALESCE(in_fleet, TRUE) = TRUE")
    total_vehicles = cur.fetchone()["total_vehicles"]
    cur.execute("SELECT COUNT(*) as total_orders FROM orders")
    total_orders = cur.fetchone()["total_orders"]
    cur.execute("SELECT COUNT(*) as total_inspections FROM kiem_tra_dau_ngay WHERE check_date = CURRENT_DATE")
    today_inspections = cur.fetchone()["total_inspections"]
    cur.execute("SELECT COUNT(*) as flagged_anomalies FROM kiem_tra_dau_ngay WHERE check_date = CURRENT_DATE AND (flag_deviation_km = TRUE OR flag_status = 'rejected')")
    flagged_anomalies = cur.fetchone()["flagged_anomalies"]
    cur.execute("SELECT COUNT(*) as active_breakdowns FROM bao_hong WHERE decision = 'pending'")
    active_breakdowns = cur.fetchone()["active_breakdowns"]
    cur.execute("SELECT COUNT(*) as fuel_mismatches FROM cap_dau WHERE flag_location_mismatch = TRUE")
    fuel_mismatches = cur.fetchone()["fuel_mismatches"]
    cur.close()
    conn.close()
    return {
        "total_vehicles": total_vehicles,
        "total_orders": total_orders,
        "today_inspections": today_inspections,
        "flagged_anomalies": flagged_anomalies,
        "active_breakdowns": active_breakdowns,
        "fuel_mismatches": fuel_mismatches,
        "compliance_rate": "96.4%",
        "avg_pump_time_minutes": 78
    }

# 6. Quản lý Đơn hàng (Orders)
def _vehicle_driver_id(cur, plate: Optional[str]) -> int:
    """Mỗi xe có một tài khoản tài xế phụ trách: lấy tài xế của đơn theo xe."""
    plate = (plate or "").strip()
    if not plate:
        raise HTTPException(status_code=400, detail="Vui lòng chọn phương tiện vận chuyển")
    cur.execute("SELECT default_driver_id FROM vehicles WHERE plate_number = %s", (plate,))
    row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=400, detail=f"Không tìm thấy xe {plate}")
    if not row["default_driver_id"]:
        raise HTTPException(status_code=400, detail=f"Xe {plate} chưa được gán tài xế phụ trách. Vào Đội xe & Tài xế để gán trước.")
    return row["default_driver_id"]

@app.post("/api/v1/orders", status_code=status.HTTP_201_CREATED)
def create_order(o: OrderCreate, current_user: dict = Depends(get_current_user)):
    _validate_order_point(o.pickup_lat, o.pickup_lng, "Nơi nhận hàng")
    _validate_order_point(o.delivery_lat, o.delivery_lng, "Điểm giao hàng")
    conn = get_db()
    cur = conn.cursor()
    try:
        o.assigned_driver_id = _vehicle_driver_id(cur, o.assigned_vehicle_plate)
        cur.execute(
            """INSERT INTO orders (order_code, customer_code, factory_code, product_id, product_detail, transport_type, carrier_name, customer_group_id,
                                  pickup_address, pickup_lat, pickup_lng, delivery_address, delivery_lat, delivery_lng,
                                  pickup_radius_m, delivery_radius_m,
                                  assigned_vehicle_plate, assigned_driver_id, cargo_weight_tons)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s) RETURNING *""",
            (o.order_code, (o.customer_code or "").strip() or None, o.factory_code, o.product_id, (o.product_detail or "").strip() or None, o.transport_type, (o.carrier_name or "").strip() or None, o.customer_group_id,
             o.pickup_address, o.pickup_lat, o.pickup_lng, o.delivery_address, o.delivery_lat, o.delivery_lng,
             o.pickup_radius_m, o.delivery_radius_m,
             o.assigned_vehicle_plate, o.assigned_driver_id, o.cargo_weight_tons)
        )
        conn.commit()
        created = cur.fetchone()
        cur.close()
        conn.close()
        return _attach_photo_geo_check(created)
    except HTTPException:
        conn.rollback()
        conn.close()
        raise
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.get("/api/v1/orders")
def get_orders(current_user: dict = Depends(get_current_user)):
    conn = get_db()
    cur = conn.cursor()
    cur.execute("""
        SELECT o.*, p.name as product_name, u.full_name as driver_name
        FROM orders o
        LEFT JOIN products p ON o.product_id = p.id
        LEFT JOIN users u ON o.assigned_driver_id = u.id
        ORDER BY o.id DESC
    """)
    orders = cur.fetchall()
    cur.close()
    conn.close()
    return [_attach_photo_geo_check(r) for r in orders]

@app.put("/api/v1/orders/{order_id}")
def update_order(order_id: int, o: OrderUpdate, current_user: dict = Depends(get_current_user)):
    roles = current_user.get("roles", [])
    username = current_user.get("username", "")
    allowed = (username == "admin" or any(r in ["admin", "manager", "dispatcher"] for r in roles))
    if not allowed:
        raise HTTPException(status_code=403, detail="Chỉ Quản lý và Điều phối viên mới có quyền cập nhật đơn hàng")
    _validate_order_point(o.pickup_lat, o.pickup_lng, "Nơi nhận hàng")
    _validate_order_point(o.delivery_lat, o.delivery_lng, "Điểm giao hàng")

    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT * FROM orders WHERE id = %s", (order_id,))
        existing = cur.fetchone()
        if not existing:
            raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")

        fields = []
        values = []
        if o.order_code is not None:
            fields.append("order_code = %s")
            values.append(o.order_code.strip())
        if o.customer_code is not None:
            fields.append("customer_code = %s")
            values.append(o.customer_code.strip() or None)
        if o.factory_code is not None:
            fields.append("factory_code = %s")
            values.append(o.factory_code.strip())
        if o.product_id is not None:
            fields.append("product_id = %s")
            values.append(o.product_id)
        if o.product_detail is not None:
            fields.append("product_detail = %s")
            values.append(o.product_detail.strip() or None)
        if o.transport_type is not None:
            fields.append("transport_type = %s")
            values.append(o.transport_type)
        if o.carrier_name is not None:
            fields.append("carrier_name = %s")
            values.append(o.carrier_name.strip() or None)
        if o.customer_group_id is not None:
            fields.append("customer_group_id = %s")
            values.append(o.customer_group_id)
        if o.pickup_address is not None:
            fields.append("pickup_address = %s")
            values.append(o.pickup_address)
        # Tọa độ và bán kính: gửi null là xóa, không gửi là giữ nguyên
        sent = o.model_fields_set
        for _col in ("pickup_lat", "pickup_lng", "pickup_radius_m",
                     "delivery_lat", "delivery_lng", "delivery_radius_m"):
            if _col in sent:
                fields.append(f"{_col} = %s")
                values.append(getattr(o, _col))
        if o.delivery_address is not None:
            fields.append("delivery_address = %s")
            values.append(o.delivery_address)
        # Tài xế đi theo xe: chỉ khi đổi xe mới lấy lại tài xế phụ trách của xe mới.
        # Giữ nguyên xe thì giữ nguyên tài xế đang có của đơn; assigned_driver_id gửi lên bị bỏ qua.
        if o.assigned_vehicle_plate is not None:
            new_plate = o.assigned_vehicle_plate.strip()
            if new_plate != (existing.get("assigned_vehicle_plate") or "").strip():
                fields.append("assigned_vehicle_plate = %s")
                values.append(new_plate)
                fields.append("assigned_driver_id = %s")
                values.append(_vehicle_driver_id(cur, new_plate))
        if o.cargo_weight_tons is not None:
            fields.append("cargo_weight_tons = %s")
            values.append(o.cargo_weight_tons)
        if o.status is not None:
            fields.append("status = %s")
            values.append(o.status)

        if fields:
            values.append(order_id)
            cur.execute(f"UPDATE orders SET {', '.join(fields)} WHERE id = %s RETURNING *", tuple(values))
            conn.commit()
            updated = cur.fetchone()
        else:
            updated = existing

        cur.close()
        conn.close()
        return _attach_photo_geo_check(updated)
    except HTTPException:
        conn.close()
        raise
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.delete("/api/v1/orders/{order_id}")
def delete_order(order_id: int, current_user: dict = Depends(get_current_user)):
    roles = current_user.get("roles", [])
    username = current_user.get("username", "")
    allowed = (username == "admin" or any(r in ["admin", "manager", "dispatcher"] for r in roles))
    if not allowed:
        raise HTTPException(status_code=403, detail="Chỉ Quản lý và Điều phối viên mới có quyền xóa đơn hàng")

    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT * FROM orders WHERE id = %s", (order_id,))
        existing = cur.fetchone()
        if not existing:
            raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")

        # Xóa các ràng buộc liên quan nếu có (moc_chuyen, chung_tu_chuyen, cap_dau)
        cur.execute("DELETE FROM moc_chuyen WHERE order_id = %s", (order_id,))
        cur.execute("DELETE FROM chung_tu_chuyen WHERE order_id = %s", (order_id,))
        cur.execute("DELETE FROM cap_dau WHERE order_id = %s", (order_id,))
        cur.execute("DELETE FROM orders WHERE id = %s", (order_id,))
        conn.commit()
        cur.close()
        conn.close()
        return {"status": "success", "message": f"Đã xóa đơn hàng {existing['order_code']}"}
    except HTTPException:
        conn.close()
        raise
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

# 7. NGHIỆP VỤ KIỂM TRA ĐẦU NGÀY (5 ẢNH)
@app.get("/api/v1/inspection/status/{plate_number}")
def check_inspection_status(plate_number: str, current_user: dict = Depends(get_current_user)):
    # Nếu là khách hàng tự chở thì miễn kiểm tra
    if current_user.get("driver_type") == "CUSTOMER_SELF":
        return {
            "plate_number": plate_number,
            "is_inspected": True,
            "can_take_trip": True,
            "bypass_inspection": True,
            "reason": "Khach hang tu cho duoc mien kiem tra dau ngay"
        }

    conn = get_db()
    cur = conn.cursor()
    cur.execute(
        "SELECT * FROM kiem_tra_dau_ngay WHERE plate_number = %s AND check_date = CURRENT_DATE ORDER BY id DESC LIMIT 1",
        (plate_number,)
    )
    inspection = cur.fetchone()
    cur.close()
    conn.close()
    if not inspection:
        return {"plate_number": plate_number, "is_inspected": False, "can_take_trip": False, "reason": "Chua chup 5 anh dau ngay"}
    
    can_take = (inspection["flag_status"] in ["none", "ignored", "monitored"])
    return {
        "plate_number": plate_number,
        "is_inspected": True,
        "can_take_trip": can_take,
        "flag_status": inspection["flag_status"],
        "reason": "Chuyen bi giu cho den khi Dieu phoi/Ky thuat phe duyet" if not can_take else "San sang nhan chuyen"
    }

@app.post("/api/v1/inspection/submit", status_code=status.HTTP_201_CREATED)
def submit_inspection(insp: InspectionSubmit, current_user: dict = Depends(get_current_user)):
    # 5 ảnh kiểm tra xe bắt buộc có GPS: tọa độ chung + tọa độ riêng của từng ảnh (nếu app gửi)
    _validate_gps(insp.gps_lat, insp.gps_lng, "Phiếu kiểm tra xe")
    photo_gps = None
    if insp.photo_gps is not None:
        if len(insp.photo_gps) != 5:
            raise HTTPException(status_code=400, detail="Phải có tọa độ GPS cho đủ 5 ảnh kiểm tra xe")
        for idx, g in enumerate(insp.photo_gps, start=1):
            _validate_gps(g.get("lat"), g.get("lng"), f"Ảnh kiểm tra xe số {idx}")
        photo_gps = json.dumps(insp.photo_gps)
    conn = get_db()
    cur = conn.cursor()
    flag_deviation = (abs(insp.km_confirmed - insp.km_ocr) > 20.0)
    try:
        cur.execute(
            """INSERT INTO kiem_tra_dau_ngay (check_date, plate_number, driver_id, completed_at,
                                             img_front_underbody, img_rear_underbody, img_left_side, img_right_side, img_dashboard,
                                             gps_lat, gps_lng, gps_accuracy, device_id, km_ocr, km_confirmed, flag_deviation_km,
                                             photo_gps)
               VALUES (%s, %s, %s, CURRENT_TIMESTAMP, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s::jsonb) RETURNING *""",
            (insp.check_date, insp.plate_number, current_user["id"],
             insp.img_front_underbody, insp.img_rear_underbody, insp.img_left_side, insp.img_right_side, insp.img_dashboard,
             insp.gps_lat, insp.gps_lng, insp.gps_accuracy, insp.device_id, insp.km_ocr, insp.km_confirmed, flag_deviation,
             photo_gps)
        )
        conn.commit()
        created = cur.fetchone()
        cur.close()
        conn.close()
        _emit_event("inspection_submitted", {
            "inspection_id": created["id"],
            "plate_number": created["plate_number"],
            "driver_id": current_user["id"],
            "driver_name": current_user.get("full_name", ""),
            "flag_status": created.get("flag_status", "pending"),
        })
        return created
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.get("/api/v1/inspections")
def get_inspections(date: Optional[str] = None, plate_number: Optional[str] = None, current_user: dict = Depends(get_current_user)):
    conn = get_db()
    cur = conn.cursor()
    query = """
        SELECT k.*, u.full_name as driver_name, u.username as driver_username, u.phone as driver_phone,
               v.vehicle_type, v.ownership_type, v.owner_company,
               rv.full_name as resolver_name
        FROM kiem_tra_dau_ngay k
        LEFT JOIN users u ON k.driver_id = u.id
        LEFT JOIN vehicles v ON k.plate_number = v.plate_number
        LEFT JOIN users rv ON k.flag_resolved_by = rv.id
        WHERE 1=1
    """
    params = []
    if date:
        query += " AND k.check_date = %s"
        params.append(date)
    if plate_number:
        query += " AND k.plate_number ILIKE %s"
        params.append(f"%{plate_number}%")
    query += " ORDER BY k.id DESC"
    cur.execute(query, tuple(params))
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return rows

@app.put("/api/v1/inspections/{inspection_id}/review")
def review_inspection(inspection_id: int, review: InspectionReview, current_user: dict = Depends(get_current_user)):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute(
            """UPDATE kiem_tra_dau_ngay
               SET flag_status = %s, flag_reason = %s, flag_resolved_by = %s, flag_resolved_at = CURRENT_TIMESTAMP
               WHERE id = %s RETURNING *""",
            (review.flag_status, review.flag_reason, current_user["id"], inspection_id)
        )
        conn.commit()
        updated = cur.fetchone()
        cur.close()
        conn.close()
        if not updated:
            raise HTTPException(status_code=404, detail="Khong tim thay ban ghi kiem tra xe")
        _emit_event("inspection_reviewed", {
            "inspection_id": updated["id"],
            "plate_number": updated["plate_number"],
            "driver_id": updated["driver_id"],
            "flag_status": updated["flag_status"],
            "flag_reason": updated["flag_reason"],
        }, target_user_id=updated["driver_id"])
        return updated
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))


# 8. NGHIỆP VỤ CÂY DẦU (XÁC NHẬN CẤP NHIÊN LIỆU)
@app.post("/api/v1/fuel/confirm", status_code=status.HTTP_201_CREATED)
def confirm_fuel(fuel: FuelConfirm, current_user: dict = Depends(get_current_user)):
    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT * FROM gas_stations WHERE id = %s", (fuel.gas_station_id,))
    gs = cur.fetchone()
    if not gs:
        conn.close()
        raise HTTPException(status_code=404, detail="Khong tim thay cay dau")

    # Kiểm tra khoảng cách thực tế đến cây xăng
    dist_meters = haversine_distance(fuel.gps_lat, fuel.gps_lng, gs["lat"], gs["lng"])
    flag_location = dist_meters > gs["allowed_radius_meters"]

    try:
        cur.execute(
            """INSERT INTO cap_dau (order_id, plate_number, driver_id, gas_station_id, fuel_type,
                                   liters_ocr, liters_actual, img_meter, img_receipt, gps_lat, gps_lng, flag_location_mismatch)
               VALUES (%s, %s, (SELECT assigned_driver_id FROM orders WHERE id = %s), %s, %s, %s, %s, %s, %s, %s, %s, %s) RETURNING *""",
            (fuel.order_id, fuel.plate_number, fuel.order_id, fuel.gas_station_id, fuel.fuel_type,
             fuel.liters_ocr, fuel.liters_actual, fuel.img_meter, fuel.img_receipt, fuel.gps_lat, fuel.gps_lng, flag_location)
        )
        conn.commit()
        record = cur.fetchone()
        cur.close()
        conn.close()
        return {
            "status": "success",
            "message": "Xac nhan cap dau thanh cong",
            "distance_to_station_meters": round(dist_meters, 2),
            "flag_location_mismatch": flag_location,
            "record": record
        }
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

# 9. NGHIỆP VỤ MỐC GIỜ CHUYẾN (ĐẾN & BƠM XONG)
@app.post("/api/v1/trip/arrive")
def milestone_arrive(m: MilestoneArrive, current_user: dict = Depends(get_current_user)):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute(
            """INSERT INTO moc_chuyen (order_id, plate_number, arrive_time, arrive_lat, arrive_lng, source)
               VALUES (%s, %s, CURRENT_TIMESTAMP, %s, %s, 'app') RETURNING *""",
            (m.order_id, m.plate_number, m.arrive_lat, m.arrive_lng)
        )
        conn.commit()
        record = cur.fetchone()
        cur.close()
        conn.close()
        return {"status": "success", "message": "Da ghi nhan moc gio DEN diem giao", "record": record}
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.post("/api/v1/trip/pump-done")
def milestone_pump_done(m: MilestonePumpDone, current_user: dict = Depends(get_current_user)):
    conn = get_db()
    cur = conn.cursor()
    cur.execute(
        "SELECT * FROM moc_chuyen WHERE order_id = %s ORDER BY id DESC LIMIT 1",
        (m.order_id,)
    )
    rec = cur.fetchone()
    if not rec or not rec["arrive_time"]:
        conn.close()
        raise HTTPException(status_code=400, detail="Chua ghi nhan moc gio DEN cua don hang nay")

    cur.execute("""
        UPDATE moc_chuyen 
        SET pump_done_time = CURRENT_TIMESTAMP,
            pump_done_lat = %s,
            pump_done_lng = %s,
            wait_duration_minutes = EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - arrive_time))/60,
            wait_reason_code = %s,
            wait_reason_note = %s
        WHERE id = %s RETURNING *
    """, (m.pump_done_lat, m.pump_done_lng, m.wait_reason_code, m.wait_reason_note, rec["id"]))
    
    conn.commit()
    updated = cur.fetchone()
    cur.close()
    conn.close()
    return {"status": "success", "message": "Da ghi nhan moc gio BOM XONG", "record": updated}

# 10. QUẢN LÝ CA TRỰC ĐIỀU PHỐI (DISPATCHER SHIFTS)
@app.get("/api/v1/shifts/active")
def get_active_shifts(current_user: dict = Depends(get_current_user)):
    conn = get_db()
    cur = conn.cursor()
    cur.execute("""
        SELECT s.id, s.user_id, s.shift_name, s.started_at, s.status, s.note, s.handover_note,
               u.username, u.full_name, u.phone, u.avatar_url
        FROM dispatcher_shifts s
        JOIN users u ON s.user_id = u.id
        WHERE s.status = 'active'
        ORDER BY s.started_at DESC
    """)
    shifts = cur.fetchall()
    cur.close()
    conn.close()
    return shifts

@app.get("/api/v1/shifts/history")
def get_shift_history(user_id: Optional[int] = None, limit: int = 50, current_user: dict = Depends(get_current_user)):
    """Lấy danh sách toàn bộ lịch sử các ca trực điều phối viên đã hoàn thành hoặc đang trực"""
    conn = get_db()
    cur = conn.cursor()
    query = """
        SELECT s.id, s.user_id, s.shift_name, s.started_at, s.ended_at, s.status, s.note, s.handover_note, s.created_at,
               ROUND(EXTRACT(EPOCH FROM (COALESCE(s.ended_at, CURRENT_TIMESTAMP) - s.started_at)) / 3600.0, 2) AS duration_hours,
               u.username, u.full_name, u.phone, u.avatar_url
        FROM dispatcher_shifts s
        JOIN users u ON s.user_id = u.id
    """
    params = []
    if user_id:
        query += " WHERE s.user_id = %s"
        params.append(user_id)
    query += " ORDER BY s.started_at DESC LIMIT %s"
    params.append(limit)

    cur.execute(query, tuple(params))
    history = cur.fetchall()
    cur.close()
    conn.close()
    return history

@app.post("/api/v1/shifts/checkin", status_code=status.HTTP_201_CREATED)
def checkin_shift(req: ShiftCheckin, current_user: dict = Depends(get_current_user)):
    user_roles = current_user.get("roles", [])
    if "dispatcher" not in user_roles and "admin" not in user_roles:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Chỉ tài khoản Điều phối viên mới được phép nhận ca trực."
        )

    user_id = current_user["id"]
    conn = get_db()
    cur = conn.cursor()
    try:
        # Kiểm tra xem user này đã có ca active nào chưa
        cur.execute("SELECT id FROM dispatcher_shifts WHERE user_id = %s AND status = 'active'", (user_id,))
        existing = cur.fetchone()
        if existing:
            cur.close()
            conn.close()
            return {"status": "success", "message": "Bạn đã trong ca trực", "shift_id": existing["id"]}

        cur.execute(
            """INSERT INTO dispatcher_shifts (user_id, shift_name, started_at, status, note)
               VALUES (%s, %s, CURRENT_TIMESTAMP, 'active', %s) RETURNING *""",
            (user_id, req.shift_name or "Ca ngày", req.note)
        )
        conn.commit()
        created = cur.fetchone()
        cur.close()
        conn.close()
        return {"status": "success", "message": "Nhận ca trực thành công", "shift": created}
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.post("/api/v1/shifts/checkout")
def checkout_shift(req: ShiftCheckout, current_user: dict = Depends(get_current_user)):
    user_id = current_user["id"]
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("""
            UPDATE dispatcher_shifts 
            SET ended_at = CURRENT_TIMESTAMP,
                status = 'completed',
                handover_note = COALESCE(%s, handover_note)
            WHERE user_id = %s AND status = 'active'
            RETURNING *
        """, (req.note, user_id))
        conn.commit()
        updated = cur.fetchone()
        cur.close()
        conn.close()
        if not updated:
            return {"status": "warning", "message": "Không tìm thấy ca trực đang mở của bạn"}
        return {"status": "success", "message": "Kết thúc ca trực thành công", "shift": updated}
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))


def _save_order_photo(order_id: int, photo_type: str, img_data: str) -> str:
    if not img_data:
        return ""
    if img_data.startswith("/uploads/") or img_data.startswith("uploads/") or img_data.startswith("http"):
        return img_data
    base_upload = globals().get("UPLOAD_DIR", "uploads")
    upload_dir = os.path.join(base_upload, "orders")
    os.makedirs(upload_dir, exist_ok=True)
    raw = img_data.split(",")[1] if "," in img_data else img_data
    filename = f"order_{order_id}_{photo_type}_{int(datetime.now().timestamp())}.jpg"
    filepath = os.path.join(upload_dir, filename)
    with open(filepath, "wb") as f:
        f.write(base64.b64decode(raw))
    return f"/uploads/orders/{filename}"

@app.post("/api/v1/orders/{order_id}/attachment")
def submit_order_attachment(
    order_id: int,
    payload: OrderAttachmentSubmit,
    current_user: dict = Depends(get_current_user),
):
    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT * FROM orders WHERE id = %s", (order_id,))
    existing = cur.fetchone()
    if not existing:
        cur.close()
        conn.close()
        raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")

    actor = current_user.get("full_name") or current_user.get("username") or "Người dùng"
    ptype = (payload.photo_type or "").strip().lower()
    if ptype in ("pump_before", "pump_slip_after", "pump_after"):
        ptype = "pump_slip_before" if ptype == "pump_before" else "pump_slip"
    if ptype not in ORDER_PHOTO_PREFIX:
        cur.close()
        conn.close()
        raise HTTPException(status_code=400, detail=f"Loại hình chụp không hợp lệ: {ptype}")

    # 2 ảnh bơm hàng (Trước khi bơm / Đã bơm xong) bắt buộc do tài khoản Tài xế chụp
    if ptype in ("pump_slip_before", "pump_slip"):
        user_roles = [r.lower() for r in current_user.get("roles", [])]
        if "driver" not in user_roles:
            cur.close()
            conn.close()
            raise HTTPException(
                status_code=403,
                detail="Ảnh bơm hàng chỉ tài khoản Tài xế mới được chụp và gửi",
            )
        if ptype == "pump_slip" and not (existing.get("pump_slip_before_photo_url") or "").strip():
            cur.close()
            conn.close()
            raise HTTPException(
                status_code=400,
                detail="Phải chụp ảnh TRƯỚC KHI BƠM trước khi gửi ảnh ĐÃ BƠM XONG",
            )

    # Mọi ảnh của tài xế đều bắt buộc có tọa độ GPS lúc chụp
    try:
        _validate_gps(payload.gps_lat, payload.gps_lng)
    except HTTPException:
        cur.close()
        conn.close()
        raise

    prefix = ORDER_PHOTO_PREFIX[ptype]
    gps_sql = (
        f"{prefix}_gps_lat = %s, {prefix}_gps_lng = %s, "
        f"{prefix}_gps_accuracy = %s, "
        f"{prefix}_gps_captured_at = COALESCE(%s, CURRENT_TIMESTAMP),"
    )
    gps_params = (
        payload.gps_lat,
        payload.gps_lng,
        payload.gps_accuracy,
        _parse_gps_time(payload.gps_captured_at),
    )
    try:
        saved_path = _save_order_photo(order_id, ptype, payload.photo_base64)
        if ptype == "pump_slip_before":
            cur.execute(
                f"""
                UPDATE orders
                SET pump_slip_before_photo_url = %s,
                    pump_slip_before_time = CURRENT_TIMESTAMP,
                    pump_slip_before_by = %s,
                    pump_slip_before_note = COALESCE(%s, pump_slip_before_note),
                    {gps_sql}
                    status = CASE WHEN status IN ('waiting', 'assigned') THEN 'in_progress' ELSE status END,
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
                RETURNING *
                """,
                (saved_path, actor, payload.note, *gps_params, order_id),
            )
        elif ptype == "pump_slip":
            cur.execute(
                f"""
                UPDATE orders
                SET pump_slip_photo_url = %s,
                    pump_slip_time = CURRENT_TIMESTAMP,
                    pump_slip_by = %s,
                    pump_slip_note = COALESCE(%s, pump_slip_note),
                    {gps_sql}
                    status = CASE WHEN status IN ('waiting', 'assigned') THEN 'in_progress' ELSE status END,
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
                RETURNING *
                """,
                (saved_path, actor, payload.note, *gps_params, order_id),
            )
        elif ptype == "weigh_slip":
            cur.execute(
                f"""
                UPDATE orders
                SET weigh_slip_photo_url = %s,
                    weigh_slip_time = CURRENT_TIMESTAMP,
                    weigh_slip_tonnage = COALESCE(%s, weigh_slip_tonnage),
                    weigh_slip_code = COALESCE(%s, weigh_slip_code),
                    {gps_sql}
                    status = CASE WHEN status IN ('waiting', 'assigned') THEN 'in_progress' ELSE status END,
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
                RETURNING *
                """,
                (saved_path, payload.tonnage, payload.slip_code, *gps_params, order_id),
            )
        elif ptype == "delivery_slip":
            cur.execute(
                f"""
                UPDATE orders
                SET delivery_slip_photo_url = %s,
                    delivery_slip_time = CURRENT_TIMESTAMP,
                    delivery_slip_note = COALESCE(%s, delivery_slip_note),
                    {gps_sql}
                    status = 'completed',
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
                RETURNING *
                """,
                (saved_path, payload.note, *gps_params, order_id),
            )
        elif ptype == "breakdown":
            cur.execute(
                f"""
                UPDATE orders
                SET has_breakdown = TRUE,
                    breakdown_status = 'reported',
                    breakdown_photo_url = %s,
                    breakdown_reason = COALESCE(%s, breakdown_reason),
                    breakdown_location = COALESCE(%s, breakdown_location),
                    breakdown_time = CURRENT_TIMESTAMP,
                    breakdown_reported_by = %s,
                    {gps_sql}
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
                RETURNING *
                """,
                (saved_path, payload.note, payload.location, actor, *gps_params, order_id),
            )
        elif ptype == "repair":
            r_status = payload.repair_status or "fixed"
            b_status = "resolved" if r_status == "fixed" else "repairing"
            cur.execute(
                f"""
                UPDATE orders
                SET repair_photo_url = %s,
                    repair_status = %s,
                    repair_note = COALESCE(%s, repair_note),
                    repair_time = CURRENT_TIMESTAMP,
                    repair_by = %s,
                    breakdown_status = %s,
                    {gps_sql}
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
                RETURNING *
                """,
                (saved_path, r_status, payload.note, actor, b_status, *gps_params, order_id),
            )
        else:
            cur.close()
            conn.close()
            raise HTTPException(status_code=400, detail=f"Loại hình chụp không hợp lệ: {ptype}")

        updated = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()
        return _attach_photo_geo_check(updated)
    except HTTPException:
        raise
    except Exception as e:
        conn.rollback()
        cur.close()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))
