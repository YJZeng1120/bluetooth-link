import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ble_device.dart';
import 'bluetooth_service.dart';
import '../tracking/tracking_providers.dart';

// ── Data model ────────────────────────────────────────────────────────────────

class ScanState {
  final bool isScanning;
  final String bluetoothState;
  final Map<String, BleDevice> nearbyDevices;
  final String? errorMessage;

  const ScanState({
    this.isScanning = false,
    this.bluetoothState = 'unavailable',
    this.nearbyDevices = const {},
    this.errorMessage,
  });

  ScanState copyWith({
    bool? isScanning,
    String? bluetoothState,
    Map<String, BleDevice>? nearbyDevices,
    String? errorMessage,
  }) =>
      ScanState(
        isScanning: isScanning ?? this.isScanning,
        bluetoothState: bluetoothState ?? this.bluetoothState,
        nearbyDevices: nearbyDevices ?? this.nearbyDevices,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

// ── Providers ─────────────────────────────────────────────────────────────────

final bluetoothServiceProvider = Provider<BluetoothService>(
  (ref) => BluetoothService(),
);

class ScanNotifier extends Notifier<ScanState> {
  late final BluetoothService _service;
  StreamSubscription<BleDevice>? _scanSub;
  StreamSubscription<String>? _stateSub;
  Timer? _cleanupTimer;
  final Map<String, DateTime> _deviceLastSeen = {};

  @override
  ScanState build() {
    _service = ref.read(bluetoothServiceProvider);
    ref.onDispose(() {
      _cleanupTimer?.cancel();
      _stateSub?.cancel();
      _scanSub?.cancel();
      _service.stopScan();
    });
    Future.microtask(_init);
    return const ScanState();
  }

  Future<void> _init() async {
    final granted = await _service.requestPermission();
    if (!granted) {
      state = state.copyWith(errorMessage: '需要藍牙權限才能掃描裝置');
      return;
    }

    _stateSub = _service.bluetoothStateStream.listen((s) {
      state = state.copyWith(bluetoothState: s);
      if (s == 'on' && !state.isScanning) {
        startScan();
      } else if (s != 'on' && state.isScanning) {
        stopScan();
      }
    });
  }

  Future<void> startScan() async {
    try {
      await _service.startScan();
      state = state.copyWith(isScanning: true);

      _scanSub = _service.scanResults.listen((device) {
        _deviceLastSeen[device.id] = DateTime.now();
        final updated = Map<String, BleDevice>.from(state.nearbyDevices)
          ..[device.id] = device;
        state = state.copyWith(nearbyDevices: updated);
        ref.read(trackingProvider.notifier).onScanResult(device);
      });

      _cleanupTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _removeStale(),
      );
    } catch (e) {
      state = state.copyWith(errorMessage: '無法啟動掃描：$e');
    }
  }

  Future<void> stopScan() async {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    await _scanSub?.cancel();
    _scanSub = null;
    await _service.stopScan();
    state = state.copyWith(isScanning: false);
  }

  void _removeStale() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 30));
    final staleIds = _deviceLastSeen.entries
        .where((e) => e.value.isBefore(cutoff))
        .map((e) => e.key)
        .toList();
    if (staleIds.isEmpty) return;
    for (final id in staleIds) {
      _deviceLastSeen.remove(id);
    }
    final updated = Map<String, BleDevice>.from(state.nearbyDevices)
      ..removeWhere((id, _) => staleIds.contains(id));
    state = state.copyWith(nearbyDevices: updated);
  }
}

final scanProvider = NotifierProvider<ScanNotifier, ScanState>(ScanNotifier.new);
