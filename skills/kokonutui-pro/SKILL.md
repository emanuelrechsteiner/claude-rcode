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

## Token Source — TWO places are required

The token lives in three locations for different consumers:

1. **`~/.koko_pro_token`** (chmod 600, never committed) — single source of truth.
2. **`~/.zshrc`** → `export KOKO_PRO_TOKEN=$(cat ~/.koko_pro_token)` — for **interactive** terminals you open yourself.
3. **`~/.claude/settings.local.json` → `env.KOKO_PRO_TOKEN`** (literal value) — **REQUIRED for Claude Code's tools.** Must be `settings.local.json` (gitignored), **NOT** `settings.json` (committed/shared) — see below.

### ⚠️ Why an `env` block at all — and why `settings.local.json`, NOT `settings.json` (learned 2026-06-06; corrected 2026-06-08)

Claude Code's Bash tool spawns a **non-interactive shell that does NOT source `~/.zshrc`**. So the zshrc export is invisible to `npx shadcn add` when Claude (or a subagent) runs it → auth fails with the token "missing" even though it's set in your terminal. That's why the token needs to live in a Claude `env` block.

The `env` block in **`settings.local.json`** is injected into every tool invocation (Bash + MCP servers) **exactly like `settings.json`** (it even takes precedence), so the token IS visible to `npx shadcn add`.

**Use `settings.local.json`, never `settings.json`:** `~/.claude` is a **shared, committed git repo** (`claude-code-config`). A literal token in `settings.json` gets pushed publicly and leaks the secret. `settings.local.json` is **gitignored** → it stays on your machine and is never committed.

> **General principle: secret tokens belong in `settings.local.json` (gitignored), never in committed `settings.json`.**

Note: no shell substitution happens in either file, so store the **literal token string** (not `$(cat ...)`). Re-paste the new value here after any rotation.

Verification (inside Claude's Bash, after a restart): `echo "${KOKO_PRO_TOKEN:-EMPTY}"` must NOT print EMPTY.

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
