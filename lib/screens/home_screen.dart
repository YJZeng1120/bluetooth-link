import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bluetooth/ble_device.dart';
import '../bluetooth/scan_providers.dart';
import '../tracking/tracking_providers.dart';
import '../widgets/signal_bar.dart' show SignalBar, rssiToLabel, rssiTrend;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // 本地 UI 狀態：記錄已彈過通知的裝置，避免重複提示
  final _alertedLostIds = <String>{};

  @override
  Widget build(BuildContext context) {
    // 偵測掃描錯誤（權限被拒、掃描失敗）
    ref.listen<ScanState>(scanProvider, (prev, next) {
      if (next.errorMessage != null &&
          next.errorMessage != prev?.errorMessage) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.errorMessage!)));
      }
    });

    // 偵測新增的 lost 裝置
    ref.listen<List<TrackedDeviceState>>(trackingProvider, (_, next) {
      for (final s in next) {
        if (s.isLost && _alertedLostIds.add(s.device.id)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${s.device.displayName} 已超出範圍'),
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    });

    final scanState = ref.watch(scanProvider);
    final trackedStates = ref.watch(trackingProvider);

    final trackedIds = trackedStates.map((s) => s.device.id).toSet();
    final nearbyUntracked =
        scanState.nearbyDevices.values
            .where((d) => !trackedIds.contains(d.id) && d.name.isNotEmpty)
            .toList()
          ..sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));

    return Scaffold(
      appBar: AppBar(
        title: const Text('藍牙搜尋器'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: Icon(scanState.isScanning ? Icons.stop : Icons.play_arrow),
            tooltip: scanState.isScanning ? '停止掃描' : '開始掃描',
            onPressed: scanState.isScanning
                ? ref.read(scanProvider.notifier).stopScan
                : ref.read(scanProvider.notifier).startScan,
          ),
        ],
      ),
      body: Column(
        children: [
          if (scanState.bluetoothState == 'off') const _BluetoothOffBanner(),
          Expanded(
            child: ListView(
              children: [
                _SectionHeader(
                  title: '我的裝置',
                  subtitle: '${trackedStates.length} 個裝置',
                ),
                if (trackedStates.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Text(
                      '尚未加入追蹤裝置。從附近裝置列表中加入。',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ...trackedStates.map(
                  (s) => _TrackedDeviceTile(
                    device: s.device,
                    isLost: s.isLost,
                    previousRssi: s.previousRssi,
                    onRemove: () {
                      _alertedLostIds.remove(s.device.id);
                      ref
                          .read(trackingProvider.notifier)
                          .removeDevice(s.device.id);
                    },
                  ),
                ),
                const Divider(height: 1),
                _SectionHeader(
                  title: '附近裝置',
                  subtitle: scanState.isScanning
                      ? '掃描中... ${nearbyUntracked.length} 個'
                      : '已停止',
                ),
                if (nearbyUntracked.isEmpty && scanState.isScanning)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Text(
                      '掃描中，尚未發現裝置...',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ...nearbyUntracked.map(
                  (device) => _NearbyDeviceTile(
                    device: device,
                    onAdd: () =>
                        ref.read(trackingProvider.notifier).addDevice(device),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Private widgets ───────────────────────────────────────────────────────────

class _BluetoothOffBanner extends StatelessWidget {
  const _BluetoothOffBanner();

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
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey),
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

  const _TrackedDeviceTile({
    required this.device,
    required this.isLost,
    required this.onRemove,
    this.previousRssi,
  });

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
          : Text(
              '訊號 ${rssiToLabel(device.rssi)} (${device.rssi} dBm)'
              '${rssiTrend(previousRssi, device.rssi)}  ·  ${device.shortId}',
            ),
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
