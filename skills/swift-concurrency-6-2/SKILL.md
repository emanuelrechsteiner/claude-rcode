---
name: swift-concurrency-6-2
description: Swift 6.2 Approachable Concurrency — code stays on the calling actor, @concurrent offloads explicitly, isolated conformances fit main-actor types. Use when migrating to Swift 6.2 or fixing data-race errors. Triggers on "Swift 6.2", "@concurrent", "MainActor", "data race error".
---

<!--
Adapted from affaan-m/ECC skills/swift-concurrency-6-2 @ c70874f (MIT, Copyright (c) 2026 Affaan Mustafa); reviewed and rewritten 2026-10-01 for this framework.
-->

# Swift 6.2 Approachable Concurrency

Swift 6.2 makes code single-threaded by default and makes concurrency an explicit choice. Most "Sending ... risks causing data races" errors from Swift 6.0/6.1 disappear without giving up performance.

Re-check the exact setting names and proposal numbers against the current Swift and Xcode documentation before editing build settings; they are the fast-moving part.

## When to Use

- Migrating Swift 5.x or 6.0/6.1 code to Swift 6.2
- Resolving data-race safety compiler errors
- Designing a MainActor-centered app architecture
- Offloading CPU-heavy work to a background thread
- Conforming a MainActor-isolated type to a protocol
- Enabling the Approachable Concurrency settings in Xcode 26

## The core problem: implicit background offloading

In Swift 6.1 and earlier, a nonisolated async function could run off the caller's actor. That caused data-race errors even in code that looked safe.

```swift
// Swift 6.1: ERROR
@MainActor
final class StickerModel {
    let photoProcessor = PhotoProcessor()

    func extractSticker(_ item: PhotosPickerItem) async throws -> Sticker? {
        guard let data = try await item.loadTransferable(type: Data.self) else { return nil }
        // Error: Sending 'self.photoProcessor' risks causing data races
        return await photoProcessor.extractSticker(data: data, with: item.itemIdentifier)
    }
}
```

In Swift 6.2, with the nonisolated-nonsending behavior enabled, the same async function stays on the calling actor, and the code above compiles.

## Pattern 1: isolated conformances

A MainActor type can conform to a protocol safely when the conformance itself is isolated.

```swift
protocol Exportable { func export() }

// Swift 6.1: ERROR. Swift 6.2: OK with an isolated conformance.
extension StickerModel: @MainActor Exportable {
    func export() { photoProcessor.exportAsPNG() }
}
```

The compiler allows the conformance only where the main actor is guaranteed.

```swift
@MainActor
struct ImageExporter {
    var items: [any Exportable]
    mutating func add(_ item: StickerModel) { items.append(item) }   // OK: same isolation
}

nonisolated struct NonisolatedExporter {
    var items: [any Exportable]
    mutating func add(_ item: StickerModel) {
        items.append(item)   // ERROR: main actor-isolated conformance cannot be used here
    }
}
```

## Pattern 2: global and static state

Protect shared mutable state with the main actor.

```swift
// Swift 6.1: ERROR, non-Sendable type with shared mutable state
final class StickerLibrary {
    static let shared: StickerLibrary = .init()
}

// Fix
@MainActor
final class StickerLibrary {
    static let shared: StickerLibrary = .init()
}
```

### MainActor default isolation

Swift 6.2 adds an opt-in mode that infers `@MainActor` for a module's declarations, so no annotations are needed.

```swift
// With default MainActor isolation enabled for the target:
final class StickerLibrary {
    static let shared: StickerLibrary = .init()   // implicitly @MainActor
}

final class StickerModel {
    let photoProcessor: PhotoProcessor
    var selection: [PhotosPickerItem]              // implicitly @MainActor
}

extension StickerModel: Exportable {               // implicitly an isolated conformance
    func export() { photoProcessor.exportAsPNG() }
}
```

Recommended for app targets, scripts, and other executable targets. Not for library targets that want to stay nonisolated by default.

## Pattern 3: @concurrent for real parallelism

When profiling shows a real bottleneck, offload explicitly with `@concurrent`.

Requirement: this example is only race-free with both settings on, default MainActor isolation and nonisolated-nonsending-by-default. Without them the compiler flags a data race on `cachedStickers`.

```swift
nonisolated final class PhotoProcessor {
    private var cachedStickers: [String: Sticker] = [:]

    func extractSticker(data: Data, with id: String) async -> Sticker {
        if let sticker = cachedStickers[id] { return sticker }

        let sticker = await Self.extractSubject(from: data)
        cachedStickers[id] = sticker
        return sticker
    }

    // Expensive work runs on the concurrent pool
    @concurrent
    static func extractSubject(from data: Data) async -> Sticker { /* ... */ }
}

// Callers must await
processedPhotos[item.id] = await processor.extractSticker(data: data, with: item.id)
```

To adopt `@concurrent`:
1. Mark the containing type `nonisolated`.
2. Add `@concurrent` to the function.
3. Make the function `async` if it is not already.
4. Add `await` at every call site.

## Design decisions

| Decision | Rationale |
|---|---|
| Single-threaded by default | Most natural code is data-race free; concurrency is opt-in |
| Async stays on the calling actor | Removes the implicit offloading behind most false-positive races |
| Isolated conformances | MainActor types conform to protocols without unsafe workarounds |
| Explicit `@concurrent` | Background execution is a deliberate performance choice |
| MainActor default inference | Fewer boilerplate annotations in app targets |
| Opt-in per setting | Incremental, non-breaking migration |

## Migration steps

1. Enable the features in Xcode: Build Settings, Swift Compiler, Concurrency section.
2. In a Swift package, enable them through `SwiftSettings` in the manifest.
3. Use the migration tooling and guides published on swift.org for automatic changes.
4. Start with MainActor default isolation for app targets.
5. Profile first, then add `@concurrent` to the measured hot paths.
6. Build and test after each setting; races are now compile-time errors, so a clean build is real evidence.

## Best practices

- Write single-threaded code first, optimize later.
- Reserve `@concurrent` for CPU-heavy work (image processing, compression, parsing). I/O waits already suspend without it.
- Protect global and static mutable state with an actor or `@MainActor`.
- Prefer isolated conformances over `nonisolated` workarounds or `@Sendable` wrappers.
- Replace legacy `DispatchQueue` synchronization with actors where you touch the code anyway.
- Migrate one setting at a time.

## Anti-patterns

- `@concurrent` on every async function (most need no background execution).
- `nonisolated` added only to silence an error, without understanding the isolation.
- Keeping `DispatchQueue` locking next to actors for the same state.
- Fighting the compiler: a reported race is a real race until proven otherwise.
- Assuming async code runs in the background. In Swift 6.2 with these settings it stays on the calling actor.

## Related skills

- `swift-actor-persistence`: an actor-isolated store.
- `swiftui-patterns`: `@Observable` models and `.task {}`.
- `rcode-ios`: Swift Testing and the iOS toolchain defaults.
