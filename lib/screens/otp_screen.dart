import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'elder_dashboard.dart';
import 'guardian_dashboard.dart';
import 'volunteer_dashboard.dart';
import 'login_screen.dart';

class OtpScreen extends StatefulWidget {
  final String email;
  final String role;

  const OtpScreen({
    super.key,
    required this.email,
    this.role = 'Elder',
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  static const Color _primaryGreen = Color(0xFF0F765E);
  static const Color _bgColor = Color(0xFFF7F9F8);

  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  int _resendCountdown = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startCountdown() {
    _resendCountdown = 30;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown > 0) {
        setState(() => _resendCountdown--);
      } else {
        _timer?.cancel();
      }
    });
  }

  String get _enteredOtp => _controllers.map((c) => c.text).join();

  Future<void> _verifyOtp() async {
    final token = _enteredOtp.trim();
    if (token.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter all 6 digits of the OTP.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await Supabase.instance.client.auth.verifyOTP(
        email: widget.email,
        token: token,
        type: OtpType.signup,
      );

      if (response.user == null) {
        throw 'Verification failed. Please check the code.';
      }

      if (mounted) {
        Widget targetScreen;
        switch (widget.role) {
          case 'Guardian':
            targetScreen = const GuardianDashboard();
            break;
          case 'Volunteer':
            targetScreen = const VolunteerDashboard();
            break;
          case 'Elder':
          default:
            targetScreen = const ElderDashboard();
            break;
        }

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => targetScreen),
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

  Future<void> _resendOtp() async {
    if (_resendCountdown > 0) return;

    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: widget.email,
      );
      _startCountdown();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A new OTP code has been sent.'),
            backgroundColor: _primaryGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error resending OTP: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const LoginScreen()),
            );
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.mark_email_read_outlined, size: 70, color: _primaryGreen),
                const SizedBox(height: 16),
                const Text(
                  'Verification Code',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: _primaryGreen,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'We sent a 6-digit verification code to\n${widget.email}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.4),
                ),
                const SizedBox(height: 36),

                // 6-digit input row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (index) {
                    return SizedBox(
                      width: 46,
                      height: 56,
                      child: TextField(
                        controller: _controllers[index],
                        focusNode: _focusNodes[index],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 1,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          counterText: '',
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: _primaryGreen, width: 2),
                          ),
                        ),
                        onChanged: (val) {
                          if (val.isNotEmpty && index < 5) {
                            _focusNodes[index + 1].requestFocus();
                          } else if (val.isEmpty && index > 0) {
                            _focusNodes[index - 1].requestFocus();
                          }
                          if (_enteredOtp.length == 6) {
                            _verifyOtp();
                          }
                        },
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 32),

                // Verify Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _verifyOtp,
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
                        : const Text(
                            'Verify Code',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                const SizedBox(height: 20),

                // Resend action
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Didn't receive code? ", style: TextStyle(color: Colors.grey[700])),
                    TextButton(
                      onPressed: _resendCountdown == 0 ? _resendOtp : null,
                      child: Text(
                        _resendCountdown > 0 ? 'Resend in ${_resendCountdown}s' : 'Resend Code',
                        style: TextStyle(
                          color: _resendCountdown > 0 ? Colors.grey : _primaryGreen,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}