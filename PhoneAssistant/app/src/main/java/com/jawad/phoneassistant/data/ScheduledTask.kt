package com.jawad.phoneassistant.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * The delivery channel an action targets.
 *
 * WHATSAPP / WHATSAPP_BUSINESS are driven through the AccessibilityService
 * (tap-simulation). SMS and EMAIL are sent directly through proper APIs.
 */
enum class TaskChannel(val displayName: String, val packageName: String?) {
    WHATSAPP("WhatsApp", "com.whatsapp"),
    WHATSAPP_BUSINESS("WhatsApp Business", "com.whatsapp.w4b"),
    SMS("SMS", null),
    EMAIL("Email", null);

    val isWhatsApp: Boolean get() = this == WHATSAPP || this == WHATSAPP_BUSINESS
}

enum class TaskStatus { SCHEDULED, RUNNING, DONE, FAILED, CANCELLED }

@Entity(tableName = "scheduled_tasks")
data class ScheduledTask(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,

    /** What kind of message to send. */
    val channel: TaskChannel,

    /** Raw target the user gave: a contact name, a phone number, or an email. */
    val target: String,

    /** Phone number resolved from [target] (for WhatsApp/SMS), if known. */
    val resolvedNumber: String? = null,

    /** Email subject (EMAIL channel only). */
    val subject: String? = null,

    /** The content to send. */
    val message: String,

    /** Absolute firing time as a UTC epoch-millis value. */
    val triggerAtMillis: Long,

    val status: TaskStatus = TaskStatus.SCHEDULED,

    val createdAtMillis: Long = System.currentTimeMillis(),

    /** Populated when status == FAILED. */
    val lastError: String? = null
)
