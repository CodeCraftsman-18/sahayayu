import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VitalsBleService {
  static final VitalsBleService instance = VitalsBleService._internal();
  VitalsBleService._internal();

  // Standard Bluetooth SIG UUIDs
  static final Guid heartRateServiceUuid = Guid("0000180d-0000-1000-8000-00805f9b34fb");
  static final Guid heartRateMeasurementUuid = Guid("00002a37-0000-1000-8000-00805f9b34fb");

  BluetoothDevice? connectedDevice;
  StreamSubscription? _vitalsSubscription;

  final ValueNotifier<int> currentHeartRate = ValueNotifier<int>(0);
  final ValueNotifier<bool> isConnected = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isReceivingData = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isScanning = ValueNotifier<bool>(false);
  
  final ValueNotifier<String> connectionStatus = ValueNotifier<String>("OFFLINE");

  Stream<List<ScanResult>> scanForWatch() {
    isScanning.value = true;
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));

    FlutterBluePlus.isScanning.listen((scanning) {
      isScanning.value = scanning;
    });

    return FlutterBluePlus.scanResults;
  }

  Future<bool> connectToWatch(BluetoothDevice device) async {
    try {
      await FlutterBluePlus.stopScan();
      connectionStatus.value = "CONNECTING...";
      await device.connect(autoConnect: false, timeout: const Duration(seconds: 10));

      connectedDevice = device;
      isConnected.value = true;
      connectionStatus.value = "PAIRED (READING SERVICES)";

      List<BluetoothService> services = await device.discoverServices();
      debugPrint('=== [boAt GATT SERVICES DISCOVERED] ===');
      for (var s in services) {
        debugPrint('Service UUID: ${s.uuid}');
        for (var c in s.characteristics) {
          debugPrint('   Characteristic: ${c.uuid} (Properties: ${c.properties})');
        }
      }

      bool foundStandardHr = false;
      for (var service in services) {
        if (service.uuid == heartRateServiceUuid) {
          for (var char in service.characteristics) {
            if (char.uuid == heartRateMeasurementUuid) {
              foundStandardHr = true;
              await _subscribeToHeartRate(char);
              connectionStatus.value = "STREAMING (0x180D)";
              return true;
            }
          }
        }
      }

      if (!foundStandardHr) {
        debugPrint('[BLE WARNING] boAt watch does not expose open standard GATT 0x180D.');
        connectionStatus.value = "LOCKED VENDOR GATT";
      }

      return true;
    } catch (e) {
      debugPrint('[BLE ERROR] Connection failed: $e');
      disconnect();
      return false;
    }
  }

  Future<void> _subscribeToHeartRate(BluetoothCharacteristic characteristic) async {
    await characteristic.setNotifyValue(true);
    _vitalsSubscription = characteristic.lastValueStream.listen((value) {
      if (value.isEmpty) return;

      int flag = value[0];
      int hr = (flag & 0x01 == 0) ? value[1] : (value[1] + (value[2] << 8));

      if (hr > 0) {
        currentHeartRate.value = hr;
        isReceivingData.value = true;
        connectionStatus.value = "STREAMING";
        debugPrint('[boAt WATCH] Live Heart Rate: $hr BPM');

        if (hr > 125 || (hr < 45 && hr > 0)) {
          _logVitalsAnomalyToSupabase(hr);
        }
      }
    });
  }

  Future<void> _logVitalsAnomalyToSupabase(int hr) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('emergencies').insert({
        'status': 'OPEN',
        'source': 'boAt Lunar Connect Wearable: Tachycardia Spike ($hr BPM)',
        'heart_rate': hr,
        'systolic_bp': 130,
        'diastolic_bp': 85,
        'shock_index': double.parse((hr / 130.0).toStringAsFixed(2)),
        'location': 'Living Room (Wearable Telemetry Stream)',
      });
    } catch (e) {
      debugPrint('[SUPABASE BLE ERROR] $e');
    }
  }

  void disconnect() {
    _vitalsSubscription?.cancel();
    connectedDevice?.disconnect();
    connectedDevice = null;
    isConnected.value = false;
    isReceivingData.value = false;
    currentHeartRate.value = 0;
    connectionStatus.value = "OFFLINE";
  }
}