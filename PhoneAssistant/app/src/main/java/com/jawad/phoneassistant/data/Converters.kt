package com.jawad.phoneassistant.data

import androidx.room.TypeConverter

/** Stores the enum types as their String names in the database. */
class Converters {
    @TypeConverter
    fun channelToString(c: TaskChannel): String = c.name

    @TypeConverter
    fun stringToChannel(s: String): TaskChannel = TaskChannel.valueOf(s)

    @TypeConverter
    fun statusToString(s: TaskStatus): String = s.name

    @TypeConverter
    fun stringToStatus(s: String): TaskStatus = TaskStatus.valueOf(s)
}
