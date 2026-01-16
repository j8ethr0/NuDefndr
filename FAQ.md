# FAQ

Q: Network activity?  
A: Zero. All ML is on-device.

Q: Data sent to servers?  
A: Nothing. No servers exist.

Q: Encryption algorithm?  
A: ChaCha20-Poly1305 (AEAD, 256-bit)

Q: Where are keys stored?  
A: iOS Keychain, device-bound, not backed up to iCloud.

Q: Open source?  
A: Partial. Core security components only.

Q: Audited?  
A: No.

Q: Do I need to enable “Sensitive Content Warning”?  
A: Strongly recommended for best results. The app surfaces its status and provides guidance. You can toggle it in Settings → Privacy & Security → Sensitive Content Warning.

Q: Does this setting upload anything to the cloud?  
A: No. It affects on-device analysis only. NudeFndr has zero network activity.