# NudeFndr - Transparency Repository

Privacy-first iOS app for detecting sensitive content using Apple's on-device ML.

🔗 Website: https://nudefndr.com  
📱 App Store: https://apps.apple.com/jp/app/nudefndr/id6745149292  
🌍 Languages: English, Japanese (日本語), Thai (ไทย), Simplified Chinese (简体中文)  
📄 License: MIT

---

## What’s New

2026-01-16
- Surfacing system “Sensitive Content Warning” status in Onboarding and Settings to reduce confusion and misconfiguration. Added docs and availability helper in the transparency code.
- No changes to networking or data practices (still zero network, on-device only).

---

## What’s Included

- Vault Encryption (ChaCha20-Poly1305)
- Keychain Integration
- SensitiveContentAnalysis Wrapper

## What’s NOT Included

- UI code
- Business logic
- Production app code

## Security

- On-device ML only (zero network)
- ChaCha20-Poly1305 encryption
- iOS Keychain storage (device-bound keys)

## Requirements

- iOS 18+
- iPhone/iPad

## Documentation

- ARCHITECTURE.md
- SENSITIVE_CONTENT_WARNING.md
- SECURITY.md
- CHANGELOG.md

## Repository History

Replaces NuDefndr-Core (2024–2025, archived).

## Disclaimer

Partial transparency release. Not independently audited. Use at your own risk.

## Contact

See SECURITY.md