# Fail Loud Rule

> Ban silent fallbacks in agent-generated code. Triangulated from Armin Ronacher + Danilo Campos (PostHog Wizard postmortem) + Mario Zechner (KB cluster 10, 2026-05-26). Always loaded.

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

## References

- Armin Ronacher — "The Friction Is Your Judgment"
- Danilo Campos — "LLM codegen fails" (PostHog Wizard postmortem)
- Mario Zechner — "Building pi in a World of Slop"
- Cluster source: see author's knowledge base (private)
