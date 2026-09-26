package com.example.melodify

import com.ryanheise.audioservice.AudioServiceActivity
import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var notificationChannel: MethodChannel? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        notificationChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.example.melodify/notifications")
        notificationChannel?.setMethodCallHandler { call, result ->
            val channelId = "com.example.melodify.playback"
            when (call.method) {
                "isChannelBlocked" -> {
                    val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                    val blocked = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        manager.getNotificationChannel(channelId)?.importance == NotificationManager.IMPORTANCE_NONE
                    } else false
                    result.success(blocked)
                }
                "openChannelSettings" -> {
                    try {
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                .putExtra(Settings.EXTRA_CHANNEL_ID, channelId)
                        } else {
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        }
                        startActivity(intent)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("settings_unavailable", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        notificationChannel?.setMethodCallHandler(null)
        notificationChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
