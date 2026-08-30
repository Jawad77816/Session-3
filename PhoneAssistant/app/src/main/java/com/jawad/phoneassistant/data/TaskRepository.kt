package com.jawad.phoneassistant.data

import android.content.Context

/** Thin wrapper over the DAO so the rest of the app never touches Room directly. */
class TaskRepository(context: Context) {
    private val dao = AppDatabase.get(context).taskDao()

    fun observeAll() = dao.observeAll()
    suspend fun getById(id: Long) = dao.getById(id)
    suspend fun getPending() = dao.getPending()
    suspend fun insert(task: ScheduledTask): Long = dao.insert(task)
    suspend fun update(task: ScheduledTask) = dao.update(task)
    suspend fun delete(task: ScheduledTask) = dao.delete(task)
    suspend fun setStatus(id: Long, status: TaskStatus, error: String? = null) =
        dao.setStatus(id, status, error)
}
