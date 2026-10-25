import Foundation
import Security

public enum MobileKeychain {
    public static func read(_ account: String, service: String = "com.abdirakhym.sandy.mobile") throws -> Data? {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,
            kSecAttrAccount as String:account,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw MobileFailure.invalid }
        return data
    }
    public static func write(_ data: Data, account: String, service: String = "com.abdirakhym.sandy.mobile") throws {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account]
        let attributes: [String: Any] = [kSecValueData as String:data,kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query.merging(attributes, uniquingKeysWith: { _, new in new }) as CFDictionary, nil) == errSecSuccess else { throw MobileFailure.invalid }
        } else if status != errSecSuccess { throw MobileFailure.invalid }
    }
    public static func remove(_ account: String, service: String = "com.abdirakhym.sandy.mobile") {
        SecItemDelete([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account] as CFDictionary)
    }
}
