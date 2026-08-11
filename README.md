# NuDefndr - Transparency Repository

![Version](https://img.shields.io/badge/version-2.5.9-blue)
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

**2026-08-11 – Version 2.5.9**

Usability, and two corrections. Photos can now be imported straight into the Vault without running a scan first, through the same pipeline as the review flow — full resolution, metadata stripped. Pro features in Settings are grouped rather than listed as a column of locked rows, so a free user can find the settings they can actually change. The two corrections: the "Change Vault PIN" control did not ask for the existing PIN, so anyone holding the unlocked phone could replace it; it now does, rate-limited by the same throttle as every other PIN entry. And premium themes kept working after a subscription lapsed — the only Pro feature that did — which now falls back to Essential while preserving the user's choice for resubscription. Travel Mode gains an arming confirmation and a lock-out timer that actually counts down, and the Panic PIN is renamed the Ghost PIN. See [CHANGELOG.md](CHANGELOG.md) for full version history and transparency repository updates.

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
- **No telemetry:** no analytics SDK, no tracking, no crash reporting. Your photos, scan results, audit logs and vault contents never leave the device. The app's only network traffic is App Store subscription validation through RevenueCat, which sees an anonymous subscriber identifier and your entitlement status — no photos, no scan data, no personal identifiers.
- **Backups:** encrypted vault files may be included in an iCloud or device backup, but the key is device-only and never syncs. Ciphertext restored onto another device cannot be opened — which is exactly why [Key Recovery](CHANGELOG.md) exists.

## Verify It Yourself

The published sources back the claims above directly — read the file, not just the description:

| Source | Backs |
|--------|-------|
| [`Sources/Vault/VaultEncryption.swift`](Sources/Vault/VaultEncryption.swift) | ChaCha20-Poly1305 AEAD seal/open and 256-bit random key generation — the vault's actual encryption path |
| [`Sources/Vault/KeychainManager.swift`](Sources/Vault/KeychainManager.swift) | Device-bound key storage via `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — keys never leave the device |
| [`Sources/Vault/VaultKeyBackup.swift`](Sources/Vault/VaultKeyBackup.swift) | Passphrase-wrapped vault key export/import (PBKDF2-SHA256 200k + AES-GCM) — air-gapped `.nudefndrkey` file, never uploaded |
| [`Sources/Scanner/ContentAnalyzer.swift`](Sources/Scanner/ContentAnalyzer.swift) | On-device `SensitiveContentAnalysis` wrapper — no network calls |
| [`Sources/Scanner/DocumentDetectionService.swift`](Sources/Scanner/DocumentDetectionService.swift) | On-device Documents & IDs detection via Apple Vision — no network calls; conservative structural checks (Luhn / IBAN mod-97 / passport MRZ) |
| [`Sources/Models/ScanResult.swift`](Sources/Models/ScanResult.swift) | Scan result model — local only, no telemetry fields |

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