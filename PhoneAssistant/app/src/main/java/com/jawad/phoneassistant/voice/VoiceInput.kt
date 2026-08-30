package com.jawad.phoneassistant.voice

import android.content.Intent
import android.speech.RecognizerIntent
import java.util.Locale

/**
 * Voice capture via the system speech recogniser dialog. Using the
 * RecognizerIntent means no microphone permission and no recogniser lifecycle
 * to manage — the recognised text comes back through an activity result.
 */
object VoiceInput {
    fun intent(prompt: String): Intent =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault())
            putExtra(RecognizerIntent.EXTRA_PROMPT, prompt)
        }
}
