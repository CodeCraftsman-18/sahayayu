import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'elder_dashboard.dart';
import 'guardian_dashboard.dart';
import 'volunteer_dashboard.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String _selectedRole = 'Elder';
  bool _obscurePassword = true;
  bool _isLoading = false;

  final List<String> _roles = ['Elder', 'Guardian', 'Volunteer'];
  static const Color _primaryGreen = Color(0xFF0F765E);

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        data: {
          'full_name': _nameController.text.trim(),
          'role': _selectedRole,
        },
      );

      if (response.user == null) {
        throw 'Registration failed. Please check your details.';
      }

      if (mounted) {
        Widget targetDashboard;
        switch (_selectedRole) {
          case 'Guardian':
            targetDashboard = const GuardianDashboard();
            break;
          case 'Volunteer':
            targetDashboard = const VolunteerDashboard();
            break;
          case 'Elder':
          default:
            targetDashboard = ElderDashboard();
            break;
        }

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => targetDashboard),
          (route) => false,
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
            child: Form(
              key: _formKey,
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
                    'Create your SahayAyu account',
                    style: TextStyle(fontSize: 15, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 32),

                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.person_outline),
                      labelText: 'Full Name',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Enter your name' : null,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.email_outlined),
                      labelText: 'Email',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    ),
                    validator: (v) => v == null || !v.contains('@') ? 'Enter a valid email' : null,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
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
                    validator: (v) => v != null && v.length < 6 ? 'Password must be 6+ chars' : null,
                  ),
                  const SizedBox(height: 20),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'I am registering as:',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[800]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedRole,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.groups_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    items: _roles.map((role) {
                      return DropdownMenuItem(value: role, child: Text(role));
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedRole = val!),
                  ),
                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleRegister,
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
                          : const Text('Create Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 18),

                  TextButton(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => const LoginScreen()),
                      );
                    },
                    child: RichText(
                      text: TextSpan(
                        text: 'Already have an account? ',
                        style: TextStyle(color: Colors.grey[700]),
                        children: const [
                          TextSpan(
                            text: 'Login',
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
      ),
    );
  }
}