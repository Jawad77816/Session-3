package com.jawad.phoneassistant.scheduler

import android.content.Context
import com.jawad.phoneassistant.data.ScheduledTask
import com.jawad.phoneassistant.data.TaskRepository

/** One place to create/update/cancel tasks and keep their alarms in sync. */
object TaskController {

    suspend fun createAndSchedule(context: Context, task: ScheduledTask): ScheduledTask {
        val repo = TaskRepository(context)
        val id = repo.insert(task)
        val saved = task.copy(id = id)
        AlarmScheduler.schedule(context, saved)
        return saved
    }

    suspend fun reschedule(context: Context, task: ScheduledTask) {
        val repo = TaskRepository(context)
        repo.update(task)
        AlarmScheduler.cancel(context, task.id)
        AlarmScheduler.schedule(context, task)
    }

    suspend fun cancelAndDelete(context: Context, task: ScheduledTask) {
        val repo = TaskRepository(context)
        AlarmScheduler.cancel(context, task.id)
        repo.delete(task)
    }
}
