import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/family_record.dart';
import '../services/firebase_service.dart';
import '../services/child_app_service.dart';
import '../theme/app_theme.dart';
import '../constants/colors.dart';

class ActivityScreen extends StatefulWidget {
  final String familyCode;
  final FamilyInfo familyInfo;

  const ActivityScreen({
    super.key,
    required this.familyCode,
    required this.familyInfo,
  });

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final ChildAppService _childService = ChildAppService();
  List<ActivityRecord> _allActivities = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllActivities();
    _setupRealtimeListener();
  }

  void _setupRealtimeListener() {
    // Listen to real-time updates for family data
    _childService.listenToSurvivalStatus(widget.familyCode).listen((data) {
      if (mounted) {
        _loadAllActivities();
      }
    });
  }

  Future<void> _loadAllActivities() async {
    setState(() {
      _isLoading = true;
    });

    try {
      List<ActivityRecord> activities = [];

      // Get real meal data from Firebase
      await _loadMealActivities(activities);
      
      // Get phone inactivity alerts from Firebase
      await _loadPhoneAlertActivities(activities);

      // Sort all activities by timestamp (newest first)
      activities.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      setState(() {
        _allActivities = activities;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading activities: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMealActivities(List<ActivityRecord> activities) async {
    try {
      // Load recent meal records (last 30 days)
      final now = DateTime.now();
      final startDate = now.subtract(const Duration(days: 30));
      
      final mealsByDate = await FirebaseService.getMealsInRange(
        widget.familyCode,
        startDate,
        now,
      );

      // Convert meals to activity records
      mealsByDate.forEach((date, meals) {
        for (var meal in meals) {
          activities.add(ActivityRecord(
            id: 'meal_${meal.timestamp.millisecondsSinceEpoch}',
            type: ActivityType.meal,
            title: '식사 완료',
            message: '${meal.elderlyName}님이 ${meal.mealNumber}번째 식사를 하셨습니다',
            timestamp: meal.timestamp,
            icon: Icons.restaurant,
            elderlyName: meal.elderlyName,
            additionalData: {'mealNumber': meal.mealNumber},
          ));
        }
      });
    } catch (e) {
      print('Error loading meal activities: $e');
    }
  }

  Future<void> _loadPhoneAlertActivities(List<ActivityRecord> activities) async {
    try {
      // Get current survival status to check for phone inactivity
      final statusData = await _childService.getSurvivalStatus(widget.familyCode);
      
      if (statusData != null) {
        final lastPhoneActivity = statusData['lastPhoneActivity'];
        final elderlyName = statusData['elderlyName'] ?? '부모님';
        
        if (lastPhoneActivity != null) {
          final lastActivity = (lastPhoneActivity as Timestamp).toDate();
          final now = DateTime.now();
          final hoursSinceActivity = now.difference(lastActivity).inHours;
          
          // Generate phone inactivity alerts for different time thresholds
          if (hoursSinceActivity >= 8) {
            // Add alert for 8+ hours of inactivity
            activities.add(ActivityRecord(
              id: 'phone_alert_8h_${lastActivity.millisecondsSinceEpoch}',
              type: ActivityType.phoneAlert,
              title: '휴대폰 미사용 알림',
              message: '${elderlyName}님이 8시간째 휴대폰을 사용하지 않고 있습니다',
              timestamp: lastActivity.add(const Duration(hours: 8)),
              icon: Icons.phone_disabled,
              elderlyName: elderlyName,
              additionalData: {'hoursInactive': 8},
            ));
          }
          
          if (hoursSinceActivity >= 12) {
            // Add alert for 12+ hours of inactivity
            activities.add(ActivityRecord(
              id: 'phone_alert_12h_${lastActivity.millisecondsSinceEpoch}',
              type: ActivityType.phoneAlert,
              title: '휴대폰 장시간 미사용',
              message: '${elderlyName}님이 12시간째 휴대폰을 사용하지 않고 있습니다',
              timestamp: lastActivity.add(const Duration(hours: 12)),
              icon: Icons.warning,
              elderlyName: elderlyName,
              additionalData: {'hoursInactive': 12},
            ));
          }
          
          if (hoursSinceActivity >= 24) {
            // Add critical alert for 24+ hours of inactivity
            activities.add(ActivityRecord(
              id: 'phone_alert_24h_${lastActivity.millisecondsSinceEpoch}',
              type: ActivityType.phoneAlert,
              title: '휴대폰 미사용 경고',
              message: '${elderlyName}님이 24시간 이상 휴대폰을 사용하지 않고 있습니다',
              timestamp: lastActivity.add(const Duration(hours: 24)),
              icon: Icons.error,
              elderlyName: elderlyName,
              additionalData: {'hoursInactive': 24},
            ));
          }
        }
        
        // Also check for survival alerts
        final survivalAlert = statusData['survivalAlert'] as Map<String, dynamic>?;
        if (survivalAlert != null && survivalAlert['isActive'] == true) {
          final alertTimestamp = survivalAlert['timestamp'];
          if (alertTimestamp != null) {
            activities.add(ActivityRecord(
              id: 'survival_alert_${(alertTimestamp as Timestamp).millisecondsSinceEpoch}',
              type: ActivityType.survivalAlert,
              title: '생존 신호 경고',
              message: survivalAlert['message'] ?? '장시간 활동이 감지되지 않습니다',
              timestamp: alertTimestamp.toDate(),
              icon: Icons.warning_amber,
              elderlyName: elderlyName,
              additionalData: {'alertType': 'survival'},
            ));
          }
        }
      }
    } catch (e) {
      print('Error loading phone alert activities: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.softGray,
      appBar: AppBar(
        title: const Text(
          '활동 기록',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _loadAllActivities,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _allActivities.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.timeline,
                          size: 48,
                          color: AppColors.lightText,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '활동 기록이 없습니다',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.lightText,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    itemCount: _allActivities.length,
                    itemBuilder: (context, index) {
                      final activity = _allActivities[index];
                      return _buildActivityItem(activity, index == _allActivities.length - 1);
                    },
                  ),
      ),
    );
  }

  Widget _buildActivityItem(ActivityRecord activity, bool isLast) {
    Color activityColor = _getActivityColor(activity.type);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Timeline Line
            Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: activityColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: activityColor.withValues(alpha: 0.3),
                    ),
                  ),
              ],
            ),
            
            const SizedBox(width: 16),
            
            // Content
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: AppTheme.getCardShadow(),
                  border: activity.type == ActivityType.phoneAlert || activity.type == ActivityType.survivalAlert
                      ? Border(left: BorderSide(color: activityColor, width: 4))
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          activity.icon,
                          color: activityColor,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            activity.title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.darkText,
                            ),
                          ),
                        ),
                        if (activity.type == ActivityType.meal && activity.additionalData?['mealNumber'] != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: activityColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${activity.additionalData!['mealNumber']}번째',
                              style: TextStyle(
                                fontSize: 12,
                                color: activityColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      activity.message,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.darkText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      DateFormat('yyyy년 MM월 dd일 HH:mm').format(activity.timestamp),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.lightText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getActivityColor(ActivityType type) {
    switch (type) {
      case ActivityType.meal:
        return AppColors.primaryBlue;
      case ActivityType.phoneAlert:
        return AppColors.cautionOrange;
      case ActivityType.survivalAlert:
        return AppColors.warningRed;
    }
  }
}

// Data models for activity records
enum ActivityType {
  meal,
  phoneAlert,
  survivalAlert,
}

class ActivityRecord {
  final String id;
  final ActivityType type;
  final String title;
  final String message;
  final DateTime timestamp;
  final IconData icon;
  final String elderlyName;
  final Map<String, dynamic>? additionalData;

  ActivityRecord({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.timestamp,
    required this.icon,
    required this.elderlyName,
    this.additionalData,
  });
}