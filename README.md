# NuDefndr - Transparency Repository

![Version](https://img.shields.io/badge/version-2.5.4-blue)
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

**2026-06-24 – Version 2.5.4**

See [CHANGELOG.md](CHANGELOG.md) for full version history and transparency repository updates.

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

- **ChaCha20-Poly1305 AEAD:** 256-bit authenticated encryption with hardware-level tamper detection.
- **Ephemeral Keys:** Automatic RAM purge on app suspension; zero disk persistence.
- **Device-Bound Storage:** Enforced `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` protection.
- **Key Derivation:** PBKDF2, 100k iterations, SHA-256.
- **Zero Telemetry:** 100% offline-first. Zero network activity, zero tracking hooks.
- **No Cloud Leakage:** Vault paths are explicitly excluded from iCloud backups.

## Verify It Yourself

The published sources back the claims above directly — read the file, not just the description:

| Source | Backs |
|--------|-------|
| [`Sources/Vault/VaultEncryption.swift`](Sources/Vault/VaultEncryption.swift) | ChaCha20-Poly1305 AEAD, 256-bit keys, PBKDF2 (100k iterations, SHA-256) |
| [`Sources/Vault/KeychainManager.swift`](Sources/Vault/KeychainManager.swift) | Device-bound key storage via `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — keys never leave the device |
| [`Sources/Scanner/ContentAnalyzer.swift`](Sources/Scanner/ContentAnalyzer.swift) | On-device `SensitiveContentAnalysis` wrapper — no network calls |
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

Partial transparency release. Not independently audited. Use at your own risk.

## Contact

See [SECURITY.md](SECURITY.md)