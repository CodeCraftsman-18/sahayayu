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
  static const Color _alertRed = Color(0xFFD32F2F);

  late final Stream<List<Map<String, dynamic>>> _incidentsStream;

  @override
  void initState() {
    super.initState();
    _incidentsStream = Supabase.instance.client
        .from('emergencies')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
  }

  // --- External Actions ---

  Future<void> _launchMaps(double lat, double lng) async {
    final uri = Uri.parse('geo:$lat,$lng?q=$lat,$lng(Emergency+Location)');
    final webUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open map: $e')),
        );
      }
    }
  }

  Future<void> _makeCall(String phoneNumber) async {
    final uri = Uri.parse('tel:$phoneNumber');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not dial $phoneNumber')),
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

  Future<void> _acceptIncident(String incidentId) async {
    try {
      await Supabase.instance.client
          .from('emergencies')
          .update({'status': 'RESPONDING'})
          .eq('id', incidentId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Incident Accepted! Status marked as RESPONDING.'),
            backgroundColor: _primaryGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating status: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _resolveIncident(String incidentId) async {
    try {
      await Supabase.instance.client
          .from('emergencies')
          .update({'status': 'RESOLVED'})
          .eq('id', incidentId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Emergency marked as RESOLVED.'),
            backgroundColor: _primaryGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error resolving incident: $e')),
        );
      }
    }
  }

  // --- PostGIS Spatial Responder Query ---

  Future<void> _showRankedResponders(BuildContext context, double lat, double lng) async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return FutureBuilder<List<dynamic>>(
          future: Supabase.instance.client.rpc(
            'find_ranked_responders',
            params: {
              'elder_lat': lat,
              'elder_lng': lng,
              'search_radius_meters': 3500.0,
            },
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 200,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: _primaryGreen),
                      SizedBox(height: 12),
                      Text('Querying PostGIS Spatial Index...'),
                    ],
                  ),
                ),
              );
            }

            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text('PostGIS Error: ${snapshot.error}', softWrap: true),
              );
            }

            final responders = snapshot.data ?? [];

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
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Flexible(
                        child: Text(
                          'Ranked Nearby Responders',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          softWrap: true,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${responders.length} Found',
                          style: const TextStyle(
                            color: _primaryGreen,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Spatial ranking computed via ST_Distance (PostGIS)',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 14),
                  if (responders.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('No active volunteers within 3.5 km radius.')),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: responders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (ctx, i) {
                          final r = responders[i];
                          final name = r['name'] ?? 'Responder';
                          final phone = r['phone'] ?? '';
                          final dist = r['distance_meters'] ?? 0.0;
                          final skills = (r['skills'] as List<dynamic>?)?.join(' · ') ?? 'First Aid';

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
                                  backgroundColor: _primaryGreen.withOpacity(0.12),
                                  child: Text(
                                    '${i + 1}',
                                    style: const TextStyle(color: _primaryGreen, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        softWrap: true,
                                      ),
                                      Text(
                                        skills,
                                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                        softWrap: true,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Distance: ${dist.toStringAsFixed(0)}m away',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF0284C7),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (phone.isNotEmpty)
                                  IconButton(
                                    onPressed: () => _makeCall(phone),
                                    icon: const Icon(Icons.phone, color: _primaryGreen),
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

  // --- AI Clinical Triage Synthesis Engine ---

  Widget _buildAiTriageCard(Map<String, dynamic> incident) {
    final source = (incident['source'] ?? '').toString();
    final bpm = (incident['heart_rate'] as num?)?.toInt() ?? 78;
    final sys = (incident['systolic_bp'] as num?)?.toInt() ?? 120;
    final dia = (incident['diastolic_bp'] as num?)?.toInt() ?? 80;
    final shockIndex = (incident['shock_index'] as num?)?.toDouble() ?? (bpm / sys);

    String priorityLabel = 'P2: STANDARD ALERT';
    Color badgeColor = const Color(0xFFD97706);
    List<String> clinicalPoints = [];

    if (shockIndex >= 0.9) {
      priorityLabel = 'P1: ACUTE SHOCK';
      badgeColor = _alertRed;
      clinicalPoints.add('Shock Index critical ($shockIndex >= 0.9). High suspicion of internal trauma, severe dehydration, or cardiogenic collapse.');
      clinicalPoints.add('Dispatch 108 ALS ambulance immediately. Keep patient supine with legs elevated 15° if conscious.');
    } else if (source.contains('Fall') || source.contains('Kinematic') || source.contains('CCTV')) {
      priorityLabel = 'P1: TRAUMA / IMPACT';
      badgeColor = _alertRed;
      clinicalPoints.add('Kinematic impact detected. Suspect cervical spine or orthopedic fracture. Avoid moving head or neck abruptly.');
      clinicalPoints.add('Pulse: $bpm BPM | BP: $sys/$dia mmHg. Patient on regular care schedule. Check responsiveness upon arrival.');
    } else if (bpm > 120 || sys > 150) {
      priorityLabel = 'P1: CARDIO CRISIS';
      badgeColor = _alertRed;
      clinicalPoints.add('Cardiovascular exertion detected ($bpm BPM, $sys/$dia mmHg). Elevated stroke and ischemia risk.');
      clinicalPoints.add('Ensure quiet environment, loosen tight collar, monitor consciousness every 2 minutes.');
    } else {
      clinicalPoints.add('Manual alert dispatched by senior citizen. Vitals currently stable ($bpm BPM, $sys/$dia mmHg).');
      clinicalPoints.add('Proceed to location for physical verification and reassuring wellness check.');
    }

    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: badgeColor.withOpacity(0.3), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrap replaces rigid Row to avoid overflow on narrow screens
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, color: badgeColor, size: 16),
                  const SizedBox(width: 6),
                  const Text(
                    'AI Paramedic Triage',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  priorityLabel,
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: badgeColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final point in clinicalPoints)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold)),
                  Expanded(
                    child: Text(
                      point,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF334155), height: 1.3),
                      softWrap: true,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // --- UI Card Builder ---

  Widget _buildIncidentCard(Map<String, dynamic> incident) {
    final id = incident['id'].toString();
    final status = (incident['status'] ?? 'OPEN').toString().toUpperCase();
    final source = incident['source'] ?? 'Manual SOS Button';
    final location = incident['location'] ?? 'Location Locked';
    final lat = (incident['latitude'] as num?)?.toDouble() ?? 22.7196;
    final lng = (incident['longitude'] as num?)?.toDouble() ?? 75.8577;

    final bpm = (incident['heart_rate'] as num?)?.toInt() ?? 78;
    final sys = (incident['systolic_bp'] as num?)?.toInt() ?? 120;
    final dia = (incident['diastolic_bp'] as num?)?.toInt() ?? 80;
    final shockIndex = (incident['shock_index'] as num?)?.toDouble() ?? (bpm / sys);

    final isResponding = status == 'RESPONDING';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isResponding ? const Color(0xFF0284C7) : _alertRed.withOpacity(0.5),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Status + Category
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isResponding ? const Color(0xFFE0F2FE) : const Color(0xFFFEE2E2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isResponding ? Icons.directions_run : Icons.warning_rounded,
                    color: isResponding ? const Color(0xFF0284C7) : _alertRed,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              isResponding ? 'RESPONDER EN ROUTE' : 'CRITICAL SOS ALERT',
                              style: TextStyle(
                                color: isResponding ? const Color(0xFF0284C7) : _alertRed,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                letterSpacing: 0.5,
                              ),
                              softWrap: true,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isResponding ? const Color(0xFFE0F2FE) : const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(
                                color: isResponding ? const Color(0xFF0284C7) : _alertRed,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        source,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        softWrap: true, // Wraps longer sentences across multiple lines cleanly
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Location Bar with multi-line wrapping for long addresses
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Color(0xFF475569), size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'GPS: $location',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF334155), fontWeight: FontWeight.w500),
                      softWrap: true,
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => _launchMaps(lat, lng),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.map, size: 13, color: Color(0xFF0284C7)),
                          SizedBox(width: 4),
                          Text('Map', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0284C7))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Horizontally Sliding & Bounded Hemodynamic Biometrics Strip
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Pulse Section
                    Row(
                      children: [
                        Icon(Icons.favorite, size: 15, color: bpm > 110 ? _alertRed : _primaryGreen),
                        const SizedBox(width: 6),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$bpm BPM',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: bpm > 110 ? _alertRed : Colors.black87,
                              ),
                            ),
                            const Text('Pulse Rate', style: TextStyle(fontSize: 9, color: Colors.grey)),
                          ],
                        ),
                      ],
                    ),

                    Container(margin: const EdgeInsets.symmetric(horizontal: 14), height: 26, width: 1, color: Colors.grey.shade300),

                    // BP Section
                    Row(
                      children: [
                        const Icon(Icons.speed_rounded, size: 15, color: Color(0xFF0284C7)),
                        const SizedBox(width: 6),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$sys/$dia',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: (sys > 140 || sys < 90) ? _alertRed : Colors.black87,
                              ),
                            ),
                            const Text('BP (mmHg)', style: TextStyle(fontSize: 9, color: Colors.grey)),
                          ],
                        ),
                      ],
                    ),

                    Container(margin: const EdgeInsets.symmetric(horizontal: 14), height: 26, width: 1, color: Colors.grey.shade300),

                    // Shock Index Section
                    Row(
                      children: [
                        Icon(Icons.monitor_heart, size: 15, color: shockIndex >= 0.9 ? _alertRed : _primaryGreen),
                        const SizedBox(width: 6),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shockIndex.toStringAsFixed(2),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: shockIndex >= 0.9 ? _alertRed : _primaryGreen,
                              ),
                            ),
                            Text(
                              shockIndex >= 0.9 ? 'CRITICAL SHOCK' : 'Shock Idx (Nominal)',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: shockIndex >= 0.9 ? _alertRed : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // AI Paramedic Briefing
            _buildAiTriageCard(incident),

            const SizedBox(height: 10),

            // Flexible Multi-Line / Responsive Action Buttons (Wrap prevents button overflow)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 64) / 2,
                  child: OutlinedButton.icon(
                    onPressed: () => _showRankedResponders(context, lat, lng),
                    icon: const Icon(Icons.people_alt_outlined, size: 15),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Responders', style: TextStyle(fontSize: 12)),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 64) / 2,
                  child: !isResponding
                      ? ElevatedButton.icon(
                          onPressed: () => _acceptIncident(id),
                          icon: const Icon(Icons.check_circle, size: 15),
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Accept & Assist', style: TextStyle(fontSize: 12)),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        )
                      : ElevatedButton.icon(
                          onPressed: () => _resolveIncident(id),
                          icon: const Icon(Icons.done_all, size: 15),
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Mark Resolved', style: TextStyle(fontSize: 12)),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0284C7),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                ),
              ],
            ),

            const SizedBox(height: 4),

            // Emergency Call 108
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => _makeCall('108'),
                icon: const Icon(Icons.phone_in_talk, size: 15, color: _alertRed),
                label: const Text(
                  'Dial 108 Ambulance Dispatch',
                  style: TextStyle(color: _alertRed, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'SahayAyu Responder Feed',
          style: TextStyle(color: _primaryGreen, fontWeight: FontWeight.bold, fontSize: 19),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black87),
            onPressed: _logout,
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _incidentsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _primaryGreen));
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Feed Disrupted: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
            );
          }

          final all = snapshot.data ?? [];
          final active = all.where((i) {
            final st = (i['status'] ?? '').toString().toUpperCase();
            return st == 'OPEN' || st == 'RESPONDING';
          }).toList();

          if (active.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async => setState(() {}),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: const BoxDecoration(
                            color: Color(0xFFE8F5E9),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.shield_outlined, size: 54, color: _primaryGreen),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No Active Emergencies',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Neighborhood sector is secure.\nStandby for incident broadcasts.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            itemCount: active.length,
            itemBuilder: (context, index) => _buildIncidentCard(active[index]),
          );
        },
      ),
    );
  }
}