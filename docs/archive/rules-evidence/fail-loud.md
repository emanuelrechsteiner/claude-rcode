<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Evidence, incidents, and measurements moved verbatim out of rules/fail-loud.md on 2026-09-24 (IMP-217) — the rule itself stays there; this file carries the full-length "why".
-->
# Evidence for `rules/fail-loud.md`

> Moved out 2026-09-24 (IMP-217). Every block sits under the same heading it had in the rule, and is carried over unchanged.

## Title blockquote (intro line)

Triangulated from Armin Ronacher + Danilo Campos (PostHog Wizard postmortem) + Mario Zechner (KB cluster 10, 2026-05-26).

## Why This Matters

Agents are statistically prone to writing "defensive" code that hides bugs:
- `except: pass` to "make the test green"
- `value = config.get("X") or "default"` when X is required
- `try { ... } catch { return null }` masking the real failure
- "Just adding a check" that silently skips broken paths

Each silent fallback **compounds reliability degradation** (slop-on-slop pattern from `slop-prevention.md`). At 0.95^20 = 36% reliability already without fallbacks, adding fallbacks accelerates the degradation toward zero.

## Repetition Without Escalation Is Also Silence (IMP-164, 2026-08-24)

Fail-loud is not satisfied by a routine that prints a warning every run if the warning never changes shape when nobody acts on it — the reader habituates, and an unresolved 20-day-old condition becomes visually identical to a fresh one-day condition. This is a distinct failure mode from the ones above: the failure *was* reported, every single time, and it was still effectively silent.

Three documented cases in the same August-2026 window, all traced to this exact pattern:

1. **"Backfill the 7 drifted metric lines"** (said in German) — reported identically in 8 consecutive nightly routine runs, never actioned.
2. **`NOTION_PARENT_PAGE_ID` missing** — reported 10× over 12 days, same wording each time.
3. **The IMP-138 observation-loop staleness counter** — fired for 20 consecutive days (`stale=7` on 2026-08-03 climbing to `stale=26` on 2026-08-22, while `shards=6` sat frozen the whole span) and was overlooked the entire time. This one is the sharpest case: the alarm was **never silent** — it printed every session-end for three weeks — and it was still missed, because each day's printout looked like just another day's printout.

## References

- Armin Ronacher — "The Friction Is Your Judgment"
- Danilo Campos — "LLM codegen fails" (PostHog Wizard postmortem)
- Mario Zechner — "Building pi in a World of Slop"
- Cluster source: see author's knowledge base (private)

## Moved from the rule on 2026-09-29 (IMP-234)

> Moved out verbatim while the rule was condensed to its normative core. The rule now states this section in one paragraph; the "Why This Matters" list and the 0.95^20 math were already archived above.

### Repetition Without Escalation Is Also Silence (IMP-164, 2026-08-24) — original two paragraphs (verbatim)

**A message that recurs unchanged eight times is functionally a non-message.** Fail-loud is not satisfied by a routine that prints a warning every run if the warning never changes shape when nobody acts on it — the reader habituates, and an unresolved 20-day-old condition becomes visually identical to a fresh one-day condition. This is a distinct failure mode from the ones above: the failure *was* reported, every single time, and it was still effectively silent.

**The fix is escalation, not volume.** A message-class that fires N times in a row must change its own presentation at a threshold (see `hooks/session-end-check.sh`'s `alarm_repeat_count` helper, wired into the IMP-138 staleness reminder: 3rd consecutive occurrence switches from an informational line to an explicit "ESKALATION" form; 5th adds a note that a ledger entry is due). This is deliberately **not an auto-fix** — the human stays the gate — it only makes the N-th occurrence impossible to mistake for the 1st.

## Moved 2026-11-10 (context diet)

> Passages moved verbatim out of rules/fail-loud.md on 2026-11-10 (context diet). The rule keeps the normative text; this file carries the code examples, detection regexes, rationale and history.
>
> Note (2026-11-10, verified): the "Enforcement" block below describes detection in `hooks/security-audit.sh` that does not exist. `security-audit.sh` has no `except: pass` check and no `# ALLOWED:` marker (IMP-235 A3). The rule carries the corrected wording.

### Why This Matters

Agents are statistically prone to "defensive" code that hides bugs — including "just adding a check" that silently skips broken paths — and each silent fallback **compounds reliability degradation** (the slop-on-slop math in [[slop-prevention]]).

### Forbidden Patterns

#### Python
```python
# ❌ FORBIDDEN
except: pass
except Exception: pass
except: continue
value = config.get("required_key") or "default"  # if key is REQUIRED
try: x()
except: return None  # masking the failure
```

#### TypeScript / JavaScript
```typescript
// ❌ FORBIDDEN
try { x() } catch { }                                       // empty catch
try { x() } catch { return null }                           // mask
const value = config.requiredKey ?? "default"              // if REQUIRED
.catch(() => {})                                            // promise swallowing
```

#### Detection regex (for `security-audit.sh` extension)
```bash
# Python
grep -rE 'except\s*:\s*(pass|continue|return None)' src/
grep -rE 'except\s+Exception\s*:\s*(pass|continue|return None)' src/

# TypeScript
grep -rE 'catch\s*\([^)]*\)\s*\{\s*\}' src/                # empty catch block
grep -rE '\.catch\s*\(\s*\(\s*\)\s*=>\s*\{?\s*\}?\s*\)' src/   # promise.catch(() => {})
```

### Repetition Without Escalation Is Also Silence (IMP-164, 2026-08-24) — full original paragraph

**A message that recurs unchanged eight times is functionally a non-message:** a warning printed every run that never changes shape when nobody acts on it does not satisfy fail-loud — the reader habituates, and a 20-day-old unresolved condition looks identical to a fresh one. **The fix is escalation, not volume:** a message-class that fires N times in a row must change its own presentation at a threshold (reference: `hooks/session-end-check.sh`'s `alarm_repeat_count` helper on the IMP-138 staleness reminder — 3rd consecutive occurrence switches to an explicit "ESKALATION" form, the 5th adds a note that a ledger entry is due). Deliberately **not an auto-fix** — the human stays the gate; it only makes the N-th occurrence impossible to mistake for the 1st.

### Allowed Patterns (Legitimate Fallbacks) — first paragraph

Fallbacks are OK (1) **at system boundaries** — user input, external API, network — wrapped with explicit error reporting; (2) for **truly optional values** — feature flags, optional configs — where the default is documented behavior, not error-masking; (3) as **graceful degradation** — UI loading states, retry-with-backoff — with the failure **logged**, not silenced.

### Enforcement (original wording, superseded in the rule)

Extend `~/.claude/hooks/security-audit.sh` with the detection regexes above: PreToolUse on Edit/Write blocks edits introducing the forbidden patterns. If a fallback is genuinely needed, add an explicit `# ALLOWED: <reason>` comment that the hook can recognize as override.

### When to Override (original wording)

Test fixtures and mocks (test code may swallow expected exceptions); generated code from build tools; auto-formatters writing boilerplate; try/except around imports for optional dependencies (must log unavailable). Document the override in the commit message: `"allows fail-silent in test fixture per fail-loud.md exception"`.
