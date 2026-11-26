package ma.foorsa.crm

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * The CRM's notifications on Android. The CRM sends data-only messages
 * (fcmPush.service.ts: title, body, type, route), so the app draws them:
 * a call in its own high-priority channel, everything else as a message.
 * A tap opens the app on the message's route.
 */
class CrmMessagingService : FirebaseMessagingService() {
    companion object {
        const val EXTRA_ROUTE = "foorsa_crm_route"
        private const val CHANNEL_MESSAGES = "crm_messages"
        private const val CHANNEL_CALLS = "crm_calls"
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        val title = data["title"]?.takeIf { it.isNotBlank() } ?: message.notification?.title ?: "Foorsa CRM"
        val body = data["body"] ?: message.notification?.body ?: ""
        val isCall = data["type"] == "call"
        val route = data["route"]?.takeIf { it.startsWith("/") } ?: "/"
        show(this, title, body, isCall, route, data["tag"] ?: data["route"] ?: title)
    }

    override fun onNewToken(token: String) {
        // The CRM registers the token again the next time the app is opened
        // and someone is signed in (registerNativePushDevice).
    }

    private fun show(context: Context, title: String, body: String, isCall: Boolean, route: String, tag: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        ensureChannels(context)
        val open = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_ROUTE, route)
        }
        val pending = PendingIntent.getActivity(
            context,
            route.hashCode(),
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, if (isCall) CHANNEL_CALLS else CHANNEL_MESSAGES)
            .setSmallIcon(R.mipmap.ic_launcher_foreground)
            .setColor(0xFF041229.toInt())
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(pending)
            .setCategory(if (isCall) NotificationCompat.CATEGORY_CALL else NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(if (isCall) NotificationCompat.PRIORITY_MAX else NotificationCompat.PRIORITY_HIGH)
            .build()
        NotificationManagerCompat.from(context).notify(tag.hashCode(), notification)
    }

    private fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_MESSAGES, "Messages", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Team chat and CRM messages"
            }
        )
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_CALLS, "Calls", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Incoming team and office calls"
            }
        )
    }
}
