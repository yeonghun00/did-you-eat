import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'screens/family_setup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/history_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/account_deleted_screen.dart';
import 'services/firebase_service.dart';
import 'services/child_app_service.dart';
import 'services/fcm_message_service.dart';
import 'services/fcm_token_service.dart';
import 'models/family_record.dart';
import 'theme/app_theme.dart';
import 'constants/colors.dart';

void main() {
  runApp(const LoveEverydayApp());
}

class LoveEverydayApp extends StatelessWidget {
  const LoveEverydayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '식사 기록',
      theme: AppTheme.lightTheme,
      home: const FirebaseInitWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class FirebaseInitWrapper extends StatefulWidget {
  const FirebaseInitWrapper({super.key});

  @override
  State<FirebaseInitWrapper> createState() => _FirebaseInitWrapperState();
}

class _FirebaseInitWrapperState extends State<FirebaseInitWrapper> {
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initializeFirebase();
  }

  Future<void> _initializeFirebase() async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

      // Initialize FCM message service
      try {
        await FCMMessageService.initialize();
        print('✅ FCM Message Service initialized successfully');
        
        // Request notification permissions
        final permissionGranted = await FCMTokenService.requestPermissions();
        print('🔔 Notification permissions granted: $permissionGranted');
        
        // Set up token refresh listener
        FCMTokenService.setupTokenRefreshListener();
        print('🔄 FCM token refresh listener setup complete');
      } catch (e) {
        print('⚠️ FCM initialization failed: $e');
      }

      // Anonymous authentication
      try {
        final userCredential = await FirebaseAuth.instance.signInAnonymously();
        print('Anonymous authentication successful: ${userCredential.user?.uid}');
      } catch (e) {
        print('Anonymous authentication failed: $e');
      }

      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      print('Firebase initialization failed: $e');
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Scaffold(
        backgroundColor: AppTheme.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: AppTheme.primaryBlue,
              ),
              const SizedBox(height: 16),
              const Text(
                'Firebase 초기화 실패',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _hasError = false;
                    _isInitialized = false;
                  });
                  _initializeFirebase();
                },
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: AppTheme.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.family_restroom,
                  size: 48,
                  color: AppTheme.white,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                '앱 초기화 중...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      );
    }

    return const SplashScreen();
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // 스플래시 화면 표시 시간
    await Future.delayed(const Duration(seconds: 2));

    try {
      // 기존 가족 코드 확인
      final prefs = await SharedPreferences.getInstance();
      final familyCode = prefs.getString('family_code');

      if (familyCode != null) {
        // 가족 코드가 있으면 계정 삭제 여부부터 확인
        final childService = ChildAppService();
        final familyExists = await childService.checkFamilyExists(familyCode);

        if (!familyExists) {
          // 가족 계정이 삭제된 경우
          await prefs.clear(); // 모든 저장된 데이터 삭제
          Navigator.pushReplacement(
            context,
            AppTheme.fadeTransition(page: const AccountDeletedScreen()),
          );
          return;
        }

        // 가족 코드가 존재하면 유효성 검사 (connectionCode를 사용)
        final familyData = await childService.getFamilyInfo(familyCode);

        if (familyData != null && familyData['approved'] == true) {
          // 유효하고 승인된 가족 코드이면 홈 화면으로 이동
          final familyInfo = FamilyInfo.fromMap({
            'familyCode': familyCode,
            ...familyData,
          });

          // Register FCM token for this family
          final familyId = familyData['familyId'] as String?;
          if (familyId != null) {
            Future.delayed(const Duration(seconds: 2), () async {
              try {
                final registered = await FCMTokenService.registerChildToken(familyId);
                if (registered) {
                  print('✅ FCM token registered for family: $familyId');
                } else {
                  print('⚠️ FCM token registration failed');
                }
              } catch (e) {
                print('❌ Failed to register FCM token: $e');
              }
            });
          }

          Navigator.pushReplacement(
            context,
            AppTheme.slideTransition(
              page: HomeScreen(familyCode: familyCode, familyInfo: familyInfo),
            ),
          );
          return;
        } else {
          // 유효하지 않거나 승인되지 않은 가족 코드이면 제거
          await prefs.remove('family_code');
        }
      }

      // 가족 코드가 없거나 유효하지 않으면 설정 화면으로 이동
      Navigator.pushReplacement(
        context,
        AppTheme.slideTransition(page: const FamilySetupScreen()),
      );
    } catch (e) {
      print('Error initializing app: $e');
      // 에러 발생 시 설정 화면으로 이동
      Navigator.pushReplacement(
        context,
        AppTheme.fadeTransition(page: const FamilySetupScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 앱 아이콘
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue,
                borderRadius: BorderRadius.circular(20),
                boxShadow: AppTheme.getCardShadow(elevation: 8),
              ),
              child: const Icon(
                Icons.family_restroom,
                size: 48,
                color: AppTheme.white,
              ),
            ),

            const SizedBox(height: 32),

            // 앱 이름
            const Text(
              '식사 기록',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark,
                letterSpacing: -0.5,
              ),
            ),

            const SizedBox(height: 8),

            // 부제목
            const Text(
              '부모님 안전 모니터링',
              style: TextStyle(
                fontSize: 16,
                color: AppTheme.textMedium,
                fontWeight: FontWeight.w500,
              ),
            ),

            const SizedBox(height: 40),

            // 로딩 인디케이터
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryBlue),
                backgroundColor: AppTheme.gray200,
                strokeWidth: 2.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
