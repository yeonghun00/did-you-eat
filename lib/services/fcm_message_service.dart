import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import '../constants/colors.dart';

class FCMMessageService {
  static final FlutterLocalNotificationsPlugin _localNotifications = 
      FlutterLocalNotificationsPlugin();
  
  /// Initialize FCM message service
  static Future<void> initialize() async {
    // Initialize local notifications
    await _initializeLocalNotifications();
    
    // Set up FCM message handlers
    await _setupMessageHandlers();
    
    print('✅ FCM Message Service initialized');
  }

  /// Initialize local notifications plugin
  static Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );
    
    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }

  /// Set up FCM message handlers
  static Future<void> _setupMessageHandlers() async {
    // Handle messages when app is in foreground
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    
    // Handle messages when app is in background or terminated
    FirebaseMessaging.onBackgroundMessage(_backgroundMessageHandler);
    
    // Handle notification taps when app is terminated
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleMessageTap(initialMessage);
    }
    
    // Handle notification taps when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);
  }

  /// Handle foreground messages
  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    print('📱 Received foreground message:');
    print('  Title: ${message.notification?.title}');
    print('  Body: ${message.notification?.body}');
    print('  Data: ${message.data}');
    
    // Show local notification for foreground messages
    await _showLocalNotification(message);
    
    // Handle specific message types
    _handleMessageByType(message);
  }

  /// Handle message by type
  static void _handleMessageByType(RemoteMessage message) {
    final type = message.data['type'];
    
    switch (type) {
      case 'meal_recorded':
        _handleMealNotification(message.data);
        break;
      case 'survival_alert':
        _handleSurvivalAlert(message.data);
        break;
      case 'safety_status_critical':
        _handleSafetyStatusCritical(message.data);
        break;
      case 'food_alert':
        _handleFoodAlert(message.data);
        break;
      default:
        print('⚠️ Unknown message type: $type');
    }
  }

  /// Handle meal recorded notification
  static void _handleMealNotification(Map<String, dynamic> data) {
    final elderlyName = data['elderly_name'] ?? '부모님';
    final mealNumber = data['meal_number'] ?? '1';
    final timeDisplay = data['time_display'] ?? '';
    
    print('🍽️ Meal notification: $elderlyName - $mealNumber번째 식사 ($timeDisplay)');
    
    // TODO: Update UI, show in-app notification, etc.
  }

  /// Handle survival alert notification
  static void _handleSurvivalAlert(Map<String, dynamic> data) {
    final elderlyName = data['elderly_name'] ?? '부모님';
    final hoursInactive = data['hours_inactive'] ?? '12';
    
    print('🚨 Survival alert: $elderlyName - ${hoursInactive}시간 비활성');
    
    // TODO: Show urgent UI alert, sound alarm, etc.
  }

  /// Handle safety status critical notification
  static void _handleSafetyStatusCritical(Map<String, dynamic> data) {
    final elderlyName = data['elderly_name'] ?? '부모님';
    final hoursInactive = data['hours_inactive'] ?? '12';
    final alertHours = data['alert_hours'] ?? '12';
    final safetyLevel = data['safety_level'] ?? 'critical';
    
    print('🚨 Safety status critical: $elderlyName - ${hoursInactive}시간 비활성 (설정: ${alertHours}시간)');
    
    // TODO: Show critical safety UI, vibrate phone, play alarm sound
    // TODO: Option to call emergency contacts, acknowledge safety
  }

  /// Handle food alert notification
  static void _handleFoodAlert(Map<String, dynamic> data) {
    final elderlyName = data['elderly_name'] ?? '부모님';
    final hoursWithoutFood = data['hours_without_food'] ?? '8';
    
    print('⚠️ Food alert: $elderlyName - ${hoursWithoutFood}시간 식사 없음');
    
    // TODO: Show warning UI, suggest contacting parent, etc.
  }

  /// Show local notification
  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final type = message.data['type'];
    String channelId = 'meal_notifications'; // default
    
    // Set channel based on message type
    switch (type) {
      case 'meal_recorded':
        channelId = 'meal_notifications';
        break;
      case 'survival_alert':
        channelId = 'emergency_alerts';
        break;
      case 'safety_status_critical':
        channelId = 'safety_alerts';
        break;
      case 'food_alert':
        channelId = 'meal_alerts';
        break;
    }
    
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channelId,
      _getChannelName(channelId),
      channelDescription: _getChannelDescription(channelId),
      importance: _getImportance(type),
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
      icon: '@mipmap/ic_launcher',
    );
    
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      message.notification?.title ?? '알림',
      message.notification?.body ?? '',
      details,
      payload: message.data.toString(),
    );
  }

  /// Handle notification tap
  static void _onNotificationTapped(NotificationResponse response) {
    print('📱 Notification tapped: ${response.payload}');
    // TODO: Navigate to relevant screen based on notification type
  }

  /// Handle message tap (from system notification)
  static void _handleMessageTap(RemoteMessage message) {
    print('📱 Message opened app: ${message.data}');
    // TODO: Navigate to relevant screen based on message type
  }

  /// Get channel name by ID
  static String _getChannelName(String channelId) {
    switch (channelId) {
      case 'meal_notifications':
        return '식사 알림';
      case 'meal_alerts':
        return '식사 패턴 경고';
      case 'emergency_alerts':
        return '응급 알림';
      case 'safety_alerts':
        return '안전 상태 알림';
      default:
        return '알림';
    }
  }

  /// Get channel description by ID
  static String _getChannelDescription(String channelId) {
    switch (channelId) {
      case 'meal_notifications':
        return '식사 기록 알림';
      case 'meal_alerts':
        return '식사 패턴 이상 알림';
      case 'emergency_alerts':
        return '생존 신호 응급 알림';
      case 'safety_alerts':
        return '부모님 안전 상태 알림';
      default:
        return '일반 알림';
    }
  }

  /// Get importance based on message type
  static Importance _getImportance(String? type) {
    switch (type) {
      case 'survival_alert':
      case 'safety_status_critical':
        return Importance.max;
      case 'food_alert':
        return Importance.high;
      case 'meal_recorded':
      default:
        return Importance.defaultImportance;
    }
  }
}

/// Background message handler (top-level function required)
@pragma('vm:entry-point')
Future<void> _backgroundMessageHandler(RemoteMessage message) async {
  print('📱 Background message received:');
  print('  Title: ${message.notification?.title}');
  print('  Body: ${message.notification?.body}');
  print('  Data: ${message.data}');
  
  // Background messages are automatically displayed by the system
  // Just log and handle any specific logic needed
}