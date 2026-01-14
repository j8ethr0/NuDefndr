# Security Disclosure

**App:** NudeFndr (com.dro1d.PicDefndr)  
**Email:** security@dro1d.org

## Response Times

- Acknowledgment: ≤72 hours
- Initial response: ≤7 days
- Fix: ≤30-90 days
- Public disclosure: 90 days after fix

## Safe Harbor

Yes - good faith testing protected.

## Data Collection

**ZERO**
- No analytics
- No accounts
- No cloud storage
- On-device only

## Encryption

- ChaCha20-Poly1305 (AEAD)
- 256-bit keys
- iOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- PBKDF2 (100k iterations, SHA-256)