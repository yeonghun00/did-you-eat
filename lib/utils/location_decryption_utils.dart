import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// LocationDecryptionUtils provides AES-256-CBC encryption/decryption for location data
/// 
/// Key Features:
/// - AES-256-CBC encryption with PBKDF2-SHA256 key derivation
/// - Uses family connection code + device-specific salt for key generation
/// - Format: `v1:base64(iv + encryptedData)`
/// - Backward compatibility with unencrypted data
/// - Real-time decryption for streaming location updates
class LocationDecryptionUtils {
  static const String _version = 'v1';
  static const int _keyLength = 32; // 256 bits
  static const int _ivLength = 16; // 128 bits for AES
  static const int _iterationCount = 10000; // PBKDF2 iterations
  static const int _saltLength = 32; // 256 bits

  /// Generates a device-specific salt using device info and connection code
  /// This ensures each device has a unique encryption key
  static Uint8List _generateDeviceSalt(String connectionCode, String deviceInfo) {
    final combined = '$connectionCode:$deviceInfo';
    final bytes = utf8.encode(combined);
    final digest = sha256.convert(bytes);
    return Uint8List.fromList(digest.bytes);
  }

  /// Derives encryption key using PBKDF2-SHA256
  /// 
  /// [connectionCode] - Family connection code as base key material
  /// [deviceInfo] - Device-specific information for salt generation
  static Uint8List _deriveKey(String connectionCode, String deviceInfo) {
    final password = utf8.encode(connectionCode);
    final salt = _generateDeviceSalt(connectionCode, deviceInfo);
    
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    pbkdf2.init(Pbkdf2Parameters(salt, _iterationCount, _keyLength));
    
    return pbkdf2.process(password);
  }

  /// Generates a random IV for encryption
  static Uint8List _generateIV() {
    final random = Random.secure();
    final iv = Uint8List(_ivLength);
    for (int i = 0; i < _ivLength; i++) {
      iv[i] = random.nextInt(256);
    }
    return iv;
  }

  /// Encrypts location data using AES-256-CBC
  /// 
  /// [locationData] - Location data as Map containing latitude, longitude, etc.
  /// [connectionCode] - Family connection code for key derivation
  /// [deviceInfo] - Device-specific information for salt generation
  /// 
  /// Returns encrypted string in format: `v1:base64(iv + encryptedData)`
  static String encryptLocationData(
    Map<String, dynamic> locationData,
    String connectionCode,
    String deviceInfo,
  ) {
    try {
      // Convert location data to JSON
      final jsonData = json.encode(locationData);
      final plaintext = utf8.encode(jsonData);
      
      // Derive encryption key
      final key = _deriveKey(connectionCode, deviceInfo);
      
      // Generate random IV
      final iv = _generateIV();
      
      // Setup AES cipher
      final cipher = CBCBlockCipher(AESEngine());
      final params = ParametersWithIV(KeyParameter(key), iv);
      cipher.init(true, params); // true = encrypt
      
      // Pad plaintext to block size (16 bytes for AES)
      final paddedPlaintext = _padPKCS7(plaintext, 16);
      
      // Encrypt
      final encrypted = Uint8List(paddedPlaintext.length);
      int offset = 0;
      while (offset < paddedPlaintext.length) {
        offset += cipher.processBlock(paddedPlaintext, offset, encrypted, offset);
      }
      
      // Combine IV + encrypted data
      final combined = Uint8List(iv.length + encrypted.length);
      combined.setRange(0, iv.length, iv);
      combined.setRange(iv.length, combined.length, encrypted);
      
      // Return versioned base64 encoded result
      final base64Data = base64.encode(combined);
      return '$_version:$base64Data';
    } catch (e) {
      throw Exception('Failed to encrypt location data: $e');
    }
  }

  /// Decrypts location data using AES-256-CBC
  /// 
  /// [encryptedData] - Encrypted string in format: `v1:base64(iv + encryptedData)`
  /// [connectionCode] - Family connection code for key derivation
  /// [deviceInfo] - Device-specific information for salt generation
  /// 
  /// Returns decrypted location data as Map
  static Map<String, dynamic> decryptLocationData(
    String encryptedData,
    String connectionCode,
    String deviceInfo,
  ) {
    try {
      // Check if data is encrypted (contains version prefix)
      if (!encryptedData.startsWith('$_version:')) {
        throw FormatException('Invalid encrypted data format');
      }
      
      // Extract base64 data
      final base64Data = encryptedData.substring('$_version:'.length);
      final combined = base64.decode(base64Data);
      
      if (combined.length < _ivLength) {
        throw FormatException('Invalid encrypted data: too short');
      }
      
      // Extract IV and encrypted data
      final iv = combined.sublist(0, _ivLength);
      final encrypted = combined.sublist(_ivLength);
      
      // Derive decryption key
      final key = _deriveKey(connectionCode, deviceInfo);
      
      // Setup AES cipher
      final cipher = CBCBlockCipher(AESEngine());
      final params = ParametersWithIV(KeyParameter(key), iv);
      cipher.init(false, params); // false = decrypt
      
      // Decrypt
      final decrypted = Uint8List(encrypted.length);
      int offset = 0;
      while (offset < encrypted.length) {
        offset += cipher.processBlock(encrypted, offset, decrypted, offset);
      }
      
      // Remove PKCS7 padding
      final unpadded = _removePKCS7Padding(decrypted);
      
      // Convert back to JSON
      final jsonString = utf8.decode(unpadded);
      return json.decode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Failed to decrypt location data: $e');
    }
  }

  /// Safely decrypts location data with backward compatibility
  /// 
  /// [locationData] - Either encrypted string or unencrypted Map
  /// [connectionCode] - Family connection code for key derivation
  /// [deviceInfo] - Device-specific information for salt generation
  /// 
  /// Returns location data as Map, handling both encrypted and unencrypted data
  static Map<String, dynamic>? safeDecryptLocationData(
    dynamic locationData,
    String connectionCode,
    String deviceInfo,
  ) {
    try {
      // Handle null data
      if (locationData == null) {
        return null;
      }
      
      // If it's already a Map (unencrypted), return as-is for backward compatibility
      if (locationData is Map<String, dynamic>) {
        return locationData;
      }
      
      // If it's a String, try to decrypt
      if (locationData is String) {
        // Check if it's encrypted (starts with version prefix)
        if (locationData.startsWith('$_version:')) {
          return decryptLocationData(locationData, connectionCode, deviceInfo);
        } else {
          // Assume it's a JSON string (legacy format)
          try {
            return json.decode(locationData) as Map<String, dynamic>;
          } catch (e) {
            // If JSON parsing fails, treat as invalid data
            print('Warning: Invalid location data format: $locationData');
            return null;
          }
        }
      }
      
      // Unknown format
      print('Warning: Unknown location data format: ${locationData.runtimeType}');
      return null;
    } catch (e) {
      print('Error in safeDecryptLocationData: $e');
      return null;
    }
  }

  /// Checks if location data is encrypted
  /// 
  /// [locationData] - Location data to check
  /// 
  /// Returns true if data is encrypted, false otherwise
  static bool isEncrypted(dynamic locationData) {
    if (locationData is String) {
      return locationData.startsWith('$_version:');
    }
    return false;
  }

  /// Validates that encrypted location data can be decrypted
  /// 
  /// [encryptedData] - Encrypted location data
  /// [connectionCode] - Family connection code
  /// [deviceInfo] - Device-specific information
  /// 
  /// Returns true if data can be successfully decrypted
  static bool validateEncryptedData(
    String encryptedData,
    String connectionCode,
    String deviceInfo,
  ) {
    try {
      final result = decryptLocationData(encryptedData, connectionCode, deviceInfo);
      return result.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Adds PKCS7 padding to data
  static Uint8List _padPKCS7(Uint8List data, int blockSize) {
    final padding = blockSize - (data.length % blockSize);
    final padded = Uint8List(data.length + padding);
    padded.setRange(0, data.length, data);
    for (int i = data.length; i < padded.length; i++) {
      padded[i] = padding;
    }
    return padded;
  }

  /// Removes PKCS7 padding from data
  static Uint8List _removePKCS7Padding(Uint8List data) {
    if (data.isEmpty) {
      throw ArgumentError('Cannot remove padding from empty data');
    }
    
    final padding = data.last;
    if (padding == 0 || padding > 16) {
      throw ArgumentError('Invalid PKCS7 padding');
    }
    
    // Verify padding bytes
    for (int i = data.length - padding; i < data.length; i++) {
      if (data[i] != padding) {
        throw ArgumentError('Invalid PKCS7 padding');
      }
    }
    
    return data.sublist(0, data.length - padding);
  }

  /// Encrypts location coordinates specifically (for real-time updates)
  /// 
  /// [latitude] - Latitude coordinate
  /// [longitude] - Longitude coordinate
  /// [connectionCode] - Family connection code
  /// [deviceInfo] - Device-specific information
  /// 
  /// Returns encrypted coordinates as string
  static String encryptCoordinates(
    double latitude,
    double longitude,
    String connectionCode,
    String deviceInfo,
  ) {
    final coordinateData = {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': DateTime.now().toIso8601String(),
    };
    return encryptLocationData(coordinateData, connectionCode, deviceInfo);
  }

  /// Decrypts location coordinates specifically
  /// 
  /// [encryptedCoordinates] - Encrypted coordinates string
  /// [connectionCode] - Family connection code
  /// [deviceInfo] - Device-specific information
  /// 
  /// Returns Map with latitude and longitude
  static Map<String, double>? decryptCoordinates(
    String encryptedCoordinates,
    String connectionCode,
    String deviceInfo,
  ) {
    try {
      final data = decryptLocationData(encryptedCoordinates, connectionCode, deviceInfo);
      final latitude = data['latitude']?.toDouble();
      final longitude = data['longitude']?.toDouble();
      
      if (latitude != null && longitude != null) {
        return {
          'latitude': latitude,
          'longitude': longitude,
        };
      }
      return null;
    } catch (e) {
      print('Error decrypting coordinates: $e');
      return null;
    }
  }
}