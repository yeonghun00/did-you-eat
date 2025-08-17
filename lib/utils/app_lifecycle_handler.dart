import 'package:flutter/widgets.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';

class AppLifecycleHandler extends WidgetsBindingObserver {
  static final AppLifecycleHandler _instance = AppLifecycleHandler._internal();
  factory AppLifecycleHandler() => _instance;
  AppLifecycleHandler._internal();

  AuthService? _authService;
  DateTime? _pausedAt;
  bool _isHandlingResume = false;

  AuthService get authService {
    _authService ??= AuthService();
    return _authService!;
  }

  void initialize() {
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.paused:
        _handleAppPause();
        break;
      case AppLifecycleState.resumed:
        _handleAppResume();
        break;
      case AppLifecycleState.detached:
        _handleAppDetached();
        break;
      case AppLifecycleState.inactive:
        // App is transitioning between states
        break;
      case AppLifecycleState.hidden:
        // App is hidden but still running
        break;
    }
  }

  void _handleAppPause() {
    _pausedAt = DateTime.now();
    print('App paused at: $_pausedAt');
  }

  Future<void> _handleAppResume() async {
    if (_isHandlingResume) return;
    _isHandlingResume = true;

    try {
      final now = DateTime.now();
      final pauseDuration = _pausedAt != null ? now.difference(_pausedAt!) : Duration.zero;
      
      print('App resumed after ${pauseDuration.inMinutes} minutes');

      // If app was paused for a significant time, just log it
      if (pauseDuration.inMinutes >= 5) {
        print('App was paused for a significant time: ${pauseDuration.inMinutes} minutes');
      }

      // Always check Firebase connection
      await _ensureFirebaseConnection();
      
    } catch (e) {
      print('Error handling app resume: $e');
    } finally {
      _isHandlingResume = false;
      _pausedAt = null;
    }
  }

  void _handleAppDetached() {
    print('App detached/terminated');
    _pausedAt = null;
  }


  /// Ensure Firebase connection is active
  Future<void> _ensureFirebaseConnection() async {
    try {
      // Only test connection if user is authenticated
      if (FirebaseAuth.instance.currentUser == null) {
        print('Skipping Firebase connection test - user not authenticated');
        return;
      }
      
      // Enable Firestore network if it was disabled
      await FirebaseFirestore.instance.enableNetwork();
      print('Firebase network enabled');
      
      // Test connection with a lightweight operation (only if authenticated)
      await FirebaseFirestore.instance
          .collection('_test')
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 5));
      
      print('Firebase connection verified');
    } catch (e) {
      print('Firebase connection issue: $e');
      // Don't throw here, let the app continue and retry operations as needed
    }
  }

  /// Get app pause duration for external use
  Duration? get pauseDuration {
    if (_pausedAt == null) return null;
    return DateTime.now().difference(_pausedAt!);
  }

  /// Check if app was recently resumed from a long pause
  bool get wasLongPause {
    final duration = pauseDuration;
    return duration != null && duration.inMinutes >= 5;
  }
}