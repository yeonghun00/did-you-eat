import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'screens/family_setup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/account_deleted_screen.dart';
import 'screens/auth/login_screen.dart';
import 'services/child_app_service.dart';
import 'services/fcm_message_service.dart';
import 'services/fcm_token_service.dart';
import 'services/auth_service.dart';
import 'models/family_record.dart';
import 'theme/app_theme.dart';
import 'utils/app_lifecycle_handler.dart';
import 'utils/connectivity_checker.dart';

void main() {
  runApp(const LoveEverydayApp());
}

class LoveEverydayApp extends StatelessWidget {
  const LoveEverydayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '식사하셨어요?',
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
  final AppLifecycleHandler _lifecycleHandler = AppLifecycleHandler();
  final ConnectivityChecker _connectivityChecker = ConnectivityChecker();

  @override
  void initState() {
    super.initState();
    _initializeFirebase();
  }

  @override
  void dispose() {
    _lifecycleHandler.dispose();
    _connectivityChecker.dispose();
    super.dispose();
  }

  Future<void> _initializeFirebase() async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      
      // Check network connectivity first
      final connectivityStatus = await _connectivityChecker.checkConnectivity();
      if (connectivityStatus == ConnectivityStatus.disconnected) {
        print('No network connection, waiting for connectivity...');
        final hasConnection = await _connectivityChecker.waitForConnection(
          timeout: const Duration(seconds: 15),
        );
        if (!hasConnection) {
          throw Exception('No network connection available');
        }
      }
      
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

      // FCM and Firebase are now initialized
      // Authentication will be handled by AuthWrapper

      // Initialize other services after Firebase is ready
      _lifecycleHandler.initialize();
      _connectivityChecker.initialize();

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

    return const AuthWrapper();
  }
}

// AuthWrapper handles authentication state and routing with error recovery
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final AuthService _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authService.authStateChanges,
      builder: (context, snapshot) {
        // Show loading while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }
        
        // Handle connection errors or auth failures
        if (snapshot.hasError) {
          print('Auth stream error: ${snapshot.error}');
          return _buildErrorRecoveryWidget(snapshot.error.toString());
        }
        
        // User is signed in and valid
        if (snapshot.hasData && snapshot.data != null) {
          final user = snapshot.data!;
          
          // Check if user is properly authenticated (not anonymous)
          if (user.isAnonymous) {
            print('⚠️ WARNING: User is anonymous, redirecting to login');
            return const LoginScreen();
          }
          
          print('✅ User properly authenticated: ${user.email ?? user.uid}');
          return const AuthenticatedApp();
        }
        
        // No user - show login screen (no need for auth recovery with proper auth)
        return const LoginScreen();
      },
    );
  }

  Widget _buildErrorRecoveryWidget(String error) {
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
              '연결 문제 발생',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '네트워크 연결을 확인하고 다시 시도해주세요.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                // Restart the app authentication flow
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              },
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}

// Handles app logic for authenticated users
class AuthenticatedApp extends StatefulWidget {
  const AuthenticatedApp({super.key});

  @override
  State<AuthenticatedApp> createState() => _AuthenticatedAppState();
}

class _AuthenticatedAppState extends State<AuthenticatedApp> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  String _extractDeviceInfo(dynamic deviceInfo) {
    if (deviceInfo is String) {
      return deviceInfo;
    } else if (deviceInfo is Map) {
      return deviceInfo['lastUpdateSource']?.toString() ?? 'Unknown';
    } else {
      return 'Unknown';
    }
  }

  Future<void> _initializeApp() async {
    // Small delay for smooth transition
    await Future.delayed(const Duration(seconds: 1));

    try {
      // Check user profile for family codes
      final authService = AuthService();
      final currentUser = authService.currentUser;
      print('🔍 Checking user profile for family codes...');
      print('👤 Current user: ${currentUser?.email ?? currentUser?.uid ?? 'null'}');
      
      final userProfile = await authService.getUserProfile();
      
      if (userProfile != null) {
        print('✅ User profile found: ${userProfile.keys}');
        print('📊 Full profile data: $userProfile');
        
        if (userProfile['familyCodes'] != null) {
          final familyCodes = List<String>.from(userProfile['familyCodes']);
          print('📱 Family codes in profile: $familyCodes (count: ${familyCodes.length})');
          
          if (familyCodes.isNotEmpty) {
            // Use the first (most recent) family code
            final familyCode = familyCodes.first;
            print('🔑 Using family code: $familyCode');
            print('💾 Family code CONFIRMED in user profile - should persist across sessions');
            
            // Validate family code and check if approved
            final childService = ChildAppService();
            final familyExists = await childService.checkFamilyExists(familyCode);

            if (familyExists == null) {
              // Network error - show retry dialog instead of account deletion
              print('⚠️ Network error checking family existence - KEEPING code in profile');
              print('Family code preserved: $familyCode');
              if (!mounted) return;
              final shouldRetry = await _showProfileRetryDialog();
              
              if (shouldRetry) {
                _initializeApp();
                return;
              } else {
                // User chose to re-enter family code - but DON'T remove existing code
                print('📝 User chose family setup but preserving existing code: $familyCode');
                Navigator.pushReplacement(
                  context,
                  AppTheme.slideTransition(page: const FamilySetupScreen()),
                );
                return;
              }
            }

            if (familyExists == false) {
              // Family actually deleted - remove from user profile
              print('❌ Family was actually deleted by parent app');
              await authService.removeFamilyCode(familyCode);
              if (!mounted) return;
              Navigator.pushReplacement(
                context,
                AppTheme.fadeTransition(page: const AccountDeletedScreen()),
              );
              return;
            }

            final familyData = await childService.getFamilyInfo(familyCode);
            if (familyData != null && familyData['approved'] == true) {
              // Valid and approved family code
              print('🔍 Raw family data: $familyData');
              print('📊 Family data keys: ${familyData.keys.toList()}');
              print('📊 Family data types: ${familyData.map((key, value) => MapEntry(key, value.runtimeType))}');
              
              // Only pass the fields that FamilyInfo constructor expects
              final familyInfo = FamilyInfo.fromMap({
                'familyCode': familyCode,
                'elderlyName': familyData['elderlyName'] ?? '',
                'createdAt': familyData['createdAt'],
                'lastMealTime': familyData['lastMealTime'],
                'isActive': familyData['isActive'] ?? false,
                'deviceInfo': _extractDeviceInfo(familyData['deviceInfo']),
              });

              // Register FCM token
              final familyId = familyData['familyId'] as String?;
              if (familyId != null) {
                Future.delayed(const Duration(seconds: 2), () async {
                  try {
                    await FCMTokenService.registerChildToken(familyId);
                  } catch (e) {
                    // Handle FCM token registration error silently
                  }
                });
              }

              if (!mounted) return;

              Navigator.pushReplacement(
                context,
                AppTheme.slideTransition(
                  page: HomeScreen(familyCode: familyCode, familyInfo: familyInfo),
                ),
              );
              return;
            } else {
              // Family code exists but not approved or network error - DON'T remove from profile
              print('⚠️ Family code exists but not approved or network error - keeping code in profile');
              print('Family data: $familyData');
              
              // Show retry dialog instead of removing family code
              if (!mounted) return;
              final shouldRetry = await _showProfileRetryDialog();
              
              if (shouldRetry) {
                _initializeApp();
                return;
              }
              // If user chooses not to retry, go to family setup but DON'T remove code
            }
          } else {
            print('❌ No family codes found in user profile');
          }
        } else {
          print('❌ familyCodes field is null in user profile');
        }
      } else {
        print('❌ No user profile found - this might be a network issue');
        
        // Show retry dialog instead of immediately going to family setup
        if (!mounted) return;
        final shouldRetry = await _showProfileRetryDialog();
        
        if (shouldRetry) {
          // Retry initialization
          _initializeApp();
          return;
        }
      }

      // No valid family code, go to family setup
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        AppTheme.slideTransition(page: const FamilySetupScreen()),
      );
    } catch (e) {
      print('❌ Error during app initialization: $e');
      
      // Show retry option for network/connection errors
      if (!mounted) return;
      final shouldRetry = await _showProfileRetryDialog();
      
      if (shouldRetry) {
        _initializeApp();
        return;
      }
      
      // If user chooses not to retry, go to family setup
      Navigator.pushReplacement(
        context,
        AppTheme.fadeTransition(page: const FamilySetupScreen()),
      );
    }
  }

  Future<bool> _showProfileRetryDialog() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.refresh, color: AppTheme.primaryBlue),
            const SizedBox(width: 8),
            const Text('연결 문제'),
          ],
        ),
        content: const Text(
          '사용자 정보를 불러오는 중 문제가 발생했습니다.\n'
          '네트워크 연결을 확인하고 다시 시도하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('가족 코드 재입력'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('다시 시도'),
          ),
        ],
      ),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return const SplashScreen();
  }
}

// Splash screen component
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

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
              '식사하셨어요?',
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
