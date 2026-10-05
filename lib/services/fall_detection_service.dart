import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

class FallDetectionService {
  FallDetectionService._internal();
  static final FallDetectionService instance = FallDetectionService._internal();

  StreamSubscription<AccelerometerEvent>? _accelSub;
  VoidCallback? _onFallCallback;

  bool _isListening = false;
  bool _freeFallDetected = false;
  DateTime? _freeFallTimestamp;

  // Thresholds calibrated for smartphone pocket/handheld carry
  static const double _freeFallThreshold = 4.5; // m/s^2 (~0.45g)
  static const double _impactThreshold = 25.0;  // m/s^2 (~2.55g)
  static const int _maxImpactWindowMs = 600;    // Time allowed between fall & impact
  static const int _cooldownSeconds = 15;       // Prevent re-trigger storms

  DateTime? _lastAlertTriggered;

  bool get isRunning => _isListening;

  void startListening({required VoidCallback onFallDetected}) {
    if (_isListening) return;
    _onFallCallback = onFallDetected;
    _isListening = true;

    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval, // ~20-50 Hz
    ).listen(_processAccelerometerSample);
  }

  void _processAccelerometerSample(AccelerometerEvent event) {
    // 1. Calculate Signal Vector Magnitude (SVM)
    // SVM = sqrt(ax^2 + ay^2 + az^2). At rest, SVM ≈ 9.8 m/s^2 (gravity)
    final double svm = sqrt(
      pow(event.x, 2) + pow(event.y, 2) + pow(event.z, 2),
    );

    final now = DateTime.now();

    // Check cooldown to avoid duplicate triggers
    if (_lastAlertTriggered != null &&
        now.difference(_lastAlertTriggered!).inSeconds < _cooldownSeconds) {
      return;
    }

    // 2. Stage 1: Detect Free-Fall Weightlessness
    if (svm < _freeFallThreshold) {
      _freeFallDetected = true;
      _freeFallTimestamp = now;
      return;
    }

    // 3. Stage 2: Check for Impact Spike within the valid time window
    if (_freeFallDetected && _freeFallTimestamp != null) {
      final elapsedMs = now.difference(_freeFallTimestamp!).inMilliseconds;

      if (elapsedMs > _maxImpactWindowMs) {
        // Expired window; discarded as natural swing/toss
        _freeFallDetected = false;
        _freeFallTimestamp = null;
      } else if (svm > _impactThreshold) {
        // Impact confirmed
        _freeFallDetected = false;
        _freeFallTimestamp = null;
        _lastAlertTriggered = now;

        debugPrint('[FALL DETECTED] High impact spike: ${svm.toStringAsFixed(2)} m/s^2');
        _onFallCallback?.call();
      }
    }
  }

  void stopListening() {
    _accelSub?.cancel();
    _accelSub = null;
    _isListening = false;
    _freeFallDetected = false;
  }
}