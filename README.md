# NuDefndr - Transparency Repository

![Version](https://img.shields.io/badge/version-2.6.1-blue)
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

**2026-08-25 – Version 2.6.1**

A vault and location release. Vault thumbnails are now encrypted on disk — they were written as ordinary JPEGs before this, which is stated plainly in the [CHANGELOG](CHANGELOG.md) because it changes what the app leaves readable. The vault also reports its own state (item count, size, key-backup status, last opened), tells you when no key backup exists, and location data can now be cleaned one place at a time, on-device, with no geocoding request. See [CHANGELOG.md](CHANGELOG.md) for full version history and transparency repository updates.

---

## What's Included

- Vault Encryption (ChaCha20-Poly1305)
- Keychain Integration (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- SensitiveContentAnalysis Framework Wrapper

## What's NOT Included

- Proprietary UI Code
- Premium Feature Business Logic
- Closed-Source Production Binaries

## Security Architecture

- **ChaCha20-Poly1305 AEAD:** 256-bit authenticated encryption. The Poly1305 tag is verified on every decrypt, so modified or forged ciphertext fails to open rather than returning garbage.
- **Random vault key:** the vault key is a 256-bit key from the system CSPRNG — not derived from a PIN or passphrase. It lives in the Keychain and is dropped from RAM when the app leaves the foreground; no decrypted photo data is ever written to disk.
- **Device-bound storage:** the key is stored `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, so it is readable only while the device is unlocked and never migrates to another device or to iCloud.
- **Key derivation, where it is actually used:** PBKDF2-HMAC-SHA256 at 310,000 iterations for PIN credentials, and 600,000 iterations for the passphrase that wraps an exported key-backup file. The vault key itself is random, so no derivation is involved in opening the vault.
- **No telemetry:** no analytics SDK, no tracking, no crash reporting. Your photos, scan results, audit logs and vault contents never leave the device. Two things go out, neither carrying photos or scan data: App Store subscription validation through RevenueCat, and the FAQ screen loading this FAQ from `nudefndr.com` when you open it. See [FAQ.md](FAQ.md).
- **Backups:** encrypted vault files may be included in an iCloud or device backup, but the key is device-only and never syncs. Ciphertext restored onto another device cannot be opened — which is exactly why [Key Recovery](CHANGELOG.md) exists.

## Verify It Yourself

The published sources back the claims above directly — read the file, not just the description:

| Source | Backs |
|--------|-------|
| [`Sources/Vault/KeychainHelper.swift`](Sources/Vault/KeychainHelper.swift) | Device-bound key storage via `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, and the read path that refuses to conflate "no key yet" with "could not read the key" |
| [`Sources/Vault/KeyDerivation.swift`](Sources/Vault/KeyDerivation.swift) | The one PBKDF2-HMAC-SHA256 implementation in the codebase, and the HKDF-SHA256 subkey derivation — including why a random 256-bit input is expanded rather than stretched |
| [`Sources/Vault/VaultKeyBackup.swift`](Sources/Vault/VaultKeyBackup.swift) | Passphrase-wrapped key export and import — PBKDF2-SHA256 at 600,000 iterations then AES-GCM, written to an air-gapped `.nudefndrkey` file that is never uploaded |
| [`Sources/Scanner/SensitiveContentService.swift`](Sources/Scanner/SensitiveContentService.swift) | The `SensitiveContentAnalysis` wrapper — on-device, no network calls, and how the app detects whether the system setting is switched on |
| [`Sources/Scanner/DocumentDetectionService.swift`](Sources/Scanner/DocumentDetectionService.swift) | On-device Documents & IDs detection via Apple Vision — no network calls; conservative structural checks (Luhn / IBAN mod-97 / passport MRZ) |
| [`Sources/Models/SensitiveAsset.swift`](Sources/Models/SensitiveAsset.swift) | The scan result model — local only, no telemetry fields |
| [`Sources/Purchases/PurchaseManager.swift`](Sources/Purchases/PurchaseManager.swift) | Every RevenueCat call the app makes apart from the one-line SDK initialisation at app launch — entitlement checks, purchase and restore. No subscriber attributes, no attribution, no user identity |
| [`Sources/Purchases/ProEntitlementCache.swift`](Sources/Purchases/ProEntitlementCache.swift) | The locally cached Pro flag the UI reads, so a launch does not gate features on a network round-trip |
| [`Sources/FAQ/FAQDocumentStore.swift`](Sources/FAQ/FAQDocumentStore.swift) | The FAQ fetch — the one host, an ephemeral session with no cookie, credential or URL cache, and a generic user-agent |
| [`Sources/FAQ/FAQWebPage.swift`](Sources/FAQ/FAQWebPage.swift) | The FAQ renderer — non-persistent data store, `baseURL: nil`, every navigation but the initial load refused |

Each of these is the shipping file, under its real name, with debug-only branches
resolved to the release build. Vault encryption itself has no file of its own to
publish: `ChaChaPoly.seal` and `ChaChaPoly.open` are called inline where vault
items and thumbnails are written and read. What is published here is everything
that decides *which key* those calls use.

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