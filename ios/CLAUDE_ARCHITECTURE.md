# CLAUDE_ARCHITECTURE.md — App Architecture

## Pattern: Observable MVVM + Repository

iOS 26 projects use **Observable MVVM** (not VIPER, not TCA, not Combine-based MVVM).

```
View  →  ViewModel (@Observable)  →  Repository (actor)  →  Data Source
          ↑ owns state                ↑ owns I/O               (SwiftData / Network / Hardware)
```

### ViewModel rules
- Annotate with `@Observable` (not `ObservableObject`)
- `@MainActor` unless proven computation-heavy
- No `import UIKit` in ViewModels
- Dependencies injected via `init`; never use singletons in feature code

```swift
@Observable
@MainActor
final class CameraViewModel {
    var capturedImage: UIImage?
    var isCapturing = false
    var error: CameraError?

    private let cameraService: CameraService

    init(cameraService: CameraService = CameraService()) {
        self.cameraService = cameraService
    }

    func capture() async {
        isCapturing = true
        defer { isCapturing = false }
        do {
            capturedImage = try await cameraService.capturePhoto()
        } catch {
            self.error = error as? CameraError ?? .unknown
        }
    }
}
```

### Repository rules
- Defined as a `protocol` + concrete `actor` implementation
- Returns domain models, never raw DB/network types
- All methods `async throws`

```swift
protocol ItemRepository: Sendable {
    func fetchAll() async throws -> [Item]
    func save(_ item: Item) async throws
    func delete(id: UUID) async throws
}

actor SwiftDataItemRepository: ItemRepository {
    private let modelContext: ModelContext

    init(container: ModelContainer) {
        self.modelContext = ModelContext(container)
    }

    func fetchAll() async throws -> [Item] {
        let descriptor = FetchDescriptor<ItemModel>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map(Item.init)
    }

    func save(_ item: Item) async throws {
        let model = ItemModel(item)
        modelContext.insert(model)
        try modelContext.save()
    }

    func delete(id: UUID) async throws {
        let predicate = #Predicate<ItemModel> { $0.id == id }
        try modelContext.delete(model: ItemModel.self, where: predicate)
        try modelContext.save()
    }
}
```

---

## Dependency Injection

Use a lightweight `AppEnvironment` struct passed through the SwiftUI environment — no third-party DI containers.

```swift
// Core/DI/AppEnvironment.swift
struct AppEnvironment {
    let itemRepository: any ItemRepository
    let cameraService: CameraService
    let mlService: MLService

    static let live: AppEnvironment = {
        let container = try! ModelContainer(for: ItemModel.self)
        return AppEnvironment(
            itemRepository: SwiftDataItemRepository(container: container),
            cameraService: CameraService(),
            mlService: MLService()
        )
    }()

    static let preview = AppEnvironment(
        itemRepository: MockItemRepository(),
        cameraService: MockCameraService(),
        mlService: MockMLService()
    )
}

// Register in App entry point
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AppEnvironment.live)
        }
    }
}

// Consume in views
struct ItemListView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel: ItemListViewModel

    init(env: AppEnvironment) {
        _viewModel = State(initialValue: ItemListViewModel(repository: env.itemRepository))
    }
}
```

---

## Navigation: NavigationStack + NavigationPath

```swift
// Typed navigation — no string-based routes
enum AppRoute: Hashable {
    case itemDetail(Item.ID)
    case camera
    case settings
    case arView(anchorID: UUID)
}

@Observable
@MainActor
final class NavigationStore {
    var path = NavigationPath()

    func push(_ route: AppRoute) { path.append(route) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path = NavigationPath() }
}

struct RootView: View {
    @State private var nav = NavigationStore()

    var body: some View {
        NavigationStack(path: $nav.path) {
            HomeView()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .itemDetail(let id): ItemDetailView(id: id)
                    case .camera:             CameraView()
                    case .settings:           SettingsView()
                    case .arView(let id):     ARSceneView(anchorID: id)
                    }
                }
        }
        .environment(nav)
    }
}
```

---

## Error Handling Architecture

```swift
// Shared/Errors/AppError.swift
enum AppError: LocalizedError {
    case network(URLError)
    case data(any Error)
    case hardware(HardwareError)
    case mlInference(MLError)
    case permissionDenied(PermissionType)

    var errorDescription: String? {
        switch self {
        case .network(let e):          return "Network error: \(e.localizedDescription)"
        case .data(let e):             return "Data error: \(e.localizedDescription)"
        case .hardware(let e):         return e.localizedDescription
        case .mlInference(let e):      return e.localizedDescription
        case .permissionDenied(let p): return "\(p.displayName) permission is required."
        }
    }
}

// In ViewModels — surface errors as state, never crash
var appError: AppError?
var showError: Bool { appError != nil }

// In Views — display with .alert modifier
.alert("Something went wrong", isPresented: $viewModel.showError) {
    Button("OK") { viewModel.appError = nil }
} message: {
    Text(viewModel.appError?.localizedDescription ?? "")
}
```

---

## Module Boundaries

```
┌─────────────────────────────────┐
│  Features  (no cross-imports)   │  ← knows Core, knows Shared
├─────────────────────────────────┤
│  Core                           │  ← knows Shared only
├─────────────────────────────────┤
│  Shared                         │  ← no app dependencies
└─────────────────────────────────┘
```

- Features must NOT import other Feature modules directly
- Cross-feature navigation goes through `NavigationStore`
- Cross-feature data sharing goes through a shared Repository in Core

---

## App Intents Integration

```swift
// Every major user action should be an AppIntent
struct CapturePhotoIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture Photo"
    static var description = IntentDescription("Takes a photo using the device camera.")

    @MainActor
    func perform() async throws -> some IntentResult {
        // Routed via deep link into CameraView scene
        return .result()
    }
}
```

---

*See also: `CLAUDE_DATA.md` for SwiftData details, `CLAUDE_CONCURRENCY.md` for actor patterns.*
