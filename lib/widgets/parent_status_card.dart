import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/family_record.dart';
import '../constants/colors.dart';

class ParentStatusCard extends StatefulWidget {
  final FamilyInfo familyInfo;
  final ParentStatusInfo statusInfo;
  final List<MealRecord> todayMeals;

  const ParentStatusCard({
    Key? key,
    required this.familyInfo,
    required this.statusInfo,
    required this.todayMeals,
  }) : super(key: key);

  @override
  State<ParentStatusCard> createState() => _ParentStatusCardState();
}

class _ParentStatusCardState extends State<ParentStatusCard> 
    with TickerProviderStateMixin {
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
    return AnimatedBuilder(
      animation: _bounceAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _bounceAnimation.value,
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: _getStatusGradient(),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: _getStatusColor().withOpacity(0.3),
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
            // 부모님 이름과 상태 아이콘
            Row(
              children: [
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnimation.value,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _getStatusIcon(),
                          style: const TextStyle(fontSize: 24),
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
                        '${widget.familyInfo.elderlyName} 님',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.statusInfo.message,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // 오늘의 식사 정보
            if (widget.todayMeals.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.restaurant,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '오늘 ${_getLastMealTime()} 식사',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                          '총 ${widget.todayMeals.length}번 식사하셨습니다',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '오늘 아직 식사 기록이 없습니다',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 16),
            
            // 연속 식사 기록 정보
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfoChip(
                  '📅 연속: ${_getStreakDays()}일',
                  Colors.white.withOpacity(0.2),
                ),
                _buildInfoChip(
                  '🍴 총 식사: ${widget.todayMeals.length}번',
                  Colors.white.withOpacity(0.2),
                ),
              ],
            ),
          ],
        ),
      ),
          ),
        );
      },
    );
  }

  Widget _buildInfoChip(String text, Color backgroundColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _getStatusIcon() {
    switch (widget.statusInfo.status) {
      case ParentStatus.normal:
        return '🟢';
      case ParentStatus.caution:
        return '🟡';
      case ParentStatus.warning:
        return '🔴';
      case ParentStatus.emergency:
        return '⚫';
    }
  }

  Color _getStatusColor() {
    switch (widget.statusInfo.status) {
      case ParentStatus.normal:
        return AppColors.normalGreen;
      case ParentStatus.caution:
        return AppColors.cautionOrange;
      case ParentStatus.warning:
        return AppColors.warningRed;
      case ParentStatus.emergency:
        return AppColors.emergencyBlack;
    }
  }

  LinearGradient _getStatusGradient() {
    switch (widget.statusInfo.status) {
      case ParentStatus.normal:
        return AppColors.normalGradient;
      case ParentStatus.caution:
        return AppColors.cautionGradient;
      case ParentStatus.warning:
        return AppColors.warningGradient;
      case ParentStatus.emergency:
        return AppColors.emergencyGradient;
    }
  }

  String _getLastMealTime() {
    if (widget.todayMeals.isEmpty) return '';
    final lastMeal = widget.todayMeals.last;
    return DateFormat('HH:mm').format(lastMeal.timestamp);
  }

  int _getStreakDays() {
    // 실제로는 연속 기록 일수를 계산하는 로직이 필요
    // 현재는 간단히 반환
    return widget.statusInfo.daysSinceLastRecord == 0 ? 1 : 0;
  }
}