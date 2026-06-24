# Architecture

## Data Flow

Photo Library → SensitiveContentAnalysis (on-device) → Vault (encrypted)

## Components

1. Photo Analysis: SensitiveContentAnalysis (iOS 17+), zero network
2. Encryption: ChaCha20-Poly1305 (CryptoKit)
3. Key Storage: iOS Keychain (device-bound)

## Vault Memory Security

- Ephemeral decryption: keys purged from RAM on scene phase transition
- Background timeout: optimized delay before volatile memory scrubbing
- Zero-persistence: no decrypted data survives app suspension

## Vault Storage Metrics

- Reported storage size is computed by summing encrypted file sizes via `FileManager` resource values — vault content is never decrypted to measure usage.
- Only file metadata (byte counts) is read, so the figure is available while the vault is locked without exposing plaintext.

## Security Guarantees

- Authenticated encryption: ChaCha20-Poly1305 AEAD prevents tampering and forged ciphertext
- Forward secrecy: ephemeral keys never written to disk
- Memory isolation: decrypted data purged on background transition
- Device-bound: keys use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- No cloud escape: vault data excluded from iCloud backup and device-to-device sync
- Key derivation: PBKDF2 with 100k iterations, SHA-256

## System Integration: Sensitive Content Warning

- Location: Settings → Privacy & Security → Sensitive Content Warning
- Behavior: If the system feature is disabled or restricted, the analyzer may be unavailable.
- App UX: The app now surfaces the system setting status in Onboarding and Settings and guides users to enable the feature for best results. No data leaves the device.

## Availability Behavior

- We treat SCSensitivityAnalyzer() == nil as "Unavailable" (device/OS unsupported or feature disabled/restricted).
- The transparency code exposes a helper to check availability; production UI uses this to display guidance.