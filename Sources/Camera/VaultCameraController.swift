// NudeFndr - nudefndr.com
// Transparency Repository - Vault camera capture session (v2.6.2)
//
// Published in full because the claim it backs is a negative one: a photo taken
// in this app is never written to the photo library. That is not something a
// screenshot can show, and it is not something the app can prove by telling you.
// What it can do is hand you the file, so you can check that the calls which
// would break the claim are simply not in it.
//
// The bytes go: AVCapturePhotoOutput -> fileDataRepresentation() -> Data held in
// memory -> VaultManager.addCapturedImage, which strips metadata and seals with
// ChaCha20-Poly1305 before anything reaches disk. See ARCHITECTURE.md.




import AVFoundation
import UIKit
import Combine

/// Runs the camera and hands its bytes to the caller. It never stores anything.
///
/// The reason this exists rather than a `UIImagePickerController` or a
/// `PHPickerViewController` is the route the bytes take.
/// `AVCapturePhotoOutput.fileDataRepresentation()` returns a `Data` held in
/// memory, which goes straight to `VaultManager.addCapturedImage` and is sealed
/// there. A picker writes the photo into the library first and leaves removing
/// it as a promise — and a promise that runs after the fact is exactly the gap
/// this feature exists to close. **Nothing in this file references
/// `PHPhotoLibrary`, and nothing in it writes a file.**
///
/// **Isolation.** This type is main-actor: it publishes the state the UI reads.
/// It owns *no* AVFoundation object. Everything mutable that AVFoundation
/// touches lives in `CameraEngine` below, which is not actor-isolated and runs
/// entirely on its own serial queue. The first cut of this file kept the session
/// here and worked on it inside `sessionQueue.async`, which reads fine and is a
/// data race: main-actor state mutated from a background queue.
@MainActor
final class VaultCameraController: ObservableObject {

    /// Why there is no preview, when there isn't one.
    ///
    /// `.unavailable` is the simulator case and is not an error worth showing a
    /// user — it cannot happen on a device with a camera, and on a device
    /// without one there is nothing to say beyond the absence.
    enum Availability: Equatable {
        case unknown
        case ready
        /// Permission refused. The only state with somewhere for the user to go.
        case denied
        /// No capture device at all — every simulator, and nothing else.
        case unavailable
    }

    @Published private(set) var availability: Availability = .unknown
    @Published private(set) var position: AVCaptureDevice.Position = .back
    @Published var isFlashOn = false
    @Published private(set) var isZoomedIn = false
    /// True from shutter press until the bytes are in hand, so the band can
    /// refuse a second press without growing a spinner.
    @Published private(set) var isCapturing = false

    private let engine = CameraEngine()

    /// Handed to `AVCaptureVideoPreviewLayer` on the main thread, which is what
    /// Apple's own sample code does. The session object itself is a `let` the
    /// engine never replaces; only its inputs and outputs change, and those
    /// change on the engine's queue.
    var session: AVCaptureSession { engine.session }

    // MARK: - Permission

    /// Asks for the camera, and reports back what the answer means for the UI.
    ///
    /// Deliberately not called from `init`: the permission sheet should appear
    /// when the user opens the camera, not when the screen that owns it is
    /// constructed.
    func requestAccessAndConfigure() async {
        guard CameraEngine.hasAnyCamera else {
            availability = .unavailable
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { availability = .denied; return }
        case .denied, .restricted:
            availability = .denied
            return
        @unknown default:
            availability = .denied
            return
        }

        // `.ready` only if the session can actually take a photo. It used to be
        // set unconditionally, so a session that failed to configure still
        // reported ready and armed a shutter that would crash.
        availability = await engine.configure() ? .ready : .unavailable
    }

    // MARK: - Session lifecycle

    /// Starts the preview. Safe to call repeatedly.
    func start() {
        guard availability == .ready else { return }
        Task { _ = await engine.start() }
    }

    /// Stops the preview.
    ///
    /// Called on every route out of the foreground, not just on dismissal. A
    /// running session is a live view of the room the phone is in; leaving it
    /// running behind the app switcher is the same class of leak as an
    /// unshielded vault grid.
    func stop() {
        Task { _ = await engine.stop() }
    }

    // MARK: - Controls

    func toggleCamera() {
        let target: AVCaptureDevice.Position = (position == .back) ? .front : .back
        Task {
            guard await engine.switchCamera(to: target) else { return }
            position = target
            // Zoom belongs to the device that was zoomed, not to the session, so
            // switching cameras resets it rather than reporting a zoom the new
            // lens is not at.
            isZoomedIn = false
        }
    }

    func toggleFlash() { isFlashOn.toggle() }

    /// 1× / 2×. A zoom factor rather than a lens switch, so it behaves the same
    /// on a phone with one rear camera as on a phone with three.
    func toggleZoom() {
        let target: CGFloat = isZoomedIn ? 1.0 : 2.0
        Task {
            guard await engine.setZoom(target) else { return }
            isZoomedIn.toggle()
        }
    }

    // MARK: - Capture

    /// Takes one photo and returns its bytes. Returns nil if the capture failed.
    ///
    /// The bytes are the caller's problem from here — this type keeps no copy,
    /// and there is no disk anywhere on the path.
    func capturePhoto() async -> Data? {
        guard availability == .ready, !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }
        return await engine.capture(flashMode: isFlashOn ? .on : .off)
    }
}

/// The AVFoundation objects, and the only thread that is allowed to touch them.
///
/// Not actor-isolated and not `Sendable` by inference — `@unchecked`, with
/// `queue` as the stated reason. Every stored property below is read and written
/// exclusively inside a `queue` block, so the serial queue is the mutual
/// exclusion. An `actor` would be the tidier spelling, but
/// `AVCaptureSession.startRunning()` blocks its caller and configuration has to
/// be bracketed by `beginConfiguration`/`commitConfiguration` on one thread, so
/// a serial queue is the shape AVFoundation actually asks for.
///
/// `session` is the one exception, deliberately: it is a `let` handed to the
/// preview layer on the main thread and never reassigned.
private final class CameraEngine: @unchecked Sendable {

    let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "com.dro1d.nudefndr.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var isConfigured = false
    /// Tracks how the device is actually held, so a capture can be sealed the
    /// right way up.
    ///
    /// Nothing set a rotation before, and the iPhone target ships landscape — so
    /// holding the phone sideways stored the photo 90° out. Unlike a library
    /// photo that is not fixable afterwards: the vault has no rotate control, and
    /// the original was never written anywhere.
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    /// `AVCapturePhotoOutput` does not retain its delegate, so one that only
    /// lived as long as the `capturePhoto` call would be gone before the photo
    /// came back. Held here, on the queue, and dropped when it finishes.
    private var pendingDelegates: [ObjectIdentifier: CaptureDelegate] = [:]

    static var hasAnyCamera: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
            || AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
    }

    /// Returns false if the session did not end up able to take a photo.
    ///
    /// It used to return `Void` and swallow every failure — a throwing
    /// `AVCaptureDeviceInput(device:)` or a refused `canAddInput` left a session
    /// with no input, while the caller still published `.ready`. The next shutter
    /// press then reached `capturePhoto` with no active video connection, which
    /// AVFoundation answers with an `NSInvalidArgumentException`: not catchable in
    /// Swift, so a hard crash.
    func configure() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            queue.async {
                guard !self.isConfigured else {
                    continuation.resume(returning: self.canTakePhoto)
                    return
                }

                self.session.beginConfiguration()
                self.session.sessionPreset = .photo

                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                   let input = try? AVCaptureDeviceInput(device: device),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.videoInput = input
                    self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(
                        device: device, previewLayer: nil)
                }

                if self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)
                    // Set before the configuration commits: a per-shot
                    // prioritisation above this ceiling throws at capture time.
                    self.photoOutput.maxPhotoQualityPrioritization = .quality
                }

                self.session.commitConfiguration()

                // Only now, and only if it actually worked. Marking it configured
                // before the work meant a failed configuration was never retried.
                self.isConfigured = self.canTakePhoto
                continuation.resume(returning: self.isConfigured)
            }
        }
    }

    /// Whether a `capturePhoto` call would find something to capture with.
    /// Must be read on `queue`.
    private var canTakePhoto: Bool {
        videoInput != nil
            && session.outputs.contains(photoOutput)
            && photoOutput.connection(with: .video) != nil
    }

    /// Returns whether the session is running afterwards, so the caller can
    /// publish that rather than guess at it.
    func start() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            queue.async {
                if !self.session.isRunning { self.session.startRunning() }
                continuation.resume(returning: self.session.isRunning)
            }
        }
    }

    func stop() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            queue.async {
                if self.session.isRunning { self.session.stopRunning() }
                continuation.resume(returning: self.session.isRunning)
            }
        }
    }

    func switchCamera(to target: AVCaptureDevice.Position) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            queue.async {
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: target),
                      let newInput = try? AVCaptureDeviceInput(device: device) else {
                    continuation.resume(returning: false)
                    return
                }

                self.session.beginConfiguration()
                for input in self.session.inputs { self.session.removeInput(input) }
                var swapped = false
                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                    self.videoInput = newInput
                    self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(
                        device: device, previewLayer: nil)
                    // `videoZoomFactor` belongs to the device, so the old lens
                    // stayed zoomed: back → 2× → front → back came back at 2×
                    // with the label reading 1×, and the next tap did nothing.
                    if (try? device.lockForConfiguration()) != nil {
                        device.videoZoomFactor = 1.0
                        device.unlockForConfiguration()
                    }
                    swapped = true
                } else if let previous = self.videoInput, self.session.canAddInput(previous) {
                    // Put the old one back rather than committing a session with
                    // no input at all, which would freeze the preview.
                    self.session.addInput(previous)
                }
                self.session.commitConfiguration()

                // If neither the new input nor the old one could go back, the
                // session now has no input and the next shutter press would
                // crash. Say so rather than leaving the caller to find out.
                // Reported, not just recorded. Setting `isConfigured = false` alone
                // left `availability` on `.ready` with nothing ever calling
                // `configure()` again — a frozen preview under a live-looking
                // shutter that answered every press with an error.
                if !self.canTakePhoto { self.isConfigured = false }
                continuation.resume(returning: swapped && self.canTakePhoto)
            }
        }
    }

    func setZoom(_ factor: CGFloat) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            queue.async {
                guard let device = self.videoInput?.device,
                      (try? device.lockForConfiguration()) != nil else {
                    continuation.resume(returning: false)
                    return
                }
                device.videoZoomFactor = min(max(factor, 1.0), device.activeFormat.videoMaxZoomFactor)
                device.unlockForConfiguration()
                continuation.resume(returning: true)
            }
        }
    }

    func capture(flashMode: AVCaptureDevice.FlashMode) async -> Data? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            queue.async {
                // AVFoundation raises `NSInvalidArgumentException` — uncatchable
                // from Swift — if there is no active video connection. Refusing
                // here turns a crash into a nil.
                guard self.session.isRunning, self.canTakePhoto else {
                    AppLogger.vault.error("Capture refused: session not ready")
                    continuation.resume(returning: nil)
                    return
                }

                let delegate = CaptureDelegate(
                    // Resumes the caller. May fire on either callback.
                    onData: { data in continuation.resume(returning: data) },
                    // Fires only on `didFinishCaptureFor`, the callback AVFoundation
                    // documents as last for a request. The dictionary is the only
                    // strong reference — the output does not retain its delegate —
                    // so releasing it from `onData` (which normally runs on the
                    // *earlier* callback) let the object die between the two, and
                    // the terminal callback was simply dropped. Apple's own AVCam
                    // removes from its in-progress map here for this reason.
                    onFinished: { [weak self] id in
                        self?.queue.async { self?.pendingDelegates[id] = nil }
                    }
                )
                self.pendingDelegates[ObjectIdentifier(delegate)] = delegate

                // HEIF where the device supports it, matching what the vault
                // already stores for library imports since 2.5.8. The strip path
                // is covered for HEIC by `MetadataStripSelfTest`.
                let settings = self.photoOutput.availablePhotoCodecTypes.contains(.hevc)
                    ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                    : AVCapturePhotoSettings()
                settings.photoQualityPrioritization = .quality
                if self.photoOutput.supportedFlashModes.contains(flashMode) {
                    settings.flashMode = flashMode
                }

                // Horizon-level, not interface orientation: this is the angle that
                // makes the sealed photo match what the user was pointing at, even
                // with rotation lock on.
                if let connection = self.photoOutput.connection(with: .video),
                   let angle = self.rotationCoordinator?.videoRotationAngleForHorizonLevelCapture,
                   connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }

                self.photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }
}

/// One shot's delegate.
///
/// Implements **both** the per-image callback and the terminal one.
/// `didFinishProcessingPhoto` is not guaranteed for a request that ends without
/// producing an image — tearing the session down mid-capture is the easy way to
/// see that, and swiping to the app switcher right after the shutter does
/// exactly that. When it did not arrive the continuation leaked, so
/// `capturePhoto`'s `defer` never ran, `isCapturing` stayed true forever, and the
/// shutter was dead for the rest of the screen's life with nothing on screen to
/// explain it. `didFinishCaptureFor` always arrives last, so it is the backstop.
///
/// `@unchecked Sendable` with a real lock, not a promise: two callbacks can now
/// reach `hasCompleted`, so serial delivery is no longer an argument that one
/// thread touches it.
private final class CaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let onData: (Data?) -> Void
    private let onFinished: (ObjectIdentifier) -> Void
    private let lock = NSLock()
    private var hasCompleted = false

    init(onData: @escaping (Data?) -> Void, onFinished: @escaping (ObjectIdentifier) -> Void) {
        self.onData = onData
        self.onFinished = onFinished
    }

    /// Hands back the bytes exactly once, whichever callback gets here first.
    /// The completion runs outside the lock so it cannot deadlock against it.
    private func deliver(_ data: Data?) {
        lock.lock()
        let alreadyDone = hasCompleted
        hasCompleted = true
        lock.unlock()
        guard !alreadyDone else { return }
        onData(data)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            AppLogger.vault.error("Capture failed: \(error.localizedDescription, privacy: .private)")
            deliver(nil)
            return
        }
        deliver(photo.fileDataRepresentation())
    }

    /// Always delivered last for a request, including requests that never produce
    /// an image — tearing the session down mid-capture is the easy way to see
    /// that, and swiping to the app switcher right after the shutter does exactly
    /// that. Without this the continuation leaked, `isCapturing` stuck true, and
    /// the shutter was dead for the rest of the screen's life with nothing on
    /// screen to explain it.
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        deliver(nil)
        onFinished(ObjectIdentifier(self))
    }
}
