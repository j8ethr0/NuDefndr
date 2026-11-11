# NuDefndr - Transparency Repository

![Version](https://img.shields.io/badge/version-2.6.8-blue)
![Platform](https://img.shields.io/badge/iOS-18%2B-black)
![License](https://img.shields.io/badge/license-MIT-green)
![Languages](https://img.shields.io/badge/languages-4-orange)

Privacy-first iOS app for detecting sensitive content using Apple's on-device ML.

🔗 Website: https://nudefndr.com
📱 App Store: https://apps.apple.com/jp/app/nudefndr/id6745149292 
🌍 Languages: English, Japanese (日本語), Thai (ไทย), Simplified Chinese (简体中文) 
📄 License: MIT

---

## Latest Update

**2026-11-04 – Version 2.6.8**

Every vault photo is sealed to its own record, Pro runs on Apple's StoreKit with no third-party SDK, and the language chosen in Settings applies throughout the app. See [CHANGELOG.md](CHANGELOG.md) for full version history and transparency repository updates.

---

## What's Included

- Vault Encryption (ChaCha20-Poly1305)
- Vault Intake: Metadata Stripping and Sealing (ImageIO, ChaCha20-Poly1305)
- Vault Camera Capture Session (AVFoundation)
- Keychain Integration (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- SensitiveContentAnalysis Framework Wrapper

## What's NOT Included

- Proprietary UI Code
- Premium Feature Business Logic
- Closed-Source Production Binaries

## Security Architecture

- **ChaCha20-Poly1305 AEAD:** 256-bit authenticated encryption. The Poly1305 tag is verified on every decrypt, so modified or forged ciphertext fails to open rather than returning garbage.
- **Sealed to its record:** each vault photo is sealed with its item identifier as ChaCha20-Poly1305 authenticated data, so a file opens only for the record it was sealed for. Two files swapped on disk fail the tag check.
- **Random vault key:** the vault key is a 256-bit key from the system CSPRNG — not derived from a PIN or passphrase. It lives in the Keychain and is dropped from RAM when the app leaves the foreground; no decrypted photo data is ever written to disk.
- **Device-bound storage:** the key is stored `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, so it is readable only while the device is unlocked and never migrates to another device or to iCloud.
- **Key derivation, where it is actually used:** PBKDF2-HMAC-SHA256 at 310,000 iterations for PIN credentials, and 600,000 iterations for the passphrase that wraps an exported key-backup file. The vault key itself is random, so no derivation is involved in opening the vault.
- **No telemetry:** no analytics SDK, no tracking, no crash reporting. Your photos, scan results, audit logs and vault contents never leave the device. Purchases and Pro entitlement checks go through Apple's StoreKit on the device, with no third-party SDK, so the app connects to Apple and to nothing else. The FAQ ships inside the app and loads nothing. See [FAQ.md](FAQ.md).
- **Backups:** encrypted vault files may be included in an iCloud or device backup, but the key is device-only and never syncs. Ciphertext restored onto another device cannot be opened — which is exactly why [Key Recovery](CHANGELOG.md) exists.

## Verify It Yourself

The published sources back the claims above directly — read the file, not just the description:

| Source | Backs |
|--------|-------|
| [`Sources/Vault/KeychainHelper.swift`](Sources/Vault/KeychainHelper.swift) | Device-bound key storage via `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, and the read path that refuses to conflate "no key yet" with "could not read the key" |
| [`Sources/Vault/KeyDerivation.swift`](Sources/Vault/KeyDerivation.swift) | The one PBKDF2-HMAC-SHA256 implementation in the codebase, and the HKDF-SHA256 subkey derivation — including why a random 256-bit input is expanded rather than stretched |
| [`Sources/Vault/VaultKeyBackup.swift`](Sources/Vault/VaultKeyBackup.swift) | Passphrase-wrapped key export and import — PBKDF2-SHA256 at 600,000 iterations then AES-GCM, written to an air-gapped `.nudefndrkey` file that is never uploaded |
| [`Sources/Security/Authenticator.swift`](Sources/Security/Authenticator.swift) | App Lock — the single grace rule (left while unlocked under 60 seconds ago, stamped once when the app goes from unlocked to locked), and Instant Lock voiding a Face ID already in progress |
| [`Sources/Vault/PinAttemptThrottle.swift`](Sources/Vault/PinAttemptThrottle.swift) | The PIN attempt delay — measured on a monotonic clock the date setting cannot move, kept in the Keychain across a reinstall, and an unreadable record counts as a lockout |
| [`Sources/Vault/PanicPinStore.swift`](Sources/Vault/PanicPinStore.swift) | PIN credential storage — a salted PBKDF2-SHA256 hash at 310,000 iterations in the Keychain, `ThisDeviceOnly`, written in place and never as the PIN itself |
| [`Sources/Camera/VaultCameraController.swift`](Sources/Camera/VaultCameraController.swift) | The vault camera's capture session — the bytes go from `AVCapturePhotoOutput` to memory to the vault's sealing path, and neither `PHPhotoLibrary` nor a temporary file appears anywhere in it |
| [`Sources/Scanner/SensitiveContentService.swift`](Sources/Scanner/SensitiveContentService.swift) | The `SensitiveContentAnalysis` wrapper — on-device, no network calls, and how the app detects whether the system setting is switched on |
| [`Sources/Scanner/DocumentDetectionService.swift`](Sources/Scanner/DocumentDetectionService.swift) | On-device Documents & IDs detection via Apple Vision — no network calls; conservative structural checks (Luhn / IBAN mod-97 / passport MRZ) |
| [`Sources/Models/SensitiveAsset.swift`](Sources/Models/SensitiveAsset.swift) | The scan result model — local only, no telemetry fields |
| [`Sources/Purchases/PurchaseManager.swift`](Sources/Purchases/PurchaseManager.swift) | The whole purchase path, written against Apple's StoreKit 2 — product list, purchase, restore and entitlement checks, verified on the device. No third-party SDK, no account, no user identity |
| [`Sources/Purchases/ProEntitlementCache.swift`](Sources/Purchases/ProEntitlementCache.swift) | The locally cached Pro flag the UI reads, so a launch does not gate features on a network round-trip |
| [`Sources/FAQ/FAQPages.swift`](Sources/FAQ/FAQPages.swift) | The in-app FAQ — four self-contained pages in the app bundle (en, ja, th, zh), read from disk with no network code |
| [`Sources/FAQ/FAQWebPage.swift`](Sources/FAQ/FAQWebPage.swift) | The FAQ renderer — non-persistent data store, `baseURL: nil`; the FAQ carries no links and loads nothing; every navigation but its own page is refused |
| [`Sources/Vault/VaultIntake.swift`](Sources/Vault/VaultIntake.swift) | The path every photo takes into the vault, imported or captured — metadata removed by `MetadataStrip`, then sealed with ChaCha20-Poly1305 and written with complete file protection |
| [`Sources/Privacy/MetadataStrip.swift`](Sources/Privacy/MetadataStrip.swift) | The one metadata strip, shared by the vault and Clean & Share — GPS, EXIF, TIFF, IPTC, XMP and every camera maker's notes removed with ImageIO, orientation kept, and a clean copy checked against an allow-list before it leaves the phone |

Each of these is shipping code, with debug-only branches resolved to the release
build. The call that seals a vault photo to its item identifier and writes it is
published in `VaultIntake.swift`; `ChaChaPoly.open`, and the seal for thumbnails,
are called inline where those are read and written. Together with the key storage and derivation above, what is
published here covers *which key* those calls use and how a vault photo reaches disk.

## Requirements

- iOS 18.0+
- CoreML compatible iPhone/iPad

## Documentation

- [CHANGELOG.md](CHANGELOG.md) – Version history and updates
- [ARCHITECTURE.md](ARCHITECTURE.md) – System design
- [SENSITIVE_CONTENT_WARNING.md](SENSITIVE_CONTENT_WARNING.md) – Setup guide
- [SECURITY.md](SECURITY.md) – Security disclosure policy
- [FAQ.md](FAQ.md) – Frequently asked questions

## Repository History

Replaces NuDefndr-Core (2024–2025, archived).

## Disclaimer

This is a partial source release: the security-critical components are published here, the full application is not. It has not been independently audited — if that matters for your threat model, weigh it accordingly.

## Contact

See [SECURITY.md](SECURITY.md)