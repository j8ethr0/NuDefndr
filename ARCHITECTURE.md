# Architecture

## Data Flow

Photo Library → SensitiveContentAnalysis (on-device) → Vault (encrypted)

## Components

1. Photo Analysis: SensitiveContentAnalysis, on-device, no network calls (app requires iOS 18+)
2. Encryption: ChaCha20-Poly1305 (CryptoKit)
3. Key Storage: iOS Keychain (device-bound)

## Vault Memory Security

- The vault key is read from the Keychain on unlock and held in memory only while the vault is open.
- Backgrounding the app locks the vault and releases the key; decrypted image caches (memory and on-disk thumbnails) are cleared at the same time.
- A separate 60-second grace timer also clears key material and caches if the app is left backgrounded, and latches the vault locked so the next entry requires re-authentication.
- No decrypted photo data is persisted. The key itself is persisted — in the Keychain, device-bound — because a random key that vanished would take the vault with it.

## Vault Storage Metrics

- Reported storage size is computed by summing encrypted file sizes via `FileManager` resource values — vault content is never decrypted to measure usage.
- Only file metadata (byte counts) is read, so the figure is available while the vault is locked without exposing plaintext.

## Vault Storage Metrics

- Reported storage size is computed by summing encrypted file sizes via `FileManager` resource values — vault content is never decrypted to measure usage.
- Only file metadata (byte counts) is read, so the figure is available while the vault is locked without exposing plaintext.

## Security Guarantees

- **Authenticated encryption:** ChaCha20-Poly1305 AEAD. A modified or forged ciphertext fails the Poly1305 tag check and refuses to open.
- **Random keys:** the vault key comes from the system CSPRNG. It is not derived from a PIN, so PIN strength is not the vault's cryptographic strength.
- **Memory hygiene:** decrypted image data is purged when the app backgrounds; nothing decrypted is written to disk.
- **Device-bound:** keys use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — unreadable while the device is locked, and never synced or migrated.
- **Backup posture:** encrypted vault files can appear in an iCloud or device backup; the key cannot. Restored ciphertext is unopenable without a separately exported key backup.
- **Key derivation:** PBKDF2-HMAC-SHA256 — 310,000 iterations for PIN credentials, 600,000 for the passphrase wrapping an exported key-backup file.

Deliberately *not* claimed: forward secrecy. Vault files are sealed with one long-lived key; there is no per-session key exchange and no property that past content stays safe if that key is compromised.

## System Integration: Sensitive Content Warning

- Location: Settings → Privacy & Security → Sensitive Content Warning
- Behavior: If the system feature is disabled or restricted, the analyzer may be unavailable.
- App UX: The app now surfaces the system setting status in Onboarding and Settings and guides users to enable the feature for best results. No data leaves the device.

## Availability Behavior

- We treat SCSensitivityAnalyzer() == nil as "Unavailable" (device/OS unsupported or feature disabled/restricted).
- The transparency code exposes a helper to check availability; production UI uses this to display guidance.