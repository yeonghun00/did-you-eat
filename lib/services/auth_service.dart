import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:async';
import '../utils/secure_logger.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Session management
  Timer? _tokenRefreshTimer;
  StreamSubscription<User?>? _authStateSubscription;
  bool _isInitialized = false;
  
  // Persistence keys
  static const String _lastAuthMethodKey = 'last_auth_method';
  static const String _lastSignInTimeKey = 'last_signin_time';
  static const String _autoSignInEnabledKey = 'auto_signin_enabled';

  // Current user stream with persistence
  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;
  bool get isSignedIn => currentUser != null;
  
  // Initialize authentication service with persistence
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Set up Firebase Auth persistence (only on web)
      if (kIsWeb) {
        try {
          await _auth.setPersistence(Persistence.LOCAL);
          secureLog.info('Firebase Auth web persistence set');
        } catch (e) {
          secureLog.warning('Firebase Auth web persistence failed', e);
        }
      } else {
        secureLog.info('Mobile platform - Firebase Auth persistence is automatic');
      }
      
      // Set up auth state listener with automatic recovery
      _authStateSubscription = _auth.authStateChanges().listen(
        _handleAuthStateChange,
        onError: (error) {
          secureLog.error('Auth state error', error);
          _attemptTokenRefresh();
        },
      );
      
      // Set up periodic token refresh
      _setupTokenRefresh();
      
      // Enable Firestore offline persistence (only on mobile)
      if (!kIsWeb) {
        try {
          await _firestore.enablePersistence();
          secureLog.info('Firestore offline persistence enabled');
        } catch (e) {
          secureLog.warning('Firestore persistence already enabled or failed', e);
        }
      } else {
        try {
          await _firestore.enablePersistence(
            const PersistenceSettings(synchronizeTabs: true),
          );
          secureLog.info('Firestore web persistence enabled');
        } catch (e) {
          secureLog.warning('Firestore web persistence already enabled or failed', e);
        }
      }
      
      _isInitialized = true;
      secureLog.info('AuthService initialized with platform-appropriate persistence');
    } catch (e) {
      secureLog.error('AuthService initialization failed', e);
      // Don't let persistence failures block initialization
      _isInitialized = true;
    }
  }
  
  // Handle auth state changes
  void _handleAuthStateChange(User? user) async {
    if (user != null) {
      print('🔄 Auth state changed: ${user.email ?? user.uid}');
      
      // Refresh token if it's about to expire
      try {
        final tokenResult = await user.getIdTokenResult();
        final expirationTime = tokenResult.expirationTime;
        final now = DateTime.now();
        
        if (expirationTime != null) {
          final timeUntilExpiration = expirationTime.difference(now);
          if (timeUntilExpiration.inMinutes < 30) {
            print('🔄 Token expires in ${timeUntilExpiration.inMinutes} minutes, refreshing...');
            await _attemptTokenRefresh();
          }
        }
      } catch (e) {
        print('⚠️ Token check failed: $e');
      }
    } else {
      print('🔄 User signed out');
    }
  }
  
  // Set up periodic token refresh
  void _setupTokenRefresh() {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = Timer.periodic(const Duration(minutes: 30), (timer) {
      if (currentUser != null) {
        _attemptTokenRefresh();
      }
    });
  }
  
  // Attempt to refresh authentication token
  Future<void> _attemptTokenRefresh() async {
    try {
      final user = currentUser;
      if (user == null) return;
      
      print('🔄 Attempting token refresh for user: ${user.email ?? user.uid}');
      
      // Force token refresh
      await user.getIdToken(true);
      
      // For Google Sign-In users, also refresh Google tokens
      if (user.providerData.any((p) => p.providerId == 'google.com')) {
        try {
          final googleUser = await _googleSignIn.signInSilently();
          if (googleUser != null) {
            final googleAuth = await googleUser.authentication;
            if (googleAuth.accessToken != null) {
              final credential = GoogleAuthProvider.credential(
                accessToken: googleAuth.accessToken,
                idToken: googleAuth.idToken,
              );
              await user.reauthenticateWithCredential(credential);
              print('✅ Google token refreshed successfully');
            }
          }
        } catch (e) {
          print('⚠️ Google token refresh failed: $e');
        }
      }
      
      print('✅ Token refresh completed');
    } catch (e) {
      print('❌ Token refresh failed: $e');
    }
  }
  
  // Clean up resources
  void dispose() {
    _tokenRefreshTimer?.cancel();
    _authStateSubscription?.cancel();
    _isInitialized = false;
  }

  // Check if authentication is valid with automatic recovery
  Future<bool> isAuthenticationValid({bool autoRecover = true}) async {
    try {
      await initialize(); // Ensure service is initialized
      
      final user = currentUser;
      
      if (user == null) {
        print('No user found');
        if (autoRecover) {
          return await _attemptAutoSignIn();
        }
        return false;
      }
      
      // Check if user is anonymous (should not be for proper auth)
      if (user.isAnonymous) {
        print('User is anonymous - not properly authenticated');
        if (autoRecover) {
          return await _attemptAutoSignIn();
        }
        return false;
      }
      
      // Validate existing token by making a test call
      try {
        await user.reload();
        
        // Check token expiration
        final tokenResult = await user.getIdTokenResult();
        final expirationTime = tokenResult.expirationTime;
        
        if (expirationTime != null) {
          final now = DateTime.now();
          if (expirationTime.isBefore(now)) {
            print('Token has expired, attempting refresh...');
            if (autoRecover) {
              await _attemptTokenRefresh();
              return await isAuthenticationValid(autoRecover: false); // Prevent infinite recursion
            }
            return false;
          }
        }
        
        print('Auth token is valid for user: ${user.email ?? user.uid}');
        return true;
      } catch (e) {
        print('Auth token expired or invalid: $e');
        if (autoRecover) {
          await _attemptTokenRefresh();
          return await isAuthenticationValid(autoRecover: false); // Prevent infinite recursion
        }
        return false;
      }
    } catch (e) {
      print('Authentication validation failed: $e');
      return false;
    }
  }
  
  // Attempt automatic sign-in using stored credentials
  Future<bool> _attemptAutoSignIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final autoSignInEnabled = prefs.getBool(_autoSignInEnabledKey) ?? false;
      final lastAuthMethod = prefs.getString(_lastAuthMethodKey);
      
      if (!autoSignInEnabled || lastAuthMethod == null) {
        print('Auto sign-in not enabled or no stored auth method');
        return false;
      }
      
      print('🔄 Attempting auto sign-in with method: $lastAuthMethod');
      
      switch (lastAuthMethod) {
        case 'google':
          return await _attemptGoogleAutoSignIn();
        case 'apple':
          // Apple Sign-In doesn't support silent refresh in same way
          print('Apple Sign-In auto-refresh not supported');
          return false;
        default:
          print('Unknown auth method for auto sign-in: $lastAuthMethod');
          return false;
      }
    } catch (e) {
      print('❌ Auto sign-in failed: $e');
      return false;
    }
  }
  
  // Attempt Google auto sign-in
  Future<bool> _attemptGoogleAutoSignIn() async {
    try {
      final googleUser = await _googleSignIn.signInSilently();
      if (googleUser == null) {
        print('Google silent sign-in returned null');
        return false;
      }
      
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      
      final userCredential = await _auth.signInWithCredential(credential);
      
      if (userCredential.user != null) {
        print('✅ Google auto sign-in successful');
        await _saveAuthMethod('google');
        return true;
      }
      
      return false;
    } catch (e) {
      print('❌ Google auto sign-in failed: $e');
      return false;
    }
  }
  
  // Save authentication method for auto sign-in
  Future<void> _saveAuthMethod(String method) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastAuthMethodKey, method);
      await prefs.setInt(_lastSignInTimeKey, DateTime.now().millisecondsSinceEpoch);
      await prefs.setBool(_autoSignInEnabledKey, true);
      print('✅ Auth method saved: $method');
    } catch (e) {
      print('❌ Failed to save auth method: $e');
    }
  }

  // Anonymous authentication with better error handling
  Future<AuthResult> signInAnonymously() async {
    try {
      final credential = await _auth.signInAnonymously();
      if (credential.user != null) {
        print('Anonymous authentication successful: ${credential.user?.uid}');
        return AuthResult.success(credential.user!);
      }
      return AuthResult.failure('Anonymous authentication failed');
    } on FirebaseAuthException catch (e) {
      print('Anonymous auth FirebaseException: ${e.code} - ${e.message}');
      return AuthResult.failure(_getAuthErrorMessage(e));
    } catch (e) {
      print('Anonymous auth general error: $e');
      return AuthResult.failure('Authentication failed: $e');
    }
  }


  // Email & Password Authentication
  Future<AuthResult> signUpWithEmail(String email, String password, String name) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user != null) {
        // Update display name
        await credential.user!.updateDisplayName(name);
        
        // Send email verification
        await credential.user!.sendEmailVerification();
        
        // Create user profile in Firestore
        await _createUserProfile(credential.user!, {
          'name': name,
          'email': email,
          'signUpMethod': 'email',
          'emailVerified': false,
        });

        return AuthResult.success(credential.user!);
      }
      return AuthResult.failure('회원가입에 실패했습니다.');
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_getAuthErrorMessage(e));
    } catch (e) {
      return AuthResult.failure('알 수 없는 오류가 발생했습니다: $e');
    }
  }

  Future<AuthResult> signInWithEmail(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user != null) {
        return AuthResult.success(credential.user!);
      }
      return AuthResult.failure('로그인에 실패했습니다.');
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_getAuthErrorMessage(e));
    } catch (e) {
      return AuthResult.failure('알 수 없는 오류가 발생했습니다: $e');
    }
  }

  // Google Sign-In
  Future<AuthResult> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return AuthResult.failure('Google 로그인이 취소되었습니다.');
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      
      if (userCredential.user != null) {
        // Create or update user profile
        await _createUserProfile(userCredential.user!, {
          'name': userCredential.user!.displayName ?? 'Google User',
          'email': userCredential.user!.email ?? '',
          'signUpMethod': 'google',
          'emailVerified': userCredential.user!.emailVerified,
        });
        
        // Save auth method for auto sign-in
        await _saveAuthMethod('google');

        return AuthResult.success(userCredential.user!);
      }
      return AuthResult.failure('Google 로그인에 실패했습니다.');
    } catch (e) {
      return AuthResult.failure('Google 로그인 오류: $e');
    }
  }

  // Apple Sign-In (iOS only)
  Future<AuthResult> signInWithApple() async {
    if (!Platform.isIOS) {
      return AuthResult.failure('Apple 로그인은 iOS에서만 사용 가능합니다.');
    }

    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: credential.identityToken,
        accessToken: credential.authorizationCode,
      );

      final userCredential = await _auth.signInWithCredential(oauthCredential);
      
      if (userCredential.user != null) {
        // Create or update user profile
        await _createUserProfile(userCredential.user!, {
          'name': userCredential.user!.displayName ?? 
                  '${credential.givenName ?? ''} ${credential.familyName ?? ''}'.trim(),
          'email': userCredential.user!.email ?? '',
          'signUpMethod': 'apple',
          'emailVerified': userCredential.user!.emailVerified,
        });
        
        // Save auth method for auto sign-in
        await _saveAuthMethod('apple');

        return AuthResult.success(userCredential.user!);
      }
      return AuthResult.failure('Apple 로그인에 실패했습니다.');
    } catch (e) {
      return AuthResult.failure('Apple 로그인 오류: $e');
    }
  }

  // Password Reset
  Future<AuthResult> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return AuthResult.success(null, message: '비밀번호 재설정 이메일을 발송했습니다.');
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_getAuthErrorMessage(e));
    } catch (e) {
      return AuthResult.failure('비밀번호 재설정에 실패했습니다: $e');
    }
  }

  // Email Verification
  Future<AuthResult> sendEmailVerification() async {
    try {
      final user = currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
        return AuthResult.success(null, message: '인증 이메일을 발송했습니다.');
      }
      return AuthResult.failure('사용자가 없거나 이미 인증되었습니다.');
    } catch (e) {
      return AuthResult.failure('이메일 인증 발송 실패: $e');
    }
  }

  // Sign Out
  Future<void> signOut() async {
    try {
      // Clear auto sign-in settings
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastAuthMethodKey);
      await prefs.remove(_lastSignInTimeKey);
      await prefs.setBool(_autoSignInEnabledKey, false);
      
      // Cancel timers and subscriptions
      dispose();
      
      // Sign out from all services
      await Future.wait([
        _auth.signOut(),
        _googleSignIn.signOut(),
      ]);
      
      print('✅ Signed out successfully');
    } catch (e) {
      print('❌ Sign out error: $e');
    }
  }

  // Delete Account
  Future<AuthResult> deleteAccount() async {
    try {
      final user = currentUser;
      if (user != null) {
        // Delete user profile from Firestore
        await _firestore.collection('users').doc(user.uid).delete();
        
        // Delete Firebase Auth user
        await user.delete();
        
        return AuthResult.success(null, message: '계정이 삭제되었습니다.');
      }
      return AuthResult.failure('사용자가 없습니다.');
    } catch (e) {
      return AuthResult.failure('계정 삭제 실패: $e');
    }
  }

  // Create user profile in Firestore
  Future<void> _createUserProfile(User user, Map<String, dynamic> additionalData) async {
    final userDoc = _firestore.collection('users').doc(user.uid);
    final docSnapshot = await userDoc.get();
    
    if (!docSnapshot.exists) {
      await userDoc.set({
        'uid': user.uid,
        'email': user.email,
        'name': user.displayName,
        'photoURL': user.photoURL,
        'createdAt': FieldValue.serverTimestamp(),
        'lastSignIn': FieldValue.serverTimestamp(),
        'familyCodes': <String>[], // Array of family codes this user has access to
        ...additionalData,
      });
    } else {
      // Update last sign in
      await userDoc.update({
        'lastSignIn': FieldValue.serverTimestamp(),
        'emailVerified': user.emailVerified,
      });
    }
  }

  // Get user profile with retry logic and proper error handling
  Future<Map<String, dynamic>?> getUserProfile() async {
    final user = currentUser;
    if (user == null) {
      print('❌ No current user for getUserProfile');
      return null;
    }

    print('🔍 Fetching user profile for: ${user.email ?? user.uid}');
    
    // Retry logic for network issues
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        print('📡 Attempt ${attempt + 1} to fetch user profile...');
        
        final doc = await _firestore
            .collection('users')
            .doc(user.uid)
            .get()
            .timeout(const Duration(seconds: 10));
        
        if (doc.exists) {
          final data = doc.data();
          print('✅ User profile retrieved successfully');
          print('📊 Profile data keys: ${data?.keys.toList()}');
          return data;
        } else {
          print('❌ User profile document does not exist');
          return null;
        }
      } catch (e) {
        print('⚠️ Attempt ${attempt + 1} failed: $e');
        
        if (attempt == 2) {
          print('❌ All attempts failed to fetch user profile');
          return null;
        }
        
        // Wait before retry
        await Future.delayed(Duration(seconds: attempt + 1));
      }
    }
    
    return null;
  }

  // Update user profile
  Future<AuthResult> updateUserProfile(Map<String, dynamic> data) async {
    try {
      final user = currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).update({
          ...data,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return AuthResult.success(user, message: '프로필이 업데이트되었습니다.');
      }
      return AuthResult.failure('사용자가 없습니다.');
    } catch (e) {
      return AuthResult.failure('프로필 업데이트 실패: $e');
    }
  }

  // Add family code to user profile
  Future<AuthResult> addFamilyCode(String familyCode) async {
    try {
      final user = currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).update({
          'familyCodes': FieldValue.arrayUnion([familyCode]),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return AuthResult.success(user, message: '가족 코드가 추가되었습니다.');
      }
      return AuthResult.failure('사용자가 없습니다.');
    } catch (e) {
      return AuthResult.failure('가족 코드 추가 실패: $e');
    }
  }

  // Remove family code from user profile
  Future<AuthResult> removeFamilyCode(String familyCode) async {
    try {
      final user = currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).update({
          'familyCodes': FieldValue.arrayRemove([familyCode]),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return AuthResult.success(user, message: '가족 코드가 제거되었습니다.');
      }
      return AuthResult.failure('사용자가 없습니다.');
    } catch (e) {
      return AuthResult.failure('가족 코드 제거 실패: $e');
    }
  }

  // Get Firebase Auth error messages in Korean
  String _getAuthErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return '비밀번호가 너무 약합니다.';
      case 'email-already-in-use':
        return '이미 사용 중인 이메일입니다.';
      case 'invalid-email':
        return '유효하지 않은 이메일 주소입니다.';
      case 'user-not-found':
        return '사용자를 찾을 수 없습니다.';
      case 'wrong-password':
        return '잘못된 비밀번호입니다.';
      case 'user-disabled':
        return '비활성화된 계정입니다.';
      case 'too-many-requests':
        return '너무 많은 요청이 발생했습니다. 잠시 후 다시 시도해주세요.';
      case 'operation-not-allowed':
        return '허용되지 않는 작업입니다.';
      case 'invalid-credential':
        return '유효하지 않은 인증 정보입니다.';
      case 'network-request-failed':
        return '네트워크 연결을 확인해주세요.';
      case 'requires-recent-login':
        return '보안을 위해 다시 로그인해주세요.';
      default:
        return '인증 오류가 발생했습니다: ${e.message}';
    }
  }

  // ============================================================================
  // FAMILY CONNECTION RESTORATION (Fix for reinstall issue)
  // ============================================================================

  /// Find user's existing family connection from Firestore
  ///
  /// This fixes the critical issue where users lose family connection
  /// after app reinstall or update. When app is deleted, SharedPreferences
  /// is cleared, but Firestore data persists.
  ///
  /// Returns: Map with 'familyId' and 'connectionCode', or null if not found
  Future<Map<String, String>?> findExistingFamilyConnection() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        secureLog.warning('Cannot find family connection: No authenticated user');
        return null;
      }

      secureLog.info('🔍 Searching for existing family connection for user: ${user.uid}');

      // Query families where this user is a member
      // This works because we add user.uid to memberIds array when they join
      final querySnapshot = await _firestore
          .collection('families')
          .where('memberIds', arrayContains: user.uid)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        secureLog.info('❌ No existing family connection found for user');
        return null;
      }

      final familyDoc = querySnapshot.docs.first;
      final familyData = familyDoc.data();

      final familyId = familyDoc.id;
      final connectionCode = familyData['connectionCode'] as String?;
      final elderlyName = familyData['elderlyName'] as String?;

      if (connectionCode == null) {
        secureLog.warning('⚠️ Family found but missing connection code');
        return null;
      }

      secureLog.operationSuccess('✅ Found existing family connection!');
      secureLog.info('   Family ID: $familyId');
      secureLog.info('   Connection Code: $connectionCode');
      secureLog.info('   Elderly Name: $elderlyName');

      return {
        'familyId': familyId,
        'connectionCode': connectionCode,
      };
    } catch (e) {
      secureLog.error('❌ Error finding existing family connection', e);
      return null;
    }
  }

  /// Save connection code to SharedPreferences
  ///
  /// Stores the connection code locally for fast access on next app launch.
  /// This is cleared when app is deleted, which is why we also need
  /// findExistingFamilyConnection() as a fallback.
  Future<void> saveConnectionCode(String connectionCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('connectionCode', connectionCode);
      await prefs.setString('familyCode', connectionCode); // Backward compatibility
      secureLog.info('✅ Connection code saved to SharedPreferences: $connectionCode');
    } catch (e) {
      secureLog.error('❌ Failed to save connection code', e);
    }
  }

  /// Get stored connection code from SharedPreferences
  ///
  /// Returns the locally stored connection code, or null if not found.
  /// This is the fast path - if it exists, we don't need to query Firestore.
  Future<String?> getStoredConnectionCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString('connectionCode') ?? prefs.getString('familyCode');

      if (code != null) {
        secureLog.info('✅ Found connection code in SharedPreferences: $code');
      } else {
        secureLog.info('❌ No connection code found in SharedPreferences');
      }

      return code;
    } catch (e) {
      secureLog.error('❌ Failed to get stored connection code', e);
      return null;
    }
  }

  /// Clear stored connection code from SharedPreferences
  ///
  /// Used when user logs out or leaves a family.
  Future<void> clearStoredConnectionCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('connectionCode');
      await prefs.remove('familyCode');
      secureLog.info('✅ Connection code cleared from SharedPreferences');
    } catch (e) {
      secureLog.error('❌ Failed to clear connection code', e);
    }
  }
}

// Result wrapper class for better error handling
class AuthResult {
  final bool isSuccess;
  final String? errorMessage;
  final String? successMessage;
  final User? user;

  AuthResult._({
    required this.isSuccess,
    this.errorMessage,
    this.successMessage,
    this.user,
  });

  factory AuthResult.success(User? user, {String? message}) {
    return AuthResult._(
      isSuccess: true,
      user: user,
      successMessage: message,
    );
  }

  factory AuthResult.failure(String error) {
    return AuthResult._(
      isSuccess: false,
      errorMessage: error,
    );
  }
}