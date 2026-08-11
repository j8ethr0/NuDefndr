# Changelog

All notable changes to NuDefndr releases and this transparency repository.

---

## 2026-08-11 – Version 2.5.9

A usability release, with two corrections worth stating plainly: a paid feature that kept working after people stopped paying for it, and a way the Vault PIN could be replaced by someone who did not know it.

**New in 2.5.9**

- **Direct Vault import:** photos could previously only reach the Vault through the review screen after a scan, or via the share extension. That works if the app agrees with you about which photos are sensitive, and not otherwise — anyone who already knew which photo they wanted protected had to run a full library scan and hope. You can now pick photos straight into the Vault from your library. Import runs through the same path as the review flow, so it inherits full-resolution intake, EXIF and GPS stripping, audit logging, and the Travel Mode guard rather than re-implementing any of them. You choose whether the originals stay in Photos.
- **Free tier presentation:** Pro features in Settings rendered as a column of individually locked rows — seven consecutive ones in Vault, five in Scanning — which buried the settings a free user can actually change. Each section now shows its Pro features as a single named group. Nothing is hidden: every feature is still listed by name, because a free user is entitled to know exactly what the paid tier contains.
- **Vault PIN change now requires the current PIN.** Previously the "Change Vault PIN" control dropped into the same form used to set one for the first time, and did not ask for the existing code. Anyone with the unlocked phone could therefore replace the Vault PIN with one of their own. The owner would not necessarily find out: because an incorrect PIN behaves the way it does, they would arm Travel Mode later, enter what they believed was their code, and be shown a plausible result. Changing the PIN now requires the current one, and is rate-limited by the same attempt throttle as every other PIN entry.
- **Premium themes now follow the subscription.** Themes are a Pro feature, but the selected theme was stored as an ordinary preference with nothing checking entitlement — so a lapsed subscriber kept using a paid theme indefinitely. It was the only Pro feature that carried on working after the entitlement ended. The rendered theme now falls back to Essential without an active subscription, in the app and in the home-screen widget. The choice itself is preserved rather than erased, so resubscribing restores it.
- **Travel Mode refinements:** arming now confirms what it changes before it takes effect, rather than switching silently. PIN fields show how many digits have been entered, matching the vault pad. The attempt-throttle lock-out now counts down live; it previously displayed a fixed number of seconds that never moved, which at the top of the escalation ladder meant an unchanging "3600 seconds" for an hour.
- **Panic PIN is now the Ghost PIN.** A rename only — the feature, the stored credential, and the behaviour are unchanged. "Panic" announced itself in a settings list, and sat one row from "Distress PIN" while meaning something entirely different. Two near-synonyms for two features with opposite consequences is a poor thing to rely on remembering under pressure.
- **Purchase and restore reporting:** Restore Purchases now states its outcome. A restore that completes but finds no purchase on the signed-in Apple Account — the most common result — previously changed nothing on screen and was indistinguishable from a control that did not work. Store errors are now reported in terms of what to do next rather than as raw framework text. Subscription status in Settings also now reflects the current entitlement rather than the one read at launch.
- **Documentation:** the in-app FAQ gains entries for Travel Mode, the Ghost PIN, the Distress PIN, vault key backup, key recovery, and document detection.

As always: all scanning, detection, encryption, and stripping happen locally on your device. Nothing is sent to a server.

---

## 2026-07-25 – Version 2.5.8

A security and honesty release: a mode for higher-risk situations, a fix for what the app switcher could reveal, full-quality Vault storage, and telling you the whole truth about deletion.

**New in 2.5.8**

- **Travel Mode (Pro):** an optional posture for situations where the phone might leave your hands unlocked. While it is on, the Vault opens only with a PIN you choose — biometrics will not open it. A face can be pointed at a camera; a code you have not said out loud cannot. Travel Mode also hides the vault button, forces Ultra Stealth, and suppresses the scan Live Activity, so nothing about the app advertises that a vault exists. Turning it off requires the same PIN. As with our other protections for people under pressure, the precise behaviour when an incorrect PIN is entered is deliberately underspecified — that opacity is part of the protection.
- **App-switcher privacy:** iOS snapshots every app when it leaves the foreground and uses that image as the app-switcher thumbnail. Previously that snapshot could capture an open Vault, meaning vault contents were visible from the switcher without unlocking anything. The app now covers itself with an opaque screen the moment it stops being active — unconditionally, for every user, independent of App Lock, subscription status, and the vault's own lock state. Applied per presentation layer, including the full-screen photo viewer, which renders above the main view hierarchy.
- **Full-quality Vault storage:** photos entering the Vault were being taken from the scanner's image pipeline, which downscales to 1536px and re-encodes as JPEG to keep scanning fast. That is right for analysis and wrong for archival — a 12-megapixel photo lost roughly 85% of its pixels, and anyone who deleted the original after vaulting lost that quality permanently. Vault intake now takes the asset's original bytes, at full resolution, with no re-encode. EXIF and GPS stripping still runs, and now refuses to fall back to unstripped data if it fails. Photos vaulted before 2.5.8 are unaffected and remain at their stored resolution.
- **Vault key reminders:** the app now tells you when your vault key has not been backed up, both at the moment you first vault photos and in Vault settings. Key backup shipped in 2.5.7, but nothing pointed you at it — and an iCloud restore brings back the encrypted files without the device-bound key that opens them.
- **Sharing check hardening:** the share-sheet check previously examined only the first photo of a multi-photo send, and did not appear at all when more than one photo was selected. It now checks every photo. It also no longer fails open: if Apple's Sensitive Content Warning is disabled in iOS Settings the analyzer reports everything as clean, which was indistinguishable from a genuine all-clear. The check now reports that it could not verify your photos rather than implying they are safe.
- **Recently Deleted disclosure:** deleting a photo has never been instant on iOS — the system keeps it recoverable in the Recently Deleted album for up to 30 days. NuDefndr now says so plainly after every removal, and offers a shortcut into Photos so you can empty Recently Deleted and make it final. We would rather tell you about a platform limitation than let a false sense of finality stand.
- **Metadata-free Vault guarantee:** photos entering the Vault are explicitly passed through the same EXIF/GPS stripping engine used by the Location Cleaner before encryption, and the stripper is now verified against HEIC as well as JPEG — HEIC being the format most iPhones actually produce.
- **VoiceOver support for protection state:** the ghost's eye color carries scan and protection state throughout the app — which excluded VoiceOver users and anyone with color-vision deficiency. The home hero card, protection widgets, vault status headers, and the scan Live Activity (including the compact Dynamic Island states) now describe their state as text to assistive technologies.
- **Corrected cipher disclosure:** several screens described the Vault's encryption as AES-256. The Vault has always used ChaCha20-Poly1305 with a 256-bit key. Both are strong, but the label was wrong, and a transparency project that misstates its own primitives is worth less than one that corrects itself. Every surface now names the cipher accurately. (The separate key-backup file format does use AES-GCM to wrap the exported key — that part was always correct.)
- **Interface consistency:** square-cornered themes no longer show rounded card surfaces, plus wider translation coverage and internal cleanup.

As always: all scanning, detection, encryption, and stripping happen locally on your device. Nothing is sent to a server.

---

## 2026-07-14 – Version 2.5.7

A security-focused release: stronger protection for high-risk situations, and a way to recover your vault if a device is lost or reset. As always, everything runs on-device — nothing is uploaded.

**New in 2.5.7**

- **Vault Key Backup & Recovery (Pro):** your vault key is device-bound (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), which is the right default for security — but it also means a lost or reset phone can lock you out of your own vault forever. You can now export a recovery key, wrapped with a passphrase you choose (PBKDF2-SHA256, 600k iterations, then AES-GCM), to a `.nudefndrkey` file you store wherever you like. It is fully air-gapped — nothing is uploaded — and useless to anyone without the passphrase. Import it on a new device to restore access.
- **Hardened duress protections (Pro):** additional safeguards for high-risk situations. The optional secondary PINs are now stored as salted PBKDF2-SHA256 credentials in the Keychain (previously an unsalted hash), so they can't be lifted from a device backup and brute-forced; existing setups upgrade automatically, with no risk of lockout. 2.5.7 also adds an optional last-resort safeguard, gated behind a completed key backup so it can never be triggered as an accidental data-loss trap. We keep the exact behaviour of these features deliberately underspecified — for tools meant to protect you under pressure, that opacity is part of the protection.
- **Ambient status surfaces:** Lock Screen widgets, a Protection widget that matches your selected theme, the ghost mascot within the Ghost theme itself, and a branded Instant Lock control.
- **Clearer action confirmations** after photos are moved to the Vault, deleted, or cleared.

**Transparency repository**

- Published [`Sources/Vault/VaultKeyBackup.swift`](Sources/Vault/VaultKeyBackup.swift) — the passphrase-wrapped, upload-free vault key export/import — and added it to the "Verify It Yourself" table.

As always: all scanning, detection, encryption, and recovery happen locally on your device. Nothing is sent to a server.

---

## 2026-07-09 – Version 2.5.6

Our biggest feature release in a while. As always, every one of these runs entirely on-device — nothing here sends your photos, documents, or location anywhere.

**New in 2.5.6**

- **Live Scan Activity:** watch a scan progress in real time from the Dynamic Island and Lock Screen, fronted by the NuDefndr ghost — its eyes change color with the scan state (scanning, paused, done). The completed state now lingers briefly so fast scans don't vanish before you notice them.
- **Documents & IDs detection (opt-in):** on-device text recognition flags photos that expose payment cards, passports and other IDs, IBANs, SSNs, and credential phrases. It is deliberately conservative — every hit requires a structural check (card Luhn checksum, IBAN mod-97, passport machine-readable zone) so ordinary receipts, menus, and screenshots don't flood your results. Off by default, and nothing is uploaded.
- **Instant Lock:** instantly lock the whole app behind Face ID — from Control Center, the Action Button, or Siri — even if App Lock isn't enabled. The app stays locked until you re-authenticate.
- **Protection widget:** a Home Screen widget showing your protection status at a glance.
- **Location Audit & Cleaner:** find photos that still carry GPS location data and strip it.
- **Metadata stripping:** remove EXIF and other embedded metadata.
- **Auto-Redact:** automatic redaction suggestions for sensitive regions before you share.
- Refreshed app icon (the ghost) plus a set of alternate icons, and a round of Settings, Results, and Vault UI polish.

As always: all scanning, detection, and redaction happen locally on your device. Nothing is sent to a server.

---

## 2026-06-29 – Version 2.5.5 (supersedes 2.5.4)

An update on the 2.5.4 situation: after the resubmitted 2.5.4 sat in the review queue for over four days with no movement, we decided to stop waiting. Rather than hold the fixes back, we're shipping **2.5.5** as a fresh submission. It includes everything from 2.5.4 plus a round of UI and stability work — the two releases are rolled into one, so nothing from 2.5.4 is lost.

As always: nothing about how your data is handled has changed. All analysis stays on-device.

**New in 2.5.5**

- Themes: refined Terminal, Pixel & Tactical visuals for a sleeker, more premium look
- Display: fixed dark-only themes (Terminal / Pixel / Tactical and others) that could render a washed-out white card under Light Mode — they now stay correctly dark regardless of system appearance
- Layout: tightened the home screen so the cards and bottom navigation fit cleanly on larger iPhones (Pro Max)
- Onboarding: refreshed the welcome sequence
- Performance and stability improvements

**Carried over from 2.5.4** (full detail in the 2.5.4 entry below)

- Redesigned paywall with a dedicated unlock action
- Modernized full-screen Vault viewer (restore / share / delete)
- Live encrypted storage usage on the Vault and App Lock screens
- Theme-aware redaction controls with surfaced export errors

---

## 2026-06-25 – Status: v2.5.4 still in review

A quick transparency note for anyone wondering where 2.5.4 went.

We submitted on June 24. Two days later, App Review came back — not with anything wrong in the app, but with the *text* of our App Store listing. The same description and keywords that have shipped without issue across roughly our last 20 updates over the past three months were, this time, flagged. App Review consistency remains an adventure.

To be clear: **nothing about the app, its features, or your data has changed.** This is purely store-page wording. We've revised the listing, resubmitted, and we're back in the queue waiting on a re-review.

We'll update here the moment it goes live. Thanks for your patience.

---

## 2026-06-24 – Version 2.5.4

- Vault: lock screen displays live encrypted storage usage, computed from on-disk file sizes without decrypting vault contents
- Vault: fixed a thumbnail/viewer desync — the paginated items loader cache is now keyed on the item set (count + id hash) rather than only sort/filter, so add/delete/restore can no longer serve a stale list
- Vault: modernized full-screen photo viewer (position counter, capture date, themed Restore / Share / Delete bar) with explicit restore confirmation
- App Lock screen security status capsule (cipher / biometric / on-device), consistent with the Vault lock screen
- Redaction editor: theme-aware controls and surfaced export errors that previously failed silently
- Removed non-functional repeating animations across themed components
- Performance and stability improvements

---

## 2026-06-11 – Version 2.5.3

- Redesigned Vault, Results & Review - cleaner in every premium theme
- Scan results now appear right on the home screen status card, embedded
- New adaptive photo grids (2–4 columns) with clearer actions
- Share redacted enhancements for premium themes
- "Ignore" is now "Mark Safe" - clearer what it does
- Polish and bug fixes

---

## 2026-05-31 – Version 2.5.2

- Ephemeral decryption keys: automatic RAM purge on scene phase transition
- Optimized background timeout before volatile memory scrubbing
- Zero-persistence architecture: no decrypted data survives app suspension
- Enhanced PIXEL and TERMINAL premium theme rendering
- Settings UI refactor: tabbed interface (Security/UI) for improved navigation hierarchy
- Internationalization improvements: refined onboarding flow and translation accuracy
- Canvas rendering optimizations with reduced draw cycle overhead

---

## 2026-05-23 – Version 2.5.1

- Scanning and vault performance optimizations
- Improved image viewing, zooming, caching, and rendering responsiveness
- Added Settings search for faster navigation
- Added two new Premium themes: Pixel Ghost and Terminal
- Full app-wide custom theming enhancements for all premium themes
- Enhanced onboarding flow and refined overall UI consistency
- Redaction editor fixes with improved reliability and style selection
- Reduced memory usage and visual overhead across themed components
- General stability improvements, UI refinements, and bug fixes

---

## 2026-05-09 – Version 2.4.2

- Faster batch scanning with optimized image processing
- Improved scan scheduling and incremental detection reliability [Pro]
- Enhanced background scan stability / outlier timeouts resolved [Pro]
- Audit Trail is now available from the Info page [Pro]
- Fixed Audit Trail URL
- Minor fixes and performance refinements

---

## 2026-05-07 – Version 2.4.1

- PhotoLibrary architecture refactor with improved component separation
- Fixed thread safety issues in background scan operations (MainActor enforcement)
- Reduced iCloud asset timeout from 20s to 10s for faster scan progression
- Removed verbose debug logging from scan execution hot paths
- DeAd theme visual enhancements [Premium]
- Settings & Info page layout improvements with better readability
- FAQ page redesign with section-specific color coding
- Interactive Audit Trail demo website [accessible from Info page & dro1d.org / nudefndr.com]

---

## 2026-04-16 – Version 2.3.4

- Audit Trail [Pro]:
- Audit trail now logs data export events with file size and format
- Enhanced audit logging with IPv6, failed auth tracking, image IDs and app version changes
- Improved vault performance for larger datasets (50+ items)
- Info page now shows app version, build number, and device/iOS details

---

## 2026-04-08 – Version 2.3.3

- Audit Trail [Pro]:
- Comprehensive security logging system tracking all scan operations, vault access events, and settings changes. Real-time event logging with severity filtering, category-based organization. Biometric authentication required to clear logs. Detailed metadata inspection.
- Data export available as plain txt or formatted csv.
- ProMotion Vault Engine [Pro]: 
- Re-engineered for speed. Asynchronous loading and advanced caching for stutter-free scrolling.
- Settings redesign & theme enhancements
- Rebuilt modular interface with improved navigation and color-coded security categories.

---

## 2026-03-28 – Version 2.3.2

- Advanced Time Range Scanning [Year and quarter-based]
- Batch processing with progressive result saving
- Improved Self-healing scan technology & auto-recovers from interruptions
- Enhanced scan control feedback and affordances
- iCloud photo timeout handling with retry mechanism
- Vault toggle on/off on home screen
- App interface & theming enhancements throughout

---

## 2026-02-20 – Version 2.3.1

- Swipe navigation added across the app for more natural movement between screens
- Multiple performance improvements - faster browsing, smoother scrolling, and reduced battery usage
- Optimized photo scanning and results (results & review pages) loading for significantly improved responsiveness
- Improved memory usage and storage calculation accuracy
- New premium app icons (8 designs) available in Settings
- Some speed & stability improvements and bug fixes

---

## 2026-02-16 – Version 2.2.5

- Faster thumbnail loading with improved performance
- Enhanced privacy controls on Results & Review screens
- Share Redacted now respects blur settings (Pro)
- UI refinements and bug fixes

---

## 2026-01-30 – Version 2.2.4

Bug Fixes:
- Fixed pause/resume functionality on some devices - scans now correctly save progress and resume from where you left off instead of restarting
- Improved scan progress accuracy when pausing mid-scan
- Removed additional progress indicator during active manual scans for cleaner UI

Performance Improvements
- Significantly faster incremental scanning - intelligently skips already-analyzed photos
- Optimized scan state persistence for better resume reliability

---

## 2026-01-22 – Version 2.2.3

**App Store Release**
- Enhanced background scan speed & efficiency - NuDefndr now automatically detects new photos and runs incremental scans
- Stuck Scans: Fixed outlier issue (diagnosed on 14 Pro) where scans could get stuck at 0%
- Added auto-recovery and "Clear Scan State" option in Settings ->Advanced
- Improved FAQ & translations

---

## 2026-01-18 – Version 2.2.2

**App Store Release**
- Added in-app status checker to verify Sensitive Content Warning setup
- Improved FAQ and setup instructions with visual guide during onboarding
- Fixed localization in Smart Scan settings
- Reminder: Enable "Sensitive Content Warning" in Settings → Privacy & Security

---

## 2026-01-14 – Version 2.2.1

**App Store Release**
- Vault performance upgrade: faster scrolling, huge memory reduction, smoother loading
- Instant thumbnail loading with smarter caching and better battery efficiency
- Clearer iCloud photo handling with better scan progress feedback
- Faster redaction processing with improved accuracy and new sharing options
- Added Chinese, Japanese, and Thai languages

---

## 2026-01-09 – Version 2.1.6

**App Store Release**
- Introduced Essential theme: softer, friendlier design with better light mode support
- UI polish and refinements across the app
- Enhanced scan progress view showing items found in real-time
- Improved Settings & Info page descriptions
- Refined & optimized onboarding flow

---

## 2025-12-28 – Version 2.1.5

**App Store Release**
- Added two new premium themes: Cyber and De-Ad with theme-specific visuals
- Improved home screen layout and visual hierarchy
- Enhanced vault status visibility with themed unlock button
- Reduced excess padding for cleaner layout on Pro Max
- Revamped onboarding experience with theme-aware launch animations
- Removed haptics from non-interactive animations

---

## 2025-12-22 – Version 2.1.4

**App Store Release**
- New flexible Monthly Access protocol added
- Redesigned upgrade screen
- Optimized app memory calculation logic
- Reduced latency for system diagnostics initialization
- Enhanced contrast for navigation controls in Dark Mode
- Feature status indicators now color-coded by category

---

## 2025-12-19 – Version 2.1.3

**App Store Release**
- Universal accessibility: VoiceOver support, Dynamic Type, Reduce Motion, High Contrast
- Faster vault thumbnail loading with enhanced caching
- Reduced layout calculations for smoother scrolling
- Home page background optimizations for lower battery usage
- Quick Search in Settings to find any setting instantly
- Vault Metrics: Pro users can display item count (off by default)
- FAQ completely redesigned with organized sections
- Vault lock screen displays real-time security metrics

---

## 2025-12-15 – Version 2.1.2

**App Store Release**
- Visual architecture overhaul: Pro Command Center with modular grid system
- New "System Status" hero monitor with active pulse animation
- Full-width "Initiate Scan" button for rapid engagement
- Configuration options relocated to Hero Card (Pro)
- Weekly Cycles: Free tier scanning now on weekly reset cycle
- Fixed layout jitter on scan triggers
- Dynamic pluralization for remaining scan counters

---

## 2025-12-08 – Version 2.1.1

**App Store Release**
- Jailbreak Defense: Multi-layer integrity system with 40+ checks
- Detection Engine: filesystem sweeps, sandbox tests, runtime analysis
- New full-screen warning view and persistent vault banner
- Configurable toggle under Settings → Security & Privacy
- Confidence-based risk scoring (Low → Certain)
- All analysis stays fully on-device
- Panic PIN flow improvements with technical breakdown
- Launch Animation toggle (Premium): optional boot animation bypass

---

## 2025-12-05 – Version 2.0

**App Store Release**
- Incremental scanning engine: 5-10× faster scans using timestamp skipping
- Manual and auto scans share unified completion state
- Range Logic: older assets skipped, modified items always re-analyzed
- Complete UI redesign for Home, Info, and Settings across all themes
- Background scheduling stabilized with strict single-request logic
- Expanded diagnostic logging with ISO-8601 precision

---

## 2025-11-30 – Version 1.6.8

**App Store Release**
- Privacy Blur: interface obfuscates when entering App Switcher
- Modular Command Deck: 3-Capsule Layout for rapid data assessment
- Tactical Controls: Cyber-Glass aesthetic buttons
- Zero latency: refactored architecture for instant responsiveness
- Metal Rendering: GPU-accelerated background grids
- Vault visual upgrade: new lock screen with seamless biometric flow

---

## 2025-11-19 – Version 1.6.7

**App Store Release**
- Auto-scan performance improvements (Premium)
- Fixed styling issues on home page & Review Screen
- Bug fixes & minor performance tweaks

---

## 2025-11-17 – Version 1.6.6

**App Store Release**
- Fixed frozen "Last Scan" timestamp (now updates in real-time)
- Redesigned Vault lock screen with cleaner aesthetic
- Improved Home screen status card, Results and Review screens

---

## 2025-11-15 – Version 1.6.5

**App Store Release**
- Smarter Auto-Scanning: perfect incremental scanning for Pro users
- Auto-scans and manual scans no longer interfere
- New adaptive catchup mode prevents gaps from iOS background delays
- Enhanced Premium Themes with improved polish
- Performance and stability improvements

---

## 2025-11-11 – Version 1.6.4

**App Store Release**
- Vault: Smart Sorting & date filters (Premium)
- Vault: Enhanced selection with stored last sort/filter choices (Premium)
- New Tactical and Ghost themes (Premium)
- Stealth enhancements & optional status-bar hiding (Premium)
- Themed launch animations (Premium)
- FAQ & Onboarding: updated and revised

---

## 2025-11-07 – Version 1.6.3

**App Store Release**
- Stealth theme (Premium): minimal tactical interface in pure blacks and grays
- Advanced Redaction Toolkit (Premium): Heavy Blur, Pixelate, Black Box options
- Safe sharing via AirDrop with redacted images
- Scans & review actions now limited for free users

---

## 2025-10-24 – Version 1.6.2

**App Store Release**
- iOS 26 compatibility updates
- UI enhancements
- Background scan optimizations
- Bug fixes

---

## 2025-08-31 – Version 1.6.1

**App Store Release**
- Faster thumbnail loading on newer devices (iPhone 15 Pro+)
- Optimized memory usage and smoother scrolling
- New Pro Feature: Share heavily redacted versions via AirDrop
- Clearer "Previously Scanned" messaging
- Better network efficiency for iCloud Photos users
- Improved scan completion detection

---

## 2025-08-27 – Version 1.5.9

**App Store Release**
- "NEW" items persist correctly until viewing results
- Faster thumbnails, UI polish, bug fixes

---

## 2025-08-14 – Version 1.5.8

**App Store Release**
- Enhanced UI & refined Pro experience with premium visual treatments
- Vault & Scan Results enhancements
- PANIC_PIN lockdown & UI enhancement
- Performance improvements & bug fixes

---

## 2025-08-11 – Version 1.5.7

**App Store Release**
- Improved Options Menu: more compact and polished
- Better Background Task Logic: reduced over-scheduling
- Optimized performance and app stability
- Visual consistency: unified design across Settings, FAQ, and Info

---

## 2025-08-06 – Version 1.5.6

**App Store Release**
- Auto-scan now scans last 24 hours (changed from 7 days) for efficiency (Premium)
- Fixed Face ID app lock system on some models
- App lock: re-added 60-second grace period
- Instant Premium feature activation after purchase
- Improved toast notification system reliability
- Enhanced button alignment in home screen scan interface

---

## 2025-08-04 – Version 1.5.5

**App Store Release**
- Refined Home Screen with sleek Options menu
- Redesigned Settings: cleaner layout, color scheme picker, clearer toggles
- Smart-Scan & Scan_Range quick toggles in Settings
- Performance boosts: faster thumbnails, improved haptics
- Background Auto-Scan runs even when app is closed (within iOS limits)

---

## 2025-07-14 – Version 1.5.4

**App Store Release**
- Smart Scan Targets: Favorites, Selfies, Screenshots, Panoramas, custom albums
- Camera-Only Scan: exclude social media saves and screenshots
- Custom Album Selection for precise analysis
- Improved thumbnail quality
- Refined UI with better visual feedback and loading states

---

## 2025-07-04 – Version 1.5.3

**App Store Release**
- Concurrency optimized for paused manual scans / auto scan discardment
- Compact layout improved while manual scan is paused / in progress
- Bug fixes

---

## 2025-06-26 – Version 1.5.2

**App Store Release**
- Auto-Scan Toast (Premium): quick banner for background scan completion
- Smarter Fresh-Start: cancelling specific range scan guarantees full sweep next run
- Found & Processed counts visible on home screen for paused scans

---

## Earlier Releases

For app versions prior to 1.5.2 (pre-June 2025), see the [App Store listing](https://apps.apple.com/app/nudefndr/id6745149292).

---

## Repository Documentation Updates

### 2026-07-26

**Corrections**

A review of this repository against the shipping code found several claims that
were wrong or overstated. Correcting them in public, because a transparency
project that misstates its own behaviour is worth less than one that fixes it.

- **"Zero network activity" was false.** The README and FAQ claimed the app was
  100% offline with zero network activity. NuDefndr validates App Store
  subscriptions through RevenueCat, which makes requests on launch and whenever
  entitlements are checked. It sees an anonymous subscriber identifier and
  entitlement status — no photos, no scan data — and it remains the app's only
  outbound traffic, with no analytics SDK, crash reporter or tracking. But
  "zero network activity" was not true and is now stated accurately.
- **"Vault paths are explicitly excluded from iCloud backups" was false.** No
  backup-exclusion attribute is set; encrypted vault files can appear in a
  backup. The protection is that the *key* is
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and never syncs, so restored
  ciphertext cannot be opened — which is why Key Recovery exists. The
  CHANGELOG already described that behaviour correctly; the README and
  ARCHITECTURE contradicted it.
- **PBKDF2 iteration counts were wrong and understated.** The docs cited 100,000
  iterations as the app's key derivation. The vault key is not derived at all —
  it is random and Keychain-stored. Production PBKDF2 is 310,000 iterations for
  PIN credentials and 600,000 for key-backup passphrase wrapping. The published
  `VaultEncryption.swift` helper that carries the 100,000 figure is not the
  vault's key path and is now annotated as such.
- **Removed incorrect terminology.** "Hardware-level tamper detection"
  (Poly1305 is a software MAC), "forward secrecy" (there is no session key
  exchange; vault files use one long-lived key), "keys… bound to the physical
  hardware" (a Keychain accessibility class, not Secure Enclave), and "zero disk
  persistence" for a key that is deliberately persisted in the Keychain.
- **Audit Trail description corrected.** It was described as an "immutable
  ledger" that is "strictly append-only". It is a JSON file in the app
  container, it can be cleared from within the app behind Face ID, and anyone
  with filesystem access could alter it. It is a personal record, not forensic
  evidence.
- **Background-scan guidance corrected.** The FAQ previously suggested turning
  App Lock off to diagnose background scans. App Lock does not gate background
  scans; iOS scheduling budgets do. No one should be advised to weaken a
  security setting as a troubleshooting step.

### 2026-01-16

**Transparency Repository**
- Added SENSITIVE_CONTENT_WARNING.md with setup/testing guidance
- Added availability helper documentation in ContentAnalyzer
- Added "What's New" section to README
- Added system integration section to ARCHITECTURE
- Added FAQ entries for Sensitive Content Warning
- Minor docs polish

**Security**
- No changes in data collection (still zero network), no new telemetry