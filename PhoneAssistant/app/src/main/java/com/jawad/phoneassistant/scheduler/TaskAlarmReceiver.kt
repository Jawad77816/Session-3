package com.jawad.phoneassistant.scheduler

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.content.ContextCompat

/**
 * Fires when a task's exact alarm goes off. Hands the task id to the
 * foreground ExecutionService, which is allowed to start from the background
 * because it was triggered by an exact alarm.
 */
class TaskAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val taskId = intent.getLongExtra(AlarmScheduler.EXTRA_TASK_ID, -1L)
        if (taskId <= 0) return

        val svc = Intent(context, ExecutionService::class.java).apply {
            putExtra(AlarmScheduler.EXTRA_TASK_ID, taskId)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ContextCompat.startForegroundService(context, svc)
        } else {
            context.startService(svc)
        }
    }
}
