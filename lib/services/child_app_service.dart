import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChildAppService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Ensure authentication before any Firebase operations
  Future<void> _ensureAuthenticated() async {
    if (_auth.currentUser == null) {
      print('No authenticated user, signing in anonymously...');
      await _auth.signInAnonymously();
      print('Anonymous authentication successful: ${_auth.currentUser?.uid}');
    }
  }

  /// Validate and get family information using connection code
  Future<Map<String, dynamic>?> getFamilyInfo(String connectionCode) async {
    try {
      await _ensureAuthenticated();
      
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
        return null;
      }
    } catch (e) {
      print('ERROR: Failed to get family info: $e');
      print('Error type: ${e.runtimeType}');
      return null;
    }
  }

  /// Approve/reject family code (CRITICAL for elderly app to proceed)
  Future<bool> approveFamilyCode(String connectionCode, bool approved) async {
    try {
      await _ensureAuthenticated();
      
      print('🚨 CRITICAL: Attempting to approve connection code: $connectionCode with approved: $approved');
      print('Current user: ${_auth.currentUser?.uid}');
      
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
          'lastActivity': data['lastActivity'], // Last activity timestamp
          'survivalAlert': data['survivalAlert'], // Active alert info
          'foodAlert': data['foodAlert'], // Food alert info
          'isActive': data['isActive'], // Currently active status
          'elderlyName': data['elderlyName'],
          'lastFoodIntake': data['lastFoodIntake'], // Last food intake data
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
            'lastActivity': data['lastActivity'], // Timestamp of last activity
            'survivalAlert': data['survivalAlert'], // Alert details if triggered
            'foodAlert': data['foodAlert'], // Food alert details
            'isActive': data['isActive'], // Is elderly person active
            'elderlyName': data['elderlyName'],
            'settings': data['settings'], // App settings
            'lastFoodIntake': data['lastFoodIntake'], // Last food intake data
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

  /// Clear food alert after family acknowledges
  Future<bool> clearFoodAlert(String connectionCode) async {
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
        'foodAlert.isActive': false,
        'foodAlert.clearedAt': FieldValue.serverTimestamp(),
        'foodAlert.clearedBy': 'Child App',
      });
      return true;
    } catch (e) {
      print('Failed to clear food alert: $e');
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
  Future<bool> checkFamilyExists(String connectionCode) async {
    try {
      await _ensureAuthenticated();
      
      final query = await _firestore.collection('families')
          .where('connectionCode', isEqualTo: connectionCode)
          .limit(1)
          .get();
      
      return query.docs.isNotEmpty;
    } catch (e) {
      print('Error checking family exists: $e');
      return false;
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
        print('Family document not found for connection code: $connectionCode');
        yield false;
        return;
      }
      
      final familyId = query.docs.first.id;
      print('Monitoring family document existence for ID: $familyId');
      
      await for (final snapshot in _firestore
          .collection('families')
          .doc(familyId)
          .snapshots()) {
        yield snapshot.exists;
        if (!snapshot.exists) {
          print('Family document deleted: $familyId');
        }
      }
    } catch (e) {
      print('Error monitoring family existence: $e');
      yield false;
    }
  }

}