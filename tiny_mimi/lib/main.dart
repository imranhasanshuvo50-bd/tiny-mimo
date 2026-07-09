import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/scan_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/prayer_screen.dart';
import 'screens/time_screen.dart';
import 'screens/settings_screen.dart';
import 'services/ble_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Keep orientation locked to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Eagerly initialize BleService instance to start reconnect loops
  BleService.instance;

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tiny Mimo Controller',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0C0C12),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FFCC),
          secondary: Color(0xFFFF3366),
          background: Color(0xFF0C0C12),
          surface: Color(0xFF1E1E2E),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Color(0xFFF1F1F8),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: IconThemeData(color: Color(0xFF00FFCC)),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFFF1F1F8)),
          bodyMedium: TextStyle(color: Color(0xFF8B8B9E)),
        ),
      ),
      initialRoute: '/scan',
      routes: {
        '/scan': (context) => const ScanScreen(),
        '/dashboard': (context) => const DashboardScreen(),
        '/prayers': (context) => const PrayerScreen(),
        '/time': (context) => const TimeScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}
