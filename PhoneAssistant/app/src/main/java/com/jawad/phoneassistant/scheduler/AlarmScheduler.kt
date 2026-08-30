package com.jawad.phoneassistant.scheduler

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.jawad.phoneassistant.data.ScheduledTask

/** Wraps AlarmManager to fire a task at its exact scheduled moment. */
object AlarmScheduler {

    const val EXTRA_TASK_ID = "task_id"

    fun canScheduleExact(context: Context): Boolean {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) am.canScheduleExactAlarms() else true
    }

    fun schedule(context: Context, task: ScheduledTask) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = pendingIntent(context, task.id)
        val fireAt = maxOf(task.triggerAtMillis, System.currentTimeMillis() + 1_000)

        // Exact + allowed while idle so Doze doesn't delay a scheduled message.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
            // Fall back to a (possibly delayed) inexact alarm if the user hasn't
            // granted the exact-alarm permission yet.
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, pi)
        } else {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, pi)
        }
    }

    fun cancel(context: Context, taskId: Long) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(pendingIntent(context, taskId))
    }

    private fun pendingIntent(context: Context, taskId: Long): PendingIntent {
        val intent = Intent(context, TaskAlarmReceiver::class.java).apply {
            putExtra(EXTRA_TASK_ID, taskId)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(context, taskId.toInt(), intent, flags)
    }
}
