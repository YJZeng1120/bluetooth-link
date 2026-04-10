import 'dart:async';
import 'package:flutter/foundation.dart';
import '../bluetooth/ble_device.dart';
import 'device_repository.dart';

class TrackedDeviceState {
  final BleDevice device;
  final bool isLost;
  final DateTime? lastSeen;

  const TrackedDeviceState({
    required this.device,
    this.isLost = false,
    this.lastSeen,
  });

  TrackedDeviceState copyWith({BleDevice? device, bool? isLost, DateTime? lastSeen}) {
    return TrackedDeviceState(
      device: device ?? this.device,
      isLost: isLost ?? this.isLost,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

class TrackingNotifier extends ChangeNotifier {
  final DeviceRepository _repo;

  TrackingNotifier(this._repo);

  final Map<String, TrackedDeviceState> _states = {};
  Timer? _lostCheckTimer;

  // Callback：當裝置被標記為 lost 時呼叫
  void Function(BleDevice device)? onDeviceLost;

  List<TrackedDeviceState> get trackedStates => _states.values.toList();

  Future<void> load() async {
    final devices = await _repo.getTrackedDevices();
    for (final d in devices) {
      _states[d.id] = TrackedDeviceState(device: d);
    }
    notifyListeners();
    _startLostCheckTimer();
  }

  Future<void> addDevice(BleDevice device) async {
    await _repo.addDevice(device);
    _states[device.id] = TrackedDeviceState(device: device);
    notifyListeners();
  }

  Future<void> removeDevice(String id) async {
    await _repo.removeDevice(id);
    _states.remove(id);
    notifyListeners();
  }

  bool isTracked(String id) => _states.containsKey(id);

  // 每次收到掃描結果，更新對應追蹤裝置的 lastSeen + rssi
  void onScanResult(BleDevice scanned) {
    if (!_states.containsKey(scanned.id)) return;
    final prev = _states[scanned.id]!;
    final wasLost = prev.isLost;
    _states[scanned.id] = prev.copyWith(
      device: prev.device.copyWith(rssi: scanned.rssi),
      isLost: false,
      lastSeen: DateTime.now(),
    );
    if (wasLost) notifyListeners(); // 恢復時通知
    notifyListeners();
  }

  // 每秒檢查是否有追蹤裝置超過 5 秒未出現
  void _startLostCheckTimer() {
    _lostCheckTimer?.cancel();
    _lostCheckTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      bool changed = false;
      for (final id in _states.keys) {
        final state = _states[id]!;
        if (state.isLost) continue;
        final lastSeen = state.lastSeen;
        if (lastSeen == null) continue;
        if (now.difference(lastSeen).inSeconds >= 5) {
          _states[id] = state.copyWith(isLost: true);
          onDeviceLost?.call(state.device);
          changed = true;
        }
      }
      if (changed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _lostCheckTimer?.cancel();
    super.dispose();
  }
}
