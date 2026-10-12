import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/app_state.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const TaxiDriverApp());
}

class TaxiDriverApp extends StatelessWidget {
  const TaxiDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
      ],
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
          dialogTheme: const DialogThemeData(
            elevation: 0,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(4)),
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

          // Quy chuẩn Toast thông báo (SnackBar): Nổi (floating), cách đáy 100px, co gọn vừa phải (không full width), bo góc 4px
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            insetPadding: const EdgeInsets.only(bottom: 100, left: 24, right: 24),
            width: 420, // Độ rộng gọn gàng trên Desktop, tự căn giữa
          ),

          // Quy chuẩn rounded-sm và đồng bộ chiều cao cho Input và Select (DropdownFormField)
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

          // Quy chuẩn rounded-sm và đồng bộ chiều cao 44px cho ElevatedButton
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              elevation: 0,
              shadowColor: Colors.transparent,
              minimumSize: const Size(64, 44),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),

          // Quy chuẩn rounded-sm và đồng bộ chiều cao 44px cho OutlinedButton
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(64, 44),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),

          // Quy chuẩn rounded-sm và đồng bộ chiều cao 44px cho FilledButton
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size(64, 44),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),

          // Quy chuẩn rounded-sm cho SegmentedButton
          segmentedButtonTheme: SegmentedButtonThemeData(
            style: ButtonStyle(
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
        home: const LoginScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
