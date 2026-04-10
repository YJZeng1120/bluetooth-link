package com.example.bluetooth_link

import android.Manifest
import android.annotation.SuppressLint
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
        (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
    }


    private fun ensureScanPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_SCAN
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

        val granted = permissions.all {
            ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }

        if (granted) {
            result.success(true)
            return
        }

        ActivityCompat.requestPermissions(this, permissions, PERMISSION_REQUEST_CODE)
        result.success(false)
    }

    private fun getDeviceName(result: ScanResult): String {
        val recordName = result.scanRecord?.deviceName
        if (!recordName.isNullOrEmpty()) return recordName

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val hasPerm = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_CONNECT
            ) == PackageManager.PERMISSION_GRANTED

            if (hasPerm) result.device.name ?: "" else ""
        } else {
            result.device.name ?: ""
        }
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !result.isConnectable) return

            val data = mapOf(
                "id" to result.device.address,
                "name" to getDeviceName(result),
                "rssi" to result.rssi
            )

            eventSink?.success(data)
        }

        override fun onScanFailed(errorCode: Int) {
            eventSink?.error("SCAN_FAILED", "error: $errorCode", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
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

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    eventSink = sink
                }

                override fun onCancel(arguments: Any?) {
                    stopScan()
                    eventSink = null
                }
            })
    }



    private fun getBluetoothState(): String {
        val adapter = bluetoothAdapter ?: return "unavailable"
        return if (adapter.isEnabled) "on" else "off"
    }



    @SuppressLint("MissingPermission")
    private fun startScan(result: MethodChannel.Result) {
        val adapter = bluetoothAdapter

        if (adapter == null || !adapter.isEnabled) {
            result.error("BT_OFF", "Bluetooth is not enabled", null)
            return
        }

        if (!ensureScanPermission()) {
            result.error("NO_PERMISSION", "Permission not granted", null)
            return
        }

        if (isScanning) {
            result.success(null)
            return
        }

        adapter.bluetoothLeScanner?.startScan(scanCallback)
        isScanning = true

        result.success(null)
    }

    @SuppressLint("MissingPermission")
    private fun stopScan() {
        if (!isScanning) return
        bluetoothAdapter?.bluetoothLeScanner?.stopScan(scanCallback)
        isScanning = false
    }

    companion object {
        private const val PERMISSION_REQUEST_CODE = 100
    }
}