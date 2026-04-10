package com.example.bluetooth_link

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val METHOD_CHANNEL = "bluetooth/control"
    private val EVENT_CHANNEL = "bluetooth/scan"

    private var eventSink: EventChannel.EventSink? = null
    private var isScanning = false

    private val bluetoothAdapter: BluetoothAdapter? by lazy {
        val manager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        manager.adapter
    }

    // BLE ScanCallback：掃描到裝置時推送到 EventSink
    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            // 只處理可連線的裝置（API 26+），過濾掉 beacon / Nearby Share 等廣播
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !result.isConnectable) return

            val device = result.device
            val hasConnectPerm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                ActivityCompat.checkSelfPermission(
                    this@MainActivity, Manifest.permission.BLUETOOTH_CONNECT
                ) == PackageManager.PERMISSION_GRANTED
            } else true

            // scanRecord?.deviceName 通常比 device.name 更即時
            val name = result.scanRecord?.deviceName
                ?: if (hasConnectPerm) device.name else null

            // 擷取 service UUID 清單（幫助識別裝置類型）
            val serviceUuids = result.scanRecord?.serviceUuids
                ?.map { it.toString() } ?: emptyList<String>()

            val data = mapOf(
                "id" to device.address,
                "name" to (name ?: ""),
                "rssi" to result.rssi,
                "serviceUuids" to serviceUuids
            )
            runOnUiThread {
                eventSink?.success(data)
            }
        }

        override fun onScanFailed(errorCode: Int) {
            runOnUiThread {
                eventSink?.error("SCAN_FAILED", "BLE scan failed with error code $errorCode", null)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupMethodChannel(flutterEngine)
        setupEventChannel(flutterEngine)
    }

    // ─── MethodChannel 設定 ───────────────────────────────────────────────────

    private fun setupMethodChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getBluetoothState" -> result.success(getBluetoothState())
                "requestPermission" -> requestPermission(result)
                "startScan" -> startScan(result)
                "stopScan" -> {
                    stopScan()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // 回傳 "on" / "off" / "unavailable"
    private fun getBluetoothState(): String {
        val adapter = bluetoothAdapter ?: return "unavailable"
        return if (adapter.isEnabled) "on" else "off"
    }

    // 請求 BLE 相關權限，回傳是否已全部授權
    private fun requestPermission(result: MethodChannel.Result) {
        val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT
            )
        } else {
            arrayOf(
                Manifest.permission.BLUETOOTH,
                Manifest.permission.BLUETOOTH_ADMIN,
                Manifest.permission.ACCESS_FINE_LOCATION
            )
        }

        val allGranted = permissions.all {
            ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }

        if (allGranted) {
            result.success(true)
        } else {
            ActivityCompat.requestPermissions(this, permissions, PERMISSION_REQUEST_CODE)
            // 回傳目前狀態（用戶可能剛授權），下次呼叫才會是 true
            result.success(false)
        }
    }

    // 啟動 BLE 掃描
    private fun startScan(result: MethodChannel.Result) {
        val adapter = bluetoothAdapter
        if (adapter == null || !adapter.isEnabled) {
            result.error("BLUETOOTH_OFF", "Bluetooth is not enabled", null)
            return
        }

        val hasPermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(
                this, Manifest.permission.BLUETOOTH_SCAN
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(
                this, Manifest.permission.ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        }

        if (!hasPermission) {
            result.error("PERMISSION_DENIED", "Bluetooth scan permission not granted", null)
            return
        }

        if (!isScanning) {
            adapter.bluetoothLeScanner?.startScan(scanCallback)
            isScanning = true
        }
        result.success(null)
    }

    // 停止 BLE 掃描
    private fun stopScan() {
        if (isScanning) {
            val hasPermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                ContextCompat.checkSelfPermission(
                    this, Manifest.permission.BLUETOOTH_SCAN
                ) == PackageManager.PERMISSION_GRANTED
            } else true

            if (hasPermission) {
                bluetoothAdapter?.bluetoothLeScanner?.stopScan(scanCallback)
            }
            isScanning = false
        }
    }

    // ─── EventChannel 設定 ───────────────────────────────────────────────────

    private fun setupEventChannel(flutterEngine: FlutterEngine) {
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                eventSink = sink
            }

            override fun onCancel(arguments: Any?) {
                stopScan()
                eventSink = null
            }
        })
    }

    companion object {
        private const val PERMISSION_REQUEST_CODE = 100
    }
}
