import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_theme.dart';
import '../constants/colors.dart';
import '../models/family_record.dart';

class HealthScreen extends StatefulWidget {
  final String familyCode;
  final FamilyInfo familyInfo;

  const HealthScreen({
    super.key,
    required this.familyCode,
    required this.familyInfo,
  });

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  
  // Health data
  Map<String, dynamic> _healthSummary = {};
  List<MedicationReminder> _medications = [];
  List<HealthMetric> _recentMetrics = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadHealthData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHealthData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await Future.wait([
        _loadHealthSummary(),
        _loadMedications(),
        _loadHealthMetrics(),
      ]);
    } catch (e) {
      print('Error loading health data: $e');
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadHealthSummary() async {
    // Mock health summary - in real app, this would come from family data
    _healthSummary = {
      'lastMealTime': DateTime.now().subtract(const Duration(hours: 2)),
      'dailyMealCount': 2,
      'activityLevel': 'Normal',
      'lastPhoneActivity': DateTime.now().subtract(const Duration(minutes: 30)),
      'sleepPattern': 'Regular',
      'medicationCompliance': 85,
    };
  }

  Future<void> _loadMedications() async {
    // Mock medication data - in real app, this would be stored in Firestore
    _medications = [
      MedicationReminder(
        name: '혈압약',
        dosage: '5mg',
        frequency: '하루 1회',
        timeSlots: [const TimeOfDay(hour: 8, minute: 0)],
        lastTaken: DateTime.now().subtract(const Duration(hours: 12)),
        isActive: true,
      ),
      MedicationReminder(
        name: '당뇨약',
        dosage: '500mg',
        frequency: '하루 2회',
        timeSlots: [
          const TimeOfDay(hour: 8, minute: 0),
          const TimeOfDay(hour: 20, minute: 0),
        ],
        lastTaken: DateTime.now().subtract(const Duration(hours: 4)),
        isActive: true,
      ),
      MedicationReminder(
        name: '비타민 D',
        dosage: '1000IU',
        frequency: '하루 1회',
        timeSlots: [const TimeOfDay(hour: 9, minute: 0)],
        lastTaken: DateTime.now().subtract(const Duration(days: 1)),
        isActive: false,
      ),
    ];
  }

  Future<void> _loadHealthMetrics() async {
    // Mock health metrics - in real app, this could be integrated with health devices
    _recentMetrics = [
      HealthMetric(
        type: 'Blood Pressure',
        value: '120/80',
        timestamp: DateTime.now().subtract(const Duration(days: 1)),
        status: HealthStatus.normal,
      ),
      HealthMetric(
        type: 'Heart Rate',
        value: '72 bpm',
        timestamp: DateTime.now().subtract(const Duration(days: 2)),
        status: HealthStatus.normal,
      ),
      HealthMetric(
        type: 'Weight',
        value: '68 kg',
        timestamp: DateTime.now().subtract(const Duration(days: 3)),
        status: HealthStatus.normal,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.softGray,
      appBar: AppBar(
        title: Text(
          '${widget.familyInfo.elderlyName}님 건강',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: const [
            Tab(
              icon: Icon(Icons.dashboard),
              text: '건강 요약',
            ),
            Tab(
              icon: Icon(Icons.medication),
              text: '복용 약물',
            ),
            Tab(
              icon: Icon(Icons.trending_up),
              text: '건강 지표',
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildHealthSummaryTab(),
                _buildMedicationsTab(),
                _buildHealthMetricsTab(),
              ],
            ),
    );
  }

  Widget _buildHealthSummaryTab() {
    return RefreshIndicator(
      onRefresh: _loadHealthSummary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            // Daily Health Status Card
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppTheme.getCardShadow(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.favorite,
                        color: AppColors.warningRed,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '오늘의 건강 상태',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildHealthStatusRow(
                    '식사 횟수',
                    '${_healthSummary['dailyMealCount']}회',
                    _healthSummary['dailyMealCount'] >= 2 ? AppColors.normalGreen : AppColors.cautionOrange,
                    Icons.restaurant,
                  ),
                  const SizedBox(height: 12),
                  _buildHealthStatusRow(
                    '활동 상태',
                    _healthSummary['activityLevel'],
                    AppColors.normalGreen,
                    Icons.directions_walk,
                  ),
                  const SizedBox(height: 12),
                  _buildHealthStatusRow(
                    '수면 패턴',
                    _healthSummary['sleepPattern'],
                    AppColors.normalGreen,
                    Icons.bedtime,
                  ),
                  const SizedBox(height: 12),
                  _buildHealthStatusRow(
                    '약물 복용률',
                    '${_healthSummary['medicationCompliance']}%',
                    _healthSummary['medicationCompliance'] >= 80 ? AppColors.normalGreen : AppColors.cautionOrange,
                    Icons.medication,
                  ),
                ],
              ),
            ),

            // Recent Activity Card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppTheme.getCardShadow(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.timeline,
                        color: AppColors.primaryBlue,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '최근 활동',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildActivityItem(
                    '마지막 식사',
                    _formatTimeAgo(_healthSummary['lastMealTime']),
                    Icons.restaurant,
                  ),
                  const SizedBox(height: 12),
                  _buildActivityItem(
                    '휴대폰 사용',
                    _formatTimeAgo(_healthSummary['lastPhoneActivity']),
                    Icons.phone_android,
                  ),
                ],
              ),
            ),

            // Quick Actions Card
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppTheme.getCardShadow(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.medical_services,
                        color: AppColors.primaryBlue,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '건강 관리',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildQuickActionButton(
                          '병원 예약',
                          Icons.local_hospital,
                          () => _showFeatureComingSoon(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildQuickActionButton(
                          '응급 연락',
                          Icons.emergency,
                          () => _showFeatureComingSoon(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedicationsTab() {
    return RefreshIndicator(
      onRefresh: _loadMedications,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            // Medication Summary
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppTheme.getCardShadow(),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.medication,
                    color: AppColors.primaryBlue,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '복용 중인 약물',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.darkText,
                          ),
                        ),
                        Text(
                          '총 ${_medications.where((m) => m.isActive).length}개 약물',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.lightText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => _showFeatureComingSoon(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('추가'),
                  ),
                ],
              ),
            ),

            // Medications List
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _medications.length,
              itemBuilder: (context, index) {
                final medication = _medications[index];
                return _buildMedicationCard(medication);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthMetricsTab() {
    return RefreshIndicator(
      onRefresh: _loadHealthMetrics,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            // Meal Pattern Chart
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppTheme.getCardShadow(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.bar_chart,
                        color: AppColors.primaryBlue,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '최근 7일 식사 패턴',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    child: _buildMealPatternChart(),
                  ),
                ],
              ),
            ),

            // Health Metrics List
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppTheme.getCardShadow(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.monitor_heart,
                        color: AppColors.warningRed,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '최근 건강 지표',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _recentMetrics.length,
                    itemBuilder: (context, index) {
                      final metric = _recentMetrics[index];
                      return _buildHealthMetricItem(metric);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthStatusRow(String label, String value, Color color, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.lightText,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildActivityItem(String label, String time, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primaryBlue, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.lightText,
          ),
        ),
        const Spacer(),
        Text(
          time,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.darkText,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionButton(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primaryBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primaryBlue, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedicationCard(MedicationReminder medication) {
    final nextDoseTime = _getNextDoseTime(medication);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: medication.isActive 
                          ? AppColors.primaryBlue.withOpacity(0.1)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.medication,
                      color: medication.isActive ? AppColors.primaryBlue : Colors.grey,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          medication.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.darkText,
                          ),
                        ),
                        Text(
                          '${medication.dosage} • ${medication.frequency}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.lightText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: medication.isActive,
                    onChanged: (value) {
                      setState(() {
                        medication.isActive = value;
                      });
                    },
                    activeColor: AppColors.primaryBlue,
                  ),
                ],
              ),
              if (medication.isActive) ...[
                const SizedBox(height: 12),
                Divider(color: Colors.grey.shade200),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.schedule, color: AppColors.lightText, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '다음 복용: $nextDoseTime',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.lightText,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '마지막: ${_formatTimeAgo(medication.lastTaken)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.lightText,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHealthMetricItem(HealthMetric metric) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.softGray,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            _getMetricIcon(metric.type),
            color: _getStatusColor(metric.status),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.type,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.darkText,
                  ),
                ),
                Text(
                  DateFormat('MM월 dd일 HH:mm').format(metric.timestamp),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.lightText,
                  ),
                ),
              ],
            ),
          ),
          Text(
            metric.value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _getStatusColor(metric.status),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMealPatternChart() {
    // Mock data for the last 7 days
    final List<FlSpot> spots = [
      const FlSpot(0, 3),
      const FlSpot(1, 2),
      const FlSpot(2, 3),
      const FlSpot(3, 2),
      const FlSpot(4, 3),
      const FlSpot(5, 2),
      const FlSpot(6, 2),
    ];

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: TextStyle(fontSize: 12, color: AppColors.lightText),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                final days = ['월', '화', '수', '목', '금', '토', '일'];
                return Text(
                  days[value.toInt()],
                  style: TextStyle(fontSize: 12, color: AppColors.lightText),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppColors.primaryBlue,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) =>
                  FlDotCirclePainter(
                radius: 4,
                color: AppColors.primaryBlue,
                strokeWidth: 2,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.primaryBlue.withValues(alpha: 0.1),
            ),
          ),
        ],
        minY: 0,
        maxY: 4,
      ),
    );
  }

  IconData _getMetricIcon(String type) {
    switch (type) {
      case 'Blood Pressure':
        return Icons.monitor_heart;
      case 'Heart Rate':
        return Icons.favorite;
      case 'Weight':
        return Icons.scale;
      default:
        return Icons.health_and_safety;
    }
  }

  Color _getStatusColor(HealthStatus status) {
    switch (status) {
      case HealthStatus.normal:
        return AppColors.normalGreen;
      case HealthStatus.caution:
        return AppColors.cautionOrange;
      case HealthStatus.warning:
        return AppColors.warningRed;
    }
  }

  String _getNextDoseTime(MedicationReminder medication) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    for (final timeSlot in medication.timeSlots) {
      final doseTime = today.add(Duration(hours: timeSlot.hour, minutes: timeSlot.minute));
      if (doseTime.isAfter(now)) {
        return DateFormat('HH:mm').format(doseTime);
      }
    }
    
    // If no more doses today, show first dose tomorrow
    final tomorrow = today.add(const Duration(days: 1));
    final firstDose = tomorrow.add(Duration(
      hours: medication.timeSlots.first.hour,
      minutes: medication.timeSlots.first.minute,
    ));
    return '내일 ${DateFormat('HH:mm').format(firstDose)}';
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}분 전';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}시간 전';
    } else {
      return '${difference.inDays}일 전';
    }
  }

  void _showFeatureComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('이 기능은 곧 추가될 예정입니다'),
        backgroundColor: AppColors.primaryBlue,
      ),
    );
  }
}

// Health-related data models
class MedicationReminder {
  final String name;
  final String dosage;
  final String frequency;
  final List<TimeOfDay> timeSlots;
  final DateTime lastTaken;
  bool isActive;

  MedicationReminder({
    required this.name,
    required this.dosage,
    required this.frequency,
    required this.timeSlots,
    required this.lastTaken,
    required this.isActive,
  });
}

class HealthMetric {
  final String type;
  final String value;
  final DateTime timestamp;
  final HealthStatus status;

  HealthMetric({
    required this.type,
    required this.value,
    required this.timestamp,
    required this.status,
  });
}

enum HealthStatus {
  normal,
  caution,
  warning,
}