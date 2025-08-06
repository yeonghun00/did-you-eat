import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'dart:io';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Current user stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;
  bool get isSignedIn => currentUser != null;

  // Check if authentication is valid (NO automatic recovery)
  Future<bool> isAuthenticationValid() async {
    try {
      final user = currentUser;
      
      if (user == null) {
        print('No user found');
        return false;
      }
      
      // Check if user is anonymous (should not be for proper auth)
      if (user.isAnonymous) {
        print('User is anonymous - not properly authenticated');
        return false;
      }
      
      // Validate existing token by making a test call
      try {
        await user.reload();
        print('Auth token is valid for user: ${user.email ?? user.uid}');
        return true;
      } catch (e) {
        print('Auth token expired or invalid: $e');
        return false;
      }
    } catch (e) {
      print('Authentication validation failed: $e');
      return false;
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
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
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