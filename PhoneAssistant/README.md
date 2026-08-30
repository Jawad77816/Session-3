# Phone Assistant

A personal, on-device automation assistant for Android. Schedule messages by
**voice or text**, and have them sent automatically at a time you choose in
**Pakistan Standard Time (PKT, UTC+5)** — via **WhatsApp, WhatsApp Business,
SMS, or Email**.

> Example: say or type **“WhatsApp Ali: I’ll be 10 minutes late at 5:30pm”** and
> the app opens WhatsApp at 5:30pm PKT and sends it for you.

---

## ⚠️ Read this first — what Android does and doesn’t allow

You asked for “full read/write access to **all** apps’ data.” That is **not
possible on Android for any app**, and this app does not do it — the phone’s
operating system stops it at the kernel level (every app’s private data is
locked to its own OS user; there is no permission that grants access to another
app’s data). Rooting doesn’t change this in any usable, safe way.

What this app uses instead is the **closest thing Android allows**, which
covers the real goal:

| What you wanted | How this app delivers it |
| --- | --- |
| Control / press buttons in another app (WhatsApp) | **Accessibility service** — taps “Send” for you in any app |
| Awareness across all apps | **Notification listener** — reads notifications from every app |
| Works for future apps too | Both services apply to any app automatically |
| Send SMS / Email | Proper Android APIs (`SmsManager` / SMTP) |
| Look up contacts | Contacts permission |
| Schedule at an exact PKT time | Exact alarms + `Asia/Karachi` timezone |

Automating WhatsApp works by **simulating your taps**. It’s reliable but can
break if WhatsApp changes its screen layout, and automated sending may bend
WhatsApp’s terms of service — use it on your own account, at your own risk.

---

## 📲 How to get the installable APK (no computer needed)

This project builds itself on GitHub. Every push to the branch triggers a build.

1. Open your repo on GitHub → **Actions** tab → the latest **Build APK** run.
2. Either:
   - Download **`PhoneAssistant-debug-apk`** from that run’s **Artifacts** (a zip
     containing `app-debug.apk`), **or**
   - Go to the repo’s **Releases** → **Latest debug APK** → download
     **`app-debug.apk`** directly.
3. Copy the `.apk` to your phone and open it. When prompted, allow
   **“Install unknown apps”** for your browser/file manager, then install.

> The APK is a **debug** build (signed with Android’s debug key). That’s normal
> for personal sideloading. It is not on the Play Store — accessibility-based
> automation + SMS apps can’t easily be published there.

---

## 🚀 First launch — grant permissions

On first open you’ll see the **Setup** screen (reopen anytime from the ⋮ menu →
*Setup & permissions*). Grant, in order:

1. **App Automation (Accessibility)** — turn on “Phone Assistant — App
   Automation”. Required for WhatsApp/WhatsApp Business auto-send.
2. **Notification access** — optional; cross-app notification awareness.
3. **SMS & Contacts** — send SMS and resolve contact names to numbers.
4. **Show notifications** — see when a task ran (Android 13+).
5. **Exact alarms** — fire tasks at the exact minute (Android 12+).
6. **Ignore battery optimisation** — keep scheduled tasks reliable when idle.

For **Email**, open **Settings** and enter your SMTP details (e.g. Gmail:
host `smtp.gmail.com`, port `587`, your address, and a Gmail **App Password** —
not your normal password).

For **AI natural-language commands** (optional), open **Settings**, turn on the
AI switch and paste your **Claude API key**. Without it, the app still works
using its built-in offline command parser.

---

## 🗣️ How to use

**Command box** (top of the main screen) — type or tap 🎤 to speak, then ▶.

Recognised shapes (offline parser):

- `WhatsApp <name>: <message> at <time>`
- `WhatsApp Business <number> saying <message> in <N> hours`
- `SMS <name> saying <message> tomorrow at 9am`
- `Email <address> subject <subject> body <message> at <time>`

Times are always **Pakistan time**. Understood time phrases include
`at 5:30pm`, `at 17:30`, `in 2 hours`, `after 30 minutes`, `2 hours from now`,
`tomorrow at 9am`, `today at 8pm`. **No time = send now.**

With the **AI** option enabled, you can phrase commands however you like and the
app resolves the details for you (falls back to this when the offline parser
can’t understand a phrase).

**➕ button** — a structured form (pick channel, contact, message, date & time)
if you’d rather not type a sentence. Tap a task to edit it; tap 🗑 to cancel it.

---

## 🔒 Security & privacy

- All tasks are stored **locally** on your phone (SQLite via Room).
- The API key and email password are stored **encrypted**
  (`EncryptedSharedPreferences`) and excluded from backups.
- Nothing is uploaded anywhere except: the messages **you** schedule (sent
  through WhatsApp/SMS/your email server), and — only if you enable AI — the
  command text you type is sent to the Anthropic API to interpret it.

---

## 🧱 Tech / project layout

- **Language/UI:** Kotlin, Android Views + Material 3, minSdk 26, targetSdk 34.
- **Scheduling:** `AlarmManager` exact alarms → `TaskAlarmReceiver` →
  foreground `ExecutionService`; re-armed after reboot by `BootReceiver`.
- **Actions:** `SmsSender` (SmsManager), `EmailSender` (JavaMail/SMTP),
  `WhatsAppSender` (Accessibility auto-tap).
- **Commands:** `OfflineCommandParser` (regex) + `AiCommandParser` (Anthropic
  Messages API, raw HTTPS).
- **Build:** Gradle (wrapper included); CI in `.github/workflows/build-apk.yml`.

```
PhoneAssistant/
├─ app/src/main/java/com/jawad/phoneassistant/
│  ├─ data/         Room entities, DAO, repository
│  ├─ command/      offline + AI command parsing
│  ├─ scheduler/    alarms, boot receiver, execution service
│  ├─ actions/      SMS / Email / WhatsApp senders
│  ├─ service/      Accessibility + Notification-listener services
│  ├─ ui/           MainActivity, Add/Edit, Settings, Onboarding
│  ├─ voice/  util/  security/
│  └─ AssistantApp.kt
└─ app/src/main/AndroidManifest.xml
```

## Building locally (optional)

You don’t need to — GitHub builds the APK for you. But if you have Android
Studio: open the `PhoneAssistant` folder, let it sync, then **Build → Build
APK(s)**, or on the command line from `PhoneAssistant/`:

```bash
./gradlew assembleDebug
# → app/build/outputs/apk/debug/app-debug.apk
```
