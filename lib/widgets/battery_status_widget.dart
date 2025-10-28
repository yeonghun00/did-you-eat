import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BatteryStatusWidget extends StatelessWidget {
  final int? batteryLevel;
  final bool? isCharging;
  final dynamic batteryTimestamp;
  final String? batteryHealth;

  const BatteryStatusWidget({
    super.key,
    this.batteryLevel,
    this.isCharging,
    this.batteryTimestamp,
    this.batteryHealth,
  });

  @override
  Widget build(BuildContext context) {
    // No battery data
    if (batteryLevel == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.battery_unknown, color: Colors.grey),
          title: const Text('배터리 상태'),
          subtitle: const Text('데이터 없음'),
        ),
      );
    }

    // Get battery info
    final level = batteryLevel!;
    final charging = isCharging ?? false;
    final emoji = _getBatteryEmoji(level, charging);
    final color = _getBatteryColor(level, charging);
    final statusText = _getBatteryStatusText(level, charging);
    final timeAgo = _getTimeAgo(batteryTimestamp);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 40)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '배터리: $level%',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                if (charging)
                  const Icon(Icons.charging_station, color: Colors.blue, size: 32),
              ],
            ),
            const SizedBox(height: 8),

            // Battery level bar
            LinearProgressIndicator(
              value: level / 100,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),

            const SizedBox(height: 8),

            // Timestamp
            Text(
              '업데이트: $timeAgo',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),

            // Battery health warning
            if (batteryHealth != null && batteryHealth != 'GOOD')
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.orange, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '배터리 상태: $batteryHealth',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getBatteryEmoji(int level, bool charging) {
    if (charging) return '🔌';
    if (level >= 80) return '🔋';
    if (level >= 50) return '🔋';
    if (level >= 20) return '🪫';
    if (level >= 10) return '⚠️';
    return '🔴';
  }

  Color _getBatteryColor(int level, bool charging) {
    if (charging) return Colors.blue;
    if (level >= 50) return Colors.green;
    if (level >= 20) return Colors.orange;
    if (level >= 10) return Colors.deepOrange;
    return Colors.red;
  }

  String _getBatteryStatusText(int level, bool charging) {
    if (charging) return '충전 중';
    if (level >= 50) return '양호';
    if (level >= 20) return '보통';
    if (level >= 10) return '낮음 - 충전 필요';
    if (level > 0) return '위험 - 곧 꺼질 수 있음!';
    return '휴대폰 꺼짐';
  }

  String _getTimeAgo(dynamic timestamp) {
    if (timestamp == null) return '알 수 없음';

    DateTime? dateTime;
    if (timestamp is Timestamp) {
      dateTime = timestamp.toDate();
    } else if (timestamp is String) {
      try {
        dateTime = DateTime.parse(timestamp);
      } catch (e) {
        return '알 수 없음';
      }
    } else if (timestamp is DateTime) {
      dateTime = timestamp;
    } else {
      return '알 수 없음';
    }

    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) return '방금 전';
    if (difference.inMinutes < 60) return '${difference.inMinutes}분 전';
    if (difference.inHours < 24) return '${difference.inHours}시간 전';
    return '${difference.inDays}일 전';
  }
}
