---
name: scroll-animation-patterns
description: Reusable scroll-linked animation patterns for React/Next.js. Covers RAF-driven character-chaos effects, sticky card decks, scroll-snap overlays, and avoids common state/ref conflicts. Use when implementing scroll-linked effects, hero reveal animations, or text/character staggered animations. Triggers on "scroll animation", "sticky card", "parallax", "character chaos", "scroll-linked", "RAF animation", "hero animation".
context: fork
model: sonnet
allowed-tools: Read, Write, Edit, Glob, Grep
---

# Scroll Animation Patterns

## Purpose

Provide battle-tested scroll-linked animation primitives extracted from a production landing page (reference implementation). Eliminates re-invention of RAF loops, ref synchronization, and CSS containment for each new project.

## When to Use

- Building a scroll-linked hero animation (text reveal, character chaos, character split)
- Implementing sticky card decks (overlapping cards revealed on scroll)
- Creating parallax or RAF-driven scroll effects without libraries (Framer Motion often overkill for simple cases)
- Debugging jank / frame drops on scroll animations

## Core Patterns

### Pattern 1 — CharacterChaos (per-character RAF-driven)

**When:** Text reveal where each character independently animates (position, rotation, opacity) based on scroll position.

**Key insights from the reference implementation:**
- Store character refs in an array; iterate in a single RAF callback
- Use `transform: translate3d()` + `opacity` only — do NOT animate `top/left/width/height`
- Add `will-change: transform, opacity` to the characters, remove after animation completes
- The single RAF loop must read scroll once, compute all character states, write transforms — never read/write interleaved (forced reflow kills frames)

```tsx
// Skeleton
function CharacterChaos({ text }: { text: string }) {
  const charsRef = useRef<(HTMLSpanElement | null)[]>([]);
  const rafRef = useRef<number>();
  const scrollYRef = useRef(0);

  useEffect(() => {
    const onScroll = () => {
      scrollYRef.current = window.scrollY;
      if (rafRef.current) return;           // RAF throttling
      rafRef.current = requestAnimationFrame(() => {
        const y = scrollYRef.current;
        charsRef.current.forEach((el, i) => {
          if (!el) return;
          const progress = computeProgress(y, i);
          el.style.transform = `translate3d(${progress * 50}px, ${progress * -20}px, 0) rotate(${progress * 15}deg)`;
          el.style.opacity = String(Math.min(progress * 2, 1));
        });
        rafRef.current = undefined;
      });
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    onScroll();
    return () => {
      window.removeEventListener("scroll", onScroll);
      if (rafRef.current) cancelAnimationFrame(rafRef.current);
    };
  }, []);

  return (
    <span>
      {Array.from(text).map((ch, i) => (
        <span
          key={i}
          ref={(el) => (charsRef.current[i] = el)}
          style={{ display: "inline-block", willChange: "transform, opacity" }}
        >
          {ch === " " ? "\u00A0" : ch}
        </span>
      ))}
    </span>
  );
}
```

### Pattern 2 — Sticky Card Deck

**When:** Multiple cards stack and reveal as user scrolls (common in storytelling landing pages).

**Technique:**
- Parent container gets `position: relative; height: N * 100vh`
- Each card `position: sticky; top: 0; height: 100vh`
- Use `IntersectionObserver` (not scroll listener) to toggle per-card state
- For overlap effects, apply `transform: scale()` + `opacity` based on next-card visibility

**Gotcha:** `position: sticky` requires NO `overflow: hidden` on any ancestor. Check early.

### Pattern 3 — Scroll-Snap with Overlay

**When:** Section-by-section scroll with overlay header/footer.

```css
html { scroll-snap-type: y mandatory; }
section { scroll-snap-align: start; min-height: 100vh; }
.overlay { position: fixed; inset: 0; pointer-events: none; }
.overlay > * { pointer-events: auto; }
```

## Anti-Patterns (From React Perf Experience)

### ❌ Animating layout properties
Never animate `width`, `height`, `top`, `left`, `margin`. Always `transform` + `opacity`. Browsers composite these on GPU; layout props force reflow per frame.

### ❌ State for every scroll tick
```tsx
// ❌ WRONG — triggers re-render per scroll event
const [scrollY, setScrollY] = useState(0);
useEffect(() => {
  window.addEventListener("scroll", () => setScrollY(window.scrollY));
}, []);
```
```tsx
// ✓ RIGHT — ref + RAF, no re-renders
const scrollRef = useRef(0);
```

### ❌ Reading scroll + writing in interleaved fashion
```tsx
// ❌ WRONG — forced reflow per character
chars.forEach((el, i) => {
  const y = window.scrollY;         // read
  el.style.transform = ...;         // write
});
```
```tsx
// ✓ RIGHT — read once, write all
const y = window.scrollY;
chars.forEach((el, i) => { el.style.transform = ...; });
```

### ❌ Forgetting passive listener
`{ passive: true }` on scroll listeners allows the browser to continue scroll while JS runs. Without it, scroll stutters on heavy handlers.

### ❌ Leaving `will-change` permanently
`will-change: transform` is a hint that costs GPU memory. Add it on animation start, remove on completion. Don't set it on hundreds of elements by default.

## Performance Budget

For smooth 60fps on mid-tier mobile:
- Scroll handler total < 8ms per frame (16.6ms budget; ≤8ms leaves room for compositing)
- No layout reads between writes within a single frame
- Max ~200 animated elements with transform updates per frame
- Test on Chrome DevTools Performance panel under CPU 4x slowdown

## Integration with react-perf-check

If scroll animation feels janky:
1. Run the `react-perf-check` skill
2. Check for state/ref conflicts (ref pattern above)
3. Check for unnecessary re-renders via React DevTools Profiler
4. Check for forced reflow in Chrome DevTools Performance panel

## References

- Production landing page (reference implementation, 2026-04, author's private project)
- CharacterChaos engine: lives in the reference implementation's hero section
- Sticky Card Deck: phase-transition sections of the same reference page
- MDN: https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_scroll_snap
- React scroll performance: https://web.dev/articles/rendering-performance
