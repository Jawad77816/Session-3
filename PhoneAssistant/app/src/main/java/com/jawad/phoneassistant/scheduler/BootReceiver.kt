package com.jawad.phoneassistant.scheduler

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.jawad.phoneassistant.data.TaskRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/** Re-arms all pending alarms after a reboot or an app update. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) return

        val pending = goAsync()
        val appContext = context.applicationContext
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val repo = TaskRepository(appContext)
                repo.getPending().forEach { task ->
                    AlarmScheduler.schedule(appContext, task)
                }
            } finally {
                pending.finish()
            }
        }
    }
}
