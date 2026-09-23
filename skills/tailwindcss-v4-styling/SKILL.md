---
name: tailwindcss-v4-styling
description: TailwindCSS v4 specialist ensuring correct theme configuration, variable naming, and utility class usage. Validates @theme directives, prevents spacing/container naming conflicts, and enforces v4 best practices. Use when setting up TailwindCSS v4, creating theme customizations, debugging styling issues, or implementing UI components with Tailwind. Triggers on "TailwindCSS", "Tailwind v4", "@theme", "styling broken", "CSS not working", "max-w", "spacing utilities", "theme configuration", "styling kaputt", "css geht nicht", "tailwind einrichten", "theme konfigurieren", "abstände stimmen nicht", "klassen greifen nicht".
user-invocable: false
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(npm:*)
---

# TailwindCSS v4 Styling Skill

## Critical Lessons Learned

**Recent Bug Fixed (2026-01-18):**
A semantic naming conflict in `@theme` caused all layout utilities to break:
- Used `--spacing-sm`, `--spacing-md`, `--spacing-lg` (intended as custom tokens)
- TailwindCSS v4 interpreted these as container sizes for `max-w-*` utilities
- Result: `max-w-sm` generated only 8px width instead of 384px
- **Fix**: Use single `--spacing` base unit and dedicated `--container-*` variables

## TailwindCSS v4 Architecture

### Key Changes from v3
1. **No config file**: Configuration via CSS `@theme` directive, not `tailwind.config.js`
2. **Vite plugin**: Use `@tailwindcss/vite` instead of PostCSS plugin
3. **Single spacing base**: One `--spacing` variable, utilities multiply it
4. **Reserved namespaces**: TailwindCSS owns specific variable name patterns
5. **CSS-first customization**: All theme customization in CSS files

### Reserved Variable Namespaces

TailwindCSS v4 reserves these patterns - **DO NOT** use them for custom tokens:

```css
/* ❌ NEVER use these patterns for custom variables */
--spacing-*     /* Reserved for container sizes (max-w-*, w-*) */
--color-*       /* Reserved for color utilities */
--font-*        /* Reserved for font utilities */
--text-*        /* Reserved for font size utilities */
--radius-*      /* Reserved for border radius utilities */
--shadow-*      /* Reserved for shadow utilities */
--container-*   /* Reserved for container max-width */

/* ✅ Safe custom variable patterns */
--space-*       /* Your custom spacing tokens */
--brand-*       /* Your brand-specific values */
--app-*         /* Application-specific values */
--custom-*      /* General custom values */
```

## Correct Theme Configuration

### Spacing System (CRITICAL)

```css
@theme {
  /* ✅ CORRECT: Single base unit for padding/margin multipliers */
  --spacing: 0.25rem;  /* p-4 = calc(0.25rem * 4) = 1rem */

  /* ✅ CORRECT: Dedicated container sizes */
  --container-sm: 24rem;    /* max-w-sm → 384px */
  --container-md: 28rem;    /* max-w-md → 448px */
  --container-lg: 32rem;    /* max-w-lg → 512px */
  --container-xl: 36rem;    /* max-w-xl → 576px */
  --container-2xl: 42rem;   /* max-w-2xl → 672px */

  /* ✅ CORRECT: Custom spacing tokens (different namespace) */
  --space-xs: 0.25rem;
  --space-sm: 0.5rem;
  --space-md: 1rem;
  --space-lg: 1.5rem;
  --space-xl: 2rem;
}
```

```css
/* ❌ WRONG: DO NOT DO THIS */
@theme {
  --spacing-xs: 0.25rem;   /* ❌ Conflicts with container sizing */
  --spacing-sm: 0.5rem;    /* ❌ max-w-sm will be 8px! */
  --spacing-md: 1rem;      /* ❌ max-w-md will be 16px! */
}
```

### Color System

```css
@theme {
  /* ✅ CORRECT: Use OKLCH for colors */
  --color-primary-50: oklch(0.98 0.03 95);
  --color-primary-100: oklch(0.96 0.06 93);
  --color-primary-500: oklch(0.80 0.17 85);
  --color-primary-900: oklch(0.40 0.10 65);

  /* ✅ CORRECT: Semantic color names */
  --color-success: oklch(0.75 0.15 145);
  --color-error: oklch(0.65 0.20 25);
  --color-warning: oklch(0.85 0.16 85);
}
```

### Typography System

```css
@theme {
  /* ✅ CORRECT: Font families */
  --font-sans: 'Inter', system-ui, sans-serif;
  --font-display: 'Nunito', var(--font-sans);
  --font-mono: 'JetBrains Mono', monospace;

  /* ✅ CORRECT: Font sizes with line heights */
  --text-xs: 0.75rem;
  --text-xs--line-height: 1.5;
  --text-sm: 0.875rem;
  --text-sm--line-height: 1.5;
  --text-base: 1rem;
  --text-base--line-height: 1.5;

  /* ✅ Font weights */
  --font-weight-normal: 400;
  --font-weight-medium: 500;
  --font-weight-semibold: 600;
  --font-weight-bold: 700;
}
```

## Configuration Validation Checklist

Before committing any `@theme` changes, validate:

### 1. Spacing Configuration
```bash
# ✅ Check: Single --spacing base unit exists
grep "^  --spacing:" src/styles/globals.css

# ✅ Check: Container sizes use --container-* namespace
grep "^  --container-" src/styles/globals.css

# ❌ Check: No --spacing-* variables (except base --spacing)
! grep "^  --spacing-[a-z]" src/styles/globals.css
```

### 2. Build Output Verification
```bash
# After changes, rebuild and verify utilities
npm run build

# ✅ max-w-sm should use --container-sm
grep "max-w-sm" dist/assets/main-*.css
# Expected: .max-w-sm{max-width:var(--container-sm)}

# ✅ p-4 should use --spacing calculation
grep "\.p-4{" dist/assets/main-*.css
# Expected: .p-4{padding:calc(var(--spacing)*4)}
```

### 3. Visual Inspection
- `max-w-sm` containers should be ~384px wide
- `p-4` padding should be 1rem (16px)
- Colors should render correctly
- Responsive breakpoints work

## Common Pitfalls & Solutions

### Pitfall 1: Spacing/Container Conflict (THE BUG WE FIXED)
**Problem:**
```css
@theme {
  --spacing-sm: 0.5rem;  /* ❌ Breaks max-w-sm */
}
```

**Solution:**
```css
@theme {
  --spacing: 0.25rem;           /* ✅ Base unit */
  --container-sm: 24rem;        /* ✅ For max-w-sm */
  --space-sm: 0.5rem;          /* ✅ Custom token */
}
```

### Pitfall 2: Overriding Default Tailwind Values
**Problem:** Accidentally replacing Tailwind's default spacing scale

**Solution:** Only define what you need to customize, Tailwind merges with defaults

### Pitfall 3: Mixing v3 and v4 Configuration
**Problem:** Having both `tailwind.config.js` and `@theme` directive

**Solution:** Remove `tailwind.config.js`, use only CSS `@theme`

### Pitfall 4: Incorrect @layer Order
**Problem:**
```css
@layer base {
  /* base styles */
}
@import "tailwindcss";  /* ❌ Import must come first */
```

**Solution:**
```css
@import "tailwindcss";  /* ✅ Import first */

@layer base {
  /* Custom base styles after import */
}

@theme {
  /* Theme customization */
}
```

## Component Styling Best Practices

### Use Utility Classes First
```tsx
/* ✅ GOOD: Utility-first approach */
<div className="max-w-sm p-4 bg-primary-500 rounded-lg">
  <h2 className="text-xl font-semibold">Title</h2>
</div>

/* ❌ AVOID: Custom CSS unless necessary */
<div className="custom-container">
  <h2 className="custom-heading">Title</h2>
</div>
```

### Responsive Design
```tsx
/* ✅ GOOD: Mobile-first responsive */
<div className="w-full sm:w-auto md:max-w-lg lg:max-w-xl">
  {/* Responsive container */}
</div>
```

### Custom Utilities (When Needed)
```css
/* When you need custom CSS, use @utility */
@utility custom-glass {
  background: rgba(255, 255, 255, 0.1);
  backdrop-filter: blur(10px);
  border: 1px solid rgba(255, 255, 255, 0.2);
}

/* Then use in components */
<div className="custom-glass p-6">
  {/* Glass morphism effect */}
</div>
```

## Setup Validation Protocol

When setting up TailwindCSS v4 in a new project:

1. **Install correct packages:**
   ```bash
   npm install tailwindcss @tailwindcss/vite
   ```

2. **Configure Vite plugin:**
   ```typescript
   // vite.config.ts
   import tailwindcss from '@tailwindcss/vite'

   export default defineConfig({
     plugins: [tailwindcss()],
   })
   ```

3. **Create CSS file with proper structure:**
   ```css
   /* src/styles/globals.css */
   @import "tailwindcss";

   @theme {
     /* Theme customization */
   }

   @layer base {
     /* Base overrides */
   }
   ```

4. **Import in app:**
   ```typescript
   // src/main.tsx
   import './styles/globals.css'
   ```

5. **Validate build:**
   ```bash
   npm run build
   # Check generated CSS has correct utilities
   ```

## Debugging Styling Issues

### Issue: "Utilities not working"
1. Check `@import "tailwindcss"` is first in CSS file
2. Verify Vite plugin is configured correctly
3. Check browser console for CSS errors
4. Rebuild: `npm run build`

### Issue: "max-w-* creates tiny widths"
1. **THIS IS THE BUG WE FIXED**
2. Check for `--spacing-*` variables in `@theme`
3. Replace with `--container-*` for layout sizes
4. Use single `--spacing` base unit

### Issue: "Colors not rendering"
1. Verify `--color-*` variables in `@theme`
2. Check OKLCH syntax is correct
3. Ensure color names match utility classes

### Issue: "Custom theme not applying"
1. Check `@theme` block is after `@import`
2. Verify variable names follow TailwindCSS conventions
3. Clear build cache: `rm -rf dist && npm run build`

## Memory Integration

When working on styling tasks:

1. **Query existing patterns:**
   ```javascript
   mcp__memory__search_nodes({ query: "styling theme tailwind" })
   ```

2. **Document theme decisions:**
   ```javascript
   mcp__memory__create_entities({
     entities: [{
       name: "TailwindCSS Theme",
       entityType: "Configuration",
       observations: [
         "Using --spacing: 0.25rem base unit",
         "Container sizes: --container-sm through --container-2xl",
         "Custom tokens use --space-* namespace"
       ]
     }]
   })
   ```

3. **Link to components:**
   ```javascript
   mcp__memory__create_relations({
     relations: [{
       from: "Button Component",
       to: "TailwindCSS Theme",
       relationType: "uses-styling-from"
     }]
   })
   ```

## Quick Reference Card

```
TailwindCSS v4 Variable Namespaces:
├─ --spacing (single value)      → Base unit for p-*, m-* arithmetic
├─ --container-* (sizes)         → Container max-width (max-w-*)
├─ --color-* (colors)            → Color palette (bg-*, text-*)
├─ --font-* (families)           → Font families (font-sans, font-mono)
├─ --text-* (sizes)              → Font sizes (text-sm, text-lg)
├─ --radius-* (sizes)            → Border radius (rounded-*)
├─ --shadow-* (values)           → Box shadows (shadow-*)
└─ Custom tokens                 → Use --space-*, --brand-*, --app-*

Common Utilities:
├─ Layout:     max-w-sm (384px), max-w-md (448px), max-w-lg (512px)
├─ Spacing:    p-4 (1rem), m-2 (0.5rem), gap-4 (1rem)
├─ Typography: text-base, font-semibold, leading-relaxed
├─ Colors:     bg-primary-500, text-gray-700
└─ Responsive: sm:, md:, lg:, xl:, 2xl:
```

## Success Criteria

A properly configured TailwindCSS v4 project should:
- ✅ Build without errors or warnings
- ✅ Generate correct utility classes in dist/assets/*.css
- ✅ Render layouts with proper container widths
- ✅ Apply spacing utilities consistently
- ✅ Support custom theme colors in OKLCH
- ✅ Work across all responsive breakpoints
- ✅ Have no `--spacing-*` variables except base `--spacing`

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-18 | Initial skill created after fixing spacing/container conflict bug |

---

**Remember:** TailwindCSS v4 is CSS-first. When in doubt, check the generated CSS output in `dist/` to verify utilities are correct.
