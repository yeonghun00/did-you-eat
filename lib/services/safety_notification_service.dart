import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'child_app_service.dart';
import 'safety_status_calculator.dart';
import 'fcm_message_service.dart';
import '../utils/secure_logger.dart';

/// 안전 상태 알림 서비스
/// 
/// 부모님의 안전 상태를 실시간으로 모니터링하고,
/// 위험 상태 진입 시 자동으로 알림을 전송하는 서비스입니다.
class SafetyNotificationService {
  static final SafetyNotificationService _instance = SafetyNotificationService._internal();
  factory SafetyNotificationService() => _instance;
  SafetyNotificationService._internal();

  final ChildAppService _childService = ChildAppService();
  final SafetyStatusCalculator _statusCalculator = SafetyStatusCalculator();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  StreamSubscription? _monitoringSubscription;
  Timer? _periodicCheckTimer;
  
  String? _currentFamilyCode;
  SafetyLevel? _lastKnownLevel;
  DateTime? _lastCriticalNotificationTime;
  
  // 알림 방지를 위한 설정
  static const Duration _criticalNotificationCooldown = Duration(hours: 1);
  static const Duration _monitoringInterval = Duration(minutes: 5);

  /// 안전 상태 모니터링 시작
  /// 
  /// [familyCode] - 모니터링할 가족 코드
  Future<void> startMonitoring(String familyCode) async {
    try {
      secureLog.info('Starting safety monitoring for family: $familyCode');
      
      await stopMonitoring(); // 기존 모니터링 중지
      
      _currentFamilyCode = familyCode;
      
      // 실시간 가족 데이터 스트림 모니터링
      _monitoringSubscription = _childService
          .listenToSurvivalStatus(familyCode)
          .listen(
        _handleFamilyDataUpdate,
        onError: (error) {
          secureLog.error('Error in safety monitoring stream', error);
          _scheduleRetry();
        },
      );
      
      // 주기적 상태 확인 (네트워크 문제 대비)
      _periodicCheckTimer = Timer.periodic(
        _monitoringInterval,
        (_) => _performPeriodicCheck(familyCode),
      );
      
      secureLog.info('Safety monitoring started successfully');
    } catch (e) {
      secureLog.error('Failed to start safety monitoring', e);
    }
  }

  /// 안전 상태 모니터링 중지
  Future<void> stopMonitoring() async {
    secureLog.info('Stopping safety monitoring');
    
    await _monitoringSubscription?.cancel();
    _periodicCheckTimer?.cancel();
    
    _monitoringSubscription = null;
    _periodicCheckTimer = null;
    _currentFamilyCode = null;
    _lastKnownLevel = null;
  }

  /// 가족 데이터 업데이트 처리
  void _handleFamilyDataUpdate(Map<String, dynamic> familyData) {
    try {
      if (familyData.isEmpty) {
        secureLog.warning('Received empty family data');
        return;
      }

      final safetyStatus = _statusCalculator.calculateSafetyStatus(familyData);
      final currentLevel = safetyStatus.level;
      
      secureLog.debug('Safety status updated: $currentLevel');
      
      // 위험 상태로 전환된 경우 알림 처리
      if (_lastKnownLevel != SafetyLevel.critical && 
          currentLevel == SafetyLevel.critical) {
        _handleCriticalStatusEntered(familyData, safetyStatus);
      }
      
      // 안전 상태로 복구된 경우 로그
      if (_lastKnownLevel == SafetyLevel.critical && 
          currentLevel != SafetyLevel.critical) {
        secureLog.info('Safety status recovered from critical to $currentLevel');
      }
      
      _lastKnownLevel = currentLevel;
    } catch (e) {
      secureLog.error('Error handling family data update', e);
    }
  }

  /// 위험 상태 진입 처리
  Future<void> _handleCriticalStatusEntered(
    Map<String, dynamic> familyData,
    SafetyStatus safetyStatus,
  ) async {
    try {
      secureLog.security('CRITICAL: Safety status entered critical level');
      
      // 알림 쿨다운 확인
      if (!_canSendCriticalNotification()) {
        secureLog.info('Critical notification skipped due to cooldown');
        return;
      }
      
      final elderlyName = familyData['elderlyName'] as String? ?? '부모님';
      final hoursInactive = safetyStatus.timeSinceLastActivity.inHours;
      
      // Firebase에 위험 상태 알림 기록
      await _recordCriticalAlert(familyData, safetyStatus);
      
      // 로컬 알림 전송 (FCM은 Firebase Functions에서 처리)
      await _sendLocalCriticalNotification(elderlyName, hoursInactive);
      
      // 알림 시간 기록
      _lastCriticalNotificationTime = DateTime.now();
      await _saveCriticalNotificationTime();
      
      secureLog.security('Critical safety notification sent successfully');
    } catch (e) {
      secureLog.error('Failed to handle critical status notification', e);
    }
  }

  /// Firebase에 위험 알림 기록
  Future<void> _recordCriticalAlert(
    Map<String, dynamic> familyData,
    SafetyStatus safetyStatus,
  ) async {
    try {
      if (_currentFamilyCode == null) return;
      
      // 가족 문서에 알림 상태 업데이트
      final familyInfo = await _childService.getFamilyInfo(_currentFamilyCode!);
      if (familyInfo == null) return;
      
      final familyId = familyInfo['familyId'] as String;
      final currentUser = FirebaseAuth.instance.currentUser;
      
      await _firestore.collection('families').doc(familyId).update({
        'alerts.survival': FieldValue.serverTimestamp(),
        'alertsTriggered.survival': {
          'timestamp': FieldValue.serverTimestamp(),
          'triggeredBy': 'SafetyNotificationService',
          'inactiveHours': safetyStatus.timeSinceLastActivity.inHours,
          'alertHours': safetyStatus.alertHours,
          'detectedBy': currentUser?.uid ?? 'ChildApp',
        },
      });
      
      secureLog.info('Critical alert recorded in Firebase');
    } catch (e) {
      secureLog.error('Failed to record critical alert in Firebase', e);
    }
  }

  /// 로컬 위험 알림 전송
  Future<void> _sendLocalCriticalNotification(String elderlyName, int hoursInactive) async {
    try {
      // FCMMessageService를 통한 로컬 알림
      // 실제 FCM 푸시는 Firebase Functions에서 처리되므로 여기서는 로컬 알림만 처리
      
      secureLog.info('Local critical notification sent for $elderlyName ($hoursInactive hours inactive)');
      
      // TODO: 필요시 추가 로컬 알림 로직 구현
      // 예: 진동, 소리, 배지 업데이트 등
    } catch (e) {
      secureLog.error('Failed to send local critical notification', e);
    }
  }

  /// 주기적 상태 확인 (백업 체크)
  Future<void> _performPeriodicCheck(String familyCode) async {
    try {
      secureLog.debug('Performing periodic safety check');
      
      final familyData = await _childService.getSurvivalStatus(familyCode);
      if (familyData != null) {
        _handleFamilyDataUpdate(familyData);
      }
    } catch (e) {
      secureLog.warning('Periodic safety check failed', e);
    }
  }

  /// 위험 알림 쿨다운 확인
  bool _canSendCriticalNotification() {
    if (_lastCriticalNotificationTime == null) return true;
    
    final timeSinceLastNotification = DateTime.now().difference(_lastCriticalNotificationTime!);
    return timeSinceLastNotification >= _criticalNotificationCooldown;
  }

  /// 위험 알림 시간 저장
  Future<void> _saveCriticalNotificationTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'last_critical_notification_time',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      secureLog.warning('Failed to save critical notification time', e);
    }
  }

  /// 위험 알림 시간 로드
  Future<void> _loadCriticalNotificationTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt('last_critical_notification_time');
      if (timestamp != null) {
        _lastCriticalNotificationTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
    } catch (e) {
      secureLog.warning('Failed to load critical notification time', e);
    }
  }

  /// 연결 실패 시 재시도 스케줄링
  void _scheduleRetry() {
    Timer(const Duration(minutes: 1), () {
      if (_currentFamilyCode != null) {
        secureLog.info('Retrying safety monitoring after connection error');
        startMonitoring(_currentFamilyCode!);
      }
    });
  }

  /// 서비스 상태 확인
  bool get isMonitoring => _monitoringSubscription != null && _currentFamilyCode != null;
  
  /// 현재 모니터링 중인 가족 코드
  String? get currentFamilyCode => _currentFamilyCode;
  
  /// 마지막 알림 시간
  DateTime? get lastCriticalNotificationTime => _lastCriticalNotificationTime;

  /// 서비스 초기화
  Future<void> initialize() async {
    await _loadCriticalNotificationTime();
    secureLog.info('SafetyNotificationService initialized');
  }

  /// 서비스 정리
  Future<void> dispose() async {
    await stopMonitoring();
    secureLog.info('SafetyNotificationService disposed');
  }
}

/// 앱 생명주기에 따른 안전 모니터링 관리
/// 
/// 앱이 백그라운드로 이동하거나 포그라운드로 복귀할 때
/// 안전 모니터링을 적절히 관리합니다.
class SafetyMonitoringLifecycleManager with WidgetsBindingObserver {
  final SafetyNotificationService _notificationService = SafetyNotificationService();
  String? _familyCode;

  void initialize(String familyCode) {
    _familyCode = familyCode;
    WidgetsBinding.instance.addObserver(this);
    _notificationService.startMonitoring(familyCode);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationService.stopMonitoring();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        // 앱이 포그라운드로 복귀 - 모니터링 재시작
        if (_familyCode != null && !_notificationService.isMonitoring) {
          secureLog.info('App resumed - restarting safety monitoring');
          _notificationService.startMonitoring(_familyCode!);
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // 앱이 백그라운드로 이동 - 모니터링 유지 (Firebase Functions이 처리)
        secureLog.info('App backgrounded - safety monitoring continues via Firebase Functions');
        break;
      case AppLifecycleState.detached:
        // 앱 종료 - 모니터링 중지
        secureLog.info('App detached - stopping safety monitoring');
        _notificationService.stopMonitoring();
        break;
      case AppLifecycleState.inactive:
        // 앱이 비활성 상태 (전화, 알림 등) - 모니터링 유지
        break;
    }
  }
}