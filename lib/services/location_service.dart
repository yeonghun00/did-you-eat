import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../utils/location_decryption_utils.dart';

/// LocationService handles encrypted location storage and retrieval
/// 
/// Features:
/// - Encrypts location data before storing in Firebase
/// - Decrypts location data when reading from Firebase
/// - Maintains backward compatibility with unencrypted data
/// - Provides real-time location streaming with automatic decryption
/// - Uses device-specific encryption keys for security
class LocationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Cache for device info to avoid repeated calls
  String? _cachedDeviceInfo;

  /// Get device info for encryption key derivation
  Future<String> _getDeviceInfo() async {
    if (_cachedDeviceInfo != null) {
      return _cachedDeviceInfo!;
    }

    try {
      final deviceInfoPlugin = DeviceInfoPlugin();
      String deviceInfo;

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfoPlugin.androidInfo;
        deviceInfo = '${androidInfo.manufacturer}_${androidInfo.model}_${androidInfo.id}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfoPlugin.iosInfo;
        deviceInfo = '${iosInfo.name}_${iosInfo.model}_${iosInfo.identifierForVendor}';
      } else {
        // Fallback for other platforms
        deviceInfo = 'unknown_device_${DateTime.now().millisecondsSinceEpoch}';
      }

      _cachedDeviceInfo = deviceInfo;
      return deviceInfo;
    } catch (e) {
      print('Error getting device info: $e');
      // Use a fallback device identifier
      final fallback = 'fallback_device_${DateTime.now().millisecondsSinceEpoch}';
      _cachedDeviceInfo = fallback;
      return fallback;
    }
  }

  /// Store encrypted location data in Firebase
  /// 
  /// [familyId] - The family document ID in Firestore
  /// [connectionCode] - Family connection code for encryption
  /// [latitude] - Location latitude
  /// [longitude] - Location longitude  
  /// [address] - Optional address string
  /// [timestamp] - Optional timestamp (defaults to now)
  /// 
  /// Returns true if successful, false otherwise
  Future<bool> storeEncryptedLocation({
    required String familyId,
    required String connectionCode,
    required double latitude,
    required double longitude,
    String? address,
    DateTime? timestamp,
  }) async {
    try {
      final deviceInfo = await _getDeviceInfo();
      timestamp ??= DateTime.now();
      
      // Create location data structure
      final locationData = {
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp.toIso8601String(),
        if (address != null) 'address': address,
      };
      
      // Encrypt the location data
      final encryptedLocation = LocationDecryptionUtils.encryptLocationData(
        locationData,
        connectionCode,
        deviceInfo,
      );
      
      // Store in Firebase
      await _firestore.collection('families').doc(familyId).update({
        'location': encryptedLocation,
        'lastLocationUpdate': FieldValue.serverTimestamp(),
      });
      
      print('Successfully stored encrypted location for family: $familyId');
      return true;
    } catch (e) {
      print('Error storing encrypted location: $e');
      return false;
    }
  }

  /// Store location data with automatic encryption decision
  /// 
  /// This method will encrypt new location data but can also handle
  /// legacy unencrypted data for backward compatibility
  /// 
  /// [familyId] - The family document ID in Firestore
  /// [connectionCode] - Family connection code for encryption
  /// [locationData] - Location data map
  /// [forceEncryption] - Force encryption even for legacy data
  /// 
  /// Returns true if successful, false otherwise
  Future<bool> storeLocationData({
    required String familyId,
    required String connectionCode,
    required Map<String, dynamic> locationData,
    bool forceEncryption = true,
  }) async {
    try {
      if (forceEncryption) {
        final deviceInfo = await _getDeviceInfo();
        
        // Encrypt the location data
        final encryptedLocation = LocationDecryptionUtils.encryptLocationData(
          locationData,
          connectionCode,
          deviceInfo,
        );
        
        // Store encrypted data
        await _firestore.collection('families').doc(familyId).update({
          'location': encryptedLocation,
          'lastLocationUpdate': FieldValue.serverTimestamp(),
        });
        
        print('Successfully stored encrypted location data for family: $familyId');
      } else {
        // Store unencrypted for backward compatibility
        await _firestore.collection('families').doc(familyId).update({
          'location': locationData,
          'lastLocationUpdate': FieldValue.serverTimestamp(),
        });
        
        print('Successfully stored unencrypted location data for family: $familyId');
      }
      
      return true;
    } catch (e) {
      print('Error storing location data: $e');
      return false;
    }
  }

  /// Retrieve and decrypt location data from Firebase
  /// 
  /// [familyId] - The family document ID in Firestore
  /// [connectionCode] - Family connection code for decryption
  /// 
  /// Returns decrypted location data or null if not found/error
  Future<Map<String, dynamic>?> getDecryptedLocation({
    required String familyId,
    required String connectionCode,
  }) async {
    try {
      final doc = await _firestore.collection('families').doc(familyId).get();
      
      if (!doc.exists) {
        print('Family document not found: $familyId');
        return null;
      }
      
      final data = doc.data()!;
      final rawLocation = data['location'];
      
      if (rawLocation == null) {
        print('No location data found for family: $familyId');
        return null;
      }
      
      final deviceInfo = await _getDeviceInfo();
      return LocationDecryptionUtils.safeDecryptLocationData(
        rawLocation,
        connectionCode,
        deviceInfo,
      );
    } catch (e) {
      print('Error retrieving location data: $e');
      return null;
    }
  }

  /// Get real-time stream of decrypted location updates
  /// 
  /// [familyId] - The family document ID in Firestore
  /// [connectionCode] - Family connection code for decryption
  /// 
  /// Returns stream of decrypted location data
  Stream<Map<String, dynamic>?> listenToLocationUpdates({
    required String familyId,
    required String connectionCode,
  }) async* {
    try {
      await for (final snapshot in _firestore
          .collection('families')
          .doc(familyId)
          .snapshots()) {
        
        if (!snapshot.exists) {
          print('Family document does not exist: $familyId');
          yield null;
          continue;
        }
        
        final data = snapshot.data()!;
        final rawLocation = data['location'];
        
        if (rawLocation == null) {
          yield null;
          continue;
        }
        
        try {
          final deviceInfo = await _getDeviceInfo();
          final decryptedLocation = LocationDecryptionUtils.safeDecryptLocationData(
            rawLocation,
            connectionCode,
            deviceInfo,
          );
          
          yield decryptedLocation;
        } catch (e) {
          print('Error decrypting location in stream: $e');
          yield null;
        }
      }
    } catch (e) {
      print('Error in location stream: $e');
      yield null;
    }
  }

  /// Validate that encrypted location data can be decrypted
  /// 
  /// [encryptedData] - Encrypted location data string
  /// [connectionCode] - Family connection code
  /// 
  /// Returns true if data can be decrypted successfully
  Future<bool> validateEncryptedLocation({
    required String encryptedData,
    required String connectionCode,
  }) async {
    try {
      final deviceInfo = await _getDeviceInfo();
      return LocationDecryptionUtils.validateEncryptedData(
        encryptedData,
        connectionCode,
        deviceInfo,
      );
    } catch (e) {
      print('Error validating encrypted location: $e');
      return false;
    }
  }

  /// Check if location data is encrypted
  /// 
  /// [locationData] - Location data to check
  /// 
  /// Returns true if data is encrypted
  bool isLocationEncrypted(dynamic locationData) {
    return LocationDecryptionUtils.isEncrypted(locationData);
  }

  /// Migrate unencrypted location data to encrypted format
  /// 
  /// [familyId] - The family document ID in Firestore
  /// [connectionCode] - Family connection code for encryption
  /// 
  /// Returns true if migration was successful or not needed
  Future<bool> migrateToEncryptedLocation({
    required String familyId,
    required String connectionCode,
  }) async {
    try {
      final doc = await _firestore.collection('families').doc(familyId).get();
      
      if (!doc.exists) {
        print('Family document not found for migration: $familyId');
        return false;
      }
      
      final data = doc.data()!;
      final rawLocation = data['location'];
      
      if (rawLocation == null) {
        print('No location data to migrate for family: $familyId');
        return true; // No data to migrate is success
      }
      
      // Check if already encrypted
      if (isLocationEncrypted(rawLocation)) {
        print('Location data already encrypted for family: $familyId');
        return true;
      }
      
      // If it's a Map (unencrypted), encrypt it
      if (rawLocation is Map<String, dynamic>) {
        final deviceInfo = await _getDeviceInfo();
        
        final encryptedLocation = LocationDecryptionUtils.encryptLocationData(
          rawLocation,
          connectionCode,
          deviceInfo,
        );
        
        await _firestore.collection('families').doc(familyId).update({
          'location': encryptedLocation,
          'locationMigrated': true,
          'migrationTimestamp': FieldValue.serverTimestamp(),
        });
        
        print('Successfully migrated location data to encrypted format for family: $familyId');
        return true;
      }
      
      print('Unknown location data format for migration: ${rawLocation.runtimeType}');
      return false;
    } catch (e) {
      print('Error migrating location data: $e');
      return false;
    }
  }

  /// Clear cached device info (useful for testing or device changes)
  void clearDeviceInfoCache() {
    _cachedDeviceInfo = null;
  }

  /// Get cached device info without regenerating
  String? getCachedDeviceInfo() {
    return _cachedDeviceInfo;
  }
}