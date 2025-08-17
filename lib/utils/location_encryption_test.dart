import '../utils/location_decryption_utils.dart';
import '../services/firebase_service.dart';

/// LocationEncryptionTest provides utilities to test and validate
/// the location encryption/decryption system
class LocationEncryptionTest {
  
  /// Test the encryption and decryption of location data
  /// 
  /// [connectionCode] - Family connection code to test with
  /// [deviceInfo] - Device info for testing (optional, will generate if not provided)
  /// 
  /// Returns true if all tests pass, false otherwise
  static Future<bool> testLocationEncryption({
    required String connectionCode,
    String? deviceInfo,
  }) async {
    print('🔧 Starting location encryption tests...');
    
    try {
      // Use provided device info or generate test data
      final testDeviceInfo = deviceInfo ?? 'test_device_${DateTime.now().millisecondsSinceEpoch}';
      
      // Test data
      final testLocationData = {
        'latitude': 37.5665,
        'longitude': 126.9780,
        'address': '서울특별시 중구 명동',
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      print('📍 Test location data: $testLocationData');
      
      // Test 1: Basic encryption/decryption
      print('🔐 Test 1: Basic encryption/decryption...');
      final encrypted = LocationDecryptionUtils.encryptLocationData(
        testLocationData,
        connectionCode,
        testDeviceInfo,
      );
      
      if (!encrypted.startsWith('v1:')) {
        print('❌ Test 1 failed: Invalid encryption format');
        return false;
      }
      
      print('✅ Encrypted data: ${encrypted.substring(0, 50)}...');
      
      final decrypted = LocationDecryptionUtils.decryptLocationData(
        encrypted,
        connectionCode,
        testDeviceInfo,
      );
      
      if (!_compareLocationData(testLocationData, decrypted)) {
        print('❌ Test 1 failed: Decrypted data does not match original');
        print('Original: $testLocationData');
        print('Decrypted: $decrypted');
        return false;
      }
      
      print('✅ Test 1 passed: Basic encryption/decryption works');
      
      // Test 2: Backward compatibility with unencrypted data
      print('🔄 Test 2: Backward compatibility...');
      final unencryptedResult = LocationDecryptionUtils.safeDecryptLocationData(
        testLocationData,
        connectionCode,
        testDeviceInfo,
      );
      
      if (!_compareLocationData(testLocationData, unencryptedResult!)) {
        print('❌ Test 2 failed: Backward compatibility broken');
        return false;
      }
      
      print('✅ Test 2 passed: Backward compatibility works');
      
      // Test 3: Encryption detection
      print('🔍 Test 3: Encryption detection...');
      if (!LocationDecryptionUtils.isEncrypted(encrypted)) {
        print('❌ Test 3 failed: Failed to detect encrypted data');
        return false;
      }
      
      if (LocationDecryptionUtils.isEncrypted(testLocationData)) {
        print('❌ Test 3 failed: False positive for unencrypted data');
        return false;
      }
      
      print('✅ Test 3 passed: Encryption detection works');
      
      // Test 4: Validation
      print('✅ Test 4: Validation...');
      if (!LocationDecryptionUtils.validateEncryptedData(
        encrypted,
        connectionCode,
        testDeviceInfo,
      )) {
        print('❌ Test 4 failed: Validation failed for valid data');
        return false;
      }
      
      print('✅ Test 4 passed: Validation works');
      
      // Test 5: Wrong key handling
      print('🔐 Test 5: Wrong key handling...');
      try {
        final wrongDecrypted = LocationDecryptionUtils.decryptLocationData(
          encrypted,
          'wrong_connection_code',
          testDeviceInfo,
        );
        print('❌ Test 5 failed: Should have thrown error for wrong key');
        return false;
      } catch (e) {
        print('✅ Test 5 passed: Correctly rejected wrong key');
      }
      
      // Test 6: Coordinate encryption
      print('📍 Test 6: Coordinate encryption...');
      final encryptedCoords = LocationDecryptionUtils.encryptCoordinates(
        37.5665,
        126.9780,
        connectionCode,
        testDeviceInfo,
      );
      
      final decryptedCoords = LocationDecryptionUtils.decryptCoordinates(
        encryptedCoords,
        connectionCode,
        testDeviceInfo,
      );
      
      if (decryptedCoords == null ||
          (decryptedCoords['latitude']! - 37.5665).abs() > 0.0001 ||
          (decryptedCoords['longitude']! - 126.9780).abs() > 0.0001) {
        print('❌ Test 6 failed: Coordinate encryption/decryption failed');
        return false;
      }
      
      print('✅ Test 6 passed: Coordinate encryption works');
      
      print('🎉 All location encryption tests passed!');
      return true;
      
    } catch (e) {
      print('❌ Location encryption test failed with error: $e');
      return false;
    }
  }
  
  /// Test the Firebase integration with encryption
  /// 
  /// [connectionCode] - Family connection code to test with
  /// 
  /// Returns true if Firebase integration works correctly
  static Future<bool> testFirebaseIntegration({
    required String connectionCode,
  }) async {
    print('🔧 Starting Firebase integration tests...');
    
    try {
      // Test storage and retrieval
      final testSuccess = await FirebaseService.storeEncryptedLocation(
        connectionCode: connectionCode,
        latitude: 37.5665,
        longitude: 126.9780,
        address: '테스트 주소',
      );
      
      if (!testSuccess) {
        print('❌ Firebase storage test failed');
        return false;
      }
      
      print('✅ Successfully stored encrypted location to Firebase');
      
      // Wait a moment for storage to complete
      await Future.delayed(const Duration(seconds: 2));
      
      // Test retrieval
      final retrievedLocation = await FirebaseService.getDecryptedLocation(
        connectionCode: connectionCode,
      );
      
      if (retrievedLocation == null) {
        print('❌ Firebase retrieval test failed - no data returned');
        return false;
      }
      
      if ((retrievedLocation['latitude'] - 37.5665).abs() > 0.0001 ||
          (retrievedLocation['longitude'] - 126.9780).abs() > 0.0001) {
        print('❌ Firebase retrieval test failed - coordinates do not match');
        return false;
      }
      
      print('✅ Successfully retrieved and decrypted location from Firebase');
      print('🎉 Firebase integration tests passed!');
      return true;
      
    } catch (e) {
      print('❌ Firebase integration test failed with error: $e');
      return false;
    }
  }
  
  /// Generate test report for location encryption system
  /// 
  /// [connectionCode] - Family connection code to test with
  /// 
  /// Returns a detailed test report as a string
  static Future<String> generateTestReport({
    required String connectionCode,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('📊 Location Encryption System Test Report');
    buffer.writeln('==========================================');
    buffer.writeln('Test Date: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Connection Code: $connectionCode');
    buffer.writeln('');
    
    // Run encryption tests
    buffer.writeln('🔐 Encryption/Decryption Tests:');
    final encryptionResult = await testLocationEncryption(
      connectionCode: connectionCode,
    );
    buffer.writeln('Result: ${encryptionResult ? "✅ PASSED" : "❌ FAILED"}');
    buffer.writeln('');
    
    // Run Firebase integration tests
    buffer.writeln('🗄️ Firebase Integration Tests:');
    final firebaseResult = await testFirebaseIntegration(
      connectionCode: connectionCode,
    );
    buffer.writeln('Result: ${firebaseResult ? "✅ PASSED" : "❌ FAILED"}');
    buffer.writeln('');
    
    // Overall result
    final overallResult = encryptionResult && firebaseResult;
    buffer.writeln('📈 Overall Test Result:');
    buffer.writeln(overallResult ? "🎉 ALL TESTS PASSED" : "❌ SOME TESTS FAILED");
    buffer.writeln('');
    
    // Security information
    buffer.writeln('🔒 Security Information:');
    buffer.writeln('- Encryption: AES-256-CBC');
    buffer.writeln('- Key Derivation: PBKDF2-SHA256 (10,000 iterations)');
    buffer.writeln('- Key Source: Connection Code + Device Info');
    buffer.writeln('- Format: v1:base64(iv + encryptedData)');
    buffer.writeln('- Backward Compatibility: Yes');
    
    return buffer.toString();
  }
  
  // Helper method to compare location data
  static bool _compareLocationData(Map<String, dynamic> original, Map<String, dynamic> decrypted) {
    // Check required fields
    if (original['latitude'] != decrypted['latitude']) return false;
    if (original['longitude'] != decrypted['longitude']) return false;
    
    // Check optional fields
    if (original.containsKey('address') && original['address'] != decrypted['address']) return false;
    if (original.containsKey('timestamp') && original['timestamp'] != decrypted['timestamp']) return false;
    
    return true;
  }
}