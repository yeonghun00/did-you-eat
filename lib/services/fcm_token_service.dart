import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'session_manager.dart';

class FCMTokenService {
  static const String _deviceIdKey = 'unique_device_id';
  
  /// Registers FCM token to parent app's Firestore structure
  /// Collections: families/{familyId}/child_devices/{deviceId}
  static Future<bool> registerChildToken(String familyId) async {
    try {
      // Get FCM token with retry logic for FIS_AUTH_ERROR
      String? fcmToken;
      int retryCount = 0;
      const maxRetries = 3;
      
      while (fcmToken == null && retryCount < maxRetries) {
        try {
          fcmToken = await FirebaseMessaging.instance.getToken();
          if (fcmToken != null) break;
        } catch (e) {
          retryCount++;
          print('⚠️ FCM token request failed (attempt $retryCount/$maxRetries): $e');
          if (retryCount < maxRetries) {
            await Future.delayed(Duration(seconds: retryCount * 2)); // Exponential backoff
          }
        }
      }
      
      if (fcmToken == null) {
        print('❌ FCM token is null after $maxRetries attempts');
        return false;
      }

      // Get unique device ID
      final deviceId = await _getUniqueDeviceId();
      
      // Get device name
      final deviceName = await _getDeviceName();

      print('📱 Registering device:');
      print('  Family ID: $familyId');
      print('  Device ID: $deviceId');
      print('  FCM Token: ${fcmToken.substring(0, 20)}...');

      // Get current user ID
      final currentUser = FirebaseAuth.instance.currentUser;
      final userId = currentUser?.uid ?? 'anonymous';
      
      print('  User ID: $userId');

      // Register with parent app's Firestore structure
      print('🔥 FIREBASE: Attempting to write to families/$familyId/child_devices/$deviceId');
      
      await FirebaseFirestore.instance
          .collection('families')
          .doc(familyId)
          .collection('child_devices')
          .doc(deviceId)
          .set({
        'fcm_token': fcmToken,
        'device_id': deviceId,
        'device_name': deviceName,
        'user_id': userId,
        'is_active': true,
        'registered_at': FieldValue.serverTimestamp(),
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      print('🔥 FIREBASE: Successfully wrote FCM token to Firestore');
      print('🔥 FIREBASE: Path: families/$familyId/child_devices/$deviceId');
      print('🔥 FIREBASE: FCM Token registered: ${fcmToken.substring(0, 30)}...');

      print('✅ FCM token registered successfully to Firestore');
      return true;
    } catch (e) {
      print('❌ Failed to register FCM token: $e');
      return false;
    }
  }

  /// Updates FCM token when it changes
  static Future<void> updateToken(String familyId, String newToken) async {
    try {
      final deviceId = await _getUniqueDeviceId();
      
      await FirebaseFirestore.instance
          .collection('families')
          .doc(familyId)
          .collection('child_devices')
          .doc(deviceId)
          .update({
        'fcm_token': newToken,
        'last_updated': FieldValue.serverTimestamp(),
      });

      print('✅ FCM token updated in Firestore');
    } catch (e) {
      print('❌ Failed to update FCM token: $e');
    }
  }

  /// Marks device as inactive (for logout/uninstall)
  static Future<void> deactivateDevice(String familyId) async {
    try {
      final deviceId = await _getUniqueDeviceId();
      
      await FirebaseFirestore.instance
          .collection('families')
          .doc(familyId)
          .collection('child_devices')
          .doc(deviceId)
          .update({
        'is_active': false,
        'last_updated': FieldValue.serverTimestamp(),
      });

      print('✅ Device marked as inactive');
    } catch (e) {
      print('❌ Failed to deactivate device: $e');
    }
  }

  /// Generates a unique device identifier
  static Future<String> _getUniqueDeviceId() async {
    try {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      
      if (Platform.isAndroid) {
        final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        return 'android_${androidInfo.id}';
      } else if (Platform.isIOS) {
        final IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        return 'ios_${iosInfo.identifierForVendor ?? 'unknown'}';
      }
    } catch (e) {
      print('❌ Failed to get device ID: $e');
    }
    
    // Fallback to timestamp-based ID
    return 'device_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Gets device name for display purposes
  static Future<String> _getDeviceName() async {
    try {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      
      if (Platform.isAndroid) {
        final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        return '${androidInfo.brand} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        return '${iosInfo.name} (${iosInfo.model})';
      }
    } catch (e) {
      print('❌ Failed to get device name: $e');
    }
    
    return 'Child App Device';
  }

  /// Test token generation (for debugging)
  static Future<bool> testFCMTokenGeneration() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      print('🧪 FCM Token Test:');
      print('  Token: ${token?.substring(0, 50)}...');
      print('  Length: ${token?.length}');
      return token != null;
    } catch (e) {
      print('❌ Token generation test failed: $e');
      return false;
    }
  }

  /// Request notification permissions
  static Future<bool> requestPermissions() async {
    try {
      final messaging = FirebaseMessaging.instance;
      
      final settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      print('🔔 Notification permission status: ${settings.authorizationStatus}');
      
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
             settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      print('❌ Failed to request permissions: $e');
      return false;
    }
  }

  /// Set up token refresh listener
  static void setupTokenRefreshListener() {
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      print('🔄 FCM token refreshed');
      
      try {
        // Get stored family ID from SharedPreferences or wherever it's stored
        final familyId = await _getStoredFamilyId();
        if (familyId != null) {
          await updateToken(familyId, newToken);
        }
      } catch (e) {
        print('❌ Failed to update refreshed token: $e');
      }
    });
  }

  /// Get stored family ID from session manager
  static Future<String?> _getStoredFamilyId() async {
    try {
      final sessionManager = SessionManager();
      await sessionManager.initialize();
      
      if (sessionManager.hasValidSession) {
        final familyCode = sessionManager.currentFamilyCode;
        final cachedData = sessionManager.cachedFamilyData;
        final familyId = cachedData?['familyId'] as String?;
        
        print('🔍 Found stored family ID: $familyId for family code: $familyCode');
        return familyId;
      }
      
      print('⚠️ No valid session found for FCM token refresh');
      return null;
    } catch (e) {
      print('❌ Failed to get stored family ID: $e');
      return null;
    }
  }

  /// Debug method to manually trigger FCM registration for current session
  static Future<bool> debugRegisterForCurrentSession() async {
    try {
      print('🐛 DEBUG: Starting manual FCM registration...');
      
      final sessionManager = SessionManager();
      await sessionManager.initialize();
      
      print('🐛 DEBUG: Session valid: ${sessionManager.hasValidSession}');
      print('🐛 DEBUG: Family code: ${sessionManager.currentFamilyCode}');
      print('🐛 DEBUG: Cached data keys: ${sessionManager.cachedFamilyData?.keys.toList()}');
      
      final familyId = await _getStoredFamilyId();
      if (familyId != null) {
        print('🐛 DEBUG: Found family ID: $familyId');
        print('🐛 DEBUG: Manually triggering FCM registration for family: $familyId');
        return await registerChildToken(familyId);
      } else {
        print('🐛 DEBUG: No family ID found for FCM registration');
        print('🐛 DEBUG: Please reconnect to family or check session data');
        return false;
      }
    } catch (e) {
      print('🐛 DEBUG: Failed to register FCM token: $e');
      return false;
    }
  }
}