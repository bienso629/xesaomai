import base64
import os
import math
import uuid
import shutil
from datetime import datetime, timedelta, timezone
from typing import Optional, List
import psycopg2
from psycopg2.extras import RealDictCursor
from fastapi import FastAPI, HTTPException, Depends, status, UploadFile, File
from fastapi.staticfiles import StaticFiles
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from pydantic import BaseModel
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
    username: str
    password: str

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
    factory_code: str
    product_id: int
    transport_type: Optional[str] = "INTERNAL"
    customer_group_id: Optional[str] = None
    pickup_address: str
    pickup_lat: Optional[float] = None
    pickup_lng: Optional[float] = None
    delivery_address: str
    delivery_lat: Optional[float] = None
    delivery_lng: Optional[float] = None
    assigned_vehicle_plate: str
    assigned_driver_id: int
    cargo_weight_tons: float

class OrderUpdate(BaseModel):
    order_code: Optional[str] = None
    factory_code: Optional[str] = None
    product_id: Optional[int] = None
    transport_type: Optional[str] = None
    customer_group_id: Optional[str] = None
    pickup_address: Optional[str] = None
    pickup_lat: Optional[float] = None
    pickup_lng: Optional[float] = None
    delivery_address: Optional[str] = None
    delivery_lat: Optional[float] = None
    delivery_lng: Optional[float] = None
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
    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT * FROM users WHERE username = %s AND is_active = TRUE", (creds.username,))
    user = cur.fetchone()
    if not user or not verify_password(creds.password, user["password_hash"]):
        cur.close()
        conn.close()
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
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.put("/api/v1/products/{product_id}")
def update_product(product_id: int, product: ProductUpdate, current_user: dict = Depends(require_admin)):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT id, name, code FROM products WHERE id = %s", (product_id,))
        existing = cur.fetchone()
        if not existing:
            cur.close()
            conn.close()
            raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm")

        fields, params = [], []
        for col, val in [("code", product.code), ("name", product.name), ("category", product.category),
                         ("unit", product.unit), ("standard_pump_time_minutes", product.standard_pump_time_minutes),
                         ("requires_air_pump", product.requires_air_pump)]:
            if val is not None:
                fields.append(f"{col} = %s")
                params.append(val)
        params.append(product_id)

        cur.execute(f"UPDATE products SET {', '.join(fields)}, updated_at = CURRENT_TIMESTAMP WHERE id = %s RETURNING *", params)
        conn.commit()
        updated = cur.fetchone()
        cur.close()
        conn.close()
        return updated
    except HTTPException:
        raise
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.delete("/api/v1/products/{product_id}")
def delete_product(product_id: int, current_user: dict = Depends(require_admin)):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT id, name FROM products WHERE id = %s", (product_id,))
        existing = cur.fetchone()
        if not existing:
            cur.close()
            conn.close()
            raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm")

        # Soft delete nếu đang có đơn hàng tham chiếu, hard delete nếu trơn tru
        cur.execute("SELECT COUNT(*) AS cnt FROM orders WHERE product_id = %s", (product_id,))
        used = cur.fetchone()["cnt"]
        if used and used > 0:
            cur.execute("UPDATE products SET is_active = FALSE, updated_at = CURRENT_TIMESTAMP WHERE id = %s", (product_id,))
            conn.commit()
            cur.close()
            conn.close()
            return {"message": f"Sản phẩm '{existing['name']}' đang có {used} đơn hàng nên đã được chuyển trạng thái ẩn (soft delete)"}

        cur.execute("DELETE FROM products WHERE id = %s", (product_id,))
        conn.commit()
        cur.close()
        conn.close()
        return {"message": f"Đã xóa sản phẩm '{existing['name']}'"}
    except HTTPException:
        raise
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

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
@app.get("/api/v1/vehicles")
def get_vehicles(current_user: dict = Depends(get_current_user)):
    conn = get_db()
    cur = conn.cursor()
    cur.execute("""
        SELECT v.*, u.full_name as driver_name, u.username as driver_username, u.phone as driver_phone 
        FROM vehicles v 
        LEFT JOIN users u ON v.default_driver_id = u.id 
        ORDER BY v.plate_number ASC
    """)
    vehicles = cur.fetchall()
    cur.close()
    conn.close()
    return vehicles

@app.post("/api/v1/vehicles", status_code=status.HTTP_201_CREATED)
def create_vehicle(v: VehicleCreate, current_user: dict = Depends(get_current_user)):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute(
            "INSERT INTO vehicles (plate_number, vehicle_type, ownership_type, default_driver_id, owner_company, status) VALUES (%s, %s, %s, %s, %s, %s) RETURNING *",
            (v.plate_number, v.vehicle_type, v.ownership_type, v.default_driver_id, v.owner_company or "Sao Mai Logistics", v.status or "ready")
        )
        conn.commit()
        created = cur.fetchone()
        cur.close()
        conn.close()
        return created
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
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.put("/api/v1/gas-stations/{station_id}")
def update_gas_station(station_id: int, req: GasStationUpdate, current_user: dict = Depends(require_admin)):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT id FROM gas_stations WHERE id = %s", (station_id,))
        if not cur.fetchone():
            cur.close()
            conn.close()
            raise HTTPException(status_code=404, detail="Không tìm thấy trạm dầu")

        fields = []
        values = []
        if req.name is not None:
            fields.append("name = %s")
            values.append(req.name)
        if req.address is not None:
            fields.append("address = %s")
            values.append(req.address)
        if req.lat is not None:
            fields.append("lat = %s")
            values.append(req.lat)
        if req.lng is not None:
            fields.append("lng = %s")
            values.append(req.lng)
        if req.allowed_radius_meters is not None:
            fields.append("allowed_radius_meters = %s")
            values.append(req.allowed_radius_meters)
        if req.user_id is not None:
            fields.append("user_id = %s")
            values.append(req.user_id)

        if not fields:
            cur.close()
            conn.close()
            raise HTTPException(status_code=400, detail="Không có dữ liệu cần cập nhật")

        values.append(station_id)
        cur.execute(f"""UPDATE gas_stations SET {', '.join(fields)} WHERE id = %s RETURNING *""", values)
        conn.commit()
        updated = cur.fetchone()
        cur.close()
        conn.close()
        return updated
    except HTTPException:
        raise
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.delete("/api/v1/gas-stations/{station_id}")
def delete_gas_station(station_id: int, current_user: dict = Depends(require_admin)):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT id, name FROM gas_stations WHERE id = %s", (station_id,))
        station = cur.fetchone()
        if not station:
            cur.close()
            conn.close()
            raise HTTPException(status_code=404, detail="Không tìm thấy trạm dầu")

        cur.execute("SELECT COUNT(*) AS cnt FROM cap_dau WHERE gas_station_id = %s", (station_id,))
        used = cur.fetchone()["cnt"]
        if used and used > 0:
            cur.close()
            conn.close()
            raise HTTPException(status_code=400, detail=f"Không thể xóa trạm '{station['name']}' vì đã có {used} lượt cấp dầu liên quan")

        cur.execute("DELETE FROM gas_stations WHERE id = %s", (station_id,))
        conn.commit()
        cur.close()
        conn.close()
        return {"message": f"Đã xóa trạm dầu '{station['name']}'"}
    except HTTPException:
        raise
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))

@app.get("/api/v1/reports/summary")
def get_reports_summary(current_user: dict = Depends(get_current_user)):
    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) as total_vehicles FROM vehicles")
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
@app.post("/api/v1/orders", status_code=status.HTTP_201_CREATED)
def create_order(o: OrderCreate, current_user: dict = Depends(get_current_user)):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute(
            """INSERT INTO orders (order_code, factory_code, product_id, transport_type, customer_group_id,
                                  pickup_address, pickup_lat, pickup_lng, delivery_address, delivery_lat, delivery_lng,
                                  assigned_vehicle_plate, assigned_driver_id, cargo_weight_tons)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s) RETURNING *""",
            (o.order_code, o.factory_code, o.product_id, o.transport_type, o.customer_group_id,
             o.pickup_address, o.pickup_lat, o.pickup_lng, o.delivery_address, o.delivery_lat, o.delivery_lng,
             o.assigned_vehicle_plate, o.assigned_driver_id, o.cargo_weight_tons)
        )
        conn.commit()
        created = cur.fetchone()
        cur.close()
        conn.close()
        return created
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
    return orders

@app.put("/api/v1/orders/{order_id}")
def update_order(order_id: int, o: OrderUpdate, current_user: dict = Depends(get_current_user)):
    roles = current_user.get("roles", [])
    username = current_user.get("username", "")
    allowed = (username == "admin" or any(r in ["admin", "manager", "dispatcher"] for r in roles))
    if not allowed:
        raise HTTPException(status_code=403, detail="Chỉ Quản lý và Điều phối viên mới có quyền cập nhật đơn hàng")

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
        if o.factory_code is not None:
            fields.append("factory_code = %s")
            values.append(o.factory_code.strip())
        if o.product_id is not None:
            fields.append("product_id = %s")
            values.append(o.product_id)
        if o.transport_type is not None:
            fields.append("transport_type = %s")
            values.append(o.transport_type)
        if o.customer_group_id is not None:
            fields.append("customer_group_id = %s")
            values.append(o.customer_group_id)
        if o.pickup_address is not None:
            fields.append("pickup_address = %s")
            values.append(o.pickup_address)
        if o.pickup_lat is not None:
            fields.append("pickup_lat = %s")
            values.append(o.pickup_lat)
        if o.pickup_lng is not None:
            fields.append("pickup_lng = %s")
            values.append(o.pickup_lng)
        if o.delivery_address is not None:
            fields.append("delivery_address = %s")
            values.append(o.delivery_address)
        if o.delivery_lat is not None:
            fields.append("delivery_lat = %s")
            values.append(o.delivery_lat)
        if o.delivery_lng is not None:
            fields.append("delivery_lng = %s")
            values.append(o.delivery_lng)
        if o.assigned_vehicle_plate is not None:
            fields.append("assigned_vehicle_plate = %s")
            values.append(o.assigned_vehicle_plate)
        if o.assigned_driver_id is not None:
            fields.append("assigned_driver_id = %s")
            values.append(o.assigned_driver_id)
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
        return updated
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
    conn = get_db()
    cur = conn.cursor()
    flag_deviation = (abs(insp.km_confirmed - insp.km_ocr) > 20.0)
    try:
        cur.execute(
            """INSERT INTO kiem_tra_dau_ngay (check_date, plate_number, driver_id, completed_at,
                                             img_front_underbody, img_rear_underbody, img_left_side, img_right_side, img_dashboard,
                                             gps_lat, gps_lng, gps_accuracy, device_id, km_ocr, km_confirmed, flag_deviation_km)
               VALUES (%s, %s, %s, CURRENT_TIMESTAMP, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s) RETURNING *""",
            (insp.check_date, insp.plate_number, current_user["id"],
             insp.img_front_underbody, insp.img_rear_underbody, insp.img_left_side, insp.img_right_side, insp.img_dashboard,
             insp.gps_lat, insp.gps_lng, insp.gps_accuracy, insp.device_id, insp.km_ocr, insp.km_confirmed, flag_deviation)
        )
        conn.commit()
        created = cur.fetchone()
        cur.close()
        conn.close()
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
    try:
        saved_path = _save_order_photo(order_id, ptype, payload.photo_base64)
        if ptype == "pump_slip":
            cur.execute(
                """
                UPDATE orders
                SET pump_slip_photo_url = %s,
                    pump_slip_time = CURRENT_TIMESTAMP,
                    pump_slip_by = %s,
                    pump_slip_note = COALESCE(%s, pump_slip_note),
                    status = CASE WHEN status IN ('waiting', 'assigned') THEN 'in_progress' ELSE status END,
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
                RETURNING *
                """,
                (saved_path, actor, payload.note, order_id),
            )
        elif ptype == "weigh_slip":
            cur.execute(
                """
                UPDATE orders
                SET weigh_slip_photo_url = %s,
                    weigh_slip_time = CURRENT_TIMESTAMP,
                    weigh_slip_tonnage = COALESCE(%s, weigh_slip_tonnage),
                    weigh_slip_code = COALESCE(%s, weigh_slip_code),
                    status = CASE WHEN status IN ('waiting', 'assigned') THEN 'in_progress' ELSE status END,
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
                RETURNING *
                """,
                (saved_path, payload.tonnage, payload.slip_code, order_id),
            )
        elif ptype == "delivery_slip":
            cur.execute(
                """
                UPDATE orders
                SET delivery_slip_photo_url = %s,
                    delivery_slip_time = CURRENT_TIMESTAMP,
                    delivery_slip_note = COALESCE(%s, delivery_slip_note),
                    status = 'completed',
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
                RETURNING *
                """,
                (saved_path, payload.note, order_id),
            )
        elif ptype == "breakdown":
            cur.execute(
                """
                UPDATE orders
                SET has_breakdown = TRUE,
                    breakdown_status = 'reported',
                    breakdown_photo_url = %s,
                    breakdown_reason = COALESCE(%s, breakdown_reason),
                    breakdown_location = COALESCE(%s, breakdown_location),
                    breakdown_time = CURRENT_TIMESTAMP,
                    breakdown_reported_by = %s,
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
                RETURNING *
                """,
                (saved_path, payload.note, payload.location, actor, order_id),
            )
        elif ptype == "repair":
            r_status = payload.repair_status or "fixed"
            b_status = "resolved" if r_status == "fixed" else "repairing"
            cur.execute(
                """
                UPDATE orders
                SET repair_photo_url = %s,
                    repair_status = %s,
                    repair_note = COALESCE(%s, repair_note),
                    repair_time = CURRENT_TIMESTAMP,
                    repair_by = %s,
                    breakdown_status = %s,
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
                RETURNING *
                """,
                (saved_path, r_status, payload.note, actor, b_status, order_id),
            )
        else:
            cur.close()
            conn.close()
            raise HTTPException(status_code=400, detail=f"Loại hình chụp không hợp lệ: {ptype}")

        updated = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()
        return dict(updated)
    except HTTPException:
        raise
    except Exception as e:
        conn.rollback()
        cur.close()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))
