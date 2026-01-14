# Architecture

## Data Flow

Photo Library → SensitiveContentAnalysis (on-device) → Vault (encrypted)

## Components

1. **Photo Analysis:** SensitiveContentAnalysis (iOS 17+), zero network
2. **Encryption:** ChaCha20-Poly1305 (CryptoKit)
3. **Key Storage:** iOS Keychain (device-bound)