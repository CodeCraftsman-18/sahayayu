import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'login_screen.dart';
import 'cctv_surveillance_screen.dart';

class GuardianDashboard extends StatefulWidget {
  const GuardianDashboard({super.key});

  @override
  State<GuardianDashboard> createState() => _GuardianDashboardState();
}

class _GuardianDashboardState extends State<GuardianDashboard> {
  static const Color _primaryGreen = Color(0xFF0F765E);
  static const Color _accentRed = Color(0xFFDC2626);
  static const Color _bgColor = Color(0xFFF8FAFC);

  Stream<List<Map<String, dynamic>>>? _emergenciesStream;
  Stream<List<Map<String, dynamic>>>? _profileStream;

  @override
  void initState() {
    super.initState();
    _initializeStreams();
  }

  void _initializeStreams() {
    final client = Supabase.instance.client;
    _emergenciesStream = client
        .from('emergencies')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);

    _profileStream = client
        .from('elder_clinical_profiles')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(1);
  }

  Future<void> _openGoogleMaps(double lat, double lon) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Do you want to log out of the Guardian portal?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _primaryGreen),
            onPressed: () async {
              Navigator.pop(ctx);
              await Supabase.instance.client.auth.signOut();
              if (!mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSendSandeshDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.favorite_rounded, color: _primaryGreen),
            SizedBox(width: 8),
            Text('Send Sandesh'),
          ],
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter wellness message for elder...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _primaryGreen),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sandesh sent to Elder device!')),
              );
            },
            child: const Text('Send', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: _primaryGreen, size: 20),
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

  Widget _buildActiveEmergencyBanner(Map<String, dynamic> activeAlert) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _accentRed.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accentRed, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: _accentRed, size: 36),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CRITICAL EMERGENCY ACTIVE',
                      style: TextStyle(
                        color: _accentRed,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Source: ${activeAlert['source'] ?? 'Alert Triggered'}\nResponders and Trauma Bay alerted.',
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLiveLocationCard() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _profileStream,
      builder: (context, snapshot) {
        double lat = 22.7196;
        double lon = 75.8577;

        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          final data = snapshot.data!.first;
          lat = (data['last_latitude'] as num?)?.toDouble() ?? 22.7196;
          lon = (data['last_longitude'] as num?)?.toDouble() ?? 75.8577;
        }

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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.my_location_rounded, color: _primaryGreen, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: () => setState(() => _initializeStreams()),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.map_rounded, size: 18),
                    label: const Text('Open in Google Maps / Navigation'),
                    onPressed: () => _openGoogleMaps(lat, lon),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCctvSentinelCard() {
    return Card(
      elevation: 0.5,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CctvSurveillanceScreen(),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _primaryGreen.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.videocam_rounded, color: _primaryGreen, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Optical CCTV Sentinel',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.green.shade300, width: 0.8),
                          ),
                          child: Text(
                            'ARMED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap to view real-time feed & room coverage',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmergencyFeedStream() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _emergenciesStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No past incidents recorded.', style: TextStyle(color: Colors.grey)),
            ),
          );
        }

        final items = snapshot.data!;
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.take(4).length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final e = items[index];
            final isOpen = (e['status'] ?? '').toString().toUpperCase() == 'OPEN';

            return Card(
              elevation: 0.5,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: ListTile(
                leading: Icon(
                  isOpen ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                  color: isOpen ? _accentRed : _primaryGreen,
                ),
                title: Text(
                  e['source'] ?? 'Alert',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                subtitle: Text(
                  'HR: ${e['heart_rate'] ?? "--"} BPM • SI: ${e['shock_index'] ?? "--"}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                trailing: Text(
                  e['status'] ?? 'OPEN',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isOpen ? _accentRed : _primaryGreen,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

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
            setState(() => _initializeStreams());
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

                _buildSectionHeader('Optical CCTV Sentinel', Icons.videocam_outlined),
                const SizedBox(height: 8),
                _buildCctvSentinelCard(),

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