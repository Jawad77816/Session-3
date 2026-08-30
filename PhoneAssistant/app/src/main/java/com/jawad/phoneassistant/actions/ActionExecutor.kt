package com.jawad.phoneassistant.actions

import android.content.Context
import com.jawad.phoneassistant.data.ScheduledTask
import com.jawad.phoneassistant.data.TaskChannel

/** Dispatches a task to the right sender based on its channel. */
object ActionExecutor {
    suspend fun execute(context: Context, task: ScheduledTask): Result<Unit> = when (task.channel) {
        TaskChannel.SMS -> SmsSender.send(context, task)
        TaskChannel.EMAIL -> EmailSender.send(context, task)
        TaskChannel.WHATSAPP, TaskChannel.WHATSAPP_BUSINESS -> WhatsAppSender.send(context, task)
    }
}
