
class BleDevice {
  final String id;
  final String name;
  final int? rssi;
  final List<String> serviceUuids;

  const BleDevice({
    required this.id,
    required this.name,
    this.rssi,
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

  String get displayName => name.isNotEmpty ? name : '未知裝置';

  // 顯示用的短 ID
  String get shortId => id.length > 8 ? '${id.substring(0, 8)}...' : id;
}
