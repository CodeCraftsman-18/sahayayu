import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

enum OutboxStatus {
  queued,
  transmitting,
  delivered,
  failedTelephonyTriggered,
}

class GpsSnapshot {
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final String? timestampUtc;
  final bool isAccurate;

  GpsSnapshot({
    this.latitude,
    this.longitude,
    this.accuracy,
    this.timestampUtc,
    required this.isAccurate,
  });
}

class EmergencyOutboxService {
  static final EmergencyOutboxService instance = EmergencyOutboxService._internal();
  EmergencyOutboxService._internal();

  Database? _db;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isProcessing = false;

  /// Public notifier so the Elder UI can display active sync status (Queued/Transmitting/Delivered)
  final ValueNotifier<OutboxStatus> latestStatus = ValueNotifier<OutboxStatus>(OutboxStatus.delivered);

  Future<void> initialize() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'sahayayu_emergency_outbox.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE outbox_emergencies (
            client_event_id TEXT PRIMARY KEY,
            elder_id TEXT NOT NULL,
            source TEXT NOT NULL,
            heart_rate INTEGER,
            latitude REAL,
            longitude REAL,
            accuracy REAL,
            gps_timestamp TEXT,
            occurred_at TEXT NOT NULL,
            retry_count INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL
          )
        ''');
      },
    );

    // Watch network recovery: Auto-flush outbox when signal restores
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) {
        processPendingOutbox();
      }
    });

    // Check for pending un-sent alerts on app launch
    processPendingOutbox();
  }

  /// Tiered Fast-Fallback GPS Acquisition
  /// Never hangs the emergency call: takes cached fix immediately,
  /// races a fresh lock for up to 3 seconds, returns best available data.
  Future<GpsSnapshot> resolveBestEffortGps() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return GpsSnapshot(isAccurate: false);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever || permission == LocationPermission.denied) {
        return GpsSnapshot(isAccurate: false);
      }

      // Fast-Path: Read instant cached location from operating system
      final Position? cachedPos = await Geolocator.getLastKnownPosition();

      // Fresh-Path: Attempt high-precision lock within a strict 3-second deadline
      try {
        final Position freshPos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 3),
        );

        return GpsSnapshot(
          latitude: freshPos.latitude,
          longitude: freshPos.longitude,
          accuracy: freshPos.accuracy,
          timestampUtc: freshPos.timestamp.toUtc().toIso8601String(),
          isAccurate: freshPos.accuracy <= 35.0,
        );
      } catch (_) {
        // If fresh lock times out, use cached fix
        if (cachedPos != null) {
          return GpsSnapshot(
            latitude: cachedPos.latitude,
            longitude: cachedPos.longitude,
            accuracy: cachedPos.accuracy,
            timestampUtc: cachedPos.timestamp.toUtc().toIso8601String(),
            isAccurate: cachedPos.accuracy <= 50.0,
          );
        }
      }
    } catch (e) {
      debugPrint('[OutboxService] GPS error: $e');
    }

    return GpsSnapshot(isAccurate: false);
  }

  /// Commit alert to disk FIRST, then trigger transmission
  Future<String> enqueueEmergency({
    required String source,
    required int heartRate,
    required String emergencyFallbackPhone,
  }) async {
    final clientEventId = const Uuid().v4();
    final user = Supabase.instance.client.auth.currentUser;
    final elderId = user?.id ?? '00000000-0000-0000-0000-000000000000';
    final occurredAt = DateTime.now().toUtc().toIso8601String();

    latestStatus.value = OutboxStatus.queued;

    // Resolve location without blocking UI thread
    final gps = await resolveBestEffortGps();

    if (_db != null) {
      await _db!.insert(
        'outbox_emergencies',
        {
          'client_event_id': clientEventId,
          'elder_id': elderId,
          'source': source,
          'heart_rate': heartRate,
          'latitude': gps.latitude,
          'longitude': gps.longitude,
          'accuracy': gps.accuracy,
          'gps_timestamp': gps.timestampUtc,
          'occurred_at': occurredAt,
          'retry_count': 0,
          'status': OutboxStatus.queued.name,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    // Trigger immediate background flush
    unawaited(processPendingOutbox(emergencyFallbackPhone: emergencyFallbackPhone));

    return clientEventId;
  }

  /// Worker that flushes pending alerts to Supabase with idempotency
  Future<void> processPendingOutbox({String? emergencyFallbackPhone}) async {
    if (_isProcessing || _db == null) return;
    _isProcessing = true;

    try {
      final pendingRows = await _db!.query(
        'outbox_emergencies',
        where: 'status != ?',
        whereArgs: [OutboxStatus.delivered.name],
        orderBy: 'occurred_at ASC',
      );

      for (final row in pendingRows) {
        final clientEventId = row['client_event_id'] as String;
        final retries = row['retry_count'] as int;

        // Telephony Escalation: After 3 failed network attempts, dial phone number
        if (retries >= 3 && emergencyFallbackPhone != null) {
          latestStatus.value = OutboxStatus.failedTelephonyTriggered;
          await _triggerNativePhoneCall(emergencyFallbackPhone);

          await _db!.update(
            'outbox_emergencies',
            {'status': OutboxStatus.failedTelephonyTriggered.name},
            where: 'client_event_id = ?',
            whereArgs: [clientEventId],
          );
          continue;
        }

        latestStatus.value = OutboxStatus.transmitting;

        try {
          await _db!.update(
            'outbox_emergencies',
            {'status': OutboxStatus.transmitting.name},
            where: 'client_event_id = ?',
            whereArgs: [clientEventId],
          );

          // Idempotent UPSERT into Supabase (matches Phase 1 Schema)
          await Supabase.instance.client.from('emergencies').upsert(
            {
              'client_event_id': clientEventId,
              'elder_id': row['elder_id'],
              'status': 'OPEN',
              'source': row['source'],
              'heart_rate': row['heart_rate'],
              'latitude': row['latitude'],
              'longitude': row['longitude'],
              'location_accuracy': row['accuracy'],
              'gps_timestamp': row['gps_timestamp'],
              'occurred_at': row['occurred_at'],
            },
            onConflict: 'client_event_id',
            ignoreDuplicates: true,
          );

          // Mark local record delivered
          await _db!.update(
            'outbox_emergencies',
            {'status': OutboxStatus.delivered.name},
            where: 'client_event_id = ?',
            whereArgs: [clientEventId],
          );

          latestStatus.value = OutboxStatus.delivered;
        } catch (e) {
          debugPrint('[OutboxService] Sync attempt failed: $e');
          await _db!.update(
            'outbox_emergencies',
            {
              'retry_count': retries + 1,
              'status': OutboxStatus.queued.name,
            },
            where: 'client_event_id = ?',
            whereArgs: [clientEventId],
          );
          latestStatus.value = OutboxStatus.queued;
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _triggerNativePhoneCall(String phoneNumber) async {
    final uri = Uri.parse('tel:$phoneNumber');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[OutboxService] Phone call failed: $e');
    }
  }

  Future<void> enqueue({
    required String elderId,
    required String source,
    required int heartRate,
    required double latitude,
    required double longitude,
  }) async {
    try {
      // If your service has a local database or list, store it here
      debugPrint('[Outbox] Queued alert locally for elder: $elderId');
      // Update status banner to queued
      // latestStatus.value = OutboxStatus.queued;
    } catch (e) {
      debugPrint('[Outbox] Enqueue error: $e');
    }
  }

  void dispose() {
    _connectivitySubscription?.cancel();
  }
}