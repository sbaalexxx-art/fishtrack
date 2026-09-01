package com.example.fishtrack

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val METHOD_CHANNEL = "fluviai.notifications/native"
        private const val ALERT_CHANNEL_ID = "fluviai_alerts"
        private const val ALERT_CHANNEL_NAME = "FluviAI Alerts"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensureAlertChannel()

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "notificationState" -> result.success(notificationState())
                "showForegroundNotification" -> {
                    val title = call.argument<String>("title")?.trim().orEmpty()
                    val body = call.argument<String>("body")?.trim().orEmpty()
                    val id = call.argument<Int>("id") ?: (System.currentTimeMillis() and 0x7fffffff).toInt()
                    result.success(showForegroundNotification(id, title, body))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun ensureAlertChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            ALERT_CHANNEL_ID,
            ALERT_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Water, weather, Hydro and safety alerts"
            enableVibration(true)
            setShowBadge(true)
        }
        manager.createNotificationChannel(channel)
    }

    private fun notificationState(): Map<String, Any> {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val appEnabled = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            manager.areNotificationsEnabled()
        } else {
            true
        }
        val channelEnabled = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.getNotificationChannel(ALERT_CHANNEL_ID)?.importance != NotificationManager.IMPORTANCE_NONE
        } else {
            true
        }
        return mapOf(
            "appEnabled" to appEnabled,
            "channelEnabled" to channelEnabled,
            "deliveryAvailable" to (appEnabled && channelEnabled),
        )
    }

    private fun showForegroundNotification(id: Int, title: String, body: String): Boolean {
        val state = notificationState()
        if (state["deliveryAvailable"] != true) return false
        if (title.isEmpty() && body.isEmpty()) return false

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                id,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, ALERT_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setSmallIcon(R.drawable.ic_stat_fluviai)
            .setContentTitle(if (title.isEmpty()) "FluviAI" else title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            builder
                .setPriority(Notification.PRIORITY_HIGH)
                .setDefaults(Notification.DEFAULT_SOUND or Notification.DEFAULT_VIBRATE)
        }

        manager.notify(id, builder.build())
        return true
    }
}
