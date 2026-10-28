// Test kiem chung form "Them/Sua diem nhan / giao" (locations_screen.dart)
// da dong bo icon + style voi form don hang (dispatch_supervisor_screen.dart):
//   - Icon 17 co gioi han khung (prefixIconConstraints minWidth: 34)
//   - Label dam dat rieng phia tren (fontSize 12.5, w600)
//   - Input isDense, vien radius 4 theo inputDecorationTheme toan cuc
//
// Chay:
//   flutter test test/dispatch_icon_test.dart --update-goldens   (lan dau: tao golden PNG)
//   flutter test test/dispatch_icon_test.dart                    (lan sau: verify)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_tai_xe/screens/locations_screen.dart';

Future<void> _loadFonts() async {
  final items = <String, List<String>>{
    'Nunito': ['assets/fonts/Nunito-Variable.ttf'],
    'Quicksand': ['assets/fonts/Quicksand-Variable.ttf'],
    'Roboto': [
      'assets/fonts/Roboto-Regular.ttf',
      'assets/fonts/Roboto-Bold.ttf',
    ],
  };
  for (final e in items.entries) {
    final loader = FontLoader(e.key);
    for (final p in e.value) {
      loader.addFont(rootBundle.load(p));
    }
    await loader.load();
  }
}

// Bam sat theme toan cuc cua app trong lib/main.dart
Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      useMaterial3: true,
      fontFamily: 'Nunito',
      shadowColor: Colors.transparent,
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
          borderSide: BorderSide(color: Colors.black26),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
          borderSide: BorderSide(color: Colors.blue, width: 1.5),
        ),
      ),
    ),
    home: Scaffold(body: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);

  testWidgets('Form diem: icon 17 gioi han khung + label dam rieng phia tren', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 1000);
    addTearDown(tester.view.reset);
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(const LocationsScreen()));
    await tester.pump();

    // Mo dialog "Them diem nhan / giao" qua nut toolbar "Them diem"
    await tester.tap(find.byIcon(Icons.add_location_alt_outlined));
    await tester.pump(); // bat dau mo dialog
    // Khong dung pumpAndSettle: man hinh ben duoi con spinner fetch animate vo han
    await tester.pump(
      const Duration(milliseconds: 600),
    ); // cho animation dialog chay xong

    // Mo dung dialog
    expect(find.text('Thêm điểm nhận / giao'), findsOneWidget);

    // Moi field co prefixIcon deu phai: icon size 17 + gioi han khung minWidth 34 + isDense
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .where((f) => f.decoration?.prefixIcon != null)
        .toList();
    expect(
      fields.length,
      greaterThanOrEqualTo(7),
      reason: 'Form co 7 o nhap + 1 select',
    );
    for (final f in fields) {
      expect(
        (f.decoration!.prefixIcon as Icon).size,
        17,
        reason: 'Icon phai co size 17 theo chuan app',
      );
      expect(
        f.decoration!.prefixIconConstraints?.minWidth,
        34,
        reason: 'Gioi han khung icon phai la minWidth 34 theo chuan app',
      );
      expect(
        f.decoration!.isDense ?? false,
        isTrue,
        reason: 'Input phai isDense',
      );
    }

    // Icon phu hop dung voi tung field
    int countIcon(IconData data) => tester
        .widgetList<Icon>(find.byIcon(data))
        .where((i) => i.size == 17)
        .length;
    expect(
      countIcon(Icons.place_outlined),
      greaterThanOrEqualTo(1),
      reason: 'Ten diem',
    );
    expect(
      countIcon(Icons.location_on_outlined),
      greaterThanOrEqualTo(1),
      reason: 'Dia chi',
    );
    expect(
      countIcon(Icons.my_location),
      greaterThanOrEqualTo(2),
      reason: 'Vi do + Kinh do',
    );
    expect(
      countIcon(Icons.radar),
      greaterThanOrEqualTo(1),
      reason: 'Ban kinh nhan dien',
    );
    expect(
      countIcon(Icons.notes_outlined),
      greaterThanOrEqualTo(1),
      reason: 'Ghi chu',
    );
    expect(
      countIcon(Icons.swap_vert),
      greaterThanOrEqualTo(1),
      reason: 'Loai diem (select)',
    );

    // Label dam dat rieng phia tren o nhap
    final label = tester.widget<Text>(find.text('Tên điểm *'));
    expect(label.style?.fontWeight, FontWeight.w600);
    expect(label.style?.fontSize, 12.5);

    // Soi truc tiep ket qua qua golden PNG
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/form_diem_nhan_giao.png'),
    );
  });
}
