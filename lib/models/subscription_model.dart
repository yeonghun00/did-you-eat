import 'package:cloud_firestore/cloud_firestore.dart';

/// 구독 상태를 나타내는 열거형
enum SubscriptionStatus {
  /// 구독한 적 없음
  neverSubscribed,
  /// 무료 체험 중
  freeTrial,
  /// 활성 구독 중
  active,
  /// 구독 만료됨
  expired,
  /// 구독 취소됨 (기간 남음)
  cancelled,
  /// 구독 대기 중 (결제 문제 등)
  pending,
}

/// 구독 정보를 관리하는 모델 클래스
class SubscriptionInfo {
  /// 구독 ID (Google Play의 구독 ID)
  final String? subscriptionId;
  
  /// 제품 ID (premium_monthly_1500)
  final String? productId;
  
  /// 현재 구독 상태
  final SubscriptionStatus status;
  
  /// 구독 시작일
  final DateTime? startDate;
  
  /// 구독 만료일
  final DateTime? expiryDate;
  
  /// 체험 기간 시작일
  final DateTime? trialStartDate;
  
  /// 체험 기간 만료일
  final DateTime? trialEndDate;
  
  /// 자동 갱신 여부
  final bool autoRenewing;
  
  /// 구독 취소일 (취소된 경우)
  final DateTime? cancelledDate;
  
  /// 마지막 업데이트 시간
  final DateTime lastUpdated;
  
  /// 가격 (원화, 1500)
  final int price;
  
  /// 통화 코드 (KRW)
  final String currency;

  const SubscriptionInfo({
    this.subscriptionId,
    this.productId,
    required this.status,
    this.startDate,
    this.expiryDate,
    this.trialStartDate,
    this.trialEndDate,
    this.autoRenewing = false,
    this.cancelledDate,
    required this.lastUpdated,
    this.price = 1500,
    this.currency = 'KRW',
  });

  /// 무료 체험 사용 가능한지 확인
  bool get canStartFreeTrial {
    return status == SubscriptionStatus.neverSubscribed && 
           trialStartDate == null;
  }

  /// 현재 무료 체험 중인지 확인
  bool get isInFreeTrial {
    if (status != SubscriptionStatus.freeTrial || trialEndDate == null) {
      return false;
    }
    return DateTime.now().isBefore(trialEndDate!);
  }

  /// 구독이 활성 상태인지 확인 (체험 포함)
  bool get isActive {
    final now = DateTime.now();
    
    switch (status) {
      case SubscriptionStatus.active:
        return expiryDate == null || now.isBefore(expiryDate!);
      case SubscriptionStatus.freeTrial:
        return trialEndDate != null && now.isBefore(trialEndDate!);
      case SubscriptionStatus.cancelled:
        return expiryDate != null && now.isBefore(expiryDate!);
      default:
        return false;
    }
  }

  /// 프리미엄 기능 사용 가능한지 확인
  bool get canUsePremiumFeatures {
    return isActive;
  }

  /// 체험 만료까지 남은 일수
  int get daysUntilTrialExpiry {
    if (!isInFreeTrial || trialEndDate == null) return 0;
    return trialEndDate!.difference(DateTime.now()).inDays;
  }

  /// 구독 만료까지 남은 일수
  int get daysUntilExpiry {
    if (!isActive || expiryDate == null) return 0;
    return expiryDate!.difference(DateTime.now()).inDays;
  }

  /// 구독 상태 한국어 설명
  String get statusDescription {
    switch (status) {
      case SubscriptionStatus.neverSubscribed:
        return '구독하지 않음';
      case SubscriptionStatus.freeTrial:
        if (isInFreeTrial) {
          return '무료 체험 중 ($daysUntilTrialExpiry일 남음)';
        } else {
          return '무료 체험 만료됨';
        }
      case SubscriptionStatus.active:
        return '프리미엄 구독 중';
      case SubscriptionStatus.expired:
        return '구독 만료됨';
      case SubscriptionStatus.cancelled:
        if (isActive) {
          return '구독 취소됨 ($daysUntilExpiry일 남음)';
        } else {
          return '구독 취소됨';
        }
      case SubscriptionStatus.pending:
        return '구독 처리 중';
    }
  }

  /// Firestore 저장용 Map 변환
  Map<String, dynamic> toFirestore() {
    return {
      'subscriptionId': subscriptionId,
      'productId': productId,
      'status': status.name,
      'startDate': startDate?.toIso8601String(),
      'expiryDate': expiryDate?.toIso8601String(),
      'trialStartDate': trialStartDate?.toIso8601String(),
      'trialEndDate': trialEndDate?.toIso8601String(),
      'autoRenewing': autoRenewing,
      'cancelledDate': cancelledDate?.toIso8601String(),
      'lastUpdated': Timestamp.fromDate(lastUpdated),
      'price': price,
      'currency': currency,
    };
  }

  /// Firestore에서 객체 생성
  factory SubscriptionInfo.fromFirestore(Map<String, dynamic> data) {
    return SubscriptionInfo(
      subscriptionId: data['subscriptionId'],
      productId: data['productId'],
      status: SubscriptionStatus.values.firstWhere(
        (status) => status.name == data['status'],
        orElse: () => SubscriptionStatus.neverSubscribed,
      ),
      startDate: data['startDate'] != null 
          ? DateTime.parse(data['startDate']) 
          : null,
      expiryDate: data['expiryDate'] != null 
          ? DateTime.parse(data['expiryDate']) 
          : null,
      trialStartDate: data['trialStartDate'] != null 
          ? DateTime.parse(data['trialStartDate']) 
          : null,
      trialEndDate: data['trialEndDate'] != null 
          ? DateTime.parse(data['trialEndDate']) 
          : null,
      autoRenewing: data['autoRenewing'] ?? false,
      cancelledDate: data['cancelledDate'] != null 
          ? DateTime.parse(data['cancelledDate']) 
          : null,
      lastUpdated: data['lastUpdated'] is Timestamp
          ? (data['lastUpdated'] as Timestamp).toDate()
          : DateTime.now(),
      price: data['price'] ?? 1500,
      currency: data['currency'] ?? 'KRW',
    );
  }

  /// 기본 상태 (구독하지 않음)
  factory SubscriptionInfo.defaultState() {
    return SubscriptionInfo(
      status: SubscriptionStatus.neverSubscribed,
      lastUpdated: DateTime.now(),
    );
  }

  /// 무료 체험 시작 상태
  factory SubscriptionInfo.startFreeTrial({
    required String subscriptionId,
    required DateTime trialStartDate,
    required DateTime trialEndDate,
  }) {
    return SubscriptionInfo(
      subscriptionId: subscriptionId,
      productId: 'premium_monthly_1500',
      status: SubscriptionStatus.freeTrial,
      trialStartDate: trialStartDate,
      trialEndDate: trialEndDate,
      autoRenewing: true,
      lastUpdated: DateTime.now(),
    );
  }

  /// 복사본 생성 (일부 필드 수정)
  SubscriptionInfo copyWith({
    String? subscriptionId,
    String? productId,
    SubscriptionStatus? status,
    DateTime? startDate,
    DateTime? expiryDate,
    DateTime? trialStartDate,
    DateTime? trialEndDate,
    bool? autoRenewing,
    DateTime? cancelledDate,
    DateTime? lastUpdated,
    int? price,
    String? currency,
  }) {
    return SubscriptionInfo(
      subscriptionId: subscriptionId ?? this.subscriptionId,
      productId: productId ?? this.productId,
      status: status ?? this.status,
      startDate: startDate ?? this.startDate,
      expiryDate: expiryDate ?? this.expiryDate,
      trialStartDate: trialStartDate ?? this.trialStartDate,
      trialEndDate: trialEndDate ?? this.trialEndDate,
      autoRenewing: autoRenewing ?? this.autoRenewing,
      cancelledDate: cancelledDate ?? this.cancelledDate,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      price: price ?? this.price,
      currency: currency ?? this.currency,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubscriptionInfo &&
          runtimeType == other.runtimeType &&
          subscriptionId == other.subscriptionId &&
          status == other.status &&
          expiryDate == other.expiryDate &&
          trialEndDate == other.trialEndDate;

  @override
  int get hashCode =>
      subscriptionId.hashCode ^
      status.hashCode ^
      expiryDate.hashCode ^
      trialEndDate.hashCode;

  @override
  String toString() {
    return 'SubscriptionInfo('
        'subscriptionId: $subscriptionId, '
        'status: $status, '
        'isActive: $isActive, '
        'canUsePremium: $canUsePremiumFeatures'
        ')';
  }
}

/// 구독 이벤트를 나타내는 모델
class SubscriptionEvent {
  final String eventType;
  final DateTime timestamp;
  final Map<String, dynamic> data;

  const SubscriptionEvent({
    required this.eventType,
    required this.timestamp,
    required this.data,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'eventType': eventType,
      'timestamp': Timestamp.fromDate(timestamp),
      'data': data,
    };
  }

  factory SubscriptionEvent.fromFirestore(Map<String, dynamic> data) {
    return SubscriptionEvent(
      eventType: data['eventType'],
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      data: data['data'] ?? {},
    );
  }
}