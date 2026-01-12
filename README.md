# NudeFndr - Transparency Repository

Privacy-first iOS app for detecting sensitive content using Apple's on-device ML. This repo contains core encryption and analysis components for independent review.

**What's included:** Vault encryption (AES-256-GCM/ChaCha20), keychain integration, Apple SensitiveContentAnalysis wrapper

**What's NOT included:** UI, business logic, production app code, proprietary optimizations

Uses Apple CryptoKit. No network activity in analysis pipeline (verifiable). Device-bound encryption keys.

MIT License. Not independently audited. Partial transparency release only.
