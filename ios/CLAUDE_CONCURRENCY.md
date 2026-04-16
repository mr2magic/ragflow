# CLAUDE_CONCURRENCY.md — Swift 6 Concurrency

## Strict Concurrency Mode

All targets must compile with:

```
// Package.swift or Xcode build settings
swiftSettings: [
    .enableExperimentalFeature("StrictConcurrency"),   // transitional
    // OR in Swift 6 mode (default for new targets):
    // strict concurrency is on by default
]
```

**Rule**: zero `@unchecked Sendable` without a `// SAFETY:` comment explaining thread safety guarantees.

---

## Actor Hierarchy

```
@MainActor          ← All UI state, ViewModels
    ↓ await
Actor (domain)      ← Repositories, services with shared mutable state  
    ↓ await
async func          ← Stateless async work (network calls, ML inference, file I/O)
```

### When to use each

| Mechanism | Use for |
|---|---|
| `@MainActor` | ViewModels, UI event handlers, all `@Observable` state |
| `actor` | Shared mutable state accessed from multiple tasks (cache, DB context, hardware session) |
| `async func` | Stateless I/O or computation; no isolation needed |
| `nonisolated` | Pure functions on actors that don't touch actor state |
| `Task.detached` | Work that must NOT inherit actor context (rare) |

---

## Actor Examples

```swift
// Shared cache — classic actor use case
actor ImageCache {
    private var cache: [URL: UIImage] = [:]

    func image(for url: URL) -> UIImage? {
        cache[url]
    }

    func store(_ image: UIImage, for url: URL) {
        cache[url] = image
    }

    func evict(for url: URL) {
        cache.removeValue(forKey: url)
    }
}

// Global actor for a hardware resource
@globalActor
actor CameraActor {
    static let shared = CameraActor()
}

@CameraActor
final class CameraSession {
    private let session = AVCaptureSession()
    // All methods on this type are isolated to CameraActor
    func startRunning() { session.startRunning() }
    func stopRunning()  { session.stopRunning() }
}
```

---

## Structured Concurrency Patterns

### Parallel fetch with TaskGroup

```swift
func fetchDashboardData() async throws -> DashboardData {
    try await withThrowingTaskGroup(of: DashboardData.Partial.self) { group in
        group.addTask { try await self.fetchWeatherData() }
        group.addTask { try await self.fetchHealthData() }
        group.addTask { try await self.fetchActivityData() }

        var result = DashboardData()
        for try await partial in group {
            result.merge(partial)
        }
        return result
    }
}
```

### AsyncStream for sensor data

```swift
// Wrap delegate/callback APIs in AsyncStream
func lidarDepthStream() -> AsyncStream<ARFrame> {
    AsyncStream { continuation in
        let delegate = ARSessionDelegate { frame in
            continuation.yield(frame)
        }
        arSession.delegate = delegate
        arSession.run(ARWorldTrackingConfiguration())
        continuation.onTermination = { _ in
            self.arSession.pause()
        }
    }
}

// Consume
for await frame in lidarDepthStream() {
    await processDepthMap(frame.capturedDepthData)
}
```

### AsyncSequence transformations

```swift
// Filter + map on AsyncSequence (no Combine needed)
let highConfidenceDetections = mlDetectionStream
    .filter { $0.confidence > 0.8 }
    .map { Detection(from: $0) }

for await detection in highConfidenceDetections {
    await handleDetection(detection)
}
```

---

## Task Lifecycle Management

```swift
// In @Observable ViewModel — store tasks to cancel on deinit
@Observable
@MainActor
final class LiveSensorViewModel {
    var readings: [SensorReading] = []
    private var sensorTask: Task<Void, Never>?

    func startMonitoring() {
        sensorTask = Task {
            for await reading in SensorService.shared.stream() {
                guard !Task.isCancelled else { break }
                readings.append(reading)
            }
        }
    }

    func stopMonitoring() {
        sensorTask?.cancel()
        sensorTask = nil
    }

    deinit {
        sensorTask?.cancel()
    }
}

// In View — use .task modifier (automatically cancelled on view disappear)
.task {
    await viewModel.startMonitoring()
}
.task(id: filterCriteria) {
    // Restarts whenever filterCriteria changes
    await viewModel.applyFilter(filterCriteria)
}
```

---

## Sendable Conformance

```swift
// Value types — automatic Sendable if all stored properties are Sendable
struct SensorReading: Sendable {
    let timestamp: Date       // Sendable ✅
    let value: Double         // Sendable ✅
    let sensorType: SensorType // must also be Sendable
}

// Enums with associated values — conditional Sendable
enum SensorEvent: Sendable {
    case reading(SensorReading)
    case error(any Error & Sendable)   // 'any Error' is NOT Sendable; box it
}

// Class — explicit Sendable only if truly thread-safe
final class ImmutableConfig: Sendable {
    let endpoint: URL
    let timeout: TimeInterval
    init(endpoint: URL, timeout: TimeInterval) {
        self.endpoint = endpoint
        self.timeout = timeout
    }
}

// Unsafe escape hatch — MUST have SAFETY comment
final class LegacyWrapper: @unchecked Sendable {
    // SAFETY: `data` is only mutated during init before this object
    // crosses concurrency boundaries. After init it is read-only.
    var data: NSData
    init(_ data: NSData) { self.data = data }
}
```

---

## Continuation Bridging (for legacy/callback APIs)

```swift
// One-shot callback → async
func requestLocationOnce() async throws -> CLLocation {
    try await withCheckedThrowingContinuation { continuation in
        locationManager.requestLocation { result in
            switch result {
            case .success(let loc): continuation.resume(returning: loc)
            case .failure(let err): continuation.resume(throwing: err)
            }
        }
    }
}

// RULE: Each continuation must be resumed exactly once.
// Use withCheckedContinuation (debug asserts on double-resume).
// Switch to withUnsafeContinuation only in hot paths after verification.
```

---

## Common Anti-Patterns to Avoid

```swift
// ❌ DON'T: DispatchQueue in new code
DispatchQueue.global(qos: .userInitiated).async { ... }

// ✅ DO:
Task(priority: .userInitiated) { ... }

// ❌ DON'T: Combine PassthroughSubject
let subject = PassthroughSubject<Int, Never>()

// ✅ DO: AsyncStream
let (stream, continuation) = AsyncStream.makeStream(of: Int.self)

// ❌ DON'T: @escaping closures that capture mutable state across actors
func doThing(completion: @escaping (Result<Foo, Error>) -> Void)

// ✅ DO: async throws
func doThing() async throws -> Foo

// ❌ DON'T: Thread.sleep
Thread.sleep(forTimeInterval: 1)

// ✅ DO:
try await Task.sleep(for: .seconds(1))
```

---

*See also: `CLAUDE_HARDWARE.md` for sensor stream patterns, `CLAUDE_AI_ML.md` for async ML inference.*
