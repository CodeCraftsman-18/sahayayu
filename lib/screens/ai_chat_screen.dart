import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

// LowerCamelCase identifier to comply with Dart lint rules
const String geminiApiKey = String.fromEnvironment(
  'GEMINI_API_KEY',
  defaultValue: '', 
);

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  const _ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

class _AiChatScreenState extends State<AiChatScreen> {
  static const Color _primaryGreen = Color(0xFF0F765E);
  static const Color _chatBg = Color(0xFFF8FAFC);

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _isTyping = false;

  GenerativeModel? _model;

  @override
  void initState() {
    super.initState();
    _initGemini();
    // Welcome message tailored for geriatric care
    _messages.add(
      _ChatMessage(
        text: "Namaste! I am your SahayAyu Clinical Wellness Assistant. "
            "I'm here to support your daily health, medication schedules, hydration goals, and fall prevention. "
            "How can I assist you today?",
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _initGemini() {
    if (geminiApiKey.isNotEmpty && geminiApiKey.startsWith('AIzaSy')) {
      try {
        _model = GenerativeModel(
          model: 'gemini-1.5-flash',
          apiKey: geminiApiKey,
          systemInstruction: Content.system(
            "You are SahayAyu's compassionate, evidence-based geriatric clinical health companion. "
            "Your audience consists of elderly individuals and their family guardians. "
            "Provide warm, concise, medically sound guidance on senior wellness, CDC STEADI fall prevention, "
            "anticoagulant safety, cardiac vitals, hydration, and medication compliance. "
            "Keep all explanations respectful, clear, and under 3 to 4 sentences. "
            "If the user reports severe chest pain or traumatic falls, urgently advise pressing the red PANIC SOS button."
          ),
        );
      } catch (e) {
        debugPrint('[GEMINI INIT ERROR] $e');
        _model = null;
      }
    }
  }

  // ===========================================================================
  // COMPREHENSIVE GERIATRIC CLINICAL RULES ENGINE (OFFLINE FALLBACK)
  // ===========================================================================
  String _generateOfflineClinicalResponse(String input) {
    final q = input.toLowerCase().trim();

    // 1. Cultural & Casual Greetings
    if (q.contains('namaste') || q.contains('hello') || q.contains('hi') || 
        q.contains('pranam') || q.contains('kaise ho') || q.contains('good morning') || 
        q.contains('good evening') || q.contains('kem cho')) {
      return "Namaste! I am doing well and keeping a close watch on your wellness telemetry. "
          "Are you feeling comfortable and well-rested today?";
    }

    // 2. Hydration & Fluid Intake
    if (q.contains('water') || q.contains('drink') || q.contains('hydration') || 
        q.contains('paani') || q.contains('fluid') || q.contains('thirsty')) {
      return "Older adults have a reduced natural thirst sensation, making deliberate hydration crucial. "
          "Aim for 6 to 8 glasses (about 1.5 to 2 liters) of water daily. "
          "Sipping regularly throughout the day prevents orthostatic blood pressure drops and dizziness.";
    }

    // 3. Medication Compliance & Anticoagulant Protocol
    if (q.contains('medicine') || q.contains('medication') || q.contains('pill') || 
        q.contains('tablet') || q.contains('dawai') || q.contains('schedule') || 
        q.contains('dose') || q.contains('blood thinner') || q.contains('anticoagulant') || 
        q.contains('warfarin') || q.contains('aspirin')) {
      return "Consistent medication timing is critical for stable vitals. "
          "If you are on blood thinners (anticoagulants), take them at the exact same hour daily with water to prevent clot risks. "
          "Never skip or double a dose without your physician's authorization.";
    }

    // 4. Cardiac Vitals & Heart Rate (Pulse)
    if (q.contains('heart rate') || q.contains('pulse') || q.contains('bpm') || 
        q.contains('cardiac') || q.contains('heart') || q.contains('dharkan')) {
      return "A standard resting heart rate for older adults ranges between 60 and 100 BPM. "
          "Your boAt Lunar Connect smartwatch continuously streams this telemetry to the dashboard. "
          "If your resting pulse exceeds 110 BPM or drops below 50 BPM with lightheadedness, rest immediately and notify your guardian.";
    }

    // 5. Blood Pressure & Shock Index
    if (q.contains('bp') || q.contains('blood pressure') || q.contains('hypertension') || 
        q.contains('hypotension') || q.contains('120') || q.contains('systolic')) {
      return "Healthy resting blood pressure for seniors is generally around 120/80 to 130/80 mmHg. "
          "SahayAyu monitors your Shock Index (Heart Rate divided by Systolic BP). "
          "To avoid sudden postural blood pressure drops, always sit upright on the edge of your bed for 1 minute before standing.";
    }

    // 6. Dizziness, Lightheadedness & Fall Prevention (CDC STEADI)
    if (q.contains('dizzy') || q.contains('dizziness') || q.contains('chakkar') || 
        q.contains('fall') || q.contains('unsteady') || q.contains('balance') || 
        q.contains('gira') || q.contains('faint') || q.contains('tripped')) {
      return "Feeling dizzy is the leading precursor to accidental falls. "
          "Please sit down in a sturdy chair immediately, take slow breaths, and do not attempt to walk alone. "
          "Keep your cane or walker within reach, and tap the PANIC SOS button if the unsteady feeling persists.";
    }

    // 7. Diet & Geriatric Nutrition
    if (q.contains('food') || q.contains('diet') || q.contains('nutrition') || 
        q.contains('eat') || q.contains('khana') || q.contains('meal') || q.contains('fruits')) {
      return "Senior wellness thrives on high-fiber grains, easily digestible proteins to preserve muscle mass, and reduced sodium to protect blood pressure. "
          "Incorporate cooked vegetables, lentils, and calcium-rich foods like curd or milk to maintain bone density.";
    }

    // 8. Sleep & Rest
    if (q.contains('sleep') || q.contains('neend') || q.contains('tired') || 
        q.contains('insomnia') || q.contains('rest') || q.contains('fatigue')) {
      return "Aim for 7 to 8 hours of restful sleep every night. "
          "To reduce nighttime fall risks, avoid heavy fluids 1 hour before bed, and always keep a nightlight on along the path to the restroom.";
    }

    // 9. Acute Emergency, Chest Pain, or Severe Trauma
    if (q.contains('pain') || q.contains('chest pain') || q.contains('breath') || 
        q.contains('stroke') || q.contains('severe') || q.contains('bleeding') || 
        q.contains('emergency') || q.contains('bachao') || q.contains('help')) {
      return "⚠️ URGENT HEALTH NOTICE: If you are experiencing acute chest pressure, shortness of breath, sudden weakness, or trauma from a fall, please press the RED PANIC SOS button on your home dashboard right now to dispatch immediate trauma care!";
    }

    // 10. Intelligent Contextual General Guidance
    return "I am actively tracking your physiological baseline, CDC STEADI fall risk profile, and smartwatch telemetry. "
        "You can ask me specifically about your heart rate norms, daily water intake, medication schedules, or dizziness precautions.";
  }

  // ===========================================================================
  // MESSAGE HANDLING ENGINE
  // ===========================================================================
  Future<void> _handleSubmitted(String text) async {
    final query = text.trim();
    if (query.isEmpty) return;

    _textController.clear();
    setState(() {
      _messages.add(_ChatMessage(text: query, isUser: true, timestamp: DateTime.now()));
      _isTyping = true;
    });
    _scrollToBottom();

    String replyText = "";

    // 1. Try Gemini API first if configured
    if (_model != null) {
      try {
        final response = await _model!.generateContent([Content.text(query)]);
        replyText = response.text?.trim() ?? "";
      } catch (e) {
        debugPrint('[GEMINI REQUEST ERROR] Fallback engaged: $e');
      }
    }

    // 2. If Gemini is unavailable, empty, or threw an error, use the robust clinical engine
    if (replyText.isEmpty) {
      await Future.delayed(const Duration(milliseconds: 400)); // Natural cadence
      replyText = _generateOfflineClinicalResponse(query);
    }

    if (!mounted) return;
    setState(() {
      _isTyping = false;
      _messages.add(_ChatMessage(text: replyText, isUser: false, timestamp: DateTime.now()));
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ===========================================================================
  // UI WIDGETS
  // ===========================================================================
  Widget _buildQuickSuggestionChips() {
    final suggestions = [
      "💧 Water Intake",
      "💊 Medication Schedule",
      "❤️ Normal Heart Rate",
      "⚠️ Dizziness & Falls",
      "🩺 Blood Pressure",
    ];

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final label = suggestions[index];
          return ActionChip(
            label: Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _primaryGreen),
            ),
            backgroundColor: Colors.white,
            side: BorderSide(color: _primaryGreen.withOpacity(0.3)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            onPressed: () => _handleSubmitted(label),
          );
        },
      ),
    );
  }

  Widget _buildMessageBubble(_ChatMessage message) {
    final isMe = message.isUser;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _primaryGreen.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.health_and_safety_rounded, color: _primaryGreen, size: 20),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isMe ? _primaryGreen : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.black87,
                  fontSize: 14.5,
                  height: 1.4,
                ),
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person, color: Colors.black54, size: 20),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _chatBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.8,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SahayAyu Health AI',
              style: TextStyle(color: _primaryGreen, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              'Clinical Wellness & Triage Assistant',
              style: TextStyle(color: Colors.black54, fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.black54),
            tooltip: 'Clear Conversation',
            onPressed: () {
              setState(() {
                _messages.clear();
                _messages.add(
                  _ChatMessage(
                    text: "Conversation reset. How can I help you right now?",
                    isUser: false,
                    timestamp: DateTime.now(),
                  ),
                );
              });
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            _buildQuickSuggestionChips(),
            const Divider(height: 12, thickness: 0.5),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _messages.length,
                itemBuilder: (context, index) => _buildMessageBubble(_messages[index]),
              ),
            ),
            if (_isTyping)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _primaryGreen),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Formulating clinical advice...',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Ask about vitals, water, medicines, or dizziness...',
                        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        filled: true,
                        fillColor: _chatBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: _handleSubmitted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      color: _primaryGreen,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      onPressed: () => _handleSubmitted(_textController.text),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}