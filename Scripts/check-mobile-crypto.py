#!/usr/bin/env python3
"""Check CryptoKit <-> Bouncy Castle authenticated HPKE. Uses random test keys only."""
import argparse, base64, json, os, pathlib, subprocess, tempfile
p=argparse.ArgumentParser();p.add_argument('--bc-jar',required=True);p.add_argument('--java-home',default=os.environ.get('JAVA_HOME','/opt/homebrew/opt/openjdk'));a=p.parse_args()
root=pathlib.Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='sandy-crypto-') as temp:
 d=pathlib.Path(temp)
 (d/'main.swift').write_text('''import CryptoKit
import Foundation
let a=Array(CommandLine.arguments.dropFirst())
if a[0]=="keys" {
 let k=P256.KeyAgreement.PrivateKey();print(k.rawRepresentation.base64EncodedString());print(k.publicKey.x963Representation.base64EncodedString())
} else {
 let k=try P256.KeyAgreement.PrivateKey(rawRepresentation:Data(base64Encoded:a[1])!)
 if a[0]=="seal" {
  let e=try MobileCrypto.seal(MobileMessage(type:"hello",name:"conformance"),room:"test-room",sender:k,recipient:Data(base64Encoded:a[2])!)
  print(String(data:try JSONEncoder().encode(e),encoding:.utf8)!)
 } else {
  let e=try JSONDecoder().decode(MobileEnvelope.self,from:Data(a[2].utf8))
  print(try MobileCrypto.open(e,room:"test-room",recipient:k,trustedSender:Data(base64Encoded:a[3])!).type)
 }
}
''')
 subprocess.run(['swiftc','-module-cache-path',str(root/'.build/localization-module-cache'),str(root/'Sources/SandyMobileCore/MobileProtocol.swift'),str(d/'main.swift'),'-o',str(d/'probe')],check=True)
 java=str(pathlib.Path(a.java_home)/'bin/java');javac=str(pathlib.Path(a.java_home)/'bin/javac')
 subprocess.run([javac,'-cp',a.bc_jar,'-d',temp,str(root/'Mobile/android/app/src/main/java/com/abdirakhym/sandy/crypto/EnvelopeCrypto.java'),str(root/'Mobile/android/InteropProbe.java')],check=True)
 def swift(*args): return subprocess.check_output([str(d/'probe'),*args],text=True).strip().splitlines()
 def jvm(*args): return subprocess.check_output([java,'-cp',temp+os.pathsep+a.bc_jar,'com.abdirakhym.sandy.crypto.InteropProbe',*args],text=True).strip().splitlines()
 def b64(x):return base64.b64encode(x).decode()
 sk,pk=swift('keys');js,jp=jvm('keys')
 env=json.loads(swift('seal',sk,jp)[0]);aad=f'sandy/mobile/1\n{env["room"]}\n{env["id"]}\n{env["sentAt"]}\n{env["senderKey"]}'.encode()
 plain=base64.b64decode(jvm('open',js,jp,pk,env['encapsulatedKey'],b64(aad),env['ciphertext'])[0]);assert json.loads(plain)['name']=='conformance'
 ct,enc=jvm('seal',js,jp,pk,b64(aad.replace(pk.encode(),jp.encode())),b64(b'{"type":"hello","name":"android"}'))
 env.update(senderKey=jp,ciphertext=ct,encapsulatedKey=enc)
 assert swift('open',sk,json.dumps(env),jp)==['hello']
 print('PASS: CryptoKit → Android and Android → CryptoKit authenticated HPKE')
