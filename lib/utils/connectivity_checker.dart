import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

enum ConnectivityStatus {
  connected,
  disconnected,
  unknown,
}

class ConnectivityChecker {
  static final ConnectivityChecker _instance = ConnectivityChecker._internal();
  factory ConnectivityChecker() => _instance;
  ConnectivityChecker._internal();

  ConnectivityStatus _status = ConnectivityStatus.unknown;
  final StreamController<ConnectivityStatus> _statusController =
      StreamController<ConnectivityStatus>.broadcast();
  
  Timer? _periodicChecker;
  bool _isChecking = false;

  ConnectivityStatus get status => _status;
  Stream<ConnectivityStatus> get statusStream => _statusController.stream;

  void initialize() {
    _startPeriodicCheck();
    // Initial check
    checkConnectivity();
  }

  void dispose() {
    _periodicChecker?.cancel();
    _statusController.close();
  }

  void _startPeriodicCheck() {
    _periodicChecker = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!_isChecking) {
        checkConnectivity();
      }
    });
  }

  /// Check connectivity by attempting to connect to Google's DNS
  Future<ConnectivityStatus> checkConnectivity() async {
    if (_isChecking) return _status;
    _isChecking = true;

    try {
      // Try to connect to Google's public DNS (reliable and fast)
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        _updateStatus(ConnectivityStatus.connected);
        return ConnectivityStatus.connected;
      }
    } on SocketException catch (e) {
      debugPrint('No internet connection: $e');
      _updateStatus(ConnectivityStatus.disconnected);
      return ConnectivityStatus.disconnected;
    } on TimeoutException catch (e) {
      debugPrint('Internet connection timeout: $e');
      _updateStatus(ConnectivityStatus.disconnected);
      return ConnectivityStatus.disconnected;
    } catch (e) {
      debugPrint('Connectivity check error: $e');
      _updateStatus(ConnectivityStatus.unknown);
      return ConnectivityStatus.unknown;
    } finally {
      _isChecking = false;
    }

    _updateStatus(ConnectivityStatus.disconnected);
    return ConnectivityStatus.disconnected;
  }

  /// Check if connected to internet with Firebase-specific test
  Future<bool> checkFirebaseConnectivity() async {
    try {
      // Try to resolve Firebase-related domains
      final firebaseResults = await Future.wait([
        InternetAddress.lookup('firebase.google.com'),
        InternetAddress.lookup('firestore.googleapis.com'),
      ]).timeout(const Duration(seconds: 8));

      final hasFirebaseAccess = firebaseResults.every(
        (result) => result.isNotEmpty && result[0].rawAddress.isNotEmpty,
      );

      if (hasFirebaseAccess) {
        _updateStatus(ConnectivityStatus.connected);
        return true;
      }
    } catch (e) {
      debugPrint('Firebase connectivity check failed: $e');
    }

    _updateStatus(ConnectivityStatus.disconnected);
    return false;
  }

  void _updateStatus(ConnectivityStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      _statusController.add(newStatus);
      debugPrint('Connectivity status changed to: $newStatus');
    }
  }

  /// Wait for internet connection with timeout
  Future<bool> waitForConnection({Duration timeout = const Duration(seconds: 30)}) async {
    if (_status == ConnectivityStatus.connected) {
      return true;
    }

    final completer = Completer<bool>();
    late StreamSubscription subscription;

    // Set up timeout
    final timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    });

    // Listen for connection
    subscription = statusStream.listen((status) {
      if (status == ConnectivityStatus.connected && !completer.isCompleted) {
        completer.complete(true);
      }
    });

    // Start checking if not already connected
    if (_status != ConnectivityStatus.connected) {
      checkConnectivity();
    }

    final result = await completer.future;
    
    // Cleanup
    timeoutTimer.cancel();
    subscription.cancel();
    
    return result;
  }

  /// Check if device has any network interface (WiFi, mobile data, etc.)
  Future<bool> hasNetworkInterface() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.any,
      );
      return interfaces.isNotEmpty;
    } catch (e) {
      debugPrint('Network interface check failed: $e');
      return false;
    }
  }
}