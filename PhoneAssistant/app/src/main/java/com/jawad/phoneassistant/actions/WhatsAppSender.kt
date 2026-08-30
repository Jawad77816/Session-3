package com.jawad.phoneassistant.actions

import android.content.Context
import com.jawad.phoneassistant.data.ScheduledTask
import com.jawad.phoneassistant.service.AutomationAccessibilityService
import com.jawad.phoneassistant.util.ContactResolver
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Sends a WhatsApp / WhatsApp Business message by opening the chat with the
 * text pre-filled and letting the AccessibilityService tap "Send".
 *
 * This relies on the Accessibility service being enabled, and on WhatsApp's
 * on-screen "Send" control — if WhatsApp changes that UI, the selector in
 * [AutomationAccessibilityService] may need updating.
 */
object WhatsAppSender {
    suspend fun send(context: Context, task: ScheduledTask): Result<Unit> = withContext(Dispatchers.IO) {
        val pkg = task.channel.packageName
            ?: return@withContext Result.failure(IllegalStateException("Not a WhatsApp channel"))

        val service = AutomationAccessibilityService.instance
            ?: return@withContext Result.failure(
                IllegalStateException("Accessibility not enabled — turn on “Phone Assistant — App Automation” in Accessibility settings")
            )

        val rawNumber = task.resolvedNumber
            ?: ContactResolver.resolveNumber(context, task.target)
            ?: return@withContext Result.failure(IllegalStateException("Couldn't find a number for \"${task.target}\""))
        val intl = ContactResolver.toInternational(rawNumber)

        val latch = CountDownLatch(1)
        val launched = service.enqueueWhatsApp(pkg, intl, task.message, latch)
        if (!launched) {
            return@withContext Result.failure(IllegalStateException("Couldn't open ${task.channel.displayName} (is it installed?)"))
        }

        val clicked = latch.await(15, TimeUnit.SECONDS)
        if (clicked) Result.success(Unit)
        else Result.failure(IllegalStateException("Opened the chat but couldn't tap Send in time (WhatsApp UI may have changed)"))
    }
}
