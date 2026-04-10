// 常見 BLE service UUID → 裝置類型對照
const _serviceTypeHints = {
  '00001812': 'HID 裝置（鍵盤/滑鼠）',
  '0000180f': '電池裝置',
  '0000180a': '裝置資訊',
  '0000fe9f': 'Google 裝置',
  '0000feed': 'Google Nearby',
  '0000feaa': 'Eddystone Beacon',
  '0000180d': '心率裝置',
  '0000181c': '使用者資料',
};

class BleDevice {
  final String id;
  final String name;
  final int rssi;
  final List<String> serviceUuids;

  const BleDevice({
    required this.id,
    required this.name,
    required this.rssi,
    this.serviceUuids = const [],
  });

  BleDevice copyWith({int? rssi}) {
    return BleDevice(id: id, name: name, rssi: rssi ?? this.rssi, serviceUuids: serviceUuids);
  }

  factory BleDevice.fromMap(Map<dynamic, dynamic> map) {
    final uuids = (map['serviceUuids'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    return BleDevice(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      rssi: map['rssi'] as int,
      serviceUuids: uuids,
    );
  }

  String get displayName => name.isNotEmpty ? name : typeHint ?? '未知裝置';

  // 根據 service UUID 猜測裝置類型
  String? get typeHint {
    for (final uuid in serviceUuids) {
      final normalized = uuid.toLowerCase().replaceAll('-', '');
      if (normalized.length < 8) continue;
      final short = normalized.substring(0, 8);
      if (_serviceTypeHints.containsKey(short)) return _serviceTypeHints[short];
    }
    return null;
  }

  // 顯示用的短 ID
  String get shortId => id.length > 8 ? '${id.substring(0, 8)}...' : id;
}
