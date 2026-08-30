package com.jawad.phoneassistant

import android.Manifest
import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

class AssistantApp : Application() {

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_STATUS,
                getString(R.string.channel_status),
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply { description = "Results of your scheduled tasks" }
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    companion object {
        const val CHANNEL_STATUS = "task_status"

        /** Posts a small result notification; silently skips if not permitted. */
        fun notifyResult(context: Context, id: Int, title: String, text: String) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) return
            try {
                val n = NotificationCompat.Builder(context, CHANNEL_STATUS)
                    .setSmallIcon(R.drawable.ic_send)
                    .setContentTitle(title)
                    .setContentText(text)
                    .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                    .setAutoCancel(true)
                    .build()
                NotificationManagerCompat.from(context).notify(id, n)
            } catch (e: Exception) {
                // ignore — notification is best-effort feedback
            }
        }
    }
}
