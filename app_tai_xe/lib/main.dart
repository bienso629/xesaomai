import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'services/app_state.dart';
import 'screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const TaxiDriverApp());
}

class TaxiDriverApp extends StatelessWidget {
  const TaxiDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AppState())],
      child: MaterialApp(
        title: 'Tài xế Sao Mai',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
          fontFamily: 'Nunito',

          shadowColor: Colors.transparent,

          // Quy chuẩn rounded-sm (BorderRadius = 4px) và loại bỏ hoàn toàn shadow (elevation = 0)
          cardTheme: CardThemeData(
            elevation: 0,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.all(Radius.circular(4)),
              side: BorderSide(color: Colors.grey.shade400, width: 1),
            ),
          ),
          // Quy chuẩn Dialog: chữ to dễ đọc trên mobile (Title 20px bold, Nội dung 15px, giãn dòng 1.5)
          // Phóng to dialog toàn app: rộng tối đa 480 (mặc định ~280), thêm 16 lề mỗi bên để không chạm mép màn hình hẹp
          dialogTheme: const DialogThemeData(
            elevation: 0,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(4)),
            ),
            constraints: BoxConstraints(minWidth: 320, maxWidth: 480),
            insetPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            titleTextStyle: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            contentTextStyle: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: Colors.black87,
            ),
          ),
          appBarTheme: const AppBarTheme(
            elevation: 0,
            scrolledUnderElevation: 0,
            shadowColor: Colors.transparent,
          ),
          drawerTheme: const DrawerThemeData(
            elevation: 0,
            shadowColor: Colors.transparent,
          ),

          // Quy chuẩn Toast thông báo (SnackBar): Nổi (floating), cách đáy 100px, co gọn vừa phải (không full width, tự co theo chiều rộng màn hình), bo góc 4px
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            insetPadding: const EdgeInsets.only(
              bottom: 100,
              left: 24,
              right: 24,
            ),
            width: 420, // Độ rộng gọn gàng trên Desktop, tự căn giữa
          ),

          // Quy chuẩn rounded-sm cho Input và Select (DropdownFormField)
          inputDecorationTheme: const InputDecorationTheme(
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

          // Quy chuẩn rounded-sm và đồng bộ chiều cao 36px cho ElevatedButton
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              elevation: 0,
              shadowColor: Colors.transparent,
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              minimumSize: const Size(64, 36),
              fixedSize: const Size.fromHeight(36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.standard,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
          ),

          // Quy chuẩn rounded-sm và đồng bộ chiều cao 36px cho OutlinedButton
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(64, 36),
              fixedSize: const Size.fromHeight(36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.standard,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
          ),
          // Quy chuẩn nút văn bản (TextButton) trong Dialog: chiều cao 36px, chữ 13px đậm
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              minimumSize: const Size(64, 36),
              fixedSize: const Size.fromHeight(36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.standard,
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
          ),

          // Quy chuẩn rounded-sm và đồng bộ chiều cao 36px cho FilledButton
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size(64, 36),
              fixedSize: const Size.fromHeight(36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.standard,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
          ),

          // Quy chuẩn rounded-sm cho SegmentedButton
          segmentedButtonTheme: SegmentedButtonThemeData(
            style: ButtonStyle(
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ),
        ),
        builder: (context, child) {
          // Toast (SnackBar) responsive: giữ width 420 gọn gàng trên Desktop,
          // tự co lại trên màn hình điện thoại hẹp (tránh dính sát 2 mép).
          // Lề tối thiểu 14dp mỗi bên -> ngưỡng co: 420 + 2 * 14 = 448.
          final screenW = MediaQuery.sizeOf(context).width;
          final toastMax = screenW < 448 ? screenW - 28 : 420.0;
          return Theme(
            data: Theme.of(context).copyWith(
              snackBarTheme: Theme.of(
                context,
              ).snackBarTheme.copyWith(width: toastMax),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const LoginScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
