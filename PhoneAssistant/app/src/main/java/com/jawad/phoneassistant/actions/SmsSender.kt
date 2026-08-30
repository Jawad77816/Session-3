package com.jawad.phoneassistant.actions

import android.content.Context
import android.os.Build
import android.telephony.SmsManager
import com.jawad.phoneassistant.data.ScheduledTask
import com.jawad.phoneassistant.util.ContactResolver

/** Sends an SMS directly and reliably via the platform SmsManager. */
object SmsSender {
    fun send(context: Context, task: ScheduledTask): Result<Unit> {
        val number = task.resolvedNumber
            ?: ContactResolver.resolveNumber(context, task.target)
            ?: return Result.failure(IllegalStateException("Couldn't find a number for \"${task.target}\""))
        return try {
            @Suppress("DEPRECATION")
            val sms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                context.getSystemService(SmsManager::class.java)
            else SmsManager.getDefault()

            val parts = sms.divideMessage(task.message)
            if (parts.size > 1) {
                sms.sendMultipartTextMessage(number, null, parts, null, null)
            } else {
                sms.sendTextMessage(number, null, task.message, null, null)
            }
            Result.success(Unit)
        } catch (e: SecurityException) {
            Result.failure(IllegalStateException("SMS permission not granted"))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
