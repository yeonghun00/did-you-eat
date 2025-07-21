import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/child_app_service.dart';
import '../constants/colors.dart';

class FoodAlertWidget extends StatefulWidget {
  final String familyCode;

  const FoodAlertWidget({
    Key? key,
    required this.familyCode,
  }) : super(key: key);

  @override
  State<FoodAlertWidget> createState() => _FoodAlertWidgetState();
}

class _FoodAlertWidgetState extends State<FoodAlertWidget>
    with TickerProviderStateMixin {
  final ChildAppService _childService = ChildAppService();
  late AnimationController _pulseController;
  late AnimationController _bounceController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    
    _bounceAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _bounceController,
      curve: Curves.elasticOut,
    ));
    
    _bounceController.forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: _childService.listenToSurvivalStatus(widget.familyCode),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return _buildLoadingCard();
        }

        final data = snapshot.data!;
        final foodAlert = data['foodAlert'] as Map<String, dynamic>?;
        final lastFoodIntake = data['lastFoodIntake'] as Map<String, dynamic>?;
        final elderlyName = data['elderlyName'] as String? ?? '';

        return AnimatedBuilder(
          animation: _bounceAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _bounceAnimation.value,
              child: _buildFoodCard(foodAlert, lastFoodIntake, elderlyName),
            );
          },
        );
      },
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildFoodCard(Map<String, dynamic>? foodAlert, Map<String, dynamic>? lastFoodIntake, String elderlyName) {
    final bool hasActiveAlert = foodAlert?['isActive'] == true;
    final DateTime? lastIntakeTime = lastFoodIntake?['timestamp'] != null
        ? (lastFoodIntake!['timestamp'] is Timestamp
            ? (lastFoodIntake['timestamp'] as Timestamp).toDate()
            : DateTime.parse(lastFoodIntake['timestamp'].toString()))
        : null;

    Color cardColor;
    Color iconColor;
    IconData iconData;
    String title;
    String message;
    LinearGradient gradient;

    if (hasActiveAlert) {
      cardColor = AppColors.warningRed;
      iconColor = Colors.white;
      iconData = Icons.warning_amber_rounded;
      title = '🚨 식사 알림';
      message = '부모님이 오랫동안 식사하지 않으셨습니다';
      gradient = AppColors.warningGradient;
    } else if (lastIntakeTime != null) {
      final hoursSinceLastMeal = DateTime.now().difference(lastIntakeTime).inHours;
      
      if (hoursSinceLastMeal < 6) {
        cardColor = AppColors.normalGreen;
        iconColor = Colors.white;
        iconData = Icons.restaurant;
        title = '🍽️ 식사 상태';
        message = '최근에 식사하셨습니다';
        gradient = AppColors.normalGradient;
      } else if (hoursSinceLastMeal < 12) {
        cardColor = AppColors.cautionOrange;
        iconColor = Colors.white;
        iconData = Icons.schedule;
        title = '⏰ 식사 시간';
        message = '${hoursSinceLastMeal}시간 전 마지막 식사';
        gradient = AppColors.cautionGradient;
      } else {
        cardColor = AppColors.warningRed;
        iconColor = Colors.white;
        iconData = Icons.warning_amber_rounded;
        title = '⚠️ 식사 확인 필요';
        message = '${hoursSinceLastMeal}시간째 식사 기록이 없습니다';
        gradient = AppColors.warningGradient;
      }
    } else {
      cardColor = AppColors.primaryBlue;
      iconColor = Colors.white;
      iconData = Icons.info_outline;
      title = '🍽️ 식사 모니터링';
      message = '식사 기록을 기다리고 있습니다';
      gradient = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.primaryBlue, AppColors.primaryBlue.withOpacity(0.8)],
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: cardColor.withOpacity(0.3),
            spreadRadius: 2,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 제목과 아이콘
            Row(
              children: [
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: hasActiveAlert ? _pulseAnimation.value : 1.0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          iconData,
                          color: iconColor,
                          size: 24,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message,
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
            ),
            
            const SizedBox(height: 16),
            
            // 마지막 식사 정보
            if (lastIntakeTime != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.access_time,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '마지막 식사: ${_formatTime(lastIntakeTime)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            // 알림 해제 버튼 (활성 알림이 있을 때만)
            if (hasActiveAlert) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    _clearFoodAlert();
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('알림 확인'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: cardColor,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 1) {
      return '방금 전';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}분 전';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}시간 전';
    } else if (difference.inDays == 1) {
      return '어제 ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else {
      return '${dateTime.month}/${dateTime.day} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _clearFoodAlert() async {
    try {
      final success = await _childService.clearFoodAlert(widget.familyCode);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('식사 알림이 해제되었습니다'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('알림 해제에 실패했습니다'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('오류가 발생했습니다'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}