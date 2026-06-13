# FAQ

## Privacy & Security

**Q: Does NuDefndr send anything over the network?** A: No. All image analysis, classification, and processing happens entirely on-device. The app operates 100% offline.

**Q: Is any data sent to external servers?** A: No. NuDefndr does not transmit your photos, scan results, logs, or metadata to any external infrastructure.

**Q: What encryption standard does NuDefndr use?** A: ChaCha20-Poly1305 (256-bit AEAD authenticated encryption).

**Q: Where are encryption keys stored?** A: Keys are stored securely inside the iOS Keychain, strictly bound to the physical hardware, and are excluded from iCloud backups.

**Q: What happens to decrypted vault data in memory?** A: Decryption keys are strictly ephemeral and are completely purged from RAM the moment the app enters the background. No decrypted data survives app suspension.

**Q: How does NuDefndr's encryption compare to standard vault apps?** A: Unlike apps that rely on standard file protection or cloud-synchronized keys, NuDefndr pairs ChaCha20-Poly1305 authenticated encryption with aggressive memory management. Keys are device-bound using `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, making them impossible to extract via iCloud restoration.

**Q: Is NuDefndr open source?** A: Partially. Core security architectures, cryptographic wrappers, and transparency-critical components are publicly visible in this repository.

**Q: Has NuDefndr been independently audited?** A: Not currently. 

---

## Apple Sensitive Content Warning

**Q: Do I need to enable Apple's Sensitive Content Warning?** A: Yes. NuDefndr wraps Apple's native `SensitiveContentAnalysis` framework. The app requires this system setting to be active to perform classifications.

Enable it via:  
`Settings → Privacy & Security → Sensitive Content Warning`

**Q: Does enabling this upload anything to Apple?** A: No. The system framework performs native on-device analysis exclusively.

---

## iCloud Photos & Scanning

**Q: Does scanning iCloud assets stream data to third-party servers?** A: No. If a photo asset resides strictly in iCloud Photos (due to **Optimize iPhone Storage** being enabled), iOS temporarily downloads the asset to your local sandbox so NuDefndr can run its analysis. The app never caches or syncs these assets.

**Q: Why do some iCloud photos take longer to scan?** A: Remote assets must complete their local download via the system photo daemon before analysis can begin. Performance depends entirely on your network speed and Apple's asset delivery.

**Q: What happens if an iCloud download times out?** A: Assets that fail to load within the download window are flagged with a retry state inside the Results layout.

---

## Scanning Engine

**Q: How do I scan massive libraries (50,000+ photos)?** A: Utilize the **Advanced Time Range** tool (Pro) to batch processing by year or quarter. Scanning extremely large libraries in a single pass can trigger iOS system memory caps.

**Q: What happens if a scan process is interrupted?** A: Progress checkpoints automatically every 10–20 items. Completed state changes persist immediately within the local cache.

**Q: Do background auto-scans work when App Lock is active?** A: iOS background task allocation can be heavily restricted if biometric gates are enforced at launch. If your automated background tasks are hanging, temporarily toggling App Lock off will isolate whether authentication gating is causing the iOS framework restriction.

---

## Audit Trail (Pro)

**Q: What is the Audit Trail feature?** A: A local, immutable ledger tracking sensitive structural operations within the app, featuring granular retention controls and authenticated purging.

It logs events including:
- Engine scan cycles
- Biometric/PIN authentication events
- Vault access mutations
- Security level modifications

**Q: Where is the Audit Log stored?** A: Locally within isolated app storage. It is never synced, backed up, or exported automatically.

**Q: Can the Audit Log be manipulated?** A: Entries are strictly append-only during active execution to preserve structural integrity.

---

## Miscellaneous

**Q: Why is scanning slower than standard camera roll browsing?** A: NuDefndr executes localized tensor evaluation models on every single image frame, which demands significantly higher compute cycles than rendering flat UI thumbnails.

**Q: Does deleting an item inside NuDefndr delete it from my system Photos?** A: Only if you explicitly grant system deletion permissions via the confirmation prompt. The app contains zero automated deletion logic.