---
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,py,swift,go,rs,java,kt,kts,rb,php,vue,svelte,astro,sh,bash,zsh,c,h,cc,cpp,hpp,cs,m,mm,dart,gd,lua,ex,exs,scala,sql,prisma,html,css,scss}"
---

# Fail Loud Rule

> Ban silent fallbacks in agent-generated code. Path-scoped: loads when a source file is read or edited.

## The Rule

**Errors must propagate.** Silent fallbacks (returning a default when required input is missing, swallowing exceptions, masking failures with `try/except: pass`) are forbidden in agent-generated code.

## Why This Matters

Agents are statistically prone to "defensive" code that hides bugs, and each silent fallback **compounds reliability degradation** (the slop-on-slop math in [[slop-prevention]]).

## Forbidden Patterns

Python: `except: pass|continue|return None`, `except Exception: pass`, `value = cfg.get("required_key") or "default"` for a REQUIRED key. TypeScript/JavaScript: empty `catch {}`, `catch { return null }`, `.catch(() => {})`, `requiredKey ?? "default"` for a REQUIRED value.

## Repetition Without Escalation Is Also Silence (IMP-164, 2026-08-24)

A message that recurs unchanged N times is functionally a non-message — the reader habituates. A message class that fires N times in a row must change its presentation at a threshold (reference: `alarm_repeat_count` in `hooks/session-end-check.sh`: 3rd consecutive occurrence switches to an explicit escalation form, the 5th adds that a ledger entry is due); escalation, not volume, and never an auto-fix.

## Allowed Patterns (Legitimate Fallbacks)

Fallbacks are OK only:
- at system boundaries (user input, external API, network), with explicit error reporting;
- for truly optional values (feature flags, optional configs), where the default is documented behavior;
- as graceful degradation (UI loading states, retry-with-backoff), with the failure logged.

The distinction: **did the failure get reported somewhere observable?** Logged → OK; metric incremented → OK; returned but the caller doesn't know it's a fallback → NOT OK.

## Enforcement

`hooks/security-audit.sh` blocks the forbidden patterns above in incoming `.py`, `.ts` and `.js` code (IMP-271): a bare `except`, `except Exception` or `except BaseException` whose body is only `pass`, `continue` or `return None`, an empty `catch` block, a `catch` that returns `null`, an empty `.catch` callback. Override: `# ALLOWED: <reason>` (Python) or `// ALLOWED: <reason>` (JS/TS) on the handler line or the line directly above. Test, fixture and mock paths are exempt; a handler for a specific exception, or one that logs or re-raises, never fires. Everything else in this rule stays behavioural.

## When to Override

Test fixtures and mocks, generated code, formatter boilerplate, optional-dependency imports that log unavailability; document the override in the commit message.
