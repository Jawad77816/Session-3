package com.jawad.phoneassistant.actions

import android.content.Context
import com.jawad.phoneassistant.data.ScheduledTask
import com.jawad.phoneassistant.security.SecurePrefs
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.Properties
import javax.mail.Authenticator
import javax.mail.Message
import javax.mail.PasswordAuthentication
import javax.mail.Session
import javax.mail.Transport
import javax.mail.internet.InternetAddress
import javax.mail.internet.MimeMessage

/** Sends email over SMTP using the user's own account (app password). */
object EmailSender {
    suspend fun send(context: Context, task: ScheduledTask): Result<Unit> = withContext(Dispatchers.IO) {
        val prefs = SecurePrefs.get(context)
        if (!prefs.hasEmailConfigured) {
            return@withContext Result.failure(IllegalStateException("Email not set up (add SMTP details in Settings)"))
        }
        try {
            val props = Properties().apply {
                put("mail.smtp.auth", "true")
                put("mail.smtp.host", prefs.smtpHost)
                put("mail.smtp.port", prefs.smtpPort.toString())
                if (prefs.smtpPort == 465) {
                    put("mail.smtp.ssl.enable", "true")
                } else {
                    put("mail.smtp.starttls.enable", "true")
                }
            }
            val session = Session.getInstance(props, object : Authenticator() {
                override fun getPasswordAuthentication() =
                    PasswordAuthentication(prefs.smtpUser, prefs.smtpPassword)
            })
            val msg = MimeMessage(session).apply {
                setFrom(InternetAddress(prefs.smtpUser))
                setRecipients(Message.RecipientType.TO, InternetAddress.parse(task.target))
                subject = task.subject?.ifBlank { null } ?: "(no subject)"
                setText(task.message)
            }
            Transport.send(msg)
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
