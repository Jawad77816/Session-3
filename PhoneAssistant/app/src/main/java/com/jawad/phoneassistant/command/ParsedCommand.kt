package com.jawad.phoneassistant.command

import com.jawad.phoneassistant.data.TaskChannel

/**
 * The structured result of understanding a natural-language command.
 * [triggerAtMillis] == null means "do it now".
 */
data class ParsedCommand(
    val channel: TaskChannel,
    val target: String,
    val message: String,
    val subject: String? = null,
    val triggerAtMillis: Long? = null,
    val source: String = "offline"
)
