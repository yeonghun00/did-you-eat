import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

/// LocationService handles location storage and retrieval
/// 
/// Features:
/// - Stores location data in Firebase
/// - Provides real-time location streaming
/// - Simple location data management
class LocationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Store location data in Firebase
  /// 
  /// [familyId] - The family document ID in Firestore
  /// [latitude] - Location latitude
  /// [longitude] - Location longitude  
  /// [address] - Optional address string
  /// [timestamp] - Optional timestamp (defaults to now)
  /// 
  /// Returns true if successful, false otherwise
  Future<bool> storeLocation({
    required String familyId,
    required double latitude,
    required double longitude,
    String? address,
    DateTime? timestamp,
  }) async {
    try {
      timestamp ??= DateTime.now();
      
      // Create location data structure
      final locationData = {
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp.toIso8601String(),
        if (address != null) 'address': address,
      };
      
      // Store in Firebase
      await _firestore.collection('families').doc(familyId).update({
        'location': locationData,
        'lastLocationUpdate': FieldValue.serverTimestamp(),
      });
      
      print('Successfully stored location for family: $familyId');
      return true;
    } catch (e) {
      print('Error storing location: $e');
      return false;
    }
  }

  /// Store location data in Firebase
  /// 
  /// [familyId] - The family document ID in Firestore
  /// [locationData] - Location data map
  /// 
  /// Returns true if successful, false otherwise
  Future<bool> storeLocationData({
    required String familyId,
    required Map<String, dynamic> locationData,
  }) async {
    try {
      await _firestore.collection('families').doc(familyId).update({
        'location': locationData,
        'lastLocationUpdate': FieldValue.serverTimestamp(),
      });
      
      print('Successfully stored location data for family: $familyId');
      return true;
    } catch (e) {
      print('Error storing location data: $e');
      return false;
    }
  }

  /// Retrieve location data from Firebase
  /// 
  /// [familyId] - The family document ID in Firestore
  /// 
  /// Returns location data or null if not found/error
  Future<Map<String, dynamic>?> getLocation({
    required String familyId,
  }) async {
    try {
      final doc = await _firestore.collection('families').doc(familyId).get();
      
      if (!doc.exists) {
        print('Family document not found: $familyId');
        return null;
      }
      
      final data = doc.data()!;
      final locationData = data['location'];
      
      if (locationData == null) {
        print('No location data found for family: $familyId');
        return null;
      }
      
      if (locationData is Map<String, dynamic>) {
        return locationData;
      } else {
        print('Invalid location data format: ${locationData.runtimeType}');
        return null;
      }
    } catch (e) {
      print('Error retrieving location data: $e');
      return null;
    }
  }

  /// Get real-time stream of location updates
  /// 
  /// [familyId] - The family document ID in Firestore
  /// 
  /// Returns stream of location data
  Stream<Map<String, dynamic>?> listenToLocationUpdates({
    required String familyId,
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
        final locationData = data['location'];
        
        if (locationData == null) {
          yield null;
          continue;
        }
        
        if (locationData is Map<String, dynamic>) {
          yield locationData;
        } else {
          print('Invalid location data format in stream: ${locationData.runtimeType}');
          yield null;
        }
      }
    } catch (e) {
      print('Error in location stream: $e');
      yield null;
    }
  }

  /// Check if location data is valid
  /// 
  /// [locationData] - Location data to check
  /// 
  /// Returns true if data is valid
  bool isLocationValid(dynamic locationData) {
    if (locationData is Map<String, dynamic>) {
      return locationData.containsKey('latitude') && locationData.containsKey('longitude');
    }
    return false;
  }
}