---
name: liquid-glass-design
description: iOS 26 Liquid Glass for SwiftUI, UIKit, and WidgetKit — glassEffect, GlassEffectContainer, morphing, widget accent modes. Use when building or migrating to iOS 26 glass UI. Triggers on "Liquid Glass", "glassEffect", "GlassEffectContainer", "iOS 26 design".
---

<!--
Adapted from affaan-m/ECC skills/liquid-glass-design @ c70874f (MIT, Copyright (c) 2026 Affaan Mustafa); reviewed and rewritten 2026-10-01 for this framework.
-->

# Liquid Glass Design System (iOS 26)

Liquid Glass is Apple's dynamic material: it blurs content behind it, reflects color and light from its surroundings, and reacts to touch and pointer input. This skill covers SwiftUI, UIKit, and WidgetKit.

The API surface is new and moves between SDK releases. Before writing code, check symbol names and availability against Apple's current Liquid Glass documentation (or Context7) for the SDK in use, and guard with `#available(iOS 26, *)` while the app still supports older systems.

## When to Use

- Building or updating an app for the iOS 26 design language
- Glass-style buttons, cards, toolbars, containers; morphing between glass elements
- Glass in widgets
- Replacing hand-rolled blur or material effects

## SwiftUI

### Basic effect, shape, tint, interaction

```swift
Text("Hello, World!")
    .font(.title)
    .padding()
    .glassEffect()   // default: regular variant, capsule shape

Text("Hello, World!")
    .padding()
    .glassEffect(.regular.tint(.orange).interactive(), in: .rect(cornerRadius: 16.0))
```

- `.regular`: the standard glass. `.tint(Color)`: a color tint for prominence. `.interactive()`: reacts to touch and pointer input.
- Shapes: `.capsule` (default), `.rect(cornerRadius:)`, `.circle`.

### Button styles

```swift
Button("Click Me") { /* action */ }.buttonStyle(.glass)
Button("Important") { /* action */ }.buttonStyle(.glassProminent)
```

### GlassEffectContainer for several elements

Wrap sibling glass views in a container: it improves rendering performance and enables morphing. `spacing` is the merge distance; elements closer than that blend their shapes.

```swift
GlassEffectContainer(spacing: 40.0) {
    HStack(spacing: 40.0) {
        Image(systemName: "scribble.variable")
            .frame(width: 80.0, height: 80.0)
            .font(.system(size: 36))
            .glassEffect()
        Image(systemName: "eraser.fill")
            .frame(width: 80.0, height: 80.0)
            .font(.system(size: 36))
            .glassEffect()
    }
}
```

### Uniting effects

Combine several views into one glass shape with `glassEffectUnion`.

```swift
@Namespace private var namespace

GlassEffectContainer(spacing: 20.0) {
    HStack(spacing: 20.0) {
        ForEach(symbolSet.indices, id: \.self) { item in
            Image(systemName: symbolSet[item])
                .frame(width: 80.0, height: 80.0)
                .glassEffect()
                .glassEffectUnion(id: item < 2 ? "group1" : "group2", namespace: namespace)
        }
    }
}
```

### Morphing transitions

Give each element an id in a shared namespace and animate the hierarchy change.

```swift
@State private var isExpanded = false
@Namespace private var namespace

GlassEffectContainer(spacing: 40.0) {
    HStack(spacing: 40.0) {
        Image(systemName: "scribble.variable")
            .frame(width: 80.0, height: 80.0)
            .glassEffect()
            .glassEffectID("pencil", in: namespace)

        if isExpanded {
            Image(systemName: "eraser.fill")
                .frame(width: 80.0, height: 80.0)
                .glassEffect()
                .glassEffectID("eraser", in: namespace)
        }
    }
}

Button("Toggle") { withAnimation { isExpanded.toggle() } }
    .buttonStyle(.glass)
```

### Horizontal scrolling under a sidebar

Let the `ScrollView` content reach the container's leading and trailing edges; the system then handles scrolling under the sidebar or inspector. No extra modifier is needed.

## UIKit

```swift
let glassEffect = UIGlassEffect()
glassEffect.tintColor = UIColor.systemBlue.withAlphaComponent(0.3)
glassEffect.isInteractive = true

let visualEffectView = UIVisualEffectView(effect: glassEffect)
visualEffectView.translatesAutoresizingMaskIntoConstraints = false
visualEffectView.layer.cornerRadius = 20
visualEffectView.clipsToBounds = true
view.addSubview(visualEffectView)
// constrain it, and add content to visualEffectView.contentView

// Several glass elements: put them in a container effect
let containerEffect = UIGlassContainerEffect()
containerEffect.spacing = 40.0
let containerView = UIVisualEffectView(effect: containerEffect)
containerView.contentView.addSubview(UIVisualEffectView(effect: UIGlassEffect()))

// Scroll edge effects
scrollView.topEdgeEffect.style = .automatic
scrollView.bottomEdgeEffect.style = .hard
scrollView.leftEdgeEffect.isHidden = true

// Opt a toolbar item out of the shared glass background
favoriteButton.hidesSharedBackground = true
```

## WidgetKit

```swift
struct MyWidgetView: View {
    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        if renderingMode == .accented {
            // Tinted mode: white-tinted, themed glass background
        } else {
            // Full color mode
        }
    }
}

// Accent groups for visual hierarchy
HStack {
    VStack(alignment: .leading) {
        Text("Title").widgetAccentable()   // accent group
        Text("Subtitle")                   // primary group (default)
    }
    Image(systemName: "star.fill").widgetAccentable()
}

Image("myImage").widgetAccentedRenderingMode(.monochrome)   // images in accented mode

VStack { /* content */ }
    .containerBackground(for: .widget) { Color.blue.opacity(0.2) }
```

## Best practices

- Use `GlassEffectContainer` whenever several sibling views carry glass.
- Apply `.glassEffect()` after the other appearance modifiers (frame, font, padding).
- Use `.interactive()` only on elements that respond to input.
- Choose container `spacing` deliberately; it decides when shapes merge.
- Wrap hierarchy changes in `withAnimation` so morphing runs; pair `@Namespace` with `glassEffectID`.
- Support accented rendering in widgets; the system applies tinted glass on a tinted Home Screen.
- Test light, dark, and accented/tinted appearances, and with Reduce Transparency and Increase Contrast on.
- Keep text on glass readable: check contrast against varied backgrounds.

## Anti-patterns

- Several standalone `.glassEffect()` siblings without a container.
- Nesting many glass layers: costs performance and clarity.
- Glass on every view; reserve it for controls, toolbars, and cards.
- Missing `clipsToBounds = true` in UIKit when using corner radii.
- Ignoring accented rendering in widgets, which breaks the tinted Home Screen.
- Opaque backgrounds behind glass, which cancel the translucency.

## Verification

Glass is a visual claim. "Done" needs a screenshot of the running app or widget in the simulator (`ios-simulator-testing`), described in words and compared with the design, not a read of the modifier chain.

Related: `swiftui-patterns` (the views the glass is applied to), `rcode-ios` (workflow and toolchain defaults).
