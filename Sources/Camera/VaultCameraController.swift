// NuDefndr - nudefndr.com
// Transparency Repository - Vault camera capture session (v2.6.9)

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
    @Published private(set) var zoom: CGFloat = 1
    @Published private(set) var isCapturing = false

    private let engine = CameraEngine()
    private var lens = CameraLens.wideOnly
    private var pinchBase: CGFloat = 1

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

        if let lens = await engine.configure() {
            self.lens = lens
            zoom = 1
            availability = .ready
        } else {
            availability = .unavailable
        }
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
            guard let lens = await engine.switchCamera(to: target) else { return }
            position = target
            self.lens = lens
            applyZoom(1)
        }
    }

    func toggleFlash() { isFlashOn.toggle() }

    func cycleZoom() {
        let stops = lens.stops
        applyZoom(stops.first { $0 > zoom + 0.05 } ?? stops[0])
    }

    func pinchBegan() { pinchBase = zoom }

    func pinchChanged(scale: CGFloat) { applyZoom(pinchBase * scale) }

    var zoomLabel: String { CameraLens.label(zoom) }

    private func applyZoom(_ value: CGFloat) {
        guard availability == .ready else { return }
        let clamped = min(max(value, lens.minZoom), lens.maxZoom)
        zoom = clamped
        engine.setZoom(clamped)
    }

    func focus(at devicePoint: CGPoint) {
        guard availability == .ready else { return }
        engine.focus(at: devicePoint)
    }

    func capturePhoto() async -> Data? {
        guard availability == .ready, !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }
        return await engine.capture(flashMode: isFlashOn ? .on : .off)
    }
}

struct CameraLens: Sendable, Equatable {
    var wideFactor: CGFloat
    var minZoom: CGFloat
    var maxZoom: CGFloat

    static let wideOnly = CameraLens(wideFactor: 1, minZoom: 1, maxZoom: 2)

    static let zoomCeiling: CGFloat = 10

    var stops: [CGFloat] {
        let all: [CGFloat] = [0.5, 1, 2]
        let reachable = all.filter { $0 >= minZoom - 0.01 && $0 <= maxZoom + 0.01 }
        return reachable.isEmpty ? [1] : reachable
    }

    static func label(_ zoom: CGFloat) -> String {
        let tenths = (zoom * 10).rounded() / 10
        return tenths == tenths.rounded()
            ? "\(Int(tenths))×"
            : String(format: "%.1f×", Double(tenths))
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
    private var lens = CameraLens.wideOnly
    private var zoom: CGFloat = 1
    private var subjectAreaObserver: NSObjectProtocol?

    init() {
        subjectAreaObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.subjectAreaDidChangeNotification, object: nil, queue: nil
        ) { [weak self] note in
            guard let id = (note.object as? AVCaptureDevice)?.uniqueID else { return }
            guard let engine = self else { return }
            engine.queue.async { engine.resetFocus(ifDevice: id) }
        }
    }

    deinit {
        if let subjectAreaObserver { NotificationCenter.default.removeObserver(subjectAreaObserver) }
    }

    private static func device(at position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if position == .back {
            let spanning: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera]
            for type in spanning {
                if let device = AVCaptureDevice.default(type, for: .video, position: .back) { return device }
            }
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    private static func lens(of device: AVCaptureDevice) -> CameraLens {
        var wideFactor: CGFloat = 1
        if device.constituentDevices.first?.deviceType == .builtInUltraWideCamera,
           let switchOver = device.virtualDeviceSwitchOverVideoZoomFactors.first {
            wideFactor = max(CGFloat(truncating: switchOver), 1)
        }
        let minZoom = device.minAvailableVideoZoomFactor / wideFactor
        let maxZoom = min(device.maxAvailableVideoZoomFactor / wideFactor, CameraLens.zoomCeiling)
        return CameraLens(wideFactor: wideFactor, minZoom: min(minZoom, 1), maxZoom: max(maxZoom, 1))
    }

    private func adopt(_ device: AVCaptureDevice) {
        lens = Self.lens(of: device)
        zoom = 1
        applyZoom(to: device)
    }

    private func applyZoom(to device: AVCaptureDevice) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        let factor = zoom * lens.wideFactor
        device.videoZoomFactor = min(max(factor, device.minAvailableVideoZoomFactor),
                                     device.maxAvailableVideoZoomFactor)
        device.unlockForConfiguration()
    }

    static var hasAnyCamera: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
            || AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
    }

    func configure() async -> CameraLens? {
        await withCheckedContinuation { (continuation: CheckedContinuation<CameraLens?, Never>) in
            queue.async {
                guard !self.isConfigured else {
                    continuation.resume(returning: self.canTakePhoto ? self.lens : nil)
                    return
                }

                self.session.beginConfiguration()
                self.session.sessionPreset = .photo

                if let device = Self.device(at: .back),
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
                if self.isConfigured, let device = self.videoInput?.device { self.adopt(device) }
                continuation.resume(returning: self.isConfigured ? self.lens : nil)
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
                if !self.session.isRunning {
                    self.session.startRunning()
                    if self.session.isRunning, let device = self.videoInput?.device {
                        self.applyZoom(to: device)
                    }
                }
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

    func switchCamera(to target: AVCaptureDevice.Position) async -> CameraLens? {
        await withCheckedContinuation { (continuation: CheckedContinuation<CameraLens?, Never>) in
            queue.async {
                guard let device = Self.device(at: target),
                      let newInput = try? AVCaptureDeviceInput(device: device) else {
                    continuation.resume(returning: nil)
                    return
                }

                if let old = self.videoInput?.device { self.resetFocus(ifDevice: old.uniqueID) }
                self.session.beginConfiguration()
                for input in self.session.inputs { self.session.removeInput(input) }
                var swapped = false
                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                    self.videoInput = newInput
                    self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(
                        device: device, previewLayer: nil)
                    swapped = true
                } else if let previous = self.videoInput, self.session.canAddInput(previous) {
                    self.session.addInput(previous)
                }
                self.session.commitConfiguration()

                if !self.canTakePhoto { self.isConfigured = false }
                guard swapped, self.canTakePhoto else {
                    if let previous = self.videoInput?.device { self.adopt(previous) }
                    continuation.resume(returning: nil)
                    return
                }
                self.adopt(device)
                continuation.resume(returning: self.lens)
            }
        }
    }

    func setZoom(_ zoom: CGFloat) {
        queue.async {
            self.zoom = zoom
            guard let device = self.videoInput?.device else { return }
            self.applyZoom(to: device)
        }
    }

    func focus(at point: CGPoint) {
        queue.async {
            guard let device = self.videoInput?.device,
                  (try? device.lockForConfiguration()) != nil else { return }
            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported,
               device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposurePointOfInterest = point
                device.exposureMode = .continuousAutoExposure
            }
            device.isSubjectAreaChangeMonitoringEnabled = true
            device.unlockForConfiguration()
        }
    }

    private func resetFocus(ifDevice id: String) {
        guard let device = videoInput?.device, device.uniqueID == id,
              (try? device.lockForConfiguration()) != nil else { return }
        let centre = CGPoint(x: 0.5, y: 0.5)
        if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = centre }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = centre }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        device.isSubjectAreaChangeMonitoringEnabled = false
        device.unlockForConfiguration()
    }

    func capture(flashMode: AVCaptureDevice.FlashMode) async -> Data? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            queue.async { [self] in
                guard self.session.isRunning, self.canTakePhoto else {
                    AppLogger.vault.error("Capture refused: session not ready")
                    continuation.resume(returning: nil)
                    return
                }

                let delegate = CaptureDelegate(
                    onData: { data in continuation.resume(returning: data) },
                    onFinished: { [weak self] id in
                        guard let engine = self else { return }
                        engine.queue.async { engine.pendingDelegates[id] = nil }
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
