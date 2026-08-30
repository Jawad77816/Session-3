package com.jawad.phoneassistant.ui

import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.jawad.phoneassistant.databinding.ActivitySettingsBinding
import com.jawad.phoneassistant.security.SecurePrefs

class SettingsActivity : AppCompatActivity() {

    private lateinit var b: ActivitySettingsBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        b = ActivitySettingsBinding.inflate(layoutInflater)
        setContentView(b.root)
        b.toolbar.setNavigationOnClickListener { finish() }

        val p = SecurePrefs.get(this)
        b.aiSwitch.isChecked = p.aiEnabled
        b.apiKeyInput.setText(p.claudeApiKey)
        b.smtpHost.setText(p.smtpHost)
        b.smtpPort.setText(p.smtpPort.toString())
        b.smtpUser.setText(p.smtpUser)
        b.smtpPass.setText(p.smtpPassword)

        b.saveSettings.setOnClickListener {
            p.aiEnabled = b.aiSwitch.isChecked
            p.claudeApiKey = b.apiKeyInput.text?.toString().orEmpty()
            p.smtpHost = b.smtpHost.text?.toString().orEmpty().ifBlank { "smtp.gmail.com" }
            p.smtpPort = b.smtpPort.text?.toString()?.toIntOrNull() ?: 587
            p.smtpUser = b.smtpUser.text?.toString().orEmpty()
            p.smtpPassword = b.smtpPass.text?.toString().orEmpty()
            Toast.makeText(this, "Settings saved", Toast.LENGTH_SHORT).show()
            finish()
        }
    }
}
