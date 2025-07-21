import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/child_app_service.dart';
import '../constants/colors.dart';
import 'location_map_widget.dart';
import 'simple_location_widget.dart';

class SurvivalMonitorWidget extends StatefulWidget {
  final String familyCode;

  const SurvivalMonitorWidget({
    Key? key,
    required this.familyCode,
  }) : super(key: key);

  @override
  State<SurvivalMonitorWidget> createState() => _SurvivalMonitorWidgetState();
}

class _SurvivalMonitorWidgetState extends State<SurvivalMonitorWidget> {
  final ChildAppService _childService = ChildAppService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: _childService.listenToSurvivalStatus(widget.familyCode),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
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

        final data = snapshot.data!;
        final lastActivity = data['lastActivity'] as Timestamp?;
        final survivalAlert = data['survivalAlert'] as Map<String, dynamic>?;
        final foodAlert = data['foodAlert'] as Map<String, dynamic>?;
        final elderlyName = data['elderlyName'] as String? ?? '';
        final isActive = data['isActive'] as bool? ?? false;
        final lastFoodIntake = data['lastFoodIntake'] as Map<String, dynamic>?;
        final location = data['location'] as Map<String, dynamic>?;

        // Calculate hours since last phone usage
        final hoursSinceActivity = lastActivity != null
            ? DateTime.now().difference(lastActivity.toDate()).inHours
            : 999;

        // Determine status
        String status;
        Color statusColor;
        IconData statusIcon;

        if (survivalAlert?['isActive'] == true) {
          status = '🚨 12시간 이상 활동 없음';
          statusColor = Colors.red;
          statusIcon = Icons.emergency;
        } else if (!isActive) {
          status = '📱 앱이 비활성화됨';
          statusColor = Colors.grey;
          statusIcon = Icons.mobile_off;
        } else if (hoursSinceActivity < 2) {
          status = '✅ 최근 활동 (${hoursSinceActivity}시간 전)';
          statusColor = AppColors.normalGreen;
          statusIcon = Icons.check_circle;
        } else if (hoursSinceActivity < 6) {
          status = '⚠️ ${hoursSinceActivity}시간 전 마지막 활동';
          statusColor = AppColors.cautionOrange;
          statusIcon = Icons.warning;
        } else if (hoursSinceActivity < 12) {
          status = '⚠️ ${hoursSinceActivity}시간 이상 활동 없음';
          statusColor = AppColors.warningRed;
          statusIcon = Icons.error;
        } else {
          status = '🚨 ${hoursSinceActivity}시간 이상 활동 없음';
          statusColor = Colors.red;
          statusIcon = Icons.emergency;
        }

        return Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                statusColor.withOpacity(0.1),
                statusColor.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: statusColor.withOpacity(0.3),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: statusColor.withOpacity(0.2),
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
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        statusIcon,
                        color: statusColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$elderlyName님 생존 신호',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.darkText,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '활동 모니터링',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.lightText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
                
                // Status
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        status,
                        style: TextStyle(
                          fontSize: 16,
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (lastActivity != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '마지막 활동: ${_formatTimestamp(lastActivity.toDate())}',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.lightText,
                          ),
                        ),
                      ],
                      // Food alert display
                      if (foodAlert?['isActive'] == true) ...{
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.restaurant, size: 16, color: Colors.orange),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  foodAlert!['message']?.toString() ?? '식사 알림',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      },
                      
                      // Survival alert display
                      if (survivalAlert?['message'] != null && 
                          survivalAlert!['message'].toString().isNotEmpty) ...{
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            survivalAlert!['message']?.toString() ?? '생존 알림',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.red,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      },
                    ],
                  ),
                ),
                
                // Clear alert buttons
                if (survivalAlert?['isActive'] == true || foodAlert?['isActive'] == true) ...{
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (survivalAlert?['isActive'] == true) ...{
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              try {
                                final success = await _childService.clearSurvivalAlert(widget.familyCode);
                                if (success && mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('생존 알림을 확인했습니다.'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('알림 확인에 실패했습니다.'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.check_circle, color: Colors.white),
                            label: const Text(
                              '생존 알림 확인',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      },
                      if (survivalAlert?['isActive'] == true && foodAlert?['isActive'] == true)
                        const SizedBox(width: 8),
                      if (foodAlert?['isActive'] == true) ...{
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              try {
                                final success = await _childService.clearFoodAlert(widget.familyCode);
                                if (success && mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('식사 알림을 확인했습니다.'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('알림 확인에 실패했습니다.'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.restaurant, color: Colors.white),
                            label: const Text(
                              '식사 알림 확인',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      },
                    ],
                  ),
                },
                
                // Food intake status
                if (lastFoodIntake != null) ...{
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.restaurant, size: 16, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '오늘 ${lastFoodIntake!['todayCount'] ?? 0}회 식사${lastFoodIntake!['timestamp'] != null ? ' | ${_formatTimestamp(lastFoodIntake!['timestamp'] is Timestamp ? (lastFoodIntake!['timestamp'] as Timestamp).toDate() : DateTime.parse(lastFoodIntake!['timestamp'].toString()))}' : ''}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.green,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                },
                
                // Location info (simplified - map moved to separate widget)
                if (location != null && 
                    location!['latitude'] != null && 
                    location!['longitude'] != null) ...{
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.location_on, size: 16, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '위치: ${location!['address'] ?? '위치 정보 없음'}${location!['timestamp'] != null ? ' | ${_formatTimestamp(location!['timestamp'] is Timestamp ? (location!['timestamp'] as Timestamp).toDate() : DateTime.parse(location!['timestamp'].toString()))}' : ''}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.blue,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                },
                
                
                // Status explanation
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: AppColors.primaryBlue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '앱 사용, 화면 켜짐 등의 활동을 모니터링합니다.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showLocationMap(BuildContext context, Map<String, dynamic> location, String elderlyName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.location_on, color: AppColors.warningRed),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$elderlyName님의 위치',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            
            // Map
            Expanded(
              child: LocationMapWidget(
                latitude: location['latitude'].toDouble(),
                longitude: location['longitude'].toDouble(),
                address: location['address'],
                timestamp: location['timestamp'] != null 
                    ? DateTime.parse(location['timestamp'])
                    : null,
                elderlyName: elderlyName,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 1) {
      return '방금 전';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}분 전';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}시간 전';
    } else {
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
             '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }
}