package tr.com.webey.webey_mobile

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class WebeyFirebaseMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        val type = data["type"].orEmpty()
        Log.d(TAG, "onMessageReceived type=$type data_keys=${data.keys.joinToString(",")} hasNotificationPayload=${message.notification != null}")

        // Desteklenen tipler: booking (onay/red aksiyonlu), deposit_sent
        // (müşteri "IBAN'a parayı attım" — işletme heads-up bildirimi görmeli),
        // appointment_status / deposit_status (müşteri tarafı durum pushları).
        // Bu servis foreground + background her durumda sistem bildirimi
        // gösterir; uygulama açıkken de telefon bildirimi hissi verir.
        if (type !in SUPPORTED_TYPES) {
            Log.d(TAG, "ignored type=$type")
            return
        }

        val appointmentId = data["appointment_id"].orEmpty()
        if (type == "booking" && appointmentId.isBlank()) {
            Log.w(TAG, "booking push missing appointment_id, aborting")
            return
        }

        val title = data["notification_title"]?.takeIf { it.isNotBlank() }
            ?: message.notification?.title
            ?: defaultTitle(type)
        val body = data["notification_body"]?.takeIf { it.isNotBlank() }
            ?: message.notification?.body
            ?: buildFallbackBody(data)
        // Onay/Red aksiyonları yalnızca yeni randevu (booking) bildirimi için;
        // deposit_sent akışında işletme uygulama içinden "Para geldi" der.
        val approveToken = if (type == "booking") data["approve_token"].orEmpty() else ""
        val rejectToken = if (type == "booking") data["reject_token"].orEmpty() else ""
        val endpoint = data["action_endpoint"]?.takeIf { it.isNotBlank() }
            ?: "/api/mobile/business/appointment-action.php"
        val channelId = data["channel_id"]?.takeIf { it.isNotBlank() }
            ?: "bookings_sound_v1"

        Log.d(TAG, "type=$type appointment_id=$appointmentId title='$title'")

        showBookingNotification(
            appointmentId = appointmentId.ifBlank { message.messageId ?: type },
            title = title,
            body = body,
            approveToken = approveToken,
            rejectToken = rejectToken,
            endpoint = endpoint,
            channelId = channelId
        )
    }

    private fun defaultTitle(type: String): String = when (type) {
        "deposit_sent" -> "Yeni randevu bildirimi"
        "deposit_status" -> "Kapora durumu güncellendi"
        "appointment_status" -> "Randevu durumu güncellendi"
        else -> "Yeni randevunuz var"
    }

    private fun buildFallbackBody(data: Map<String, String>): String {
        val parts = listOf(
            data["customer_name"].orEmpty(),
            data["service_name"].orEmpty(),
            data["appointment_start"].orEmpty()
        ).filter { it.isNotBlank() }
        return if (parts.isEmpty()) "Yeni bir randevu oluşturuldu." else parts.joinToString(" · ")
    }

    private fun showBookingNotification(
        appointmentId: String,
        title: String,
        body: String,
        approveToken: String,
        rejectToken: String,
        endpoint: String,
        channelId: String
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        ensureWebeyChannel(channelId)
        val notificationId = appointmentId.hashCode()
        val contentIntent = PendingIntent.getActivity(
            this,
            notificationId,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setSmallIcon(R.drawable.ic_stat_webey)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .setShowWhen(true)

        var actionsAdded = 0
        if (approveToken.isNotBlank()) {
            builder.addAction(
                R.drawable.ic_stat_webey,
                "Onayla",
                actionPendingIntent(notificationId, appointmentId, "approve", approveToken, endpoint)
            )
            actionsAdded++
        }
        if (rejectToken.isNotBlank()) {
            builder.addAction(
                R.drawable.ic_stat_webey,
                "Reddet",
                actionPendingIntent(notificationId + 1, appointmentId, "reject", rejectToken, endpoint)
            )
            actionsAdded++
        }
        Log.d(TAG, "actions added=${actionsAdded > 0} count=$actionsAdded")

        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(notificationId, builder.build())
    }

    private fun actionPendingIntent(
        requestCode: Int,
        appointmentId: String,
        action: String,
        token: String,
        endpoint: String
    ): PendingIntent {
        val intent = Intent(this, AppointmentActionReceiver::class.java).apply {
            putExtra(AppointmentActionReceiver.EXTRA_NOTIFICATION_ID, appointmentId.hashCode())
            putExtra(AppointmentActionReceiver.EXTRA_APPOINTMENT_ID, appointmentId)
            putExtra(AppointmentActionReceiver.EXTRA_ACTION, action)
            putExtra(AppointmentActionReceiver.EXTRA_ACTION_TOKEN, token)
            putExtra(AppointmentActionReceiver.EXTRA_ENDPOINT, endpoint)
        }
        return PendingIntent.getBroadcast(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun ensureWebeyChannel(channelId: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val normalized = normalizeChannelId(channelId)
        val name = when {
            normalized.startsWith("reviews_") -> "Yorumlar"
            normalized.startsWith("payments_") -> "Ödemeler"
            normalized.startsWith("system_") -> "Sistem"
            else -> "Randevular"
        }
        val channel = NotificationChannel(
            normalized,
            name,
            NotificationManager.IMPORTANCE_HIGH
        )
        when {
            normalized.endsWith("_silent_v1") -> {
                channel.setSound(null, null)
                channel.enableVibration(false)
            }
            normalized.endsWith("_vibrate_v1") -> {
                channel.setSound(null, null)
                channel.enableVibration(true)
            }
            else -> {
                val soundUri = Uri.parse("android.resource://$packageName/${R.raw.webey_notification}")
                val audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                channel.setSound(soundUri, audioAttributes)
                channel.enableVibration(true)
            }
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun normalizeChannelId(channelId: String): String {
        val allowed = setOf(
            "bookings_sound_v1", "bookings_vibrate_v1", "bookings_silent_v1",
            "reviews_sound_v1", "reviews_vibrate_v1", "reviews_silent_v1",
            "payments_sound_v1", "payments_vibrate_v1", "payments_silent_v1",
            "system_sound_v1", "system_vibrate_v1", "system_silent_v1"
        )
        return if (allowed.contains(channelId)) channelId else "bookings_sound_v1"
    }

    companion object {
        private const val TAG = "WebeyFCM"
        private val SUPPORTED_TYPES = setOf(
            "booking", "deposit_sent", "appointment_status", "deposit_status"
        )
    }
}
