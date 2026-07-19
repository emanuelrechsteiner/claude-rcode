---
name: rcode-ios
description: iOS-specific adaptations of the R.Code atomic development workflow (toolchain defaults, SwiftData patterns, Swift Testing, mandatory i18n gate, /phase-gate overrides). Use when working in a R.Code-managed iOS project — `.rcode/` exists alongside `.xcodeproj` or `Package.swift`. Triggers on "iOS", "SwiftData", "SwiftUI", "Swift Testing", "SwiftLint", ".xcodeproj", "Package.swift", "Xcode", "@Observable", "Localizable.xcstrings", "iOS app bauen", "iOS projekt", "iOS entwickeln", "swift tests schreiben".
---

# R.Code-iOS

> iOS-specific adaptations of the R.Code atomic development workflow. Derived from IMP-008 (5 conversation logs, 87MB) and 2026-04-17 toolchain decisions on a reference iOS project. Use when `.rcode/` exists and the project is iOS (`.xcodeproj` or `Package.swift`). On-demand skill — demoted from always-loaded rule per IMP-079 (2026-07-03).

## Toolchain Defaults (2026-04)

| Tool | Default | Alternative | Rationale |
|------|---------|-------------|-----------|
| Xcode project | **Raw `.xcodeproj`** | XcodeGen, Tuist | Fewer moving parts. Apple tooling is first-class citizen. Team scale ≤ 3 devs. |
| Testing framework | **Swift Testing** | XCTest | Swift Testing is the 2026 standard; XCTest only for legacy targets or UI tests not yet ported. |
| Lint | **SwiftLint** | swift-format | SwiftLint has strict mode + broad rule coverage. Swift-format is formatting only. |
| UI framework | **SwiftUI + @Observable** | UIKit, Combine | @Observable (iOS 17+) replaces ObservableObject with less boilerplate. |
| Persistence | **SwiftData** | Core Data, Realm | SwiftData is native, less boilerplate than Core Data. Core Data only for legacy. |
| Dependency Manager | **SPM** | CocoaPods | Apple's direction. CocoaPods only for libraries not yet on SPM. |

Default these unless the project has explicit reason to differ.

## Issue Workflow (iOS-Specific)

### Phase Sequence (compressed vs. web: 5 vs. 8 phases)

1. **Explore & Understand** — Read the issue, map affected views/models/services. Check relevant SwiftData schema.
2. **Test-First** — Write failing Swift Testing tests that describe the desired behavior.
3. **Implement** — Minimum code to pass tests. Respect separation: View (SwiftUI) / ViewModel (@Observable) / Model (SwiftData).
4. **i18n Gate** — All user-facing strings in `Localizable.xcstrings`. No hardcoded strings in views. This phase is **mandatory**; blocks phase-gate.
5. **Review & Ship** — SwiftLint strict, Swift Testing green, Xcode build clean, preview renders without crash.

## Mandatory i18n Gate

Before any PR merges:
```bash
# Check for hardcoded string literals in SwiftUI views
grep -rn '"[A-Z][a-z].*"' --include="*.swift" Views/ | grep -v "Localizable" | grep -v "LocalizedStringKey"
```
Any hit in a view must be moved to `Localizable.xcstrings` with a translation key.

Why mandatory: Retrofitting i18n is 10x the cost of in-line discipline. Field evidence: 2 sprints lost to retrofit on an earlier iOS project.

## SwiftData Patterns

### @Model for persistent, @Observable for ephemeral
```swift
@Model final class User {          // persisted to SwiftData store
    var id: UUID
    var name: String
}

@Observable final class ProfileViewModel {   // view-scoped state
    var user: User
    var isEditing = false
}
```

### Query in the View, not the ViewModel
```swift
struct UserList: View {
    @Query(sort: \User.name) var users: [User]   // ✓ SwiftData handles invalidation
    var body: some View { ... }
}
```

### Migrations require VersionedSchema
```swift
enum UserSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [User.self] }
}
```
Never modify a `@Model` class without a migration plan.

## Testing Patterns (Swift Testing)

```swift
import Testing

@Suite("SplittingCalculator")
struct SplittingCalculatorTests {
    @Test("calculates 50-50 split correctly")
    func fiftyFifty() async throws {
        let result = SplittingCalculator.split(100_000, ratio: 0.5)
        #expect(result == (50_000, 50_000))
    }

    @Test(arguments: [100_000, 200_000, 50_000])
    func handlesVariousAmounts(_ amount: Int) async throws {
        let result = SplittingCalculator.split(amount, ratio: 0.5)
        #expect(result.0 + result.1 == amount)
    }
}
```

No XCTestCase subclassing in new code. Parametric tests via `arguments:`. Async tests are first-class.

## SwiftLint Configuration

Required `.swiftlint.yml`:
```yaml
opt_in_rules:
  - empty_count
  - closure_spacing
  - contains_over_first_not_nil
  - force_unwrapping
disabled_rules:
  - line_length  # too noisy for SwiftUI
strict: true
```

Enforce `force_unwrapping` — `!` is a red flag outside test fixtures.

## Anti-Patterns

### ❌ ObservableObject for new code
`@Observable` supersedes `ObservableObject`. Only use ObservableObject when integrating with UIKit or legacy.

### ❌ Core Data for new projects
SwiftData is the 2026 default. Only choose Core Data if you need features SwiftData lacks (CloudKit custom merges, NSFetchedResultsController).

### ❌ Hardcoded strings in views
Blocks i18n gate. No merge.

### ❌ XcodeGen/Tuist without team scale justification
Adds a toolchain hop for solo/small-team projects. Only valuable at 5+ devs or multi-target complexity.

### ❌ XCTest for new test files
Swift Testing is the default. XCTest only for UI tests not yet ported.

## Phase-Gate Command Override

`/phase-gate <N>` in iOS projects additionally verifies:
- SwiftLint strict mode passes with 0 warnings
- Swift Testing run exits 0 with all tests passing
- `xcodebuild -scheme <scheme> build` succeeds
- `Localizable.xcstrings` contains entries for all user-facing strings
- No `Math.random()` or equivalent in crypto-relevant code paths

## Example Reference Case

- `.rcode/` inside the app for framework development (see the `framework-extraction` skill)
- Decision 2026-04-17: Raw Xcode + Swift Testing + SwiftLint — no XcodeGen/Tuist
- MVP scope: Bootstrap, iOS-specific rules, Project docs, /issue + /phase-gate command overrides
- Reference implementation for R.Code-iOS extraction (see IMP-012)

## References

- IMP-008 (iOS Workflow v2, 2026-02-22) in improvement-ledger.json
- Reference iOS project at `~/code/your-ios-app`
- Swift Testing: https://developer.apple.com/documentation/testing
- SwiftData migrations: https://developer.apple.com/documentation/swiftdata/schema-migrations
