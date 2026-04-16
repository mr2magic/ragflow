# CLAUDE_HARDWARE.md — Device Hardware APIs

## Hardware Capability Matrix

Always check before using. Never assume hardware is present.

```swift
// Core/Hardware/HardwareCapabilities.swift
struct HardwareCapabilities {
    static var hasLiDAR: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    static var hasTrueDepth: Bool {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTrueDepthCamera],
            mediaType: .video,
            position: .front
        ).devices.isEmpty == false
    }

    static var hasProRAW: Bool {
        guard let device = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) else { return false }
        return device.activeFormat.isVideoHDRSupported  // proxy check
    }

    static var hasUltraWide: Bool {
        AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) != nil
    }

    static var hasNeuralEngine: Bool {
        // All A12+ devices have ANE; check via MLComputeUnits availability
        let config = MLModelConfiguration()
        config.computeUnits = .all
        return true   // safe assumption for iOS 26 min deployment
    }

    static var supportsARKit: Bool {
        ARConfiguration.isSupported
    }

    static var hasBarometer: Bool {
        CMAltimeter.isRelativeAltitudeAvailable()
    }

    static var hasMotionSensors: Bool {
        CMMotionManager().isDeviceMotionAvailable
    }
}
```

---

## Camera System

### Multi-Camera Session (simultaneous front + back)

```swift
@CameraActor
final class MultiCameraService {
    private let session = AVCaptureMultiCamSession()
    private var photoOutput = AVCapturePhotoOutput()

    func configure() throws {
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            throw HardwareError.notSupported("MultiCam requires iPhone XS or later")
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // Back camera — main
        let backDevice = try AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            .orThrow(HardwareError.deviceNotFound)
        let backInput = try AVCaptureDeviceInput(device: backDevice)
        session.addInputWithNoConnections(backInput)

        // Front camera — secondary
        let frontDevice = try AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            .orThrow(HardwareError.deviceNotFound)
        let frontInput = try AVCaptureDeviceInput(device: frontDevice)
        session.addInputWithNoConnections(frontInput)

        session.addOutput(photoOutput)
        photoOutput.isAppleProRAWEnabled = photoOutput.isAppleProRAWSupported
        photoOutput.maxPhotoQualityPrioritization = .quality
    }

    func startRunning() { session.startRunning() }
    func stopRunning()  { session.stopRunning() }
}
```

### Photo Capture with ProRAW + Photon Mapping (iOS 26)

```swift
func capturePhoto() async throws -> AVCapturePhoto {
    try await withCheckedThrowingContinuation { continuation in
        let settings = AVCapturePhotoSettings()
        if photoOutput.isAppleProRAWSupported {
            let proRAWFormat = photoOutput.availableRawPhotoPixelFormatTypes
                .first(where: { AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) })
            if let format = proRAWFormat {
                settings = AVCapturePhotoSettings(rawPixelFormatType: format)
            }
        }
        settings.flashMode = .auto
        settings.photoQualityPrioritization = .quality

        photoOutput.capturePhoto(with: settings, delegate: PhotoCaptureDelegate(continuation: continuation))
    }
}
```

### Cinematic Mode / Video Stabilization

```swift
func configureCinematicMode(for connection: AVCaptureConnection) {
    // Cinematic mode (iOS 15+, enhanced in iOS 26)
    if connection.isVideoStabilizationSupported {
        connection.preferredVideoStabilizationMode = .cinematicExtended
    }
}
```

---

## LiDAR & Depth

```swift
// ARKit 6 world tracking with mesh reconstruction
func startLiDARSession() {
    guard HardwareCapabilities.hasLiDAR else { return }

    let config = ARWorldTrackingConfiguration()
    config.sceneReconstruction = .meshWithClassification
    config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
    config.environmentTexturing = .automatic

    arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
}

// RoomPlan 2 — room capture
import RoomPlan

func startRoomCapture() {
    let captureSession = RoomCaptureSession()
    let config = RoomCaptureSession.Configuration()
    captureSession.run(configuration: config)

    // Access results
    captureSession.delegate = self
}

extension RoomCaptureDelegate: RoomCaptureSessionDelegate {
    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        // room.walls, room.doors, room.windows, room.objects
    }
}

// Point cloud from depth data
func pointCloud(from depthMap: CVPixelBuffer, intrinsics: simd_float3x3) -> [SIMD3<Float>] {
    var points: [SIMD3<Float>] = []
    let width = CVPixelBufferGetWidth(depthMap)
    let height = CVPixelBufferGetHeight(depthMap)

    CVPixelBufferLockBaseAddress(depthMap, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

    let buffer = unsafeBitCast(CVPixelBufferGetBaseAddress(depthMap), to: UnsafePointer<Float32>.self)
    let fx = intrinsics[0][0], fy = intrinsics[1][1]
    let cx = intrinsics[2][0], cy = intrinsics[2][1]

    for y in 0..<height {
        for x in 0..<width {
            let depth = buffer[y * width + x]
            if depth > 0 {
                let px = (Float(x) - cx) * depth / fx
                let py = (Float(y) - cy) * depth / fy
                points.append(SIMD3(px, py, depth))
            }
        }
    }
    return points
}
```

---

## Motion & Core Motion

```swift
actor MotionService {
    private let manager = CMMotionManager()
    private let queue = OperationQueue()

    func deviceMotionStream(interval: TimeInterval = 1.0/60.0) -> AsyncStream<CMDeviceMotion> {
        AsyncStream { continuation in
            guard manager.isDeviceMotionAvailable else {
                continuation.finish()
                return
            }
            manager.deviceMotionUpdateInterval = interval
            manager.startDeviceMotionUpdates(to: queue) { motion, error in
                if let motion { continuation.yield(motion) }
                else if error != nil { continuation.finish() }
            }
            continuation.onTermination = { _ in
                self.manager.stopDeviceMotionUpdates()
            }
        }
    }

    // Attitude for AR overlays
    func currentAttitude() -> CMAttitude? {
        manager.deviceMotion?.attitude
    }

    // Pedometer
    func stepStream() -> AsyncStream<CMPedometerData> {
        AsyncStream { continuation in
            let pedometer = CMPedometer()
            guard CMPedometer.isStepCountingAvailable() else {
                continuation.finish(); return
            }
            pedometer.startUpdates(from: Date()) { data, error in
                if let data { continuation.yield(data) }
            }
            continuation.onTermination = { _ in pedometer.stopUpdates() }
        }
    }
}
```

---

## Haptics

```swift
// Core/Hardware/HapticsService.swift
// Always check support before triggering
final class HapticsService {
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()

    // Prepare before user action for lower latency
    func prepare() {
        feedbackGenerator.prepare()
    }

    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notificationGenerator.notificationOccurred(type)
    }

    func selection() {
        selectionGenerator.selectionChanged()
    }
}

// Core Haptics — custom patterns
import CoreHaptics

actor CoreHapticsEngine {
    private var engine: CHHapticEngine?

    func start() async throws {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try CHHapticEngine()
        try await engine?.start()
        engine?.stoppedHandler = { _ in Task { try? await self.start() } }
    }

    func play(pattern: CHHapticPattern) throws {
        let player = try engine?.makePlayer(with: pattern)
        try player?.start(atTime: CHHapticTimeImmediate)
    }

    func heartbeatPattern() throws -> CHHapticPattern {
        let events = [
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            ], relativeTime: 0),
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
            ], relativeTime: 0.15)
        ]
        return try CHHapticPattern(events: events, parameters: [])
    }
}
```

---

## Location & GPS

```swift
// Core Location with async/await (iOS 17+)
import CoreLocation

actor LocationService {
    private let manager = CLLocationManager()

    func requestAuthorization() async -> CLAuthorizationStatus {
        await withCheckedContinuation { continuation in
            // Use CLLocationManagerDelegate pattern, resume once
        }
    }

    // iOS 17+ CLLocationUpdate stream
    func locationStream() -> AsyncStream<CLLocation> {
        AsyncStream { continuation in
            let updates = CLLocationUpdate.liveUpdates(.fitness)
            Task {
                for try await update in updates {
                    if let loc = update.location {
                        continuation.yield(loc)
                    }
                }
            }
        }
    }

    // One-shot location
    func currentLocation() async throws -> CLLocation {
        for try await update in CLLocationUpdate.liveUpdates() {
            if let location = update.location {
                return location
            }
        }
        throw LocationError.unavailable
    }
}
```

---

## NFC

```swift
import CoreNFC

actor NFCReader: NSObject {
    private var session: NFCNDEFReaderSession?

    func read() -> AsyncStream<NFCNDEFMessage> {
        AsyncStream { continuation in
            session = NFCNDEFReaderSession(delegate: NFCDelegate(continuation: continuation),
                                           queue: nil,
                                           invalidateAfterFirstRead: false)
            session?.alertMessage = "Hold your iPhone near an NFC tag."
            session?.begin()
        }
    }
}
```

---

## Ultra-Wideband (UWB) / Nearby Interaction

```swift
import NearbyInteraction

actor UWBSession: NSObject, NISessionDelegate {
    private var niSession: NISession?
    private var continuation: AsyncStream<NINearbyObject>.Continuation?

    func startSession(with token: NIDiscoveryToken) -> AsyncStream<NINearbyObject> {
        AsyncStream { cont in
            self.continuation = cont
            niSession = NISession()
            niSession?.delegate = self
            let config = NINearbyPeerConfiguration(peerToken: token)
            niSession?.run(config)
        }
    }

    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        Task { await handleUpdate(nearbyObjects) }
    }

    private func handleUpdate(_ objects: [NINearbyObject]) {
        objects.forEach { continuation?.yield($0) }
    }
}
```

---

*See also: `CLAUDE_AI_ML.md` for Neural Engine / Vision framework, `CLAUDE_CONCURRENCY.md` for AsyncStream patterns.*
