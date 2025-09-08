import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/subscription_manager.dart';
import '../models/subscription_error_type.dart';

/// 구독 관련 에러 처리 및 사용자 피드백 위젯
class SubscriptionErrorHandler {
  static final SubscriptionManager _subscriptionManager = SubscriptionManager();

  /// 에러 메시지 매핑
  static String getErrorMessage(SubscriptionErrorType errorType) {
    switch (errorType) {
      case SubscriptionErrorType.networkError:
        return '인터넷 연결을 확인해 주세요.\n잠시 후 다시 시도하겠습니다.';
      case SubscriptionErrorType.paymentError:
        return '결제 처리 중 문제가 발생했습니다.\nGoogle Play 설정에서 결제 수단을 확인해주세요.';
      case SubscriptionErrorType.serviceUnavailable:
        return '서비스가 일시적으로 중단되었습니다.\n잠시 후 다시 이용해주세요.';
      case SubscriptionErrorType.userCancelled:
        return '사용자가 결제를 취소했습니다.';
      case SubscriptionErrorType.alreadySubscribed:
        return '이미 프리미엄 서비스를 이용 중입니다.\n설정에서 구독 상태를 확인해주세요.';
      case SubscriptionErrorType.invalidProduct:
        return '구독 상품 정보를 찾을 수 없습니다.\n앱을 다시 시작하거나 업데이트해주세요.';
      case SubscriptionErrorType.unknown:
        return '예상치 못한 문제가 발생했습니다.\n잠시 후 다시 시도해주세요.';
    }
  }

  /// 에러 아이콘 매핑
  static IconData _getErrorIcon(SubscriptionErrorType errorType) {
    switch (errorType) {
      case SubscriptionErrorType.networkError:
        return Icons.wifi_off;
      case SubscriptionErrorType.paymentError:
        return Icons.payment_outlined;
      case SubscriptionErrorType.serviceUnavailable:
        return Icons.cloud_off;
      case SubscriptionErrorType.userCancelled:
        return Icons.cancel_outlined;
      case SubscriptionErrorType.alreadySubscribed:
        return Icons.verified;
      case SubscriptionErrorType.invalidProduct:
        return Icons.shopping_cart_outlined;
      case SubscriptionErrorType.unknown:
        return Icons.error_outline;
    }
  }

  /// 스낵바로 에러 표시
  static void showErrorSnackBar(
    BuildContext context,
    SubscriptionErrorType errorType, {
    String? customMessage,
    bool showRetryButton = true,
    VoidCallback? onRetry,
  }) {
    final String message = customMessage ?? getErrorMessage(errorType);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              _getErrorIcon(errorType),
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.errorRed,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        action: showRetryButton && onRetry != null
            ? SnackBarAction(
                label: '다시 시도',
                textColor: Colors.white,
                onPressed: () {
                  HapticFeedback.lightImpact();
                  onRetry();
                },
              )
            : null,
      ),
    );
  }

  /// 다이얼로그로 에러 표시
  static Future<void> showErrorDialog(
    BuildContext context,
    SubscriptionErrorType errorType, {
    String? customMessage,
    String? title,
    bool showRetryButton = true,
    VoidCallback? onRetry,
    VoidCallback? onContactSupport,
  }) {
    final String message = customMessage ?? getErrorMessage(errorType);
    final String dialogTitle = title ?? '구독 오류';

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.errorRed.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getErrorIcon(errorType),
                  color: AppTheme.errorRed,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  dialogTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: AppTheme.textMedium,
                ),
              ),
              if (errorType == SubscriptionErrorType.paymentError) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.gray50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '해결 방법:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textDark,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '1. Google Play 앱 열기\n'
                        '2. 계정 설정 > 결제 및 구독\n'
                        '3. 결제 수단 확인 및 업데이트\n'
                        '4. 반복되면 Google 고객센터로 문의',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textMedium,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            if (onContactSupport != null)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onContactSupport();
                },
                child: const Text('문의하기'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
            if (showRetryButton && onRetry != null)
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  HapticFeedback.lightImpact();
                  onRetry();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('다시 시도'),
              ),
          ],
        );
      },
    );
  }

  /// 성공 메시지 표시
  static void showSuccessSnackBar(
    BuildContext context,
    String message, {
    IconData icon = Icons.check_circle,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.successGreen,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 프리미엄 기능 접근 차단 메시지
  static void showPremiumRequiredDialog(
    BuildContext context,
    String featureName, {
    VoidCallback? onSubscribe,
  }) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.warningAmber.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_outline,
                  color: AppTheme.warningAmber,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '프리미엄 기능',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$featureName은(는) 프리미엄 기능입니다.',
                style: const TextStyle(
                  fontSize: 16,
                  color: AppTheme.textMedium,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryBlue.withOpacity(0.1),
                      AppTheme.primaryBlue.withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🎉 7일 무료 체험',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '월 1,500원으로 모든 기능을 이용해보세요',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (onSubscribe != null) {
                  onSubscribe();
                } else {
                  _subscriptionManager.showSubscriptionPopupNow(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
              ),
              child: const Text('구독하기'),
            ),
          ],
        );
      },
    );
  }

  /// 로딩 표시
  static Widget buildLoadingIndicator({
    String message = '처리 중...',
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryBlue),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppTheme.textMedium,
            ),
          ),
        ],
      ),
    );
  }

  /// 에러로부터 에러 타입 추론
  static SubscriptionErrorType inferErrorType(dynamic error) {
    final String errorMessage = error.toString().toLowerCase();
    
    if (errorMessage.contains('network') || 
        errorMessage.contains('connection') ||
        errorMessage.contains('timeout')) {
      return SubscriptionErrorType.networkError;
    }
    
    if (errorMessage.contains('payment') ||
        errorMessage.contains('billing') ||
        errorMessage.contains('purchase')) {
      return SubscriptionErrorType.paymentError;
    }
    
    if (errorMessage.contains('service') ||
        errorMessage.contains('unavailable')) {
      return SubscriptionErrorType.serviceUnavailable;
    }
    
    if (errorMessage.contains('cancel')) {
      return SubscriptionErrorType.userCancelled;
    }
    
    if (errorMessage.contains('already') ||
        errorMessage.contains('exist')) {
      return SubscriptionErrorType.alreadySubscribed;
    }
    
    if (errorMessage.contains('product') ||
        errorMessage.contains('invalid')) {
      return SubscriptionErrorType.invalidProduct;
    }
    
    return SubscriptionErrorType.unknown;
  }
}