import Foundation
import Security

enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
}

final class KeychainHelper {
    static let shared = KeychainHelper()

    func set(_ value: Data, for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var newItem = query
        newItem[kSecValueData as String] = value
        let status = SecItemAdd(newItem as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    func get(for key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        return result as? Data
    }

    func setString(_ value: String, for key: String) throws {
        try set(Data(value.utf8), for: key)
    }

    func getString(for key: String) throws -> String? {
        guard let data = try get(for: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}


