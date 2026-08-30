package com.jawad.phoneassistant.ui

import android.graphics.Color
import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.jawad.phoneassistant.data.ScheduledTask
import com.jawad.phoneassistant.data.TaskStatus
import com.jawad.phoneassistant.databinding.ItemTaskBinding
import com.jawad.phoneassistant.util.TimeParser

class TaskAdapter(
    private val onClick: (ScheduledTask) -> Unit,
    private val onDelete: (ScheduledTask) -> Unit
) : ListAdapter<ScheduledTask, TaskAdapter.VH>(DIFF) {

    inner class VH(val b: ItemTaskBinding) : RecyclerView.ViewHolder(b.root)

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val b = ItemTaskBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return VH(b)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        val t = getItem(position)
        holder.b.itemTitle.text = "${t.channel.displayName} → ${t.target}"
        holder.b.itemMessage.text = t.message
        holder.b.itemTime.text = TimeParser.format(t.triggerAtMillis)
        holder.b.itemStatus.text = t.status.name + (t.lastError?.let { " • $it" } ?: "")
        holder.b.itemStatus.setTextColor(colorFor(t.status))
        holder.b.root.setOnClickListener { onClick(t) }
        holder.b.itemDelete.setOnClickListener { onDelete(t) }
    }

    private fun colorFor(status: TaskStatus): Int = when (status) {
        TaskStatus.SCHEDULED -> Color.parseColor("#0B6BCB")
        TaskStatus.RUNNING -> Color.parseColor("#B54708")
        TaskStatus.DONE -> Color.parseColor("#12B76A")
        TaskStatus.FAILED -> Color.parseColor("#D92D20")
        TaskStatus.CANCELLED -> Color.parseColor("#5A6069")
    }

    companion object {
        val DIFF = object : DiffUtil.ItemCallback<ScheduledTask>() {
            override fun areItemsTheSame(a: ScheduledTask, b: ScheduledTask) = a.id == b.id
            override fun areContentsTheSame(a: ScheduledTask, b: ScheduledTask) = a == b
        }
    }
}
