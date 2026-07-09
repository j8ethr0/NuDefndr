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

## Documents & IDs Detection (Pro, opt-in) — new in 2.5.6

**Q: What is Documents & IDs detection?** A: An optional scan mode that flags photos exposing documents and credentials — payment cards, passports and other government IDs, IBANs, US Social Security numbers, and explicit credential text (verification codes, recovery phrases, private keys). It is **off by default** and enabled under Scan Settings.

**Q: Does it send my documents anywhere?** A: No. Detection runs entirely on-device using Apple's Vision framework for text recognition. Nothing is uploaded, and the recognized text itself is never stored — only the fact that a photo matched is recorded locally.

**Q: How does it avoid flagging every receipt and screenshot?** A: Detection is deliberately conservative — every signal requires a structural check, not just a keyword. Card numbers must pass the Luhn checksum; IBANs must pass the mod-97 checksum; passports and IDs must contain a valid machine-readable-zone (MRZ) pattern. Photographed identity documents additionally require both identity keywords *and* a document-shaped image. This keeps ordinary receipts, menus, and discount-code screenshots out of your results.

**Q: Where do detected documents appear?** A: In the same Results grid as sensitive photos, tagged with a document badge and filterable separately via the Nudity / Documents filter.

**Q: Can I verify the detection logic myself?** A: Yes. The on-device implementation is published in this repository at [`Sources/Scanner/DocumentDetectionService.swift`](Sources/Scanner/DocumentDetectionService.swift).

---

## Live Scan Activity & Instant Lock — new in 2.5.6

**Q: Does the Live Activity / Dynamic Island send scan data anywhere?** A: No. The Live Activity is rendered entirely on-device from local scan progress. It displays only counts and progress — never image content — and transmits nothing.

**Q: What does Instant Lock do?** A: Triggered from Control Center, the Action Button, or Siri, it immediately locks the entire app behind Face ID — even if you don't have App Lock enabled — without opening the app. The vault locks, any running scan is cancelled, and NuDefndr stays locked until you re-authenticate. It only affects NuDefndr's own lock state — it does not touch your device passcode or any other app. (Distinct from **Panic PIN**, which opens a decoy vault when you enter a specific code.)

**Q: Do Location Audit and metadata stripping change my original photos?** A: Only when you explicitly ask. NuDefndr surfaces which photos still carry GPS or EXIF metadata; stripping is an action you confirm, and it never runs silently in the background.

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