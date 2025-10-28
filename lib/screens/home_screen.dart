import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:love_everyday/theme/app_theme.dart';
import '../models/family_record.dart';
import '../services/firebase_service.dart';
import '../services/child_app_service.dart';
import '../services/subscription_manager.dart';
import '../models/subscription_model.dart';
import '../widgets/today_meal_section.dart';
import '../widgets/safety_status_widget.dart';
import '../widgets/location_card_widget.dart';
import '../services/safety_notification_service.dart';
import '../constants/colors.dart';
import 'activity_screen.dart';
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
  final SafetyNotificationService _safetyService = SafetyNotificationService();
  final SubscriptionManager _subscriptionManager = SubscriptionManager();
  ParentStatusInfo? _statusInfo;
  List<MealRecord> _todayMeals = [];
  SubscriptionInfo? _subscriptionInfo;
  bool _isLoading = true;
  Timer? _familyExistenceDebounceTimer;

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
    _startSafetyMonitoring();
    _initializeSubscription();
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
    _familyExistenceDebounceTimer?.cancel();
    _safetyService.stopMonitoring();
    _subscriptionManager.dispose();
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
    // DISABLED: Family existence is now properly handled in main.dart authentication flow
    // This was causing false positives when app is killed from background
    print('🔒 Family existence monitoring disabled - handled by authentication flow');
    
    // Instead, only check family existence periodically when app is actively being used
    // This prevents false account deletion during network issues or app backgrounding
    Timer.periodic(const Duration(minutes: 5), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      print('🔍 Periodic family existence check (every 5 minutes)...');
      final familyExists = await _childService.checkFamilyExists(widget.familyCode);
      
      if (familyExists == false && mounted) {
        // Only show account deleted if we're certain the family was deleted
        print('❌ CONFIRMED: Family was deleted during periodic check');
        timer.cancel();
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const AccountDeletedScreen()),
          (route) => false,
        );
      } else if (familyExists == null) {
        print('🌐 Network error during periodic check - will retry in 5 minutes');
      } else {
        print('✅ Family confirmed to exist during periodic check');
      }
    });
  }

  /// 안전 상태 모니터링 시작
  void _startSafetyMonitoring() {
    _safetyService.startMonitoring(widget.familyCode);
  }

  /// 구독 관리자 초기화 및 앱 시작 시 팝업 처리
  Future<void> _initializeSubscription() async {
    try {
      print('🔔 구독 매니저 초기화 시작');
      
      // 구독 매니저 초기화 (팝업 없이)
      await _subscriptionManager.initialize();
      
      // 구독 상태 실시간 리스너 설정
      _subscriptionManager.subscriptionStream.listen((subscriptionInfo) {
        if (mounted) {
          setState(() {
            _subscriptionInfo = subscriptionInfo;
          });
          print('🔄 구독 상태 업데이트: ${subscriptionInfo.status}');
        }
      });
      
      print('✅ 구독 매니저 초기화 완료');
    } catch (e) {
      print('❌ 구독 초기화 실패: $e');
    }
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

  /// 프리미엄 상태 정보 다이얼로그 표시
  void _showPremiumStatusDialog() {
    if (_subscriptionInfo == null) return;

    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.workspace_premium,
                  color: Colors.amber,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '구독 상태',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.amber.withOpacity(0.1),
                      Colors.amber.withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '현재 상태: ${_subscriptionInfo!.statusDescription}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                    if (_subscriptionInfo!.isInFreeTrial) ...[
                      const SizedBox(height: 8),
                      Text(
                        '무료 체험 ${_subscriptionManager.getDaysUntilExpiry()}일 남음',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textMedium,
                        ),
                      ),
                    ],
                    if (_subscriptionInfo!.status == SubscriptionStatus.active) ...[
                      const SizedBox(height: 8),
                      const Text(
                        '월 1,500원 • 자동 갱신 중',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.textMedium,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '프리미엄 기능',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '• 실시간 위치 추적\n'
                '• 안전 상태 알림\n'
                '• 식사 패턴 분석\n'
                '• 건강 리포트',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textMedium,
                  height: 1.5,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('확인'),
            ),
            if (!_subscriptionInfo!.canUsePremiumFeatures)
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => SettingsScreen(
                      familyCode: widget.familyCode,
                      familyInfo: widget.familyInfo,
                    )),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('구독 관리'),
              ),
          ],
        );
      },
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
              '식사하셨어요?',
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
                        // 안전 상태 모니터링
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          child: SafetyStatusWidget(
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
        unselectedItemColor: AppTheme.textLight,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.timeline), label: '활동기록'),
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
                  page: ActivityScreen(
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
