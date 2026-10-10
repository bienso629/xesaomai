import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:app_tai_xe/main.dart';
import 'package:app_tai_xe/services/app_state.dart';

void main() {
  testWidgets('App navigation and tabs smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppState()),
        ],
        child: const TaxiDriverApp(),
      ),
    );

    // Kiểm tra màn hình Đăng nhập hiển thị đầu tiên
    expect(find.text('Đăng nhập'), findsOneWidget);
    expect(find.textContaining('Sao Mai'), findsOneWidget);

    // Bấm nút Đăng nhập để vào màn hình chính
    await tester.tap(find.text('Đăng nhập'));
    await tester.pumpAndSettle();

    // Kiểm tra hiển thị 3 tabs ở navigation bar
    expect(find.text('Bản đồ'), findsOneWidget);
    expect(find.text('Tài xế'), findsOneWidget);
    expect(find.text('Quản lý'), findsOneWidget);

    // Mặc định tab 0 là Bản đồ
    expect(find.textContaining('Giám Sát'), findsOneWidget);

    // Nhấn chuyển sang tab Tài xế
    await tester.tap(find.text('Tài xế'));
    await tester.pumpAndSettle();

    // Màn hình của tài xế hiển thị các nội dung cốt lõi
    expect(find.textContaining('Kiểm tra xe đầu ngày'), findsOneWidget);
    expect(find.textContaining('Lịch Chuyến & Mốc Giờ'), findsOneWidget);

    // Nhấn chuyển sang tab Quản lý
    await tester.tap(find.text('Quản lý'));
    await tester.pumpAndSettle();

    // Màn hình Quản lý hiển thị các nội dung giám sát điều phối
    expect(find.textContaining('Màn hình Điều phối'), findsOneWidget);
    expect(find.textContaining('Cờ Bất Thường'), findsOneWidget);
  });
}
