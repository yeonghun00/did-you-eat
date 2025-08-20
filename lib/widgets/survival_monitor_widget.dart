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
        
        
        final todayMealCount = data['todayMealCount'] as int? ?? 0;
        final survivalAlert = data['survivalAlert'] as Map<String, dynamic>?;
        final elderlyName = data['elderlyName'] as String? ?? '';
        final lastPhoneActivity = data['lastPhoneActivity'] as dynamic; // General phone activity
        final lastActive = data['lastActive'] as dynamic; // Our specific app usage
        final location = data['location'] as Map<String, dynamic>?;
        final settings = data['settings'] as Map<String, dynamic>?;
        
        // Get survival alert hours setting (default: 12 hours)
        final survivalAlertHours = settings?['survivalAlertHours'] as int? ?? 12;

        // Check survival alert status (handled by parent app's native monitoring)
        final isSurvivalAlertActive = survivalAlert?['isActive'] as bool? ?? false;

        // Parse lastPhoneActivity timestamp (for survival monitoring)
        DateTime? lastPhoneActivityTime;
        if (lastPhoneActivity != null) {
          try {
            if (lastPhoneActivity is Timestamp) {
              lastPhoneActivityTime = lastPhoneActivity.toDate();
            } else if (lastPhoneActivity is String) {
              lastPhoneActivityTime = DateTime.parse(lastPhoneActivity);
            }
          } catch (e) {
            print('Error parsing lastPhoneActivity: $e');
          }
        }

        // Determine status based on actual activity data
        String status;
        Color statusColor;
        IconData statusIcon;

        if (isSurvivalAlertActive) {
          final alertMessage = survivalAlert?['message'] as String? ?? '장시간 활동 없음';
          status = '🚨 $alertMessage';
          statusColor = Colors.red;
          statusIcon = Icons.emergency;
        } else if (lastPhoneActivityTime == null) {
          status = '📱 안전 상태 확인 중';
          statusColor = Colors.grey;
          statusIcon = Icons.mobile_off;
        } else {
          final now = DateTime.now();
          final inactiveMinutes = now.difference(lastPhoneActivityTime).inMinutes;
          
          // Calculate thresholds based on user settings
          final redThresholdMinutes = survivalAlertHours * 60; // Convert hours to minutes
          final orangeThresholdMinutes = redThresholdMinutes - 60; // 1 hour before red threshold
          
          if (inactiveMinutes >= redThresholdMinutes) {
            // Red: At or past the survival alert threshold
            final hours = (inactiveMinutes / 60).floor();
            final remainingMinutes = inactiveMinutes % 60;
            String timeStr = hours > 0 
                ? '${hours}시간${remainingMinutes > 0 ? ' ${remainingMinutes}분' : ''}'
                : '${inactiveMinutes}분';
            status = '🚨 $timeStr째 휴대폰 미사용 - 위험';
            statusColor = AppColors.warningRed;
            statusIcon = Icons.warning;
          } else if (inactiveMinutes >= orangeThresholdMinutes && orangeThresholdMinutes > 0) {
            // Orange: 1 hour before the red threshold
            final remainingMinutes = redThresholdMinutes - inactiveMinutes;
            final remainingHours = (remainingMinutes / 60).floor();
            final remainingMins = remainingMinutes % 60;
            String timeStr = remainingHours > 0 
                ? '${remainingHours}시간${remainingMins > 0 ? ' ${remainingMins}분' : ''}'
                : '${remainingMinutes}분';
            status = '⏰ 주의 - $timeStr 후 위험 단계';
            statusColor = AppColors.cautionOrange;
            statusIcon = Icons.schedule;
          } else {
            // Green: Safe zone
            final hours = (inactiveMinutes / 60).floor();
            final remainingMinutes = inactiveMinutes % 60;
            String timeStr;
            if (hours > 0) {
              timeStr = '${hours}시간${remainingMinutes > 0 ? ' ${remainingMinutes}분' : ''}';
            } else {
              timeStr = '${inactiveMinutes}분';
            }
            status = '✅ 안전하게 지내고 계세요 ($timeStr 전 사용)';
            statusColor = AppColors.normalGreen;
            statusIcon = Icons.check_circle;
          }
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
                            '$elderlyName님 안전 상태',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.darkText,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '가족 안심 서비스',
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
                      if (lastPhoneActivityTime != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '마지막 휴대폰 사용: ${_formatDetailedTimestamp(lastPhoneActivityTime!)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.lightText,
                          ),
                        ),
                      ],
                      
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
                if (survivalAlert?['isActive'] == true) ...{
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
                                      content: Text('안전 상태를 확인했습니다.'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('안전 확인에 실패했습니다.'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.check_circle, color: Colors.white),
                            label: const Text(
                              '안전 확인 완료',
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
                    ],
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
                            '현재 위치: ${location!['address'] ?? '위치 공유 준비 중'}${location!['timestamp'] != null ? ' | ${_formatTimestamp(location!['timestamp'] is Timestamp ? (location!['timestamp'] as Timestamp).toDate() : DateTime.parse(location!['timestamp'].toString()))}' : ''}',
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
                          '가족이 안심할 수 있도록 안전 상태를 공유합니다.',
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

  String _formatDetailedTimestamp(DateTime dateTime) {
    // Format: "July 26, 2025 at 3:22:15 PM UTC+9"
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    
    final month = months[dateTime.month];
    final day = dateTime.day;
    final year = dateTime.year;
    
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');
    
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    
    return '$month $day, $year at $displayHour:$minute:$second $period UTC+9';
  }
}