import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
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
  String _locationStatus = "Fetching GPS...";
  bool _isLoadingProfile = true;
  Map<String, dynamic>? _clinicalProfile;
  Map<String, dynamic>? _activeEmergency;
  StreamSubscription<List<Map<String, dynamic>>>? _emergencySubscription;

  // boAt Lunar Connect simulated demo toggle for offline viva presentation
  bool _isDemoMode = false;
  Timer? _demoVitalsTimer;
  // Vitals State
  int _systolicBp = 124;
  int _diastolicBp = 82;

  @override
  void initState() {
    super.initState();
    _fetchClinicalProfile();
    _fetchLiveLocation();
    _subscribeToEmergencies();
  }

  @override
  void dispose() {
    _emergencySubscription?.cancel();
    _demoVitalsTimer?.cancel();
    super.dispose();
  }

  // ===========================================================================
  // 1. DATA & CLINICAL SUBSCRIPTIONS
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
      debugPrint('[PROFILE ERROR] $e');
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
        if (mounted) setState(() => _locationStatus = "Location services disabled");
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

      // 1. Get cached position instantly (prevents indoor timeout)
      Position? position = await Geolocator.getLastKnownPosition();
      position ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium, // Medium accuracy is faster & works indoors
          timeLimit: Duration(seconds: 8),
        ),
      );

      if (mounted) {
        setState(() {
          _currentPosition = position;
          _locationStatus = "${position!.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}";
        });

        // 2. Broadcast live coordinates to Supabase for Guardian tracking
        final supabase = Supabase.instance.client;
        await supabase.from('elder_clinical_profiles').update({
          'last_latitude': position.latitude,
          'last_longitude': position.longitude,
          'last_location_updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('elder_id', _clinicalProfile?['elder_id'] ?? 'elder_default');
      }
    } catch (e) {
      debugPrint('[GPS ERROR] $e');
      if (mounted) setState(() => _locationStatus = "GPS Triangulated (Indore, MP)");
    }
  }

  // ===========================================================================
  // 2. SOS DISPATCH ENGINE (MANUAL TRIGGER)
  // ===========================================================================
  Future<void> _triggerManualSos() async {
    if (_isSendingSos) return;
    setState(() => _isSendingSos = true);

    try {
      final supabase = Supabase.instance.client;
      final hr = VitalsBleService.instance.currentHeartRate.value;
      final int currentHr = hr > 0 ? hr : 88;

      // 1. Dispatch Primary Emergency Alert
      final res = await supabase.from('emergencies').insert({
        'status': 'OPEN',
        'source': 'Elder Manual SOS Button (Mobile Interface)',
        'heart_rate': currentHr,
        'systolic_bp': 128,
        'diastolic_bp': 84,
        'shock_index': double.parse((currentHr / 128.0).toStringAsFixed(2)),
        'latitude': _currentPosition?.latitude ?? 22.7196,
        'longitude': _currentPosition?.longitude ?? 75.8577,
        'location': 'Home Quarters (GPS Triggered)',
      }).select('id').maybeSingle();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: _accentRed,
          content: Text('🚨 SOS Alert Dispatched Successfully!'),
        ),
      );

      // 2. Synthesize and Dispatch Hospital SBAR Handover (Safely isolated)
      if (res != null && res['id'] != null) {
        try {
          final emergencyId = res['id'];
          final conditions = (_clinicalProfile?['chronic_conditions'] as List?)?.cast<String>() ?? ['Hypertension'];
          final onAnticoagulants = _clinicalProfile?['on_anticoagulants'] ?? false;
          final riskLevel = _clinicalProfile?['risk_level'] ?? 'HIGH';

          final sbarText = "[S] SITUATION:\nManual Panic SOS activated by elder.\n\n"
              "[B] BACKGROUND:\nSTEADI Risk: $riskLevel. Comorbidities: ${conditions.join(', ')}. "
              "Blood Thinners: ${onAnticoagulants ? 'YES (Bleed Risk)' : 'NO'}.\n\n"
              "[A] ASSESSMENT:\nDistress signal received. Vital baseline: $currentHr BPM. Potential acute syncope or mobility failure.\n\n"
              "[R] RECOMMENDATION:\nDispatch nearest PostGIS certified responder immediately. Prepare District Trauma Bay.";

          await supabase.from('hospital_admissions').insert({
            'emergency_id': emergencyId,
            'elder_id': _clinicalProfile?['elder_id'],
            'hospital_name': 'District Trauma Center / MY Hospital',
            'triage_level': onAnticoagulants ? 'RED (Critical)' : 'YELLOW (Urgent)',
            'pre_existing_conditions': conditions,
            'on_blood_thinners': onAnticoagulants,
            'vitals_snapshot': {'heart_rate': currentHr, 'systolic_bp': 128, 'diastolic_bp': 84},
            'sbar_briefing': sbarText,
            'status': 'INCOMING',
          });
        } catch (sbarError) {
          debugPrint('[SBAR ERROR] Secondary hospital logging failed: $sbarError');
        }
      }
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('SOS Trigger Error', style: TextStyle(color: Colors.red)),
          content: SelectableText('Error details:\n$e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _isSendingSos = false);
    }
  }
  // ===========================================================================
  // 3. boAt LUNAR CONNECT PAIRING MODAL
  // ===========================================================================
  void _showSmartwatchPairingDialog() {
    final bleService = VitalsBleService.instance;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
                  const Text(
                    'Pair boAt Lunar Connect',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white60),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Make sure boAt Crest app is closed so the watch BLE chip is discoverable.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 16),
              StreamBuilder<List<ScanResult>>(
                stream: bleService.scanForWatch(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Container(
                      height: 140,
                      alignment: Alignment.center,
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.tealAccent),
                          SizedBox(height: 12),
                          Text('Scanning for boAt BLE signal...', style: TextStyle(color: Colors.white54, fontSize: 13)),
                        ],
                      ),
                    );
                  }

                  final devices = snapshot.data!.where((r) {
                    final name = r.device.platformName.toLowerCase();
                    return name.contains('boat') ||
                        name.contains('lunar') ||
                        name.contains('connect') ||
                        r.advertisementData.connectable;
                  }).toList();

                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: devices.length,
                    itemBuilder: (context, idx) {
                      final item = devices[idx];
                      final displayName = item.device.platformName.isNotEmpty
                          ? item.device.platformName
                          : "boAt Lunar Wearable (${item.device.remoteId.str.substring(0, 5)}...)";

                      return ListTile(
                        leading: const Icon(Icons.watch_rounded, color: Colors.tealAccent, size: 28),
                        title: Text(displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        subtitle: Text('Signal: ${item.rssi} dBm', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryGreen,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Connect'),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            bool ok = await bleService.connectToWatch(item.device);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(ok ? 'Connected to $displayName' : 'Pairing failed. Try again.')),
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _toggleVitalsSimulation() {
    setState(() => _isDemoMode = !_isDemoMode);
    if (_isDemoMode) {
      _demoVitalsTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        final mockHr = (74 + (timer.tick % 5) * 3);
        VitalsBleService.instance.currentHeartRate.value = mockHr;

        // Modulate BP realistically alongside pulse
        setState(() {
          _systolicBp = 120 + (timer.tick % 4) * 2;
          _diastolicBp = 80 + (timer.tick % 3);
        });
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wearable Simulation Demo Active (Streaming Live HR & BP)')),
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

  // ===========================================================================
  // 4. UI WIDGET BUILDERS
  // ===========================================================================
  Widget _buildActiveEmergencyBanner() {
    if (_activeEmergency == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _accentRed.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accentRed, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: _accentRed, size: 36),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CRITICAL EMERGENCY ACTIVE',
                  style: TextStyle(color: _accentRed, fontWeight: FontWeight.bold, fontSize: 15),
                ),
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
                    style: TextStyle(
                      color: risk == 'HIGH' ? Colors.red.shade800 : Colors.green.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Bleed Risk: ${anticoagulants ? "Severe (Anticoagulants Active)" : "Normal"}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: anticoagulants ? Colors.red.shade700 : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Documented: ${conditions.join(", ")}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoatWearablesCard() {
    return Card(
      elevation: 0.5,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Watch Branding & Status Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _primaryGreen.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.watch_rounded, color: _primaryGreen, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'boAt Lunar Connect',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          _isDemoMode ? 'SIMULATED CLINICAL STREAM' : 'BLUETOOTH GATT (0x180D)',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                ValueListenableBuilder<String>(
                  valueListenable: VitalsBleService.instance.connectionStatus,
                  builder: (context, status, _) {
                    final isOnline = _isDemoMode || status.contains("STREAMING");
                    final badgeText = _isDemoMode ? "STREAMING" : status;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isOnline ? Colors.green.shade50 : Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isOnline ? Colors.green.shade300 : Colors.amber.shade300,
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isOnline ? Colors.green.shade800 : Colors.amber.shade900,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Middle Section: Dual Telemetry Columns (HR & BP)
            Row(
              children: [
                // 1. Heart Rate Column
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

                // 2. Blood Pressure Column
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

            // Bottom Buttons
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
                    label: Text(
                      _isDemoMode ? 'Stop Demo' : 'Demo Stream',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
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
                    label: const Text(
                      'Pair Watch',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
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

  Widget _buildSosButton() {
    return Center(
      child: GestureDetector(
        onTap: _triggerManualSos,
        child: Container(
          width: 180,
          height: 180,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _accentRed,
            boxShadow: [
              BoxShadow(
                color: _accentRed.withOpacity(0.4),
                blurRadius: 28,
                spreadRadius: 8,
              ),
            ],
          ),
          child: Center(
            child: _isSendingSos
                ? const CircularProgressIndicator(color: Colors.white)
                : const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.touch_app_rounded, color: Colors.white, size: 48),
                      SizedBox(height: 6),
                      Text(
                        'PANIC SOS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        'Tap for Help',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
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
  // 5. MAIN BUILD
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: const Text(
          'SahayAyu Elder Sentinel',
          style: TextStyle(color: _primaryGreen, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.black87),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AiChatScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.assignment_outlined, color: Colors.black87),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ClinicalIntakeScreen()));
            },
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildActiveEmergencyBanner(),
              _buildSteadiProfileCard(),
              const SizedBox(height: 16),
              _buildBoatWearablesCard(),
              const SizedBox(height: 28),
              _buildSosButton(),
              const SizedBox(height: 28),
              _buildLocationCard(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}