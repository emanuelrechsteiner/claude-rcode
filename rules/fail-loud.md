# Fail Loud Rule

> Ban silent fallbacks in agent-generated code. Always loaded.

## The Rule

**Errors must propagate.** Silent fallbacks (returning a default when required input is missing, swallowing exceptions, masking failures with `try/except: pass`) are forbidden in agent-generated code.

## Why This Matters

Agents are statistically prone to "defensive" code that hides bugs — including "just adding a check" that silently skips broken paths — and each silent fallback **compounds reliability degradation** (the slop-on-slop math in [[slop-prevention]]).

## Forbidden Patterns

### Python
```python
# ❌ FORBIDDEN
except: pass
except Exception: pass
except: continue
value = config.get("required_key") or "default"  # if key is REQUIRED
try: x()
except: return None  # masking the failure
```

### TypeScript / JavaScript
```typescript
// ❌ FORBIDDEN
try { x() } catch { }                                       // empty catch
try { x() } catch { return null }                           // mask
const value = config.requiredKey ?? "default"              // if REQUIRED
.catch(() => {})                                            // promise swallowing
```

### Detection regex (for `security-audit.sh` extension)
```bash
# Python
grep -rE 'except\s*:\s*(pass|continue|return None)' src/
grep -rE 'except\s+Exception\s*:\s*(pass|continue|return None)' src/

# TypeScript
grep -rE 'catch\s*\([^)]*\)\s*\{\s*\}' src/                # empty catch block
grep -rE '\.catch\s*\(\s*\(\s*\)\s*=>\s*\{?\s*\}?\s*\)' src/   # promise.catch(() => {})
```

## Repetition Without Escalation Is Also Silence (IMP-164, 2026-08-24)

**A message that recurs unchanged eight times is functionally a non-message:** a warning printed every run that never changes shape when nobody acts on it does not satisfy fail-loud — the reader habituates, and a 20-day-old unresolved condition looks identical to a fresh one. **The fix is escalation, not volume:** a message-class that fires N times in a row must change its own presentation at a threshold (reference: `hooks/session-end-check.sh`'s `alarm_repeat_count` helper on the IMP-138 staleness reminder — 3rd consecutive occurrence switches to an explicit "ESKALATION" form, the 5th adds a note that a ledger entry is due). Deliberately **not an auto-fix** — the human stays the gate; it only makes the N-th occurrence impossible to mistake for the 1st.

## Allowed Patterns (Legitimate Fallbacks)

Fallbacks are OK (1) **at system boundaries** — user input, external API, network — wrapped with explicit error reporting; (2) for **truly optional values** — feature flags, optional configs — where the default is documented behavior, not error-masking; (3) as **graceful degradation** — UI loading states, retry-with-backoff — with the failure **logged**, not silenced.

The distinction: **did the failure get reported somewhere observable?** Logged → OK; metric incremented → OK; returned but the caller doesn't know it's a fallback → NOT OK.

## Enforcement

Extend `~/.claude/hooks/security-audit.sh` with the detection regexes above: PreToolUse on Edit/Write blocks edits introducing the forbidden patterns. If a fallback is genuinely needed, add an explicit `# ALLOWED: <reason>` comment that the hook can recognize as override.

## When to Override

Test fixtures and mocks (test code may swallow expected exceptions); generated code from build tools; auto-formatters writing boilerplate; try/except around imports for optional dependencies (must log unavailable). Document the override in the commit message: `"allows fail-silent in test fixture per fail-loud.md exception"`.
