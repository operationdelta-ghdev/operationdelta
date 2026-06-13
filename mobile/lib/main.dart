import 'package:flutter/material.dart';
import 'screens/dashboard_screen.dart';
import 'services/notification_service.dart';

void main() async {
  // Ensure framework is ready for plugins
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize notification service BEFORE runApp so it is ready
  // when the dashboard makes its first fetch and rescheduleAlarms() call.
  try {
    await NotificationService().init();
  } catch (e) {
    debugPrint("Notification service initialization failed: $e");
  }

  runApp(const IngressEventApp());
}

class IngressEventApp extends StatelessWidget {
  const IngressEventApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Operation Delta',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF080b11),
        primaryColor: const Color(0xFF00c8ff),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00c8ff),
          secondary: Color(0xFF02ff77),
          surface: Color(0xFF0d141e),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0d141e),
          elevation: 0,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFFe2e8f0)),
          bodyMedium: TextStyle(color: Color(0xFF94a3b8)),
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}
