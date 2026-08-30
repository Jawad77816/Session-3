package com.jawad.phoneassistant.scheduler

import android.app.Notification
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import com.jawad.phoneassistant.AssistantApp
import com.jawad.phoneassistant.R
import com.jawad.phoneassistant.actions.ActionExecutor
import com.jawad.phoneassistant.data.TaskRepository
import com.jawad.phoneassistant.data.TaskStatus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Short-lived foreground service that runs one scheduled task at its firing
 * moment. Started by [TaskAlarmReceiver]; allowed to launch from the
 * background because an exact alarm triggered it.
 */
class ExecutionService : Service() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startAsForeground()
        val taskId = intent?.getLongExtra(AlarmScheduler.EXTRA_TASK_ID, -1L) ?: -1L
        if (taskId <= 0) {
            stopSelf(startId)
            return START_NOT_STICKY
        }

        val repo = TaskRepository(applicationContext)
        scope.launch {
            try {
                val task = repo.getById(taskId)
                if (task == null) {
                    stopSelf(startId); return@launch
                }
                repo.setStatus(taskId, TaskStatus.RUNNING, null)
                val result = ActionExecutor.execute(applicationContext, task)
                if (result.isSuccess) {
                    repo.setStatus(taskId, TaskStatus.DONE, null)
                    AssistantApp.notifyResult(applicationContext, taskId.toInt(),
                        "Task done", "Sent via ${task.channel.displayName} to ${task.target}")
                } else {
                    val msg = result.exceptionOrNull()?.message ?: "Unknown error"
                    repo.setStatus(taskId, TaskStatus.FAILED, msg)
                    AssistantApp.notifyResult(applicationContext, taskId.toInt(),
                        "Task failed", msg)
                }
            } catch (e: Exception) {
                repo.setStatus(taskId, TaskStatus.FAILED, e.message)
            } finally {
                stopSelf(startId)
            }
        }
        return START_NOT_STICKY
    }

    private fun startAsForeground() {
        val n: Notification = NotificationCompat.Builder(this, AssistantApp.CHANNEL_STATUS)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(getString(R.string.running_task))
            .setSmallIcon(R.drawable.ic_send)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceCompat.startForeground(
                this, FGS_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(FGS_ID, n)
        }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    companion object {
        private const val FGS_ID = 4201
    }
}
