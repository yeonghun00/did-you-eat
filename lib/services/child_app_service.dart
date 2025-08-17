import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart';

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
      return await _authService.isAuthenticationValid();
    } catch (e) {
      print('Authentication failed in ChildAppService: $e');
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
          print('Authentication failed for $operationName, attempt ${attempt + 1}');
          throw Exception('Authentication failed');
        }

        // Execute operation with timeout
        return await operation().timeout(timeout);
      } on SocketException catch (e) {
        print('Network error in $operationName (attempt ${attempt + 1}): $e');
        if (attempt == maxRetries - 1) rethrow;
        await Future.delayed(Duration(seconds: math.pow(2, attempt).toInt()));
      } on TimeoutException catch (e) {
        print('Timeout in $operationName (attempt ${attempt + 1}): $e');
        if (attempt == maxRetries - 1) rethrow;
        await Future.delayed(Duration(seconds: math.pow(2, attempt).toInt()));
      } on FirebaseException catch (e) {
        print('Firebase error in $operationName (attempt ${attempt + 1}): ${e.code} - ${e.message}');
        // Don't retry permission errors or invalid data errors
        if (e.code == 'permission-denied' || e.code == 'invalid-argument') {
          rethrow;
        }
        if (attempt == maxRetries - 1) rethrow;
        await Future.delayed(Duration(seconds: math.pow(2, attempt).toInt()));
      } catch (e) {
        print('Unexpected error in $operationName (attempt ${attempt + 1}): $e');
        if (attempt == maxRetries - 1) rethrow;
        await Future.delayed(Duration(seconds: math.pow(2, attempt).toInt()));
      }
    }
    return null;
  }

  /// Validate and get family information using connection code
  Future<Map<String, dynamic>?> getFamilyInfo(String connectionCode) async {
    return await _executeWithRetry<Map<String, dynamic>>(
      () async {
        print('Getting family info for connection code: $connectionCode');
        
        // Query by connectionCode instead of document ID
        final query = await _firestore.collection('families')
            .where('connectionCode', isEqualTo: connectionCode)
            .limit(1)
            .get();
        
        if (query.docs.isNotEmpty) {
          final doc = query.docs.first;
          final data = doc.data();
          data['familyId'] = doc.id; // Add document ID for reference
          print('Family info found: familyId=${doc.id}, elderlyName=${data['elderlyName']}, approved=${data['approved']}');
          return data;
        } else {
          print('Connection code $connectionCode does not exist');
          return <String, dynamic>{};
        }
      },
      operationName: 'getFamilyInfo',
    );
  }

  /// Approve/reject family code (CRITICAL for elderly app to proceed)
  Future<bool> approveFamilyCode(String connectionCode, bool approved) async {
    try {
      await _ensureAuthenticated();
      
      print('🚨 CRITICAL: Attempting to approve connection code: $connectionCode with approved: $approved');
      print('Current user: ${_authService.currentUser?.uid}');
      
      // Find the family document by connection code
      final query = await _firestore.collection('families')
          .where('connectionCode', isEqualTo: connectionCode)
          .limit(1)
          .get();
      
      if (query.docs.isEmpty) {
        print('❌ ERROR: Connection code $connectionCode does not exist');
        return false;
      }
      
      final doc = query.docs.first;
      final familyId = doc.id;
      final currentData = doc.data();
      
      print('Found family ID: $familyId for connection code: $connectionCode');
      print('Current approval status: ${currentData['approved']}');
      
      // Update the approval status using the correct family ID
      await _firestore.collection('families').doc(familyId).update({
        'approved': approved,
        'approvedAt': FieldValue.serverTimestamp(),
        'approvedBy': 'Child App',
      });
      
      print('✅ SUCCESS: Family ID $familyId (connection code $connectionCode) updated with approved: $approved');
      
      // Verify the update worked
      final updatedDoc = await _firestore.collection('families').doc(familyId).get();
      final updatedData = updatedDoc.data()!;
      print('✅ VERIFICATION: approved field is now: ${updatedData['approved']}');
      
      return true;
    } catch (e) {
      print('❌ ERROR: Failed to approve family code: $e');
      print('Error type: ${e.runtimeType}');
      print('Error details: ${e.toString()}');
      return false;
    }
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
        print('❌ ERROR: Connection code $connectionCode does not exist');
        return [];
      }
      
      final familyId = query.docs.first.id;
      print('Found family ID: $familyId for connection code: $connectionCode');
      
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
      print('Failed to get recordings: $e');
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
      print('❌ ERROR: Connection code $connectionCode does not exist');
      yield [];
      return;
    }
    
    final familyId = query.docs.first.id;
    print('Found family ID: $familyId for connection code: $connectionCode');
    
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
        print('❌ ERROR: Connection code $connectionCode does not exist');
        return null;
      }
      
      final familyId = query.docs.first.id;
      final doc = await _firestore.collection('families').doc(familyId).get();

      if (doc.exists) {
        final data = doc.data()!;
        return {
          'lastMealTime': data['lastMealTime'], // Last meal timestamp (cleaned structure)
          'todayMealCount': data['todayMealCount'], // Today's meal count
          'survivalAlert': data['survivalAlert'], // Active alert info
          'lastPhoneActivity': data['lastPhoneActivity'], // General phone activity (any app, calls, etc.)
          'lastActive': data['lastActive'], // Our specific app usage
          'elderlyName': data['elderlyName'],
          'location': data['location'], // Location data
        };
      }
      return null;
    } catch (e) {
      print('Failed to get survival status: $e');
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
        print('❌ ERROR: Connection code $connectionCode does not exist');
        yield {};
        return;
      }
      
      final familyId = query.docs.first.id;
      print('Found family ID: $familyId for connection code: $connectionCode');
      
      await for (final snapshot in _firestore
          .collection('families')
          .doc(familyId)
          .snapshots()) {
        if (snapshot.exists) {
          final data = snapshot.data()!;
          yield {
            'lastMealTime': data['lastMealTime'], // Last meal timestamp (cleaned structure)
            'todayMealCount': data['todayMealCount'], // Today's meal count
            'survivalAlert': data['survivalAlert'], // Alert details if triggered
            'lastPhoneActivity': data['lastPhoneActivity'], // General phone activity (any app, calls, etc.)
            'lastActive': data['lastActive'], // Our specific app usage
            'elderlyName': data['elderlyName'],
            'settings': data['settings'], // App settings
            'location': data['location'], // Location data
          };
        } else {
          print('Family document deleted: $familyId');
          yield {};
        }
      }
    } catch (e) {
      print('Error in listenToSurvivalStatus: $e');
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
        print('❌ ERROR: Connection code $connectionCode does not exist');
        return false;
      }
      
      final familyId = query.docs.first.id;
      
      await _firestore.collection('families').doc(familyId).update({
        'survivalAlert.isActive': false,
        'survivalAlert.clearedAt': FieldValue.serverTimestamp(),
        'survivalAlert.clearedBy': 'Child App',
      });
      return true;
    } catch (e) {
      print('Failed to clear survival alert: $e');
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
        print('❌ ERROR: Connection code $connectionCode does not exist');
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
      print('Failed to update settings: $e');
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
        print('❌ ERROR: Connection code $connectionCode does not exist');
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
      print('Failed to get statistics: $e');
      return {};
    }
  }

  /// Check if family document still exists (for account deletion detection)
  /// Returns null if network error, true/false if successful check
  Future<bool?> checkFamilyExists(String connectionCode) async {
    print('🔍 Checking if family exists for code: $connectionCode');
    
    final result = await _executeWithRetry<bool>(
      () async {
        final query = await _firestore.collection('families')
            .where('connectionCode', isEqualTo: connectionCode)
            .limit(1)
            .get();
        
        final exists = query.docs.isNotEmpty;
        print('📊 Family exists check result: $exists');
        return exists;
      },
      operationName: 'checkFamilyExists',
    );
    
    if (result == null) {
      print('⚠️ checkFamilyExists failed due to network/connection issues');
    }
    
    return result; // Return null for network errors, true/false for actual results
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
        print('Family document not found for connection code: $connectionCode');
        yield false;
        return;
      }
      
      final familyId = query.docs.first.id;
      print('Monitoring family document existence for ID: $familyId');
      
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
          print('📡 Metadata change detected - from cache: ${snapshot.metadata.isFromCache}, pending writes: ${snapshot.metadata.hasPendingWrites}');
          // Don't yield false for network/cache issues - keep last known state
          continue;
        }
        
        final currentExists = snapshot.exists;
        
        // Only yield changes if the existence state actually changed
        if (currentExists != lastKnownState) {
          print('📊 Family existence changed from $lastKnownState to $currentExists');
          lastKnownState = currentExists;
          yield currentExists;
          
          if (!currentExists) {
            print('❌ Family document actually deleted: $familyId');
          } else {
            print('✅ Family document restored/created: $familyId');
          }
        } else {
          print('📡 No change in family existence state: $currentExists');
        }
      }
    } catch (e) {
      print('❌ Error monitoring family existence: $e');
      // Don't yield false on errors - this could be network issues
      print('⚠️ Network error in family monitoring - not yielding false to prevent incorrect account deletion');
    }
  }
  
  /// Clean up all active listeners
  void dispose() {
    for (final subscription in _activeListeners.values) {
      subscription.cancel();
    }
    _activeListeners.clear();
    print('✅ ChildAppService disposed - all listeners cancelled');
  }
  
  /// Get connection status
  bool get isConnected => _isConnected;
  
  /// Get last successful operation time
  DateTime? get lastSuccessfulOperation => _lastSuccessfulOperation;

}