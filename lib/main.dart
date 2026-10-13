import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/elder_dashboard.dart';
import 'screens/login_screen.dart';
import 'services/emergency_outbox_service.dart';
import 'services/notification_service.dart';
import 'core/app_config.dart';

void main() async {
  // 1. Ensure Flutter bindings are ready
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Initialize Supabase safely with fallback
  bool isSupabaseReady = false;
  try {
    // Attempt environment config first, fallback to hardcoded credentials if empty
    String url = AppConfig.supabaseUrl;
    String anonKey = AppConfig.supabaseAnonKey;

    if (url.isEmpty || anonKey.isEmpty) {
      url = 'https://xjvxzjhsmhprbkwuwpou.supabase.co';
      anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhqdnh6amhzbWhwcmJrd3V3cG91Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYyNTcxMzcsImV4cCI6MjEwMTgzMzEzN30.MgaT33q9Pgg0F8syxoj58VXBx1CUxXBQCw8zc9Dy00E';
    }

    await Supabase.initialize(
      url: url,
      publishableKey: anonKey,
    );
    isSupabaseReady = true;
  } catch (e) {
    debugPrint('[Startup] Supabase initialization error: $e');
  }

  // 3. Initialize background services safely
  try {
    await NotificationService().init();
    await NotificationService().scheduleMorningCheckIn();
  } catch (e) {
    debugPrint('[Startup] NotificationService caught: $e');
  }

  try {
    await EmergencyOutboxService.instance.initialize();
  } catch (e) {
    debugPrint('[Startup] EmergencyOutboxService caught: $e');
  }

  // 4. Launch UI — Guaranteed to mount
  runApp(SahayAyuApp(isSupabaseReady: isSupabaseReady));
}

class SahayAyuApp extends StatelessWidget {
  final bool isSupabaseReady;
  const SahayAyuApp({super.key, required this.isSupabaseReady});

  @override
  Widget build(BuildContext context) {
    Widget homeScreen;

    if (!isSupabaseReady) {
      // Fallback screen if network or credentials completely failed
      homeScreen = Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off, size: 64, color: Colors.orange),
                const SizedBox(height: 16),
                const Text(
                  'Initialization Error',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Unable to connect to the cloud backend. Please check your internet connection and restart.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => main(),
                  child: const Text('Retry'),
                )
              ],
            ),
          ),
        ),
      );
    } else {
      final session = Supabase.instance.client.auth.currentSession;
      homeScreen = session != null ? const ElderDashboard() : const LoginScreen();
    }

    return MaterialApp(
      title: 'SahayAyu',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F765E)),
        useMaterial3: true,
      ),
      home: homeScreen,
    );
  }
}