package com.jawad.phoneassistant.service

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.net.Uri
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.net.URLEncoder
import java.util.concurrent.CountDownLatch

/**
 * The "universal control" layer. Once enabled, Android routes UI events from
 * every app to this service and lets it perform taps. We use it to press
 * "Send" in WhatsApp / WhatsApp Business after opening a pre-filled chat.
 *
 * The same capability generalises to any app, present or future — that is the
 * closest Android allows to "control all apps".
 */
class AutomationAccessibilityService : AccessibilityService() {

    private data class PendingSend(
        val pkg: String,
        val latch: CountDownLatch,
        val createdAt: Long = System.currentTimeMillis()
    )

    @Volatile private var pending: PendingSend? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    override fun onInterrupt() {}

    /**
     * Opens a WhatsApp chat with [message] pre-filled and arms auto-send.
     * Returns true if the chat intent launched.
     */
    fun enqueueWhatsApp(pkg: String, intlNumber: String, message: String, latch: CountDownLatch): Boolean {
        return try {
            val encoded = URLEncoder.encode(message, "UTF-8")
            val url = "https://api.whatsapp.com/send?phone=$intlNumber&text=$encoded"
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                setPackage(pkg)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            pending = PendingSend(pkg, latch)
            startActivity(intent)
            true
        } catch (e: Exception) {
            pending = null
            false
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val p = pending ?: return
        // Expire stale requests so we never click an old chat.
        if (System.currentTimeMillis() - p.createdAt > 20_000) {
            pending = null
            return
        }
        val evtPkg = event?.packageName?.toString() ?: return
        if (evtPkg != p.pkg) return

        val root = rootInActiveWindow ?: return
        if (clickSend(root, p.pkg)) {
            pending = null
            p.latch.countDown()
        }
    }

    private fun clickSend(root: AccessibilityNodeInfo, pkg: String): Boolean {
        // Primary: WhatsApp's send FAB has a stable view id.
        root.findAccessibilityNodeInfosByViewId("$pkg:id/send")?.forEach { node ->
            if (clickNode(node)) return true
        }
        // Fallback: any clickable node described as "Send".
        findByDescription(root, "send")?.let { if (clickNode(it)) return true }
        return false
    }

    private fun clickNode(node: AccessibilityNodeInfo): Boolean {
        var n: AccessibilityNodeInfo? = node
        while (n != null) {
            if (n.isClickable) return n.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            n = n.parent
        }
        return node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
    }

    private fun findByDescription(node: AccessibilityNodeInfo?, desc: String): AccessibilityNodeInfo? {
        node ?: return null
        val cd = node.contentDescription?.toString()
        if (cd != null && cd.contains(desc, ignoreCase = true)) return node
        for (i in 0 until node.childCount) {
            findByDescription(node.getChild(i), desc)?.let { return it }
        }
        return null
    }

    companion object {
        @Volatile
        var instance: AutomationAccessibilityService? = null
            private set

        fun isEnabled(): Boolean = instance != null
    }
}
