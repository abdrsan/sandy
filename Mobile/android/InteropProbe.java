package com.abdirakhym.sandy.crypto;
import java.util.Base64;
/** Standalone conformance probe; excluded from the Android app build. */
public final class InteropProbe {
    static byte[] d(String s) { return Base64.getDecoder().decode(s); }
    static String b(byte[] x) { return Base64.getEncoder().encodeToString(x); }
    public static void main(String[] a) throws Exception {
        if(a[0].equals("keys")) { var c=new EnvelopeCrypto(); System.out.println(b(c.privateKey())); System.out.println(b(c.publicKey())); }
        else {
            var c=new EnvelopeCrypto(d(a[1]),d(a[2]));
            if(a[0].equals("open")) System.out.println(b(c.open(d(a[3]),d(a[4]),d(a[5]),d(a[6]))));
            else { var x=c.seal(d(a[3]),d(a[4]),d(a[5])); System.out.println(b(x[0]));System.out.println(b(x[1])); }
        }
    }
}
