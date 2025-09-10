import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/secure_logger.dart';

/// 안전 상태 레벨
enum SafetyLevel {
  safe,     // 녹색 - 안전 상태
  warning,  // 주황색 - 주의 필요 (알림 1시간 전)
  critical, // 빨간색 - 위험 상태 (알림 시간 초과)
}

/// 안전 상태 정보 클래스
class SafetyStatus {
  final SafetyLevel level;
  final String message;
  final String? description;
  final DateTime? lastActivityTime;
  final Duration timeSinceLastActivity;
  final Duration timeUntilNextLevel;
  final int alertHours;

  SafetyStatus({
    required this.level,
    required this.message,
    this.description,
    this.lastActivityTime,
    required this.timeSinceLastActivity,
    required this.timeUntilNextLevel,
    required this.alertHours,
  });

  @override
  String toString() {
    return 'SafetyStatus(level: $level, message: $message, '
           'timeSinceLastActivity: $timeSinceLastActivity, '
           'timeUntilNextLevel: $timeUntilNextLevel, '
           'alertHours: $alertHours)';
  }
}

/// 안전 상태 계산 서비스
/// 
/// 부모님의 마지막 활동 시간과 설정된 알림 시간을 기반으로
/// 현재 안전 상태(녹색/주황/빨강)를 계산하고 관련 정보를 제공합니다.
class SafetyStatusCalculator {
  
  /// 가족 데이터를 기반으로 현재 안전 상태 계산
  /// 
  /// [familyData] - Firebase에서 가져온 가족 데이터
  /// 
  /// 상태 계산 로직:
  /// - 녹색 (안전): 알림 시간 - 50분 이전
  /// - 주황색 (주의): 알림 시간 50분 전 ~ 알림 시간
  /// - 빨간색 (위험): 알림 시간 초과
  SafetyStatus calculateSafetyStatus(Map<String, dynamic> familyData) {
    try {
      // 알림 설정 시간 가져오기 (기본값: 12시간)
      final settings = familyData['settings'] as Map<String, dynamic>?;
      final alertHours = settings?['alertHours'] as int? ?? 
                        settings?['survivalAlertHours'] as int? ?? 12;
      
      // 마지막 활동 시간 파싱
      final lastActivityTime = _parseLastActivityTime(familyData);
      
      if (lastActivityTime == null) {
        return SafetyStatus(
          level: SafetyLevel.warning,
          message: '활동 정보를 확인 중입니다',
          description: '부모님의 앱 사용 기록을 불러오고 있습니다.',
          timeSinceLastActivity: Duration.zero,
          timeUntilNextLevel: Duration.zero,
          alertHours: alertHours,
        );
      }

      final now = DateTime.now();
      final timeSinceLastActivity = now.difference(lastActivityTime);
      
      // 임계값 계산 (분 단위)
      final alertThresholdMinutes = alertHours * 60;
      final warningThresholdMinutes = alertThresholdMinutes - 50; // 50분 전 경고
      
      // 현재 비활성 시간 (분 단위)
      final inactiveMinutes = timeSinceLastActivity.inMinutes;
      
      secureLog.debug('Safety status calculation: '
          'inactiveMinutes=$inactiveMinutes, '
          'warningThreshold=$warningThresholdMinutes, '
          'alertThreshold=$alertThresholdMinutes');

      if (inactiveMinutes >= alertThresholdMinutes) {
        // 빨간색 - 위험 상태 (알림 시간 초과)
        return _createCriticalStatus(
          timeSinceLastActivity, 
          lastActivityTime, 
          alertHours,
        );
      } else if (warningThresholdMinutes > 0 && inactiveMinutes >= warningThresholdMinutes) {
        // 주황색 - 주의 필요 (50분 전 경고)
        final timeUntilCritical = Duration(
          minutes: alertThresholdMinutes - inactiveMinutes,
        );
        return _createWarningStatus(
          timeSinceLastActivity,
          timeUntilCritical,
          lastActivityTime,
          alertHours,
        );
      } else {
        // 녹색 - 안전 상태
        final timeUntilWarning = warningThresholdMinutes > 0
            ? Duration(minutes: warningThresholdMinutes - inactiveMinutes)
            : Duration(minutes: alertThresholdMinutes - inactiveMinutes);
        return _createSafeStatus(
          timeSinceLastActivity,
          timeUntilWarning,
          lastActivityTime,
          alertHours,
        );
      }
    } catch (e) {
      secureLog.error('Error calculating safety status', e);
      return SafetyStatus(
        level: SafetyLevel.warning,
        message: '상태 계산 중 오류가 발생했습니다',
        description: '잠시 후 다시 확인해주세요.',
        timeSinceLastActivity: Duration.zero,
        timeUntilNextLevel: Duration.zero,
        alertHours: 12,
      );
    }
  }

  /// 마지막 활동 시간 파싱
  /// 
  /// 다양한 데이터 소스에서 마지막 활동 시간을 추출:
  /// 1. lastPhoneActivity (최우선 - 실제 폰 사용 활동)
  /// 2. lastActive (앱 특정 활동)
  /// 3. lastMealTime (식사 기록)
  /// 4. location (위치 정보는 보조 지표로만 사용)
  DateTime? _parseLastActivityTime(Map<String, dynamic> familyData) {
    try {
      // 1. 휴대폰 일반 활동 시간 (최우선 - 실제 사용자 활동을 나타냄)
      final lastPhoneActivity = familyData['lastPhoneActivity'] ?? 
                               familyData['blastPhoneActivity'];
      if (lastPhoneActivity != null) {
        final phoneTime = _parseTimestamp(lastPhoneActivity);
        if (phoneTime != null) {
          secureLog.debug('Using lastPhoneActivity as primary activity indicator: $phoneTime');
          return phoneTime;
        }
      }

      // 2. 앱 특정 활동 시간 (두 번째 우선순위)
      final lastActive = familyData['lastActive'];
      if (lastActive != null) {
        final activeTime = _parseTimestamp(lastActive);
        if (activeTime != null) {
          secureLog.debug('Using lastActive as activity indicator: $activeTime');
          return activeTime;
        }
      }

      // 3. 최근 식사 시간 (세 번째 우선순위)
      final lastMeal = familyData['lastMeal'] as Map<String, dynamic>?;
      if (lastMeal != null) {
        final mealTimestamp = lastMeal['timestamp'];
        if (mealTimestamp != null) {
          final mealTime = _parseTimestamp(mealTimestamp);
          if (mealTime != null) {
            secureLog.debug('Using lastMealTime as activity indicator: $mealTime');
            return mealTime;
          }
        }
      }

      // 4. 위치 정보 업데이트 시간 (최후 수단 - GPS는 자동 업데이트될 수 있음)
      final location = familyData['location'] as Map<String, dynamic>?;
      if (location != null && location['timestamp'] != null) {
        final locationTime = _parseTimestamp(location['timestamp']);
        if (locationTime != null) {
          secureLog.debug('Using location timestamp as fallback activity indicator: $locationTime');
          return locationTime;
        }
      }

      secureLog.warning('No valid activity timestamps found in family data');
      return null;
    } catch (e) {
      secureLog.error('Error parsing last activity time', e);
      return null;
    }
  }

  /// 다양한 형식의 타임스탬프를 DateTime으로 변환
  DateTime? _parseTimestamp(dynamic timestamp) {
    try {
      if (timestamp is Timestamp) {
        return timestamp.toDate();
      } else if (timestamp is String) {
        return DateTime.parse(timestamp);
      } else if (timestamp is int) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
      return null;
    } catch (e) {
      secureLog.warning('Failed to parse timestamp: $timestamp', e);
      return null;
    }
  }

  /// 안전 상태 생성
  SafetyStatus _createSafeStatus(
    Duration timeSinceLastActivity,
    Duration timeUntilNextLevel,
    DateTime lastActivityTime,
    int alertHours,
  ) {
    final hours = timeSinceLastActivity.inHours;
    final minutes = timeSinceLastActivity.inMinutes % 60;
    
    String timeStr;
    if (hours > 0) {
      timeStr = minutes > 0 ? '$hours시간 $minutes분' : '$hours시간';
    } else {
      timeStr = '$minutes분';
    }

    return SafetyStatus(
      level: SafetyLevel.safe,
      message: '안전하게 지내고 계십니다',
      description: '$timeStr 전에 활동하셨습니다. 정상적으로 생활하고 계세요.',
      lastActivityTime: lastActivityTime,
      timeSinceLastActivity: timeSinceLastActivity,
      timeUntilNextLevel: timeUntilNextLevel,
      alertHours: alertHours,
    );
  }

  /// 주의 상태 생성
  SafetyStatus _createWarningStatus(
    Duration timeSinceLastActivity,
    Duration timeUntilCritical,
    DateTime lastActivityTime,
    int alertHours,
  ) {
    final remainingHours = timeUntilCritical.inHours;
    final remainingMinutes = timeUntilCritical.inMinutes % 60;
    
    String timeStr;
    if (remainingHours > 0) {
      timeStr = remainingMinutes > 0 ? '$remainingHours시간 $remainingMinutes분' : '$remainingHours시간';
    } else {
      timeStr = '$remainingMinutes분';
    }

    return SafetyStatus(
      level: SafetyLevel.warning,
      message: '주의가 필요합니다',
      description: '$timeStr 후에 알림이 전송됩니다. 부모님께 안부를 확인해보세요.',
      lastActivityTime: lastActivityTime,
      timeSinceLastActivity: timeSinceLastActivity,
      timeUntilNextLevel: timeUntilCritical,
      alertHours: alertHours,
    );
  }

  /// 위험 상태 생성
  SafetyStatus _createCriticalStatus(
    Duration timeSinceLastActivity,
    DateTime lastActivityTime,
    int alertHours,
  ) {
    final hours = timeSinceLastActivity.inHours;
    final minutes = timeSinceLastActivity.inMinutes % 60;
    
    String timeStr;
    if (hours > 0) {
      timeStr = minutes > 0 ? '$hours시간 $minutes분' : '$hours시간';
    } else {
      timeStr = '$minutes분';
    }

    return SafetyStatus(
      level: SafetyLevel.critical,
      message: '긴급 상황이 의심됩니다',
      description: '$timeStr째 활동이 없습니다. 즉시 부모님의 안전을 확인해주세요.',
      lastActivityTime: lastActivityTime,
      timeSinceLastActivity: timeSinceLastActivity,
      timeUntilNextLevel: Duration.zero, // 이미 최고 위험 단계
      alertHours: alertHours,
    );
  }

  /// 활동 데이터가 유효한지 확인
  bool hasValidActivityData(Map<String, dynamic> familyData) {
    return _parseLastActivityTime(familyData) != null;
  }

  /// 알림 설정이 유효한지 확인
  bool hasValidAlertSettings(Map<String, dynamic> familyData) {
    final settings = familyData['settings'] as Map<String, dynamic>?;
    final alertHours = settings?['alertHours'] as int? ?? 
                      settings?['survivalAlertHours'] as int?;
    return alertHours != null && alertHours > 0 && alertHours <= 72;
  }
}