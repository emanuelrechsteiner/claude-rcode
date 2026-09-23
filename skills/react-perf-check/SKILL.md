---
name: react-perf-check
description: Performance anti-pattern detection for React components. Detects state/ref conflicts, unnecessary re-renders, missing memoization, and animation performance issues. Use when experiencing UI lag, jank, or unexpected behavior. Triggers on "react performance", "slow render", "re-render", "laggy", "jank", "animation slow", "state ref conflict", "useEffect performance", "react performance prüfen", "langsames rendern", "ui ruckelt", "unnötige re-renders", "animation ruckelt", "komponente ist langsam".
user-invocable: false
allowed-tools: Read, Glob, Grep
---

# React Performance Check Skill

## Purpose

Detect common React performance anti-patterns that cause unnecessary re-renders, UI lag, or unexpected behavior. Focus on patterns that are easy to introduce but hard to debug.

## Anti-Pattern Categories

### 1. State/Ref Conflict (CRITICAL)

**The Problem:**
Using React state AND ref-based DOM updates for the same CSS property causes ref updates to be overwritten on every re-render.

**Detection:**

```bash
# Find components with refs that also use inline styles
grep -rn "ref={" src/ --include="*.tsx" -l | xargs grep -l "style={{" | while read f; do
  echo "Potential conflict in: $f"
  grep -n "ref=\|style={{" "$f"
done
```

**Pattern to Find:**

```tsx
// BAD - React overwrites ref updates on re-render
<div
  ref={elementRef}
  style={{ top: `${stateValue}%` }}  // React controls this
/>
// Later: elementRef.current.style.top = '50%' // Gets overwritten!

// GOOD - Ref has exclusive control
<div
  ref={elementRef}
  style={{ display: visible ? 'block' : 'none' }}  // Only static props
/>
// Ref controls position exclusively - works correctly
```

**Symptoms:**
- Animation doesn't respond in real-time
- UI updates lag behind user input
- Scroll position doesn't track smoothly

### 2. Missing useCallback/useMemo

**The Problem:**
Functions and objects created in render are new references every time, causing child components to re-render unnecessarily.

**Detection:**

```bash
# Find inline functions passed as props
grep -rn "onClick={() =>\|onChange={() =>\|onSubmit={() =>" src/ --include="*.tsx"

# Find inline object props
grep -rn "style={{" src/ --include="*.tsx" | grep -v "const\|let\|var"
```

**Pattern to Find:**

```tsx
// BAD - New function every render
<Button onClick={() => handleClick(item.id)} />

// GOOD - Stable reference
const handleItemClick = useCallback(() => {
  handleClick(item.id);
}, [item.id]);
<Button onClick={handleItemClick} />
```

### 3. useEffect Dependency Issues

**The Problem:**
Missing or excessive dependencies cause effects to run too often or not when needed.

**Detection:**

```bash
# Find useEffects with empty deps that reference external values
grep -B 10 "\[\])" src/ --include="*.tsx" | grep "useEffect"

# Find useEffects with many dependencies (potential issue)
grep -E "useEffect.*\[.{50,}\]" src/ --include="*.tsx"

# Find useEffects without dependency array (runs every render)
grep "useEffect(.*=>" src/ --include="*.tsx" | grep -v "\["
```

**Pattern to Find:**

```tsx
// BAD - Missing dependency
useEffect(() => {
  fetchData(userId);  // userId not in deps
}, []);

// BAD - Runs every render
useEffect(() => {
  console.log('Rendered');
});

// GOOD - Correct dependencies
useEffect(() => {
  fetchData(userId);
}, [userId]);
```

### 4. Expensive Calculations in Render

**The Problem:**
Heavy computations in render block the main thread.

**Detection:**

```bash
# Find array operations that might be expensive
grep -rn "\.filter(\|\.map(\|\.reduce(\|\.sort(" src/ --include="*.tsx" | grep -v "useMemo\|useCallback"

# Find potential heavy operations
grep -rn "JSON\.parse\|JSON\.stringify" src/ --include="*.tsx"
```

**Pattern to Find:**

```tsx
// BAD - Runs every render
const sortedItems = items.sort((a, b) => a.date - b.date);

// GOOD - Only recalculates when items change
const sortedItems = useMemo(
  () => items.sort((a, b) => a.date - b.date),
  [items]
);
```

### 5. Component Not Memoized

**The Problem:**
Child components re-render even when their props haven't changed.

**Detection:**

```bash
# Find components that might benefit from memo
# Look for components receiving object/function props
grep -rn "export function\|export const" src/components/ --include="*.tsx" | grep -v "memo("
```

**When to Use React.memo:**
- Component renders often with same props
- Component has expensive render logic
- Parent re-renders frequently

```tsx
// Consider memo for these
const ExpensiveList = memo(({ items }: { items: Item[] }) => {
  return items.map(item => <ExpensiveItem key={item.id} {...item} />);
});
```

### 6. Animation Performance Issues

**The Problem:**
Animations not using compositor-friendly properties or not optimized for smooth rendering.

**Detection:**

```bash
# Find CSS transitions on non-compositor properties
grep -rn "transition:" src/ --include="*.css" --include="*.tsx" | grep -v "transform\|opacity"

# Find scroll handlers that might need RAF
grep -rn "onScroll\|addEventListener.*scroll" src/ --include="*.tsx"
```

**Pattern to Find:**

```tsx
// BAD - Layout-triggering animation
element.style.top = scrollY + 'px';
element.style.left = scrollX + 'px';

// GOOD - Compositor-friendly animation
element.style.transform = `translate(${scrollX}px, ${scrollY}px)`;
```

## Quick Scan Commands

Run these for a performance audit:

```bash
# 1. State/Ref conflicts
echo "=== State/Ref Conflicts ==="
grep -rn "ref={.*Ref" src/ --include="*.tsx" -l | xargs -I{} sh -c 'grep -l "style={{" {} 2>/dev/null'

# 2. Inline functions
echo "=== Inline Event Handlers ==="
grep -c "onClick={() =>" src/**/*.tsx 2>/dev/null | grep -v ":0"

# 3. Missing deps
echo "=== Empty useEffect Dependencies ==="
grep -rn "useEffect.*\[\])" src/ --include="*.tsx" | head -10

# 4. Heavy render operations
echo "=== Potential Heavy Operations ==="
grep -rn "\.sort(\|\.filter(" src/ --include="*.tsx" | grep -v "useMemo" | head -10
```

## Performance Checklist

For each component, verify:

### Render Optimization
- [ ] No inline functions in JSX (use useCallback)
- [ ] No inline objects in JSX (use useMemo or const)
- [ ] Expensive calculations memoized
- [ ] List items have stable keys

### State Management
- [ ] No state/ref conflicts on same property
- [ ] State updates batched where possible
- [ ] No derived state that could be computed

### Effects
- [ ] All dependencies in useEffect array
- [ ] No effects that run every render
- [ ] Cleanup functions where needed

### Animation
- [ ] Using transform/opacity for animations
- [ ] RAF for scroll-linked animations
- [ ] will-change hint for animated elements

## Integration

This skill works with:
- `scroll-handling-patterns.md` rule for scroll-specific guidance
- `framework-specialist-agent` for complex React issues
- Component testing for before/after comparison

## Response Format

When reporting issues:

```
## Performance Analysis: [Component Name]

### Issues Found

| Severity | Issue | Location | Impact |
|----------|-------|----------|--------|
| 🔴 High | State/Ref conflict | line 42 | Animation lag |
| 🟡 Medium | Inline handler | line 15 | Child re-renders |
| 🟢 Low | Missing memo | export | Potential re-renders |

### Recommended Fixes

1. **[Issue]** at line X
   - Problem: [explanation]
   - Fix: [code suggestion]

### Performance Improvement Estimate
- Re-render reduction: ~X%
- Animation smoothness: [Improved/Unchanged]
```
