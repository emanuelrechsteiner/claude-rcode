---
name: swift-actor-persistence
description: Thread-safe Swift persistence with actors — in-memory cache plus an atomically written JSON file, failed loads reported, not hidden. Use when local storage needs data-race safety. Triggers on "Swift actor", "actor repository", "thread-safe persistence", "local JSON storage".
---

<!--
Adapted from affaan-m/ECC skills/swift-actor-persistence @ c70874f (MIT, Copyright (c) 2026 Affaan Mustafa); reviewed and rewritten 2026-10-01 for this framework.
-->

# Swift Actors for Thread-Safe Persistence

A persistence layer where an actor serializes all access to an in-memory cache that is mirrored to a file. The compiler enforces the isolation, so locks and queues are not needed.

Choose the right store first: for relational or queryable app data in an R.Code iOS project the default is SwiftData (`rcode-ios`). This pattern fits small document-style data, settings, caches, and offline queues.

## When to Use

- A Swift 5.5+ persistence layer with shared mutable state
- Replacing `NSLock` or `DispatchQueue` synchronization
- Offline-first apps that sync later
- Local storage of user data, settings, or cached content

## Core pattern: actor-based repository

```swift
public actor LocalRepository<T: Codable & Identifiable & Sendable> where T.ID == String {
    private var cache: [String: T]
    private let fileURL: URL

    public init(directory: URL = .documentsDirectory, filename: String = "data.json") throws {
        let url = directory.appendingPathComponent(filename)
        self.fileURL = url
        // Synchronous load in init: no await needed, actor isolation not yet in play.
        self.cache = try Self.loadSynchronously(from: url)
    }

    // MARK: - Public API

    public func save(_ item: T) throws {
        cache[item.id] = item
        try persistToFile()
    }

    public func delete(_ id: String) throws {
        cache[id] = nil
        try persistToFile()
    }

    public func find(by id: String) -> T? { cache[id] }

    public func loadAll() -> [T] { Array(cache.values) }

    // MARK: - Private

    private func persistToFile() throws {
        let data = try JSONEncoder().encode(Array(cache.values))
        try data.write(to: fileURL, options: .atomic)
    }

    private static func loadSynchronously(from url: URL) throws -> [String: T] {
        // A missing file is a normal first launch. Anything else is a real failure.
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        let items = try JSONDecoder().decode([T].self, from: data)
        return Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }
}
```

Why the load throws: a version that maps every read or decode failure to an empty cache looks fine until a corrupt or newer-format file is read as "no data", and the next `save` overwrites the file with a near-empty set. Only "file does not exist" means "start empty". Corruption must reach the caller, which decides: show an error, quarantine the file, restore a backup, or migrate.

Also note `Dictionary(uniqueKeysWithValues:)` traps on duplicate ids. If the file can come from outside the app, merge explicitly instead.

### Usage

All calls are `await` because of actor isolation.

```swift
let repository = try LocalRepository<Question>()

let question = await repository.find(by: "q-001")        // O(1) from cache
let allQuestions = await repository.loadAll()

try await repository.save(newQuestion)                   // cache + atomic file write
try await repository.delete("q-001")
```

### With an @Observable view model

```swift
@Observable
final class QuestionListViewModel {
    private(set) var questions: [Question] = []
    private let repository: LocalRepository<Question>

    init(repository: LocalRepository<Question>) {
        self.repository = repository
    }

    func load() async { questions = await repository.loadAll() }

    func add(_ question: Question) async throws {
        try await repository.save(question)
        questions = await repository.loadAll()
    }
}
```

Construct the repository at the app root, where its `throws` can be turned into a visible error state (see `swiftui-patterns`).

## Design decisions

| Decision | Rationale |
|---|---|
| Actor, not class + lock | Compiler-enforced safety, no manual synchronization |
| In-memory cache + file | Fast reads, durable writes |
| Throwing synchronous init | Avoids async initializers; failures are not hidden |
| Dictionary keyed by id | O(1) lookup |
| Generic over `Codable & Identifiable & Sendable` | Reusable; values may cross the actor boundary |
| `.atomic` writes | No partial file if the app dies mid-write |

## Best practices

- Use `Sendable` types for everything that crosses the actor boundary.
- Keep the public API to domain operations; do not expose the cache or the file URL.
- Use `.atomic` writes. Consider a versioned envelope (`{"version": 1, "items": [...]}`) so a later format change can be told from corruption.
- Treat a configurable file URL as trusted input only; do not build it from untrusted strings.
- Test the failure paths too: missing file, corrupt file, write error (inject the file access behind a protocol, see `swift-protocol-di-testing`).

## Anti-patterns

- `DispatchQueue` or `NSLock` for new Swift-concurrency code.
- Returning the internal dictionary to callers.
- `nonisolated` to bypass the actor; it defeats the design.
- `try?` on load or save, turning an I/O failure into "no data" or "saved".
- Forgetting that every actor call needs `await`.

## Related skills

- `swift-concurrency-6-2`: isolation rules and `@concurrent`.
- `swift-protocol-di-testing`: injecting a mock file accessor.
- `swiftui-patterns`: the view layer on top.
