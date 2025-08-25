import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'firebase_service.dart';

/// ParentLocationService handles location collection and storage
/// for the elderly/parent app side
/// 
/// Features:
/// - Collects GPS location data with proper permissions
/// - Reverse geocoding for address resolution
/// - Automatic storage to Firebase
/// - Periodic location updates
/// - Battery-optimized location tracking
/// - Location permission handling
class ParentLocationService {
  Timer? _locationTimer;
  StreamSubscription<Position>? _positionStream;
  String? _currentConnectionCode;
  bool _isTracking = false;
  
  // Location settings
  static const Duration _updateInterval = Duration(minutes: 5);
  static const double _distanceFilter = 10.0; // meters
  
  /// Start location tracking for a family
  /// 
  /// [connectionCode] - Family connection code
  /// [updateInterval] - How often to update location (default: 5 minutes)
  /// [highAccuracy] - Use high accuracy GPS (default: false for battery)
  /// 
  /// Returns true if tracking started successfully
  Future<bool> startLocationTracking({
    required String connectionCode,
    Duration updateInterval = _updateInterval,
    bool highAccuracy = false,
  }) async {
    try {
      // Check if already tracking
      if (_isTracking) {
        print('Location tracking already active');
        return true;
      }
      
      // Check location permissions
      if (!await _checkLocationPermissions()) {
        print('Location permissions not granted');
        return false;
      }
      
      _currentConnectionCode = connectionCode;
      _isTracking = true;
      
      // Get initial location
      final initialLocation = await _getCurrentLocation(highAccuracy: highAccuracy);
      if (initialLocation != null) {
        await _storeLocationData(initialLocation);
      }
      
      // Start periodic location updates
      _startPeriodicUpdates(updateInterval, highAccuracy);
      
      print('Location tracking started for family: $connectionCode');
      return true;
    } catch (e) {
      print('Error starting location tracking: $e');
      _isTracking = false;
      return false;
    }
  }
  
  /// Stop location tracking
  void stopLocationTracking() {
    _locationTimer?.cancel();
    _positionStream?.cancel();
    _isTracking = false;
    _currentConnectionCode = null;
    print('Location tracking stopped');
  }
  
  /// Get current location and store it immediately
  /// 
  /// [connectionCode] - Family connection code
  /// [highAccuracy] - Use high accuracy GPS
  /// 
  /// Returns true if successful
  Future<bool> updateLocationNow({
    required String connectionCode,
    bool highAccuracy = true,
  }) async {
    try {
      if (!await _checkLocationPermissions()) {
        print('Location permissions not granted');
        return false;
      }
      
      final position = await _getCurrentLocation(highAccuracy: highAccuracy);
      if (position == null) {
        print('Could not get current location');
        return false;
      }
      
      _currentConnectionCode = connectionCode;
      return await _storeLocationData(position);
    } catch (e) {
      print('Error updating location: $e');
      return false;
    }
  }
  
  /// Check if location tracking is currently active
  bool get isTracking => _isTracking;
  
  /// Get current connection code being tracked
  String? get currentConnectionCode => _currentConnectionCode;
  
  // ==================== PRIVATE METHODS ====================
  
  /// Check and request location permissions
  Future<bool> _checkLocationPermissions() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Location permissions are denied');
          return false;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        print('Location permissions are permanently denied');
        return false;
      }
      
      return true;
    } catch (e) {
      print('Error checking location permissions: $e');
      return false;
    }
  }
  
  /// Get current GPS position
  Future<Position?> _getCurrentLocation({bool highAccuracy = false}) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: highAccuracy ? LocationAccuracy.high : LocationAccuracy.medium,
        forceAndroidLocationManager: false,
        timeLimit: const Duration(seconds: 30),
      );
      
      print('Got location: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      print('Error getting current location: $e');
      return null;
    }
  }
  
  /// Start periodic location updates
  void _startPeriodicUpdates(Duration interval, bool highAccuracy) {
    _locationTimer = Timer.periodic(interval, (timer) async {
      if (!_isTracking || _currentConnectionCode == null) {
        timer.cancel();
        return;
      }
      
      try {
        final position = await _getCurrentLocation(highAccuracy: highAccuracy);
        if (position != null) {
          await _storeLocationData(position);
        }
      } catch (e) {
        print('Error in periodic location update: $e');
      }
    });
  }
  
  /// Store location data with encryption
  Future<bool> _storeLocationData(Position position) async {
    if (_currentConnectionCode == null) {
      print('No connection code available for location storage');
      return false;
    }
    
    try {
      // Get address from coordinates (reverse geocoding)
      String? address;
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        
        if (placemarks.isNotEmpty) {
          final placemark = placemarks.first;
          address = [
            placemark.street,
            placemark.locality,
            placemark.administrativeArea,
          ].where((e) => e != null && e.isNotEmpty).join(', ');
        }
      } catch (e) {
        print('Error getting address from coordinates: $e');
        // Continue without address
      }
      
      // Store location data
      final success = await FirebaseService.storeLocation(
        connectionCode: _currentConnectionCode!,
        latitude: position.latitude,
        longitude: position.longitude,
        address: address,
        timestamp: DateTime.fromMillisecondsSinceEpoch(position.timestamp!.millisecondsSinceEpoch),
      );
      
      if (success) {
        print('Successfully stored location data');
      } else {
        print('Failed to store location data');
      }
      
      return success;
    } catch (e) {
      print('Error storing location data: $e');
      return false;
    }
  }
  
  /// Cleanup resources
  void dispose() {
    stopLocationTracking();
  }
}

/// Location tracking configuration
class LocationTrackingConfig {
  final Duration updateInterval;
  final bool highAccuracy;
  final double distanceFilter;
  final bool trackInBackground;
  
  const LocationTrackingConfig({
    this.updateInterval = const Duration(minutes: 5),
    this.highAccuracy = false,
    this.distanceFilter = 10.0,
    this.trackInBackground = true,
  });
  
  /// Battery optimized configuration
  static const LocationTrackingConfig batteryOptimized = LocationTrackingConfig(
    updateInterval: Duration(minutes: 10),
    highAccuracy: false,
    distanceFilter: 50.0,
    trackInBackground: true,
  );
  
  /// High accuracy configuration
  static const LocationTrackingConfig highAccuracyMode = LocationTrackingConfig(
    updateInterval: Duration(minutes: 2),
    highAccuracy: true,
    distanceFilter: 5.0,
    trackInBackground: true,
  );
  
  /// Balanced configuration (default)
  static const LocationTrackingConfig balanced = LocationTrackingConfig(
    updateInterval: Duration(minutes: 5),
    highAccuracy: false,
    distanceFilter: 10.0,
    trackInBackground: true,
  );
}