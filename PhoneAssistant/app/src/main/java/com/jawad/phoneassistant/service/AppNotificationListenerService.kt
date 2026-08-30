package com.jawad.phoneassistant.service

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.util.concurrent.ConcurrentLinkedDeque

/**
 * Reads notifications from ALL apps (present and future). Kept intentionally
 * lightweight: a rolling in-memory buffer of the most recent notifications,
 * which the app can surface. Nothing is uploaded anywhere.
 */
class AppNotificationListenerService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return
        val extras = sbn.notification?.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
        if (title.isBlank() && text.isBlank()) return

        recent.addFirst(NotifItem(sbn.packageName, title, text, System.currentTimeMillis()))
        while (recent.size > MAX) recent.pollLast()
    }

    data class NotifItem(val pkg: String, val title: String, val text: String, val time: Long)

    companion object {
        private const val MAX = 50
        val recent = ConcurrentLinkedDeque<NotifItem>()
    }
}
