import psycopg2

conn = psycopg2.connect("postgres://taxi_user:taxi_password_2026@localhost:5432/taxi_logistics")
cur = conn.cursor()

# Seed vehicles
vehicles = [
    ("50H-891.21", "HOWO_A7", "INTERNAL", 2),
    ("50H-538.61", "HOWO_A7", "INTERNAL", 2),
    ("50H-882.60", "HYUNDAI_HD270", "INTERNAL", 2),
    ("51D-477.61", "DAEWOO_NOVUS", "RENTAL", None),
    ("51D-477.41", "HOWO_A7", "CUSTOMER_SELF", None),
]
for v in vehicles:
    cur.execute("""
        INSERT INTO vehicles (plate_number, vehicle_type, ownership_type, default_driver_id)
        VALUES (%s, %s, %s, %s)
        ON CONFLICT (plate_number) DO UPDATE SET ownership_type = EXCLUDED.ownership_type;
    """, v)

# Seed gas station
cur.execute("""
    INSERT INTO gas_stations (id, name, address, lat, lng, allowed_radius_meters, user_id)
    VALUES (1, 'Trạm Dầu Petrolimex 01 - Cát Lái', 'Cảng Cát Lái, P. Cát Lái, TP. Thủ Đức', 10.7626, 106.7871, 500, 3)
    ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;
""")

# Seed orders
orders = [
    ("DH-SAOMAI-001", "NM_NHON_TRACH", 1, "INTERNAL", "KH_HOAPHAT", "Nhà máy Xi măng Sao Mai - Nhơn Trạch", 10.7025, 106.9452, "Công trình Cầu Phước Khánh, Nhơn Trạch", 10.6651, 106.9123, "50H-891.21", 2, 32.5),
    ("DH-SAOMAI-002", "NM_HIEP_PHUOC", 2, "INTERNAL", "KH_COTEC", "Nhà máy Hiệp Phước, Nhà Bè", 10.6225, 106.7452, "Trạm trộn Bê tông Lê Phan, Q.7", 10.7321, 106.7210, "50H-538.61", 2, 28.0),
    ("DH-SAOMAI-003", "NM_LONG_AN", 1, "RENTAL", "KH_VINCONS", "Kho Long An KCN Thuận Đạo", 10.6102, 106.5120, "Dự án Khu đô thị Waterpoint, Bến Lức", 10.6401, 106.4950, "51D-477.61", 2, 30.0),
]
for o in orders:
    cur.execute("""
        INSERT INTO orders (order_code, factory_code, product_id, transport_type, customer_group_id,
                            pickup_address, pickup_lat, pickup_lng, delivery_address, delivery_lat, delivery_lng,
                            assigned_vehicle_plate, assigned_driver_id, cargo_weight_tons, status)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'assigned')
        ON CONFLICT (order_code) DO NOTHING;
    """, o)

conn.commit()
cur.close()
conn.close()
print("Seed data completed successfully")
