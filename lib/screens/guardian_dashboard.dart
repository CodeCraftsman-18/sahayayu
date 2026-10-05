import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'login_screen.dart';

class GuardianDashboard extends StatefulWidget {
  final String? targetElderId;

  const GuardianDashboard({super.key, this.targetElderId});

  @override
  State<GuardianDashboard> createState() => _GuardianDashboardState();
}

class _GuardianDashboardState extends State<GuardianDashboard> with WidgetsBindingObserver {
  static const Color _primaryGreen = Color(0xFF0F765E);
  static const Color _sosRed = Color(0xFFD32F2F);
  static const Color _bgColor = Color(0xFFF7F9F8);

  late Stream<List<Map<String, dynamic>>> _emergenciesStream;
  late Stream<List<Map<String, dynamic>>> _locationStream;

  Timer? _reconciliationTimer;
  DateTime? _lastSuccessfulSyncUtc;
  bool _isReconciling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeStreams();
    _startReconciliationTimer();
  }

  void _initializeStreams() {
    final targetId = widget.targetElderId;

    if (targetId != null) {
      _emergenciesStream = Supabase.instance.client
          .from('emergencies')
          .stream(primaryKey: ['id'])
          .eq('elder_id', targetId)
          .order('created_at', ascending: false)
          .limit(50);

      _locationStream = Supabase.instance.client
          .from('live_locations')
          .stream(primaryKey: ['elder_id'])
          .eq('elder_id', targetId);
    } else {
      _emergenciesStream = Supabase.instance.client
          .from('emergencies')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .limit(50);

      _locationStream = Supabase.instance.client
          .from('live_locations')
          .stream(primaryKey: ['elder_id']);
    }
  }

  void _startReconciliationTimer() {
    _reconciliationTimer?.cancel();
    _reconciliationTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _reconcileOpenEmergencies();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reconcileOpenEmergencies();
    }
  }

  Future<void> _reconcileOpenEmergencies() async {
    if (_isReconciling) return;
    _isReconciling = true;
    try {
      final targetId = widget.targetElderId;
      var query = Supabase.instance.client
          .from('emergencies')
          .select()
          .eq('status', 'OPEN');

      if (targetId != null) {
        query = query.eq('elder_id', targetId);
      }

      await query.limit(1).maybeSingle();

      if (mounted) {
        setState(() {
          _lastSuccessfulSyncUtc = DateTime.now().toUtc();
        });
      }
    } catch (e) {
      debugPrint('[Reconciliation] Error verifying active emergencies: $e');
    } finally {
      _isReconciling = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reconciliationTimer?.cancel();
    super.dispose();
  }

  // --- External Actions (Maps & Phone Dialer) ---

  Future<void> _openGoogleMaps(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open map application.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Map error: $e')),
        );
      }
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final uri = Uri.parse('tel:$phoneNumber');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not launch phone dialer.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Call error: $e')),
        );
      }
    }
  }

  Future<void> _resolveEmergency(dynamic id) async {
    try {
      await Supabase.instance.client.rpc(
        'resolve_emergency',
        params: {'p_emergency_id': id.toString()},
      );
    } catch (_) {
      try {
        await Supabase.instance.client
            .from('emergencies')
            .update({'status': 'RESOLVED'})
            .eq('id', id);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Update failed: $e'), backgroundColor: Colors.red),
          );
        }
        return;
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alert marked as resolved'),
          backgroundColor: _primaryGreen,
        ),
      );
    }
  }

  // --- Send Family Sandesh Modal ---

  void _showSendSandeshDialog() {
    final textController = TextEditingController();
    String selectedPreset = '';

    final presets = [
      'Drink a glass of warm water! 💧',
      'Took your morning medicines? 💊',
      'Reaching home by 6 PM today! ❤️',
      'Rest well this afternoon. 🌸',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Send Family Sandesh',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'This note will appear prominently on the elder\'s screen.',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 14),

                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: presets.map((preset) {
                      final isSelected = selectedPreset == preset;
                      return ChoiceChip(
                        label: Text(preset, style: const TextStyle(fontSize: 12)),
                        selected: isSelected,
                        selectedColor: _primaryGreen.withOpacity(0.18),
                        onSelected: (val) {
                          setModalState(() {
                            selectedPreset = val ? preset : '';
                            if (val) textController.text = preset;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: textController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Or type custom message...',
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final msg = textController.text.trim();
                        if (msg.isEmpty) return;

                        Navigator.pop(ctx);
                        try {
                          final user = Supabase.instance.client.auth.currentUser;
                          final targetId = widget.targetElderId;

                          final payload = <String, dynamic>{
                            'sender_name': 'Family',
                            'message': msg,
                            'is_acknowledged': false,
                          };
                          if (user != null) {
                            payload['sender_id'] = user.id;
                          }
                          if (targetId != null) {
                            payload['elder_id'] = targetId;
                          }

                          await Supabase.instance.client.from('family_messages').insert(payload);

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Sandesh sent to Elder screen! ❤️'),
                                backgroundColor: _primaryGreen,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Send failed: $e'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text(
                        'Send to Senior Screen',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showLogoutDialog() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to logout from Guardian mode?'),
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
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  // --- Widget Builders ---

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: _primaryGreen),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildActiveEmergencyBanner(Map<String, dynamic> alert) {
    final source = alert['source'] ?? 'Emergency Triggered';
    final heartRate = alert['heart_rate']?.toString() ?? '--';
    final id = alert['id'];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _sosRed, width: 2),
        boxShadow: [
          BoxShadow(
            color: _sosRed.withOpacity(0.2),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: _sosRed,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ACTIVE EMERGENCY DETECTED',
                      style: TextStyle(
                        color: _sosRed,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      'Immediate response recommended',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Reason: $source',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  'BPM: $heartRate',
                  style: const TextStyle(
                    color: _sosRed,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _makePhoneCall('+919876543210'),
                  icon: const Icon(Icons.call, size: 16),
                  label: const Text('Call Senior'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _makePhoneCall('108'),
                  icon: const Icon(Icons.medical_services_outlined, size: 16),
                  label: const Text('Dial 108'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _sosRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _resolveEmergency(id),
                icon: const Icon(Icons.check_circle_outline, color: _primaryGreen, size: 28),
                tooltip: 'Mark Resolved',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLiveLocationCard() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _locationStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 110,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Center(
              child: CircularProgressIndicator(color: _primaryGreen, strokeWidth: 2),
            ),
          );
        }

        if (snapshot.hasError) {
          return _buildLocationPlaceholder(
            icon: Icons.signal_wifi_bad,
            title: 'Location Stream Disrupted',
            subtitle: 'Could not fetch live GPS telemetry.',
          );
        }

        final locations = snapshot.data ?? [];
        if (locations.isEmpty) {
          return _buildLocationPlaceholder(
            icon: Icons.location_off_outlined,
            title: 'No Active Senior Tracking',
            subtitle: 'Enable "Live Location Sharing" on the Elder app to view.',
          );
        }

        final activeLocation = locations.first;
        final bool isSharing = activeLocation['is_sharing'] ?? false;
        final double lat = (activeLocation['latitude'] as num?)?.toDouble() ?? 0.0;
        final double lng = (activeLocation['longitude'] as num?)?.toDouble() ?? 0.0;

        if (!isSharing) {
          return _buildLocationPlaceholder(
            icon: Icons.pause_circle_outline,
            title: 'Location Sharing Paused',
            subtitle: 'The elder has toggled off live location sharing.',
          );
        }

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _primaryGreen.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                color: _primaryGreen.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
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
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.my_location, color: _primaryGreen, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Elder GPS Live',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            'Real-time streaming active',
                            style: TextStyle(fontSize: 12, color: _primaryGreen, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'ONLINE',
                      style: TextStyle(color: _primaryGreen, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Coordinates: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openGoogleMaps(lat, lng),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Open in Google Maps'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLocationPlaceholder({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyFeedStream() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _emergenciesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: CircularProgressIndicator(color: _primaryGreen),
            ),
          );
        }

        if (snapshot.hasError) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _sosRed, width: 2),
            ),
            child: Column(
              children: [
                const Icon(Icons.signal_wifi_connected_no_internet_4, size: 36, color: _sosRed),
                const SizedBox(height: 8),
                const Text(
                  'Telemetry Stream Disrupted',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _sosRed),
                ),
                const SizedBox(height: 4),
                Text(
                  'Cannot verify elder status right now. Check internet connection.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                ),
              ],
            ),
          );
        }

        final emergencies = snapshot.data ?? [];
        if (emergencies.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                const Icon(Icons.check_circle_outline, color: _primaryGreen, size: 40),
                const SizedBox(height: 8),
                const Text(
                  'All Quiet & Safe',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  'No open emergency triggers at this time.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: emergencies.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final item = emergencies[index];
            final status = (item['status'] ?? 'OPEN').toString().toUpperCase();
            final isOpen = status == 'OPEN';
            final source = item['source'] ?? 'SOS Alert';
            final heartRate = item['heart_rate']?.toString() ?? '--';
            final location = item['location'] ?? 'Indore Safe Zone';
            final id = item['id'];

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isOpen ? _sosRed.withOpacity(0.3) : Colors.grey.shade200,
                  width: isOpen ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isOpen ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isOpen ? Icons.warning_rounded : Icons.task_alt,
                      color: isOpen ? _sosRed : _primaryGreen,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          source,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isOpen ? _sosRed : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Pulse: $heartRate BPM · $location',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  if (isOpen)
                    TextButton(
                      onPressed: () => _resolveEmergency(id),
                      style: TextButton.styleFrom(
                        foregroundColor: _primaryGreen,
                        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      child: const Text('Resolve'),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Resolved',
                        style: TextStyle(color: Colors.grey[600], fontSize: 11),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- Main Build ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: const Text(
          'SahayAyu Guardian',
          style: TextStyle(
            color: _primaryGreen,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black87),
            onPressed: _showLogoutDialog,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showSendSandeshDialog,
        backgroundColor: _primaryGreen,
        icon: const Icon(Icons.favorite_rounded, color: Colors.white),
        label: const Text(
          'Send Sandesh',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            _initializeStreams();
            await _reconcileOpenEmergencies();
            setState(() {});
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _emergenciesStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                      final activeAlert = snapshot.data!.cast<Map<String, dynamic>?>().firstWhere(
                        (item) => (item?['status'] ?? '').toString().toUpperCase() == 'OPEN',
                        orElse: () => null,
                      );
                      if (activeAlert != null) {
                        return _buildActiveEmergencyBanner(activeAlert);
                      }
                    }
                    return const SizedBox.shrink();
                  },
                ),

                _buildSectionHeader('Live Location Tracking', Icons.location_on_outlined),
                const SizedBox(height: 8),
                _buildLiveLocationCard(),

                const SizedBox(height: 24),

                _buildSectionHeader('Emergency & Wellness Feed', Icons.shield_outlined),
                const SizedBox(height: 8),
                _buildEmergencyFeedStream(),

                const SizedBox(height: 60),
              ],
            ),
          ),
        ),
      ),
    );
  }
}