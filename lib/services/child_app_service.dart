import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart';
import '../utils/secure_logger.dart';
import 'encryption_service.dart';

class ChildAppService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final AuthService _authService = AuthService();

  // Connection tracking
  final Map<String, StreamSubscription> _activeListeners = {};
  bool _isConnected = false;
  DateTime? _lastSuccessfulOperation;

  // Encryption key cache (familyId -> derived key)
  final Map<String, String> _encryptionKeyCache = {};

  /// Ensure authentication with proper error handling and recovery
  Future<bool> _ensureAuthenticated() async {
    try {
      // First check if there's a current user
      final currentUser = FirebaseAuth.instance.currentUser;
      
      if (currentUser != null) {
        secureLog.security('User already authenticated (anonymous: ${currentUser.isAnonymous})');
        return true;
      }
      
      // If no user, try to authenticate anonymously for Firebase access
      secureLog.security('No current user, attempting anonymous authentication');
      try {
        final userCredential = await FirebaseAuth.instance.signInAnonymously();
        if (userCredential.user != null) {
          secureLog.security('Anonymous authentication successful');
          return true;
        }
      } catch (e) {
        secureLog.error('Anonymous authentication failed', e);
      }
      
      // Fallback to AuthService validation
      return await _authService.isAuthenticationValid();
    } catch (e) {
      secureLog.error('Authentication failed in ChildAppService', e);
      return false;
    }
  }

  /// Execute Firebase operation with timeout and retry logic
  Future<T?> _executeWithRetry<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration timeout = const Duration(seconds: 15),
    String operationName = 'Firebase operation',
  }) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        // Ensure authentication before each attempt
        final authSuccess = await _ensureAuthenticated();
        if (!authSuccess) {
          secureLog.warning('Authentication failed for $operationName, attempt ${attempt + 1}');
          throw Exception('Authentication failed');
        }

        // Execute operation with timeout
        return await operation().timeout(timeout);
      } on SocketException catch (e) {
        secureLog.warning('Network error in $operationName (attempt ${attempt + 1})', e);
        if (attempt == maxRetries - 1) rethrow;
        await Future.delayed(Duration(seconds: math.pow(2, attempt).toInt()));
      } on TimeoutException catch (e) {
        secureLog.warning('Timeout in $operationName (attempt ${attempt + 1})', e);
        if (attempt == maxRetries - 1) rethrow;
        await Future.delayed(Duration(seconds: math.pow(2, attempt).toInt()));
      } on FirebaseException catch (e) {
        secureLog.error('Firebase error in $operationName (attempt ${attempt + 1}): ${e.code}', e);
        
        // Enhanced error handling for new security model
        if (e.code == 'permission-denied') {
          secureLog.error('PERMISSION DENIED - user may not be in family memberIds or security rules blocked access', e);
          
          // For approval operations, retry once in case of race conditions
          if (operationName == 'approveFamilyCode' && attempt < 1) {
            secureLog.warning('Retrying approval operation in case of race condition');
            await Future.delayed(Duration(seconds: 2));
            continue;
          }
          
          // For other operations, provide more context
          if (operationName.contains('getFamilyInfo')) {
            secureLog.error('Family info access denied - user may not be in memberIds array');
          } else if (operationName.contains('survival') || operationName.contains('recordings')) {
            secureLog.error('Family data access denied - user may have been removed from family');
          }
          
          // Don't retry permission errors - they indicate security rule violations
          rethrow;
        }
        
        // Don't retry invalid data errors
        if (e.code == 'invalid-argument') {
          rethrow;
        }
        if (attempt == maxRetries - 1) rethrow;
        await Future.delayed(Duration(seconds: math.pow(2, attempt).toInt()));
      } catch (e) {
        secureLog.error('Unexpected error in $operationName (attempt ${attempt + 1})', e);
        if (attempt == maxRetries - 1) rethrow;
        await Future.delayed(Duration(seconds: math.pow(2, attempt).toInt()));
      }
    }
    return null;
  }

  /// Get or derive encryption key for a family
  ///
  /// Derives the key from familyId and caches it for future use
  /// [familyId] The family identifier
  /// Returns base64-encoded encryption key
  String _getEncryptionKey(String familyId) {
    // Check cache first
    if (_encryptionKeyCache.containsKey(familyId)) {
      return _encryptionKeyCache[familyId]!;
    }

    // Derive key from familyId
    secureLog.debug('Deriving encryption key for familyId: $familyId');
    final key = EncryptionService.deriveEncryptionKey(familyId);

    // Cache the key
    _encryptionKeyCache[familyId] = key;
    secureLog.debug('Encryption key derived and cached');

    return key;
  }

  /// Decrypt location data from Firestore
  ///
  /// [locationData] The location data map from Firestore
  /// [familyId] The family identifier for key derivation
  ///
  /// Returns decrypted location data or null if:
  /// - Location data is null/empty
  /// - Location data is not encrypted (backward compatibility)
  /// - Decryption fails
  Map<String, dynamic>? _decryptLocationData(
    Map<String, dynamic>? locationData,
    String familyId,
  ) {
    if (locationData == null || locationData.isEmpty) {
      return null;
    }

    // Check if location data is encrypted
    final encrypted = locationData['encrypted'] as String?;
    final iv = locationData['iv'] as String?;

    if (encrypted != null && iv != null) {
      // Location data is encrypted - decrypt it
      try {
        secureLog.debug('Decrypting location data for familyId: $familyId');
        final key = _getEncryptionKey(familyId);

        final decrypted = EncryptionService.decryptLocation(
          encryptedData: encrypted,
          ivBase64: iv,
          base64Key: key,
        );

        // Add timestamp if present
        if (locationData.containsKey('timestamp')) {
          decrypted['timestamp'] = locationData['timestamp'];
        }

        secureLog.debug('Location data decrypted successfully');
        return decrypted;
      } catch (e) {
        secureLog.error('Failed to decrypt location data', e);
        return null;
      }
    } else {
      // Location data is not encrypted (backward compatibility)
      // Return as-is if it has latitude/longitude
      if (locationData.containsKey('latitude') &&
          locationData.containsKey('longitude')) {
        secureLog.debug('Location data is not encrypted - using plain data');
        return locationData;
      }

      return null;
    }
  }

  /// Validate and get family information using connection code
  /// Now uses the new connection_codes collection for secure lookups
  Future<Map<String, dynamic>?> getFamilyInfo(String connectionCode) async {
    return await _executeWithRetry<Map<String, dynamic>?>(
      () async {
        secureLog.operationStart('Getting family info for connection code using new security model');
        
        // Ensure we have proper authentication
        final currentUser = FirebaseAuth.instance.currentUser;
        secureLog.debug('Current user authenticated (anonymous: ${currentUser?.isAnonymous ?? 'unknown'})');
        
        // First, look up the connection code in the new connection_codes collection
        secureLog.debug('Querying connection_codes collection');
        final codeQuery = await _firestore.collection('connection_codes')
            .where('code', isEqualTo: connectionCode)
            .where('isActive', isEqualTo: true)
            .limit(1)
            .get();
        
        if (codeQuery.docs.isEmpty) {
          secureLog.warning('Connection code not found or inactive in connection_codes collection');
          
          // Fallback: check old families collection for backward compatibility
          secureLog.debug('Checking old families collection for backward compatibility');
          final oldQuery = await _firestore.collection('families')
              .where('connectionCode', isEqualTo: connectionCode)
              .limit(1)
              .get();
          
          if (oldQuery.docs.isNotEmpty) {
            final doc = oldQuery.docs.first;
            final data = doc.data();
            data['familyId'] = doc.id;
            secureLog.info('Found family using old structure - backward compatibility');
            return data;
          }
          
          return null;
        }
        
        // Get the family ID from the connection code document
        final codeDoc = codeQuery.docs.first;
        final codeData = codeDoc.data();
        final familyId = codeData['familyId'] as String?;
        
        if (familyId == null) {
          secureLog.error('Connection code document missing familyId');
          return null;
        }
        
        secureLog.debug('Found familyId: $familyId for connection code');
        
        // Now get the actual family document
        final familyDoc = await _firestore.collection('families').doc(familyId).get();
        
        if (!familyDoc.exists) {
          secureLog.error('Family document does not exist for ID: $familyId');
          return null;
        }
        
        final familyData = familyDoc.data()!;
        familyData['familyId'] = familyId;
        familyData['connectionCode'] = connectionCode; // Ensure connection code is included
        
        secureLog.operationSuccess('Family info found with elderly name: ${familyData['elderlyName']}, approved: ${familyData['approved']}, memberIds count: ${(familyData['memberIds'] as List?)?.length ?? 0}');
        
        return familyData;
      },
      operationName: 'getFamilyInfo',
    );
  }

  /// Approve/reject family code (CRITICAL for elderly app to proceed)
  /// Now implements secure joining with memberIds validation
  Future<bool> approveFamilyCode(String connectionCode, bool approved) async {
    return await _executeWithRetry<bool>(
      () async {
        secureLog.security('CRITICAL: Attempting to approve family connection with new security model');
        
        // Ensure we have authentication
        final currentUser = FirebaseAuth.instance.currentUser;
        secureLog.security('Current user authenticated for approval (anonymous: ${currentUser?.isAnonymous})');
        
        if (currentUser == null) {
          throw Exception('No authenticated user for approval operation');
        }
        
        // Get family info using the new lookup method
        final familyData = await getFamilyInfo(connectionCode);
        
        if (familyData == null) {
          secureLog.error('ERROR: Connection code does not exist or is invalid');
          throw Exception('Family document not found for connection code: $connectionCode');
        }
        
        final familyId = familyData['familyId'] as String;
        
        secureLog.operationSuccess('Found family document for approval - Elderly: ${familyData['elderlyName']}, Current approval: ${familyData['approved']}');
        
        // Use a transaction to atomically add user to memberIds and update approval status
        secureLog.debug('Starting transaction to update approval status and membership');
        
        final result = await _firestore.runTransaction<bool>((transaction) async {
          // Re-read the document inside the transaction
          final familyDocRef = _firestore.collection('families').doc(familyId);
          final snapshot = await transaction.get(familyDocRef);
          
          if (!snapshot.exists) {
            throw Exception('Family document no longer exists during transaction');
          }
          
          final currentFamilyData = snapshot.data()!;
          final currentMemberIds = List<String>.from(currentFamilyData['memberIds'] ?? []);
          
          // Prepare update data
          Map<String, dynamic> updateData = {
            'approved': approved,
            'approvedAt': FieldValue.serverTimestamp(),
            'approvedBy': currentUser.uid,
          };
          
          // Add child info to the family document
          if (approved) {
            // Add the current user to memberIds if not already present
            if (!currentMemberIds.contains(currentUser.uid)) {
              currentMemberIds.add(currentUser.uid);
              updateData['memberIds'] = currentMemberIds;
              secureLog.security('Adding current user to family memberIds');
            }
            
            // Add child info to track who joined
            final childInfo = {
              currentUser.uid: {
                'email': currentUser.email,
                'displayName': currentUser.displayName ?? 'Child User',
                'joinedAt': FieldValue.serverTimestamp(),
                'role': 'child',
              }
            };
            
            updateData['childInfo'] = {
              ...Map<String, dynamic>.from(currentFamilyData['childInfo'] ?? {}),
              ...childInfo,
            };
          }
          
          // Update the family document
          transaction.update(familyDocRef, updateData);
          
          // If approved, also deactivate the connection code to prevent reuse
          if (approved) {
            try {
              final codeQuery = await _firestore.collection('connection_codes')
                  .where('code', isEqualTo: connectionCode)
                  .where('familyId', isEqualTo: familyId)
                  .limit(1)
                  .get();
              
              if (codeQuery.docs.isNotEmpty) {
                final codeDocRef = _firestore.collection('connection_codes').doc(codeQuery.docs.first.id);
                transaction.update(codeDocRef, {
                  'isActive': false,
                  'usedAt': FieldValue.serverTimestamp(),
                  'usedBy': currentUser.uid,
                });
                secureLog.debug('Connection code deactivated after successful approval');
              }
            } catch (e) {
              secureLog.warning('Failed to deactivate connection code, but continuing: $e');
              // Don't fail the transaction if code deactivation fails
            }
          }
          
          secureLog.debug('Transaction prepared with updates: ${updateData.keys.join(', ')}');
          return true;
        });
        
        if (result) {
          secureLog.operationSuccess('Family updated with approval status: $approved');
          
          // Verify the update worked by re-reading the document
          final updatedDoc = await _firestore.collection('families').doc(familyId).get();
          if (updatedDoc.exists) {
            final updatedData = updatedDoc.data()!;
            final newApprovalStatus = updatedData['approved'];
            final newMemberIds = List<String>.from(updatedData['memberIds'] ?? []);
            
            secureLog.debug('VERIFICATION: approved field is now: $newApprovalStatus, memberIds count: ${newMemberIds.length}');
            
            if (newApprovalStatus == approved) {
              if (approved && !newMemberIds.contains(currentUser.uid)) {
                secureLog.warning('WARNING: User was not added to memberIds as expected');
              } else {
                secureLog.operationSuccess('CONFIRMATION: Secure approval update was successful!');
              }
              return true;
            } else {
              secureLog.error('VERIFICATION FAILED: Expected $approved, got $newApprovalStatus');
              throw Exception('Approval update verification failed');
            }
          } else {
            secureLog.error('VERIFICATION FAILED: Document no longer exists');
            throw Exception('Document disappeared after update');
          }
        } else {
          throw Exception('Transaction failed to complete');
        }
      },
      operationName: 'approveFamilyCode',
      maxRetries: 2, // Fewer retries for approval to avoid double-processing
    ) ?? false;
  }

  /// Get all recordings with audio/photo URLs
  /// Now uses secure family lookup
  Future<List<Map<String, dynamic>>> getAllRecordings(String connectionCode) async {
    try {
      // Use the new secure getFamilyInfo method
      final familyData = await getFamilyInfo(connectionCode);
      
      if (familyData == null) {
        secureLog.error('ERROR: Connection code does not exist or user not authorized');
        return [];
      }
      
      final familyId = familyData['familyId'] as String;
      secureLog.debug('Found family ID for connection code with security validation');
      
      final collection = await _firestore
          .collection('families')
          .doc(familyId)
          .collection('recordings')
          .orderBy(FieldPath.documentId, descending: true)
          .get();

      List<Map<String, dynamic>> allRecordings = [];

      for (var doc in collection.docs) {
        final data = doc.data();
        final recordings = data['recordings'] as List<dynamic>? ?? [];

        for (var recording in recordings) {
          allRecordings.add({
            'date': doc.id, // YYYY-MM-DD format
            'audioUrl': recording['audioUrl'], // Direct Firebase Storage URL
            'photoUrl': recording['photoUrl'], // Direct Firebase Storage URL  
            'timestamp': recording['timestamp'], // ISO 8601 string
            'elderlyName': recording['elderlyName'],
          });
        }
      }

      // Sort by timestamp (newest first)
      allRecordings.sort((a, b) =>
          DateTime.parse(b['timestamp']).compareTo(DateTime.parse(a['timestamp']))
      );

      return allRecordings;
    } catch (e) {
      secureLog.error('Failed to get recordings', e);
      return [];
    }
  }

  /// Real-time stream of new recordings
  /// Now uses secure family lookup
  Stream<List<Map<String, dynamic>>> listenToNewRecordings(String connectionCode) async* {
    // Use the new secure getFamilyInfo method
    final familyData = await getFamilyInfo(connectionCode);
    
    if (familyData == null) {
      secureLog.error('ERROR: Connection code does not exist or user not authorized');
      yield [];
      return;
    }
    
    final familyId = familyData['familyId'] as String;
    secureLog.debug('Found family ID for connection code with security validation');
    
    await for (final snapshot in _firestore
        .collection('families')
        .doc(familyId)
        .collection('recordings')
        .snapshots()) {
      List<Map<String, dynamic>> allRecordings = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final recordings = data['recordings'] as List<dynamic>? ?? [];

        for (var recording in recordings) {
          allRecordings.add({
            'date': doc.id,
            'audioUrl': recording['audioUrl'],
            'photoUrl': recording['photoUrl'],
            'timestamp': recording['timestamp'],
            'elderlyName': recording['elderlyName'],
          });
        }
      }

      allRecordings.sort((a, b) =>
          DateTime.parse(b['timestamp']).compareTo(DateTime.parse(a['timestamp']))
      );

      yield allRecordings;
    }
  }

  /// Get survival status (ACTIVITY DETECTION)
  /// Now uses secure family lookup
  Future<Map<String, dynamic>?> getSurvivalStatus(String connectionCode) async {
    try {
      // Use the new secure getFamilyInfo method
      final familyData = await getFamilyInfo(connectionCode);
      
      if (familyData == null) {
        secureLog.error('ERROR: Connection code does not exist or user not authorized');
        return null;
      }
      
      final familyId = familyData['familyId'] as String;
      final doc = await _firestore.collection('families').doc(familyId).get();

      if (doc.exists) {
        final data = doc.data()!;
        // Parse optimized meal data structure
        final mealData = data['lastMeal'] as Map<String, dynamic>?;
        final todayMealCount = mealData?['count'] as int? ?? 0;
        
        // Handle timestamp conversion (Firebase returns Timestamp, not String)
        String? lastMealTime;
        final mealTimestamp = mealData?['timestamp'];
        if (mealTimestamp != null) {
          if (mealTimestamp is Timestamp) {
            lastMealTime = mealTimestamp.toDate().toIso8601String();
          } else if (mealTimestamp is String) {
            lastMealTime = mealTimestamp;
          }
        }
        
        // Parse optimized alert structure
        final alerts = data['alerts'] as Map<String, dynamic>?;
        final survivalAlert = {
          'isActive': alerts?['survival'] != null,
          'timestamp': alerts?['survival'],
          'message': alerts?['survival'] != null ? '장시간 활동 없음' : null,
        };

        // Decrypt location data if present
        final rawLocationData = data['location'] as Map<String, dynamic>?;
        final decryptedLocation = _decryptLocationData(rawLocationData, familyId);

        return {
          'lastMealTime': lastMealTime, // Last meal timestamp (optimized structure)
          'todayMealCount': todayMealCount, // Today's meal count (optimized structure)
          'survivalAlert': survivalAlert, // Active alert info (optimized structure)
          'lastPhoneActivity': data['blastPhoneActivity'] ?? data['lastPhoneActivity'], // General phone activity (fix field name)
          'lastActive': data['lastActive'], // Our specific app usage
          'elderlyName': data['elderlyName'],
          'location': decryptedLocation, // Decrypted location data
          'batteryLevel': data['batteryLevel'] as int?, // Battery percentage (0-100)
          'isCharging': data['isCharging'] as bool?, // Charging status
          'batteryTimestamp': data['batteryTimestamp'], // When battery was read
          'batteryHealth': data['batteryHealth'] as String?, // Battery health status
        };
      }
      return null;
    } catch (e) {
      secureLog.error('Failed to get survival status', e);
      return null;
    }
  }

  /// Real-time survival monitoring stream
  /// Now uses secure family lookup
  Stream<Map<String, dynamic>> listenToSurvivalStatus(String connectionCode) async* {
    try {
      // Use the new secure getFamilyInfo method
      final familyData = await getFamilyInfo(connectionCode);
      
      if (familyData == null) {
        secureLog.error('ERROR: Connection code does not exist or user not authorized');
        yield {};
        return;
      }
      
      final familyId = familyData['familyId'] as String;
      secureLog.debug('Found family ID for connection code with security validation');
      
      await for (final snapshot in _firestore
          .collection('families')
          .doc(familyId)
          .snapshots()) {
        if (snapshot.exists) {
          final data = snapshot.data()!;
          
          
          // Parse optimized meal data structure
          final mealData = data['lastMeal'] as Map<String, dynamic>?;
          final todayMealCount = mealData?['count'] as int? ?? 0;
          
          // Handle timestamp conversion (Firebase returns Timestamp, not String)
          String? lastMealTime;
          final mealTimestamp = mealData?['timestamp'];
          if (mealTimestamp != null) {
            if (mealTimestamp is Timestamp) {
              lastMealTime = mealTimestamp.toDate().toIso8601String();
            } else if (mealTimestamp is String) {
              lastMealTime = mealTimestamp;
            }
          }
          
          // Parse optimized alert structure
          final alerts = data['alerts'] as Map<String, dynamic>?;
          final survivalAlert = {
            'isActive': alerts?['survival'] != null,
            'timestamp': alerts?['survival'],
            'message': alerts?['survival'] != null ? '장시간 활동 없음' : null,
          };
          
          // Decrypt location data if present
          final rawLocationData = data['location'] as Map<String, dynamic>?;
          final decryptedLocation = _decryptLocationData(rawLocationData, familyId);

          yield {
            'lastMealTime': lastMealTime, // Last meal timestamp (optimized structure)
            'todayMealCount': todayMealCount, // Today's meal count (optimized structure)
            'survivalAlert': survivalAlert, // Alert details if triggered (optimized structure)
            'lastPhoneActivity': data['blastPhoneActivity'] ?? data['lastPhoneActivity'], // General phone activity (fix field name)
            'lastActive': data['lastActive'], // Our specific app usage
            'elderlyName': data['elderlyName'],
            'settings': data['settings'], // App settings
            'location': decryptedLocation, // Decrypted location data
            'batteryLevel': data['batteryLevel'] as int?, // Battery percentage (0-100)
            'isCharging': data['isCharging'] as bool?, // Charging status
            'batteryTimestamp': data['batteryTimestamp'], // When battery was read
            'batteryHealth': data['batteryHealth'] as String?, // Battery health status
          };
        } else {
          secureLog.warning('Family document deleted');
          yield {};
        }
      }
    } catch (e) {
      secureLog.error('Error in listenToSurvivalStatus', e);
      yield {};
    }
  }

  /// Clear survival alert after family acknowledges
  /// Now uses secure family lookup and updates lastPhoneActivity to current time
  Future<bool> clearSurvivalAlert(String connectionCode) async {
    try {
      // Use the new secure getFamilyInfo method
      final familyData = await getFamilyInfo(connectionCode);
      
      if (familyData == null) {
        secureLog.error('ERROR: Connection code does not exist or user not authorized');
        return false;
      }
      
      final familyId = familyData['familyId'] as String;
      final currentUser = FirebaseAuth.instance.currentUser;
      
      await _firestore.collection('families').doc(familyId).update({
        'alerts.survival': null, // Clear survival alert (optimized structure)
        'alertsCleared.survival': FieldValue.serverTimestamp(),
        'alertsClearedBy.survival': currentUser?.uid ?? 'Child App',
        'lastPhoneActivity': FieldValue.serverTimestamp(), // Update lastPhoneActivity to current time
        'blastPhoneActivity': FieldValue.serverTimestamp(), // Also update blastPhoneActivity for compatibility
      });
      return true;
    } catch (e) {
      secureLog.error('Failed to clear survival alert', e);
      return false;
    }
  }


  /// Update app settings
  /// Now uses secure family lookup
  Future<bool> updateSettings(String connectionCode, Map<String, dynamic> settings) async {
    try {
      // Use the new secure getFamilyInfo method
      final familyData = await getFamilyInfo(connectionCode);
      
      if (familyData == null) {
        secureLog.error('ERROR: Connection code does not exist or user not authorized');
        return false;
      }
      
      final familyId = familyData['familyId'] as String;
      
      Map<String, dynamic> updateData = {};
      settings.forEach((key, value) {
        updateData['settings.$key'] = value;
      });
      
      await _firestore.collection('families').doc(familyId).update(updateData);
      return true;
    } catch (e) {
      secureLog.error('Failed to update settings', e);
      return false;
    }
  }

  /// Get statistics for family dashboard
  /// Now uses secure family lookup
  Future<Map<String, dynamic>> getStatistics(String connectionCode) async {
    try {
      await _ensureAuthenticated();
      
      // Use the new secure getFamilyInfo method
      final familyData = await getFamilyInfo(connectionCode);
      
      if (familyData == null) {
        secureLog.error('ERROR: Connection code does not exist or user not authorized');
        return {};
      }
      
      final familyId = familyData['familyId'] as String;
      
      final collection = await _firestore
          .collection('families')
          .doc(familyId)
          .collection('recordings')
          .get();

      int totalRecordings = 0;
      int daysWithRecordings = collection.docs.length;
      Map<String, int> dailyCounts = {};

      for (var doc in collection.docs) {
        final data = doc.data();
        final recordings = data['recordings'] as List<dynamic>? ?? [];
        totalRecordings += recordings.length;
        dailyCounts[doc.id] = recordings.length;
      }

      return {
        'totalRecordings': totalRecordings,
        'daysWithRecordings': daysWithRecordings,
        'dailyCounts': dailyCounts, // Map<date, count>
        'averagePerDay': daysWithRecordings > 0 ? totalRecordings / daysWithRecordings : 0,
      };
    } catch (e) {
      secureLog.error('Failed to get statistics', e);
      return {};
    }
  }

  /// Check if family document still exists (for account deletion detection)
  /// Returns null if network error, true/false if successful check
  /// Now uses secure family lookup with memberIds validation
  Future<bool?> checkFamilyExists(String connectionCode) async {
    secureLog.debug('Checking if family exists for connection code with security validation');
    
    try {
      final result = await _executeWithRetry<bool>(
        () async {
          // Use the new secure getFamilyInfo method
          final familyData = await getFamilyInfo(connectionCode);
          
          if (familyData != null) {
            secureLog.info('Family found and user authorized for connection code');
            
            // Additional validation: check if user is still in memberIds
            final currentUser = FirebaseAuth.instance.currentUser;
            if (currentUser != null) {
              final memberIds = List<String>.from(familyData['memberIds'] ?? []);
              if (!memberIds.contains(currentUser.uid)) {
                secureLog.warning('User no longer in family memberIds - access revoked');
                return false; // User was removed from family
              }
            }
            
            // Check if document has basic required fields
            final hasRequiredFields = familyData.containsKey('elderlyName') || familyData.containsKey('createdAt');
            if (!hasRequiredFields) {
              secureLog.warning('Family document exists but missing required fields');
              return false; // Treat as deleted if document is corrupted
            }
            
            return true;
          } else {
            secureLog.warning('No family found or user not authorized for connection code');
            return false;
          }
        },
        operationName: 'checkFamilyExists',
      );
      
      if (result == null) {
        secureLog.warning('checkFamilyExists failed due to network/connection issues');
      }
      
      return result;
    } catch (e) {
      secureLog.error('Exception in checkFamilyExists', e);
      return null; // Return null to indicate network/connection problem, not deletion
    }
  }

  /// Stream to monitor family document existence
  /// Now uses secure family lookup with memberIds validation
  Stream<bool> listenToFamilyExistence(String connectionCode) async* {
    try {
      // Use the new secure getFamilyInfo method to get family ID
      final familyData = await getFamilyInfo(connectionCode);
      
      if (familyData == null) {
        secureLog.warning('Family document not found or user not authorized for connection code');
        yield false;
        return;
      }
      
      final familyId = familyData['familyId'] as String;
      secureLog.debug('Monitoring family document existence with security validation');
      
      // Start with true - assume family exists until proven otherwise
      bool lastKnownState = true;
      yield true;
      
      await for (final snapshot in _firestore
          .collection('families')
          .doc(familyId)
          .snapshots(includeMetadataChanges: true)) {
        
        // Check if this is a metadata-only change (network status change)
        if (snapshot.metadata.hasPendingWrites || 
            snapshot.metadata.isFromCache) {
          secureLog.debug('Metadata change detected - from cache: ${snapshot.metadata.isFromCache}, pending writes: ${snapshot.metadata.hasPendingWrites}');
          // Don't yield false for network/cache issues - keep last known state
          continue;
        }
        
        bool currentExists = snapshot.exists;
        
        // Additional check: if document exists, verify user is still in memberIds
        if (currentExists && snapshot.data() != null) {
          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser != null) {
            final memberIds = List<String>.from(snapshot.data()!['memberIds'] ?? []);
            if (!memberIds.contains(currentUser.uid)) {
              secureLog.warning('User no longer in family memberIds - treating as non-existent');
              currentExists = false; // User was removed from family
            }
          }
        }
        
        // Only yield changes if the existence state actually changed
        if (currentExists != lastKnownState) {
          secureLog.info('Family existence changed from $lastKnownState to $currentExists');
          lastKnownState = currentExists;
          yield currentExists;
          
          if (!currentExists) {
            secureLog.warning('Family document deleted or user access revoked');
          } else {
            secureLog.info('Family document restored/created or user access granted');
          }
        } else {
          secureLog.debug('No change in family existence state: $currentExists');
        }
      }
    } catch (e) {
      secureLog.error('Error monitoring family existence', e);
      // Don't yield false on errors - this could be network issues
      secureLog.warning('Network error in family monitoring - not yielding false to prevent incorrect account deletion');
    }
  }
  
  /// Clean up all active listeners
  void dispose() {
    for (final subscription in _activeListeners.values) {
      subscription.cancel();
    }
    _activeListeners.clear();
    _encryptionKeyCache.clear(); // Clear cached encryption keys
    secureLog.info('ChildAppService disposed - all listeners cancelled and encryption keys cleared');
  }
  
  /// Get connection status
  bool get isConnected => _isConnected;
  
  /// Get last successful operation time
  DateTime? get lastSuccessfulOperation => _lastSuccessfulOperation;

}