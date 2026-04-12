import 'package:flutter/services.dart';
import 'ble_device.dart';

class BluetoothService {
  static const _methodChannel = MethodChannel('bluetooth/control');
  static const _eventChannel = EventChannel('bluetooth/scan');
  static const _stateChannel = EventChannel('bluetooth/state');

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

  // Native 藍牙狀態串流，推送 "on" / "off" / "unavailable"
  // Android：訂閱時立即推送當前狀態，之後每次狀態改變再推送
  // iOS：centralManagerDidUpdateState 觸發時推送
  Stream<String> get bluetoothStateStream {
    return _stateChannel.receiveBroadcastStream().map((event) => event as String);
  }
}
