import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'elder_dashboard.dart';
import 'guardian_dashboard.dart';
import 'volunteer_dashboard.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  static const Color _primaryGreen = Color(0xFF0F765E);

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }


Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email and password.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.session != null && mounted) {
        await _navigateToDashboard();
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final isOffline = e.toString().contains('SocketException') ||
            e.toString().contains('Failed host lookup') ||
            e.toString().contains('ClientException');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isOffline
                  ? 'No internet connection. Please turn on Wi-Fi or Mobile Data to sign in.'
                  : 'Login failed: $e',
            ),
            backgroundColor: const Color(0xFFD97706),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _navigateToDashboard() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || !mounted) return;

    String role = 'elder';
    try {
      final metadataRole = user.userMetadata?['role'] as String?;
      if (metadataRole != null && metadataRole.isNotEmpty) {
        role = metadataRole.toLowerCase().trim();
      }
    } catch (_) {}

    Widget targetDashboard;
    if (role == 'guardian') {
      targetDashboard = const GuardianDashboard();
    } else if (role == 'volunteer') {
      targetDashboard = const VolunteerDashboard(); // <-- Added this route
    } else {
      targetDashboard = ElderDashboard();
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => targetDashboard),
    );
  }
  
  Future<void> _signIn() async {
  final email = _emailController.text.trim();
  final password = _passwordController.text.trim();

  if (email.isEmpty || password.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please enter your email and password.')),
    );
    return;
  }

  setState(() => _isLoading = true);

  try {
    final response = await Supabase.instance.client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    if (response.session != null && mounted) {
      // Determine user role and route to the corresponding dashboard
      _navigateToDashboard();
    }
  } on AuthException catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red,
        ),
      );
    }
  } catch (e) {
    // Catches SocketException, ClientException, and DNS failures when offline
    if (mounted) {
      final isOffline = e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup') ||
          e.toString().contains('ClientException');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isOffline
                ? 'No internet connection. Please turn on Wi-Fi or Mobile Data to sign in.'
                : 'Login failed. Please check your credentials.',
          ),
          backgroundColor: const Color(0xFFD97706),
        ),
      );
    }
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F8),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.health_and_safety, size: 70, color: _primaryGreen),
                const SizedBox(height: 12),
                const Text(
                  'SahayAyu',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: _primaryGreen,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Welcome back',
                  style: TextStyle(fontSize: 15, color: Colors.grey[600]),
                ),
                const SizedBox(height: 36),

                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.email_outlined),
                    labelText: 'Email',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock_outline),
                    labelText: 'Password',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Login', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 18),

                TextButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const RegisterScreen()),
                    );
                  },
                  child: RichText(
                    text: TextSpan(
                      text: "Don't have an account? ",
                      style: TextStyle(color: Colors.grey[700]),
                      children: const [
                        TextSpan(
                          text: 'Register',
                          style: TextStyle(color: _primaryGreen, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}