# Ghi chú sửa backend Server 3: Cho phép Admin đóng ca hộ điều phối viên

- Ngày sửa: 30/10/2026 17:07
- File: /home/yenai/projects/api.saomai/backend/main.py (bind mount vào container taxi-backend-api)
- Backup: /home/yenai/projects/api.saomai/backend/backups/main_backup_shift_checkout_20261030_170719.py
- MD5 sau sửa: 8ad32d7c08b2222d4a6ecd9ed5f4e375
- Đã restart container taxi-backend-api sau khi sửa.

## Nguyên nhân
Endpoint POST /api/v1/shifts/checkout chỉ đóng ca của chính người đăng nhập
(WHERE user_id = current_user.id). App Flutter đã thiết kế nút "Đóng ca" cho
admin bấm trên ca của điều phối viên khác và gửi kèm user_id trong body,
nhưng backend bỏ qua field này (model ShiftCheckout chỉ có note) nên admin
bấm nút chỉ nhận được cảnh báo "Không tìm thấy ca trực đang mở của bạn".

## Thay đổi 1: Model ShiftCheckout (dòng ~359)
```python
class ShiftCheckout(BaseModel):
    note: Optional[str] = None
    user_id: Optional[int] = None  # Admin dong ca ho dieu phoi vien khac
```

## Thay đổi 2: Hàm checkout_shift (dòng ~3720)
```python
@app.post("/api/v1/shifts/checkout")
def checkout_shift(req: ShiftCheckout, current_user: dict = Depends(get_current_user)):
    current_id = current_user["id"]
    # Xác định user cần đóng ca: mặc định là chính người gọi API.
    # Nếu truyền user_id của người khác => chỉ admin được phép (đóng ca hộ).
    target_id = req.user_id if req.user_id else current_id
    if target_id != current_id and "admin" not in current_user.get("roles", []):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Chỉ tài khoản Quản trị viên mới được phép đóng ca trực của người khác."
        )
    conn = get_db()
    cur = conn.cursor()
    try:
        handover = req.note
        if target_id != current_id:
            actor = current_user.get("full_name") or current_user.get("username") or "Admin"
            prefix = f"[Admin {actor} đóng ca hộ]"
            handover = f"{prefix} {req.note}" if req.note else prefix
        cur.execute("""
            UPDATE dispatcher_shifts 
            SET ended_at = CURRENT_TIMESTAMP,
                status = 'completed',
                handover_note = COALESCE(%s, handover_note)
            WHERE user_id = %s AND status = 'active'
            RETURNING *
        """, (handover, target_id))
        conn.commit()
        updated = cur.fetchone()
        cur.close()
        conn.close()
        if not updated:
            return {"status": "warning", "message": "Không tìm thấy ca trực đang mở của người dùng này"}
        return {"status": "success", "message": "Kết thúc ca trực thành công", "shift": updated}
    except Exception as e:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))
```

## Kết quả kiểm chứng
- Admin đóng ca hộ ca trực id=2 của dieuphoi_vuhoangquan (Vũ Hoàng Quân,
  bắt đầu 19:51 ngày 10/10): thành công, handover_note ghi
  "[Admin Duy IT đóng ca hộ] ..."
- Điều phối thường (dieuphoi_vuhoangquan) truyền user_id của người khác:
  bị chặn đúng 403 "Chỉ tài khoản Quản trị viên mới được phép đóng ca trực của người khác."
- Dispatcher thường đóng ca của chính mình: hoạt động bình thường như cũ.
