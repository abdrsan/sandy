package com.abdirakhym.sandy
import android.app.Activity
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.widget.*
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import org.json.JSONObject
import java.util.concurrent.Executors

class MainActivity: Activity() {
    private lateinit var client: PhoneClient
    private lateinit var list: LinearLayout
    private lateinit var status: TextView
    private val worker=Executors.newSingleThreadExecutor()
    private val handler=Handler(Looper.getMainLooper())
    private var active=false
    override fun onCreate(savedInstanceState:Bundle?) { super.onCreate(savedInstanceState);client=PhoneClient(this);render() }
    override fun onResume() { super.onResume();active=true;handler.post(poll) }
    override fun onPause() { active=false;handler.removeCallbacks(poll);super.onPause() }
    override fun onDestroy() { worker.shutdownNow();super.onDestroy() }
    private val poll=object: Runnable { override fun run() {
        if(!active) return
        if(!client.paired) { handler.postDelayed(this,2000);return }
        worker.execute {
            var error=false
            try { client.poll() } catch (_:Exception) { error=true }
            handler.post { if(active) { render();if(error) status.text="Disconnected. Data may be out of date.";handler.postDelayed(this,2000) } }
        }
    } }
    private fun button(title:String,action:()->Unit) { list.addView(Button(this).apply { text=title;setOnClickListener { action() } }) }
    private fun text(value:String) { list.addView(TextView(this).apply { text=value;textSize=15f;setPadding(0,12,0,12);setTextIsSelectable(true) }) }
    private fun render() {
        list=LinearLayout(this).apply { orientation=LinearLayout.VERTICAL;setPadding(32,48,32,32) }
        setContentView(ScrollView(this).apply { addView(list) })
        text("Sandy");status=TextView(this).apply{text=client.status};list.addView(status)
        if(!client.paired) {
            val input=EditText(this).apply { hint="Paste pairing code";inputType=android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE }
            list.addView(input)
            button("Connect") { pair(input.text.toString()) }
            button("Scan QR") { GmsBarcodeScanning.getClient(this).startScan().addOnSuccessListener { it.rawValue?.let(::pair) }.addOnFailureListener{status.text="Scan unavailable; paste the code instead"} }
        } else {
            val pending=client.snapshot.optJSONArray("approvals")
            text("Pending actions")
            if(pending==null || pending.length()==0) text("No pending actions")
            if(pending!=null) for(i in 0 until pending.length()) {
                val request=pending.getJSONObject(i)
                if(request.getLong("expiresAt")<=System.currentTimeMillis()) continue
                text(request.getString("source")+" · "+request.getString("tool"));text(request.getString("context"))
                button("Allow once") { decide(request,"allow") };button("Deny") { decide(request,"deny") }
            }
            text("Agent activity")
            val events=client.snapshot.optJSONArray("activities")
            if(events!=null) for(i in events.length()-1 downTo 0) {
                val event=events.getJSONObject(i);text(event.getString("source")+" · "+event.getString("project")+"\n"+event.getString("state")+" · "+event.getString("operation"))
            }
            button("Enable notifications") {
                if(android.os.Build.VERSION.SDK_INT>=33) requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"),1)
                if(FirebaseApp.initializeApp(this)==null) { status.text="Firebase push configuration is not installed" }
                else { FirebaseMessaging.getInstance().isAutoInitEnabled=true;FirebaseMessaging.getInstance().token.addOnSuccessListener { token -> worker.execute { try { client.registerPush(token) } catch(_:Exception){} } } }
            }
            button("Unpair") { worker.execute { client.clear();handler.post {render()} } }
        }
    }
    private fun pair(code:String) {
        worker.execute { try { client.pair(code);handler.post{render()} } catch(_:Exception) { handler.post{status.text="Invalid code, or screen lock is required"} } }
    }
    private fun decide(request:JSONObject,action:String) {
        try {
            val signature=DeviceKeys.signature()
            val bytes="sandy/decision/1\n${client.room}\n${request.getString("id")}\n${request.getString("digest")}\n${request.getString("challenge")}\n$action".toByteArray()
            BiometricPrompt.Builder(this).setTitle("Sandy: $action once").setSubtitle("Confirm this specific action on your Mac")
                .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG or BiometricManager.Authenticators.DEVICE_CREDENTIAL).build()
                .authenticate(BiometricPrompt.CryptoObject(signature),CancellationSignal(),mainExecutor,object:BiometricPrompt.AuthenticationCallback(){
                    override fun onAuthenticationSucceeded(result:BiometricPrompt.AuthenticationResult) {
                        try {
                            val signer=result.cryptoObject?.signature ?: error("No authenticated signer");signer.update(bytes);val signed=signer.sign()
                            worker.execute { try { client.decision(request,action,signed) } catch(_:Exception){} }
                        } catch(_:Exception) { status.text="Decision not sent. Nothing approved." }
                    }
                })
        } catch(_:Exception) { status.text="Device authentication unavailable; use Mac." }
    }
}
