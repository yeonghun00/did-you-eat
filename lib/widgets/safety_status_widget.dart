import 'package:flutter/material.dart';
import 'dart:async';
import '../services/child_app_service.dart';
import '../services/safety_status_calculator.dart';
import '../constants/colors.dart';
import '../theme/app_theme.dart';

/// SafetyStatusWidget - 부모님의 안전 상태를 실시간으로 모니터링하고 표시하는 위젯
///
/// 기능:
/// - 녹색(안전), 주황색(주의), 빨간색(위험) 상태 표시
/// - 설정된 알림 시간(3, 6, 12, 24시간 또는 사용자 정의)에 따른 상태 계산
/// - 실시간 부모님 활동 모니터링
/// - 위험 상태 시 자동 알림 전송
/// - 마지막 활동 시간과 다음 알림까지 남은 시간 표시
class SafetyStatusWidget extends StatefulWidget {
  final String familyCode;

  const SafetyStatusWidget({super.key, required this.familyCode});

  @override
  State<SafetyStatusWidget> createState() => _SafetyStatusWidgetState();
}

class _SafetyStatusWidgetState extends State<SafetyStatusWidget> {
  final ChildAppService _childService = ChildAppService();
  final SafetyStatusCalculator _statusCalculator = SafetyStatusCalculator();

  Timer? _statusUpdateTimer;
  StreamSubscription? _survivalStatusSubscription;
  SafetyStatus? _currentStatus;
  Map<String, dynamic>? _familyData;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeMonitoring();
  }

  @override
  void dispose() {
    _statusUpdateTimer?.cancel();
    _survivalStatusSubscription?.cancel();
    super.dispose();
  }

  /// 안전 상태 모니터링 초기화
  void _initializeMonitoring() {
    // 실시간 가족 데이터 스트림 구독
    _survivalStatusSubscription = _childService
        .listenToSurvivalStatus(widget.familyCode)
        .listen(
          (data) {
            if (mounted) {
              setState(() {
                _familyData = data;
                _isLoading = false;
                _error = null;
              });
              _updateSafetyStatus();
            }
          },
          onError: (error) {
            if (mounted) {
              setState(() {
                _error = error.toString();
                _isLoading = false;
              });
            }
          },
        );

    // 1분마다 상태 업데이트 (시간 경과에 따른 상태 변화 반영)
    _statusUpdateTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _updateSafetyStatus(),
    );
  }

  /// 안전 상태 업데이트 및 알림 처리
  void _updateSafetyStatus() {
    if (_familyData == null) return;

    final newStatus = _statusCalculator.calculateSafetyStatus(_familyData!);
    final previousStatus = _currentStatus;

    setState(() {
      _currentStatus = newStatus;
    });

    // 상태가 위험으로 변경되었을 때 알림 처리
    if (previousStatus != null &&
        previousStatus.level != SafetyLevel.critical &&
        newStatus.level == SafetyLevel.critical) {
      _handleCriticalStatusAlert();
    }
  }

  /// 위험 상태 알림 처리
  Future<void> _handleCriticalStatusAlert() async {
    try {
      // FCM을 통한 푸시 알림은 Firebase Functions에서 자동으로 처리됨
      // 여기서는 로컬 UI 상태만 관리
      print(
        '🚨 Critical safety status detected - notifications handled by Firebase Functions',
      );

      // 로컬 알림 표시 (선택사항)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_familyData?['elderlyName'] ?? '부모님'}의 안전 상태가 위험 단계입니다.',
            ),
            backgroundColor: AppTheme.errorRed,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: '확인',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      print('Error handling critical status alert: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingWidget();
    }

    if (_error != null) {
      return _buildErrorWidget();
    }

    if (_currentStatus == null) {
      return _buildNoDataWidget();
    }

    return _buildSafetyStatusCard();
  }

  /// 로딩 위젯
  Widget _buildLoadingWidget() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.getCardShadow(elevation: 4),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            '안전 상태 확인 중...',
            style: TextStyle(
              fontSize: 16,
              color: AppTheme.textMedium,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 에러 위젯
  Widget _buildErrorWidget() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.errorRed.withOpacity(0.3), width: 2),
        boxShadow: AppTheme.getCardShadow(elevation: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: AppTheme.errorRed),
          const SizedBox(height: 12),
          const Text(
            '안전 상태를 불러올 수 없습니다',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '네트워크 연결을 확인해주세요',
            style: TextStyle(fontSize: 14, color: AppTheme.textMedium),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _isLoading = true;
                _error = null;
              });
              _initializeMonitoring();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('다시 시도'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// 데이터 없음 위젯
  Widget _buildNoDataWidget() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.getCardShadow(elevation: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, size: 48, color: AppTheme.textMedium),
          const SizedBox(height: 12),
          const Text(
            '안전 상태 정보가 없습니다',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '부모님 앱에서 활동 데이터를 확인해주세요',
            style: TextStyle(fontSize: 14, color: AppTheme.textMedium),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// 안전 상태 카드 위젯
  Widget _buildSafetyStatusCard() {
    final status = _currentStatus!;
    final elderlyName = _familyData?['elderlyName'] as String? ?? '부모님';

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: _getStatusGradient(status.level),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _getStatusColor(status.level).withOpacity(0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: _getStatusColor(status.level).withOpacity(0.3),
            spreadRadius: 2,
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderSection(elderlyName, status),
            const SizedBox(height: 20),
            _buildStatusIndicator(status),
            const SizedBox(height: 20),
            _buildTimeInformation(status),
            if (status.level == SafetyLevel.critical) ...[
              const SizedBox(height: 16),
              _buildCriticalActionButtons(),
            ],
            const SizedBox(height: 16),
            _buildInfoSection(status),
          ],
        ),
      ),
    );
  }

  /// 헤더 섹션
  Widget _buildHeaderSection(String elderlyName, SafetyStatus status) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _getStatusColor(status.level).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            _getStatusIcon(status.level),
            color: _getStatusColor(status.level),
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$elderlyName님 안전 상태',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _getStatusTitle(status.level),
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withOpacity(0.9),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 상태 인디케이터
  Widget _buildStatusIndicator(SafetyStatus status) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _getStatusColor(status.level),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              status.message,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _getStatusColor(status.level),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 시간 정보 섹션
  Widget _buildTimeInformation(SafetyStatus status) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            status.level == SafetyLevel.critical
                ? Icons.warning
                : Icons.schedule,
            size: 18,
            color: AppTheme.textMedium,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.level == SafetyLevel.critical
                      ? '활동 없음'
                      : status.level == SafetyLevel.warning
                      ? '알림까지'
                      : '마지막 활동',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.textMedium,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status.level == SafetyLevel.critical
                      ? _formatDuration(status.timeSinceLastActivity)
                      : status.level == SafetyLevel.warning
                      ? _formatDuration(status.timeUntilNextLevel)
                      : _formatDuration(status.timeSinceLastActivity),
                  style: TextStyle(
                    fontSize: 16,
                    color: _getStatusColor(status.level),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 위험 상태 액션 버튼들
  Widget _buildCriticalActionButtons() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '긴급 조치 필요',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _clearSurvivalAlert,
                  icon: const Icon(Icons.check_circle, size: 18),
                  label: const Text('안전 확인'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.successGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _contactParent,
                  icon: const Icon(Icons.phone, size: 18),
                  label: const Text('연락하기'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryBlue,
                    side: BorderSide(color: AppTheme.primaryBlue, width: 2),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 정보 섹션
  Widget _buildInfoSection(SafetyStatus status) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: Colors.white.withOpacity(0.8),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '알림 설정: ${status.alertHours}시간 • ${_getStatusExplanation(status.level)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.9),
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 생존 알림 해제
  Future<void> _clearSurvivalAlert() async {
    try {
      final success = await _childService.clearSurvivalAlert(widget.familyCode);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('안전 상태를 확인했습니다.'),
            backgroundColor: AppColors.normalGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('안전 확인에 실패했습니다.'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    }
  }

  /// 부모님 연락하기 (향후 구현)
  void _contactParent() {
    // TODO: 전화걸기 기능 구현
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('연락하기 기능은 곧 추가될 예정입니다.')));
  }

  /// 상태별 색상 반환
  Color _getStatusColor(SafetyLevel level) {
    switch (level) {
      case SafetyLevel.safe:
        return AppTheme.successGreen;
      case SafetyLevel.warning:
        return AppTheme.warningAmber;
      case SafetyLevel.critical:
        return AppTheme.errorRed;
    }
  }

  /// 상태별 그라데이션 반환
  LinearGradient _getStatusGradient(SafetyLevel level) {
    switch (level) {
      case SafetyLevel.safe:
        return AppTheme.successGradient;
      case SafetyLevel.warning:
        return AppTheme.warningGradient;
      case SafetyLevel.critical:
        return AppTheme.errorGradient;
    }
  }

  /// 상태별 아이콘 반환
  IconData _getStatusIcon(SafetyLevel level) {
    switch (level) {
      case SafetyLevel.safe:
        return Icons.shield;
      case SafetyLevel.warning:
        return Icons.warning_amber;
      case SafetyLevel.critical:
        return Icons.emergency;
    }
  }

  /// 상태별 제목 반환
  String _getStatusTitle(SafetyLevel level) {
    switch (level) {
      case SafetyLevel.safe:
        return '안전 상태';
      case SafetyLevel.warning:
        return '주의 필요';
      case SafetyLevel.critical:
        return '긴급 상황';
    }
  }

  /// 상태별 설명 반환
  String _getStatusExplanation(SafetyLevel level) {
    switch (level) {
      case SafetyLevel.safe:
        return '정상적으로 활동 중입니다';
      case SafetyLevel.warning:
        return '곧 알림 시간에 도달합니다';
      case SafetyLevel.critical:
        return '즉시 확인이 필요합니다';
    }
  }

  /// 기간 포맷팅
  String _formatDuration(Duration duration) {
    if (duration.inMinutes < 60) {
      return '${duration.inMinutes}분';
    } else if (duration.inHours < 24) {
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      return minutes > 0 ? '$hours시간 $minutes분' : '$hours시간';
    } else {
      final days = duration.inDays;
      final hours = duration.inHours % 24;
      return hours > 0 ? '$days일 $hours시간' : '$days일';
    }
  }
}
