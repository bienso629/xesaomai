// Kiem thu layout dialog "Nhat ky & Lich su ca truc" TRONG TRANG THAI CO DU LIEU
// (bang danh sach ca truc + thanh phan trang), thuong xay ra overflow khi dialog
// chi rong 480 theo dialogTheme mac dinh. Su dung test seam
// DispatchSupervisorScreen.debugShiftHistoryDataSource de nap du lieu gia,
// khong goi HTTP that.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_tai_xe/screens/dispatch_supervisor_screen.dart';

List<Map<String, dynamic>> _fakeShifts(int n) {
  return List.generate(n, (i) => {
        'id': i + 1,
        'shift_name': 'Ca ngày',
        'status': i == 0 ? 'active' : 'completed',
        'note': 'Ghi chú nhận ca số $i cho kiểm thử layout',
        'handover_note': i.isOdd ? 'Bàn giao ca sau chi tiết $i' : '',
        'duration_hours': '8.5',
        'started_at': '2026-02-05T07:30:00Z',
        'ended_at': i == 0 ? null : '2026-02-05T16:00:00Z',
      });
}

Future<void> _openDialogWithData(WidgetTester tester, int itemCount) async {
  DispatchSupervisorScreen.debugShiftHistoryDataSource = _fakeShifts(itemCount);
  addTearDown(() => DispatchSupervisorScreen.debugShiftHistoryDataSource = null);

  await tester.pumpWidget(MaterialApp(
    // Dung y dialogTheme toan app: kep maxWidth 480 - trang thai that ma
    // nguoi dung gap loi layout.
    theme: ThemeData(
      dialogTheme: const DialogThemeData(
        constraints: BoxConstraints(minWidth: 320, maxWidth: 480),
      ),
    ),
    home: Scaffold(
      body: Builder(
        builder: (ctx) => Center(
          child: ElevatedButton(
            onPressed: () =>
                DispatchSupervisorScreen.showShiftHistoryDialog(ctx),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ));

  await tester.tap(find.text('Open'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

double _rightEdgeOfPagerControls(WidgetTester tester) {
  final box = tester.renderObject<RenderBox>(
    find.byKey(const ValueKey('shiftHistoryPagerControls')),
  );
  final topLeft = box.localToGlobal(Offset.zero);
  return topLeft.dx + box.size.width;
}

double _rightEdgeOfPagerBar(WidgetTester tester) {
  final box = tester.renderObject<RenderBox>(
    find.byKey(const ValueKey('shiftHistoryPagerBar')),
  );
  final topLeft = box.localToGlobal(Offset.zero);
  return topLeft.dx + box.size.width;
}

void main() {
  testWidgets('Dialog co du lieu: khong xay ra exception/overflow layout',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _openDialogWithData(tester, 12);

    // Neu co RenderFlex overflow (ngang hoac doc) thi takeException tra khac null.
    expect(tester.takeException(), isNull,
        reason: 'Dialog phai render tron ven bang + thanh phan trang khong loi layout');
  });

  testWidgets('Cum dieu khien phan trang bam sat le phai cua thanh phan trang',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _openDialogWithData(tester, 12);

    final controlsRight = _rightEdgeOfPagerControls(tester);
    final barRight = _rightEdgeOfPagerBar(tester);
    expect(barRight - controlsRight, lessThanOrEqualTo(20.0),
        reason: 'Cum dieu khien (Số dòng/trang + nut chuyen trang) phai can le phai, '
            'khoang cach le phai thanh: ${barRight - controlsRight}px');
  });

  testWidgets('Nut so dong/trang hien thi dung gia tri hien tai',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _openDialogWithData(tester, 12);

    // Mac dinh 10 dong/trang - nut phai hien chu so 10 thay vi text rong.
    expect(find.descendant(
      of: find.byKey(const ValueKey('shiftHistoryPageSizeTrigger')),
      matching: find.text('10'),
    ), findsOneWidget, reason: 'Nut "Số dòng/trang" phai hien thi so 10');
  });

  testWidgets('Dialog co du lieu tai cua so hep 520: khong overflow',
      (tester) async {
    tester.view.physicalSize = const Size(520, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _openDialogWithData(tester, 12);

    // In ra exception dau tien de chan doan khi test fail.
    final Object? firstErr = tester.takeException();
    if (firstErr != null) {
      // ignore: avoid_print
      print('CHI TIET LOI 520px: $firstErr');
    }
    expect(firstErr, isNull,
        reason: 'Cua so hep 520px cung phai render khong loi layout');
  });
}
