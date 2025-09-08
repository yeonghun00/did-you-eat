import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/colors.dart';
import '../services/subscription_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/subscription_popup.dart';

/// 구독 관리 설정 화면
/// 
/// 기능:
/// - 현재 구독 상태 표시
/// - 무료 체험 시작/관리
/// - 구독 복원
/// - 구독 취소 안내
/// - 구독 관련 FAQ
class SubscriptionSettingsScreen extends StatefulWidget {
  const SubscriptionSettingsScreen({super.key});

  @override
  State<SubscriptionSettingsScreen> createState() => _SubscriptionSettingsScreenState();
}

class _SubscriptionSettingsScreenState extends State<SubscriptionSettingsScreen> {
  final SubscriptionManager _subscriptionManager = SubscriptionManager();
  bool _isLoading = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initializeSubscription();
  }

  Future<void> _initializeSubscription() async {
    try {
      await _subscriptionManager.initialize();
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error initializing subscription: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _startFreeTrial() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    HapticFeedback.mediumImpact();

    try {
      final success = await _subscriptionManager.startFreeTrial();
      
      if (success && mounted) {
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 무료 체험이 시작되었습니다!'),
            backgroundColor: AppTheme.successGreen,
            duration: Duration(seconds: 3),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('무료 체험 시작에 실패했습니다. 다시 시도해주세요.'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    } catch (e) {
      print('Error starting free trial: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('오류가 발생했습니다. 나중에 다시 시도해주세요.'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _restorePurchases() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    HapticFeedback.mediumImpact();

    try {
      await _subscriptionManager.restorePurchases();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('구독 복원이 완료되었습니다.'),
            backgroundColor: AppTheme.successGreen,
          ),
        );
      }
    } catch (e) {
      print('Error restoring purchases: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('구독 복원에 실패했습니다. 다시 시도해주세요.'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _showSubscriptionPopup() {
    SubscriptionPopup.show(
      context,
      onDismiss: () {
        print('Subscription popup dismissed');
      },
      onSubscriptionStarted: () {
        setState(() {}); // Refresh the screen
      },
    );
  }

  void _showCancellationGuide() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '구독 해지 방법',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Google Play Store에서 구독을 해지할 수 있습니다:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 12),
              Text('1. Google Play Store 앱 열기'),
              Text('2. 프로필 아이콘 터치'),
              Text('3. "결제 및 정기결제" 선택'),
              Text('4. "정기결제" 선택'),
              Text('5. "Love Everyday" 앱 찾기'),
              Text('6. "정기결제 해지" 선택'),
              SizedBox(height: 12),
              Text(
                '참고사항:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Text('• 해지 후에도 현재 결제 기간 만료일까지 서비스 이용 가능'),
              Text('• 무료 체험 중에는 언제든 해지 가능'),
              Text('• 해지 후 다시 구독 가능'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.softGray,
      appBar: AppBar(
        title: const Text(
          '구독 관리',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading ? _buildLoadingView() : _buildContent(),
    );
  }

  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            '구독 정보를 불러오는 중...',
            style: TextStyle(
              fontSize: 16,
              color: AppTheme.textMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 현재 구독 상태
        _buildCurrentStatusSection(),
        
        const SizedBox(height: 16),
        
        // 구독 관리 액션
        _buildSubscriptionActionsSection(),
        
        const SizedBox(height: 16),
        
        // 구독 정보
        _buildSubscriptionInfoSection(),
        
        const SizedBox(height: 16),
        
        // FAQ
        _buildFAQSection(),
      ],
    );
  }

  Widget _buildCurrentStatusSection() {
    final canUsePremium = _subscriptionManager.canUsePremiumFeatures;
    final statusText = _subscriptionManager.getSubscriptionStatusText();
    final daysUntilExpiry = _subscriptionManager.getDaysUntilExpiry();
    
    return _buildSection(
      title: '현재 상태',
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: canUsePremium 
                ? AppTheme.successGradient 
                : LinearGradient(
                    colors: [
                      AppTheme.errorRed.withOpacity(0.1),
                      AppTheme.errorRed.withOpacity(0.05),
                    ],
                  ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: canUsePremium 
                  ? AppTheme.successGreen.withOpacity(0.3)
                  : AppTheme.errorRed.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (canUsePremium ? Colors.white : AppTheme.errorRed)
                          .withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      canUsePremium ? Icons.check_circle : Icons.error_outline,
                      color: canUsePremium ? Colors.white : AppTheme.errorRed,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          canUsePremium ? '프리미엄 활성화' : '구독 필요',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: canUsePremium ? Colors.white : AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 14,
                            color: canUsePremium 
                                ? Colors.white.withOpacity(0.9)
                                : AppTheme.textMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              if (canUsePremium && daysUntilExpiry > 0) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.schedule,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '만료까지 $daysUntilExpiry일 남음',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubscriptionActionsSection() {
    final canUsePremium = _subscriptionManager.canUsePremiumFeatures;
    
    return _buildSection(
      title: '구독 관리',
      children: [
        if (!canUsePremium) ...[
          _buildActionCard(
            icon: Icons.stars,
            iconColor: AppTheme.warningAmber,
            title: '무료 체험 시작',
            subtitle: '7일간 모든 프리미엄 기능을 무료로 사용해보세요',
            onTap: _isProcessing ? null : _startFreeTrial,
            buttonText: '무료 체험 시작',
            buttonColor: AppTheme.warningAmber,
            isProcessing: _isProcessing,
          ),
          const SizedBox(height: 12),
        ],
        
        _buildActionCard(
          icon: Icons.refresh,
          iconColor: AppTheme.primaryBlue,
          title: '구독 복원',
          subtitle: '다른 기기에서 구독했거나 구독 상태가 정확하지 않을 때 사용하세요',
          onTap: _isProcessing ? null : _restorePurchases,
          buttonText: '구독 복원',
          buttonColor: AppTheme.primaryBlue,
          isProcessing: _isProcessing,
        ),
        
        if (!canUsePremium) ...[
          const SizedBox(height: 12),
          _buildActionCard(
            icon: Icons.workspace_premium,
            iconColor: AppTheme.primaryBlue,
            title: '프리미엄 구독',
            subtitle: '전체 구독 옵션과 상세 정보를 확인하세요',
            onTap: _showSubscriptionPopup,
            buttonText: '구독 옵션 보기',
            buttonColor: AppTheme.primaryBlue,
          ),
        ],
        
        if (canUsePremium) ...[
          const SizedBox(height: 12),
          _buildActionCard(
            icon: Icons.cancel_outlined,
            iconColor: AppTheme.errorRed,
            title: '구독 해지',
            subtitle: 'Google Play Store에서 구독을 해지할 수 있습니다',
            onTap: _showCancellationGuide,
            buttonText: '해지 방법 보기',
            buttonColor: AppTheme.errorRed,
          ),
        ],
      ],
    );
  }

  Widget _buildSubscriptionInfoSection() {
    return _buildSection(
      title: '구독 정보',
      children: [
        _buildInfoCard(
          icon: Icons.payment,
          title: '요금제',
          subtitle: '월 1,500원 (하루 50원)',
        ),
        const SizedBox(height: 8),
        _buildInfoCard(
          icon: Icons.security,
          title: '결제 보안',
          subtitle: 'Google Play Store 공식 결제 시스템 사용',
        ),
        const SizedBox(height: 8),
        _buildInfoCard(
          icon: Icons.autorenew,
          title: '자동 갱신',
          subtitle: '매월 자동으로 갱신됩니다 (언제든 해지 가능)',
        ),
      ],
    );
  }

  Widget _buildFAQSection() {
    return _buildSection(
      title: '자주 묻는 질문',
      children: [
        _buildFAQItem(
          question: '무료 체험 기간 중에 해지할 수 있나요?',
          answer: '네, 무료 체험 기간 7일 동안 언제든 해지할 수 있습니다. 체험 기간 중 해지하면 요금이 청구되지 않습니다.',
        ),
        _buildFAQItem(
          question: '구독을 해지하면 언제까지 사용할 수 있나요?',
          answer: '구독을 해지하더라도 현재 결제 기간이 만료될 때까지 모든 프리미엄 기능을 계속 사용할 수 있습니다.',
        ),
        _buildFAQItem(
          question: '다른 기기에서도 사용할 수 있나요?',
          answer: '같은 Google 계정으로 로그인한 모든 기기에서 프리미엄 기능을 사용할 수 있습니다. 새 기기에서는 "구독 복원"을 눌러주세요.',
        ),
        _buildFAQItem(
          question: '구독 후 바로 기능을 사용할 수 있나요?',
          answer: '네, 구독 완료 즉시 모든 프리미엄 기능을 사용할 수 있습니다. 만약 활성화되지 않았다면 "구독 복원"을 시도해보세요.',
        ),
      ],
    );
  }

  Widget _buildSection({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textDark,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    required String buttonText,
    required Color buttonColor,
    bool isProcessing = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppTheme.getCardShadow(elevation: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textMedium,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: buttonColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        buttonText,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppTheme.primaryBlue, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.textDark,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            fontSize: 14,
            color: AppTheme.textMedium,
          ),
        ),
      ),
    );
  }

  Widget _buildFAQItem({required String question, required String answer}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            question,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.textDark,
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                answer,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textMedium,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}