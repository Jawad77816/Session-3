package com.jawad.phoneassistant.ui

import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Bundle
import android.view.Menu
import android.view.MenuItem
import android.view.View
import android.view.inputmethod.EditorInfo
import android.speech.RecognizerIntent
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.jawad.phoneassistant.command.CommandManager
import com.jawad.phoneassistant.data.ScheduledTask
import com.jawad.phoneassistant.data.TaskRepository
import com.jawad.phoneassistant.databinding.ActivityMainBinding
import com.jawad.phoneassistant.scheduler.TaskController
import com.jawad.phoneassistant.util.TimeParser
import com.jawad.phoneassistant.voice.VoiceInput
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {

    private lateinit var b: ActivityMainBinding
    private val repo by lazy { TaskRepository(applicationContext) }
    private lateinit var adapter: TaskAdapter

    private val voiceLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == RESULT_OK) {
            val text = result.data
                ?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                ?.firstOrNull()
            if (!text.isNullOrBlank()) {
                b.commandInput.setText(text)
                b.commandInput.setSelection(text.length)
                Toast.makeText(this, "Review, then tap send ▶", Toast.LENGTH_SHORT).show()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        b = ActivityMainBinding.inflate(layoutInflater)
        setContentView(b.root)
        setSupportActionBar(b.toolbar)

        adapter = TaskAdapter(
            onClick = { openEdit(it.id) },
            onDelete = { deleteTask(it) }
        )
        b.taskList.layoutManager = LinearLayoutManager(this)
        b.taskList.adapter = adapter

        repo.observeAll().observe(this) { list ->
            adapter.submitList(list)
            b.emptyView.visibility = if (list.isEmpty()) View.VISIBLE else View.GONE
        }

        b.sendButton.setOnClickListener { handleCommand() }
        b.micButton.setOnClickListener { launchVoice() }
        b.fab.setOnClickListener { startActivity(Intent(this, AddEditTaskActivity::class.java)) }

        b.commandInput.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEND) {
                handleCommand(); true
            } else false
        }

        maybeFirstRunSetup()
    }

    private fun handleCommand() {
        val text = b.commandInput.text?.toString()?.trim().orEmpty()
        if (text.isEmpty()) return
        lifecycleScope.launch {
            val parsed = CommandManager.parse(applicationContext, text)
            if (parsed == null) {
                Toast.makeText(
                    this@MainActivity,
                    "Couldn't understand that. Try “WhatsApp Ali: hi at 5pm”, or tap + to add it manually.",
                    Toast.LENGTH_LONG
                ).show()
                return@launch
            }
            val immediate = parsed.triggerAtMillis == null
            val fireAt = parsed.triggerAtMillis ?: (System.currentTimeMillis() + 1500)
            val task = ScheduledTask(
                channel = parsed.channel,
                target = parsed.target,
                subject = parsed.subject,
                message = parsed.message,
                triggerAtMillis = fireAt
            )
            TaskController.createAndSchedule(applicationContext, task)
            b.commandInput.setText("")
            val whenStr = if (immediate) "now" else TimeParser.format(fireAt)
            Toast.makeText(
                this@MainActivity,
                "${parsed.channel.displayName} → ${parsed.target}: $whenStr",
                Toast.LENGTH_LONG
            ).show()
        }
    }

    private fun launchVoice() {
        try {
            voiceLauncher.launch(VoiceInput.intent("Speak a command"))
        } catch (e: ActivityNotFoundException) {
            Toast.makeText(this, "Voice input isn't available on this device.", Toast.LENGTH_SHORT).show()
        }
    }

    private fun deleteTask(task: ScheduledTask) {
        lifecycleScope.launch { TaskController.cancelAndDelete(applicationContext, task) }
    }

    private fun openEdit(id: Long) {
        startActivity(Intent(this, AddEditTaskActivity::class.java)
            .putExtra(AddEditTaskActivity.EXTRA_TASK_ID, id))
    }

    private fun maybeFirstRunSetup() {
        val prefs = getSharedPreferences("app", MODE_PRIVATE)
        if (!prefs.getBoolean("onboarded", false)) {
            prefs.edit().putBoolean("onboarded", true).apply()
            startActivity(Intent(this, OnboardingActivity::class.java))
        }
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(com.jawad.phoneassistant.R.menu.main_menu, menu)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return when (item.itemId) {
            com.jawad.phoneassistant.R.id.action_setup -> {
                startActivity(Intent(this, OnboardingActivity::class.java)); true
            }
            com.jawad.phoneassistant.R.id.action_settings -> {
                startActivity(Intent(this, SettingsActivity::class.java)); true
            }
            else -> super.onOptionsItemSelected(item)
        }
    }
}
