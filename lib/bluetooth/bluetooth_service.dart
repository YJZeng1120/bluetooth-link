import 'package:flutter/services.dart';
import 'ble_device.dart';

class BluetoothService {
  static const _methodChannel = MethodChannel('bluetooth/control');
  static const _eventChannel = EventChannel('bluetooth/scan');

  // ─── MethodChannel 呼叫 ────────────────────────────────────────────────────

  Future<String> getBluetoothState() async {
    final state = await _methodChannel.invokeMethod<String>('getBluetoothState');
    return state ?? 'unavailable';
  }

  Future<bool> requestPermission() async {
    final granted = await _methodChannel.invokeMethod<bool>('requestPermission');
    return granted ?? false;
  }

  Future<void> startScan() async {
    await _methodChannel.invokeMethod<void>('startScan');
  }

  Future<void> stopScan() async {
    await _methodChannel.invokeMethod<void>('stopScan');
  }

  // ─── EventChannel 串流 ────────────────────────────────────────────────────

  // Native 掃描結果串流，每筆資料為一個 BleDevice
  Stream<BleDevice> get scanResults {
    return _eventChannel.receiveBroadcastStream().map((event) {
      return BleDevice.fromMap(event as Map<dynamic, dynamic>);
    });
  }
}
