// NuDefndr - nudefndr.com
// Transparency Repository - Vault camera capture session (v2.6.3)

import AVFoundation
import UIKit
import Combine

@MainActor
final class VaultCameraController: ObservableObject {
    enum Availability: Equatable {
        case unknown
        case ready
        case denied
        case unavailable
    }

    @Published private(set) var availability: Availability = .unknown
    @Published private(set) var position: AVCaptureDevice.Position = .back
    @Published var isFlashOn = false
    @Published private(set) var isZoomedIn = false
    @Published private(set) var isCapturing = false

    private let engine = CameraEngine()

    var session: AVCaptureSession { engine.session }

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

        availability = await engine.configure() ? .ready : .unavailable
    }

    func start() {
        guard availability == .ready else { return }
        Task { _ = await engine.start() }
    }

    func stop() {
        Task { _ = await engine.stop() }
    }

    func toggleCamera() {
        let target: AVCaptureDevice.Position = (position == .back) ? .front : .back
        Task {
            guard await engine.switchCamera(to: target) else { return }
            position = target
            isZoomedIn = false
        }
    }

    func toggleFlash() { isFlashOn.toggle() }

    func toggleZoom() {
        let target: CGFloat = isZoomedIn ? 1.0 : 2.0
        Task {
            guard await engine.setZoom(target) else { return }
            isZoomedIn.toggle()
        }
    }

    func capturePhoto() async -> Data? {
        guard availability == .ready, !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }
        return await engine.capture(flashMode: isFlashOn ? .on : .off)
    }
}

private final class CameraEngine: @unchecked Sendable {
    let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "com.dro1d.nudefndr.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var pendingDelegates: [ObjectIdentifier: CaptureDelegate] = [:]

    static var hasAnyCamera: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
            || AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
    }

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
                    self.photoOutput.maxPhotoQualityPrioritization = .quality
                }

                self.session.commitConfiguration()

                self.isConfigured = self.canTakePhoto
                continuation.resume(returning: self.isConfigured)
            }
        }
    }

    private var canTakePhoto: Bool {
        videoInput != nil
            && session.outputs.contains(photoOutput)
            && photoOutput.connection(with: .video) != nil
    }

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
                    if (try? device.lockForConfiguration()) != nil {
                        device.videoZoomFactor = 1.0
                        device.unlockForConfiguration()
                    }
                    swapped = true
                } else if let previous = self.videoInput, self.session.canAddInput(previous) {
                    self.session.addInput(previous)
                }
                self.session.commitConfiguration()

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
                guard self.session.isRunning, self.canTakePhoto else {
                    AppLogger.vault.error("Capture refused: session not ready")
                    continuation.resume(returning: nil)
                    return
                }

                let delegate = CaptureDelegate(
                    onData: { data in continuation.resume(returning: data) },
                    onFinished: { [weak self] id in
                        self?.queue.async { self?.pendingDelegates[id] = nil }
                    }
                )
                self.pendingDelegates[ObjectIdentifier(delegate)] = delegate

                let settings = self.photoOutput.availablePhotoCodecTypes.contains(.hevc)
                    ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                    : AVCapturePhotoSettings()
                settings.photoQualityPrioritization = .quality
                if self.photoOutput.supportedFlashModes.contains(flashMode) {
                    settings.flashMode = flashMode
                }

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

private final class CaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let onData: (Data?) -> Void
    private let onFinished: (ObjectIdentifier) -> Void
    private let lock = NSLock()
    private var hasCompleted = false

    init(onData: @escaping (Data?) -> Void, onFinished: @escaping (ObjectIdentifier) -> Void) {
        self.onData = onData
        self.onFinished = onFinished
    }

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

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        deliver(nil)
        onFinished(ObjectIdentifier(self))
    }
}
