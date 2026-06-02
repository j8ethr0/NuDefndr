# NudeFndr - Transparency Repository

Privacy-first iOS app for detecting sensitive content using Apple's on-device ML.

🔗 Website: https://nudefndr.com  
📱 App Store: https://apps.apple.com/jp/app/nudefndr/id6745149292  
🌍 Languages: English, Japanese (日本語), Thai (ไทย), Simplified Chinese (简体中文)  
📄 License: MIT

---

## Latest Update

**2026-05-31 – Version 2.5.2**

See [CHANGELOG.md](CHANGELOG.md) for full version history and transparency repository updates.

---

## What's Included

- Vault Encryption (ChaCha20-Poly1305)
- Keychain Integration
- SensitiveContentAnalysis Wrapper

## What's NOT Included

- UI code
- Business logic
- Production app code

## Security

- ChaCha20-Poly1305 AEAD: 256-bit authenticated encryption with tamper detection
- Ephemeral keys: automatic RAM purge on app suspension, no disk persistence
- Device-bound storage: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- Key derivation: PBKDF2, 100k iterations, SHA-256
- On-device ML: zero network activity, zero telemetry
- No cloud sync: vault excluded from iCloud backup

## Requirements

- iOS 18+
- iPhone/iPad

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