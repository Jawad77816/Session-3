package com.jawad.phoneassistant.util

import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.regex.Pattern

/**
 * Turns human phrases into an absolute firing time, always interpreted in
 * Pakistan Standard Time (Asia/Karachi, UTC+5).
 *
 * Understands, e.g.:
 *   "in 2 hours", "after 30 minutes", "2 hours from now", "in 1 hour 30 min"
 *   "at 5:30pm", "at 17:30", "5pm", "tomorrow at 9am", "today at 8:15 pm"
 * and the AI parser's structured "yyyy-MM-dd HH:mm".
 */
object TimeParser {

    val zone: ZoneId = ZoneId.of("Asia/Karachi")

    private val displayFmt =
        DateTimeFormatter.ofPattern("EEE, d MMM yyyy • h:mm a", Locale.ENGLISH)
    private val isoFmt = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm", Locale.ENGLISH)

    /** @return epoch millis (UTC) for the requested moment, or null if unparseable. */
    fun parse(text: String, nowMillis: Long = System.currentTimeMillis()): Long? {
        val t = text.lowercase(Locale.ENGLISH).trim()
        parseRelative(t, nowMillis)?.let { return it }
        parseAbsolute(t, nowMillis)?.let { return it }
        return null
    }

    /** Parse the AI parser's structured "yyyy-MM-dd HH:mm" as Karachi local time. */
    fun parseIsoKarachi(s: String): Long? = try {
        val ldt = LocalDateTime.parse(s.trim(), isoFmt)
        ldt.atZone(zone).toInstant().toEpochMilli()
    } catch (e: Exception) {
        null
    }

    fun format(millis: Long): String =
        ZonedDateTime.ofInstant(java.time.Instant.ofEpochMilli(millis), zone).format(displayFmt)

    // ---------------- relative ("in 2 hours", "30 min from now") ----------------
    private val relUnit = Pattern.compile("(\\d+)\\s*(hours?|hrs?|h|minutes?|mins?|m|days?|d|seconds?|secs?|s)\\b")

    private fun parseRelative(t: String, nowMillis: Long): Long? {
        val looksRelative = t.contains("from now") || t.startsWith("in ") ||
                t.startsWith("after ") || t.contains(" in ") || t.contains(" after ")
        if (!looksRelative) return null

        val m = relUnit.matcher(t)
        var totalMs = 0L
        var found = false
        while (m.find()) {
            val n = m.group(1)!!.toLong()
            val unit = m.group(2)!!
            val ms = when {
                unit.startsWith("h") -> n * 3_600_000L
                unit == "d" || unit.startsWith("day") -> n * 86_400_000L
                unit.startsWith("s") && unit != "min" -> n * 1_000L
                else -> n * 60_000L // minutes (min, m, minute)
            }
            totalMs += ms
            found = true
        }
        return if (found && totalMs > 0) nowMillis + totalMs else null
    }

    // ---------------- absolute ("at 5:30pm", "tomorrow at 9am") ----------------
    private val timePat =
        Pattern.compile("(?:at\\s+)?(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm|a\\.m\\.|p\\.m\\.)?")

    private fun parseAbsolute(t: String, nowMillis: Long): Long? {
        val now = ZonedDateTime.ofInstant(java.time.Instant.ofEpochMilli(nowMillis), zone)
        var date: LocalDate = now.toLocalDate()
        var dayExplicit = false
        when {
            t.contains("day after tomorrow") -> { date = date.plusDays(2); dayExplicit = true }
            t.contains("tomorrow") -> { date = date.plusDays(1); dayExplicit = true }
            t.contains("today") || t.contains("tonight") -> { dayExplicit = true }
        }

        val m = timePat.matcher(t)
        // Find a time token that actually has am/pm or a colon or an "at" prefix,
        // to avoid matching stray numbers.
        var chosen: Triple<Int, Int, String?>? = null
        while (m.find()) {
            val hasMeridiem = m.group(3) != null
            val hasColon = m.group(2) != null
            val hasAt = m.group(0)!!.trimStart().startsWith("at")
            if (!hasMeridiem && !hasColon && !hasAt) continue
            val hour = m.group(1)!!.toInt()
            if (hour > 23) continue
            val minute = m.group(2)?.toInt() ?: 0
            if (minute > 59) continue
            chosen = Triple(hour, minute, m.group(3))
            break
        }
        val (h0, min, mer) = chosen ?: return null

        var hour = h0
        if (mer != null) {
            val pm = mer.startsWith("p")
            if (pm && hour < 12) hour += 12
            if (!pm && hour == 12) hour = 0
        }
        if (hour > 23) return null

        var candidate = ZonedDateTime.of(date, LocalTime.of(hour, min), zone)
        // If no explicit day and the time already passed today, use tomorrow.
        if (!dayExplicit && !candidate.isAfter(now)) {
            candidate = candidate.plusDays(1)
        }
        return candidate.toInstant().toEpochMilli()
    }
}
