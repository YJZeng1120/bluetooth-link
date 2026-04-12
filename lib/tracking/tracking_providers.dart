import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bluetooth/ble_device.dart';
import 'device_repository.dart';

// ── Data model ────────────────────────────────────────────────────────────────

class TrackedDeviceState {
  final BleDevice device;
  final bool isLost;
  final DateTime? lastSeen;
  final int? previousRssi;

  const TrackedDeviceState({
    required this.device,
    this.isLost = false,
    this.lastSeen,
    this.previousRssi,
  });

  TrackedDeviceState copyWith({
    BleDevice? device,
    bool? isLost,
    DateTime? lastSeen,
    int? previousRssi,
  }) =>
      TrackedDeviceState(
        device: device ?? this.device,
        isLost: isLost ?? this.isLost,
        lastSeen: lastSeen ?? this.lastSeen,
        previousRssi: previousRssi ?? this.previousRssi,
      );
}

// ── Providers ─────────────────────────────────────────────────────────────────

final deviceRepositoryProvider = Provider<DeviceRepository>(
  (ref) => DeviceRepository(),
);

class TrackingNotifier extends Notifier<List<TrackedDeviceState>> {
  final Map<String, TrackedDeviceState> _states = {};
  Timer? _lostCheckTimer;

  @override
  List<TrackedDeviceState> build() {
    ref.onDispose(() => _lostCheckTimer?.cancel());
    _load();
    _startLostCheckTimer();
    return const [];
  }

  Future<void> _load() async {
    final devices = await ref.read(deviceRepositoryProvider).getTrackedDevices();
    for (final d in devices) {
      _states[d.id] = TrackedDeviceState(device: d);
    }
    state = _states.values.toList();
  }

  Future<void> addDevice(BleDevice device) async {
    await ref.read(deviceRepositoryProvider).addDevice(device);
    _states[device.id] = TrackedDeviceState(device: device);
    state = _states.values.toList();
  }

  Future<void> removeDevice(String id) async {
    await ref.read(deviceRepositoryProvider).removeDevice(id);
    _states.remove(id);
    state = _states.values.toList();
  }

  void onScanResult(BleDevice scanned) {
    if (!_states.containsKey(scanned.id)) return;
    final prev = _states[scanned.id]!;
    _states[scanned.id] = prev.copyWith(
      device: prev.device.copyWith(rssi: scanned.rssi),
      isLost: false,
      lastSeen: DateTime.now(),
      previousRssi: prev.device.rssi,
    );
    state = _states.values.toList();
  }

  void _startLostCheckTimer() {
    _lostCheckTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      bool changed = false;
      for (final id in _states.keys) {
        final s = _states[id]!;
        if (s.isLost || s.lastSeen == null) continue;
        if (now.difference(s.lastSeen!).inSeconds >= 5) {
          _states[id] = s.copyWith(isLost: true);
          changed = true;
        }
      }
      if (changed) state = _states.values.toList();
    });
  }
}

final trackingProvider =
    NotifierProvider<TrackingNotifier, List<TrackedDeviceState>>(
  TrackingNotifier.new,
);
