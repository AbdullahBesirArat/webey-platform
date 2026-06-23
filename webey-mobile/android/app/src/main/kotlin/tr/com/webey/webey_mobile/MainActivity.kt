package tr.com.webey.webey_mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createWebeyNotificationChannels()
    }

    private fun createWebeyNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = getSystemService(NotificationManager::class.java)
        listOf("bookings", "reviews", "payments", "system").forEach { base ->
            listOf("sound", "vibrate", "silent").forEach { mode ->
                manager.createNotificationChannel(buildChannel(base, mode))
            }
        }
        manager.createNotificationChannel(buildChannel("bookings", "sound", legacyId = "bookings"))
    }

    private fun buildChannel(base: String, mode: String, legacyId: String? = null): NotificationChannel {
        val id = legacyId ?: "${base}_${mode}_v1"
        val name = when (base) {
            "reviews" -> "Yorumlar"
            "payments" -> "Ödemeler"
            "system" -> "Sistem"
            else -> "Randevular"
        }
        val channel = NotificationChannel(id, name, NotificationManager.IMPORTANCE_HIGH)
        when (mode) {
            "silent" -> {
                channel.setSound(null, null)
                channel.enableVibration(false)
            }
            "vibrate" -> {
                channel.setSound(null, null)
                channel.enableVibration(true)
            }
            else -> {
                val soundUri = Uri.parse("android.resource://$packageName/${R.raw.webey_notification}")
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                channel.setSound(soundUri, attrs)
                channel.enableVibration(true)
            }
        }
        return channel
    }
}
