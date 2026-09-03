# Architecture

## Data Flow

Photo Library → SensitiveContentAnalysis (on-device) → Vault (encrypted)

Camera → AVCapturePhotoOutput → memory → Vault (encrypted)

The second path never touches the photo library. A photo captured in the app has
no plaintext form on disk at any point — it is stripped and sealed from the `Data`
the capture delivers.

## Components

1. Photo Analysis: SensitiveContentAnalysis, on-device, no network calls (app requires iOS 18+)
2. Capture: AVFoundation, in-app only — no `PHPhotoLibrary` write, no temporary file
3. Encryption: ChaCha20-Poly1305 (CryptoKit)
4. Key Storage: iOS Keychain (device-bound)

## Vault Memory Security

- The vault key is read from the Keychain on unlock and held in memory only while the vault is open.
- Backgrounding the app locks the vault and releases the key. Decrypted images held in memory are dropped at the same time.
- The on-disk thumbnail cache is *not* deleted on lock, and does not need to be: each thumbnail is sealed with ChaCha20-Poly1305 under a key derived from the vault key (HKDF-SHA256), and locking releases that key too. What stays on disk is ciphertext no key on the device can open until the vault is unlocked again — the same bar the vault's own files meet. Keeping it is what stops the second open of the day costing what the first one did.
- The thumbnail cache *is* deleted outright by the paths that end the vault rather than the session: destroying the vault, wiping the decoy, clearing the vault, and the one-time migration off the older unencrypted cache format.
- A separate 60-second grace timer also releases key material if the app is left backgrounded, and latches the vault locked so the next entry requires re-authentication.
- No decrypted photo data is persisted. The key itself is persisted — in the Keychain, device-bound — because a random key that vanished would take the vault with it.

## Network

There is no backend. Two requests leave the device, and this is all of them:

- **Subscription validation (RevenueCat).** Sends an anonymous subscriber identifier, receives entitlement status.
- **The FAQ page.** Opening the FAQ screen fetches `nudefndr.com/faq.html` (or the `ja`/`th`/`zh` page for the app's language) so the in-app FAQ is the website's, not a second copy. Fetched over an ephemeral `URLSession` with no cookie or credential storage, inlined into one file and rendered with `baseURL: nil` so the web view issues nothing of its own, and cached so the screen works offline. Discloses an IP, a generic user-agent and which language page was asked for.

No analytics, crash reporting, remote config or push. `isNetworkAccessAllowed` on some read paths pulls the user's own photo from the iCloud library they enabled — inbound, nothing uploaded. The Location Cleaner names places from coordinates on-device rather than geocoding, which would send library-derived coordinates outbound.

## Vault Storage Metrics

- Reported storage size is computed by summing encrypted file sizes via `FileManager` resource values — vault content is never decrypted to measure usage.
- Only file metadata (byte counts) is read, so the figure is available while the vault is locked without exposing plaintext.

## Security Guarantees

- **Authenticated encryption:** ChaCha20-Poly1305 AEAD. A modified or forged ciphertext fails the Poly1305 tag check and refuses to open.
- **Random keys:** the vault key comes from the system CSPRNG. It is not derived from a PIN, so PIN strength is not the vault's cryptographic strength.
- **Nothing decrypted on disk:** decrypted image data is purged when the app backgrounds, and every derived artefact that does reach disk — vault files and thumbnails alike — is sealed. No plaintext copy of a vault photo is written anywhere at any point.
- **One intake path:** photos imported from the library and photos taken with the in-app camera converge on a single function that strips metadata, seals with ChaCha20-Poly1305 and writes with complete file protection. This was two separate implementations before 2.6.2. One path means the metadata guarantee cannot hold on one route and lapse on the other, and it is why `.completeFileProtection` is structural rather than a line each caller has to remember.
- **Captured photos have no original:** vaulting a photo you already had leaves the library copy for you to delete, and deletion means thirty days in Recently Deleted. A photo taken in the app never had a library copy, so there is nothing to delete and nothing to expire. If the vault locks mid-session the camera stops rather than hold an unsealed photo in memory.
- **Device-bound:** keys use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — unreadable while the device is locked, and never synced or migrated.
- **Backup posture:** encrypted vault files can appear in an iCloud or device backup; the key cannot. Restored ciphertext is unopenable without a separately exported key backup.
- **Key derivation:** PBKDF2-HMAC-SHA256 — 310,000 iterations for PIN credentials, 600,000 for the passphrase wrapping an exported key-backup file. Purpose-specific subkeys of the vault key (the thumbnail cache key) use HKDF-SHA256 instead: the input is already a 256-bit random key, so there is nothing to stretch, and separate `info` strings make the subkeys independent — the thumbnail key cannot open a vault file.

Deliberately *not* claimed: forward secrecy. Vault files are sealed with one long-lived key; there is no per-session key exchange and no property that past content stays safe if that key is compromised.

## System Integration: Sensitive Content Warning

- Location: Settings → Privacy & Security → Sensitive Content Warning
- Behavior: If the system feature is disabled or restricted, the analyzer may be unavailable.
- App UX: The app now surfaces the system setting status in Onboarding and Settings and guides users to enable the feature for best results. No data leaves the device.

## Availability Behavior

- We treat SCSensitivityAnalyzer() == nil as "Unavailable" (device/OS unsupported or feature disabled/restricted).
- The transparency code exposes a helper to check availability; production UI uses this to display guidance.