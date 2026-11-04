// Test kich thuoc dialog "Nhat ky & Lich su ca truc".
// Yeu cau: width = 980 (gap doi so voi 480 mac dinh cua dialogTheme) khi man hinh rong,
// bang 98% be rong man hinh khi cua so hep.
// Luu y: dung pump() dinh thay vi pumpAndSettle vi FutureBuilder
// ben trong goi API that (HTTP bi chan trong test env).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_tai_xe/screens/dispatch_supervisor_screen.dart';

Future<void> _openDialog(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    // Gia lap dung dialogTheme toan app (maxWidth: 480) de kiem chung
    // viec Dialog da ghi de thanh cong constraints maxWidth: 480 nay.
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
  // Hoan tat fade-in route (150ms) ma khong cho settle vo han.
  await tester.pump(const Duration(milliseconds: 300));
  _drainExceptions(tester);
  await tester.pump(const Duration(milliseconds: 300));
  _drainExceptions(tester);
}

/// Xa het cac exception da ghi nhan (HTTP bi chan, overflow noi dung
/// co san...) de tap trung vao ket qua do width.
void _drainExceptions(WidgetTester tester) {
  var n = 0;
  while (n < 20 && tester.takeException() != null) {
    n++;
  }
}

double _measureDialogWidth(WidgetTester tester) {
  final box = tester.renderObject<RenderBox>(
    find.byKey(const ValueKey('shiftHistoryDialogBox')),
  );
  return box.size.width;
}

void main() {
  testWidgets('Dialog lich su ca: width 980 khi man hinh rong (vuot qua maxWidth 480 cua theme)',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _openDialog(tester);
    final w = _measureDialogWidth(tester);
    expect(w, closeTo(980.0, 0.5),
        reason: 'Man hinh 1920 => dialog phai rong 980 (gap doi 480), thuc te: $w');
  });

  testWidgets('Dialog lich su ca: theo 98% man hinh khi cua so hep 520x900',
      (tester) async {
    tester.view.physicalSize = const Size(520, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _openDialog(tester);
    final w = _measureDialogWidth(tester);
    // Container dat 509.6 nhung bi insetPadding (24 moi ben) kep con 472.
    final expected = 520.0 - 48.0;
    expect(w, closeTo(expected, 1.0),
        reason: 'Cua so 520 => dialog bi kep boi insetPadding, thuc te: $w');
  });
}
