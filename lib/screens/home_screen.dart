import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:love_everyday/theme/app_theme.dart';
import '../models/family_record.dart';
import '../services/firebase_service.dart';
import '../services/child_app_service.dart';
import '../widgets/today_meal_section.dart';
import '../widgets/survival_monitor_widget.dart';
import '../widgets/location_card_widget.dart';
import '../constants/colors.dart';
import 'history_screen.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';
import 'account_deleted_screen.dart';

class HomeScreen extends StatefulWidget {
  final String familyCode;
  final FamilyInfo familyInfo;

  const HomeScreen({
    super.key,
    required this.familyCode,
    required this.familyInfo,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final ChildAppService _childService = ChildAppService();
  ParentStatusInfo? _statusInfo;
  List<MealRecord> _todayMeals = [];
  bool _isLoading = true;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadInitialData();
    _setupRealtimeListeners();
    _monitorFamilyExistence();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutBack),
        );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      print('Loading initial data for family code: ${widget.familyCode}');

      final statusInfo = await FirebaseService.getParentStatus(
        widget.familyCode,
      );
      print('Status info loaded: ${statusInfo.status} - ${statusInfo.message}');

      final todayMeals = await FirebaseService.getTodayMeals(widget.familyCode);
      print('Today meals loaded: ${todayMeals.length} meals');

      setState(() {
        _statusInfo = statusInfo;
        _todayMeals = todayMeals;
        _isLoading = false;
      });

      // Start animations after data loads
      _fadeController.forward();
      Future.delayed(const Duration(milliseconds: 200), () {
        _slideController.forward();
      });
    } catch (e) {
      print('Error loading initial data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _setupRealtimeListeners() {
    // 오늘 식사 기록 실시간 업데이트
    FirebaseService.getTodayMealsStream(widget.familyCode).listen((meals) {
      setState(() {
        _todayMeals = meals;
      });
      _updateParentStatus();
    });

    // 가족 정보 실시간 업데이트
    FirebaseService.getFamilyInfoStream(widget.familyCode).listen((familyInfo) {
      if (familyInfo != null) {
        _updateParentStatus();
      }
    });
  }

  Future<void> _updateParentStatus() async {
    try {
      final statusInfo = await FirebaseService.getParentStatus(
        widget.familyCode,
      );
      setState(() {
        _statusInfo = statusInfo;
      });
    } catch (e) {
      print('Error updating parent status: $e');
    }
  }

  void _monitorFamilyExistence() {
    _childService.listenToFamilyExistence(widget.familyCode).listen((exists) {
      print('Family document exists: $exists');
      if (!exists) {
        print('Family document deleted, navigating to account deleted screen');
        // Navigate to account deleted screen
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const AccountDeletedScreen()),
          (route) => false,
        );
      }
    });
  }


  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.softGray,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.restaurant_menu,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              '식사 기록',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 20,
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.primaryBlue,
        elevation: 0,
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primaryBlue,
                AppColors.primaryBlue.withOpacity(0.8),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.settings, color: Colors.white, size: 20),
            ),
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.push(
                context,
                AppTheme.slideTransition(
                  page: SettingsScreen(
                    familyCode: widget.familyCode,
                    familyInfo: widget.familyInfo,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '부모님 식사 정보를 불러오는 중...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadInitialData,
              color: AppColors.primaryBlue,
              backgroundColor: Colors.white,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: Column(
                      children: [
                        // 생존 신호 모니터링
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          child: SurvivalMonitorWidget(
                            familyCode: widget.familyCode,
                          ),
                        ),

                        // 위치 지도 카드
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          child: LocationCardWidget(
                            familyCode: widget.familyCode,
                          ),
                        ),

                        const SizedBox(height: 8),

                        // 오늘의 식사 기록 섹션
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          child: TodayMealSection(meals: _todayMeals),
                        ),

                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: 0,
        selectedItemColor: AppColors.primaryBlue,
        unselectedItemColor: AppColors.lightText,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: '기록'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications), label: '알림'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: '설정'),
        ],
        onTap: (index) {
          HapticFeedback.lightImpact();
          switch (index) {
            case 0:
              // 홈 - 현재 화면
              break;
            case 1:
              Navigator.push(
                context,
                AppTheme.slideTransition(
                  page: HistoryScreen(
                    familyCode: widget.familyCode,
                    familyInfo: widget.familyInfo,
                  ),
                ),
              );
              break;
            case 2:
              Navigator.push(
                context,
                AppTheme.slideTransition(
                  page: const NotificationsScreen(),
                  rightToLeft: false, // Bottom-up transition for notifications
                ),
              );
              break;
            case 3:
              Navigator.push(
                context,
                AppTheme.slideTransition(
                  page: SettingsScreen(
                    familyCode: widget.familyCode,
                    familyInfo: widget.familyInfo,
                  ),
                ),
              );
              break;
          }
        },
      ),
    );
  }
}
