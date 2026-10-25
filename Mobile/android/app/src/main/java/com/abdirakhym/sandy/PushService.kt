package com.abdirakhym.sandy
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
class PushService: FirebaseMessagingService() {
    override fun onNewToken(token:String) { try { PhoneClient(this).registerPush(token) } catch(_:Exception){} }
    override fun onMessageReceived(message:RemoteMessage) {
        val manager=getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("agents","Agent updates",NotificationManager.IMPORTANCE_DEFAULT))
        val open=PendingIntent.getActivity(this,0,Intent(this,MainActivity::class.java),PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification=Notification.Builder(this,"agents").setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("Sandy").setContentText("An agent has an update. Open Sandy to review.").setContentIntent(open).setAutoCancel(true).build()
        try { manager.notify(1,notification) } catch(_:SecurityException){}
    }
}
