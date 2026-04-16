# CLAUDE_SECURITY.md — Security & Privacy

## Keychain

```swift
// Core/Security/KeychainService.swift
import Security

actor KeychainService {
    enum KeychainError: LocalizedError {
        case itemNotFound
        case duplicateItem
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .itemNotFound:           return "Keychain item not found."
            case .duplicateItem:          return "Keychain item already exists."
            case .unexpectedStatus(let s): return "Keychain error: \(s)"
            }
        }
    }

    private let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "app") {
        self.service = service
    }

    // Store
    func set(_ data: Data, for key: String, accessible: CFString = kSecAttrAccessibleWhenUnlockedThisDeviceOnly) throws {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      key,
            kSecValueData:        data,
            kSecAttrAccessible:   accessible
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            try update(data, for: key)
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func setString(_ string: String, for key: String) throws {
        guard let data = string.data(using: .utf8) else { return }
        try set(data, for: key)
    }

    // Retrieve
    func data(for key: String) throws -> Data {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw status == errSecItemNotFound ? KeychainError.itemNotFound
                                               : KeychainError.unexpectedStatus(status)
        }
        return data
    }

    func string(for key: String) throws -> String {
        let data = try data(for: key)
        return String(decoding: data, as: UTF8.self)
    }

    // Update
    private func update(_ data: Data, for key: String) throws {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        let attributes: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status != errSecSuccess { throw KeychainError.unexpectedStatus(status) }
    }

    // Delete
    func delete(for key: String) throws {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
```

---

## Biometric Authentication (Face ID / Touch ID)

```swift
import LocalAuthentication

actor BiometricService {
    enum BiometricError: LocalizedError {
        case notAvailable
        case notEnrolled
        case cancelled
        case failed(any Error)

        var errorDescription: String? {
            switch self {
            case .notAvailable: return "Biometric authentication is not available on this device."
            case .notEnrolled:  return "No biometrics are enrolled. Please set up Face ID or Touch ID in Settings."
            case .cancelled:    return "Authentication was cancelled."
            case .failed(let e): return e.localizedDescription
            }
        }
    }

    func canAuthenticate() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func biometricType() -> LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType   // .faceID, .touchID, .opticID, .none
    }

    func authenticate(reason: String) async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw error?.code == LAError.biometryNotEnrolled.rawValue
                ? BiometricError.notEnrolled
                : BiometricError.notAvailable
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            if !success { throw BiometricError.cancelled }
        } catch let laError as LAError {
            switch laError.code {
            case .userCancel, .systemCancel, .appCancel: throw BiometricError.cancelled
            default: throw BiometricError.failed(laError)
            }
        }
    }
}
```

---

## CryptoKit — Encryption & Hashing

```swift
import CryptoKit

struct CryptoService {

    // Symmetric encryption with AES-GCM
    func encrypt(_ data: Data, with key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        return sealedBox.combined!
    }

    func decrypt(_ encryptedData: Data, with key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        return try AES.GCM.open(sealedBox, using: key)
    }

    // Key derivation from password
    func deriveKey(from password: String, salt: Data) -> SymmetricKey {
        let passwordData = Data(password.utf8)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: passwordData),
            salt: salt,
            info: Data("app-encryption-key".utf8),
            outputByteCount: 32
        )
    }

    // Hashing
    func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    // HMAC for data integrity
    func hmac(_ data: Data, key: SymmetricKey) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }

    // Elliptic-curve key pair (for key exchange / signing)
    func generateKeyPair() -> P256.Signing.PrivateKey {
        P256.Signing.PrivateKey()
    }

    func sign(_ data: Data, with key: P256.Signing.PrivateKey) throws -> Data {
        let sig = try key.signature(for: data)
        return sig.derRepresentation
    }

    func verify(_ data: Data, signature: Data, publicKey: P256.Signing.PublicKey) -> Bool {
        guard let sig = try? P256.Signing.ECDSASignature(derRepresentation: signature) else { return false }
        return publicKey.isValidSignature(sig, for: data)
    }
}
```

---

## App Transport Security

```xml
<!-- Info.plist — ATS must NOT be globally disabled -->
<!-- All network calls must use HTTPS -->
<!-- Exceptions only for local dev servers: -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoadsInWebContent</key>
    <false/>
    <!-- Exception for localhost during development only -->
    <key>NSExceptionDomains</key>
    <dict>
        <key>localhost</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
        </dict>
    </dict>
</dict>
```

---

## Privacy Manifest (PrivacyInfo.xcprivacy)

Required by App Store since iOS 17 policy. Keep it accurate and minimal.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>    <!-- true only if using ATT -->

    <key>NSPrivacyCollectedDataTypes</key>
    <array>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypePhotosorVideos</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <false/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
            </array>
        </dict>
    </array>

    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string> <!-- store user settings -->
            </array>
        </dict>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>C617.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

---

## Required Info.plist Usage Descriptions

```xml
<!-- Add ONLY for permissions your app actually uses -->
<key>NSCameraUsageDescription</key>
<string>This app uses the camera to capture photos for your posts.</string>

<key>NSMicrophoneUsageDescription</key>
<string>This app uses the microphone for voice notes and video recording.</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>Your location is used to tag photos and show nearby content.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Background location is used to log your outdoor activity routes.</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>This app reads your photo library to let you choose images to share.</string>

<key>NSPhotoLibraryAddUsageDescription</key>
<string>Photos you capture are saved to your photo library.</string>

<key>NSFaceIDUsageDescription</key>
<string>Face ID is used to securely unlock the app.</string>

<key>NSHealthShareUsageDescription</key>
<string>Health data is read to display your fitness summary.</string>

<key>NSHealthUpdateUsageDescription</key>
<string>Workout data is written to Health to track your activity.</string>

<key>NSSpeechRecognitionUsageDescription</key>
<string>Speech recognition is used to transcribe your voice notes.</string>

<key>NSMotionUsageDescription</key>
<string>Motion sensors are used to count steps and detect activity.</string>
```

---

*See also: `CLAUDE_HARDWARE.md` for biometric hardware, `CLAUDE_DATA.md` for file encryption at rest.*
