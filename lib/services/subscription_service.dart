import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/subscription_model.dart';
import 'firebase_service.dart';

/// Google Play 구독 관리 서비스
/// 
/// 주요 기능:
/// - 구독 상품 정보 가져오기
/// - 무료 체험 시작
/// - 구독 상태 확인 및 동기화
/// - Firebase와 로컬 저장소 연동
class SubscriptionService {
  static final SubscriptionService _instance = SubscriptionService._internal();
  factory SubscriptionService() => _instance;
  SubscriptionService._internal();

  // Google Play Console 설정값
  static const String productId = 'premium_monthly_1500';
  static const String basePlanId = 'monthly-base';
  static const String offerId = 'trial-7-days';
  
  // 내부 상태 관리
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  
  // 현재 구독 정보
  SubscriptionInfo? _currentSubscription;
  final _subscriptionController = StreamController<SubscriptionInfo>.broadcast();
  
  bool _isInitialized = false;
  bool _isProcessingPurchase = false;

  /// 구독 정보 스트림
  Stream<SubscriptionInfo> get subscriptionStream => _subscriptionController.stream;

  /// 현재 구독 정보
  SubscriptionInfo? get currentSubscription => _currentSubscription;

  /// 서비스 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      print('🔔 구독 서비스 초기화 시작...');
      
      // In-app purchase 사용 가능 여부 확인
      final bool available = await _inAppPurchase.isAvailable();
      if (!available) {
        print('❌ In-app purchase가 사용 불가능합니다.');
        _currentSubscription = SubscriptionInfo.defaultState();
        _subscriptionController.add(_currentSubscription!);
        return;
      }

      // 구매 업데이트 리스너 설정
      _subscription = _inAppPurchase.purchaseStream.listen(
        _onPurchaseUpdate,
        onDone: () => print('구매 스트림 종료'),
        onError: (error) => print('구매 스트림 오류: $error'),
      );

      // 저장된 구독 정보 로드
      await _loadSubscriptionInfo();
      
      // 구독 상태 동기화
      await _syncSubscriptionStatus();

      _isInitialized = true;
      print('✅ 구독 서비스 초기화 완료');
    } catch (e) {
      print('❌ 구독 서비스 초기화 실패: $e');
      _currentSubscription = SubscriptionInfo.defaultState();
      _subscriptionController.add(_currentSubscription!);
    }
  }

  /// 구독 상품 정보 가져오기
  Future<ProductDetails?> getProductDetails() async {
    try {
      final Set<String> productIds = {productId};
      final ProductDetailsResponse response = await _inAppPurchase.queryProductDetails(productIds);
      
      if (response.error != null) {
        print('❌ 상품 정보 조회 실패: ${response.error}');
        return null;
      }

      if (response.productDetails.isEmpty) {
        print('❌ 상품을 찾을 수 없습니다: $productId');
        return null;
      }

      final ProductDetails product = response.productDetails.first;
      print('✅ 상품 정보 조회 성공: ${product.title} - ${product.price}');
      return product;
    } catch (e) {
      print('❌ 상품 정보 조회 중 오류: $e');
      return null;
    }
  }

  /// 무료 체험 시작
  Future<bool> startFreeTrial() async {
    if (_isProcessingPurchase) {
      print('⚠️ 이미 구매 처리 중입니다.');
      return false;
    }

    try {
      _isProcessingPurchase = true;
      print('🆓 무료 체험 시작 시도...');

      // 구독 상품 정보 가져오기
      final ProductDetails? product = await getProductDetails();
      if (product == null) {
        print('❌ 상품 정보를 가져올 수 없습니다.');
        return false;
      }

      // 구매 매개변수 설정 (무료 체험 포함)
      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: product,
        applicationUserName: FirebaseAuth.instance.currentUser?.uid,
      );

      // 구독 시작
      final bool success = await _inAppPurchase.buyNonConsumable(
        purchaseParam: purchaseParam,
      );

      if (!success) {
        print('❌ 구독 시작 실패');
        return false;
      }

      print('✅ 구독 요청 전송 완료');
      return true;
    } catch (e) {
      print('❌ 무료 체험 시작 중 오류: $e');
      return false;
    } finally {
      _isProcessingPurchase = false;
    }
  }

  /// 구독 복원 (기존 구매 내역 확인)
  Future<void> restorePurchases() async {
    try {
      print('🔄 구독 복원 시작...');
      await _inAppPurchase.restorePurchases();
      await _syncSubscriptionStatus();
      print('✅ 구독 복원 완료');
    } catch (e) {
      print('❌ 구독 복원 중 오류: $e');
    }
  }

  /// 구독 취소 (Google Play로 리디렉션)
  Future<void> cancelSubscription() async {
    try {
      print('🚫 구독 취소 안내');
      // Google Play 구독 관리 페이지로 안내하는 로직
      // 실제 취소는 Google Play에서만 가능
    } catch (e) {
      print('❌ 구독 취소 중 오류: $e');
    }
  }

  /// 구매 업데이트 처리
  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) async {
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      print('🔔 구매 업데이트: ${purchaseDetails.status}');
      
      switch (purchaseDetails.status) {
        case PurchaseStatus.pending:
          await _handlePendingPurchase(purchaseDetails);
          break;
        case PurchaseStatus.purchased:
          await _handleSuccessfulPurchase(purchaseDetails);
          break;
        case PurchaseStatus.error:
          await _handlePurchaseError(purchaseDetails);
          break;
        case PurchaseStatus.canceled:
          await _handlePurchaseCanceled(purchaseDetails);
          break;
        case PurchaseStatus.restored:
          await _handleRestoredPurchase(purchaseDetails);
          break;
      }

      // Android에서는 구매 완료 처리가 필요
      if (purchaseDetails.pendingCompletePurchase && Platform.isAndroid) {
        await _inAppPurchase.completePurchase(purchaseDetails);
      }
    }
  }

  /// 대기 중인 구매 처리
  Future<void> _handlePendingPurchase(PurchaseDetails purchaseDetails) async {
    print('⏳ 구매 대기 중...');
    
    if (_currentSubscription != null) {
      _currentSubscription = _currentSubscription!.copyWith(
        status: SubscriptionStatus.pending,
        lastUpdated: DateTime.now(),
      );
      await _saveSubscriptionInfo();
      _subscriptionController.add(_currentSubscription!);
    }
  }

  /// 성공한 구매 처리
  Future<void> _handleSuccessfulPurchase(PurchaseDetails purchaseDetails) async {
    try {
      print('✅ 구매 성공!');
      
      // 구매 검증 (서버 사이드에서 하는 것이 좋지만, 간단한 예시로 클라이언트에서 처리)
      final bool isValid = await _verifyPurchase(purchaseDetails);
      if (!isValid) {
        print('❌ 구매 검증 실패');
        return;
      }

      // 체험 기간 계산 (7일)
      final DateTime now = DateTime.now();
      final DateTime trialEnd = now.add(const Duration(days: 7));
      
      // 구독 정보 업데이트
      _currentSubscription = SubscriptionInfo.startFreeTrial(
        subscriptionId: purchaseDetails.purchaseID ?? '',
        trialStartDate: now,
        trialEndDate: trialEnd,
      );

      await _saveSubscriptionInfo();
      _subscriptionController.add(_currentSubscription!);
      
      // 이벤트 로깅
      await _logSubscriptionEvent('trial_started', {
        'purchaseId': purchaseDetails.purchaseID,
        'productId': purchaseDetails.productID,
        'trialEndDate': trialEnd.toIso8601String(),
      });
      
      print('✅ 무료 체험 시작됨: $trialEnd까지');
    } catch (e) {
      print('❌ 구매 처리 중 오류: $e');
    }
  }

  /// 구매 오류 처리
  Future<void> _handlePurchaseError(PurchaseDetails purchaseDetails) async {
    print('❌ 구매 실패: ${purchaseDetails.error}');
    
    await _logSubscriptionEvent('purchase_error', {
      'error': purchaseDetails.error?.message,
      'code': purchaseDetails.error?.code,
      'productId': purchaseDetails.productID,
    });
  }

  /// 구매 취소 처리
  Future<void> _handlePurchaseCanceled(PurchaseDetails purchaseDetails) async {
    print('🚫 구매 취소됨');
    
    await _logSubscriptionEvent('purchase_canceled', {
      'productId': purchaseDetails.productID,
    });
  }

  /// 복원된 구매 처리
  Future<void> _handleRestoredPurchase(PurchaseDetails purchaseDetails) async {
    print('🔄 구매 복원됨');
    await _handleSuccessfulPurchase(purchaseDetails);
  }

  /// 구매 검증 (간단한 클라이언트 사이드 검증)
  Future<bool> _verifyPurchase(PurchaseDetails purchaseDetails) async {
    try {
      // 실제 서비스에서는 서버에서 Google Play 영수증 검증을 해야 함
      // 여기서는 간단한 클라이언트 사이드 검증만 수행
      
      return purchaseDetails.purchaseID != null && 
             purchaseDetails.purchaseID!.isNotEmpty &&
             purchaseDetails.productID == productId;
    } catch (e) {
      print('❌ 구매 검증 중 오류: $e');
      return false;
    }
  }

  /// Firebase에서 구독 정보 로드
  Future<void> _loadSubscriptionInfo() async {
    try {
      final SubscriptionInfo? subscriptionInfo = await FirebaseService.getSubscriptionInfo();
      
      if (subscriptionInfo != null) {
        _currentSubscription = subscriptionInfo;
        print('✅ Firebase에서 구독 정보 로드: ${_currentSubscription!.status}');
      } else {
        _currentSubscription = SubscriptionInfo.defaultState();
        print('ℹ️ 저장된 구독 정보 없음, 기본 상태로 설정');
      }

      _subscriptionController.add(_currentSubscription!);
    } catch (e) {
      print('❌ 구독 정보 로드 실패: $e');
      _currentSubscription = SubscriptionInfo.defaultState();
      _subscriptionController.add(_currentSubscription!);
    }
  }

  /// Firebase에 구독 정보 저장
  Future<void> _saveSubscriptionInfo() async {
    try {
      if (_currentSubscription == null) {
        print('⚠️ 구독 정보가 없음');
        return;
      }

      final bool success = await FirebaseService.saveSubscriptionInfo(_currentSubscription!);
      
      if (success) {
        // 로컬 캐시에도 저장
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('subscription_status', _currentSubscription!.status.name);
        await prefs.setString('last_updated', _currentSubscription!.lastUpdated.toIso8601String());
        
        print('✅ 구독 정보 저장 완료');
      }
    } catch (e) {
      print('❌ 구독 정보 저장 실패: $e');
    }
  }

  /// Google Play와 구독 상태 동기화
  Future<void> _syncSubscriptionStatus() async {
    try {
      print('🔄 Google Play와 구독 상태 동기화...');
      
      // 현재 구매 내역 조회
      await _inAppPurchase.restorePurchases();
      
      // 구독 상태 업데이트
      if (_currentSubscription != null) {
        final DateTime now = DateTime.now();
        bool needsUpdate = false;
        
        // 체험 기간 만료 체크
        if (_currentSubscription!.status == SubscriptionStatus.freeTrial &&
            _currentSubscription!.trialEndDate != null &&
            now.isAfter(_currentSubscription!.trialEndDate!)) {
          print('⏰ 무료 체험 기간 만료');
          _currentSubscription = _currentSubscription!.copyWith(
            status: SubscriptionStatus.expired,
            lastUpdated: now,
          );
          needsUpdate = true;
        }
        
        // 구독 만료 체크
        if (_currentSubscription!.status == SubscriptionStatus.active &&
            _currentSubscription!.expiryDate != null &&
            now.isAfter(_currentSubscription!.expiryDate!)) {
          print('⏰ 구독 기간 만료');
          _currentSubscription = _currentSubscription!.copyWith(
            status: SubscriptionStatus.expired,
            lastUpdated: now,
          );
          needsUpdate = true;
        }
        
        if (needsUpdate) {
          await _saveSubscriptionInfo();
          _subscriptionController.add(_currentSubscription!);
        }
      }
      
      print('✅ 구독 상태 동기화 완료');
    } catch (e) {
      print('❌ 구독 상태 동기화 실패: $e');
    }
  }

  /// 구독 이벤트 로깅
  Future<void> _logSubscriptionEvent(String eventType, Map<String, dynamic> data) async {
    try {
      final SubscriptionEvent event = SubscriptionEvent(
        eventType: eventType,
        timestamp: DateTime.now(),
        data: data,
      );

      await FirebaseService.logSubscriptionEvent(event);
    } catch (e) {
      print('❌ 구독 이벤트 로깅 실패: $e');
    }
  }

  /// 서비스 정리
  void dispose() {
    _subscription.cancel();
    _subscriptionController.close();
    _isInitialized = false;
  }

  /// 구독 상태 강제 새로고침
  Future<void> refresh() async {
    await _syncSubscriptionStatus();
  }

  /// 빠른 구독 상태 체크 (로컬 캐시 사용)
  Future<bool> quickPremiumCheck() async {
    try {
      if (_currentSubscription?.canUsePremiumFeatures == true) {
        return true;
      }

      // 로컬 캐시 체크
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? statusString = prefs.getString('subscription_status');
      final String? lastUpdatedString = prefs.getString('last_updated');
      
      if (statusString != null && lastUpdatedString != null) {
        final SubscriptionStatus status = SubscriptionStatus.values.firstWhere(
          (s) => s.name == statusString,
          orElse: () => SubscriptionStatus.neverSubscribed,
        );
        
        final DateTime lastUpdated = DateTime.parse(lastUpdatedString);
        
        // 캐시가 24시간 이내인 경우만 신뢰
        if (DateTime.now().difference(lastUpdated).inHours < 24) {
          return status == SubscriptionStatus.active || 
                 status == SubscriptionStatus.freeTrial;
        }
      }

      return false;
    } catch (e) {
      print('❌ 빠른 프리미엄 체크 실패: $e');
      return false;
    }
  }
}