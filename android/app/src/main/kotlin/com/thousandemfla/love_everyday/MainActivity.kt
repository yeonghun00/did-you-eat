package com.thousandemfla.love_everyday

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        GeneratedPluginRegistrant.registerWith(flutterEngine)
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(NotificationManager::class.java)

            // Meal notifications channel
            val mealChannel = NotificationChannel(
                "meal_notifications",
                "식사 알림",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "식사 기록 알림"
                enableLights(true)
                enableVibration(true)
            }

            // Meal alerts channel (for pattern warnings)
            val mealAlertsChannel = NotificationChannel(
                "meal_alerts",
                "식사 패턴 경고",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "식사 패턴 이상 알림"
                enableLights(true)
                enableVibration(true)
            }

            // Emergency alerts channel (for survival signals)
            val emergencyChannel = NotificationChannel(
                "emergency_alerts",
                "응급 알림",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "생존 신호 응급 알림"
                enableLights(true)
                enableVibration(true)
                setSound(android.provider.Settings.System.DEFAULT_NOTIFICATION_URI, null)
            }

            // Create channels
            notificationManager.createNotificationChannel(mealChannel)
            notificationManager.createNotificationChannel(mealAlertsChannel)
            notificationManager.createNotificationChannel(emergencyChannel)
        }
    }
}
