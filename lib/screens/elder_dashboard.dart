import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'login_screen.dart';
import 'ai_chat_screen.dart';
import '../services/fall_detection_service.dart';
import '../services/voice_sos_service.dart';

// --- Top-Level Model ---
class MedicationItem {
  final String id;
  final String name;
  final String purpose;
  final String timing;
  final Color pillColor;
  final bool isCapsule;
  bool isTaken;

  MedicationItem({
    required this.id,
    required this.name,
    required this.purpose,
    required this.timing,
    required this.pillColor,
    required this.isCapsule,
    this.isTaken = false,
  });
}

class ElderDashboard extends StatefulWidget {
  const ElderDashboard({super.key});

  @override
  State<ElderDashboard> createState() => _ElderDashboardState();
}

class _ElderDashboardState extends State<ElderDashboard> {
  static const Color _primaryGreen = Color(0xFF0F765E);
  static const Color _sosRed = Color(0xFFD32F2F);

  int _bpm = 76;

  int _systolicBp = 120;
  int _diastolicBp = 80;

  // Shock Index: Heart Rate / Systolic BP (Normal: 0.5 - 0.7; Critical: >= 0.9)
  double get _shockIndex => _systolicBp > 0 ? _bpm / _systolicBp : 0.63;

  bool _isMonitoring = true;
  Timer? _timer;
  Timer? _sosCountdownTimer;
  int _sosCountdown = 10;
  bool _isVoiceSentinelActive = false;

  int _fallCountdown = 30;
  Timer? _fallTimer;

  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isLiveLocationEnabled = false;

  final double _homeLat = 22.7196;
  final double _homeLng = 75.8577;
  final double _safeRadiusMeters = 150.0;
  bool _geofenceBreached = false;

  final List<MedicationItem> _dailyMedications = [
    MedicationItem(
      id: 'med_1',
      name: 'EcoSprin',
      purpose: 'Heart & Blood Flow',
      timing: 'Morning · After Breakfast',
      pillColor: const Color(0xFFE53935),
      isCapsule: false,
    ),
    MedicationItem(
      id: 'med_2',
      name: 'Metformin',
      purpose: 'Sugar Balance',
      timing: 'Afternoon · With Lunch',
      pillColor: const Color(0xFF1E88E5),
      isCapsule: true,
    ),
    MedicationItem(
      id: 'med_3',
      name: 'Atorva',
      purpose: 'Cholesterol Care',
      timing: 'Night · Before Sleep',
      pillColor: const Color(0xFFFDD835),
      isCapsule: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startMonitoring();
      _initFallDetection();
      _initVoiceSentinel();
    });
  }
  
  void _initVoiceSentinel() async {
    final available = await VoiceSosService.instance.initialize(
      onKeywordDetected: (keyword) {
        if (!mounted) return;
        _showSosTriageDialog(
          source: 'Voice Distress Detected ("${keyword.toUpperCase()}")',
        );
      },
    );
    if (available && mounted) {
      await VoiceSosService.instance.startListening();
      setState(() => _isVoiceSentinelActive = true);
    }
  }

  void _initFallDetection() {
    FallDetectionService.instance.startListening(
      onFallDetected: () {
        if (!mounted) return;
        _showFallVerificationDialog();
      },
    );
  }

  @override
  void dispose() {
    VoiceSosService.instance.stopListening();
    FallDetectionService.instance.stopListening();
    _timer?.cancel();
    _sosCountdownTimer?.cancel();
    _fallTimer?.cancel();
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  // --- Dynamic Ambient Greetings ---
  String get _ambientGreeting {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Good morning';
    if (hour >= 12 && hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _ambientSubtitle {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Ready for a pleasant, active day?';
    if (hour >= 12 && hour < 17) return 'Stay refreshed and hydrated';
    return 'Relax and wind down comfortably';
  }

  IconData get _ambientIcon {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return Icons.wb_sunny_rounded;
    if (hour >= 12 && hour < 17) return Icons.wb_cloudy_rounded;
    return Icons.nights_stay_rounded;
  }

  Color get _ambientAccent {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return const Color(0xFFD97706);
    if (hour >= 12 && hour < 17) return const Color(0xFF0F765E);
    return const Color(0xFF475569);
  }

  Color get _ambientBackground {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return const Color(0xFFFDF8F3);
    if (hour >= 12 && hour < 17) return const Color(0xFFF5F9F7);
    return const Color(0xFFF1F5F9);
  }

  Future<void> _makeDirectCall(String phoneNumber, String contactName) async {
    final uri = Uri.parse('tel:$phoneNumber');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not call $contactName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dialer error: $e')),
        );
      }
    }
  }

  bool _isCheckingGeofence = false;

  void _startMonitoring() {
    _timer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      if (!_isMonitoring) return;

      final rand = Random();
      final newBpm = 72 + rand.nextInt(16);
      final newSys = 118 + rand.nextInt(6); // 118-124 mmHg
      final newDia = 78 + rand.nextInt(5); // 78-83 mmHg
      if (mounted) {
        setState(() {
          _bpm = newBpm;
          _systolicBp = newSys;
          _diastolicBp = newDia;
        });
      }
      

      if (_isCheckingGeofence) return;
      _isCheckingGeofence = true;

      try {
        Position? pos = await Geolocator.getLastKnownPosition();
        pos ??= await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 3),
        );

        double distance = Geolocator.distanceBetween(
          _homeLat,
          _homeLng,
          pos.latitude,
          pos.longitude,
        );

        if (distance > _safeRadiusMeters && !_geofenceBreached) {
          _geofenceBreached = true;
          _triggerSos(
            source: 'Geofence Breach (Wandering)',
            location: '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}',
          );
        } else if (distance <= _safeRadiusMeters) {
          _geofenceBreached = false;
        }
      } catch (_) {
      } finally {
        _isCheckingGeofence = false;
      }
    });
  }

  Future<void> _toggleLiveLocationSharing(bool enable) async {
    setState(() => _isLiveLocationEnabled = enable);

    await _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    if (enable) {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enable GPS hardware on device.')),
          );
        }
        setState(() => _isLiveLocationEnabled = false);
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _isLiveLocationEnabled = false);
          return;
        }
      }

      try {
        Position? initialPos = await Geolocator.getLastKnownPosition();
        initialPos ??= await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 3),
        );

        await Supabase.instance.client.from('live_locations').upsert({
          'elder_id': user.id,
          'latitude': initialPos.latitude,
          'longitude': initialPos.longitude,
          'accuracy': initialPos.accuracy,
          'is_sharing': true,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      } catch (e) {
        debugPrint('[GPS] Immediate sync error: $e');
      }

      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen(
        (Position position) async {
          try {
            await Supabase.instance.client.from('live_locations').upsert({
              'elder_id': user.id,
              'latitude': position.latitude,
              'longitude': position.longitude,
              'accuracy': position.accuracy,
              'is_sharing': true,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            });
          } catch (e) {
            debugPrint('[GPS-Stream] Sync error: $e');
          }
        },
        onError: (err) => debugPrint('[GPS-Stream] Hardware error: $err'),
      );
    } else {
      try {
        await Supabase.instance.client.from('live_locations').update({
          'is_sharing': false,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('elder_id', user.id);
      } catch (e) {
        debugPrint('[GPS] Disable error: $e');
      }
    }
  }

  void _toggleMedication(MedicationItem med) {
    setState(() => med.isTaken = !med.isTaken);

    if (med.isTaken) {
      Supabase.instance.client.from('emergencies').insert({
        'status': 'RESOLVED',
        'location': 'Home Routine',
        'heart_rate': _bpm,
        'source': 'Medicine Taken: ${med.name} (${med.purpose})',
      }).catchError((_) {});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Marked ${med.name} as taken.'),
          backgroundColor: _primaryGreen,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showMedicationSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final remainingCount = _dailyMedications.where((m) => !m.isTaken).length;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Daily Medicines',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: remainingCount == 0 ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          remainingCount == 0 ? 'All Taken' : '$remainingCount Pending',
                          style: TextStyle(
                            color: remainingCount == 0 ? _primaryGreen : const Color(0xFFE65100),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _dailyMedications.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final med = _dailyMedications[index];
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: med.isTaken ? const Color(0xFFF9FAFB) : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: med.isTaken ? Colors.grey.shade300 : _primaryGreen.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: med.pillColor.withOpacity(0.18),
                                  shape: med.isCapsule ? BoxShape.rectangle : BoxShape.circle,
                                  borderRadius: med.isCapsule ? BorderRadius.circular(14) : null,
                                  border: Border.all(color: med.pillColor, width: 2),
                                ),
                                child: Icon(
                                  med.isCapsule ? Icons.medication_liquid : Icons.circle,
                                  color: med.pillColor,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      med.name,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        decoration: med.isTaken ? TextDecoration.lineThrough : null,
                                        color: med.isTaken ? Colors.grey : Colors.black87,
                                      ),
                                    ),
                                    Text(
                                      '${med.purpose} · ${med.timing}',
                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  _toggleMedication(med);
                                  setModalState(() {});
                                },
                                icon: Icon(
                                  med.isTaken ? Icons.check_circle : Icons.radio_button_unchecked,
                                  color: med.isTaken ? _primaryGreen : Colors.grey,
                                  size: 28,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showSosTriageDialog({required String source}) {
    _sosCountdown = 10;
    _sosCountdownTimer?.cancel();

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            _sosCountdownTimer ??= Timer.periodic(const Duration(seconds: 1), (timer) {
              if (_sosCountdown > 1) {
                setModalState(() => _sosCountdown--);
              } else {
                timer.cancel();
                _sosCountdownTimer = null;
                Navigator.pop(sheetContext);
                _triggerSos(source: source);
              }
            });

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Icon(Icons.warning_amber_rounded, size: 48, color: Colors.orange),
                  const SizedBox(height: 12),
                  Text(
                    'Alerting Caregivers in $_sosCountdown s',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Reason: $source',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            _sosCountdownTimer?.cancel();
                            _sosCountdownTimer = null;
                            Navigator.pop(sheetContext);
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text("I'm Okay (Cancel)", style: TextStyle(fontSize: 15)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            _sosCountdownTimer?.cancel();
                            _sosCountdownTimer = null;
                            Navigator.pop(sheetContext);
                            _triggerSos(source: source);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _sosRed,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Send Now', style: TextStyle(color: Colors.white, fontSize: 15)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      _sosCountdownTimer?.cancel();
      _sosCountdownTimer = null;
    });
  }

  void _showFallVerificationDialog() {
    if (_fallTimer != null) return;
    _fallCountdown = 30;

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            _fallTimer ??= Timer.periodic(const Duration(seconds: 1), (t) {
              if (_fallCountdown > 1) {
                setModalState(() => _fallCountdown--);
              } else {
                t.cancel();
                _fallTimer = null;
                Navigator.of(sheetContext, rootNavigator: true).pop();
                _triggerSos(source: 'Autonomous Fall Detection (Kinematic Sensor)');
              }
            });

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFEE2E2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.personal_injury_rounded,
                      size: 48,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Potential Fall Detected!',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF991B1B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Responders will be notified in $_fallCountdown seconds if you do not cancel.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            _fallTimer?.cancel();
                            _fallTimer = null;
                            Navigator.of(sheetContext, rootNavigator: true).pop();
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: Colors.grey),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            "I'm Fine (Cancel)",
                            style: TextStyle(fontSize: 15, color: Colors.black87),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            _fallTimer?.cancel();
                            _fallTimer = null;
                            Navigator.of(sheetContext, rootNavigator: true).pop();
                            _triggerSos(source: 'Elder Confirmed Fall Alert');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Send Help Now',
                            style: TextStyle(color: Colors.white, fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      _fallTimer?.cancel();
      _fallTimer = null;
    });
  }

  Future<void> _triggerSos({
    String source = 'Manual SOS Button',
    String? location,
  }) async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Transmitting SOS to Responders...'),
            ],
          ),
          backgroundColor: Colors.black87,
          duration: Duration(seconds: 2),
        ),
      );
    }

    final user = Supabase.instance.client.auth.currentUser;
    final String? elderId = user?.id;

    double lat = _homeLat;
    double lng = _homeLng;

    try {
      Position? pos = await Geolocator.getLastKnownPosition();
      pos ??= await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 2),
      );
      if (pos != null) {
        lat = pos.latitude;
        lng = pos.longitude;
      }
    } catch (geoError) {
      debugPrint('[GPS Warning] Fallback coordinates used: $geoError');
    }

    final String resolvedLocation =
        location ?? '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';

    try {
      final payload = {
        if (elderId != null) 'elder_id': elderId,
        'status': 'OPEN',
        'source': source,
        'heart_rate': _bpm,
        'systolic_bp': _systolicBp,
        'diastolic_bp': _diastolicBp,
        'shock_index': double.parse(_shockIndex.toStringAsFixed(2)),
        'latitude': lat,
        'longitude': lng,
        'location': resolvedLocation,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      final response = await Supabase.instance.client
          .from('emergencies')
          .insert(payload)
          .select();

      debugPrint('[SOS SUCCESS] Inserted row: $response');

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('🚨 SOS Alert Live! Sent to Responders'),
              ],
            ),
            backgroundColor: Color(0xFFD32F2F),
            duration: Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (dbError) {
      debugPrint('[SOS DB Warning] Insert failed: $dbError');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('SOS transmission note: $dbError'),
            backgroundColor: const Color(0xFFD97706),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _simulateCriticalBiometrics() {
    setState(() {
      _bpm = 132;
      _systolicBp = 160;
      _diastolicBp = 100;
    });
    _showSosTriageDialog(
      source: 'Hemodynamic Anomaly: Tachycardia (132 BPM) & Hypertension (160/100 mmHg)',
    );
  }

  Future<void> _showLogoutDialog() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to logout from SahayAyu?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout == true && mounted) {
      await Supabase.instance.client.auth.signOut();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Widget _buildAmbientCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _ambientAccent.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: _ambientAccent.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _ambientAccent.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(_ambientIcon, color: _ambientAccent, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _ambientGreeting,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(_ambientSubtitle, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFamilySandeshStream() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('family_messages')
          .stream(primaryKey: ['id'])
          .eq('is_acknowledged', false)
          .order('created_at', ascending: false)
          .limit(1),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final msgData = snapshot.data!.first;
        final sender = msgData['sender_name'] ?? 'Family';
        final message = msgData['message'] ?? '';
        final id = msgData['id'];

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFFDBA74), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEA580C).withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.favorite, color: Color(0xFFEA580C), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Sandesh from $sender',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF9A3412),
                        ),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await Supabase.instance.client
                          .from('family_messages')
                          .update({'is_acknowledged': true}).eq('id', id);
                    },
                    icon: const Icon(Icons.check, size: 16, color: Color(0xFF0F765E)),
                    label: const Text(
                      'Received ❤️',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F765E)),
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                message,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87, height: 1.3),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLocationSharingTile() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.share_location, color: _isLiveLocationEnabled ? _primaryGreen : Colors.grey),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Live Location Sharing', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(
                    _isLiveLocationEnabled ? 'Family can view live map' : 'Sharing is off',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ],
          ),
          Switch(
            value: _isLiveLocationEnabled,
            activeColor: _primaryGreen,
            onChanged: _toggleLiveLocationSharing,
          ),
        ],
      ),
    );
  }

  Widget _buildMedicationSummaryTile() {
    final pending = _dailyMedications.where((m) => !m.isTaken).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF3E8FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.medication_rounded, color: Color(0xFF7E22CE), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Daily Medicines', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text(
                  pending == 0 ? 'All doses taken for today' : '$pending pending · Tap to check off',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _showMedicationSheet,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF7E22CE),
              textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            child: const Text('View All'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickSpeedDialSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _makeDirectCall('+919876543210', 'Family'),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _primaryGreen.withOpacity(0.3)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(color: Color(0xFFE8F5E9), shape: BoxShape.circle),
                      child: const Icon(Icons.phone_in_talk, color: _primaryGreen, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Call Family', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('Tap to dial', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: () => _makeDirectCall('+919123456789', 'Doctor'),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(color: Color(0xFFE3F2FD), shape: BoxShape.circle),
                      child: const Icon(Icons.medical_services_outlined, color: Colors.blue, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Call Doctor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('Dr. Sharma', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceSentinelTile() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _isVoiceSentinelActive ? const Color(0xFFF0FDF4) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isVoiceSentinelActive
              ? const Color(0xFF86EFAC)
              : Colors.grey.shade200,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _isVoiceSentinelActive
                      ? const Color(0xFFDCFCE7)
                      : Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isVoiceSentinelActive ? Icons.mic : Icons.mic_off,
                  color: _isVoiceSentinelActive ? _primaryGreen : Colors.grey,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Voice Sentinel Active',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  Text(
                    _isVoiceSentinelActive
                        ? 'Listening for "Bachao", "Help", "Madad"'
                        : 'Voice trigger paused',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ],
          ),
          Switch(
            value: _isVoiceSentinelActive,
            activeColor: _primaryGreen,
            onChanged: (val) async {
              setState(() => _isVoiceSentinelActive = val);
              if (val) {
                await VoiceSosService.instance.startListening();
              } else {
                VoiceSosService.instance.stopListening();
              }
            },
          ),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ambientBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: const Text(
          'SahayAyu Senior Care',
          style: TextStyle(color: _primaryGreen, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black87),
            onPressed: _showLogoutDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
          child: Column(
            children: [
              _buildAmbientCard(),
              const SizedBox(height: 12),

              _buildFamilySandeshStream(),
              _buildVoiceSentinelTile(),
              _buildLocationSharingTile(),
              _buildMedicationSummaryTile(),
              _buildQuickSpeedDialSection(),

              // Dual Biometrics Card (Pulse + Blood Pressure + Shock Index)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _shockIndex >= 0.9 ? _sosRed : Colors.grey.shade200,
                    width: _shockIndex >= 0.9 ? 1.5 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Left Column: Heart Rate
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _bpm > 110
                                    ? const Color(0xFFFEE2E2)
                                    : const Color(0xFFE8F5E9),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.favorite,
                                color: _bpm > 110 ? _sosRed : _primaryGreen,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$_bpm BPM',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: _bpm > 110 ? _sosRed : Colors.black87,
                                  ),
                                ),
                                Text(
                                  _bpm > 110 ? 'Elevated Pulse' : 'Resting Pulse',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        // Vertical Divider
                        Container(height: 40, width: 1, color: Colors.grey.shade200),

                        // Right Column: Blood Pressure
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: (_systolicBp > 140 || _systolicBp < 90)
                                    ? const Color(0xFFFEE2E2)
                                    : const Color(0xFFE0F2FE),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.speed_rounded,
                                color: (_systolicBp > 140 || _systolicBp < 90)
                                    ? _sosRed
                                    : const Color(0xFF0284C7),
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$_systolicBp/$_diastolicBp',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: (_systolicBp > 140 || _systolicBp < 90)
                                        ? _sosRed
                                        : Colors.black87,
                                  ),
                                ),
                                const Text(
                                  'Blood Pressure (mmHg)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 10),

                    // Bottom Row: Band Connection + Shock Index Badge
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.bluetooth_connected, size: 16, color: _primaryGreen),
                            const SizedBox(width: 6),
                            const Text(
                              'Smart Band Connected',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _primaryGreen),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _shockIndex >= 0.9 ? const Color(0xFFFEE2E2) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Shock Index: ${_shockIndex.toStringAsFixed(2)} (${_shockIndex >= 0.9 ? "CRITICAL" : "NORMAL"})',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _shockIndex >= 0.9 ? _sosRed : const Color(0xFF475569),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // SOS Button
              GestureDetector(
                onTap: () => _showSosTriageDialog(source: 'Manual SOS Pressed'),
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _sosRed,
                    boxShadow: [
                      BoxShadow(
                        color: _sosRed.withOpacity(0.32),
                        blurRadius: 26,
                        spreadRadius: 6,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.touch_app, size: 44, color: Colors.white),
                        SizedBox(height: 6),
                        Text(
                          'HELP / SOS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        Text('Tap for emergency', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // AI Health Assistant Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AiChatScreen()),
                    );
                  },
                  icon: const Icon(Icons.chat_bubble_outline, size: 20),
                  label: const Text(
                    'Ask SahayAyu Health Assistant',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Fall Simulation Button
              TextButton.icon(
                onPressed: _showFallVerificationDialog,
                icon: const Icon(Icons.personal_injury, size: 16, color: Colors.orange),
                label: const Text(
                  'Demo: Simulate Kinematic Fall Detection',
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),

              // Voice SOS Simulator
              TextButton.icon(
                onPressed: () => _showSosTriageDialog(
                  source: 'Voice Distress Detected ("BACHAO")',
                ),
                icon: const Icon(Icons.record_voice_over, size: 16, color: Colors.purple),
                label: const Text(
                  'Demo: Simulate Voice Distress ("Bachao")',
                  style: TextStyle(color: Colors.purple, fontSize: 12),
                ),
              ),

              // Critical Biometrics Simulator
              TextButton.icon(
                onPressed: _simulateCriticalBiometrics,
                icon: const Icon(
                  Icons.science_outlined,
                  size: 16,
                  color: Colors.blueGrey,
                ),
                label: const Text(
                  'Demo: Simulate Critical Pulse & BP Spike (132 BPM, 160/100 mmHg)',
                  style: TextStyle(color: Colors.blueGrey, fontSize: 12),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}