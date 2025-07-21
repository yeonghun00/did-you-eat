import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/family_record.dart';
import '../services/firebase_service.dart';
import '../services/child_app_service.dart';
import '../constants/colors.dart';

class HistoryScreen extends StatefulWidget {
  final String familyCode;
  final FamilyInfo familyInfo;

  const HistoryScreen({
    Key? key,
    required this.familyCode,
    required this.familyInfo,
  }) : super(key: key);

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final ChildAppService _childService = ChildAppService();
  List<Map<String, dynamic>> _allMeals = [];
  bool _isLoading = true;
  String _selectedPeriod = '7일';

  @override
  void initState() {
    super.initState();
    _loadMeals();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadMeals() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get all meals using Firebase service
      final now = DateTime.now();
      final days = _selectedPeriod == '7일' ? 7 : _selectedPeriod == '30일' ? 30 : 90;
      final startDate = now.subtract(Duration(days: days));
      
      final mealsByDate = await FirebaseService.getMealsInRange(
        widget.familyCode,
        startDate,
        now,
      );
      
      // Convert to flat list with date info
      final List<Map<String, dynamic>> allMeals = [];
      mealsByDate.forEach((date, meals) {
        for (final meal in meals) {
          allMeals.add({
            'date': date,
            'timestamp': meal.timestamp.toIso8601String(),
            'mealNumber': meal.mealNumber,
            'elderlyName': meal.elderlyName,
          });
        }
      });
      
      // Sort by timestamp descending (newest first)
      allMeals.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));

      setState(() {
        _allMeals = allMeals;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading meals: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.softGray,
      appBar: AppBar(
        title: const Text(
          '식사 히스토리',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 기간 선택 탭
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  spreadRadius: 1,
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: ['7일', '30일', '90일'].map((period) {
                final isSelected = _selectedPeriod == period;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedPeriod = period;
                      });
                      _loadMeals();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primaryBlue : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        period,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isSelected ? Colors.white : AppColors.darkText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // 식사 기록 리스트
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _allMeals.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.history,
                              size: 64,
                              color: AppColors.lightText,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '선택한 기간에 식사 기록이 없습니다',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: AppColors.darkText,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '부모님이 식사하시면 여기에 표시됩니다',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.lightText,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _allMeals.length,
                        itemBuilder: (context, index) {
                          final meal = _allMeals[index];
                          return _buildMealCard(meal);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildMealCard(Map<String, dynamic> meal) {
    final timestamp = DateTime.parse(meal['timestamp']);
    final mealNumber = meal['mealNumber'] as int;
    final elderlyName = meal['elderlyName'] as String? ?? '부모님';
    final date = meal['date'] as String;

    // Format date label
    final mealDate = DateTime.parse(date);
    final isToday = DateFormat('yyyy-MM-dd').format(mealDate) == 
                   DateFormat('yyyy-MM-dd').format(DateTime.now());
    final isYesterday = DateFormat('yyyy-MM-dd').format(mealDate) == 
                       DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 1)));

    String dateLabel;
    if (isToday) {
      dateLabel = '오늘';
    } else if (isYesterday) {
      dateLabel = '어제';
    } else {
      dateLabel = DateFormat('M월 d일 (E)', 'ko_KR').format(mealDate);
    }
    
    String getMealName(int mealNumber) {
      switch (mealNumber) {
        case 1: return '아침';
        case 2: return '점심';
        case 3: return '저녁';
        default: return '식사';
      }
    }

    Color getMealColor(int mealNumber) {
      switch (mealNumber) {
        case 1: return Colors.orange;
        case 2: return Colors.green;
        case 3: return Colors.blue;
        default: return AppColors.primaryBlue;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: getMealColor(mealNumber).withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.restaurant,
                  size: 18,
                  color: getMealColor(mealNumber),
                ),
                const SizedBox(width: 8),
                Text(
                  '$elderlyName님의 ${getMealName(mealNumber)} 식사',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: getMealColor(mealNumber),
                  ),
                ),
                const Spacer(),
                Text(
                  dateLabel,
                  style: TextStyle(
                    fontSize: 14,
                    color: getMealColor(mealNumber),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // 내용
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 시간 정보와 식사 정보
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 16,
                      color: AppColors.lightText,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('HH:mm').format(timestamp),
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.lightText,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: getMealColor(mealNumber).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${mealNumber}회차',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: getMealColor(mealNumber),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // 식사 정보 카드
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: getMealColor(mealNumber).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: getMealColor(mealNumber),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          Icons.restaurant,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${getMealName(mealNumber)} 식사 완료',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.darkText,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$elderlyName님이 식사하셨습니다',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.lightText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.check_circle,
                        color: getMealColor(mealNumber),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}