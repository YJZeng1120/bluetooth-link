import 'dart:async';

import 'package:flutter/material.dart';

import '../bluetooth/ble_device.dart';
import '../bluetooth/bluetooth_service.dart';
import '../tracking/device_repository.dart';
import '../tracking/tracking_notifier.dart';
import '../widgets/signal_bar.dart' show SignalBar, rssiToLabel, rssiTrend;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _bluetoothService = BluetoothService();
  late final TrackingNotifier _trackingNotifier;

  // 附近裝置的最新狀態（id → BleDevice）
  final Map<String, BleDevice> _nearbyDevices = {};
  // 每個附近裝置最後一次被掃到的時間，用於清除過期裝置
  final Map<String, DateTime> _deviceLastSeen = {};

  StreamSubscription<BleDevice>? _scanSubscription;
  StreamSubscription<String>? _stateSubscription;
  Timer? _cleanupTimer;

  bool _isScanning = false;
  String _bluetoothState = 'unavailable';
  final Set<String> _alertedLostIds = {};

  @override
  void initState() {
    super.initState();
    _trackingNotifier = TrackingNotifier(DeviceRepository());
    _trackingNotifier.onDeviceLost = _onDeviceLost;
    _trackingNotifier.load().then((_) => _initBluetooth());
  }

  Future<void> _initBluetooth() async {
    // 先請求權限（Android 現在會真正等待使用者回應後才 return）
    final granted = await _bluetoothService.requestPermission();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要藍牙權限才能掃描裝置')),
        );
      }
      return;
    }

    // 取得初始藍牙狀態，並訂閱後續狀態變化
    _bluetoothState = await _bluetoothService.getBluetoothState();
    if (mounted) setState(() {});

    _stateSubscription = _bluetoothService.bluetoothStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _bluetoothState = state);
      if (state == 'on' && !_isScanning) {
        _startScan();
      } else if (state != 'on' && _isScanning) {
        _stopScan();
      }
    });

    // _stateSubscription receives the current state immediately on subscribe (both Android
    // and iOS push it via onListen / onListenCallback), so _startScan() will be called
    // from the callback above — no need to call it explicitly here.
  }

  Future<void> _startScan() async {
    try {
      await _bluetoothService.startScan();
      setState(() => _isScanning = true);

      _scanSubscription = _bluetoothService.scanResults.listen((device) {
        setState(() {
          _nearbyDevices[device.id] = device;
          _deviceLastSeen[device.id] = DateTime.now();
        });
        _trackingNotifier.onScanResult(device);
      });

      // 每 10 秒清除超過 30 秒未出現的附近裝置
      _cleanupTimer = Timer.periodic(const Duration(seconds: 10), (_) => _removeStaleDevices());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法啟動掃描：$e')),
        );
      }
    }
  }

  Future<void> _stopScan() async {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await _bluetoothService.stopScan();
    setState(() => _isScanning = false);
  }

  // 移除超過 30 秒沒有掃描到的附近裝置
  void _removeStaleDevices() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 30));
    final staleIds = _deviceLastSeen.entries
        .where((e) => e.value.isBefore(cutoff))
        .map((e) => e.key)
        .toList();
    if (staleIds.isEmpty) return;
    setState(() {
      for (final id in staleIds) {
        _nearbyDevices.remove(id);
        _deviceLastSeen.remove(id);
      }
    });
  }

  void _onDeviceLost(BleDevice device) {
    if (_alertedLostIds.contains(device.id)) return;
    _alertedLostIds.add(device.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${device.displayName} 已超出範圍'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    _stateSubscription?.cancel();
    _stopScan();
    _trackingNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('藍牙雷達'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: Icon(_isScanning ? Icons.stop : Icons.play_arrow),
            tooltip: _isScanning ? '停止掃描' : '開始掃描',
            onPressed: _isScanning ? _stopScan : _startScan,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_bluetoothState == 'off') _BluetoothOffBanner(),
          Expanded(
            child: ListenableBuilder(
              listenable: _trackingNotifier,
              builder: (context, _) {
                final trackedStates = _trackingNotifier.trackedStates;
                final trackedIds = trackedStates.map((s) => s.device.id).toSet();
                final nearbyUntracked = _nearbyDevices.values
                    .where((d) => !trackedIds.contains(d.id) && d.name.isNotEmpty)
                    .toList()
                  ..sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));

                return ListView(
                  children: [
                    _SectionHeader(title: '我的裝置', subtitle: '${trackedStates.length} 個裝置'),
                    if (trackedStates.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Text('尚未加入追蹤裝置。從附近裝置列表中加入。', style: TextStyle(color: Colors.grey)),
                      ),
                    ...trackedStates.map((state) {
                      return _TrackedDeviceTile(
                        device: state.device,
                        isLost: state.isLost,
                        previousRssi: state.previousRssi,
                        onRemove: () {
                          _alertedLostIds.remove(state.device.id);
                          _trackingNotifier.removeDevice(state.device.id);
                        },
                      );
                    }),
                    const Divider(height: 1),
                    _SectionHeader(
                      title: '附近裝置',
                      subtitle: _isScanning ? '掃描中... ${nearbyUntracked.length} 個' : '已停止',
                    ),
                    if (nearbyUntracked.isEmpty && _isScanning)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Text('掃描中，尚未發現裝置...', style: TextStyle(color: Colors.grey)),
                      ),
                    ...nearbyUntracked.map(
                      (device) => _NearbyDeviceTile(
                        device: device,
                        onAdd: () => _trackingNotifier.addDevice(device),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BluetoothOffBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.orange.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: const Row(
        children: [
          Icon(Icons.bluetooth_disabled, color: Colors.deepOrange, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '藍牙已關閉，請在系統設定中開啟',
              style: TextStyle(color: Colors.deepOrange),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _TrackedDeviceTile extends StatelessWidget {
  final BleDevice device;
  final bool isLost;
  final int? previousRssi;
  final VoidCallback onRemove;

  const _TrackedDeviceTile({required this.device, required this.isLost, required this.onRemove, this.previousRssi});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: isLost
          ? const Icon(Icons.bluetooth_disabled, color: Colors.red)
          : const Icon(Icons.bluetooth, color: Colors.blue),
      title: Text(device.displayName),
      subtitle: isLost
          ? const Text('訊號消失', style: TextStyle(color: Colors.red))
          : device.rssi == null
              ? const Text('尚未偵測', style: TextStyle(color: Colors.grey))
              : Text('訊號 ${rssiToLabel(device.rssi)} (${device.rssi} dBm)${rssiTrend(previousRssi, device.rssi)}  ·  ${device.shortId}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isLost && device.rssi != null) SignalBar(rssi: device.rssi),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, color: Colors.grey),
            tooltip: '移除追蹤',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _NearbyDeviceTile extends StatelessWidget {
  final BleDevice device;
  final VoidCallback onAdd;

  const _NearbyDeviceTile({required this.device, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.bluetooth, color: Colors.grey),
      title: Text(device.displayName),
      subtitle: Text(
        [
          '訊號 ${rssiToLabel(device.rssi)} (${device.rssi ?? '—'} dBm)',
          device.shortId,
          if (device.typeHint != null && device.name.isEmpty) device.typeHint!,
        ].join('  ·  '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SignalBar(rssi: device.rssi),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.blue),
            tooltip: '加入追蹤',
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}
