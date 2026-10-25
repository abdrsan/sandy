package com.abdirakhym.sandy
import android.content.Context
import android.hardware.biometrics.BiometricManager
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

object DeviceKeys {
    private val ks: KeyStore get() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    private const val STORE = "sandy-pairing"
    private const val SIGN = "sandy-approval"
    fun b64(bytes: ByteArray): String = Base64.encodeToString(bytes, Base64.NO_WRAP)
    fun un64(text: String): ByteArray = Base64.decode(text, Base64.NO_WRAP)
    private fun aes(): SecretKey {
        (ks.getKey(STORE,null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(STORE,KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).setKeySize(256).build())
        }.generateKey()
    }
    fun save(context: Context, value: JSONObject) {
        val cipher=Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE,aes()) }
        val bytes=cipher.doFinal(value.toString().toByteArray())
        context.getSharedPreferences("sandy",Context.MODE_PRIVATE).edit().putString("pairing",b64(cipher.iv+bytes)).apply()
    }
    fun load(context: Context): JSONObject? = try {
        val raw=context.getSharedPreferences("sandy",Context.MODE_PRIVATE).getString("pairing",null)?.let(::un64)
        if (raw==null) null else {
            val cipher=Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE,aes(),GCMParameterSpec(128,raw,0,12)) }
            JSONObject(String(cipher.doFinal(raw,12,raw.size-12)))
        }
    } catch (_: Exception) { null }
    fun clear(context: Context) { context.getSharedPreferences("sandy",Context.MODE_PRIVATE).edit().clear().apply(); ks.deleteEntry(SIGN) }
    fun approvalPublic(): ByteArray {
        if (!ks.containsAlias(SIGN)) {
            KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC,"AndroidKeyStore").apply {
                initialize(KeyGenParameterSpec.Builder(SIGN,KeyProperties.PURPOSE_SIGN)
                    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1")).setDigests(KeyProperties.DIGEST_SHA256)
                    .setUserAuthenticationRequired(true)
                    .setUserAuthenticationParameters(0,BiometricManager.Authenticators.BIOMETRIC_STRONG or BiometricManager.Authenticators.DEVICE_CREDENTIAL).build())
            }.generateKeyPair()
        }
        val public=ks.getCertificate(SIGN).publicKey as java.security.interfaces.ECPublicKey
        fun coordinate(value: java.math.BigInteger): ByteArray = value.toByteArray().takeLast(32).toByteArray().let { ByteArray(32-it.size)+it }
        return byteArrayOf(4)+coordinate(public.w.affineX)+coordinate(public.w.affineY)
    }
    fun signature(): Signature = Signature.getInstance("SHA256withECDSA").apply { initSign(ks.getKey(SIGN,null) as PrivateKey) }
}
