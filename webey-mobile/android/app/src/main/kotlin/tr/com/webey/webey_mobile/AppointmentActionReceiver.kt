package tr.com.webey.webey_mobile

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONObject

class AppointmentActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pendingResult = goAsync()
        Thread {
            val notificationId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, 0)
            val appointmentId = intent.getStringExtra(EXTRA_APPOINTMENT_ID).orEmpty()
            val action = intent.getStringExtra(EXTRA_ACTION).orEmpty()
            val token = intent.getStringExtra(EXTRA_ACTION_TOKEN).orEmpty()
            val endpoint = intent.getStringExtra(EXTRA_ENDPOINT)
                ?: "/api/mobile/business/appointment-action.php"

            Log.d(
                TAG,
                "received action=$action appointment_id=$appointmentId endpoint=$endpoint token_present=${token.isNotBlank()}"
            )

            val manager = context.getSystemService(NotificationManager::class.java)
            if (notificationId != 0) {
                manager.cancel(notificationId)
            }

            val success = try {
                postAction(appointmentId, action, token, endpoint)
            } catch (error: Exception) {
                Log.e(TAG, "appointment action failed", error)
                false
            }

            val title = when {
                success && action == "approve" -> "Randevu onaylandı"
                success && action == "reject" -> "Randevu reddedildi"
                else -> "İşlem tamamlanamadı"
            }
            showResultNotification(context, manager, title)
            pendingResult.finish()
        }.start()
    }

    private fun postAction(
        appointmentId: String,
        action: String,
        token: String,
        endpoint: String
    ): Boolean {
        if (appointmentId.isBlank() || action.isBlank() || token.isBlank()) {
            return false
        }

        val url = URL(resolveEndpoint(endpoint))
        val connection = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 12000
            readTimeout = 20000
            doOutput = true
            setRequestProperty("Accept", "application/json")
            setRequestProperty("Content-Type", "application/json; charset=utf-8")
        }

        val payload = JSONObject().apply {
            put("appointment_id", appointmentId)
            put("action", action)
            put("action_token", token)
        }.toString()

        OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { writer ->
            writer.write(payload)
        }

        val status = connection.responseCode
        val stream = if (status in 200..299) connection.inputStream else connection.errorStream
        val body = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
        Log.d(TAG, "appointment action status=$status body=$body")
        connection.disconnect()
        return status in 200..299
    }

    private fun resolveEndpoint(endpoint: String): String {
        return if (endpoint.startsWith("http://") || endpoint.startsWith("https://")) {
            endpoint
        } else {
            "https://webey.com.tr" + if (endpoint.startsWith("/")) endpoint else "/$endpoint"
        }
    }

    private fun showResultNotification(
        context: Context,
        manager: NotificationManager,
        title: String
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    "bookings",
                    "Randevular",
                    NotificationManager.IMPORTANCE_HIGH
                )
            )
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, "bookings")
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        builder
            .setSmallIcon(R.drawable.ic_stat_webey)
            .setContentTitle(title)
            .setAutoCancel(true)
            .setShowWhen(true)
        manager.notify(System.currentTimeMillis().toInt(), builder.build())
    }

    companion object {
        const val EXTRA_NOTIFICATION_ID = "notification_id"
        const val EXTRA_APPOINTMENT_ID = "appointment_id"
        const val EXTRA_ACTION = "action"
        const val EXTRA_ACTION_TOKEN = "action_token"
        const val EXTRA_ENDPOINT = "endpoint"
        private const val TAG = "WebeyApptAction"
    }
}
