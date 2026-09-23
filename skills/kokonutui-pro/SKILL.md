---
name: kokonutui-pro
description: KokonutUI Pro setup and component installation — per-project shadcn/ui registry config, KOKO_PRO_TOKEN handling, and the complete component slug index (references/index.md). Use when setting up KokonutUI Pro in a project, adding components, or debugging registry auth/404 errors. Triggers on "kokonutui", "@kokonutui-pro", "koko", "KOKO_PRO_TOKEN", "shadcn add @kokonutui-pro", "kokonutui component", "kokonutui einrichten", "kokonutui komponente hinzufügen", "koko pro registry".
---

# KokonutUI Pro Setup

> KokonutUI Pro is a per-project shadcn/ui registry, not a global install. On-demand skill — demoted from always-loaded rule per IMP-079 (2026-07-03).

## The Rule

**The `KOKO_PRO_TOKEN` is globally available** (exported in `~/.zshrc` from `~/.koko_pro_token`, chmod 600) — no setup needed there.

**KokonutUI Pro itself is NOT global.** Each project needs its own Tailwind + shadcn/ui config with the registry block. Components are pulled on-demand via `npx shadcn add`.

## Per-Project Setup Checklist

Every project that uses KokonutUI Pro needs:

1. **Tailwind CSS** — installed and configured
2. **shadcn/ui** — initialized (`components.json` present at project root)
3. **The `@kokonutui-pro` registry block** in `components.json`

### Required `components.json` Registry Block

```json
{
  "registries": {
    "@kokonutui-pro": {
      "url": "https://kokonutui.pro/api/r/{name}",
      "headers": {
        "X-API-Key": "${KOKO_PRO_TOKEN}"
      }
    }
  }
}
```

The token is read from the environment at install time — `${KOKO_PRO_TOKEN}` resolves via the shell export in `~/.zshrc`.

### Adding a Component

```bash
npx shadcn add @kokonutui-pro/<component-name>
```

Example:
```bash
npx shadcn add @kokonutui-pro/animated-card
```

## Common Mistakes

### ❌ Assuming KokonutUI Pro works globally after token setup
The token is global; the registry config is not. A fresh project without `components.json` or the registry block will fail with an auth or "registry not found" error.

### ❌ Hardcoding the token value in `components.json`
Use `$KOKO_PRO_TOKEN` (env-var reference), not the literal token string. Prevents accidental commits.

### ❌ Running `npx shadcn add @kokonutui-pro/...` before `components.json` exists
Initialize shadcn/ui first: `npx shadcn init`. Then add the registry block. Then pull components.

## Quick Start for a New Project

```bash
# 1. Install Tailwind (framework-specific — e.g. Next.js)
npm install -D tailwindcss postcss autoprefixer
npx tailwindcss init -p

# 2. Initialize shadcn/ui
npx shadcn init

# 3. Add the kokonutui-pro registry block to components.json (see above)

# 4. Pull a component
npx shadcn add @kokonutui-pro/<component-name>
```

## Token Source — TWO places

1. **`~/.koko_pro_token`** (chmod 600, never committed) — single source of truth.
2. **`~/.zshrc`** → `export KOKO_PRO_TOKEN=$(cat ~/.koko_pro_token)` — this is what
   actually delivers the token to Claude Code's tools.

### ⚠️ CORRECTION 2026-08-04 — the third location was a dead letter box

This section previously demanded a **third** location, `~/.claude/settings.local.json`
→ `env.KOKO_PRO_TOKEN`, and called it "REQUIRED for Claude Code's tools". **That was
wrong on both counts, and the verification that "confirmed" it was a false positive.**

- **Claude Code does not read `~/.claude/settings.local.json`.** The `local` settings
  scope exists only **per project** (`.claude/settings.local.json` at a repository
  root) — see `code.claude.com/docs/en/settings`. There is no user-level equivalent.
- **Measured 2026-08-04:** the same file's `env` block also held
  `NOTION_PARENT_PAGE_ID`, which appears in **no** other source. It is **not set** in
  the session environment. Had the file been read, it would be.
- **Why the old check passed anyway:** `KOKO_PRO_TOKEN` was written to `~/.zshrc`
  **and** to `settings.local.json`. The verification below prints a non-empty value
  either way, so it credited the wrong source. Two wires, one lamp, only one of them
  carrying current — and the test only looked at the lamp.

**Where a value has to go instead:**

| Consumer | Working location |
|---|---|
| Claude's Bash tool, MCP servers, subagents (session started from a terminal) | `~/.zshrc` export |
| Something that must work **without** a shell profile (headless / scheduled runs) | `env` block in `~/.claude/settings.json` — **never for a secret**, that file is committed to a public repo |

> **General principle (revised): secrets belong in the shell profile, sourced from a
> chmod-600 file — never in any committed settings file.** The old principle named a
> file with no effect, which is worse than naming none: it reads as solved.

Verification (inside Claude's Bash, after a restart): `echo "${KOKO_PRO_TOKEN:-EMPTY}"`
must NOT print EMPTY. **This check alone proves only that *some* source works** — if
you are testing a specific location, remove the others first.

## Finding the correct component slugs

**The complete component index ships with this skill: `references/index.md`** (100 components, grouped by category). Slugs were taken verbatim from each page's official `shadcn add` command. Check it FIRST before installing anything.

Install any of them with:
```bash
npx shadcn add @kokonutui-pro/<slug>
```

### Regenerating the index (if it goes stale)

The Pro registry endpoint (`/api/r/{name}`) has **no public index** and the docs 403 plain HTTP fetchers — but **Firecrawl can read the pages** (real browser). To rebuild:
1. `firecrawl map "https://kokonutui.pro" --json` → discover category pages under `/docs/components/<category>`.
2. `firecrawl scrape` each category page → each lists its variants with their `@kokonutui-pro/<slug>` add command.
3. `grep -ohE '@kokonutui-pro/[a-z0-9-]+'` across the scraped `.md` files, `sort -u`.

Do NOT slug-guess against the registry: every wrong guess returns 404 even with valid auth, and the page-path ≠ registry-slug (e.g. page `footer/footer-01` but slug `footer-04`; `testimonials-01` page → slug `testimonial-01`).

## References

- Component slug index: `references/index.md` (in this skill)
- KokonutUI Pro registry endpoint: `https://kokonutui.pro/api/r/{name}` (auth header `X-API-Key: ${KOKO_PRO_TOKEN}`)
- KokonutUI Pro docs: https://kokonutui.pro/docs
- shadcn/ui registry docs: https://ui.shadcn.com/docs/registry
