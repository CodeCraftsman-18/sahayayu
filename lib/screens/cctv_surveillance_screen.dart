import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';

class CctvSurveillanceScreen extends StatefulWidget {
  final String streamUrl;

  const CctvSurveillanceScreen({
    super.key,
    this.streamUrl = 'http://192.168.1.33:8080/video',
  });

  @override
  State<CctvSurveillanceScreen> createState() => _CctvSurveillanceScreenState();
}

class _CctvSurveillanceScreenState extends State<CctvSurveillanceScreen> {
  bool _isPlaying = true;
  late TextEditingController _urlController;
  Uint8List? _currentFrame;
  HttpClient? _client;
  StreamSubscription? _subscription;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.streamUrl);
    _startStream();
  }

  void _startStream() async {
    _stopStream();
    if (!_isPlaying) return;

    setState(() {
      _hasError = false;
      _currentFrame = null;
    });

    try {
      _client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final uri = Uri.parse(_urlController.text.trim());
      final request = await _client!.getUrl(uri);
      final response = await request.close();

      if (response.statusCode != 200) {
        if (mounted) setState(() => _hasError = true);
        return;
      }

      final List<int> buffer = [];

      _subscription = response.listen(
        (chunk) {
          buffer.addAll(chunk);

          // Find JPEG Start of Image (0xFF, 0xD8) and End of Image (0xFF, 0xD9)
          int start = -1;
          for (int i = 0; i < buffer.length - 1; i++) {
            if (buffer[i] == 0xFF && buffer[i + 1] == 0xD8) {
              start = i;
              break;
            }
          }

          if (start != -1) {
            int end = -1;
            for (int i = start; i < buffer.length - 1; i++) {
              if (buffer[i] == 0xFF && buffer[i + 1] == 0xD9) {
                end = i + 2;
                break;
              }
            }

            if (end != -1) {
              final frameData = Uint8List.fromList(buffer.sublist(start, end));
              buffer.removeRange(0, end);
              if (mounted && _isPlaying) {
                setState(() {
                  _currentFrame = frameData;
                  _hasError = false;
                });
              }
            }
          }
        },
        onError: (err) {
          if (mounted) setState(() => _hasError = true);
        },
        cancelOnError: false,
      );
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  void _stopStream() {
    _subscription?.cancel();
    _subscription = null;
    _client?.close(force: true);
    _client = null;
  }

  @override
  void dispose() {
    _stopStream();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Live Optical Sentinel Feed'),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
            color: _isPlaying ? Colors.tealAccent : Colors.orangeAccent,
            onPressed: () {
              setState(() {
                _isPlaying = !_isPlaying;
              });
              if (_isPlaying) {
                _startStream();
              } else {
                _stopStream();
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 260,
                width: double.infinity,
                color: Colors.black,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_hasError)
                      const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.videocam_off_outlined, color: Colors.redAccent, size: 48),
                            SizedBox(height: 10),
                            Text(
                              'Stream Offline or Unreachable\nVerify IP Webcam URL and Subnet',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    else if (_currentFrame != null)
                      Image.memory(
                        _currentFrame!,
                        gaplessPlayback: true,
                        fit: BoxFit.cover,
                      )
                    else
                      const Center(
                        child: CircularProgressIndicator(color: Colors.teal),
                      ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _isPlaying ? Colors.red.withOpacity(0.85) : Colors.grey,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isPlaying ? 'LIVE SENTINEL' : 'PAUSED',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Stream Endpoint',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _urlController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'http://<IP>:8080/video',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.tealAccent),
                          onPressed: () => _startStream(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Ensure your phone and camera are connected to the same Wi-Fi router subnet.',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}