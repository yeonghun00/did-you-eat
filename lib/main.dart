import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'screens/family_setup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/account_deleted_screen.dart';
import 'screens/auth/login_screen.dart';
import 'services/child_app_service.dart';
import 'services/fcm_message_service.dart';
import 'services/fcm_token_service.dart';
import 'services/auth_service.dart';
import 'services/session_manager.dart';
import 'models/family_record.dart';
import 'theme/app_theme.dart';
import 'utils/app_lifecycle_handler.dart';
import 'utils/connectivity_checker.dart';
import 'utils/secure_logger.dart';

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
      
      // Initialize secure logging first
      secureLog.initialize();
      
      // Check network connectivity first
      final connectivityStatus = await _connectivityChecker.checkConnectivity();
      if (connectivityStatus == ConnectivityStatus.disconnected) {
        secureLog.warning('No network connection, waiting for connectivity');
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
        secureLog.info('FCM Message Service initialized successfully');
        
        // Request notification permissions
        final permissionGranted = await FCMTokenService.requestPermissions();
        secureLog.info('Notification permissions granted: $permissionGranted');
        
        // Set up token refresh listener
        FCMTokenService.setupTokenRefreshListener();
        secureLog.info('FCM token refresh listener setup complete');
        
        // Set up FCM message handling for debugging
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          print('🔥 FIREBASE: Received foreground message: ${message.messageId}');
          print('🔥 FIREBASE: Title: ${message.notification?.title}');
          print('🔥 FIREBASE: Body: ${message.notification?.body}');
          print('🔥 FIREBASE: Data: ${message.data}');
        });
        
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          print('🔥 FIREBASE: App opened from notification: ${message.messageId}');
          print('🔥 FIREBASE: Data: ${message.data}');
        });
        
        // Check for initial message when app was opened from notification
        RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
        if (initialMessage != null) {
          print('🔥 FIREBASE: App launched from notification: ${initialMessage.messageId}');
        }
      } catch (e) {
        secureLog.error('FCM initialization failed', e);
      }

      // FCM and Firebase are now initialized
      // Ensure basic Firebase Auth is ready
      try {
        // Initialize AuthService to set up proper authentication state
        final authService = AuthService();
        await authService.initialize();
        secureLog.info('AuthService initialized successfully');
      } catch (e) {
        secureLog.warning('AuthService initialization failed, but continuing', e);
      }

      // Initialize other services after Firebase is ready
      _lifecycleHandler.initialize();
      _connectivityChecker.initialize();
      
      // Initialize session manager
      await SessionManager().initialize();

      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      secureLog.error('Firebase initialization failed', e);
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
          secureLog.error('Auth stream error', snapshot.error);
          return _buildErrorRecoveryWidget(snapshot.error.toString());
        }
        
        // User is signed in and valid
        if (snapshot.hasData && snapshot.data != null) {
          final user = snapshot.data!;
          
          // Check if user is properly authenticated (not anonymous)
          if (user.isAnonymous) {
            secureLog.warning('WARNING: User is anonymous, redirecting to login');
            return const LoginScreen();
          }
          
          secureLog.security('User properly authenticated');
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
      final authService = AuthService();
      final sessionManager = SessionManager();
      
      // Initialize services
      await authService.initialize();
      await sessionManager.initialize();
      
      // Try to restore existing session first
      final sessionRestored = await sessionManager.restoreSession();
      
      if (sessionRestored && sessionManager.hasValidSession) {
        secureLog.info('Session restored from storage');
        final familyCode = sessionManager.currentFamilyCode!;
        final cachedData = sessionManager.cachedFamilyData;
        
        // Validate session is still good - but be more forgiving about network issues
        final childService = ChildAppService();
        
        try {
          final familyExists = await childService.checkFamilyExists(familyCode);
          
          if (familyExists == true) {
            // Family exists - proceed to home
            final familyInfo = FamilyInfo.fromMap({
              'familyCode': familyCode,
              'elderlyName': cachedData?['elderlyName'] ?? '',
              'createdAt': cachedData?['createdAt'],
              'lastMealTime': cachedData?['lastMealTime'], // Handled in child_app_service.dart parsing
              'isActive': cachedData?['isActive'] ?? false,
              'deviceInfo': _extractDeviceInfo(cachedData?['deviceInfo']),
            });
            
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              AppTheme.slideTransition(
                page: HomeScreen(familyCode: familyCode, familyInfo: familyInfo),
              ),
            );
            return;
          } else if (familyExists == false) {
            // Only show account deleted if we're absolutely sure (not network error)
            secureLog.warning('Family definitively does not exist - showing account deleted');
            await sessionManager.clearSession();
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              AppTheme.fadeTransition(page: const AccountDeletedScreen()),
            );
            return;
          }
          // If familyExists == null (network error), continue with normal flow and try cached data
        } catch (e) {
          // Network or Firebase error - don't assume account is deleted
          secureLog.warning('Error checking family existence, continuing with cached data: $e');
        }
        
        // If we have cached data but network check failed, still try to proceed with cached data
        if (cachedData != null && cachedData['elderlyName'] != null) {
          secureLog.info('Using cached data due to network issues');
          final familyInfo = FamilyInfo.fromMap({
            'familyCode': familyCode,
            'elderlyName': cachedData['elderlyName'] ?? '',
            'createdAt': cachedData['createdAt'],
            'lastMealTime': cachedData['lastMealTime'],
            'isActive': cachedData['isActive'] ?? false,
            'deviceInfo': _extractDeviceInfo(cachedData['deviceInfo']),
          });
          
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            AppTheme.slideTransition(
              page: HomeScreen(familyCode: familyCode, familyInfo: familyInfo),
            ),
          );
          return;
        }
      }
      
      // Fallback to user profile check
      final currentUser = authService.currentUser;
      secureLog.debug('Checking user profile for family codes');
      
      final userProfile = await authService.getUserProfile();
      
      if (userProfile != null) {
        secureLog.debug('User profile found with keys: ${userProfile.keys}');
        
        if (userProfile['familyCodes'] != null) {
          final familyCodes = List<String>.from(userProfile['familyCodes']);
          secureLog.debug('Family codes in profile (count: ${familyCodes.length})');
          
          if (familyCodes.isNotEmpty) {
            // Use the first (most recent) family code
            final familyCode = familyCodes.first;
            secureLog.security('Using family code from profile - should persist across sessions');
            
            // Start session with this family code
            await sessionManager.startSession(familyCode, null);
            
            // Validate family code and check if approved
            final childService = ChildAppService();
            final familyExists = await childService.checkFamilyExists(familyCode);

            if (familyExists == null) {
              // Network error - show retry dialog instead of account deletion
              secureLog.warning('Network error checking family existence - KEEPING code in profile');
              if (!mounted) return;
              final shouldRetry = await _showProfileRetryDialog();
              
              if (shouldRetry) {
                _initializeApp();
                return;
              } else {
                // User chose to re-enter family code - but DON'T remove existing code
                secureLog.info('User chose family setup but preserving existing family code');
                Navigator.pushReplacement(
                  context,
                  AppTheme.slideTransition(page: const FamilySetupScreen()),
                );
                return;
              }
            }

            if (familyExists == false) {
              // Family actually deleted - remove from user profile
              secureLog.warning('Family was actually deleted by parent app');
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
              secureLog.debug('Raw family data keys: ${familyData.keys.toList()}');
              
              // Update session with family data
              await sessionManager.startSession(familyCode, familyData);
              
              // Only pass the fields that FamilyInfo constructor expects
              final familyInfo = FamilyInfo.fromMap({
                'familyCode': familyCode,
                'elderlyName': familyData['elderlyName'] ?? '',
                'createdAt': familyData['createdAt'],
                'lastMealTime': familyData['lastMealTime'], // Handled in child_app_service.dart parsing
                'isActive': familyData['isActive'] ?? false,
                'deviceInfo': _extractDeviceInfo(familyData['deviceInfo']),
              });

              // Register FCM token for existing connections
              final familyId = familyData['familyId'] as String?;
              if (familyId != null) {
                Future.delayed(const Duration(seconds: 1), () async {
                  try {
                    print('🔔 Registering FCM token for existing family connection: $familyId');
                    final registered = await FCMTokenService.registerChildToken(familyId);
                    if (registered) {
                      print('✅ FCM token registered for existing family');
                    } else {
                      print('⚠️ FCM token registration failed for existing family');
                    }
                  } catch (e) {
                    print('❌ Failed to register FCM token for existing family: $e');
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
              secureLog.warning('Family code exists but not approved or network error - keeping code in profile');
              
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
            secureLog.warning('No family codes found in user profile');
          }
        } else {
          secureLog.warning('familyCodes field is null in user profile');
        }
      } else {
        secureLog.warning('No user profile found - this might be a network issue');
        
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
      secureLog.error('Error during app initialization', e);
      
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
