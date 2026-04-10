import CoreBluetooth
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {

    private let methodChannelName = "bluetooth/control"
    private let eventChannelName = "bluetooth/scan"

    private var centralManager: CBCentralManager?
    private var eventSink: FlutterEventSink?

    // startScan 在 CBCentralManager 還未 poweredOn 時的 pending result
    private var pendingStartScanResult: FlutterResult?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        guard let controller = window?.rootViewController as? FlutterViewController else {
            return super.application(application, didFinishLaunchingWithOptions: launchOptions)
        }

        setupMethodChannel(controller: controller)
        setupEventChannel(controller: controller)

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // ─── MethodChannel 設定 ───────────────────────────────────────────────────

    private func setupMethodChannel(controller: FlutterViewController) {
        let channel = FlutterMethodChannel(
            name: methodChannelName,
            binaryMessenger: controller.binaryMessenger
        )
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            switch call.method {
            case "getBluetoothState":
                result(self.getBluetoothState())
            case "requestPermission":
                result(self.getPermissionStatus())
            case "startScan":
                self.startScan(result: result)
            case "stopScan":
                self.stopScan()
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // 回傳 "on" / "off" / "unavailable"
    private func getBluetoothState() -> String {
        guard let manager = centralManager else {
            // 初始化 CBCentralManager 會觸發系統權限請求
            centralManager = CBCentralManager(delegate: self, queue: nil)
            return "unavailable"
        }
        switch manager.state {
        case .poweredOn: return "on"
        case .poweredOff: return "off"
        default: return "unavailable"
        }
    }

    // 回傳目前授權狀態（初始化 CBCentralManager 會觸發系統授權對話框）
    private func getPermissionStatus() -> Bool {
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
        if #available(iOS 13.1, *) {
            return CBCentralManager.authorization == .allowedAlways
        }
        return true
    }

    // 啟動 BLE 掃描（若還未 poweredOn 則 pending）
    private func startScan(result: @escaping FlutterResult) {
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
        guard let manager = centralManager else {
            result(FlutterError(code: "UNAVAILABLE", message: "Bluetooth unavailable", details: nil))
            return
        }
        if manager.state == .poweredOn {
            manager.scanForPeripherals(withServices: nil, options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: true
            ])
            result(nil)
        } else if manager.state == .poweredOff {
            result(FlutterError(code: "BLUETOOTH_OFF", message: "Bluetooth is not enabled", details: nil))
        } else {
            // 還在初始化，等待 centralManagerDidUpdateState 再掃描
            pendingStartScanResult = result
        }
    }

    // 停止 BLE 掃描
    private func stopScan() {
        centralManager?.stopScan()
        pendingStartScanResult = nil
    }

    // ─── EventChannel 設定 ───────────────────────────────────────────────────

    private func setupEventChannel(controller: FlutterViewController) {
        let channel = FlutterEventChannel(
            name: eventChannelName,
            binaryMessenger: controller.binaryMessenger
        )
        channel.setStreamHandler(self)
    }
}

// ─── CBCentralManagerDelegate ─────────────────────────────────────────────────

extension AppDelegate: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn, let pendingResult = pendingStartScanResult {
            // 處理 pending 的 startScan 請求
            central.scanForPeripherals(withServices: nil, options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: true
            ])
            pendingResult(nil)
            pendingStartScanResult = nil
        }
    }

    // 掃描到裝置：推送 { id, name, rssi } 至 EventSink
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // 只處理可連線的裝置，過濾掉 beacon / AirDrop 等 non-connectable 廣播
        let isConnectable = advertisementData["kCBAdvDataIsConnectable"] as? Bool ?? false
        guard isConnectable else { return }

        // advertisementData 裡的名稱比 peripheral.name 更即時且完整
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advName ?? peripheral.name ?? ""

        // 擷取 service UUID 清單（可幫助識別裝置類型）
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
            .map { $0.uuidString } ?? []

        let data: [String: Any] = [
            "id": peripheral.identifier.uuidString,
            "name": name,
            "rssi": RSSI.intValue,
            "serviceUuids": serviceUUIDs
        ]
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(data)
        }
    }
}

// ─── FlutterStreamHandler ─────────────────────────────────────────────────────

extension AppDelegate: FlutterStreamHandler {

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        stopScan()
        eventSink = nil
        return nil
    }
}
