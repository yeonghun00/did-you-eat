import 'dart:async';
import 'dart:isolate';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'session_manager.dart';
import 'auth_service.dart';
import 'child_app_service.dart';

/// Background service to maintain connection when app is backgrounded/terminated
class BackgroundService {
  static const String _sessionKeepAliveTask = 'session_keep_alive';
  static const String _authRefreshTask = 'auth_refresh';
  static const String _connectionCheckTask = 'connection_check';

  /// Initialize background service
  static Future<void> initialize() async {
    try {
      print('🔧 Initializing BackgroundService...');
      
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: false, // Set to false for production
      );

      // Register periodic tasks
      await _registerTasks();

      print('✅ BackgroundService initialized');
    } catch (e) {
      print('❌ BackgroundService initialization failed: $e');
    }
  }

  /// Register background tasks
  static Future<void> _registerTasks() async {
    try {
      // Session keep-alive task (every 5 minutes)
      await Workmanager().registerPeriodicTask(
        _sessionKeepAliveTask,
        _sessionKeepAliveTask,
        frequency: const Duration(minutes: 15), // Minimum iOS allows
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
      );

      // Auth refresh task (every 30 minutes)
      await Workmanager().registerPeriodicTask(
        _authRefreshTask,
        _authRefreshTask,
        frequency: const Duration(minutes: 30),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
      );

      // Connection check task (every 10 minutes)
      await Workmanager().registerPeriodicTask(
        _connectionCheckTask,
        _connectionCheckTask,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
      );

      print('✅ Background tasks registered');
    } catch (e) {
      print('❌ Failed to register background tasks: $e');
    }
  }

  /// Cancel all background tasks
  static Future<void> cancelAllTasks() async {
    try {
      await Workmanager().cancelAll();
      print('✅ All background tasks cancelled');
    } catch (e) {
      print('❌ Failed to cancel background tasks: $e');
    }
  }

  /// Cancel specific task
  static Future<void> cancelTask(String taskName) async {
    try {
      await Workmanager().cancelByUniqueName(taskName);
      print('✅ Task cancelled: $taskName');
    } catch (e) {
      print('❌ Failed to cancel task $taskName: $e');
    }
  }
}

/// Background task callback dispatcher
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      print('🔄 Background task started: $task');
      
      // Initialize Firebase for background task
      await _initializeFirebaseForBackground();

      switch (task) {
        case BackgroundService._sessionKeepAliveTask:
          return await _handleSessionKeepAlive();
        case BackgroundService._authRefreshTask:
          return await _handleAuthRefresh();
        case BackgroundService._connectionCheckTask:
          return await _handleConnectionCheck();
        default:
          print('⚠️ Unknown background task: $task');
          return false;
      }
    } catch (e) {
      print('❌ Background task failed: $task - $e');
      return false;
    }
  });
}

/// Initialize Firebase for background context
Future<void> _initializeFirebaseForBackground() async {
  try {
    if (Firebase.apps.isEmpty) {
      // Initialize Firebase with default options
      // Note: You'll need to provide Firebase options here
      // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
  } catch (e) {
    print('❌ Background Firebase initialization failed: $e');
  }
}

/// Handle session keep-alive task
Future<bool> _handleSessionKeepAlive() async {
  try {
    print('💓 Background session keep-alive');
    
    final sessionManager = SessionManager();
    await sessionManager.initialize();
    
    if (!sessionManager.hasValidSession) {
      print('⚠️ No valid session in background');
      return true; // Not an error condition
    }

    // Update last active timestamp
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_active_timestamp', DateTime.now().millisecondsSinceEpoch);
    
    // Validate session if family code exists
    if (sessionManager.currentFamilyCode != null) {
      final childService = ChildAppService();
      final familyExists = await childService.checkFamilyExists(
        sessionManager.currentFamilyCode!,
      );
      
      if (familyExists == false) {
        print('❌ Family deleted, clearing session in background');
        await sessionManager.clearSession();
      }
    }

    print('✅ Background session keep-alive completed');
    return true;
  } catch (e) {
    print('❌ Background session keep-alive failed: $e');
    return false;
  }
}

/// Handle auth refresh task
Future<bool> _handleAuthRefresh() async {
  try {
    print('🔄 Background auth refresh');
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('⚠️ No user for background auth refresh');
      return true;
    }

    // Refresh auth token
    await user.getIdToken(true);
    
    // Check if token is still valid
    await user.reload();
    
    print('✅ Background auth refresh completed');
    return true;
  } catch (e) {
    print('❌ Background auth refresh failed: $e');
    return false;
  }
}

/// Handle connection check task
Future<bool> _handleConnectionCheck() async {
  try {
    print('🔍 Background connection check');
    
    // Test Firebase connection
    await FirebaseFirestore.instance
        .collection('_test')
        .limit(1)
        .get()
        .timeout(const Duration(seconds: 10));

    print('✅ Background connection check completed');
    return true;
  } catch (e) {
    print('❌ Background connection check failed: $e');
    return false;
  }
}