import CommonCrypto
import Foundation
import Security

/// Unseals tokens Cursor encrypts at rest with Electron's safeStorage
/// (`cursor.storage.authTokenEncryptionAtRest`, Cursor 3.27.22+), which turns
/// `cursorAuth/accessToken` into `cursor-safe-storage:v1:<ciphertext>`.
///
/// On macOS that is Chromium's "v10" scheme: AES-128-CBC under a key derived
/// from a random password Cursor keeps in the login Keychain as
/// "Cursor Safe Storage". Reading that item makes macOS ask once; choosing
/// "Always Allow" keeps every later refresh silent.
enum CursorSafeStorage {
    static let prefix = "cursor-safe-storage:v1:"

    private static let keychainService = "Cursor Safe Storage"
    private static let versionTag = Data("v10".utf8)
    private static let salt = Data("saltysalt".utf8)
    private static let iterations: UInt32 = 1003
    private static let keyLength = kCCKeySizeAES128

    /// Derived once per launch so the Keychain is only consulted once.
    private static var cachedKey: Data?

    /// The plaintext token inside a sealed value (prefix already stripped),
    /// or nil if the Keychain is unavailable or the value doesn't decrypt.
    static func unseal(_ sealed: String) -> String? {
        guard let key = cachedKey ?? keychainPassword().flatMap(deriveKey) else { return nil }
        guard let token = unseal(sealed, key: key) else {
            // Cursor may have rotated its password; re-read it next time.
            cachedKey = nil
            return nil
        }
        cachedKey = key
        return token
    }

    static func unseal(_ sealed: String, key: Data) -> String? {
        guard let payload = decodePayload(sealed) else { return nil }
        let ciphertext = payload.starts(with: versionTag) ? payload.dropFirst(versionTag.count) : payload[...]
        guard let plain = aes128CBCDecrypt(Data(ciphertext), key: key),
              let token = String(data: plain, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else { return nil }
        return token
    }

    static func deriveKey(password: Data) -> Data? {
        var key = Data(count: keyLength)
        let status = key.withUnsafeMutableBytes { out in
            password.withUnsafeBytes { pw in
                salt.withUnsafeBytes { s in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                         pw.baseAddress?.assumingMemoryBound(to: Int8.self), password.count,
                                         s.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), iterations,
                                         out.baseAddress?.assumingMemoryBound(to: UInt8.self), keyLength)
                }
            }
        }
        return status == kCCSuccess ? key : nil
    }

    private static func keychainPassword() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    /// The ciphertext is text in the database; accept base64 (either alphabet) or hex.
    private static func decodePayload(_ text: String) -> Data? {
        var b64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        if let data = Data(base64Encoded: b64) { return data }

        guard text.count % 2 == 0, text.allSatisfy(\.isHexDigit) else { return nil }
        var data = Data(capacity: text.count / 2)
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    private static func aes128CBCDecrypt(_ data: Data, key: Data) -> Data? {
        // Chromium uses a fixed IV of 16 spaces for v10.
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var out = Data(count: data.count + kCCBlockSizeAES128)
        var moved = 0
        let outCapacity = out.count
        let status = out.withUnsafeMutableBytes { outPtr in
            data.withUnsafeBytes { inPtr in
                key.withUnsafeBytes { keyPtr in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(kCCOptionPKCS7Padding),
                                keyPtr.baseAddress, key.count, ivPtr.baseAddress,
                                inPtr.baseAddress, data.count,
                                outPtr.baseAddress, outCapacity, &moved)
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return out.prefix(moved)
    }
}
