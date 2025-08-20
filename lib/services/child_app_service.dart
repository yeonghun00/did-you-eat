import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart';
import '../utils/secure_logger.dart';

class ChildAppService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final AuthService _authService = AuthService();
  
  // Connection tracking
  final Map<String, StreamSubscription> _activeListeners = {};
  bool _isConnected = false;
  DateTime? _lastSuccessfulOperation;

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
        
        // For approval operations specifically, provide detailed error context
        if (operationName == 'approveFamilyCode' && e.code == 'permission-denied') {
          secureLog.error('PERMISSION DENIED during approval operation - user may not be in family memberIds yet', e);
          
          // For permission errors during approval, retry once in case of race conditions
          if (attempt < 1) {
            secureLog.warning('Retrying approval operation in case of race condition');
            await Future.delayed(Duration(seconds: 2));
            continue;
          }
        }
        
        // Don't retry permission errors (except approval operations) or invalid data errors
        if (e.code == 'permission-denied' || e.code == 'invalid-argument') {
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

  /// Validate and get family information using connection code
  Future<Map<String, dynamic>?> getFamilyInfo(String connectionCode) async {
    return await _executeWithRetry<Map<String, dynamic>?>(
      () async {
        secureLog.operationStart('Getting family info for connection code');
        
        // Ensure we have proper authentication
        final currentUser = FirebaseAuth.instance.currentUser;
        secureLog.debug('Current user authenticated (anonymous: ${currentUser?.isAnonymous ?? 'unknown'})');
        
        // Query by connectionCode instead of document ID
        secureLog.debug('Querying families collection');
        final query = await _firestore.collection('families')
            .where('connectionCode', isEqualTo: connectionCode)
            .limit(1)
            .get();
        
        secureLog.debug('Query completed. Found ${query.docs.length} documents');
        
        if (query.docs.isNotEmpty) {
          final doc = query.docs.first;
          final data = doc.data();
          data['familyId'] = doc.id; // Add document ID for reference
          
          secureLog.operationSuccess('Family info found with elderly name: ${data['elderlyName']}, approved: ${data['approved']}, active: ${data['isActive']}');
          
          return data;
        } else {
          secureLog.warning('Connection code does not exist in families collection');
          
          // Debug: Let's check if there are any families at all
          try {
            final allFamilies = await _firestore.collection('families').limit(5).get();
            secureLog.debug('Debug: Found ${allFamilies.docs.length} families in collection');
            for (final family in allFamilies.docs) {
              final familyData = family.data();
              secureLog.debug('Family found with elderlyName: ${familyData['elderlyName']}');
            }
          } catch (e) {
            secureLog.error('Debug query failed', e);
          }
          
          return null; // Return null instead of empty map for clarity
        }
      },
      operationName: 'getFamilyInfo',
    );
  }

  /// Approve/reject family code (CRITICAL for elderly app to proceed)
  Future<bool> approveFamilyCode(String connectionCode, bool approved) async {
    return await _executeWithRetry<bool>(
      () async {
        secureLog.security('CRITICAL: Attempting to approve family connection');
        
        // Ensure we have authentication
        final currentUser = FirebaseAuth.instance.currentUser;
        secureLog.security('Current user authenticated for approval (anonymous: ${currentUser?.isAnonymous})');
        
        if (currentUser == null) {
          throw Exception('No authenticated user for approval operation');
        }
        
        // Find the family document by connection code
        secureLog.debug('Querying for family with connection code');
        final query = await _firestore.collection('families')
            .where('connectionCode', isEqualTo: connectionCode)
            .limit(1)
            .get();
        
        if (query.docs.isEmpty) {
          secureLog.error('ERROR: Connection code does not exist');
          throw Exception('Family document not found for connection code: $connectionCode');
        }
        
        final doc = query.docs.first;
        final familyId = doc.id;
        final currentData = doc.data();
        
        secureLog.operationSuccess('Found family document for approval - Elderly: ${currentData['elderlyName']}, Current approval: ${currentData['approved']}');
        
        // Verify this is the right document
        if (currentData['connectionCode'] != connectionCode) {
          throw Exception('Connection code mismatch: expected $connectionCode, got ${currentData['connectionCode']}');
        }
        
        // Use a transaction to atomically add user to memberIds and update approval status
        secureLog.debug('Starting transaction to update approval status and membership');
        
        final result = await _firestore.runTransaction<bool>((transaction) async {
          // Re-read the document inside the transaction
          final familyDocRef = _firestore.collection('families').doc(familyId);
          final snapshot = await transaction.get(familyDocRef);
          
          if (!snapshot.exists) {
            throw Exception('Family document no longer exists during transaction');
          }
          
          final familyData = snapshot.data()!;
          final currentMemberIds = List<String>.from(familyData['memberIds'] ?? []);
          
          // Prepare update data
          Map<String, dynamic> updateData = {
            'approved': approved,
            'approvedAt': FieldValue.serverTimestamp(),
            'approvedBy': 'Child App',
            'childAppUserId': currentUser.uid,
          };
          
          // If approving, add the current user to memberIds if not already present
          if (approved && !currentMemberIds.contains(currentUser.uid)) {
            currentMemberIds.add(currentUser.uid);
            updateData['memberIds'] = currentMemberIds;
            secureLog.security('Adding current user to family memberIds');
          }
          
          // Perform the atomic update
          transaction.update(familyDocRef, updateData);
          
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
            
            secureLog.debug('VERIFICATION: approved field is now: $newApprovalStatus, memberIds count: ${newMemberIds?.length ?? 0}');
            
            if (newApprovalStatus == approved) {
              if (approved && !newMemberIds.contains(currentUser.uid)) {
                secureLog.warning('WARNING: User was not added to memberIds as expected');
              } else {
                secureLog.operationSuccess('CONFIRMATION: Approval update was successful!');
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
  Future<List<Map<String, dynamic>>> getAllRecordings(String connectionCode) async {
    try {
      // First find the family document by connection code
      final query = await _firestore.collection('families')
          .where('connectionCode', isEqualTo: connectionCode)
          .limit(1)
          .get();
      
      if (query.docs.isEmpty) {
        secureLog.error('ERROR: Connection code does not exist');
        return [];
      }
      
      final familyId = query.docs.first.id;
      secureLog.debug('Found family ID for connection code');
      
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
  Stream<List<Map<String, dynamic>>> listenToNewRecordings(String connectionCode) async* {
    // First find the family document by connection code
    final query = await _firestore.collection('families')
        .where('connectionCode', isEqualTo: connectionCode)
        .limit(1)
        .get();
    
    if (query.docs.isEmpty) {
      secureLog.error('ERROR: Connection code does not exist');
      yield [];
      return;
    }
    
    final familyId = query.docs.first.id;
    secureLog.debug('Found family ID for connection code');
    
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
  Future<Map<String, dynamic>?> getSurvivalStatus(String connectionCode) async {
    try {
      // First find the family document by connection code
      final query = await _firestore.collection('families')
          .where('connectionCode', isEqualTo: connectionCode)
          .limit(1)
          .get();
      
      if (query.docs.isEmpty) {
        secureLog.error('ERROR: Connection code does not exist');
        return null;
      }
      
      final familyId = query.docs.first.id;
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

        return {
          'lastMealTime': lastMealTime, // Last meal timestamp (optimized structure)
          'todayMealCount': todayMealCount, // Today's meal count (optimized structure)
          'survivalAlert': survivalAlert, // Active alert info (optimized structure)
          'lastPhoneActivity': data['blastPhoneActivity'] ?? data['lastPhoneActivity'], // General phone activity (fix field name)
          'lastActive': data['lastActive'], // Our specific app usage
          'elderlyName': data['elderlyName'],
          'location': data['location'], // Location data
        };
      }
      return null;
    } catch (e) {
      secureLog.error('Failed to get survival status', e);
      return null;
    }
  }

  /// Real-time survival monitoring stream
  Stream<Map<String, dynamic>> listenToSurvivalStatus(String connectionCode) async* {
    try {
      // First find the family document by connection code
      final query = await _firestore.collection('families')
          .where('connectionCode', isEqualTo: connectionCode)
          .limit(1)
          .get();
      
      if (query.docs.isEmpty) {
        secureLog.error('ERROR: Connection code does not exist');
        yield {};
        return;
      }
      
      final familyId = query.docs.first.id;
      secureLog.debug('Found family ID for connection code');
      
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
          
          yield {
            'lastMealTime': lastMealTime, // Last meal timestamp (optimized structure)
            'todayMealCount': todayMealCount, // Today's meal count (optimized structure)
            'survivalAlert': survivalAlert, // Alert details if triggered (optimized structure)
            'lastPhoneActivity': data['blastPhoneActivity'] ?? data['lastPhoneActivity'], // General phone activity (fix field name)
            'lastActive': data['lastActive'], // Our specific app usage
            'elderlyName': data['elderlyName'],
            'settings': data['settings'], // App settings
            'location': data['location'], // Location data
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
  Future<bool> clearSurvivalAlert(String connectionCode) async {
    try {
      // First find the family document by connection code
      final query = await _firestore.collection('families')
          .where('connectionCode', isEqualTo: connectionCode)
          .limit(1)
          .get();
      
      if (query.docs.isEmpty) {
        secureLog.error('ERROR: Connection code does not exist');
        return false;
      }
      
      final familyId = query.docs.first.id;
      
      await _firestore.collection('families').doc(familyId).update({
        'alerts.survival': null, // Clear survival alert (optimized structure)
        'alertsCleared.survival': FieldValue.serverTimestamp(),
        'alertsClearedBy.survival': 'Child App',
      });
      return true;
    } catch (e) {
      secureLog.error('Failed to clear survival alert', e);
      return false;
    }
  }


  /// Update app settings
  Future<bool> updateSettings(String connectionCode, Map<String, dynamic> settings) async {
    try {
      // First find the family document by connection code
      final query = await _firestore.collection('families')
          .where('connectionCode', isEqualTo: connectionCode)
          .limit(1)
          .get();
      
      if (query.docs.isEmpty) {
        secureLog.error('ERROR: Connection code does not exist');
        return false;
      }
      
      final familyId = query.docs.first.id;
      
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
  Future<Map<String, dynamic>> getStatistics(String connectionCode) async {
    try {
      await _ensureAuthenticated();
      
      // First find the family document by connection code
      final query = await _firestore.collection('families')
          .where('connectionCode', isEqualTo: connectionCode)
          .limit(1)
          .get();
      
      if (query.docs.isEmpty) {
        secureLog.error('ERROR: Connection code does not exist');
        return {};
      }
      
      final familyId = query.docs.first.id;
      
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
  Future<bool?> checkFamilyExists(String connectionCode) async {
    secureLog.debug('Checking if family exists for connection code');
    
    try {
      final result = await _executeWithRetry<bool>(
        () async {
          final query = await _firestore.collection('families')
              .where('connectionCode', isEqualTo: connectionCode)
              .limit(1)
              .get();
          
          final exists = query.docs.isNotEmpty;
          if (exists) {
            secureLog.info('Family found for connection code');
            // Additional validation: check if document has basic required fields
            final doc = query.docs.first;
            final data = doc.data();
            final hasRequiredFields = data.containsKey('elderlyName') || data.containsKey('createdAt');
            if (!hasRequiredFields) {
              secureLog.warning('Family document exists but missing required fields');
              return false; // Treat as deleted if document is corrupted
            }
          } else {
            secureLog.warning('No family found for connection code - may be deleted');
          }
          return exists;
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
  Stream<bool> listenToFamilyExistence(String connectionCode) async* {
    try {
      // First find the family document by connection code
      final query = await _firestore.collection('families')
          .where('connectionCode', isEqualTo: connectionCode)
          .limit(1)
          .get();
      
      if (query.docs.isEmpty) {
        secureLog.warning('Family document not found for connection code');
        yield false;
        return;
      }
      
      final familyId = query.docs.first.id;
      secureLog.debug('Monitoring family document existence');
      
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
        
        final currentExists = snapshot.exists;
        
        // Only yield changes if the existence state actually changed
        if (currentExists != lastKnownState) {
          secureLog.info('Family existence changed from $lastKnownState to $currentExists');
          lastKnownState = currentExists;
          yield currentExists;
          
          if (!currentExists) {
            secureLog.warning('Family document actually deleted');
          } else {
            secureLog.info('Family document restored/created');
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
    secureLog.info('ChildAppService disposed - all listeners cancelled');
  }
  
  /// Get connection status
  bool get isConnected => _isConnected;
  
  /// Get last successful operation time
  DateTime? get lastSuccessfulOperation => _lastSuccessfulOperation;

}