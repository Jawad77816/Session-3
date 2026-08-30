package com.jawad.phoneassistant.security

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Locally-encrypted storage for secrets (Claude API key, SMTP password) and
 * a few plain settings. Backed by Android Jetpack Security's
 * EncryptedSharedPreferences so the values are encrypted at rest and never
 * leave the device.
 */
class SecurePrefs private constructor(private val prefs: SharedPreferences) {

    // ---- AI command parsing ----
    var aiEnabled: Boolean
        get() = prefs.getBoolean(KEY_AI_ENABLED, false)
        set(v) = prefs.edit().putBoolean(KEY_AI_ENABLED, v).apply()

    var claudeApiKey: String
        get() = prefs.getString(KEY_API_KEY, "") ?: ""
        set(v) = prefs.edit().putString(KEY_API_KEY, v.trim()).apply()

    // ---- Email (SMTP) ----
    var smtpHost: String
        get() = prefs.getString(KEY_SMTP_HOST, "smtp.gmail.com") ?: "smtp.gmail.com"
        set(v) = prefs.edit().putString(KEY_SMTP_HOST, v.trim()).apply()

    var smtpPort: Int
        get() = prefs.getInt(KEY_SMTP_PORT, 587)
        set(v) = prefs.edit().putInt(KEY_SMTP_PORT, v).apply()

    var smtpUser: String
        get() = prefs.getString(KEY_SMTP_USER, "") ?: ""
        set(v) = prefs.edit().putString(KEY_SMTP_USER, v.trim()).apply()

    var smtpPassword: String
        get() = prefs.getString(KEY_SMTP_PASS, "") ?: ""
        set(v) = prefs.edit().putString(KEY_SMTP_PASS, v).apply()

    val hasEmailConfigured: Boolean
        get() = smtpUser.isNotBlank() && smtpPassword.isNotBlank()

    val hasAi: Boolean
        get() = aiEnabled && claudeApiKey.isNotBlank()

    companion object {
        private const val FILE = "secure_prefs"
        private const val KEY_AI_ENABLED = "ai_enabled"
        private const val KEY_API_KEY = "claude_api_key"
        private const val KEY_SMTP_HOST = "smtp_host"
        private const val KEY_SMTP_PORT = "smtp_port"
        private const val KEY_SMTP_USER = "smtp_user"
        private const val KEY_SMTP_PASS = "smtp_pass"

        @Volatile private var INSTANCE: SecurePrefs? = null

        fun get(context: Context): SecurePrefs =
            INSTANCE ?: synchronized(this) {
                INSTANCE ?: build(context.applicationContext).also { INSTANCE = it }
            }

        private fun build(context: Context): SecurePrefs {
            val masterKey = MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
            val sp = EncryptedSharedPreferences.create(
                context,
                FILE,
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
            return SecurePrefs(sp)
        }
    }
}
