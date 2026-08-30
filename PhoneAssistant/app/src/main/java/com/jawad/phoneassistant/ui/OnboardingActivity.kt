package com.jawad.phoneassistant.ui

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import com.jawad.phoneassistant.databinding.ActivityOnboardingBinding

/** Guides the user through the permissions the assistant needs. */
class OnboardingActivity : AppCompatActivity() {

    private lateinit var b: ActivityOnboardingBinding

    private val permLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { result ->
        val granted = result.values.all { it }
        Toast.makeText(
            this,
            if (granted) "Granted" else "Some permissions were not granted",
            Toast.LENGTH_SHORT
        ).show()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        b = ActivityOnboardingBinding.inflate(layoutInflater)
        setContentView(b.root)
        b.toolbar.setNavigationOnClickListener { finish() }

        b.btnAccessibility.setOnClickListener { openAction(Settings.ACTION_ACCESSIBILITY_SETTINGS) }
        b.btnNotifAccess.setOnClickListener { openAction(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS) }
        b.btnSmsContacts.setOnClickListener {
            permLauncher.launch(arrayOf(Manifest.permission.SEND_SMS, Manifest.permission.READ_CONTACTS))
        }
        b.btnPostNotif.setOnClickListener {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                permLauncher.launch(arrayOf(Manifest.permission.POST_NOTIFICATIONS))
            } else {
                Toast.makeText(this, "Not needed on this Android version", Toast.LENGTH_SHORT).show()
            }
        }
        b.btnExactAlarm.setOnClickListener { openExactAlarm() }
        b.btnBattery.setOnClickListener { openBatteryExemption() }
        b.btnDone.setOnClickListener { finish() }
    }

    private fun openAction(action: String) {
        try {
            startActivity(Intent(action))
        } catch (e: Exception) {
            Toast.makeText(this, "Couldn't open that settings screen", Toast.LENGTH_SHORT).show()
        }
    }

    private fun openExactAlarm() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                        Uri.parse("package:$packageName")
                    )
                )
            } catch (e: Exception) {
                openAction(Settings.ACTION_SETTINGS)
            }
        } else {
            Toast.makeText(this, "Not needed on this Android version", Toast.LENGTH_SHORT).show()
        }
    }

    private fun openBatteryExemption() {
        try {
            startActivity(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$packageName")
                )
            )
        } catch (e: Exception) {
            openAction(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        }
    }
}
