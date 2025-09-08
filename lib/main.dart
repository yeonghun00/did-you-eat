import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'screens/family_setup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/auth/login_screen.dart';
import 'services/child_app_service.dart';
import 'services/fcm_message_service.dart';
import 'services/fcm_token_service.dart';
import 'services/auth_service.dart';
import 'services/session_manager.dart';
import 'services/safety_notification_service.dart';
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
      home: const AppInitializer(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      
      // Initialize secure logging
      secureLog.initialize();
      
      // Initialize Firebase (handles network internally)
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

      // Initialize core services in order
      await _initializeServices();

      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      secureLog.error('App initialization failed', e);
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _initializeServices() async {
    final services = [
      () async {
        await FCMMessageService.initialize();
        await FCMTokenService.requestPermissions();
        FCMTokenService.setupTokenRefreshListener();
        _setupFCMListeners();
      },
      () => AuthService().initialize(),
      () => SessionManager().initialize(),
      () => SafetyNotificationService().initialize(),
      () async => AppLifecycleHandler().initialize(),
      () async => ConnectivityChecker().initialize(),
    ];

    for (final service in services) {
      try {
        await service();
      } catch (e) {
        secureLog.warning('Service initialization failed, continuing', e);
      }
    }
  }

  void _setupFCMListeners() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      secureLog.info('Received foreground message: ${message.messageId}');
      secureLog.debug('Title: ${message.notification?.title}');
      secureLog.debug('Body: ${message.notification?.body}');
    });
    
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      secureLog.info('App opened from notification: ${message.messageId}');
    });
    
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        secureLog.info('App launched from notification: ${message.messageId}');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _ErrorScreen(
        message: _errorMessage,
        onRetry: () {
          setState(() {
            _hasError = false;
            _isInitialized = false;
          });
          _initializeApp();
        },
      );
    }

    if (!_isInitialized) {
      return const _LoadingScreen(message: '앱 초기화 중...');
    }

    return const AuthWrapper();
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService().authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen(message: '로그인 확인 중...');
        }
        
        if (snapshot.hasError) {
          secureLog.error('Auth stream error', snapshot.error);
          return _ErrorScreen(
            message: '네트워크 연결을 확인하고 다시 시도해주세요.',
            onRetry: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const LoginScreen()),
            ),
          );
        }
        
        if (snapshot.hasData && snapshot.data != null) {
          final user = snapshot.data!;
          
          if (user.isAnonymous) {
            secureLog.warning('Anonymous user detected, redirecting to login');
            return const LoginScreen();
          }
          
          secureLog.security('User authenticated successfully');
          return const AuthenticatedApp();
        }
        
        return const LoginScreen();
      },
    );
  }
}

class AuthenticatedApp extends StatefulWidget {
  const AuthenticatedApp({super.key});

  @override
  State<AuthenticatedApp> createState() => _AuthenticatedAppState();
}

class _AuthenticatedAppState extends State<AuthenticatedApp> {
  @override
  void initState() {
    super.initState();
    _initializeUserSession();
  }

  Future<void> _initializeUserSession() async {
    await Future.delayed(const Duration(milliseconds: 500));

    try {
      final authService = AuthService();
      final sessionManager = SessionManager();
      
      await sessionManager.initialize();
      
      // Check for existing session
      if (await sessionManager.restoreSession() && sessionManager.hasValidSession) {
        final familyCode = sessionManager.currentFamilyCode!;
        if (await _validateAndNavigateToFamily(familyCode, sessionManager)) return;
      }
      
      // Check user profile for family codes
      final userProfile = await authService.getUserProfile();
      if (userProfile?['familyCodes'] != null) {
        final familyCodes = List<String>.from(userProfile!['familyCodes']);
        if (familyCodes.isNotEmpty) {
          final familyCode = familyCodes.first;
          await sessionManager.startSession(familyCode, null);
          if (await _validateAndNavigateToFamily(familyCode, sessionManager)) return;
        }
      }
      
      // No valid family found, go to setup
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        AppTheme.slideTransition(page: const FamilySetupScreen()),
      );
    } catch (e) {
      secureLog.error('Session initialization failed', e);
      if (!mounted) return;
      
      final shouldRetry = await _showRetryDialog();
      if (shouldRetry) {
        _initializeUserSession();
      } else {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            AppTheme.slideTransition(page: const FamilySetupScreen()),
          );
        }
      }
    }
  }

  Future<bool> _validateAndNavigateToFamily(String familyCode, SessionManager sessionManager) async {
    try {
      final childService = ChildAppService();
      final familyData = await childService.getFamilyInfo(familyCode);
      
      if (familyData == null) return false;
      
      if (familyData['approved'] == true) {
        final currentUser = AuthService().currentUser;
        final memberIds = List<String>.from(familyData['memberIds'] ?? []);
        
        if (currentUser != null && memberIds.contains(currentUser.uid)) {
          final familyInfo = FamilyInfo.fromMap({
            'familyCode': familyCode,
            'elderlyName': familyData['elderlyName'] ?? '',
            'createdAt': familyData['createdAt'],
            'lastMealTime': familyData['lastMealTime'],
            'isActive': familyData['isActive'] ?? false,
            'deviceInfo': _extractDeviceInfo(familyData['deviceInfo']),
          });
          
          await sessionManager.startSession(familyCode, familyData);
          _registerFCMToken(familyData);
          
          if (!mounted) return false;
          Navigator.pushReplacement(
            context,
            AppTheme.slideTransition(
              page: HomeScreen(familyCode: familyCode, familyInfo: familyInfo),
            ),
          );
          return true;
        }
      }
      
      // Family exists but not approved or user not authorized
      if (!mounted) return false;
      Navigator.pushReplacement(
        context,
        AppTheme.slideTransition(page: const FamilySetupScreen()),
      );
      return true;
    } catch (e) {
      secureLog.warning('Family validation failed: $e');
      return false;
    }
  }

  String _extractDeviceInfo(dynamic deviceInfo) {
    if (deviceInfo is String) return deviceInfo;
    if (deviceInfo is Map) return deviceInfo['lastUpdateSource']?.toString() ?? 'Unknown';
    return 'Unknown';
  }

  void _registerFCMToken(Map<String, dynamic> familyData) {
    final familyId = familyData['familyId'] as String?;
    if (familyId != null) {
      Future.delayed(const Duration(seconds: 1), () async {
        try {
          await FCMTokenService.registerChildToken(familyId);
          secureLog.info('FCM token registered for family');
        } catch (e) {
          secureLog.error('FCM token registration failed', e);
        }
      });
    }
  }

  Future<bool> _showRetryDialog() async {
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
          '가족 정보를 불러오는 중 문제가 발생했습니다.\n'
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
    return const _LoadingScreen(message: '사용자 정보 확인 중...');
  }
}

// Reusable UI Components
class _LoadingScreen extends StatelessWidget {
  final String message;
  
  const _LoadingScreen({required this.message});

  @override
  Widget build(BuildContext context) {
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
                borderRadius: BorderRadius.circular(20),
                boxShadow: AppTheme.getCardShadow(elevation: 8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/app_icon.png',
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 32),
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
            const Text(
              '부모님 안전 모니터링',
              style: TextStyle(
                fontSize: 16,
                color: AppTheme.textMedium,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 40),
            Text(
              message,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 16),
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

class _ErrorScreen extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  
  const _ErrorScreen({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: AppTheme.primaryBlue,
              ),
              const SizedBox(height: 24),
              const Text(
                '연결 문제 발생',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  color: AppTheme.textMedium,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
