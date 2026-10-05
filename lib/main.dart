import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/elder_dashboard.dart';
import 'screens/login_screen.dart';
import 'services/emergency_outbox_service.dart';
import 'services/notification_service.dart';

void main() async {
  // 1. Ensure Flutter bindings are ready
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Initialize Supabase
  try {
    await Supabase.initialize(
      url: 'https://xjvxzjhsmhprbkwuwpou.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhqdnh6amhzbWhwcmJrd3V3cG91Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYyNTcxMzcsImV4cCI6MjEwMTgzMzEzN30.MgaT33q9Pgg0F8syxoj58VXBx1CUxXBQCw8zc9Dy00E', 
    );
  } catch (e) {
    debugPrint('[Startup] Supabase init warning: $e');
  }

  // 3. Initialize Notification Service safely (won't crash app if permissions fail)
  try {
    await NotificationService().init();
    await NotificationService().scheduleMorningCheckIn();
  } catch (e) {
    debugPrint('[Startup] NotificationService init caught: $e');
  }

  // 4. Initialize Local Offline SQLite Outbox safely
  try {
    await EmergencyOutboxService.instance.initialize();
  } catch (e) {
    debugPrint('[Startup] Outbox init caught: $e');
  }

  // 5. Launch UI — Guaranteed to mount now
  runApp(const SahayAyuApp());
}

class SahayAyuApp extends StatelessWidget {
  const SahayAyuApp({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;

    return MaterialApp(
      title: 'SahayAyu',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F765E)),
        useMaterial3: true,
      ),
      home: session != null ? ElderDashboard() : const LoginScreen(),
    );
  }
}