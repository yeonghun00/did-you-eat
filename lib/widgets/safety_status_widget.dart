import 'package:flutter/material.dart';
import 'dart:async';
import '../services/child_app_service.dart';
import '../services/safety_status_calculator.dart';
import '../services/subscription_manager.dart';
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
  final SubscriptionManager _subscriptionManager = SubscriptionManager();

  Timer? _statusUpdateTimer;
  StreamSubscription? _survivalStatusSubscription;
  SafetyStatus? _currentStatus;
  Map<String, dynamic>? _familyData;
  bool _isLoading = true;
  String? _error;
  bool _isInSleepMode = false;

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

    // Check if parent is currently in sleep mode
    final isInSleep = _checkIfInSleepTime();

    setState(() {
      _currentStatus = newStatus;
      _isInSleepMode = isInSleep;
    });

    // 상태가 위험으로 변경되었을 때 알림 처리
    if (previousStatus != null &&
        previousStatus.level != SafetyLevel.critical &&
        newStatus.level == SafetyLevel.critical) {
      _handleCriticalStatusAlert();
    }
  }

  /// Check if parent is currently in sleep time period
  bool _checkIfInSleepTime() {
    if (_familyData == null) return false;

    try {
      final settings = _familyData!['settings'] as Map<String, dynamic>?;
      final sleepSettings = settings?['sleepTimeSettings'] as Map<String, dynamic>?;

      if (sleepSettings == null) return false;

      final enabled = sleepSettings['enabled'] as bool? ?? false;
      if (!enabled) return false;

      final sleepStartHour = sleepSettings['sleepStartHour'] as int? ?? 22;
      final sleepStartMinute = sleepSettings['sleepStartMinute'] as int? ?? 0;
      final sleepEndHour = sleepSettings['sleepEndHour'] as int? ?? 6;
      final sleepEndMinute = sleepSettings['sleepEndMinute'] as int? ?? 0;

      // Parse active days (1=Monday, 7=Sunday)
      final activeDays = (sleepSettings['activeDays'] as List<dynamic>?)
          ?.map((e) => e as int)
          .toList() ?? [1, 2, 3, 4, 5, 6, 7];

      final now = DateTime.now();
      final currentWeekday = now.weekday; // 1=Monday, 7=Sunday

      // Check if today is an active sleep day
      if (!activeDays.contains(currentWeekday)) {
        return false;
      }

      // Check if current time is within sleep period
      final currentMinutes = now.hour * 60 + now.minute;
      final sleepStartMinutes = sleepStartHour * 60 + sleepStartMinute;
      final sleepEndMinutes = sleepEndHour * 60 + sleepEndMinute;

      if (sleepStartMinutes > sleepEndMinutes) {
        // Overnight period (e.g., 22:00 - 06:00)
        return currentMinutes >= sleepStartMinutes || currentMinutes <= sleepEndMinutes;
      } else {
        // Same-day period (e.g., 14:00 - 16:00)
        return currentMinutes >= sleepStartMinutes && currentMinutes <= sleepEndMinutes;
      }
    } catch (e) {
      print('Error checking sleep time: $e');
      return false;
    }
  }

  /// Get sleep time period string for display (e.g., "22:00 - 06:00")
  String _getSleepTimePeriod() {
    try {
      final settings = _familyData!['settings'] as Map<String, dynamic>?;
      final sleepSettings = settings?['sleepTimeSettings'] as Map<String, dynamic>?;

      if (sleepSettings == null) return '';

      final sleepStartHour = sleepSettings['sleepStartHour'] as int? ?? 22;
      final sleepStartMinute = sleepSettings['sleepStartMinute'] as int? ?? 0;
      final sleepEndHour = sleepSettings['sleepEndHour'] as int? ?? 6;
      final sleepEndMinute = sleepSettings['sleepEndMinute'] as int? ?? 0;

      return '${_formatTime(sleepStartHour, sleepStartMinute)} - ${_formatTime(sleepEndHour, sleepEndMinute)}';
    } catch (e) {
      return '';
    }
  }

  /// Format time as HH:MM
  String _formatTime(int hour, int minute) {
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
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

    // 프리미엄 접근 제어 체크 - 즉시 팝업 표시
    if (!_subscriptionManager.canUsePremiumFeatures) {
      // 위젯이 로드된 후 즉시 팝업 표시
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showMandatorySubscriptionPopup(context);
        }
      });

      // 로딩 상태를 유지하여 사용자가 실제 콘텐츠를 보지 못하게 함
      return _buildLoadingWidget();
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
    // Check if survival signal monitoring is disabled
    final settings = _familyData?['settings'] as Map<String, dynamic>?;
    final survivalSignalEnabled = settings?['survivalSignalEnabled'] as bool? ?? true;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Survival signal disabled indicator
          if (!survivalSignalEnabled) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.warningAmber.withOpacity(0.12),
                    AppTheme.warningAmber.withOpacity(0.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.warningAmber.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.warningAmber.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.notifications_off,
                      color: AppTheme.warningAmber,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '안전 확인 알림이 비활성화됨',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '부모님이 안전 확인 알림을 끄셨습니다',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textMedium,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Sleep mode indicator (if in sleep time)
          if (_isInSleepMode) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.infoTeal.withOpacity(0.08),
                    AppTheme.primaryBlue.withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.infoTeal.withOpacity(0.2),
                  width: 1.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⏰ ${_getSleepTimePeriod()}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '부모님께서 수면시간이세요. 안전 알림이 일시 중지됩니다 💤',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textMedium,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Icon(
                Icons.schedule,
                size: 18,
                color: AppTheme.textMedium,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '마지막 활동',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textMedium,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDuration(status.timeSinceLastActivity),
                      style: TextStyle(
                        fontSize: 16,
                        color: _isInSleepMode ? Colors.blue.shade700 : _getStatusColor(status.level),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (status.level == SafetyLevel.critical && !_isInSleepMode) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
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
          ],
        ],
      ),
    );
  }

  /// 정보 섹션 (배터리 상태)
  Widget _buildInfoSection(SafetyStatus status) {
    // Get battery info from family data
    final batteryLevel = _familyData?['batteryLevel'] as int?;
    final isCharging = _familyData?['isCharging'] as bool? ?? false;
    final hasLocation = _familyData?['location'] != null;

    // Don't show section if no battery data
    if (batteryLevel == null) {
      return const SizedBox.shrink();
    }

    final batteryText = _getBatteryText(batteryLevel, isCharging);
    final batteryColor = _getBatteryColor(batteryLevel, isCharging);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isCharging ? Icons.battery_charging_full : Icons.battery_std,
                size: 20,
                color: batteryColor,
              ),
              const SizedBox(width: 8),
              Text(
                batteryText,
                style: TextStyle(
                  fontSize: 14,
                  color: batteryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Get battery text for display
  String _getBatteryText(int batteryLevel, bool isCharging) {
    if (isCharging) {
      return '배터리 $batteryLevel% 충전 중';
    } else if (batteryLevel >= 50) {
      return '배터리 $batteryLevel%';
    } else if (batteryLevel >= 20) {
      return '배터리 $batteryLevel%';
    } else if (batteryLevel >= 10) {
      return '배터리 부족 $batteryLevel%';
    } else {
      return '배터리 위험 $batteryLevel%';
    }
  }

  /// Get battery color based on level and charging status
  Color _getBatteryColor(int batteryLevel, bool isCharging) {
    if (isCharging) {
      return AppTheme.primaryBlue;
    } else if (batteryLevel >= 50) {
      return AppTheme.successGreen;
    } else if (batteryLevel >= 20) {
      return AppTheme.warningAmber;
    } else {
      return AppTheme.errorRed;
    }
  }

  /// 생존 알림 해제
  Future<void> _clearSurvivalAlert() async {
    try {
      final success = await _childService.clearSurvivalAlert(widget.familyCode);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('안전 상태를 확인했습니다.'),
            backgroundColor: AppTheme.successGreen,
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

  /// 필수 구독 팝업 표시
  void _showMandatorySubscriptionPopup(BuildContext context) {
    if (!mounted) return;

    // 이미 팝업이 표시 중인지 확인
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false, // 바깥쪽 터치로 닫기 방지
      barrierColor: Colors.black87, // 더 진한 배경으로 강조
      builder: (BuildContext dialogContext) => WillPopScope(
        onWillPop: () async => false, // 뒤로가기 버튼으로 닫기 방지
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: 400,
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 헤더
                _buildMandatoryPopupHeader(),

                // 컨텐츠 - 스크롤 가능
                Flexible(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 필수 안내 메시지
                          _buildMandatoryMessage(),

                          const SizedBox(height: 20),

                          // 프리미엄 기능 소개
                          _buildMandatoryFeaturesList(),

                          const SizedBox(height: 20),

                          // 가격 정보
                          _buildMandatoryPricingInfo(),

                          const SizedBox(height: 24),

                          // 액션 버튼들
                          _buildMandatoryActionButtons(dialogContext),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMandatoryPopupHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.errorRed, AppTheme.errorRed.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.security, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 16),
          const Text(
            '안전 모니터링 활성화 필요',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          const Text(
            '부모님의 안전을 지키기 위해 프리미엄 기능이 필요합니다',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white,
              fontWeight: FontWeight.w400,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMandatoryMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.errorRed.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.errorRed.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.errorRed.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.priority_high,
              color: AppTheme.errorRed,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '필수 기능 활성화',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '실시간 안전 모니터링은 부모님의 생명과 직결된 중요한 기능입니다. 계속 사용하려면 구독이 필요합니다.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textMedium,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMandatoryFeaturesList() {
    const features = [
      {
        'icon': Icons.emergency,
        'title': '위험 상황 즉시 알림',
        'desc': '부모님에게 응급상황 발생 시 실시간 알림',
      },
      {
        'icon': Icons.shield,
        'title': '24시간 안전 모니터링',
        'desc': '부모님의 활동 상태를 지속적으로 확인',
      },
      {'icon': Icons.phone, 'title': '긴급 연락 기능', 'desc': '위험 감지 시 가족에게 자동 연락'},
      {
        'icon': Icons.analytics,
        'title': '상세 활동 분석',
        'desc': '일상 패턴 분석으로 이상 징후 조기 발견',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '포함된 안전 기능',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textDark,
          ),
        ),
        const SizedBox(height: 12),
        ...features.map(
          (feature) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    feature['icon'] as IconData,
                    color: AppTheme.primaryBlue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        feature['title'] as String,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textDark,
                        ),
                      ),
                      Text(
                        feature['desc'] as String,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textMedium,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMandatoryPricingInfo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.warningAmber.withOpacity(0.1),
            AppTheme.warningAmber.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.warningAmber.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.warningAmber.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.stars,
                  color: AppTheme.warningAmber,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '7일 무료 체험',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text(
                '체험 후 월',
                style: TextStyle(fontSize: 16, color: AppTheme.textMedium),
              ),
              const SizedBox(width: 4),
              const Text(
                '1,500',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryBlue,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '원',
                style: TextStyle(fontSize: 16, color: AppTheme.textMedium),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '하루 단 50원 • 부모님 안전은 소중합니다',
            style: TextStyle(fontSize: 12, color: AppTheme.textMedium),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMandatoryActionButtons(BuildContext dialogContext) {
    return Column(
      children: [
        // 무료 체험 시작 버튼
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: () async {
              try {
                final success = await _subscriptionManager.startFreeTrial();
                if (success && mounted) {
                  Navigator.of(dialogContext).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('무료 체험이 시작되었습니다! 이제 모든 기능을 사용할 수 있습니다.'),
                      backgroundColor: AppTheme.successGreen,
                      duration: Duration(seconds: 4),
                    ),
                  );
                  // 위젯을 다시 빌드하여 프리미엄 콘텐츠를 표시
                  setState(() {});
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('무료 체험 시작에 실패했습니다. 다시 시도해주세요.'),
                      backgroundColor: AppTheme.errorRed,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
            child: const Text(
              '7일 무료 체험 시작하기',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // 구독 설정 바로가기 버튼
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.pushNamed(context, '/subscription-settings');
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryBlue,
              side: BorderSide(color: AppTheme.primaryBlue, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              '구독 관리 설정',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
        ),

        const SizedBox(height: 16),

        Text(
          '• 7일 무료 체험 후 자동으로 월간 구독이 시작됩니다\n• 체험 기간 중 언제든 Google Play에서 취소할 수 있습니다\n• 안전 모니터링 서비스 이용을 위해서는 구독이 필요합니다',
          style: TextStyle(
            fontSize: 11,
            color: AppTheme.textLight,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
