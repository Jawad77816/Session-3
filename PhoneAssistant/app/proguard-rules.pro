# Keep JavaMail / activation classes (reflection-heavy).
-keep class com.sun.mail.** { *; }
-keep class javax.mail.** { *; }
-keep class javax.activation.** { *; }
-keep class com.sun.activation.** { *; }
-dontwarn javax.**
-dontwarn com.sun.**

# Room
-keep class androidx.room.** { *; }
