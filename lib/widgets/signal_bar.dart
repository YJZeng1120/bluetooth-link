import 'package:flutter/material.dart';

// RSSI → 人類可讀標籤
String rssiToLabel(int rssi) {
  if (rssi >= -60) return '非常近';
  if (rssi >= -70) return '近';
  if (rssi >= -80) return '普通';
  if (rssi >= -90) return '遠';
  return '很遠';
}

// RSSI 趨勢：前後差距超過 3 dBm 才算有變化，避免雜訊
String rssiTrend(int? previousRssi, int currentRssi) {
  if (previousRssi == null) return '';
  final diff = currentRssi - previousRssi;
  if (diff > 3) return ' ↑';
  if (diff < -3) return ' ↓';
  return '';
}

// RSSI → 訊號格數（0–4）
int rssiToLevel(int rssi) {
  if (rssi >= -60) return 4;
  if (rssi >= -70) return 3;
  if (rssi >= -80) return 2;
  if (rssi >= -90) return 1;
  return 0;
}

class SignalBar extends StatelessWidget {
  final int rssi;
  final double barWidth;
  final double maxBarHeight;

  const SignalBar({
    super.key,
    required this.rssi,
    this.barWidth = 5,
    this.maxBarHeight = 20,
  });

  @override
  Widget build(BuildContext context) {
    final level = rssiToLevel(rssi);
    final color = _levelColor(level);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final barHeight = maxBarHeight * (i + 1) / 4;
        final active = i < level;
        return Container(
          width: barWidth,
          height: barHeight,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: active ? color : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Color _levelColor(int level) {
    switch (level) {
      case 4:
      case 3:
        return Colors.green;
      case 2:
        return Colors.orange;
      case 1:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
