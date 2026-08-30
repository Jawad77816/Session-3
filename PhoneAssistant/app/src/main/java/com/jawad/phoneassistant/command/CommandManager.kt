package com.jawad.phoneassistant.command

import android.content.Context

/**
 * Offline-first command understanding. Tries the instant, private offline
 * parser; if it can't confidently parse the phrase and the user has enabled
 * AI (with an API key), it falls back to the Anthropic-powered parser.
 */
object CommandManager {
    suspend fun parse(context: Context, text: String): ParsedCommand? {
        OfflineCommandParser.parse(text)?.let { return it }
        return AiCommandParser.parse(context, text)
    }
}
