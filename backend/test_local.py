import requests
import json
import sys

BASE_URL = "http://localhost:8000"

def log(msg, status="INFO"):
    print(f"[{status}] {msg}")

def run_tests():
    log("=== BẮT ĐẦU CHẠY KIỂM THỬ TỰ ĐỘNG CÁC LUỒNG NGHIỆP VỤ (LOCAL TEST) ===")

    # 1. Kiểm tra Health Check
    res = requests.get(f"{BASE_URL}/")
    assert res.status_code == 200, f"Health check thất bại: {res.text}"
    log("1. Health Check API: HOẠT ĐỘNG BÌNH THƯỜNG", "PASS")

    # 2. Đăng nhập Admin lấy JWT Token
    res = requests.post(f"{BASE_URL}/api/v1/auth/login", json={
        "username": "admin",
        "password": "admin123"
    })
    assert res.status_code == 200, f"Đăng nhập admin thất bại: {res.text}"
    admin_data = res.json()
    admin_token = admin_data["access_token"]
    headers_admin = {"Authorization": f"Bearer {admin_token}"}
    log("2. Đăng nhập Admin lấy Bearer JWT Token: THÀNH CÔNG", "PASS")

    # 3. Tạo tài khoản Tài xế và Cây dầu
    driver_payload = {
        "username": "driver_nguyenvana",
        "password": "password123",
        "full_name": "Nguyễn Văn A",
        "phone": "0988112233",
        "driver_type": "INTERNAL",
        "role_codes": ["driver"]
    }
    res = requests.post(f"{BASE_URL}/api/v1/users", json=driver_payload, headers=headers_admin)
    if res.status_code == 400 and "already exists" in res.text:
        log("Tài khoản tài xế đã tồn tại từ trước, bỏ qua tạo mới")
    else:
        assert res.status_code == 201, f"Tạo tài xế thất bại: {res.text}"
    log("3.1. Khởi tạo tài khoản Tài xế (INTERNAL): THÀNH CÔNG", "PASS")

    gas_station_user_payload = {
        "username": "caydau_petrolimex01",
        "password": "password123",
        "full_name": "Trạm Cấp Dầu Petrolimex 01",
        "phone": "0977223344",
        "driver_type": "INTERNAL",
        "role_codes": ["gas_station"]
    }
    res = requests.post(f"{BASE_URL}/api/v1/users", json=gas_station_user_payload, headers=headers_admin)
    if res.status_code == 400 and "already exists" in res.text:
        log("Tài khoản cây dầu đã tồn tại từ trước, bỏ qua tạo mới")
    else:
        assert res.status_code == 201, f"Tạo cây dầu thất bại: {res.text}"
    log("3.2. Khởi tạo tài khoản Cây dầu: THÀNH CÔNG", "PASS")

    # 4. Đăng nhập bằng tài khoản Tài xế
    res = requests.post(f"{BASE_URL}/api/v1/auth/login", json={
        "username": "driver_nguyenvana",
        "password": "password123"
    })
    assert res.status_code == 200, f"Đăng nhập tài xế thất bại: {res.text}"
    driver_data = res.json()
    driver_token = driver_data["access_token"]
    driver_id = driver_data["user_id"]
    headers_driver = {"Authorization": f"Bearer {driver_token}"}
    log(f"4. Tài xế đăng nhập thành công (ID: {driver_id}, Token cấp mới): THÀNH CÔNG", "PASS")

    # 5. Tạo phương tiện và trạm cây dầu (bằng quyền Admin)
    plate_number = "50H-166.27"
    res = requests.post(f"{BASE_URL}/api/v1/vehicles", json={
        "plate_number": plate_number,
        "vehicle_type": "Howo",
        "ownership_type": "INTERNAL",
        "default_driver_id": driver_id
    }, headers=headers_admin)
    log(f"5.1. Đăng ký phương tiện {plate_number} (Howo): THÀNH CÔNG", "PASS")

    station_lat = 10.7769
    station_lng = 106.7009
    res = requests.post(f"{BASE_URL}/api/v1/gas-stations", json={
        "name": "Cây Xăng Petrolimex Quận 2",
        "address": "123 Mai Chí Thọ, TP. Thủ Đức",
        "lat": station_lat,
        "lng": station_lng,
        "allowed_radius_meters": 500
    }, headers=headers_admin)
    gas_station_id = res.json()["id"]
    log(f"5.2. Khởi tạo trạm Cây dầu hợp đồng (ID: {gas_station_id}): THÀNH CÔNG", "PASS")

    # 6. Kiểm tra trạng thái xe trước khi nộp 5 ảnh (Bắt buộc khóa nút Nhận chuyến)
    res = requests.get(f"{BASE_URL}/api/v1/inspection/status/{plate_number}", headers=headers_driver)
    assert res.status_code == 200
    status_data = res.json()
    assert status_data["can_take_trip"] is False, "Lỗi: Chưa chụp 5 ảnh mà cho phép nhận chuyến!"
    log(f"6. Khóa nút nhận chuyến khi chưa có 5 ảnh: CHÍNH XÁC ({status_data['reason']})", "PASS")

    # 7. Tài xế nộp bộ 5 ảnh kiểm tra đầu ngày (kèm km táp lô)
    from datetime import date
    today_str = date.today().isoformat()
    res = requests.post(f"{BASE_URL}/api/v1/inspection/submit", json={
        "check_date": today_str,
        "plate_number": plate_number,
        "driver_id": driver_id,
        "img_front_underbody": "https://storage.vintrans.vn/2026/10/front_underbody.jpg",
        "img_rear_underbody": "https://storage.vintrans.vn/2026/10/rear_underbody.jpg",
        "img_left_side": "https://storage.vintrans.vn/2026/10/left_side.jpg",
        "img_right_side": "https://storage.vintrans.vn/2026/10/right_side.jpg",
        "img_dashboard": "https://storage.vintrans.vn/2026/10/dashboard.jpg",
        "gps_lat": 10.8231,
        "gps_lng": 106.6297,
        "gps_accuracy": 5.2,
        "device_id": "Pixel_7_Android_14",
        "km_ocr": 125430.0,
        "km_confirmed": 125430.0
    }, headers=headers_driver)
    assert res.status_code == 201, f"Nộp 5 ảnh thất bại: {res.text}"
    log("7. Tài xế nộp đủ 5 ảnh kiểm tra đầu ngày: THÀNH CÔNG", "PASS")

    # 8. Kiểm tra lại trạng thái xe (Đã mở khóa nút Nhận chuyến)
    res = requests.get(f"{BASE_URL}/api/v1/inspection/status/{plate_number}", headers=headers_driver)
    status_data = res.json()
    assert status_data["can_take_trip"] is True, "Lỗi: Đã nộp 5 ảnh nhưng nút nhận chuyến vẫn bị khóa!"
    log(f"8. Mở khóa nút nhận chuyến sau khi đủ 5 ảnh: CHÍNH XÁC ({status_data['reason']})", "PASS")

    # 9. Điều phối tạo đơn hàng chở Tro Bay cho xe này
    order_code = f"ORDER_TB_{int(today_str.replace('-', ''))}_01"
    res = requests.post(f"{BASE_URL}/api/v1/orders", json={
        "order_code": order_code,
        "factory_code": "NM_VINTRANS_01",
        "product_id": 1, # Tro Bay
        "transport_type": "INTERNAL",
        "customer_group_id": "zalo_group_xi_mang_ha_tien",
        "pickup_address": "Nhà máy Nhiệt điện Vĩnh Tân",
        "pickup_lat": 11.3174,
        "pickup_lng": 108.8833,
        "delivery_address": "Trạm trộn Bê tông Thủ Đức",
        "delivery_lat": 10.8494,
        "delivery_lng": 106.7725,
        "assigned_vehicle_plate": plate_number,
        "assigned_driver_id": driver_id,
        "cargo_weight_tons": 32.5
    }, headers=headers_admin)
    assert res.status_code == 201, f"Tạo đơn hàng thất bại: {res.text}"
    order_id = res.json()["id"]
    log(f"9. Tạo đơn hàng {order_code} (Sản phẩm: Tro Bay, Tải trọng: 32.5 tấn): THÀNH CÔNG", "PASS")

    # 10. Cây Dầu xác nhận cấp nhiên liệu & Đối soát khoảng cách GPS
    res = requests.post(f"{BASE_URL}/api/v1/auth/login", json={
        "username": "caydau_petrolimex01",
        "password": "password123"
    })
    gas_station_token = res.json()["access_token"]
    headers_gas = {"Authorization": f"Bearer {gas_station_token}"}

    # TH1: Cây dầu chụp tại đúng trạm (khoảng cách < 100m)
    res = requests.post(f"{BASE_URL}/api/v1/fuel/confirm", json={
        "order_id": order_id,
        "plate_number": plate_number,
        "gas_station_id": gas_station_id,
        "fuel_type": "diesel",
        "liters_ocr": 150.0,
        "liters_actual": 150.0,
        "img_meter": "https://storage.vintrans.vn/fuel/meter_150l.jpg",
        "img_receipt": "https://storage.vintrans.vn/fuel/receipt_150l.jpg",
        "gps_lat": station_lat + 0.0001, # Lệch ~11 mét
        "gps_lng": station_lng + 0.0001
    }, headers=headers_gas)
    assert res.status_code == 201
    fuel_data = res.json()
    assert fuel_data["flag_location_mismatch"] is False, "Lỗi: Tọa độ đúng nhưng bị gắn cờ lệch!"
    log(f"10.1. Cây dầu cấp 150 lít đúng vị trí (Cách {fuel_data['distance_to_station_meters']}m): HỢP LỆ (Không gắn cờ)", "PASS")

    # TH2: Cây dầu chụp sai vị trí (> 500m)
    res = requests.post(f"{BASE_URL}/api/v1/fuel/confirm", json={
        "order_id": order_id,
        "plate_number": plate_number,
        "gas_station_id": gas_station_id,
        "fuel_type": "diesel",
        "liters_ocr": 100.0,
        "liters_actual": 100.0,
        "img_meter": "https://storage.vintrans.vn/fuel/meter_fake.jpg",
        "gps_lat": station_lat + 0.05, # Lệch > 5km
        "gps_lng": station_lng + 0.05
    }, headers=headers_gas)
    fuel_data_err = res.json()
    assert fuel_data_err["flag_location_mismatch"] is True, "Lỗi: Cách quá 500m nhưng không bật cờ lệch!"
    log(f"10.2. Cây dầu cấp sai vị trí (Cách {fuel_data_err['distance_to_station_meters']}m): ĐÃ TỰ ĐỘNG BẬT CỜ CẢNH BÁO", "PASS")

    # 11. Tài xế bấm mốc giờ chuyến (ĐẾN & BƠM XONG)
    res = requests.post(f"{BASE_URL}/api/v1/trip/arrive", json={
        "order_id": order_id,
        "plate_number": plate_number,
        "arrive_lat": 10.8494,
        "arrive_lng": 106.7725
    }, headers=headers_driver)
    assert res.status_code == 200
    log("11.1. Tài xế bấm mốc ĐẾN điểm giao: THÀNH CÔNG", "PASS")

    res = requests.post(f"{BASE_URL}/api/v1/trip/pump-done", json={
        "order_id": order_id,
        "plate_number": plate_number,
        "pump_done_lat": 10.8494,
        "pump_done_lng": 106.7725,
        "wait_reason_code": "CHO_XN_XUONG",
        "wait_reason_note": "Chờ cán bộ xưởng kiểm tra bồn chứa"
    }, headers=headers_driver)
    assert res.status_code == 200
    log("11.2. Tài xế bấm mốc BƠM XONG (Kèm lý do chờ): THÀNH CÔNG", "PASS")

    log("=== TOÀN BỘ CÁC KỊCH BẢN KIỂM THỬ ĐÃ CHẠY HOÀN HẢO TRÊN MÔI TRƯỜNG LOCAL ===", "SUCCESS")

if __name__ == "__main__":
    run_tests()
