# FAQ

## Privacy & Security

**Q: Does NuDefndr send my photos or scan results anywhere?** A: No. All image analysis, classification, encryption and metadata stripping happen entirely on-device. Your photos, scan results, audit logs and vault contents are never transmitted.

**Q: So the app makes no network requests at all?** A: Two, and neither carries anything about your photos. Subscription status is validated through RevenueCat, the App Store billing layer, which sees an anonymous subscriber identifier and whether you hold a Pro entitlement. And the FAQ screen loads this FAQ from nudefndr.com, so the in-app version cannot drift out of date — the page, its stylesheet, its script and its font, all from the same host and none from anywhere else. Those requests tell our web host an IP address and which language page was asked for, the same as any browser, and only when you open that screen. There is no analytics SDK, no crash reporter and no tracking. Run NuDefndr behind a proxy and those two are all you will see.

**Q: You use RevenueCat. How do I know you are not using it for analytics?** A: Read the calls. [`Sources/Purchases/PurchaseManager.swift`](Sources/Purchases/PurchaseManager.swift) is every RevenueCat call the app makes, bar one: the SDK is initialised at app launch with a single `Purchases.configure(withAPIKey:)` taking the public client key and no other options. What is *absent* is the part that matters, because RevenueCat's data collection is opt-in through APIs the app has to call:

| API | What it would do | Used |
|---|---|---|
| `setAttributes`, `setEmail`, `setDisplayName`, `setPhoneNumber` | attach subscriber attributes | no |
| `attribution`, Apple Search Ads / AdServices collection | ad attribution | no |
| `logIn` / `logOut` / a custom app user ID | tie purchases to an identity | no |
| `RevenueCatUI` | their paywall components, which emit their own events | no |

There is no account system, so there is no identity to attach anything to — purchases run against RevenueCat's own anonymous identifier (`$RCAnonymousID:…`), which is visible to anyone watching the traffic.

**The honest limit:** this proves what the app *sends*. It cannot prove what is switched on inside a RevenueCat dashboard, because that is server-side configuration and no client code can attest to it. No integrations are enabled — nothing is forwarded from RevenueCat to any analytics or advertising service — but you have our word for that part, not our source. If that is not good enough for your threat model, the check that does not require trusting us is a proxy: put NuDefndr behind mitmproxy or Charles and watch. You will see subscription calls and, when you open the FAQ, one request for the FAQ page.

**Q: What encryption standard does NuDefndr use?** A: ChaCha20-Poly1305 (256-bit AEAD authenticated encryption).

**Q: Where are encryption keys stored?** A: In the iOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — readable only while the device is unlocked, and never synced to iCloud or migrated to another device. (That is a Keychain accessibility class, not Secure Enclave storage; we do not claim hardware binding.)

**Q: Are my encrypted vault files included in an iCloud backup?** A: They can be — they are ordinary files in the app's container. The key is not, because it is device-only. So a restored backup brings back unopenable ciphertext unless you also exported a key backup. That is the whole reason Key Recovery exists.

**Q: What happens to decrypted vault data in memory?** A: Backgrounding the app locks the vault, releases the key from memory, and drops every decrypted image held in memory. A separate 60-second timer repeats that cleanup if the app is left backgrounded. No decrypted photo data is written to disk at any point.

**Q: Does the app keep thumbnails of my vault photos on disk?** A: Yes, and they are encrypted. Each one is sealed with ChaCha20-Poly1305 under a key derived from your vault key, so a locked vault cannot read its own thumbnails any more than anyone else can. They deliberately survive a lock — regenerating them all on every app switch is slow and buys nothing once they are sealed — and they are deleted outright when the vault itself is destroyed or cleared. They are excluded from iCloud backups. Older versions of the app cached these thumbnails unencrypted; updating deletes any that were left behind, once, on first launch.

**Q: What does the encryption actually protect against?** A: Someone with access to the app's files — via a backup, a forensic image, or the filesystem — cannot read vault contents, because the key is device-only and never appears in a backup. The Poly1305 authentication tag means altered ciphertext fails to open rather than decrypting to something wrong. It does not protect against someone who has your unlocked phone and your credentials; that is what App Lock, the Vault PIN and Travel Mode are for.

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

**Q: Do background auto-scans work when App Lock is active?** A: Yes. Background scans are scheduled by iOS and run without the UI, so App Lock does not gate them. What does affect them is iOS itself: background execution is budgeted by the system based on charge, battery state and how often you open the app, so a scheduled scan can be deferred well past its earliest date. Scan progress is checkpointed, so a deferred or interrupted scan resumes rather than restarting.

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

**Q: What does Instant Lock do?** A: Triggered from Control Center, the Action Button, or Siri, it immediately locks the entire app behind Face ID — even if you don't have App Lock enabled — without opening the app. The vault locks, any running scan is cancelled, and NuDefndr stays locked until you re-authenticate. It only affects NuDefndr's own lock state — it does not touch your device passcode or any other app.

**Q: Do Location Audit and metadata stripping change my original photos?** A: Only when you explicitly ask. NuDefndr surfaces which photos still carry GPS or EXIF metadata; stripping is an action you confirm, and it never runs silently in the background.

---

## Vault Key Backup & Recovery (Pro) — new in 2.5.7

**Q: Why would I need to back up my vault key?** A: Your vault's encryption key is stored only on this device (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). It never syncs to iCloud — but that also means that if the device is lost, reset, or restored from an iCloud backup, the key does not come back and the encrypted vault can no longer be opened. Key Recovery lets you export a copy of the key so that can't happen.

**Q: How is the exported key protected?** A: The raw 256-bit vault key is wrapped with a key derived from a passphrase you choose (PBKDF2-HMAC-SHA256, 600,000 iterations) and sealed with AES-GCM authenticated encryption, then written to a `.nudefndrkey` file. The file is useless without the passphrase, and a wrong passphrase fails the AES-GCM authentication tag rather than silently producing a bad key.

**Q: Is anything uploaded?** A: No. The export is fully air-gapped — the file is handed to the iOS share sheet and you decide where it goes (Files, an external drive, another device). Nothing is transmitted, and there is no server to transmit it to. Recovery is the reverse: import the file, enter the passphrase, and vault access is restored on the new device.

**Q: Can I verify the implementation?** A: Yes. The export/import code is published in this repository at [`Sources/Vault/VaultKeyBackup.swift`](Sources/Vault/VaultKeyBackup.swift).

---

## Audit Trail (Pro)

**Q: What is the Audit Trail feature?** A: A local log of security-relevant events, with category filters and a configurable retention window.

It logs events including:
- Engine scan cycles
- Biometric/PIN authentication events
- Vault access mutations
- Security level modifications

**Q: Where is the Audit Log stored?** A: Locally within isolated app storage. It is never synced, backed up, or exported automatically.

**Q: Can the Audit Log be edited?** A: Not from inside the app — entries are only ever added, never edited, and there is no affordance to change one. (Mechanically the file is rewritten in full on each new entry rather than extended, so do not read "append-only" as a storage guarantee.) It is a JSON file in the app's container, not a tamper-evident ledger: you can clear the whole log (which requires Face ID, Touch ID or your device passcode), and anyone with filesystem access to the container could alter it. Treat it as a personal record of what the app did, not as forensic evidence.

---

## Miscellaneous

**Q: Why is scanning slower than browsing my camera roll?** A: Browsing draws a cached thumbnail. Scanning runs every photo through Apple's on-device classifier at full analysis resolution, which costs far more compute — and if a photo lives only in iCloud, it has to be downloaded first.

**Q: Does deleting an item inside NuDefndr delete it from my system Photos?** A: Only if you explicitly grant system deletion permissions via the confirmation prompt. The app contains zero automated deletion logic.