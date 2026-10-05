import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceSosService {
  VoiceSosService._internal();
  static final VoiceSosService instance = VoiceSosService._internal();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isAvailable = false;
  bool _isListening = false;
  Function(String matchedKeyword)? _onKeywordDetected;

  // Calibrated multilingual emergency keyword dictionary
  static const List<String> _distressKeywords = [
    'bachao',
    'help',
    'madad',
    'emergency',
    'doctor',
    'sahayata',
    'chhati me dard',
    'gir gaya',
    'chot lag gayi',
  ];

  bool get isListening => _isListening;
  bool get isAvailable => _isAvailable;

  Future<bool> initialize({required Function(String) onKeywordDetected}) async {
    _onKeywordDetected = onKeywordDetected;

    try {
      _isAvailable = await _speech.initialize(
        onError: (val) => debugPrint('[Voice SOS] Speech error: $val'),
        onStatus: (status) {
          debugPrint('[Voice SOS] Status: $status');
          if (status == 'notListening' && _isListening) {
            // Keep listener alive in continuous sentinel loop
            _restartListening();
          }
        },
      );
    } catch (e) {
      debugPrint('[Voice SOS] Speech initialization failed: $e');
      _isAvailable = false;
    }

    return _isAvailable;
  }

  Future<void> startListening() async {
    if (!_isAvailable) {
      final ready = await initialize(onKeywordDetected: _onKeywordDetected ?? (_) {});
      if (!ready) return;
    }

    _isListening = true;
    _startRecognitionLoop();
  }

  void _startRecognitionLoop() {
    if (!_isListening) return;

    try {
      _speech.listen(
        onResult: (result) {
          final spokenText = result.recognizedWords.toLowerCase().trim();
          debugPrint('[Voice SOS Heard]: "$spokenText"');

          for (final keyword in _distressKeywords) {
            if (spokenText.contains(keyword)) {
              debugPrint('[Voice SOS Matched]: Trigger keyword -> $keyword');
              _speech.stop();
              _isListening = false;
              _onKeywordDetected?.call(keyword);
              break;
            }
          }
        },
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('[Voice SOS] Listen loop exception: $e');
    }
  }

  void _restartListening() {
    if (_isListening) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (_isListening) _startRecognitionLoop();
      });
    }
  }

  void stopListening() {
    _isListening = false;
    try {
      _speech.stop();
    } catch (_) {}
  }
}