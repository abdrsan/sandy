import CryptoKit
import Foundation
import Security

/// Only this key signs decisions. Its private-key operation is protected by the
/// device owner check; transport decryption never substitutes for that check.
enum ApprovalKey {
    static func key(room: String, create: Bool) throws -> SecKey {
        let tag=Data(("com.abdirakhym.sandy.approval."+room).utf8)
        let query: [String:Any] = [kSecClass as String:kSecClassKey,kSecAttrApplicationTag as String:tag,
            kSecAttrKeyType as String:kSecAttrKeyTypeECSECPrimeRandom,kSecReturnRef as String:true,
            kSecUseOperationPrompt as String:"Confirm this agent action in Sandy"]
        var found: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary,&found)==errSecSuccess { return found as! SecKey }
        guard create, let access=SecAccessControlCreateWithFlags(nil,kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage,.userPresence],nil) else { throw CocoaError(.userCancelled) }
        var attributes: [String:Any] = [kSecAttrKeyType as String:kSecAttrKeyTypeECSECPrimeRandom,kSecAttrKeySizeInBits as String:256,
            kSecPrivateKeyAttrs as String:[kSecAttrIsPermanent as String:true,kSecAttrApplicationTag as String:tag,kSecAttrAccessControl as String:access]]
        if SecureEnclave.isAvailable { attributes[kSecAttrTokenID as String]=kSecAttrTokenIDSecureEnclave }
        var error: Unmanaged<CFError>?
        guard let key=SecKeyCreateRandomKey(attributes as CFDictionary,&error) else { throw error!.takeRetainedValue() }
        return key
    }
    static func publicKey(room: String) throws -> Data {
        let key=try key(room:room,create:true)
        guard let publicKey=SecKeyCopyPublicKey(key),let data=SecKeyCopyExternalRepresentation(publicKey,nil) else { throw CocoaError(.fileReadUnknown) }
        return data as Data
    }
    static func sign(_ data: Data, room: String) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let signature=SecKeyCreateSignature(try key(room:room,create:false),.ecdsaSignatureMessageX962SHA256,data as CFData,&error) else {
            if let error { throw error.takeRetainedValue() }; throw CocoaError(.userCancelled)
        }
        return signature as Data
    }
}
