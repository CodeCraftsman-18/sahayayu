import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

const String geminiApiKey = 'YOUR_GEMINI_API_KEY';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  static const Color _primaryGreen = Color(0xFF0F765E);
  static const Color _bgColor = Color(0xFFF7F9F8);

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<_ChatMessage> _messages = [
    _ChatMessage(
      sender: Sender.ai,
      text: 'Namaste! I am your SahayAyu Health Assistant. How are you feeling today?',
    ),
  ];
  bool _isSending = false;

  static const String _systemInstruction =
      "You are SahayAyu, a calm medical companion for elderly users. Keep answers short (under 3 sentences), simple, and reassuring. Respond in the language used by the user.";
  final List<String> _models = [
    'gemini-3.6-flash',
    'gemini-3.5-flash-lite',
  ];

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage([String? prefilled]) async {
    final text = prefilled ?? _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() {
      _messages.add(_ChatMessage(sender: Sender.user, text: text));
      _isSending = true;
      if (prefilled == null) _textController.clear();
    });

    _scrollToBottom();
    String? responseText;

    // Try current active models
    for (final modelName in _models) {
      try {
        final model = GenerativeModel(
          model: modelName,
          apiKey: GEMINI_API_KEY,
          systemInstruction: Content.system(_systemInstruction),
        );

        final response = await model.generateContent([Content.text(text)]);
        responseText = response.text?.trim();

        if (responseText != null && responseText.isNotEmpty) {
          break; // Successful response
        }
      } catch (e) {
        debugPrint('Model $modelName attempt failed: $e');
      }
    }

    // Instant smart safety fallback if cloud endpoint is congested
    if (responseText == null || responseText.isEmpty) {
      responseText = _getSafetyResponse(text);
    }

    if (mounted) {
      setState(() {
        _messages.add(_ChatMessage(sender: Sender.ai, text: responseText!));
        _isSending = false;
      });
      _scrollToBottom();
    }
  }

  String _getSafetyResponse(String query) {
    final lower = query.toLowerCase();
    if (lower.contains('dizzy') || lower.contains('headache') || lower.contains('chakkar')) {
      return 'Please sit down in a well-ventilated spot and drink a glass of water slowly. If you continue to feel unwell, tap the red SOS button.';
    } else if (lower.contains('heart') || lower.contains('bpm') || lower.contains('pulse')) {
      return 'A normal resting pulse is between 60 and 100 BPM. Keep your smartband on so we can monitor your vitals.';
    } else if (lower.contains('medicine') || lower.contains('tablet') || lower.contains('dawa')) {
      return 'Please take your prescribed medicines with water after your meal as directed by your physician.';
    }
    return 'I am keeping track of your health. Please rest comfortably and press the big SOS button if you need immediate family assistance.';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'SahayAyu Assistant',
          style: TextStyle(color: _primaryGreen, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildPromptChip('Feeling dizzy'),
                _buildPromptChip('Normal heart rate?'),
                _buildPromptChip('Medication schedule'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg.sender == Sender.user;
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: isUser ? _primaryGreen : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: isUser ? null : Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      msg.text,
                      style: TextStyle(
                        fontSize: 15,
                        color: isUser ? Colors.white : Colors.black87,
                        height: 1.35,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Ask a health question...',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        filled: true,
                        fillColor: _bgColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: _isSending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _primaryGreen),
                          )
                        : const Icon(Icons.send, color: _primaryGreen),
                    onPressed: _isSending ? null : () => _sendMessage(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromptChip(String text) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ActionChip(
        label: Text(text, style: const TextStyle(fontSize: 12, color: _primaryGreen, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFE8F5E9),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: _isSending ? null : () => _sendMessage(text),
      ),
    );
  }
}

enum Sender { user, ai }

class _ChatMessage {
  final Sender sender;
  final String text;

  _ChatMessage({required this.sender, required this.text});
}