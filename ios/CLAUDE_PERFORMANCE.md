# CLAUDE_PERFORMANCE.md — Performance & Optimization

## Performance Budget

| Metric | Target |
|---|---|
| App launch (cold, release) | < 400 ms to first interactive frame |
| Main thread frame time | < 16 ms (60 fps), < 8 ms (120 fps ProMotion) |
| Memory at idle | < 50 MB |
| Memory peak (camera/AR) | < 300 MB |
| Battery drain per hour (background) | < 1% |
| Core ML inference (on ANE) | < 50 ms per frame |

---

## Instruments Workflow

### Profiling Priority

1. **Time Profiler** — identify CPU hotspots before optimizing anything
2. **Allocations** — find retain cycles, excessive heap growth
3. **Leaks** — detect leaked objects
4. **Core Animation** — GPU commit time, offscreen rendering
5. **Energy Log** — CPU wakes, network radio, location usage
6. **Metal System Trace** — GPU shader performance for AR/Vision

### Key Xcode Gauges to Watch

- CPU Usage gauge: spikes during scroll → offload to actor
- Memory gauge: steady growth → suspect retain cycle
- FPS gauge: drops below 60 → check `drawingGroup()`, offscreen rendering

---

## Main Thread Rules

```swift
// RULE: Main thread is ONLY for UI updates and user input handling.
// Any work > ~1ms goes on a background task.

// ❌ WRONG: JSON decoding on main thread
@MainActor
func loadData() async {
    let items = try! JSONDecoder().decode([Item].self, from: networkData)   // blocks UI
    self.items = items
}

// ✅ CORRECT: decode off-main, publish on main
func loadData() async {
    let items = try await Task.detached(priority: .userInitiated) {
        try JSONDecoder().decode([Item].self, from: networkData)
    }.value
    await MainActor.run { self.items = items }   // only the assignment is on main
}
```

---

## SwiftUI Rendering Performance

```swift
// 1. Use .drawingGroup() to rasterize complex static views to Metal
complexStaticBackground
    .drawingGroup()   // renders to offscreen texture once; re-used every frame

// 2. Avoid identity-breaking modifiers inside List/ScrollView
// ❌ Each item gets a new view identity each scroll:
List(items) { item in
    ItemRow(item: item)
        .id(item.id)   // redundant — List already uses Identifiable
}

// 3. Equatable conformance prevents redundant diff
struct ItemRow: View, Equatable {
    let item: Item
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.item.id == rhs.item.id && lhs.item.updatedAt == rhs.item.updatedAt }

    var body: some View {
        // ...
    }
}

// 4. LazyVStack / LazyHStack for large collections
ScrollView {
    LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) {
        ForEach(groupedItems, id: \.key) { section in
            Section { ForEach(section.value) { ItemRow(item: $0) } }
        }
    }
}

// 5. Image loading — always async + cache
AsyncImage(url: item.thumbnailURL) { phase in
    switch phase {
    case .success(let img): img.resizable().scaledToFill()
    case .failure:          Image(systemName: "photo").foregroundStyle(.secondary)
    case .empty:            ProgressView()
    @unknown default:       EmptyView()
    }
}
.frame(width: 80, height: 80)
.clipped()
```

---

## Memory Management

```swift
// Detect retain cycles: use [weak self] in closures that escape
Task { [weak self] in
    guard let self else { return }
    await self.loadData()
}

// In actors, weak references are rarely needed (actors don't create cycles with Tasks)
// But watch for delegate patterns:
class Delegate: NSObject, SomeFrameworkDelegate {
    weak var viewModel: FeatureViewModel?   // ✅ weak to break cycle
}

// Large data — use value types (structs) for immutable data
// Reference types only when you need identity or mutation-sharing

// Purge caches on memory warning
NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
    .sink { _ in ImageCache.shared.evictAll() }
    .store(in: &cancellables)   // exception: Combine for system notifications is fine

// CVPixelBuffer pooling for camera frames (avoids repeated alloc/dealloc)
var pixelBufferPool: CVPixelBufferPool?
CVPixelBufferPoolCreate(nil, poolAttributes, pixelBufferAttributes, &pixelBufferPool)
```

---

## Core ML Performance

```swift
// Use .all compute units — lets OS route to ANE, GPU, or CPU as appropriate
let config = MLModelConfiguration()
config.computeUnits = .all

// Batch predictions — far more efficient than one-by-one
let batchProvider = MLArrayBatchProvider(array: inputFeatures)
let batchResults = try await model.predictions(fromBatch: batchProvider)

// Reuse model instances — loading is expensive
// ✅ Load once in actor init, reuse for all predictions:
actor MLService {
    private let model: SomeMLModel   // loaded once in init()
}

// Profile with Instruments → Core ML template
// Look for: inference time, memory footprint, compute unit utilization
```

---

## Metal / GPU (for custom rendering)

```swift
import Metal
import MetalKit

// Use MTKView for custom Metal rendering
class MetalRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState!

    init(metalView: MTKView) {
        device = MTLCreateSystemDefaultDevice()!
        commandQueue = device.makeCommandQueue()!
        super.init()
        metalView.device = device
        metalView.delegate = self
        metalView.preferredFramesPerSecond = 120   // ProMotion
        buildPipeline(metalView: metalView)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let buffer = commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        encoder.setRenderPipelineState(pipelineState)
        // ... draw calls ...
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

// Compute shaders for image processing (faster than Core Image for custom ops)
func applyComputeShader(to texture: MTLTexture) {
    guard let buffer = commandQueue.makeCommandBuffer(),
          let encoder = buffer.makeComputeCommandEncoder() else { return }
    encoder.setComputePipelineState(computePipeline)
    encoder.setTexture(texture, index: 0)
    let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
    let threadgroupCount = MTLSize(
        width: (texture.width + 15) / 16,
        height: (texture.height + 15) / 16,
        depth: 1
    )
    encoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
    encoder.endEncoding()
    buffer.commit()
}
```

---

## Battery Optimization

```swift
// 1. Use significant-change location instead of continuous GPS when possible
locationManager.startMonitoringSignificantLocationChanges()   // ~1% battery vs ~5%

// 2. Coalesce network requests — batch API calls
// 3. Use background URLSession for large transfers
let backgroundConfig = URLSessionConfiguration.background(withIdentifier: "com.app.transfer")
backgroundConfig.isDiscretionary = true   // OS schedules at optimal time

// 4. Avoid polling — use push notifications, CloudKit subscriptions, or Core Data change tokens
// 5. Defer non-urgent work using BGTaskScheduler
import BackgroundTasks

BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.app.refresh", using: nil) { task in
    Task {
        await performBackgroundRefresh()
        task.setTaskCompleted(success: true)
    }
}

func scheduleBackgroundRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: "com.app.refresh")
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)   // 15 min minimum
    try? BGTaskScheduler.shared.submit(request)
}

// 6. Thermal state awareness — reduce quality under thermal pressure
ProcessInfo.processInfo.thermalState   // .nominal, .fair, .serious, .critical
NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
    .sink { _ in
        let state = ProcessInfo.processInfo.thermalState
        if state == .serious || state == .critical {
            reduceMLFrameRate()
            stopNonEssentialSensors()
        }
    }
```

---

## Launch Time Optimization

```swift
// 1. Defer ALL non-essential init work out of @main init and App.init
// 2. Lazy-load heavy subsystems (ML models, DB containers) after first render
// 3. Use dyld_stub_binder reduction — limit ObjC runtime load
// 4. Merge small dynamic frameworks into static libs

// Measure launch with: xctrace record --template 'App Launch' --target-stdin
// Target: Time to first frame rendered < 400ms

@main
struct MyApp: App {
    // ✅ ModelContainer init is fast (schema compile happens once, cached)
    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    // Defer heavy init here, not in App.init
                    await MLService.shared.loadModels()
                }
        }
        .modelContainer(for: [Item.self, Tag.self])   // preferred: let SwiftUI manage it
    }
}
```

---

*See also: `CLAUDE_HARDWARE.md` for sensor frame-rate management, `CLAUDE_AI_ML.md` for ANE optimization.*
