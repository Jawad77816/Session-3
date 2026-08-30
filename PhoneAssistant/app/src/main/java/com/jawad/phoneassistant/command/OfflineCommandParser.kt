package com.jawad.phoneassistant.command

import com.jawad.phoneassistant.data.TaskChannel
import com.jawad.phoneassistant.util.TimeParser
import java.util.Locale

/**
 * A dependency-free, offline parser for the common command shapes:
 *
 *   "WhatsApp Ali: I'll be late at 5:30pm"
 *   "WhatsApp Business +923001234567 saying your order is ready in 2 hours"
 *   "SMS Ammi saying reached safely"
 *   "Email boss@work.com subject Leave body Taking tomorrow off at 9am"
 *
 * Returns null when it can't confidently split the command — callers then fall
 * back to the AI parser (if enabled) or the structured Add-task form.
 */
object OfflineCommandParser {

    private val businessRe = Regex("\\b(whatsapp\\s*business|business\\s*whatsapp|wa\\s*business|w4b|wab)\\b")
    private val whatsappRe = Regex("\\b(whatsapp|wsp|wa)\\b")
    private val smsRe = Regex("(^|\\b)(sms|text\\s*message)\\b")
    private val emailRe = Regex("\\b(e-?mail|gmail|mail)\\b")
    private val emailAddrRe = Regex("[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}")

    // Time phrases we strip out of the message body once the time is captured.
    private val timeStrips = listOf(
        Regex("\\b(at)\\s+\\d{1,2}(:\\d{2})?\\s*(am|pm|a\\.m\\.|p\\.m\\.)?", RegexOption.IGNORE_CASE),
        Regex("\\b(in|after)\\s+\\d+\\s*(hours?|hrs?|h|minutes?|mins?|m|days?|d|seconds?|secs?|s)(\\s+(and\\s+)?\\d+\\s*(hours?|hrs?|h|minutes?|mins?|m))?", RegexOption.IGNORE_CASE),
        Regex("\\b\\d+\\s*(hours?|hrs?|h|minutes?|mins?|m|days?|d)\\s+from\\s+now", RegexOption.IGNORE_CASE),
        Regex("\\b(day after tomorrow|tomorrow|today|tonight)\\b", RegexOption.IGNORE_CASE)
    )

    private val messageSeparators = listOf(" saying ", " message ", " that says ", " that ", " tell them ", ": ", ":")

    fun parse(raw: String): ParsedCommand? {
        val text = raw.trim()
        if (text.isEmpty()) return null
        val lower = text.lowercase(Locale.ENGLISH)

        val channel = when {
            businessRe.containsMatchIn(lower) -> TaskChannel.WHATSAPP_BUSINESS
            whatsappRe.containsMatchIn(lower) -> TaskChannel.WHATSAPP
            smsRe.containsMatchIn(lower) -> TaskChannel.SMS
            emailRe.containsMatchIn(lower) || emailAddrRe.containsMatchIn(text) -> TaskChannel.EMAIL
            else -> return null
        }

        val triggerAt = TimeParser.parse(text)

        // Remove the channel keyword from the working copy.
        var work = text
        for (re in listOf(businessRe, whatsappRe, smsRe, emailRe)) {
            work = re.replace(work) { "" }
        }
        work = work.trim().removePrefix("-").trim()

        return if (channel == TaskChannel.EMAIL) parseEmail(work, triggerAt)
        else parseMessaging(channel, work, triggerAt)
    }

    private fun parseMessaging(channel: TaskChannel, work: String, triggerAt: Long?): ParsedCommand? {
        val sep = messageSeparators.firstOrNull { work.contains(it, ignoreCase = true) } ?: return null
        val idx = work.indexOf(sep, ignoreCase = true)
        var target = work.substring(0, idx).trim()
        var message = work.substring(idx + sep.length).trim()

        target = cleanTarget(target)
        message = stripTime(message).trim().trimEnd(',', '.', ';')

        if (target.isEmpty() || message.isEmpty()) return null
        return ParsedCommand(channel, target, message, triggerAtMillis = triggerAt, source = "offline")
    }

    private fun parseEmail(work: String, triggerAt: Long?): ParsedCommand? {
        val addr = emailAddrRe.find(work)?.value ?: return null
        var rest = work.replace(addr, " ").trim()

        var subject: String? = null
        val subjMatch = Regex("subject\\s*[:\\-]?\\s*(.+?)(\\s+body\\b|\\s+saying\\b|:|$)", RegexOption.IGNORE_CASE).find(rest)
        if (subjMatch != null) {
            subject = subjMatch.groupValues[1].trim()
            rest = rest.replace(subjMatch.value, " ")
        }

        // Body follows "body"/"saying"/":", else it's whatever remains.
        val bodyMatch = Regex("(body|saying|message)\\s*[:\\-]?\\s*(.+)$", RegexOption.IGNORE_CASE).find(rest)
        var body = (bodyMatch?.groupValues?.get(2) ?: rest).trim()
        body = cleanTarget(body) // strip stray connectors like "to"
        body = stripTime(body).trim().trimEnd(',', '.', ';')

        if (body.isEmpty()) return null
        return ParsedCommand(
            TaskChannel.EMAIL, addr, body, subject = subject?.ifBlank { null },
            triggerAtMillis = triggerAt, source = "offline"
        )
    }

    private fun cleanTarget(t: String): String {
        var s = t.trim()
        s = s.removePrefix("to ").removePrefix("a message to ").removePrefix("message to ")
        s = Regex("^(send|a|message|msg|to)\\s+", RegexOption.IGNORE_CASE).replace(s, "")
        return stripTime(s).trim().trimEnd(',', '.', ':', ';').trim()
    }

    private fun stripTime(s: String): String {
        var out = s
        for (re in timeStrips) out = re.replace(out, " ")
        return out.replace(Regex("\\s{2,}"), " ").trim()
    }
}
