# CLAUDE_DATA.md — Data & Persistence

## SwiftData (Primary Persistence Layer)

### Schema Definition

```swift
import SwiftData

// Always annotate models with @Model
// Use @Attribute for column-level control
// Use @Relationship for associations

@Model
final class Item {
    @Attribute(.unique) var id: UUID
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date
    @Attribute(.externalStorage) var thumbnail: Data?   // large blobs → external file
    var isFavorite: Bool

    @Relationship(deleteRule: .cascade) var tags: [Tag] = []
    @Relationship(inverse: \Tag.items) var category: Category?

    init(title: String, body: String) {
        self.id = UUID()
        self.title = title
        self.body = body
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isFavorite = false
    }
}

@Model
final class Tag {
    @Attribute(.unique) var name: String
    var color: String   // hex string — SwiftData doesn't store Color directly
    var items: [Item] = []   // inverse relationship populated automatically

    init(name: String, color: String) {
        self.name = name
        self.color = color
    }
}

@Model
final class Category {
    @Attribute(.unique) var id: UUID
    var displayName: String
    @Relationship(deleteRule: .nullify) var items: [Item] = []
}
```

### ModelContainer Setup

```swift
// App/MyApp.swift
@main
struct MyApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([Item.self, Tag.self, Category.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .identifier("group.com.yourapp")   // for App Groups / widgets
        )
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("SwiftData container failed to initialize: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
```

### Querying with #Predicate

```swift
// Simple predicate
let predicate = #Predicate<Item> { item in
    item.isFavorite && item.title.contains(searchText)
}

// Date range
let weekAgo = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date())!
let recentPredicate = #Predicate<Item> { $0.createdAt >= weekAgo }

// Relationship filter
let tagPredicate = #Predicate<Item> { item in
    item.tags.contains(where: { $0.name == targetTagName })
}

// FetchDescriptor with sort + limit
let descriptor = FetchDescriptor<Item>(
    predicate: predicate,
    sortBy: [
        SortDescriptor(\.updatedAt, order: .reverse),
        SortDescriptor(\.title)
    ]
)
descriptor.fetchLimit = 50
descriptor.includePendingChanges = true

// In actor repository
let results = try modelContext.fetch(descriptor)
```

### @Query in Views (declarative)

```swift
struct ItemListView: View {
    @Query(sort: \.createdAt, order: .reverse) private var items: [Item]
    // Dynamic filter:
    @Query private var favorites: [Item]

    init(showFavoritesOnly: Bool) {
        let predicate = showFavoritesOnly
            ? #Predicate<Item> { $0.isFavorite }
            : #Predicate<Item> { _ in true }
        _favorites = Query(filter: predicate, sort: \.updatedAt, order: .reverse)
    }

    var body: some View {
        List(items) { ItemRow(item: $0) }
    }
}
```

### Migrations

```swift
// Versioned schema for migrations
enum ItemSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] = [Item.self, Tag.self]
}

enum ItemSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] = [Item.self, Tag.self, Category.self]

    // Rename if needed
    @Model final class Item { /* updated schema */ }
}

enum ItemMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] = [ItemSchemaV1.self, ItemSchemaV2.self]

    static var stages: [MigrationStage] = [
        .lightweight(fromVersion: ItemSchemaV1.self, toVersion: ItemSchemaV2.self)
        // .custom(...) for data transforms
    ]
}
```

---

## CloudKit Sync

```swift
// Enable CloudKit sync — just change ModelConfiguration
let config = ModelConfiguration(
    schema: schema,
    cloudKitDatabase: .private("iCloud.com.yourapp.items")   // matches entitlement
)
// SwiftData handles sync automatically with CloudKit public/private databases
```

### Manual CloudKit (for advanced queries)

```swift
import CloudKit

actor CloudKitService {
    private let container = CKContainer(identifier: "iCloud.com.yourapp")
    private var database: CKDatabase { container.privateCloudDatabase }

    func save(record: CKRecord) async throws {
        try await database.save(record)
    }

    func fetch(recordType: String, predicate: NSPredicate = NSPredicate(value: true)) async throws -> [CKRecord] {
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor? = nil

        repeat {
            let (batch, newCursor) = try await database.records(matching: query,
                                                                 continuationCursor: cursor,
                                                                 desiredKeys: nil,
                                                                 resultsLimit: 100)
            records += batch.matchResults.compactMap { try? $0.1.get() }
            cursor = newCursor
        } while cursor != nil

        return records
    }
}
```

---

## UserDefaults & AppStorage

```swift
// Type-safe keys — never raw strings
extension AppStorageKey {
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let selectedTheme = "selectedTheme"
    static let lastSyncDate = "lastSyncDate"
}

// In SwiftUI views
@AppStorage(AppStorageKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
@AppStorage(AppStorageKey.selectedTheme) private var theme = AppTheme.system

// App Group UserDefaults for widget/extension sharing
extension UserDefaults {
    static let shared = UserDefaults(suiteName: "group.com.yourapp")!
}
```

---

## File Storage Patterns

```swift
// Core/Data/FileStorage.swift
actor FileStorage {
    private let baseURL: URL

    init(directory: FileManager.SearchPathDirectory = .documentDirectory) {
        baseURL = FileManager.default.urls(for: directory, in: .userDomainMask)[0]
    }

    func save(_ data: Data, to path: String) throws {
        let url = baseURL.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    func load(from path: String) throws -> Data {
        try Data(contentsOf: baseURL.appendingPathComponent(path))
    }

    func delete(at path: String) throws {
        try FileManager.default.removeItem(at: baseURL.appendingPathComponent(path))
    }
}

// File protection levels
// .completeFileProtection       → encrypted when device locked (use for sensitive data)
// .completeFileProtectionUntilFirstUserAuthentication → accessible after first unlock (use for background tasks)
// .none                         → always accessible (use only for truly non-sensitive caches)
```

---

## Network Layer

```swift
// Core/Network/APIClient.swift
actor APIClient {
    private let session: URLSession
    private let baseURL: URL
    private let decoder = JSONDecoder.isoDate

    init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        let request = URLRequest(url: baseURL.appendingPathComponent(path))
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decoder.decode(T.self, from: data)
    }

    func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decoder.decode(Response.self, from: data)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: http.statusCode)
        }
    }
}

extension JSONDecoder {
    static let isoDate: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}
```

---

*See also: `CLAUDE_SECURITY.md` for Keychain & encryption, `CLAUDE_CONCURRENCY.md` for actor patterns.*
