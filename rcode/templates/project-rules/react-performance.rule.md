# React Performance Patterns

> Project-level rule: Install in `.claude/rules/` for React projects with performance requirements.

## Critical Anti-Pattern: React State + Ref DOM Conflicts

**NEVER** use both React-controlled inline styles AND ref-based DOM updates for the same CSS property. React will overwrite ref updates on every re-render.

```tsx
// BAD — React overwrites ref updates on re-render
<div ref={thumbRef} style={{ top: `${stateValue}%` }} />
// Then: thumbRef.current.style.top = '50%'  ← Gets overwritten!

// GOOD — Let ref have exclusive control for animated properties
<div ref={thumbRef} style={{ display: visible ? 'block' : 'none' }} />
// Ref controls position exclusively:
thumbRef.current.style.top = '50%'  // Works correctly
```

## Scroll-Linked Animations

For smooth animations during momentum scrolling (macOS touchpad):
1. Use native `addEventListener` with `{ passive: true }`
2. Start a RAF (requestAnimationFrame) loop on scroll/wheel events
3. Update positions every frame via refs (not state)
4. Stop loop on `scrollend` event or timeout

## CSS for Animated Elements

```css
.scroll-linked-element {
  will-change: top, height;  /* GPU compositing hint */
  transition: none;          /* Disable transitions for instant response */
}
```

## When to Use Native vs React Events

| Use Native (`addEventListener`) | Use React (`onScroll`) |
|--------------------------------|------------------------|
| High-frequency (scroll, wheel, mousemove) | Low-frequency events |
| Need `{ passive: true }` | Don't need passive |
| Updating DOM via refs | Updating React state |
| Performance-critical animations | Normal UI updates |

## Memoization Rules

- `useMemo` for expensive calculations that depend on specific values
- `useCallback` for functions passed as props to child components
- `React.memo` for components that re-render with same props
- Don't memoize everything — only when profiling shows it helps
