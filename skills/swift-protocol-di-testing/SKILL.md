---
name: swift-protocol-di-testing
description: Protocol-based dependency injection for testable Swift — hide file system, network, and APIs behind small protocols, simulate failures with Swift Testing. Use when Swift I/O code needs tests. Triggers on "mock file system", "Swift Testing", "protocol injection", "testable Swift".
---

<!--
Adapted from affaan-m/ECC skills/swift-protocol-di-testing @ c70874f (MIT, Copyright (c) 2026 Affaan Mustafa); reviewed and rewritten 2026-10-01 for this framework.
-->

# Swift Protocol-Based Dependency Injection for Testing

Put each external concern (file system, network, iCloud, keychain) behind a small protocol. Production code gets the real implementation by default; tests inject a mock that can return data or fail on demand. Result: deterministic tests with no real I/O, including the error paths that are hard to trigger for real.

Swift Testing is the test framework default in R.Code iOS projects (`rcode-ios`). Write the failing test first, as that workflow requires.

## When to Use

- Swift code reads files, calls the network, or uses another external API
- Error handling needs a test, and the real failure is hard to produce
- A module must run in the app, in tests, and in SwiftUI previews
- The code uses actors or structured concurrency and must stay `Sendable`

## Core pattern

### 1. Small, focused protocols

One protocol per external concern.

```swift
// File system location
public protocol FileSystemProviding: Sendable {
    func containerURL(for purpose: Purpose) -> URL?
}

// Read and write
public protocol FileAccessorProviding: Sendable {
    func read(from url: URL) throws -> Data
    func write(_ data: Data, to url: URL) throws
    func fileExists(at url: URL) -> Bool
}

// Bookmark storage (sandboxed apps)
public protocol BookmarkStorageProviding: Sendable {
    func saveBookmark(_ data: Data, for key: String) throws
    func loadBookmark(for key: String) throws -> Data?
}
```

### 2. Production implementations

```swift
public struct DefaultFileSystemProvider: FileSystemProviding {
    public init() {}
    public func containerURL(for purpose: Purpose) -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)
    }
}

public struct DefaultFileAccessor: FileAccessorProviding {
    public init() {}
    public func read(from url: URL) throws -> Data { try Data(contentsOf: url) }
    public func write(_ data: Data, to url: URL) throws { try data.write(to: url, options: .atomic) }
    public func fileExists(at url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
}
```

### 3. Mocks with configurable failures

```swift
public final class MockFileAccessor: FileAccessorProviding, @unchecked Sendable {
    public var files: [URL: Data] = [:]
    public var readError: Error?
    public var writeError: Error?

    public init() {}

    public func read(from url: URL) throws -> Data {
        if let error = readError { throw error }
        guard let data = files[url] else { throw CocoaError(.fileReadNoSuchFile) }
        return data
    }

    public func write(_ data: Data, to url: URL) throws {
        if let error = writeError { throw error }
        files[url] = data
    }

    public func fileExists(at url: URL) -> Bool { files[url] != nil }
}
```

`@unchecked Sendable` with plain `var`s is acceptable only because a test sets up the mock before use and does not share it across tasks. If a test mutates it concurrently, make the mock an actor or guard the state; otherwise the test itself has a race.

### 4. Inject with default parameters

```swift
public actor SyncManager {
    private let fileSystem: FileSystemProviding
    private let fileAccessor: FileAccessorProviding

    public init(
        fileSystem: FileSystemProviding = DefaultFileSystemProvider(),
        fileAccessor: FileAccessorProviding = DefaultFileAccessor()
    ) {
        self.fileSystem = fileSystem
        self.fileAccessor = fileAccessor
    }

    public func sync() async throws {
        guard let containerURL = fileSystem.containerURL(for: .sync) else {
            throw SyncError.containerNotAvailable
        }
        let data = try fileAccessor.read(from: containerURL.appendingPathComponent("data.json"))
        // process data
    }
}
```

The failure is thrown, not swallowed: the caller (and the test) can see it.

### 5. Tests with Swift Testing

```swift
import Testing

@Test("Sync throws when the container is missing")
func missingContainer() async {
    let manager = SyncManager(fileSystem: MockFileSystemProvider(containerURL: nil))

    await #expect(throws: SyncError.containerNotAvailable) {
        try await manager.sync()
    }
}

@Test("Sync reads data from the container")
func readsData() async throws {
    let accessor = MockFileAccessor()
    accessor.files[testURL] = testData

    let manager = SyncManager(fileAccessor: accessor)
    let result = try await manager.loadData()

    #expect(result == expectedData)
}

@Test("Sync reports a corrupt file")
func readError() async {
    let accessor = MockFileAccessor()
    accessor.readError = CocoaError(.fileReadCorruptFile)

    let manager = SyncManager(fileAccessor: accessor)

    await #expect(throws: CocoaError.self) {
        try await manager.sync()
    }
}
```

Assert the specific error that must propagate. A test that only asserts "did not crash" proves nothing about the failure path.

## Best practices

- **One concern per protocol.** No god protocols with many methods.
- **`Sendable` conformance** whenever the protocol is used across actor boundaries.
- **Default parameters** so production call sites never name the real implementation.
- **Configurable error properties** on mocks to drive every failure path.
- **Mock only boundaries** (file system, network, external APIs), never internal types.
- **Verify the mock matches reality.** Keep at least one integration test per boundary against the real implementation (a temp directory, a local server), or the mock can drift from real behavior.

## Anti-patterns

- A single large protocol covering all external access.
- Mocking internal types that have no external dependency.
- `#if DEBUG` switches instead of injection.
- Missing `Sendable` on protocols used with actors.
- A protocol for a type with no external dependency (over-engineering).
- Mocks that silently succeed when no behavior was configured; make them fail loudly instead.

## Related skills

- `swift-actor-persistence`: an actor whose file access should be injected like this.
- `swift-concurrency-6-2`: isolation and `Sendable` rules.
- `swiftui-patterns`: previews built from the same mocks.
- `rcode-ios`: Swift Testing as the default, test-first issue workflow.
