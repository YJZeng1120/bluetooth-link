# 藍牙搜尋器 (Bluetooth Link)

一款以 Flutter 開發的跨平台 BLE 掃描 App，無需第三方藍牙套件，透過原生 Platform Channel 直接呼叫 iOS CoreBluetooth 與 Android BluetoothLeScanner，即時偵測附近裝置並顯示裝置的訊號強度變化。

---

## Demo

[![Demo Video](https://img.youtube.com/vi/5Nyi7YAlei0/0.jpg)](https://youtube.com/shorts/5Nyi7YAlei0)

---

## 功能

- **即時掃描**：自動偵測附近所有可連線的 BLE 裝置，依訊號強度排序
- **裝置追蹤**：將指定裝置加入「我的裝置」清單，持續監控其訊號
- **訊號強度顯示**：以四格訊號條與 dBm 數值呈現距離，並標示趨勢（↑ / ↓）
- **離線偵測**：追蹤中的裝置若 5 秒未出現，立即標記為「訊號消失」並彈出通知
- **藍牙狀態感知**：自動隨系統藍牙開關啟動或暫停掃描，並顯示提示橫幅
- **持久化儲存**：追蹤清單存入 SharedPreferences，重啟 App 後依然保留

---

## 技術架構

### 整體架構

```
Native BLE 事件
  → BluetoothService（Platform Channel 封裝）
    → ScanNotifier（Riverpod）— 管理附近裝置列表
      → TrackingNotifier（Riverpod）— 更新追蹤裝置的 RSSI
        → HomeScreen — 顯示兩個裝置清單
```

### Flutter ↔ Native Bridge

不依賴任何第三方 BLE 套件，所有藍牙功能透過三條 Platform Channel 與原生層溝通：

| Channel | 類型 | 用途 |
|---|---|---|
| `bluetooth/control` | MethodChannel | `requestPermission` / `startScan` / `stopScan` |
| `bluetooth/scan` | EventChannel | 掃描結果串流（每筆為一個裝置） |
| `bluetooth/state` | EventChannel | 藍牙狀態串流：`"on"` / `"off"` / `"unavailable"` |

- **iOS**（`AppDelegate.swift`）：使用 `CBCentralManager`，處理非同步授權流程與掃描等待
- **Android**（`MainActivity.kt`）：使用 `BluetoothLeScanner` + `BroadcastReceiver` 監聽系統狀態變化

### 狀態管理

使用 **Riverpod**（`NotifierProvider`）管理所有應用狀態：

- `ScanNotifier`：負責掃描生命週期，30 秒未出現的裝置會自動從列表移除
- `TrackingNotifier`：管理使用者儲存的追蹤裝置，5 秒無訊號標記為遺失
- `DeviceRepository`：以 `SharedPreferences` 儲存追蹤清單

### 技術選型

| 項目 | 選用 |
|---|---|
| 框架 | Flutter|
| 狀態管理 | flutter_riverpod |
| 本地儲存 | shared_preferences |
| BLE 實作 | 原生 Platform Channel（無第三方套件） |
| 目標平台 | iOS、Android |
