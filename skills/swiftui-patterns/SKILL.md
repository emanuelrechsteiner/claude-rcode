---
name: swiftui-patterns
description: SwiftUI architecture for iOS 17+ — @Observable state, view composition, type-safe NavigationStack routing, list performance. Use when building or reviewing SwiftUI views. Triggers on "SwiftUI view", "@Observable", "NavigationStack", "SwiftUI performance".
---

<!--
Adapted from affaan-m/ECC skills/swiftui-patterns @ c70874f (MIT, Copyright (c) 2026 Affaan Mustafa); reviewed and rewritten 2026-10-01 for this framework.
-->

# SwiftUI Patterns

Declarative, performant SwiftUI built on the Observation framework. In an R.Code iOS project, `rcode-ios` sets the toolchain defaults (SwiftUI + `@Observable`, Swift Testing, SwiftData); this skill supplies the view-level patterns on top.

## When to Use

- Building SwiftUI views and choosing state wrappers
- Designing navigation with `NavigationStack`
- Structuring view models and data flow
- Fixing slow or over-invalidating lists and layouts
- Injecting dependencies through the environment

## State management

### Property wrapper selection

Choose the simplest wrapper that fits.

| Wrapper | Use for |
|---|---|
| `@State` | View-local value types (toggles, form fields, sheet presentation) |
| `@Binding` | Two-way reference to a parent's `@State` |
| `@Observable` class + `@State` | A model the view owns, with several properties |
| `@Observable` class (no wrapper) | A model passed in from the parent, read-only |
| `@Bindable` | Two-way binding to a property of an `@Observable` |
| `@Environment` | Shared dependencies injected with `.environment()` |

### @Observable view model

Use `@Observable`, not `ObservableObject`: it tracks reads per property, so only views that read a changed property re-render. A load that can fail must surface the failure; do not swallow it into an empty list.

```swift
@Observable
final class ItemListViewModel {
    private(set) var items: [Item] = []
    private(set) var isLoading = false
    private(set) var loadError: Error?
    var searchText = ""

    private let repository: any ItemRepository

    init(repository: any ItemRepository = DefaultItemRepository()) {
        self.repository = repository
    }

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            items = try await repository.fetchAll()
        } catch {
            loadError = error   // the view renders an error state; never fall back to []
        }
    }
}
```

### View consuming the model

```swift
struct ItemListView: View {
    @State private var viewModel: ItemListViewModel

    init(viewModel: ItemListViewModel = ItemListViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List(viewModel.items) { item in
            ItemRow(item: item)
        }
        .searchable(text: $viewModel.searchText)
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            } else if let error = viewModel.loadError {
                ContentUnavailableView {
                    Label("Could not load items", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("Retry") { Task { await viewModel.load() } }
                }
            }
        }
        .task { await viewModel.load() }
    }
}
```

The error state is rendered with a retry action, so a failed load is never indistinguishable from an empty result.

### Environment injection

Replace `@EnvironmentObject` with `@Environment`: inject with `ContentView().environment(authManager)`, consume with `@Environment(AuthManager.self) private var auth`.

## View composition

Break views into small, focused structs: a state change then re-renders only the subview that reads it.

```swift
struct OrderView: View {
    @State private var viewModel = OrderViewModel()

    var body: some View {
        VStack {
            OrderHeader(title: viewModel.title)
            OrderItemList(items: viewModel.items)
            OrderTotal(total: viewModel.total)
        }
    }
}
```

Reusable styling goes into a `ViewModifier` with a small `View` extension (`func cardStyle() -> some View { modifier(CardModifier()) }`).

## Navigation

`NavigationStack` with a `NavigationPath` gives programmatic, type-safe routing.

```swift
@Observable
final class Router {
    var path = NavigationPath()
    func navigate(to destination: Destination) { path.append(destination) }
    func popToRoot() { path = NavigationPath() }
}

enum Destination: Hashable {
    case detail(Item.ID)
    case settings
    case profile(User.ID)
}

struct RootView: View {
    @State private var router = Router()

    var body: some View {
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: Destination.self) { dest in
                    switch dest {
                    case .detail(let id): ItemDetailView(itemID: id)
                    case .settings: SettingsView()
                    case .profile(let id): ProfileView(userID: id)
                    }
                }
        }
        .environment(router)
    }
}
```

## Performance

- **Lazy containers** for large collections: `ScrollView { LazyVStack(spacing: 8) { ForEach(items) { ItemRow(item: $0) } } }`.
- **Stable identifiers** in `ForEach`: use `Identifiable` or an explicit stable id (`ForEach(items, id: \.stableID)`), never array indices, or inserts and moves reuse the wrong view state.
- **Keep `body` cheap.** No I/O, network calls, or heavy computation in `body`. Async work goes in `.task {}`, which cancels automatically when the view disappears. Use `.sensoryFeedback()` and `.geometryGroup()` sparingly in scroll views, and minimize `.shadow()`, `.blur()`, and `.mask()` in lists (offscreen rendering).
- **Equatable views.** For a view with an expensive body, conform to `Equatable` (`static func == (lhs: Self, rhs: Self) -> Bool { lhs.dataPoints == rhs.dataPoints }`) so unchanged inputs skip re-rendering. Measure first (Instruments, SwiftUI template); do not add it speculatively.

## Previews

Use `#Preview` with inline mock data, one preview per state (empty, loaded, error).

```swift
#Preview("Empty") {
    ItemListView(viewModel: ItemListViewModel(repository: EmptyMockRepository()))
}
#Preview("Loaded") {
    ItemListView(viewModel: ItemListViewModel(repository: PopulatedMockRepository()))
}
```

## Anti-patterns

- `ObservableObject` / `@Published` / `@StateObject` / `@EnvironmentObject` in new code: migrate to `@Observable`.
- Async work directly in `body` or `init`: use `.task {}` or an explicit load method.
- Creating a model as `@State` in a child that does not own the data: pass it from the owner.
- `AnyView` type erasure: prefer `@ViewBuilder` or `Group`.
- Turning a thrown error into an empty value (`try?` then `?? []`): it hides the failure from the user and from you.
- Ignoring `Sendable` when data crosses into or out of actors.

## Related skills

`rcode-ios` (toolchain defaults, i18n gate), `swift-actor-persistence` (storage behind a view model), `swift-protocol-di-testing` (injection and Swift Testing), `swift-concurrency-6-2` (main-actor isolation), `liquid-glass-design` (iOS 26 glass). A visible UI claim ("fixed", "done") still needs a screenshot of the running app (`ios-simulator-testing`), not a code read.
