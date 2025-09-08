import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/subscription_model.dart';
import '../services/subscription_service.dart';
import '../services/firebase_service.dart';
import '../widgets/subscription_popup.dart';

/// 구독 수명주기를 관리하는 통합 매니저
/// 
/// 주요 역할:
/// - 앱 전체에서 구독 상태 관리
/// - 자동 갱신 및 만료 처리
/// - 팝업 표시 로직 관리
/// - 프리미엄 기능 접근 제어
class SubscriptionManager {
  static final SubscriptionManager _instance = SubscriptionManager._internal();
  factory SubscriptionManager() => _instance;
  SubscriptionManager._internal();

  // 서비스 인스턴스
  final SubscriptionService _subscriptionService = SubscriptionService();
  
  // 상태 관리
  SubscriptionInfo? _currentSubscription;
  Timer? _backgroundSyncTimer;
  Timer? _popupDelayTimer;
  bool _isInitialized = false;
  
  // 팝업 관리
  bool _popupCurrentlyShown = false;
  DateTime? _lastPopupShownTime;
  static const Duration _popupCooldownDuration = Duration(hours: 4);
  
  // 스트림 컨트롤러
  final StreamController<SubscriptionInfo> _subscriptionController = 
      StreamController<SubscriptionInfo>.broadcast();

  /// 현재 구독 정보
  SubscriptionInfo? get currentSubscription => _currentSubscription;
  
  /// 구독 상태 스트림
  Stream<SubscriptionInfo> get subscriptionStream => _subscriptionController.stream;
  
  /// 프리미엄 기능 사용 가능 여부
  bool get canUsePremiumFeatures => 
      _currentSubscription?.canUsePremiumFeatures ?? false;

  /// 매니저 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      print('🔄 구독 매니저 초기화 시작...');
      
      // 구독 서비스 초기화
      await _subscriptionService.initialize();
      
      // 구독 상태 리스너 설정
      _subscriptionService.subscriptionStream.listen(_onSubscriptionUpdate);
      
      // 현재 구독 정보 로드
      _currentSubscription = _subscriptionService.currentSubscription;
      if (_currentSubscription != null) {
        _subscriptionController.add(_currentSubscription!);
      }
      
      // 백그라운드 동기화 타이머 시작
      _startBackgroundSync();
      
      // 팝업 표시 이력 로드
      await _loadPopupHistory();
      
      _isInitialized = true;
      print('✅ 구독 매니저 초기화 완료');
    } catch (e) {
      print('❌ 구독 매니저 초기화 실패: $e');
    }
  }

  /// 구독 상태 업데이트 처리
  void _onSubscriptionUpdate(SubscriptionInfo subscriptionInfo) {
    _currentSubscription = subscriptionInfo;
    _subscriptionController.add(subscriptionInfo);
    
    // 구독 상태가 만료되면 팝업 표시 허용
    if (!subscriptionInfo.canUsePremiumFeatures) {
      _resetPopupCooldown();
    }
    
    print('🔄 구독 상태 업데이트: ${subscriptionInfo.status}');
  }

  /// 백그라운드 동기화 시작
  void _startBackgroundSync() {
    // 30분마다 구독 상태 동기화
    _backgroundSyncTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => _syncSubscriptionStatus(),
    );
    
    print('✅ 백그라운드 구독 동기화 시작 (30분 간격)');
  }

  /// 구독 상태 동기화
  Future<void> _syncSubscriptionStatus() async {
    try {
      print('🔄 구독 상태 동기화 중...');
      await _subscriptionService.refresh();
    } catch (e) {
      print('❌ 구독 상태 동기화 실패: $e');
    }
  }

  /// 팝업 표시 이력 로드
  Future<void> _loadPopupHistory() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? lastPopupTimeString = prefs.getString('last_popup_shown_time');
      
      if (lastPopupTimeString != null) {
        _lastPopupShownTime = DateTime.parse(lastPopupTimeString);
        print('ℹ️ 마지막 팝업 표시 시간: $_lastPopupShownTime');
      }
    } catch (e) {
      print('❌ 팝업 이력 로드 실패: $e');
    }
  }

  /// 팝업 표시 이력 저장
  Future<void> _savePopupHistory() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (_lastPopupShownTime != null) {
        await prefs.setString(
          'last_popup_shown_time',
          _lastPopupShownTime!.toIso8601String(),
        );
      }
    } catch (e) {
      print('❌ 팝업 이력 저장 실패: $e');
    }
  }

  /// 팝업 쿨다운 리셋
  void _resetPopupCooldown() {
    _lastPopupShownTime = null;
    _savePopupHistory();
    print('🔄 팝업 쿨다운 리셋');
  }

  /// 구독 팝업 표시 가능 여부 확인
  bool _canShowSubscriptionPopup() {
    // 이미 프리미엄 사용자면 팝업 안함
    if (canUsePremiumFeatures) {
      return false;
    }
    
    // 현재 팝업이 표시 중이면 안함
    if (_popupCurrentlyShown) {
      return false;
    }
    
    // 쿨다운 시간 확인
    if (_lastPopupShownTime != null) {
      final Duration timeSinceLastPopup = 
          DateTime.now().difference(_lastPopupShownTime!);
      if (timeSinceLastPopup < _popupCooldownDuration) {
        // 쿨다운 중일 때는 조용히 false 반환 (로그 제거)
        return false;
      }
    }
    
    return true;
  }

  /// 구독 팝업 표시 (지연 처리 포함)
  Future<void> showSubscriptionPopupWithDelay(
    BuildContext context, {
    Duration delay = const Duration(seconds: 3),
  }) async {
    if (!_canShowSubscriptionPopup()) {
      return;
    }
    
    print('⏳ 구독 팝업 지연 표시 시작: ${delay.inSeconds}초 후');
    
    // 기존 타이머 취소
    _popupDelayTimer?.cancel();
    
    // 지연 후 팝업 표시
    _popupDelayTimer = Timer(delay, () {
      if (context.mounted && _canShowSubscriptionPopup()) {
        _showSubscriptionPopup(context);
      }
    });
  }

  /// 구독 팝업 즉시 표시
  Future<void> showSubscriptionPopupNow(BuildContext context) async {
    if (!_canShowSubscriptionPopup()) {
      return;
    }
    
    _showSubscriptionPopup(context);
  }

  /// 구독 팝업 실제 표시
  void _showSubscriptionPopup(BuildContext context) {
    if (_popupCurrentlyShown) return;
    
    _popupCurrentlyShown = true;
    _lastPopupShownTime = DateTime.now();
    _savePopupHistory();
    
    print('📱 구독 팝업 표시');
    
    SubscriptionPopup.show(
      context,
      onDismiss: () {
        _popupCurrentlyShown = false;
        print('📱 구독 팝업 닫힘');
      },
      onSubscriptionStarted: () {
        _popupCurrentlyShown = false;
        print('✅ 구독 시작됨');
      },
    );
  }

  /// 무료 체험 시작
  Future<bool> startFreeTrial() async {
    try {
      print('🆓 무료 체험 시작 요청');
      final bool success = await _subscriptionService.startFreeTrial();
      
      if (success) {
        // 팝업 쿨다운 리셋 (구독 시작했으므로)
        _resetPopupCooldown();
      }
      
      return success;
    } catch (e) {
      print('❌ 무료 체험 시작 실패: $e');
      return false;
    }
  }

  /// 구독 복원
  Future<void> restorePurchases() async {
    try {
      print('🔄 구독 복원 시작');
      await _subscriptionService.restorePurchases();
    } catch (e) {
      print('❌ 구독 복원 실패: $e');
    }
  }

  /// 프리미엄 기능 접근 확인
  bool checkPremiumAccess({
    BuildContext? context,
    bool showPopupIfNotSubscribed = false,
  }) {
    final bool hasAccess = canUsePremiumFeatures;
    
    if (!hasAccess && showPopupIfNotSubscribed && context != null) {
      showSubscriptionPopupNow(context);
    }
    
    return hasAccess;
  }

  /// 구독 상태 문자열 (UI 표시용)
  String getSubscriptionStatusText() {
    if (_currentSubscription == null) {
      return '구독 정보 로딩 중...';
    }
    
    return _currentSubscription!.statusDescription;
  }

  /// 구독 만료까지 남은 일수
  int getDaysUntilExpiry() {
    if (_currentSubscription == null) return 0;
    
    if (_currentSubscription!.isInFreeTrial) {
      return _currentSubscription!.daysUntilTrialExpiry;
    } else {
      return _currentSubscription!.daysUntilExpiry;
    }
  }

  /// 구독 가격 정보
  String getPricingText() {
    return '월 1,500원 (하루 50원)';
  }

  /// 앱 시작 시 초기화 및 팝업 스케줄링
  Future<void> handleAppLaunch(BuildContext context) async {
    await initialize();
    
    // 앱 로드 완료 후 팝업 표시 검토
    showSubscriptionPopupWithDelay(
      context,
      delay: const Duration(seconds: 5),
    );
  }

  /// 특정 기능 사용 시 프리미엄 체크
  bool requiresPremium(
    String featureName, {
    BuildContext? context,
    bool showErrorMessage = true,
  }) {
    final bool hasAccess = canUsePremiumFeatures;
    
    if (!hasAccess) {
      print('🔒 프리미엄 기능 접근 차단: $featureName');
      
      if (context != null) {
        if (showErrorMessage) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$featureName은(는) 프리미엄 기능입니다'),
              action: SnackBarAction(
                label: '구독하기',
                onPressed: () => showSubscriptionPopupNow(context),
              ),
            ),
          );
        } else {
          showSubscriptionPopupNow(context);
        }
      }
    }
    
    return hasAccess;
  }

  /// 구독 관련 통계 수집
  Future<Map<String, dynamic>> getUsageStats() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final int popupShownCount = prefs.getInt('popup_shown_count') ?? 0;
      final int premiumFeatureAttempts = prefs.getInt('premium_attempts') ?? 0;
      
      return {
        'subscription_status': _currentSubscription?.status.name ?? 'unknown',
        'can_use_premium': canUsePremiumFeatures,
        'popup_shown_count': popupShownCount,
        'premium_feature_attempts': premiumFeatureAttempts,
        'last_popup_time': _lastPopupShownTime?.toIso8601String(),
        'days_until_expiry': getDaysUntilExpiry(),
      };
    } catch (e) {
      print('❌ 사용 통계 수집 실패: $e');
      return {};
    }
  }

  /// 정리 작업
  void dispose() {
    _backgroundSyncTimer?.cancel();
    _popupDelayTimer?.cancel();
    _subscriptionController.close();
    _subscriptionService.dispose();
    _isInitialized = false;
  }

  /// 디버그 정보 출력
  void debugPrint() {
    print('=== 구독 매니저 디버그 정보 ===');
    print('초기화됨: $_isInitialized');
    print('현재 구독: ${_currentSubscription?.status}');
    print('프리미엄 사용 가능: $canUsePremiumFeatures');
    print('팝업 표시 중: $_popupCurrentlyShown');
    print('마지막 팝업 시간: $_lastPopupShownTime');
    print('팝업 표시 가능: ${_canShowSubscriptionPopup()}');
    print('===========================');
  }
}