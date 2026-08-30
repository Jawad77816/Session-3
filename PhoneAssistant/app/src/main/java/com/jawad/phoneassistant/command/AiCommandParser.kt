package com.jawad.phoneassistant.command

import android.content.Context
import com.jawad.phoneassistant.data.TaskChannel
import com.jawad.phoneassistant.security.SecurePrefs
import com.jawad.phoneassistant.util.TimeParser
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URL
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Natural-language command understanding via the Anthropic Messages API.
 * Uses the phone's own network and the user's own API key (stored encrypted).
 * Every failure path returns null so the caller can fall back to the offline
 * parser — this never throws to the UI.
 */
object AiCommandParser {

    // Default model. Users can change this to a faster/cheaper model
    // (e.g. "claude-haiku-4-5") in Settings notes / here if they prefer.
    private const val MODEL = "claude-opus-5"
    private const val ENDPOINT = "https://api.anthropic.com/v1/messages"
    private const val ANTHROPIC_VERSION = "2023-06-01"

    private val nowFmt = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm (EEEE)", Locale.ENGLISH)

    private const val SYSTEM_PROMPT =
        "You convert a user's instruction into ONE JSON object describing a message to send. " +
        "Output ONLY minified JSON — no prose, no markdown fences. Schema: " +
        "{\"channel\":\"whatsapp\"|\"whatsapp_business\"|\"sms\"|\"email\"," +
        "\"target\":string (contact name, phone number, or email address)," +
        "\"subject\":string (email subject; empty if not email)," +
        "\"message\":string (the exact content to send)," +
        "\"datetime\":string \"YYYY-MM-DD HH:mm\" in Pakistan time for when to send, " +
        "or empty string to send immediately}. " +
        "Resolve relative times (e.g. 'in 2 hours', 'tomorrow 9am') against the current Pakistan time given by the user. " +
        "Never put the time expression inside 'message'. If channel is unstated, pick the most likely."

    suspend fun parse(context: Context, command: String): ParsedCommand? = withContext(Dispatchers.IO) {
        val prefs = SecurePrefs.get(context)
        if (!prefs.hasAi) return@withContext null
        val apiKey = prefs.claudeApiKey
        try {
            val nowPkt = ZonedDateTime.now(TimeParser.zone).format(nowFmt)
            val userMsg = "Current date-time in Pakistan (Asia/Karachi): $nowPkt.\nCommand: $command"

            val body = JSONObject().apply {
                put("model", MODEL)
                put("max_tokens", 400)
                put("system", SYSTEM_PROMPT)
                put("messages", JSONArray().put(JSONObject().apply {
                    put("role", "user")
                    put("content", userMsg)
                }))
            }.toString()

            val text = postForText(apiKey, body) ?: return@withContext null
            val json = extractJsonObject(text) ?: return@withContext null
            toCommand(json)
        } catch (e: Exception) {
            null
        }
    }

    private fun postForText(apiKey: String, body: String): String? {
        val conn = (URL(ENDPOINT).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 15000
            readTimeout = 45000
            doOutput = true
            setRequestProperty("content-type", "application/json")
            setRequestProperty("x-api-key", apiKey)
            setRequestProperty("anthropic-version", ANTHROPIC_VERSION)
        }
        conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }

        val code = conn.responseCode
        val stream = if (code in 200..299) conn.inputStream else conn.errorStream
        val response = stream?.bufferedReader()?.use(BufferedReader::readText) ?: return null
        conn.disconnect()
        if (code !in 200..299) return null

        // Find the first text content block (skip any thinking blocks).
        val content = JSONObject(response).optJSONArray("content") ?: return null
        for (i in 0 until content.length()) {
            val block = content.optJSONObject(i) ?: continue
            if (block.optString("type") == "text") {
                val t = block.optString("text")
                if (t.isNotBlank()) return t
            }
        }
        return null
    }

    /** Pulls the first {...} JSON object out of the model's text, defensively. */
    private fun extractJsonObject(text: String): JSONObject? {
        val start = text.indexOf('{')
        val end = text.lastIndexOf('}')
        if (start < 0 || end <= start) return null
        return try {
            JSONObject(text.substring(start, end + 1))
        } catch (e: Exception) {
            null
        }
    }

    private fun toCommand(json: JSONObject): ParsedCommand? {
        val channel = when (json.optString("channel").lowercase(Locale.ENGLISH).replace(" ", "_")) {
            "whatsapp_business", "business_whatsapp", "wa_business", "w4b" -> TaskChannel.WHATSAPP_BUSINESS
            "whatsapp", "wa" -> TaskChannel.WHATSAPP
            "sms", "text" -> TaskChannel.SMS
            "email", "mail", "e-mail" -> TaskChannel.EMAIL
            else -> return null
        }
        val target = json.optString("target").trim()
        val message = json.optString("message").trim()
        if (target.isEmpty() || message.isEmpty()) return null
        val subject = json.optString("subject").trim().ifBlank { null }
        val dt = json.optString("datetime").trim()
        val triggerAt = if (dt.isBlank()) null else TimeParser.parseIsoKarachi(dt)
        return ParsedCommand(channel, target, message, subject, triggerAt, source = "ai")
    }
}
