import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../bluetooth/ble_device.dart';

class DeviceRepository {
  static const _key = 'tracked_devices';

  Future<List<BleDevice>> getTrackedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_key) ?? [];
    return jsonList.map((json) {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return BleDevice(id: map['id'], name: map['name'], rssi: 0);
    }).toList();
  }

  Future<void> addDevice(BleDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    final devices = await getTrackedDevices();
    if (devices.any((d) => d.id == device.id)) return;
    devices.add(device);
    await prefs.setStringList(_key, _encode(devices));
  }

  Future<void> removeDevice(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final devices = await getTrackedDevices();
    devices.removeWhere((d) => d.id == id);
    await prefs.setStringList(_key, _encode(devices));
  }

  List<String> _encode(List<BleDevice> devices) {
    return devices.map((d) => jsonEncode({'id': d.id, 'name': d.name})).toList();
  }
}
