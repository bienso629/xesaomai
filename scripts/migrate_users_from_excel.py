# -*- coding: utf-8 -*-
"""Migrate danh sách tài khoản theo chuẩn docs/DS DIEU PHOI_TAI XE.xlsx"""
import os, re, unicodedata
import psycopg2
import bcrypt

DSN = os.environ.get("DATABASE_URL") or "postgres://taxi_user:taxi_password_2026@postgres:5432/taxi_logistics"
DEFAULT_PWD = "123456"

def slug(name):
    s = unicodedata.normalize("NFD", name)
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = s.replace("đ", "d").replace("Đ", "d")
    return re.sub(r"[^a-z0-9]", "", s.lower())

def hash_pwd(p):
    return bcrypt.hashpw(p.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")

# (Ho ten, SDT, role_code) - Phan I: Dieu phoi / BGĐ / Admin
OFFICE = [
    ("Duy IT",            "0901234567", "admin"),      # username dac biet: admin
    ("Cao Sông Lam",      "0989077998", "manager"),
    ("Ngô Thị Kiều Oanh", "0969845554", "manager"),
    ("Nguyễn Văn Tân",    "0984549998", "dispatcher"),
    ("Vũ Hoàng Quân",     "0965778885", "dispatcher"),
    ("Triệu Thị Huệ",     "0988498885", "dispatcher"),
]
# (Ho ten, SDT, bien so xe, so mooc) - Phan II: 22 tai xe
DRIVERS = [
    ("Kim Vết",           "0787825959", "50H-449.66", "50RM02927"),
    ("Nguyễn Văn Thảo",   "0972840341", "50H-446.76", "50RM03249"),
    ("Nguyễn Đình Lâm",   "0943765579", "50H-457.21", "50RM06757"),
    ("Trịnh Trung Đấu",   "0978784665", "50H-914.39", "50RM15623"),
    ("Bùi Văn Phong",     "0853996963", "50E-889.50", "50RM-23607"),
    ("Nguyễn Viết Duy",   "0376977780", "50H-540.41", "50RM03696"),
    ("Ngô Tiến Đủ",       "0919541172", "50H-538.61", "50RM03898"),
    ("Đoàn Hoàng Anh",    "0798482479", "50E-329.52", "50RM22993"),
    ("Vũ Tuấn Dương",     "0979319559", "50H-919.49", "50RM03075"),
    ("Lê Văn Tùng",       "0877725078", "50H-882.60", "50RM10642"),
    ("Lê Văn Lương",      "0989463417", "50E-480.24", "50RM13758"),
    ("Tô Vân Sơn",        "0978199728", "50H-900.32", "50RM15117"),
    ("Phan Châu Khoa",    "0965551237", "50E-147.73", "50RM15113"),
    ("Nguyễn Thái Sơn",   "0917970102", "50H-162.27", "50RM15112"),
    ("Nguyễn Ngọc Thiên", "0965551237", "50E-151.64", "50RM15115"),
    ("Lê Văn Tuyến",      "0899860400", "51D-477.61", "50RM-23606"),
    ("Lê Hoàng Hải",      "0858229225", "51D-477.41", "50RM-23605"),
    ("Kiều Thành Nghĩa",  "0948518283", "50H-891.21", "50RM11007"),
    ("Đinh Mậu Quang",    "0908207809", "50E-477.23", "50RM13757"),
    ("Nguyễn Văn Ngọc",   "0386000448", "50H-919.51", "50RM06827"),
    ("Thái Thanh Sơn",    "0377121579", "50E-074.57", "50RM22994"),
    ("Nguyễn Văn Cường",  "0967792619", "50E-075.43", "50RM23073"),
]
PREFIX = {"admin": "", "manager": "giamdoc_", "dispatcher": "dieuphoi_", "driver": "taixe_"}
FK_TABLES = ["cap_dau", "kiem_tra_dau_ngay", "moc_chuyen", "nhac_nho", "bao_hong"]
RENAME_PLATES = [("50H-166.27", "50H-162.27"), ("50H914.39", "50H-914.39")]

conn = psycopg2.connect(DSN)
conn.autocommit = False
cur = conn.cursor()
report = []

try:
    # 0. Bo rang buoc UNIQUE phone (Excel co 2 tai xe dung chung SDT 0965551237)
    cur.execute("SELECT 1 FROM pg_constraint WHERE conname='users_phone_key'")
    if cur.fetchone():
        cur.execute("ALTER TABLE users DROP CONSTRAINT users_phone_key")
        report.append("OK: DROP CONSTRAINT users_phone_key (2 tai xe dung chung SDT 0965551237)")

    # 1. Dong cac ca truc dieu phoi dang mo
    cur.execute("DELETE FROM dispatcher_shifts")
    report.append("OK: Xoa %d ca truc dieu phoi (du lieu ca truc cu)" % cur.rowcount)

    # 2. Go tat ca FK tham chieu users
    for sql in [
        "UPDATE orders SET assigned_driver_id=NULL",
        "UPDATE kiem_tra_dau_ngay SET driver_id=NULL",
        "UPDATE kiem_tra_dau_ngay SET flag_resolved_by=NULL",
        "UPDATE cap_dau SET driver_id=NULL",
        "UPDATE cap_dau SET approved_by=NULL",
        "UPDATE bao_hong SET driver_id=NULL",
        "UPDATE bao_hong SET decided_by=NULL",
        "UPDATE nhac_nho SET driver_id=NULL",
        "UPDATE vehicles SET default_driver_id=NULL",
        "UPDATE gas_stations SET user_id=NULL",
    ]:
        cur.execute(sql)
    report.append("OK: Go FK tham chieu users (orders, kiem_tra_dau, cap_dau, vehicles...)")

    # 3. Xoa toan bo user + phan quyen cu
    cur.execute("DELETE FROM user_roles")
    cur.execute("DELETE FROM users")
    report.append("OK: Xoa toan bo user va phan quyen cu")

    # 4. Lay map role
    cur.execute("SELECT code, id FROM roles")
    role_map = dict(cur.fetchall())

    def insert_user(username, full_name, phone, driver_type):
        cur.execute(
            """INSERT INTO users (username, password_hash, full_name, phone, driver_type, is_active)
               VALUES (%s,%s,%s,%s,%s,true) RETURNING id""",
            (username, hash_pwd(DEFAULT_PWD), full_name, phone, driver_type),
        )
        return cur.fetchone()[0]

    accounts = []

    # 5. Chen Phan I - Dieu phoi / BGĐ / Admin
    for name, phone, role in OFFICE:
        username = "admin" if role == "admin" else PREFIX[role] + slug(name)
        uid = insert_user(username, name, phone, None)
        cur.execute("INSERT INTO user_roles (user_id, role_id) VALUES (%s,%s)", (uid, role_map[role]))
        accounts.append((username, name, phone, role, None, None))

    # 6. Doi ten bien so sai lech voi Excel (neu khong co du lieu FK)
    for old, new in RENAME_PLATES:
        refs = 0
        for t in FK_TABLES:
            cur.execute("SELECT count(*) FROM %s WHERE plate_number=%%s" % t, (old,))
            refs += cur.fetchone()[0]
        if refs == 0:
            cur.execute("UPDATE vehicles SET plate_number=%s WHERE plate_number=%s", (new, old))
            report.append("OK: Doi bien so %s -> %s (chuan hoa theo Excel)" % (old, new))
        else:
            report.append("CANH BAO: Giu nguyen %s vi co %d ban ghi nghiep vu tham chieu" % (old, refs))

    # 7. Chen Phan II - 22 tai xe + gan xe phu trach
    for name, phone, plate, mooc in DRIVERS:
        username = PREFIX["driver"] + slug(name)
        uid = insert_user(username, name, phone, "INTERNAL")
        cur.execute("INSERT INTO user_roles (user_id, role_id) VALUES (%s,%s)", (uid, role_map["driver"]))
        cur.execute("SELECT 1 FROM vehicles WHERE plate_number=%s", (plate,))
        if cur.fetchone():
            cur.execute("UPDATE vehicles SET default_driver_id=%s WHERE plate_number=%s", (uid, plate))
            accounts.append((username, name, phone, "driver", plate, mooc))
        else:
            report.append("CANH BAO: Khong tim thay xe %s cho %s" % (plate, name))
            accounts.append((username, name, phone, "driver", plate + " (KHONG TON TAI)", mooc))

    # 8. Reset sequence
    cur.execute("SELECT setval('users_id_seq', (SELECT COALESCE(MAX(id),1) FROM users))")
    conn.commit()
    report.append("OK: COMMIT thanh cong. Tong so tai khoan moi: %d" % len(accounts))
except Exception as e:
    conn.rollback()
    report.append("LOI - DA ROLLBACK: %s" % e)
    raise

print("\n".join(report))
print("\n=== DANH SACH TAI KHOAN MOI ===")
for u, n, p, r, plate, mooc in accounts:
    line = "%-28s | %-20s | %s | %s" % (u, n, p, r)
    if plate:
        line += " | xe %s | mooc %s" % (plate, mooc)
    print(line)
