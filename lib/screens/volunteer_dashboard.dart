import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'login_screen.dart';

class VolunteerDashboard extends StatefulWidget {
  const VolunteerDashboard({super.key});

  @override
  State<VolunteerDashboard> createState() => _VolunteerDashboardState();
}

class _VolunteerDashboardState extends State<VolunteerDashboard> {
  static const Color _primaryGreen = Color(0xFF0F765E);
  static const Color _accentRed = Color(0xFFDC2626);
  static const Color _bgColor = Color(0xFFF8FAFC);

  Stream<List<Map<String, dynamic>>>? _emergenciesStream;

  @override
  void initState() {
    super.initState();
    _initEmergenciesStream();
  }

  void _initEmergenciesStream() {
    _emergenciesStream = Supabase.instance.client
        .from('emergencies')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
  }

  Future<List<dynamic>> _fetchRankedResponders(double lat, double lng) async {
    try {
      final res = await Supabase.instance.client.rpc(
        'find_ranked_responders',
        params: {
          'elder_lat': lat,
          'elder_lng': lng,
          'search_radius_meters': 5000.0,
        },
      );
      return res as List<dynamic>;
    } catch (e) {
      debugPrint('[POSTGIS RPC ERROR] $e');
      return [];
    }
  }

  void _showRankedRespondersModal(BuildContext context, double lat, double lng) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return FutureBuilder<List<dynamic>>(
          future: _fetchRankedResponders(lat, lng),
          builder: (context, snapshot) {
            final responders = snapshot.data ?? [];
            final count = responders.length;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Ranked Nearby Responders',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: Text(
                          '$count Found',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Spatial ranking computed via ST_Distance (PostGIS)',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),

                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: CircularProgressIndicator(color: _primaryGreen),
                      ),
                    )
                  else if (responders.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      alignment: Alignment.center,
                      child: const Text(
                        'No community volunteers found within 5 km.',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.55,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: responders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final r = responders[index];
                          final distance = (r['distance_meters'] as num?)?.toDouble() ?? 0.0;
                          final distanceStr = distance < 1000
                              ? '${distance.toStringAsFixed(0)} m'
                              : '${(distance / 1000).toStringAsFixed(1)} km';

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: _primaryGreen.withOpacity(0.12),
                                  child: Text(
                                    '#${index + 1}',
                                    style: const TextStyle(
                                      color: _primaryGreen,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        r['name'] ?? 'Responder',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        r['skills'] ?? 'CPR, First Aid',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.near_me_rounded, size: 12, color: _primaryGreen),
                                      const SizedBox(width: 4),
                                      Text(
                                        distanceStr,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: _primaryGreen,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
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

  Future<void> _dialAmbulance() async {
    final uri = Uri.parse('tel:108');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openExternalMap(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _acceptEmergency(int id) async {
    try {
      await Supabase.instance.client
          .from('emergencies')
          .update({'status': 'ACKNOWLEDGED'})
          .eq('id', id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: _primaryGreen,
          content: Text('Emergency Accepted! Navigating to elder location.'),
        ),
      );
    } catch (e) {
      debugPrint('[ACCEPT ERROR] $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: const Text(
          'SahayAyu Responder Feed',
          style: TextStyle(
            color: _primaryGreen,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black87),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (!mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _emergenciesStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                'No active emergency alerts at this time.',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            );
          }

          final alerts = snapshot.data!;
          final activeAlert = alerts.firstWhere(
            (item) => (item['status'] ?? '').toString().toUpperCase() == 'OPEN',
            orElse: () => alerts.first,
          );

          final double lat = (activeAlert['latitude'] as num?)?.toDouble() ?? 22.7196;
          final double lng = (activeAlert['longitude'] as num?)?.toDouble() ?? 75.8577;
          final int alertId = (activeAlert['id'] as num?)?.toInt() ?? 0;
          final String status = activeAlert['status'] ?? 'OPEN';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Action Card
                Card(
                  elevation: 0.5,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.red.shade100),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide(color: Colors.grey.shade400),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(Icons.people_outline, color: Colors.black87),
                            label: const Text(
                              'Responders',
                              style: TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: () => _showRankedRespondersModal(context, lat, lng),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              backgroundColor: _primaryGreen,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text(
                              'Accept & Assist',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () => _acceptEmergency(alertId),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton.icon(
                          icon: const Icon(Icons.phone, color: _accentRed, size: 18),
                          label: const Text(
                            'Dial 108 Ambulance Dispatch',
                            style: TextStyle(
                              color: _accentRed,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: _dialAmbulance,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Critical Alert Details Card
                Card(
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
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: _accentRed, size: 28),
                            const SizedBox(width: 8),
                            const Text(
                              'CRITICAL SOS ALERT',
                              style: TextStyle(
                                color: _accentRed,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: status == 'OPEN' ? Colors.red.shade50 : Colors.green.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: status == 'OPEN' ? Colors.red.shade300 : Colors.green.shade300,
                                ),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: status == 'OPEN' ? Colors.red.shade800 : Colors.green.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          activeAlert['source'] ?? 'Emergency Trigger',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 16, color: Colors.black54),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'GPS: ${activeAlert['location'] ?? "$lat, $lng"}',
                                style: const TextStyle(fontSize: 12, color: Colors.black87),
                              ),
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(Icons.map_outlined, size: 14),
                              label: const Text('Map', style: TextStyle(fontSize: 12)),
                              onPressed: () => _openExternalMap(lat, lng),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}