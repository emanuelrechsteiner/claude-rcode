# Fail Loud Rule

> Ban silent fallbacks in agent-generated code. Always loaded.

## The Rule

**Errors must propagate.** Silent fallbacks (returning a default when required input is missing, swallowing exceptions, masking failures with `try/except: pass`) are forbidden in agent-generated code.

## Why This Matters

Agents are statistically prone to writing "defensive" code that hides bugs:
- `except: pass` to "make the test green"
- `value = config.get("X") or "default"` when X is required
- `try { ... } catch { return null }` masking the real failure
- "Just adding a check" that silently skips broken paths

Each silent fallback **compounds reliability degradation** (slop-on-slop pattern from `slop-prevention.md`). At 0.95^20 = 36% reliability already without fallbacks, adding fallbacks accelerates the degradation toward zero.

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

**A message that recurs unchanged eight times is functionally a non-message.** Fail-loud is not satisfied by a routine that prints a warning every run if the warning never changes shape when nobody acts on it — the reader habituates, and an unresolved 20-day-old condition becomes visually identical to a fresh one-day condition. This is a distinct failure mode from the ones above: the failure *was* reported, every single time, and it was still effectively silent.

**The fix is escalation, not volume.** A message-class that fires N times in a row must change its own presentation at a threshold (see `hooks/session-end-check.sh`'s `alarm_repeat_count` helper, wired into the IMP-138 staleness reminder: 3rd consecutive occurrence switches from an informational line to an explicit "ESKALATION" form; 5th adds a note that a ledger entry is due). This is deliberately **not an auto-fix** — the human stays the gate — it only makes the N-th occurrence impossible to mistake for the 1st.

## Allowed Patterns (Legitimate Fallbacks)

Fallbacks are OK when:
1. **At system boundaries** — user input, external API, network. Wrap with explicit error reporting.
2. **Truly optional values** — feature flags, optional configs. Default is documented behavior, not error-masking.
3. **Graceful degradation** — UI loading states, retry-with-backoff. Failure is **logged**, not silenced.

The distinction: **Did the failure get reported somewhere observable?**
- Logged → OK
- Metric incremented → OK
- Returned but caller doesn't know it's a fallback → NOT OK

## Enforcement

Extend `~/.claude/hooks/security-audit.sh` with the detection regexes above. PreToolUse on Edit/Write blocks edits introducing the forbidden patterns.

If a fallback is genuinely needed, add an explicit `# ALLOWED: <reason>` comment that the hook can recognize as override.

## When to Override

- Test fixtures and mocks (test code is OK to swallow expected exceptions)
- Generated code from build tools
- Auto-formatters writing boilerplate
- Try/except around imports for optional dependencies (must log unavailable)

Document the override in commit message: `"allows fail-silent in test fixture per fail-loud.md exception"`.

> Evidence and incident history (moved verbatim, IMP-217): `docs/archive/rules-evidence/fail-loud.md`
