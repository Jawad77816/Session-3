package com.jawad.phoneassistant.util

import android.content.Context
import android.provider.ContactsContract
import java.util.Locale

/** Looks up a phone number for a contact name using the system Contacts. */
object ContactResolver {

    private val phoneLike = Regex("^[+]?[0-9\\-()\\s]{6,}$")

    /** If [target] is already a phone number, normalise it; else search contacts. */
    fun resolveNumber(context: Context, target: String): String? {
        val trimmed = target.trim()
        if (phoneLike.matches(trimmed)) return normalize(trimmed)
        return lookupByName(context, trimmed)
    }

    private fun normalize(raw: String): String =
        raw.replace(Regex("[\\s\\-()]"), "")

    private fun lookupByName(context: Context, name: String): String? {
        val resolver = context.contentResolver
        val projection = arrayOf(
            ContactsContract.CommonDataKinds.Phone.NUMBER,
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME
        )
        // Case-insensitive partial match on display name.
        val selection = "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?"
        val args = arrayOf("%$name%")
        resolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            projection, selection, args, null
        )?.use { c ->
            val numIdx = c.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
            val nameIdx = c.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
            // Prefer an exact (case-insensitive) name match; else first partial hit.
            var firstNumber: String? = null
            while (c.moveToNext()) {
                val number = c.getString(numIdx) ?: continue
                val disp = c.getString(nameIdx) ?: ""
                if (disp.equals(name, ignoreCase = true)) return normalize(number)
                if (firstNumber == null) firstNumber = normalize(number)
            }
            return firstNumber
        }
        return null
    }

    /** Format a local Pakistani number into international (+92…) for wa.me links. */
    fun toInternational(number: String, defaultCountry: String = "92"): String {
        var n = normalize(number)
        if (n.startsWith("+")) return n.removePrefix("+")
        if (n.startsWith("00")) return n.removePrefix("00")
        if (n.startsWith("0")) return defaultCountry + n.substring(1)
        // Already looks international (starts with country code) or short — return as-is.
        return n
    }
}
