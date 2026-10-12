import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'elder_dashboard.dart';

class ClinicalIntakeScreen extends StatefulWidget {
  final bool isInitialOnboarding;

  const ClinicalIntakeScreen({
    super.key,
    this.isInitialOnboarding = true,
  });

  @override
  State<ClinicalIntakeScreen> createState() => _ClinicalIntakeScreenState();
}

class _ClinicalIntakeScreenState extends State<ClinicalIntakeScreen> {
  static const Color _primaryGreen = Color(0xFF0F765E);
  static const Color _alertRed = Color(0xFFD32F2F);
  static const Color _warningOrange = Color(0xFFD97706);

  bool _isSubmitting = false;

  // --- STEADI Clinical Intake State ---
  bool _priorFalls = false;
  String _mobilityAid = 'None';
  bool _onAnticoagulants = false;
  bool _frequentDizziness = false;

  final Map<String, bool> _chronicConditions = {
    'Hypertension': false,
    'Type 2 Diabetes': false,
    'Parkinson\'s Disease': false,
    'Cardiac Arrhythmia / CAD': false,
    'Osteoporosis': false,
    'Arthritis / Joint Pain': false,
  };

  final List<String> _mobilityOptions = [
    'None',
    'Walking Cane',
    'Walker / Rollator',
    'Wheelchair',
  ];

  // --- CDC STEADI Weighted Risk Scoring Algorithm ---
  int get _calculatedScore {
    int score = 0;

    // 1. Prior mechanical fall in past 6 months (Key STEADI predictor)
    if (_priorFalls) score += 3;

    // 2. Mobility assistance device
    switch (_mobilityAid) {
      case 'Walker / Rollator':
        score += 3;
        break;
      case 'Walking Cane':
      case 'Wheelchair':
        score += 2;
        break;
      default:
        break;
    }

    // 3. Postural instability / orthostatic dizziness
    if (_frequentDizziness) score += 2;

    // 4. Anticoagulants (Significantly elevates trauma & subdural hemorrhage risk)
    if (_onAnticoagulants) score += 2;

    // 5. Chronic comorbidities (1 point each)
    final selectedConditions = _chronicConditions.values.where((v) => v).length;
    score += selectedConditions;

    return score;
  }

  String get _riskLevel {
    final score = _calculatedScore;
    if (score >= 7 || (_priorFalls && _mobilityAid != 'None')) {
      return 'HIGH';
    } else if (score >= 4) {
      return 'MODERATE';
    } else {
      return 'LOW';
    }
  }

  Color get _riskColor {
    switch (_riskLevel) {
      case 'HIGH':
        return _alertRed;
      case 'MODERATE':
        return _warningOrange;
      default:
        return _primaryGreen;
    }
  }

  // --- Save Profile to Supabase ---
  Future<void> _saveClinicalProfile() async {
    setState(() => _isSubmitting = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      final selectedConditionsList = _chronicConditions.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList();

      final payload = {
        if (user != null) 'elder_id': user.id,
        'prior_falls_6m': _priorFalls,
        'mobility_aid': _mobilityAid,
        'on_anticoagulants': _onAnticoagulants,
        'frequent_dizziness': _frequentDizziness,
        'chronic_conditions': selectedConditionsList,
        'fall_risk_score': _calculatedScore,
        'risk_level': _riskLevel,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      await Supabase.instance.client
          .from('elder_clinical_profiles')
          .insert(payload);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile saved: Risk categorized as $_riskLevel'),
            backgroundColor: _riskColor,
          ),
        );

        if (widget.isInitialOnboarding) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const ElderDashboard()),
          );
        } else {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving clinical profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Clinical Intake & Risk Profile',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Card: CDC STEADI Context
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _primaryGreen.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.medical_information_outlined, color: _primaryGreen, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CDC STEADI Assessment',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _primaryGreen),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Calibrates sensor triggers and pre-populates paramedic SBAR summaries.',
                          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Question 1: Prior Falls
            _buildSectionCard(
              title: '1. Fall History (Past 6 Months)',
              subtitle: 'Have you slipped, stumbled, or fallen in the last 6 months?',
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _priorFalls ? 'Yes, experienced a fall recently' : 'No recent falls',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _priorFalls ? _alertRed : Colors.black87,
                  ),
                ),
                value: _priorFalls,
                activeColor: _alertRed,
                onChanged: (val) => setState(() => _priorFalls = val),
              ),
            ),

            const SizedBox(height: 14),

            // Question 2: Mobility Aid
            _buildSectionCard(
              title: '2. Mobility Assistance',
              subtitle: 'What walking support do you usually use?',
              child: Column(
                children: _mobilityOptions.map((opt) {
                  return RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(opt, style: const TextStyle(fontWeight: FontWeight.w500)),
                    value: opt,
                    groupValue: _mobilityAid,
                    activeColor: _primaryGreen,
                    onChanged: (val) {
                      if (val != null) setState(() => _mobilityAid = val);
                    },
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 14),

            // Question 3: Anticoagulants (Blood Thinners)
            _buildSectionCard(
              title: '3. High-Risk Medications',
              subtitle: 'Do you take blood thinners (e.g., Aspirin, Warfarin, Ecosprin)?',
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _onAnticoagulants
                      ? 'Yes (Alerts paramedics of internal bleed risk)'
                      : 'No blood thinners',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _onAnticoagulants ? _alertRed : Colors.black87,
                  ),
                ),
                value: _onAnticoagulants,
                activeColor: _alertRed,
                onChanged: (val) => setState(() => _onAnticoagulants = val),
              ),
            ),

            const SizedBox(height: 14),

            // Question 4: Orthostatic Dizziness
            _buildSectionCard(
              title: '4. Balance & Dizziness',
              subtitle: 'Do you feel dizzy, uncoordinated, or lightheaded when standing up?',
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _frequentDizziness ? 'Yes, frequently feel lightheaded' : 'No balance issues',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _frequentDizziness ? _warningOrange : Colors.black87,
                  ),
                ),
                value: _frequentDizziness,
                activeColor: _warningOrange,
                onChanged: (val) => setState(() => _frequentDizziness = val),
              ),
            ),

            const SizedBox(height: 14),

            // Question 5: Chronic Conditions
            _buildSectionCard(
              title: '5. Pre-Existing Conditions',
              subtitle: 'Select any conditions diagnosed by your physician:',
              child: Column(
                children: _chronicConditions.keys.map((condition) {
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(condition, style: const TextStyle(fontWeight: FontWeight.w500)),
                    value: _chronicConditions[condition],
                    activeColor: _primaryGreen,
                    onChanged: (val) {
                      setState(() => _chronicConditions[condition] = val ?? false);
                    },
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 18),

            // Live Risk Stratification Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _riskColor, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: _riskColor.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'STEADI Risk Stratification',
                        style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$_riskLevel RISK (Score: $_calculatedScore)',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _riskColor),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _riskColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _riskLevel == 'HIGH' ? 'Critical Care' : (_riskLevel == 'MODERATE' ? 'Monitored' : 'Standard'),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _riskColor),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _saveClinicalProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Text(
                        'Save Clinical Profile & Enter App',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const Divider(height: 18),
          child,
        ],
      ),
    );
  }
}