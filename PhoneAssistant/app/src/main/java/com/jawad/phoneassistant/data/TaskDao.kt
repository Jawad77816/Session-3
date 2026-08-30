package com.jawad.phoneassistant.data

import androidx.lifecycle.LiveData
import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update

@Dao
interface TaskDao {

    @Insert
    suspend fun insert(task: ScheduledTask): Long

    @Update
    suspend fun update(task: ScheduledTask)

    @Delete
    suspend fun delete(task: ScheduledTask)

    @Query("SELECT * FROM scheduled_tasks WHERE id = :id LIMIT 1")
    suspend fun getById(id: Long): ScheduledTask?

    /** Live list for the UI, soonest first. */
    @Query("SELECT * FROM scheduled_tasks ORDER BY triggerAtMillis ASC")
    fun observeAll(): LiveData<List<ScheduledTask>>

    /** Tasks that still need to fire — used to re-arm alarms after a reboot. */
    @Query("SELECT * FROM scheduled_tasks WHERE status = 'SCHEDULED'")
    suspend fun getPending(): List<ScheduledTask>

    @Query("UPDATE scheduled_tasks SET status = :status, lastError = :error WHERE id = :id")
    suspend fun setStatus(id: Long, status: TaskStatus, error: String?)
}
