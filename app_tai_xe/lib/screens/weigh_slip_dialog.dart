import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';

class WeighSlipDialog extends StatefulWidget {
  const WeighSlipDialog({super.key});

  @override
  State<WeighSlipDialog> createState() => _WeighSlipDialogState();
}

class _WeighSlipDialogState extends State<WeighSlipDialog> {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _tonsController = TextEditingController(text: "28.45");
  DateTime _weighTime = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: const [
          Icon(Icons.scale, color: Colors.indigo),
          SizedBox(width: 8),
          Text("Gửi Phiếu Cân Nhà Máy", style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Kết quả OCR tự động trích xuất phiếu cân:",
                style: TextStyle(fontSize: 13.5, color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: "Mã lấy hàng / Đơn hàng",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.qr_code),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _tonsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Khối lượng thực cân (Tấn)",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.line_weight),
                suffixText: "Tấn",
              ),
            ),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time, color: Colors.indigo),
              title: const Text("Giờ cân trên phiếu", style: TextStyle(fontSize: 15)),
              subtitle: Text("${_weighTime.hour}:${_weighTime.minute.toString().padLeft(2, '0')} - ${_weighTime.day}/${_weighTime.month}/${_weighTime.year}",
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
              trailing: IconButton(
                icon: const Icon(Icons.edit_calendar),
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(_weighTime),
                  );
                  if (picked != null) {
                    setState(() {
                      _weighTime = DateTime(_weighTime.year, _weighTime.month, _weighTime.day, picked.hour, picked.minute);
                    });
                  }
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: const [
                  Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Sau khi lưu, app lưu vào Ma_so_nha_may và tự động gửi vào nhóm Zalo OA khách hàng khi đủ điều kiện.",
                      style: TextStyle(fontSize: 12.5, color: Colors.blueGrey),
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Hủy", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
          onPressed: () {
            final tons = double.tryParse(_tonsController.text) ?? 28.45;
            context.read<AppState>().recordWeighSlip(
                  photoUrl: "storage/slips/phieu_can_${DateTime.now().millisecondsSinceEpoch}.jpg",
                  tonnage: tons,
                  weighTime: _weighTime,
                );
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: Colors.indigo,
                content: Text("Đã lưu Phiếu Cân & tự động đẩy nhóm Zalo OA khách hàng!"),
              ),
            );
          },
          child: const Text("Xác nhận & Gửi", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
