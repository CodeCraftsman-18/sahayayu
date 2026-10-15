import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VitalsBleService {
  static final VitalsBleService instance = VitalsBleService._internal();
  VitalsBleService._internal();

  // Bluetooth SIG Standard Heart Rate UUIDs
  static final Guid heartRateServiceUuid = Guid("0000180d-0000-1000-8000-00805f9b34fb");
  static final Guid heartRateMeasurementUuid = Guid("00002a37-0000-1000-8000-00805f9b34fb");

  BluetoothDevice? connectedDevice;
  StreamSubscription? _vitalsSubscription;

  final ValueNotifier<int> currentHeartRate = ValueNotifier<int>(0);
  final ValueNotifier<bool> isConnected = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isScanning = ValueNotifier<bool>(false);

  /// Scan for nearby BLE devices matching boAt Lunar Connect
  Stream<List<ScanResult>> scanForWatch() {
    isScanning.value = true;
    FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 12),
    );

    FlutterBluePlus.isScanning.listen((scanning) {
      isScanning.value = scanning;
    });

    return FlutterBluePlus.scanResults;
  }

  /// Connect to the boAt watch and discover GATT services
  Future<bool> connectToWatch(BluetoothDevice device) async {
    try {
      await FlutterBluePlus.stopScan();
      await device.connect(autoConnect: false, timeout: const Duration(seconds: 10));

      connectedDevice = device;
      isConnected.value = true;

      // Discover GATT Services on boAt Lunar Connect
      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid == heartRateServiceUuid) {
          for (var char in service.characteristics) {
            if (char.uuid == heartRateMeasurementUuid) {
              await _subscribeToHeartRate(char);
              return true;
            }
          }
        }
      }
      return true;
    } catch (e) {
      debugPrint('[BLE ERROR] Connection failed: $e');
      disconnect();
      return false;
    }
  }

  /// Parse standard GATT 0x2A37 Heart Rate Data Packet
  Future<void> _subscribeToHeartRate(BluetoothCharacteristic characteristic) async {
    await characteristic.setNotifyValue(true);
    _vitalsSubscription = characteristic.lastValueStream.listen((value) {
      if (value.isEmpty) return;

      int flag = value[0];
      int hr = (flag & 0x01 == 0) ? value[1] : (value[1] + (value[2] << 8));

      currentHeartRate.value = hr;
      debugPrint('[boAt WATCH] Live Heart Rate: $hr BPM');

      // Tachycardia spike trigger (>125 BPM or <45 BPM)
      if (hr > 125 || (hr < 45 && hr > 0)) {
        _logVitalsAnomalyToSupabase(hr);
      }
    });
  }

  /// Dispatch acute tachycardia/bradycardia spike to Supabase
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
      debugPrint('[SUPABASE] Wearable anomaly pushed to cloud.');
    } catch (e) {
      debugPrint('[SUPABASE BLE ERROR] $e');
    }
  }

  void disconnect() {
    _vitalsSubscription?.cancel();
    connectedDevice?.disconnect();
    connectedDevice = null;
    isConnected.value = false;
    currentHeartRate.value = 0;
  }
}