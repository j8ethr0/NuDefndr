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

Q: Do I need to enable "Sensitive Content Warning"?
A: Yes. The app surfaces its status and provides guidance. You can toggle it in Settings → Privacy & Security → Sensitive Content Warning.

Q: Does this setting upload anything to the cloud?
A: No. It affects on-device analysis only. NuDefndr has zero network activity.

Q: How do I scan large libraries (50k+ photos)?
A: Use Advanced Time Range (Pro) to scan by year or quarter. Standard "All Time" scans will fail on large libraries due to iOS memory limits. Scans save progress every 20 items.

Q: What if my scan is interrupted?
A: Results are saved every 20 items. Progress is preserved and viewable immediately in Results tab.

Q: iCloud photos timing out?
A: Photos that fail to download (20s timeout) can be retried later via banner in Results when connection improves.
