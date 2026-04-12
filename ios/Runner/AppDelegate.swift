import CoreBluetooth
import Flutter
import UIKit

// Separate stream handler for the BT state channel.
// AppDelegate already conforms to FlutterStreamHandler for the scan channel,
// so we can't reuse the same conformance.
private class StateStreamHandler: NSObject, FlutterStreamHandler {
    var eventSink: FlutterEventSink?
    // Called on subscribe — lets AppDelegate push the current state immediately
    var onListenCallback: ((FlutterEventSink) -> Void)?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        onListenCallback?(events)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}

@main
@objc class AppDelegate: FlutterAppDelegate {

    private let methodChannelName = "bluetooth/control"
    private let eventChannelName = "bluetooth/scan"
    private let stateChannelName = "bluetooth/state"

    private var centralManager: CBCentralManager?
    private var eventSink: FlutterEventSink?

    private lazy var stateHandler: StateStreamHandler = {
        let handler = StateStreamHandler()
        handler.onListenCallback = { [weak self] sink in
            sink(self?.getBluetoothState() ?? "unavailable")
        }
        return handler
    }()

    // startScan called before CBCentralManager reaches poweredOn
    private var pendingStartScanResult: FlutterResult?
    // requestPermission called before user responds to the system BT dialog
    private var pendingPermissionResult: FlutterResult?

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
        setupStateChannel(controller: controller)

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // ─── MethodChannel ───────────────────────────────────────────────────────

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
                self.handlePermissionRequest(result: result)
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

    private func getBluetoothState() -> String {
        guard let manager = centralManager else {
            centralManager = CBCentralManager(delegate: self, queue: nil)
            return "unavailable"
        }
        switch manager.state {
        case .poweredOn: return "on"
        case .poweredOff: return "off"
        default: return "unavailable"
        }
    }

    private func getPermissionStatus() -> Bool {
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
        if #available(iOS 13.1, *) {
            return CBCentralManager.authorization == .allowedAlways
        }
        return true
    }

    private func handlePermissionRequest(result: @escaping FlutterResult) {
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
        if #available(iOS 13.1, *) {
            switch CBCentralManager.authorization {
            case .allowedAlways:
                result(true)
            case .denied, .restricted:
                result(false)
            case .notDetermined:
                // System dialog will appear; complete the result once the manager
                // transitions to a definitive state in centralManagerDidUpdateState.
                pendingPermissionResult = result
            @unknown default:
                result(false)
            }
        } else {
            result(true)
        }
    }

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
            pendingStartScanResult = result
        }
    }

    private func stopScan() {
        centralManager?.stopScan()
        pendingStartScanResult = nil
    }

    // ─── EventChannel (scan results) ─────────────────────────────────────────

    private func setupEventChannel(controller: FlutterViewController) {
        let channel = FlutterEventChannel(
            name: eventChannelName,
            binaryMessenger: controller.binaryMessenger
        )
        channel.setStreamHandler(self)
    }

    // ─── EventChannel (BT state changes) ─────────────────────────────────────

    private func setupStateChannel(controller: FlutterViewController) {
        let channel = FlutterEventChannel(
            name: stateChannelName,
            binaryMessenger: controller.binaryMessenger
        )
        channel.setStreamHandler(stateHandler)
    }
}

// ─── CBCentralManagerDelegate ─────────────────────────────────────────────────

extension AppDelegate: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Push state change to Dart
        let stateStr: String
        switch central.state {
        case .poweredOn:  stateStr = "on"
        case .poweredOff: stateStr = "off"
        default:          stateStr = "unavailable"
        }
        stateHandler.eventSink?(stateStr)

        // Resolve a pending requestPermission call that was waiting for authorization
        if let permResult = pendingPermissionResult {
            switch central.state {
            case .poweredOn, .poweredOff:
                // Permission was granted (BT may be on or off, but access is allowed)
                permResult(true)
                pendingPermissionResult = nil
            case .unauthorized:
                permResult(false)
                pendingPermissionResult = nil
            default:
                break // Still transitioning — wait for the next state update
            }
        }

        // Resume any pending startScan call that arrived before BT was ready
        if central.state == .poweredOn, let pendingResult = pendingStartScanResult {
            central.scanForPeripherals(withServices: nil, options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: true
            ])
            pendingResult(nil)
            pendingStartScanResult = nil
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let isConnectable = advertisementData["kCBAdvDataIsConnectable"] as? Bool ?? false
        guard isConnectable else { return }

        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advName ?? peripheral.name ?? ""

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

// ─── FlutterStreamHandler (scan channel) ─────────────────────────────────────

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
