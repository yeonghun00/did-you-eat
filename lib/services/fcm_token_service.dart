import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

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

      // Register with parent app's Firestore structure
      await FirebaseFirestore.instance
          .collection('families')
          .doc(familyId)
          .collection('child_devices')
          .doc(deviceId)
          .set({
        'fcm_token': fcmToken,
        'device_id': deviceId,
        'device_name': deviceName,
        'is_active': true,
        'registered_at': FieldValue.serverTimestamp(),
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

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

  /// Get stored family ID (implement based on your storage method)
  static Future<String?> _getStoredFamilyId() async {
    try {
      // This should be implemented based on how you store family data
      // For now, we'll need to get it from SharedPreferences or similar
      return null; // Placeholder - implement based on your app's data storage
    } catch (e) {
      print('❌ Failed to get stored family ID: $e');
      return null;
    }
  }
}