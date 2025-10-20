import 'package:encrypt/encrypt.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:typed_data';

/// EncryptionService handles location data encryption and decryption
///
/// Security Features:
/// - AES-256-GCM encryption for location data
/// - Key derivation from familyId using secret salt
/// - No keys stored in Firestore
/// - PBKDF2-like key stretching with 10,000 rounds
///
/// This service is used by the child app to decrypt location data
/// sent by the parent app. The parent app uses the same algorithm
/// to encrypt the data before storing it in Firestore.
class EncryptionService {
  /// Secret salt for key derivation (KEEP THIS SECRET!)
  /// ⚠️ CRITICAL: This must match the parent app's salt exactly
  /// In production, move this to environment variables
  static const String _keySalt = 'thanks_everyday_secure_salt_v1_2025';

  /// Derive a 256-bit encryption key from familyId
  ///
  /// Uses PBKDF2-like approach with SHA-256 and 10,000 rounds
  /// Both parent and child apps derive the same key from familyId
  ///
  /// [familyId] The unique family identifier
  /// Returns base64-encoded 256-bit key
  static String deriveEncryptionKey(String familyId) {
    // Combine familyId with secret salt
    final input = '$familyId:$_keySalt';

    // Hash multiple times for better security (key stretching)
    var hash = sha256.convert(utf8.encode(input)).bytes;

    // Additional rounds of hashing (PBKDF2-like)
    // This makes brute force attacks computationally expensive
    for (int i = 0; i < 10000; i++) {
      hash = sha256.convert(hash).bytes;
    }

    // Take first 32 bytes (256 bits) for AES-256
    final keyBytes = Uint8List.fromList(hash.sublist(0, 32));

    return base64.encode(keyBytes);
  }

  /// Decrypt location data received from Firestore
  ///
  /// [encryptedData] Base64-encoded encrypted location data
  /// [ivBase64] Base64-encoded initialization vector
  /// [base64Key] Base64-encoded encryption key (from deriveEncryptionKey)
  ///
  /// Returns decrypted location data with latitude, longitude, and address
  /// Throws exception if decryption fails
  static Map<String, dynamic> decryptLocation({
    required String encryptedData,
    required String ivBase64,
    required String base64Key,
  }) {
    try {
      // Setup decryption
      final key = Key(base64.decode(base64Key));
      final iv = IV.fromBase64(ivBase64);
      final encrypter = Encrypter(AES(key, mode: AESMode.gcm));

      // Decrypt
      final decrypted = encrypter.decrypt64(encryptedData, iv: iv);

      // Parse JSON
      final locationData = json.decode(decrypted) as Map<String, dynamic>;

      return {
        'latitude': locationData['latitude'] as double,
        'longitude': locationData['longitude'] as double,
        'address': locationData['address'] as String? ?? '',
      };
    } catch (e) {
      print('⚠️ Decryption error: $e');
      rethrow;
    }
  }

  /// Encrypt location data (for parent app compatibility)
  ///
  /// This method is included for completeness but is primarily used
  /// by the parent app. The child app typically only decrypts.
  ///
  /// [latitude] GPS latitude coordinate
  /// [longitude] GPS longitude coordinate
  /// [address] Human-readable address (optional)
  /// [base64Key] Base64-encoded encryption key (from deriveEncryptionKey)
  ///
  /// Returns map with 'encrypted' and 'iv' fields (both base64-encoded)
  static Map<String, String> encryptLocation({
    required double latitude,
    required double longitude,
    required String address,
    required String base64Key,
  }) {
    try {
      // Prepare data to encrypt
      final locationData = {
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
      };
      final plainText = json.encode(locationData);

      // Setup encryption
      final key = Key(base64.decode(base64Key));
      final iv = IV.fromSecureRandom(16); // Random IV for each encryption
      final encrypter = Encrypter(AES(key, mode: AESMode.gcm));

      // Encrypt
      final encrypted = encrypter.encrypt(plainText, iv: iv);

      return {
        'encrypted': encrypted.base64,
        'iv': iv.base64,
      };
    } catch (e) {
      print('⚠️ Encryption error: $e');
      rethrow;
    }
  }

  /// Test key derivation consistency
  ///
  /// Helper method for testing that ensures the same familyId
  /// always produces the same key
  ///
  /// [familyId] The family identifier to test
  /// Returns true if key derivation is consistent
  static bool testKeyDerivation(String familyId) {
    try {
      final key1 = deriveEncryptionKey(familyId);
      final key2 = deriveEncryptionKey(familyId);

      final isConsistent = key1 == key2;

      if (isConsistent) {
        print('✅ Key derivation is consistent for familyId: $familyId');
      } else {
        print('❌ Key derivation is NOT consistent for familyId: $familyId');
      }

      return isConsistent;
    } catch (e) {
      print('❌ Key derivation test failed: $e');
      return false;
    }
  }
}
