package com.jawad.phoneassistant.ui

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.os.Bundle
import android.view.View
import android.widget.ArrayAdapter
import android.widget.AdapterView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.jawad.phoneassistant.data.ScheduledTask
import com.jawad.phoneassistant.data.TaskChannel
import com.jawad.phoneassistant.data.TaskRepository
import com.jawad.phoneassistant.data.TaskStatus
import com.jawad.phoneassistant.databinding.ActivityAddEditTaskBinding
import com.jawad.phoneassistant.scheduler.TaskController
import com.jawad.phoneassistant.util.TimeParser
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZonedDateTime

class AddEditTaskActivity : AppCompatActivity() {

    private lateinit var b: ActivityAddEditTaskBinding
    private var editingId: Long = -1
    private var loaded: ScheduledTask? = null

    // The chosen moment, held in Pakistan time.
    private var cal: ZonedDateTime = ZonedDateTime.now(TimeParser.zone)
        .plusHours(1).withSecond(0).withNano(0)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        b = ActivityAddEditTaskBinding.inflate(layoutInflater)
        setContentView(b.root)
        b.toolbar.setNavigationOnClickListener { finish() }

        val names = TaskChannel.values().map { it.displayName }
        b.channelSpinner.adapter = ArrayAdapter(
            this, android.R.layout.simple_spinner_dropdown_item, names
        )
        b.channelSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(p: AdapterView<*>?, v: View?, pos: Int, id: Long) {
                b.subjectLayout.visibility =
                    if (TaskChannel.values()[pos] == TaskChannel.EMAIL) View.VISIBLE else View.GONE
            }
            override fun onNothingSelected(p: AdapterView<*>?) {}
        }

        b.pickDate.setOnClickListener { pickDate() }
        b.pickTime.setOnClickListener { pickTime() }
        b.save.setOnClickListener { save(runNow = false) }
        b.runNow.setOnClickListener { save(runNow = true) }

        editingId = intent.getLongExtra(EXTRA_TASK_ID, -1)
        if (editingId > 0) loadExisting(editingId) else updateWhenText()
    }

    private fun loadExisting(id: Long) {
        lifecycleScope.launch {
            val t = TaskRepository(applicationContext).getById(id) ?: return@launch
            loaded = t
            b.toolbar.title = "Edit task"
            b.channelSpinner.setSelection(TaskChannel.values().indexOf(t.channel))
            b.targetInput.setText(t.target)
            b.messageInput.setText(t.message)
            t.subject?.let { b.subjectInput.setText(it) }
            cal = ZonedDateTime.ofInstant(Instant.ofEpochMilli(t.triggerAtMillis), TimeParser.zone)
            updateWhenText()
        }
    }

    private fun pickDate() {
        DatePickerDialog(this, { _, y, m, d ->
            cal = cal.withYear(y).withMonth(m + 1).withDayOfMonth(d)
            updateWhenText()
        }, cal.year, cal.monthValue - 1, cal.dayOfMonth).show()
    }

    private fun pickTime() {
        TimePickerDialog(this, { _, h, min ->
            cal = cal.withHour(h).withMinute(min).withSecond(0).withNano(0)
            updateWhenText()
        }, cal.hour, cal.minute, false).show()
    }

    private fun updateWhenText() {
        b.whenText.text = "⏰ " + TimeParser.format(cal.toInstant().toEpochMilli())
    }

    private fun save(runNow: Boolean) {
        val channel = TaskChannel.values()[b.channelSpinner.selectedItemPosition]
        val target = b.targetInput.text?.toString()?.trim().orEmpty()
        val message = b.messageInput.text?.toString()?.trim().orEmpty()
        val subject = b.subjectInput.text?.toString()?.trim()?.ifBlank { null }

        if (target.isEmpty()) { Toast.makeText(this, "Enter a contact / number / email", Toast.LENGTH_SHORT).show(); return }
        if (message.isEmpty()) { Toast.makeText(this, "Enter a message", Toast.LENGTH_SHORT).show(); return }

        val fireAt = if (runNow) System.currentTimeMillis() + 1500 else cal.toInstant().toEpochMilli()
        if (!runNow && fireAt < System.currentTimeMillis()) {
            Toast.makeText(this, "That time is in the past — pick a future time.", Toast.LENGTH_SHORT).show()
            return
        }

        lifecycleScope.launch {
            if (editingId > 0 && loaded != null) {
                val updated = loaded!!.copy(
                    channel = channel, target = target, subject = subject,
                    message = message, triggerAtMillis = fireAt,
                    status = TaskStatus.SCHEDULED, lastError = null, resolvedNumber = null
                )
                TaskController.reschedule(applicationContext, updated)
            } else {
                val task = ScheduledTask(
                    channel = channel, target = target, subject = subject,
                    message = message, triggerAtMillis = fireAt
                )
                TaskController.createAndSchedule(applicationContext, task)
            }
            finish()
        }
    }

    companion object {
        const val EXTRA_TASK_ID = "extra_task_id"
    }
}
