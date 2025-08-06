import 'package:cloud_firestore/cloud_firestore.dart';

class MealRecord {
  final DateTime timestamp;
  final int mealNumber;
  final String elderlyName;

  MealRecord({
    required this.timestamp,
    required this.mealNumber,
    required this.elderlyName,
  });

  factory MealRecord.fromMap(Map<String, dynamic> map) {
    return MealRecord(
      timestamp: map['timestamp'] is String 
          ? DateTime.parse(map['timestamp'])
          : (map['timestamp'] as Timestamp).toDate(),
      mealNumber: map['mealNumber'] ?? 1,
      elderlyName: map['elderlyName'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'mealNumber': mealNumber,
      'elderlyName': elderlyName,
    };
  }
}

// Keep FamilyRecord for backward compatibility during transition
class FamilyRecord {
  final String audioUrl;
  final String? photoUrl;
  final DateTime timestamp;
  final String elderlyName;

  FamilyRecord({
    required this.audioUrl,
    this.photoUrl,
    required this.timestamp,
    required this.elderlyName,
  });

  factory FamilyRecord.fromMap(Map<String, dynamic> map) {
    return FamilyRecord(
      audioUrl: map['audioUrl'] ?? '',
      photoUrl: map['photoUrl'],
      timestamp: map['timestamp'] is String 
          ? DateTime.parse(map['timestamp'])
          : (map['timestamp'] as Timestamp).toDate(),
      elderlyName: map['elderlyName'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'audioUrl': audioUrl,
      'photoUrl': photoUrl,
      'timestamp': Timestamp.fromDate(timestamp),
      'elderlyName': elderlyName,
    };
  }
}

class FamilyInfo {
  final String familyCode;
  final String elderlyName;
  final DateTime createdAt;
  final String? lastMealTime;
  final bool isActive;
  final String deviceInfo;

  FamilyInfo({
    required this.familyCode,
    required this.elderlyName,
    required this.createdAt,
    this.lastMealTime,
    required this.isActive,
    required this.deviceInfo,
  });

  factory FamilyInfo.fromMap(Map<String, dynamic> map) {
    // Handle lastMealTime which can be String, Map, or null
    String? lastMealTimeStr;
    final lastMealTimeRaw = map['lastMealTime'];
    if (lastMealTimeRaw != null) {
      if (lastMealTimeRaw is String) {
        lastMealTimeStr = lastMealTimeRaw;
      } else if (lastMealTimeRaw is Map) {
        // If it's a Map (like Timestamp or complex object), extract timestamp
        if (lastMealTimeRaw.containsKey('timestamp')) {
          lastMealTimeStr = lastMealTimeRaw['timestamp'] as String?;
        } else {
          lastMealTimeStr = null; // Can't parse, set to null
        }
      } else if (lastMealTimeRaw is Timestamp) {
        lastMealTimeStr = lastMealTimeRaw.toDate().toIso8601String();
      }
    }
    
    // Handle createdAt safely
    DateTime createdAtDate;
    final createdAtRaw = map['createdAt'];
    if (createdAtRaw is Timestamp) {
      createdAtDate = createdAtRaw.toDate();
    } else if (createdAtRaw is String) {
      createdAtDate = DateTime.parse(createdAtRaw);
    } else {
      createdAtDate = DateTime.now(); // Fallback
    }
    
    return FamilyInfo(
      familyCode: map['familyCode'] ?? '',
      elderlyName: map['elderlyName'] ?? '',
      createdAt: createdAtDate,
      lastMealTime: lastMealTimeStr,
      isActive: map['isActive'] ?? false,
      deviceInfo: map['deviceInfo'] ?? '',
    );
  }
}

enum ParentStatus {
  normal,    // 오늘 기록함
  caution,   // 2일 미기록
  warning,   // 3일 이상 미기록
  emergency, // 5일 이상 미기록
}

class ParentStatusInfo {
  final ParentStatus status;
  final DateTime? lastRecording;
  final int daysSinceLastRecord;
  final String message;

  ParentStatusInfo({
    required this.status,
    this.lastRecording,
    required this.daysSinceLastRecord,
    required this.message,
  });
}