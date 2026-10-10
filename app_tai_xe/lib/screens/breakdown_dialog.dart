import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/breakdown_model.dart';
import '../services/app_state.dart';

class BreakdownDialog extends StatefulWidget {
  const BreakdownDialog({super.key});

  @override
  State<BreakdownDialog> createState() => _BreakdownDialogState();
}

class _BreakdownDialogState extends State<BreakdownDialog> {
  BreakdownCategory _selectedCat = BreakdownCategory.tire;
  final TextEditingController _descController = TextEditingController();
  bool _photoTaken = false;

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: const [
          Icon(Icons.warning_amber_rounded, color: Colors.deepOrange),
          SizedBox(width: 8),
          Text("Báo hỏng xe đột xuất", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Chọn hạng mục gặp sự cố:", style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            DropdownButtonFormField<BreakdownCategory>(
              value: _selectedCat,
              isExpanded: true,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: BreakdownCategory.values.map((cat) {
                return DropdownMenuItem(
                  value: cat,
                  child: Text(cat.displayName),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedCat = val);
              },
            ),
            const SizedBox(height: 14),
            const Text("Mô tả chi tiết sự cố:", style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _descController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: "Ví dụ: Lốp sau nứt rách sâu hoặc van bồn xả bị nghẹt rò rỉ...",
              ),
            ),
            const SizedBox(height: 14),
            const Text("Ảnh chụp cận cảnh:", style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            InkWell(
              onTap: () {
                setState(() => _photoTaken = true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Đã chụp ảnh cận cảnh sự cố (nén 240 KB)")),
                );
              },
              child: Container(
                height: 100,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _photoTaken ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _photoTaken ? Colors.green : Colors.grey.shade400,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Center(
                  child: _photoTaken
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.check_circle, color: Colors.green),
                            SizedBox(width: 8),
                            Text("Đã có ảnh sự cố", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.camera_alt, color: Colors.grey, size: 30),
                            SizedBox(height: 4),
                            Text("Bấm để chụp ảnh hiện trường", style: TextStyle(color: Colors.grey, fontSize: 13)),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "* Chuyến sẽ bị giữ trên hệ thống cho tới khi Điều phối bấm 'Cho chạy' hoặc 'Đưa vào xưởng'.",
              style: TextStyle(color: Colors.redAccent, fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Hủy bỏ"),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
          onPressed: () {
            if (_descController.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Vui lòng nhập mô tả sự cố")),
              );
              return;
            }
            context.read<AppState>().addBreakdownReport(
                  _selectedCat,
                  "storage/breakdowns/bh_${DateTime.now().millisecondsSinceEpoch}.jpg",
                  _descController.text.trim(),
                );
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: Colors.redAccent,
                content: Text("Đã gửi Báo hỏng! Chuyến xe tạm thời bị giữ."),
              ),
            );
          },
          child: const Text("Gửi Báo hỏng", style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
