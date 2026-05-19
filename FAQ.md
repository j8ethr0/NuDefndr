# FAQ

## Privacy & Security

**Q: Does NuDefndr send anything over the network?**  
A: No. All image analysis, classification, and processing happens entirely on-device.

**Q: Is any data sent to external servers?**  
A: No. NuDefndr does not transmit your photos, scan results, or metadata to any external servers.

**Q: What encryption does NuDefndr use?**  
A: ChaCha20-Poly1305 (256-bit AEAD authenticated encryption).

**Q: Where are encryption keys stored?**  
A: Keys are stored in the iOS Keychain, bound to your device, and are not backed up to iCloud.

**Q: Is NuDefndr open source?**  
A: Partially. Core security and transparency-related components are publicly documented.

**Q: Has NuDefndr been independently audited?**  
A: Not currently.

---

## Apple Sensitive Content Warning

**Q: Do I need to enable Sensitive Content Warning?**  
A: Yes. NuDefndr requires Apple’s Sensitive Content Warning framework for image classification. The app checks its status and provides guidance if it is disabled.

Enable it in:  
`Settings → Privacy & Security → Sensitive Content Warning`

**Q: Does enabling this upload anything to Apple or the cloud?**  
A: No. Sensitive Content Warning performs on-device analysis only.

---

## iCloud Photos & Scanning

**Q: Does enabling iCloud scanning upload anything to iCloud or the internet?**  
A: No. If a photo exists only in iCloud Photos (because **Optimize iPhone Storage** is enabled), iOS temporarily downloads that image to your device so NuDefndr can scan it locally.

NuDefndr never uploads, transmits, or syncs those images.

**Q: Why do some iCloud photos take time to scan?**  
A: Images stored only in iCloud must first be downloaded by iOS before local analysis can begin. Scan speed depends on your connection and Apple’s photo retrieval speed.

**Q: What if an iCloud photo times out?**  
A: Photos that fail to download within the timeout window can be retried later via the retry banner in Results.

---

## Scanning

**Q: How do I scan very large libraries (50,000+ photos)?**  
A: Use **Advanced Time Range** (Pro) to scan by year or quarter.
Scanning your entire library at once may exceed iOS memory constraints on some devices.

**Q: What happens if a scan is interrupted?**  
A: Progress is checkpointed every 10-20 items. Completed results remain immediately available in the Results tab.

---

## Audit Trail (Pro)

**Q: What is Audit Trail?**  
A: Audit Trail is a secure, locally stored record of important NuDefndr activity, with customizable timeframes and authenticated deletion.

It tracks events such as:

- Scan start / completion
- Authentication events
- Vault access events
- Security-related actions

**Q: Where is Audit Log stored?**  
A: Only on your device.
It is never uploaded, synced, or shared externally.

**Q: Can Audit Log be modified?**  
A: Entries are append-only during normal app operation to preserve integrity. You can modify exported log formats.

---

## Misc

**Q: Why is scanning slower than my Photos app?**  
A: NuDefndr performs local safety analysis on each image, which is significantly more computationally intensive than simply displaying thumbnails.

**Q: Does deleting something in NuDefndr delete it from Photos?**  
A: Only if you explicitly confirm deletion. NuDefndr never removes content automatically.