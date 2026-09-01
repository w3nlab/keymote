import CryptoKit
import Foundation
import Security

/// Keeps only the encryption key in Keychain. Provider credentials themselves
/// remain in the app configuration as encrypted text.
final class InstallationKeyStore {
    private let service = "app.keymote.remote.configuration"
    private let account = "cloud-credential-encryption-key"

    func encrypt(_ value: String) throws -> String {
        let key = try symmetricKey()
        let sealed = try AES.GCM.seal(Data(value.utf8), using: key)
        guard let data = sealed.combined else { throw SecretStoreError.encryptionFailed }
        return data.base64EncodedString()
    }

    func decrypt(_ value: String) throws -> String {
        guard let data = Data(base64Encoded: value) else { throw SecretStoreError.decryptionFailed }
        let key = try symmetricKey()
        let box = try AES.GCM.SealedBox(combined: data)
        let plain = try AES.GCM.open(box, using: key)
        guard let result = String(data: plain, encoding: .utf8) else { throw SecretStoreError.decryptionFailed }
        return result
    }

    private func symmetricKey() throws -> SymmetricKey {
        if let existing = try read() { return SymmetricKey(data: existing) }
        let data = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        try write(data)
        return SymmetricKey(data: data)
    }

    private func read() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw SecretStoreError.keychain(status) }
        return data
    }

    private func write(_ data: Data) throws {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecretStoreError.keychain(status) }
    }
}

enum SecretStoreError: LocalizedError {
    case encryptionFailed, decryptionFailed, keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encryptionFailed: "Could not encrypt cloud credential"
        case .decryptionFailed: "Could not decrypt cloud credential on this Mac"
        case let .keychain(status): "Keychain error (\(status))"
        }
    }
}
