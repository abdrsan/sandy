package com.abdirakhym.sandy.crypto;
import org.bouncycastle.crypto.AsymmetricCipherKeyPair;
import org.bouncycastle.crypto.hpke.HPKE;
import java.nio.charset.StandardCharsets;

/** RFC 9180 authenticated HPKE. Matches CryptoKit P256_SHA256_AES_GCM_256. */
public final class EnvelopeCrypto {
    private static final byte[] INFO = "sandy/mobile/1/hpke-auth".getBytes(StandardCharsets.UTF_8);
    private final HPKE hpke = new HPKE(HPKE.mode_auth, HPKE.kem_P256_SHA256, HPKE.kdf_HKDF_SHA256, HPKE.aead_AES_GCM256);
    private final AsymmetricCipherKeyPair own;
    public EnvelopeCrypto() { own = hpke.generatePrivateKey(); }
    public EnvelopeCrypto(byte[] privateKey, byte[] publicKey) { own = hpke.deserializePrivateKey(privateKey, publicKey); }
    public byte[] privateKey() { return hpke.serializePrivateKey(own.getPrivate()); }
    public byte[] publicKey() { return hpke.serializePublicKey(own.getPublic()); }
    public byte[][] seal(byte[] recipient, byte[] aad, byte[] payload) throws Exception {
        return hpke.seal(hpke.deserializePublicKey(recipient), INFO, aad, payload, null, null, own);
    }
    public byte[] open(byte[] sender, byte[] encapsulated, byte[] aad, byte[] ciphertext) throws Exception {
        return hpke.open(encapsulated, own, INFO, aad, ciphertext, null, null, hpke.deserializePublicKey(sender));
    }
}
