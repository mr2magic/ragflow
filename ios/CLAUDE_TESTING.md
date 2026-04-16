# CLAUDE_TESTING.md — Testing Strategy

## Framework Choice

| Scope | Framework |
|---|---|
| Unit & integration tests | **Swift Testing** (new, preferred for Swift 6) |
| Legacy / XCTest parity | XCTest (keep for UI tests and existing suites) |
| UI / end-to-end | XCUITest |
| Performance benchmarks | XCTest `measure {}` + Instruments |
| Snapshot tests | `swift-snapshot-testing` (if approved in Package.swift) |

---

## Swift Testing Framework

```swift
import Testing
@testable import MyApp

// Basic test suite
@Suite("ItemRepository Tests")
struct ItemRepositoryTests {

    var repository: SwiftDataItemRepository!
    var container: ModelContainer!

    init() throws {
        container = try ModelContainer(
            for: Item.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        repository = SwiftDataItemRepository(container: container)
    }

    @Test("fetchAll returns empty array when no items exist")
    func fetchAllEmpty() async throws {
        let items = try await repository.fetchAll()
        #expect(items.isEmpty)
    }

    @Test("save persists item and fetchAll returns it")
    func saveAndFetch() async throws {
        let item = Item(title: "Test", body: "Body")
        try await repository.save(item)
        let fetched = try await repository.fetchAll()
        #expect(fetched.count == 1)
        #expect(fetched[0].title == "Test")
    }

    @Test("delete removes item by ID")
    func deleteItem() async throws {
        let item = Item(title: "To Delete", body: "")
        try await repository.save(item)
        try await repository.delete(id: item.id)
        let remaining = try await repository.fetchAll()
        #expect(remaining.isEmpty)
    }

    @Test("concurrent saves don't corrupt data", .timeLimit(.seconds(5)))
    func concurrentSaves() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    try await self.repository.save(Item(title: "Item \(i)", body: ""))
                }
            }
            try await group.waitForAll()
        }
        let items = try await repository.fetchAll()
        #expect(items.count == 20)
    }
}
```

### Parameterized Tests

```swift
@Suite("Sentiment Analysis Tests")
struct SentimentTests {
    let service = NLService()

    @Test("Sentiment is positive for positive text",
          arguments: ["I love this!", "Amazing experience", "Best app ever"])
    func positiveSentiment(text: String) {
        let score = service.sentiment(of: text) ?? 0
        #expect(score > 0, "Expected positive score for: '\(text)'")
    }

    @Test("Sentiment is negative for negative text",
          arguments: ["Terrible app", "This is broken", "Awful experience"])
    func negativeSentiment(text: String) {
        let score = service.sentiment(of: text) ?? 0
        #expect(score < 0, "Expected negative score for: '\(text)'")
    }
}
```

### Async & Throws

```swift
@Test("API client handles 401 with authError")
func apiUnauthorized() async throws {
    let client = APIClient(baseURL: URL(string: "https://mock.api")!, session: .mock401)
    await #expect(throws: APIError.httpError(statusCode: 401)) {
        let _: Item = try await client.get("/items/1")
    }
}
```

### Mocking with Protocols

```swift
// All repositories and services are defined as protocols → easy to mock
final class MockItemRepository: ItemRepository {
    var items: [Item] = []
    var shouldThrow = false

    func fetchAll() async throws -> [Item] {
        if shouldThrow { throw MockError.intentional }
        return items
    }

    func save(_ item: Item) async throws {
        if shouldThrow { throw MockError.intentional }
        items.append(item)
    }

    func delete(id: UUID) async throws {
        items.removeAll { $0.id == id }
    }
}

enum MockError: Error { case intentional }
```

---

## XCTest for UI Tests

```swift
import XCTest

final class OnboardingUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--skip-animations"]
        app.launchEnvironment = ["MOCK_NETWORK": "1"]
        app.launch()
    }

    func testOnboardingFlow() throws {
        // Welcome screen
        XCTAssert(app.staticTexts["Welcome to MyApp"].exists)
        app.buttons["Get Started"].tap()

        // Permissions screen
        let permissionsHeading = app.staticTexts["Allow Access"]
        XCTAssert(permissionsHeading.waitForExistence(timeout: 3))
        app.buttons["Continue"].tap()

        // Handle system alert
        addUIInterruptionMonitor(withDescription: "Camera Permission") { alert in
            alert.buttons["Allow"].tap()
            return true
        }
        app.tap()   // trigger interruption handler

        // Main screen
        XCTAssert(app.navigationBars["Home"].waitForExistence(timeout: 5))
    }

    func testItemCreation() throws {
        // Navigate to create
        app.buttons["Add Item"].tap()

        // Fill form
        let titleField = app.textFields["Title"]
        titleField.tap()
        titleField.typeText("New Test Item")

        app.buttons["Save"].tap()

        // Verify in list
        XCTAssert(app.staticTexts["New Test Item"].waitForExistence(timeout: 3))
    }

    func testAccessibilityLabels() throws {
        // Ensure interactive elements have accessibility labels
        let buttons = app.buttons.allElementsBoundByIndex
        for button in buttons {
            XCTAssertFalse(button.label.isEmpty,
                           "Button with identifier '\(button.identifier)' has no accessibility label")
        }
    }
}
```

---

## Test Helpers & Fixtures

```swift
// Tests/Helpers/ItemFixtures.swift
extension Item {
    static func fixture(
        title: String = "Test Item",
        body: String = "Test body",
        isFavorite: Bool = false
    ) -> Item {
        let item = Item(title: title, body: body)
        item.isFavorite = isFavorite
        return item
    }

    static var sampleSet: [Item] {
        [
            fixture(title: "First", isFavorite: true),
            fixture(title: "Second"),
            fixture(title: "Third", isFavorite: true)
        ]
    }
}

// Tests/Helpers/URLSession+Mock.swift
extension URLSession {
    static func mock(data: Data, statusCode: Int = 200) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.responseData = data
        MockURLProtocol.statusCode = statusCode
        return URLSession(configuration: config)
    }

    static var mock401: URLSession { mock(data: Data(), statusCode: 401) }
}
```

---

## Coverage Requirements

| Layer | Minimum Coverage |
|---|---|
| Domain models | 95% |
| Repositories | 90% |
| ViewModels | 85% |
| Services (ML, Camera, etc.) | 70% |
| SwiftUI Views | best-effort (focus on logic in VMs) |

**Enforce in CI:**
```yaml
# .github/workflows/test.yml (excerpt)
- name: Run tests with coverage
  run: |
    xcodebuild test \
      -scheme MyApp \
      -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
      -enableCodeCoverage YES \
      -resultBundlePath TestResults.xcresult
- name: Check coverage threshold
  run: xcresultparser --coverage-threshold 80 TestResults.xcresult
```

---

## Swift Testing Tags for CI Filtering

```swift
extension Tag {
    @Tag static var network: Self
    @Tag static var database: Self
    @Tag static var hardware: Self
    @Tag static var slow: Self
}

// Tag tests appropriately
@Test("Syncs to CloudKit", .tags(.network, .slow))
func cloudKitSync() async throws { ... }

// Run only fast tests in PR checks:
// swift test --filter '!slow'
```

---

*See also: `CLAUDE_PERFORMANCE.md` for Instruments-based performance tests.*
