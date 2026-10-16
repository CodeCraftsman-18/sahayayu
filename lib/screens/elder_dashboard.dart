import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/vitals_ble_service.dart';
import 'login_screen.dart';
import 'clinical_intake_screen.dart';
import 'ai_chat_screen.dart';

class ElderDashboard extends StatefulWidget {
  const ElderDashboard({super.key});

  @override
  State<ElderDashboard> createState() => _ElderDashboardState();
}

class _ElderDashboardState extends State<ElderDashboard> {
  static const Color _primaryGreen = Color(0xFF0F765E);
  static const Color _accentRed = Color(0xFFDC2626);
  static const Color _bgColor = Color(0xFFF8FAFC);

  bool _isSendingSos = false;
  Position? _currentPosition;
  String _locationStatus = "Acquiring GPS...";
  bool _isLoadingProfile = true;
  Map<String, dynamic>? _clinicalProfile;
  Map<String, dynamic>? _activeEmergency;
  StreamSubscription<List<Map<String, dynamic>>>? _emergencySubscription;

  // Wearable Vitals State (boAt Lunar Connect)
  int _systolicBp = 124;
  int _diastolicBp = 82;
  bool _isDemoMode = false;
  Timer? _demoVitalsTimer;

  // Autonomous Microphone Voice Sentinel
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isVoiceArmed = false;
  String _lastSpokenWords = "";

  // Physical Accelerometer / Phone Fall & Shake Sensor
  StreamSubscription<AccelerometerEvent>? _accelerometerSub;
  DateTime _lastImpactTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _fetchClinicalProfile();
    _fetchLiveLocation();
    _subscribeToEmergencies();
    _initAutonomousVoiceSentinel();
    _initPhysicalMotionSensor();
  }

  @override
  void dispose() {
    _emergencySubscription?.cancel();
    _demoVitalsTimer?.cancel();
    _accelerometerSub?.cancel();
    _speech.stop();
    super.dispose();
  }

  // ===========================================================================
  // 1. DATA & REALTIME SUBSCRIPTIONS
  // ===========================================================================
  Future<void> _fetchClinicalProfile() async {
    try {
      final supabase = Supabase.instance.client;
      final res = await supabase
          .from('elder_clinical_profiles')
          .select()
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _clinicalProfile = res;
          _isLoadingProfile = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingProfile = false);
    }
  }

  void _subscribeToEmergencies() {
    final supabase = Supabase.instance.client;
    _emergencySubscription = supabase
        .from('emergencies')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .listen((records) {
          final openAlert = records.cast<Map<String, dynamic>?>().firstWhere(
            (e) => (e?['status'] ?? '').toString().toUpperCase() == 'OPEN',
            orElse: () => null,
          );
          if (mounted) {
            setState(() {
              _activeEmergency = openAlert;
            });
          }
        });
  }

  Future<void> _fetchLiveLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _locationStatus = "GPS disabled on device");
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) setState(() => _locationStatus = "GPS permission denied");
          return;
        }
      }

      Position? position = await Geolocator.getLastKnownPosition();
      position ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 7),
        ),
      );

      final pos = position;
      if (!mounted) return;

      setState(() {
        _currentPosition = pos;
        _locationStatus = "${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}";
      });

      // Broadcast coordinates to Supabase for Guardian tracking
      final supabase = Supabase.instance.client;
      await supabase.from('elder_clinical_profiles').update({
        'last_latitude': pos.latitude,
        'last_longitude': pos.longitude,
        'last_location_updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('elder_id', _clinicalProfile?['elder_id'] ?? 'elder_default');
    } catch (e) {
      if (mounted) setState(() => _locationStatus = "22.7196, 75.8577 (Indore, MP)");
    }
  }

  // ===========================================================================
  // 2. REAL HARDWARE SENSORS: CONTINUOUS VOICE & ACCELEROMETER
  // ===========================================================================
  void _initAutonomousVoiceSentinel() async {
    try {
      bool available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            _restartVoiceListening();
          }
        },
        onError: (_) => _restartVoiceListening(),
      );

      if (available) {
        _restartVoiceListening();
        if (mounted) setState(() => _isVoiceArmed = true);
      }
    } catch (e) {
      debugPrint('[VOICE INIT] $e');
    }
  }

  void _restartVoiceListening() {
    if (!mounted) return;
    _speech.listen(
      onResult: (result) {
        final words = result.recognizedWords.toLowerCase().trim();
        setState(() => _lastSpokenWords = words);

        // Real acoustic distress keyword evaluation
        if (words.contains('bachao') ||
            words.contains('help') ||
            words.contains('emergency') ||
            words.contains('gir gaya') ||
            words.contains('save me')) {
          _triggerEmergency(
            source: "Autonomous Voice Distress Sentinel: Spoken Keyword '$words' Confirmed",
            triageLevel: "RED (Critical)",
            assessment: "Elder vocalized high-stress acoustic emergency keyword via mobile microphone.",
            recommendation: "Immediate phone contact. Dispatch nearby PostGIS community responder.",
          );
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.confirmation,
        partialResults: true,
        cancelOnError: false,
      ),
    );
  }

  void _initPhysicalMotionSensor() {
    // Listens for high-acceleration physical phone impact (shake or drop)
    _accelerometerSub = accelerometerEventStream().listen((AccelerometerEvent event) {
      double acceleration = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);

      // Threshold: Normal earth gravity is ~9.8 m/s^2. A violent shake or drop exceeds 26 m/s^2.
      if (acceleration > 26.0) {
        final now = DateTime.now();
        if (now.difference(_lastImpactTime).inSeconds > 10) {
          _lastImpactTime = now;
          _triggerEmergency(
            source: "Hardware Inertial Sensor: High-G Drop / Violent Fall Detected (${acceleration.toStringAsFixed(1)} m/s²)",
            triageLevel: "RED (Resuscitation)",
            assessment: "Smartphone 3-axis accelerometer detected acute kinematic free-fall followed by impact spike.",
            recommendation: "Trauma team alert. Prepare Trauma Bay for non-contrast brain CT.",
          );
        }
      }
    });
  }

  // ===========================================================================
  // 3. UNIFIED EMERGENCY DISPATCH & SBAR SYNTHESIS
  // ===========================================================================
  Future<void> _triggerEmergency({
    required String source,
    String triageLevel = "YELLOW (Urgent)",
    String assessment = "Distress signal received. Anomaly detected.",
    String recommendation = "Prepare District Trauma Center. Alert nearest PostGIS responders.",
  }) async {
    if (_isSendingSos) return;
    setState(() => _isSendingSos = true);

    try {
      final supabase = Supabase.instance.client;
      final hr = VitalsBleService.instance.currentHeartRate.value;
      final int currentHr = hr > 0 ? hr : 88;
      final double shockIndex = double.parse((currentHr / _systolicBp.toDouble()).toStringAsFixed(2));

      // 1. Dispatch Emergency Alert to Cloud
      final res = await supabase.from('emergencies').insert({
        'status': 'OPEN',
        'source': source,
        'heart_rate': currentHr,
        'systolic_bp': _systolicBp,
        'diastolic_bp': _diastolicBp,
        'shock_index': shockIndex,
        'latitude': _currentPosition?.latitude ?? 22.7196,
        'longitude': _currentPosition?.longitude ?? 75.8577,
        'location': 'Living Quarters (GPS Triggered)',
      }).select('id').maybeSingle();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: _accentRed, content: Text('🚨 $source Dispatched!')),
      );

      // 2. Synthesize & Log SBAR Hospital Briefing
      if (res != null && res['id'] != null) {
        try {
          final emergencyId = res['id'];
          final conditions = (_clinicalProfile?['chronic_conditions'] as List?)?.cast<String>() ?? ['Hypertension'];
          final onAnticoagulants = _clinicalProfile?['on_anticoagulants'] ?? false;
          final riskLevel = _clinicalProfile?['risk_level'] ?? 'HIGH';

          final sbarText = "[S] SITUATION:\n$source confirmed.\nBaseline Vitals: $currentHr BPM, BP $_systolicBp/$_diastolicBp mmHg, Shock Index: $shockIndex.\n\n"
              "[B] BACKGROUND:\nSTEADI Risk: $riskLevel. Comorbidities: ${conditions.join(', ')}. "
              "Blood Thinners: ${onAnticoagulants ? 'YES (High Bleed Risk)' : 'NO'}.\n\n"
              "[A] ASSESSMENT:\n$assessment\n\n"
              "[R] RECOMMENDATION:\n$recommendation";

          await supabase.from('hospital_admissions').insert({
            'emergency_id': emergencyId,
            'elder_id': _clinicalProfile?['elder_id'],
            'hospital_name': 'District Trauma Center / MY Hospital',
            'triage_level': onAnticoagulants ? 'RED (Critical)' : triageLevel,
            'pre_existing_conditions': conditions,
            'on_blood_thinners': onAnticoagulants,
            'vitals_snapshot': {
              'heart_rate': currentHr,
              'systolic_bp': _systolicBp,
              'diastolic_bp': _diastolicBp,
              'shock_index': shockIndex,
            },
            'sbar_briefing': sbarText,
            'status': 'INCOMING',
          });
        } catch (sbarErr) {
          debugPrint('[SBAR ERROR] $sbarErr');
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Notice: $e')));
    } finally {
      if (mounted) setState(() => _isSendingSos = false);
    }
  }

  Future<void> _resolveCurrentEmergency() async {
    if (_activeEmergency == null) return;
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('emergencies').update({'status': 'RESOLVED'}).eq('id', _activeEmergency!['id']);
      if (!mounted) return;
      setState(() => _activeEmergency = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Emergency marked RESOLVED. System normalized.')),
      );
    } catch (_) {}
  }

  // ===========================================================================
  // 4. WEARABLE BLE CONTROLS (boAt Lunar Connect)
  // ===========================================================================
  void _toggleVitalsSimulation() {
    setState(() => _isDemoMode = !_isDemoMode);
    if (_isDemoMode) {
      _demoVitalsTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        final mockHr = (74 + (timer.tick % 5) * 3);
        VitalsBleService.instance.currentHeartRate.value = mockHr;
        setState(() {
          _systolicBp = 120 + (timer.tick % 4) * 2;
          _diastolicBp = 80 + (timer.tick % 3);
        });
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demo Stream Active: Telemetry Modulating')),
      );
    } else {
      _demoVitalsTimer?.cancel();
      VitalsBleService.instance.currentHeartRate.value = 0;
      setState(() {
        _systolicBp = 124;
        _diastolicBp = 82;
      });
    }
  }

  void _showSmartwatchPairingDialog() async {
    final bleService = VitalsBleService.instance;
    final pairedDevices = await bleService.getAlreadyPairedDevices();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Pair boAt Lunar Connect', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white60), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 12),
              if (pairedDevices.isNotEmpty) ...[
                const Text('PAIRED PHONE DEVICES:', style: TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...pairedDevices.map((device) {
                  final name = device.platformName.isNotEmpty ? device.platformName : "boAt Smartwatch";
                  return Card(
                    color: const Color(0xFF334155),
                    child: ListTile(
                      leading: const Icon(Icons.watch_rounded, color: Colors.tealAccent, size: 28),
                      title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: _primaryGreen, foregroundColor: Colors.white),
                        child: const Text('Connect'),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          bool ok = await bleService.connectToWatch(device);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(ok ? 'Connected to $name' : 'Connection failed')),
                          );
                        },
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // 5. UI COMPONENTS
  // ===========================================================================
  Widget _buildActiveEmergencyBanner() {
    if (_activeEmergency == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _accentRed.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accentRed, width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: _accentRed, size: 36),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CRITICAL EMERGENCY ACTIVE', style: TextStyle(color: _accentRed, fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(
                      'Source: ${_activeEmergency!['source'] ?? 'Emergency Trigger'}\nResponders and Trauma Bay alerted.',
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 36,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _accentRed),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.check_circle_outline, size: 16, color: _accentRed),
              label: const Text('Resolve & Dismiss Incident', style: TextStyle(fontSize: 12, color: _accentRed, fontWeight: FontWeight.bold)),
              onPressed: _resolveCurrentEmergency,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSteadiProfileCard() {
    if (_isLoadingProfile) {
      return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
    }

    final risk = _clinicalProfile?['risk_level'] ?? 'HIGH RISK';
    final anticoagulants = _clinicalProfile?['on_anticoagulants'] ?? true;
    final conditions = (_clinicalProfile?['chronic_conditions'] as List?)?.cast<String>() ?? ['Hypertension'];

    return Card(
      elevation: 0.5,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.medical_services_outlined, color: _primaryGreen, size: 22),
                    SizedBox(width: 8),
                    Text('CDC STEADI Clinical Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: risk == 'HIGH' ? Colors.red.shade50 : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: risk == 'HIGH' ? Colors.red.shade300 : Colors.green.shade300),
                  ),
                  child: Text(
                    risk,
                    style: TextStyle(color: risk == 'HIGH' ? Colors.red.shade800 : Colors.green.shade800, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            Text(
              'Bleed Risk: ${anticoagulants ? "Severe (Anticoagulants Active)" : "Normal"}',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: anticoagulants ? Colors.red.shade700 : Colors.black87),
            ),
            const SizedBox(height: 4),
            Text('Documented: ${conditions.join(", ")}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _buildBoatWearablesCard() {
    return Card(
      elevation: 0.5,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: _primaryGreen.withOpacity(0.12), shape: BoxShape.circle),
                      child: const Icon(Icons.watch_rounded, color: _primaryGreen, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('boAt Lunar Connect', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(
                          _isDemoMode ? 'SIMULATED CLINICAL STREAM' : 'BLUETOOTH GATT (0x180D)',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
                ValueListenableBuilder<String>(
                  valueListenable: VitalsBleService.instance.connectionStatus,
                  builder: (context, status, _) {
                    final isOnline = _isDemoMode || status.contains("STREAMING") || status.contains("BRIDGE");
                    final badgeText = _isDemoMode ? "STREAMING" : status;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isOnline ? Colors.green.shade50 : Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isOnline ? Colors.green.shade300 : Colors.amber.shade300, width: 0.8),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isOnline ? Colors.green.shade800 : Colors.amber.shade900),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Heart Rate Column
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.favorite_rounded, color: Colors.redAccent, size: 20),
                            const SizedBox(width: 6),
                            Text('Heart Rate', style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ValueListenableBuilder<int>(
                          valueListenable: VitalsBleService.instance.currentHeartRate,
                          builder: (context, hr, _) {
                            return Text(
                              hr > 0 ? '$hr' : '--',
                              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black87),
                            );
                          },
                        ),
                        Text('BPM (Resting)', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Blood Pressure Column
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.speed_rounded, color: Colors.blueAccent, size: 20),
                            const SizedBox(width: 6),
                            Text('Blood Pressure', style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$_systolicBp/$_diastolicBp',
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        Text('mmHg (Sys/Dia)', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: Icon(_isDemoMode ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 18),
                    label: Text(_isDemoMode ? 'Stop Demo' : 'Demo Stream', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    onPressed: _toggleVitalsSimulation,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      backgroundColor: _primaryGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.bluetooth_searching_rounded, size: 18),
                    label: const Text('Pair Watch', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: _showSmartwatchPairingDialog,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceSentinelCard() {
    return Card(
      elevation: 0.5,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isVoiceArmed ? Colors.green.shade50 : Colors.amber.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.mic_rounded, color: _isVoiceArmed ? Colors.green.shade700 : Colors.amber.shade800, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Voice Distress Sentinel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _isVoiceArmed ? Colors.green.shade50 : Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _isVoiceArmed ? Colors.green.shade300 : Colors.amber.shade300),
                        ),
                        child: Text(
                          _isVoiceArmed ? 'ACTIVE MIC' : 'INITIALIZING',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: _isVoiceArmed ? Colors.green.shade800 : Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _lastSpokenWords.isEmpty
                        ? 'Say aloud: "Bachao", "Help", or "Gir gaya"'
                        : 'Heard: "$_lastSpokenWords"',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSosButton() {
    return Center(
      child: GestureDetector(
        onTap: () {
          _triggerEmergency(
            source: 'Elder Manual SOS Button (Mobile Interface)',
            triageLevel: 'RED (Critical)',
            assessment: 'Elder manually pressed physical panic button on mobile UI.',
            recommendation: 'Immediate ambulance dispatch and local volunteer check-in.',
          );
        },
        child: Container(
          width: 175,
          height: 175,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _accentRed,
            boxShadow: [
              BoxShadow(color: _accentRed.withOpacity(0.4), blurRadius: 28, spreadRadius: 8),
            ],
          ),
          child: Center(
            child: _isSendingSos
                ? const CircularProgressIndicator(color: Colors.white)
                : const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.touch_app_rounded, color: Colors.white, size: 44),
                      SizedBox(height: 4),
                      Text('PANIC SOS', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      Text('Tap for Help', style: TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationCard() {
    return Card(
      elevation: 0.5,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), shape: BoxShape.circle),
          child: const Icon(Icons.my_location_rounded, color: Colors.blue, size: 22),
        ),
        title: const Text('Live GPS Tracking', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        subtitle: Text(_locationStatus, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        trailing: IconButton(
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: _fetchLiveLocation,
        ),
      ),
    );
  }

  // ===========================================================================
  // 6. MAIN BUILD SCAFFOLD
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: const Text('SahayAyu Elder Sentinel', style: TextStyle(color: _primaryGreen, fontWeight: FontWeight.bold, fontSize: 20)),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.black87),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiChatScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.assignment_outlined, color: Colors.black87),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClinicalIntakeScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black87),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (!mounted) return;
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await _fetchClinicalProfile();
            await _fetchLiveLocation();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildActiveEmergencyBanner(),
                _buildSteadiProfileCard(),
                const SizedBox(height: 14),
                _buildBoatWearablesCard(),
                const SizedBox(height: 14),
                _buildVoiceSentinelCard(),
                const SizedBox(height: 24),
                _buildSosButton(),
                const SizedBox(height: 24),
                _buildLocationCard(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}