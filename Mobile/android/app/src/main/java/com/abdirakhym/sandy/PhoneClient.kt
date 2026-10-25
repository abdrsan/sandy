package com.abdirakhym.sandy
import android.content.Context
import com.abdirakhym.sandy.crypto.EnvelopeCrypto
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.MediaType.Companion.toMediaType
import org.json.JSONObject
import java.net.URI
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.TimeUnit

class PhoneClient(private val context: Context) {
    private var saved=DeviceKeys.load(context)
    private var cursor=0L
    private val seen=linkedSetOf<String>()
    private val http=OkHttpClient.Builder().followRedirects(false).followSslRedirects(false).callTimeout(15,TimeUnit.SECONDS).build()
    var snapshot=JSONObject(); private set
    var status="Scan or paste the pairing code from Mac"; private set
    val paired get() = saved!=null
    val room get() = saved?.getJSONObject("pairing")?.getString("room")
    private val pairing get() = saved!!.getJSONObject("pairing")
    private fun crypto(): EnvelopeCrypto = EnvelopeCrypto(DeviceKeys.un64(saved!!.getString("private")),DeviceKeys.un64(saved!!.getString("public")))
    private fun fingerprint(bytes: ByteArray)=MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it.toInt() and 255) }
    fun pair(text: String) {
        require(text.toByteArray().size<4096)
        val p=JSONObject(text); val url=URI(p.getString("relay"))
        require(url.scheme=="https" && !url.host.isNullOrEmpty() && url.userInfo==null && url.query==null && url.fragment==null && (url.path.isNullOrEmpty() || url.path=="/"))
        require(p.getInt("version")==1 && p.getString("room").matches(Regex("[A-Za-z0-9_-]{22,64}")) && p.getString("token").length in 43..128)
        require(DeviceKeys.un64(p.getString("macKey")).size==65)
        DeviceKeys.approvalPublic()
        val key=EnvelopeCrypto()
        saved=JSONObject().put("pairing",p).put("private",DeviceKeys.b64(key.privateKey())).put("public",DeviceKeys.b64(key.publicKey())).put("trusted",false)
        DeviceKeys.save(context,saved!!); cursor=0;seen.clear();status="Compare fingerprint on Mac: "+fingerprint(key.publicKey())
    }
    fun clear() { saved=null;snapshot=JSONObject();cursor=0;seen.clear();DeviceKeys.clear(context) }
    private fun request(path: String, body: JSONObject?=null): JSONObject {
        val request=Request.Builder().url(pairing.getString("relay").trimEnd('/')+"/v1/rooms/"+pairing.getString("room")+path)
            .header("Authorization","Bearer "+pairing.getString("token")).header("X-Sandy-Role","phone")
        if(body!=null) request.post(body.toString().toRequestBody("application/json".toMediaType()))
        return http.newCall(request.build()).execute().use { response ->
            check(response.code==200); val input=response.body ?: error("No response")
            input.byteStream().use { stream ->
                val output=java.io.ByteArrayOutputStream();val chunk=ByteArray(16384)
                while(true) {val n=stream.read(chunk);if(n<0)break;check(output.size()+n<=2500000);output.write(chunk,0,n)}
                JSONObject(output.toString("UTF-8"))
            }
        }
    }
    fun send(message: JSONObject) {
        val key=crypto();val id=UUID.randomUUID().toString();val at=System.currentTimeMillis()
        val sender=DeviceKeys.b64(key.publicKey());val room=pairing.getString("room")
        val aad="sandy/mobile/1\n$room\n$id\n$at\n$sender".toByteArray()
        val sealed=key.seal(DeviceKeys.un64(pairing.getString("macKey")),aad,message.toString().toByteArray())
        val envelope=JSONObject().put("version",1).put("room",room).put("id",id).put("sentAt",at).put("senderKey",sender)
            .put("encapsulatedKey",DeviceKeys.b64(sealed[1])).put("ciphertext",DeviceKeys.b64(sealed[0]))
        request("/messages",JSONObject().put("envelope",envelope).put("notify",false))
    }
    fun poll() {
        if(!paired) return
        if(!saved!!.optBoolean("trusted")) {
            send(JSONObject().put("type","hello").put("name",android.os.Build.MODEL.take(60)).put("approvalKey",DeviceKeys.b64(DeviceKeys.approvalPublic())))
            status="Compare fingerprint on Mac: "+fingerprint(crypto().publicKey())
        }
        val response=request("/messages?after=$cursor");val messages=response.getJSONArray("messages")
        for(i in 0 until messages.length()) try {
            val e=messages.getJSONObject(i);val id=e.getString("id")
            require(e.getInt("version")==1 && e.getString("room")==pairing.getString("room") && e.getString("senderKey")==pairing.getString("macKey"))
            require(kotlin.math.abs(System.currentTimeMillis()-e.getLong("sentAt"))<=120000 && !seen.contains(id))
            val aad="sandy/mobile/1\n${pairing.getString("room")}\n$id\n${e.getLong("sentAt")}\n${e.getString("senderKey")}".toByteArray()
            val plain=crypto().open(DeviceKeys.un64(e.getString("senderKey")),DeviceKeys.un64(e.getString("encapsulatedKey")),aad,DeviceKeys.un64(e.getString("ciphertext")))
            val message=JSONObject(String(plain));seen.add(id);if(seen.size>4096) seen.remove(seen.first())
            if(message.getString("type")=="snapshot") {
                snapshot=message;saved!!.put("trusted",true);DeviceKeys.save(context,saved!!);status="Connected to Mac"
            } else if(message.getString("type")=="result") { status="Mac: "+message.optString("result");snapshot.remove("approvals") }
        } catch (_: Exception) { /* Unauthenticated messages never reach the UI. */ }
        cursor=response.getLong("cursor")
    }
    fun registerPush(token: String) { if(paired) {val result=request("/push",JSONObject().put("platform","fcm").put("token",token));if(!result.optBoolean("configured")) status="Push sender is not configured on the relay yet"} }
    fun decision(request: JSONObject, action: String, signature: ByteArray) {
        require(request.getLong("expiresAt")>System.currentTimeMillis())
        val decision=JSONObject().put("requestID",request.getString("id")).put("digest",request.getString("digest"))
            .put("challenge",request.getString("challenge")).put("action",action).put("signature",DeviceKeys.b64(signature))
        send(JSONObject().put("type","decision").put("decision",decision));status="Decision sent; waiting for Mac confirmation"
    }
}
