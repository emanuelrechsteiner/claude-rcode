#!/bin/bash
# Framework Inventory — disk-truth counts for the ~/.claude framework
# ──────────────────────────────────────────────────────────────────────────
# Emits the ACTUAL component counts from the filesystem so docs (CLAUDE.md,
# HARNESS.md) can reference instead of duplicate them (IMP-083: hand-counted
# numbers in docs drift; this script is the single source of truth).
#
# Counts:
#   rules             — non-.bak *.md directly in rules/ (archive/ excluded)
#   commands          — commands/*.md
#   skills            — skills/*/SKILL.md
#   hooks_disk        — non-.bak *.sh directly in hooks/ (tests/ excluded)
#   hooks_registered  — unique *.sh script paths wired in settings.json hooks
#   agents            — non-.bak *.md directly in agents/ (archived subdir excluded)
#   scheduled_tasks   — scheduled-tasks/*/SKILL.md (live definitions)  # was routines/*.yaml|*.yml templates
#
# Usage:
#   bash ~/.claude/scripts/framework-inventory.sh            # table + JSON
#   bash ~/.claude/scripts/framework-inventory.sh --json     # JSON only
#   bash ~/.claude/scripts/framework-inventory.sh --check rules=31 skills=41
#       # audit mode: exit 1 if any given expected count mismatches disk truth
#
# Exit codes:
#   0 — success (and, in --check mode, all expectations matched)
#   1 — --check mode found at least one mismatch
#   2 — script error (missing directory / missing jq)
set -uo pipefail

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"

# ── Preconditions (fail loud, per fail-loud.md) ───────────────────────────
if [[ ! -d "$CLAUDE_DIR" ]]; then
    echo "ERROR: CLAUDE_DIR not found: $CLAUDE_DIR" >&2
    exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required (hooks_registered is extracted from settings.json via jq)" >&2
    exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required (test_suites case counts are computed by a static analyzer)" >&2
    exit 2
fi
for d in rules commands skills hooks agents; do
    if [[ ! -d "$CLAUDE_DIR/$d" ]]; then
        echo "ERROR: expected directory missing: $CLAUDE_DIR/$d" >&2
        exit 2
    fi
done

# ── Counters (disk truth) ─────────────────────────────────────────────────
count_rules() {
    find "$CLAUDE_DIR/rules" -maxdepth 1 -type f -name '*.md' ! -name '*.bak*' | wc -l | tr -d ' '
}

count_commands() {
    find "$CLAUDE_DIR/commands" -maxdepth 1 -type f -name '*.md' ! -name '*.bak*' | wc -l | tr -d ' '
}

count_skills() {
    find "$CLAUDE_DIR/skills" -mindepth 2 -maxdepth 2 -type f -name 'SKILL.md' | wc -l | tr -d ' '
}

count_hooks_disk() {
    # -maxdepth 1 keeps hooks/tests/ out of the count
    find "$CLAUDE_DIR/hooks" -maxdepth 1 -type f -name '*.sh' ! -name '*.bak*' | wc -l | tr -d ' '
}

count_hooks_registered() {
    # Unique *.sh script paths referenced by any hook command in settings.json.
    # Inline `echo ...` hook commands carry no .sh path and are excluded.
    if [[ ! -f "$SETTINGS" ]]; then
        echo "ERROR: settings.json not found: $SETTINGS" >&2
        return 2
    fi
    jq -r '.hooks // {} | to_entries[] | .value[] | .hooks[]? | .command // empty' "$SETTINGS" \
        | grep -oE '[~/][^ "'"'"']*\.sh' \
        | sort -u | wc -l | tr -d ' '
}

count_agents() {
    # -maxdepth 1 keeps agents/archived-replaced-by-skills/ out of the count
    find "$CLAUDE_DIR/agents" -maxdepth 1 -type f -name '*.md' ! -name '*.bak*' | wc -l | tr -d ' '
}

count_scheduled_tasks() {
    # IMP-087: source of truth is scheduled-tasks/*/SKILL.md (the live definitions
    # the scheduler reads at fire time). The routines/*.yaml templates were removed
    # 2026-07-03 — they were a stale duplicate source (see routines/README.md).
    if [[ -d "$CLAUDE_DIR/scheduled-tasks" ]]; then
        find "$CLAUDE_DIR/scheduled-tasks" -mindepth 2 -maxdepth 2 -type f -name 'SKILL.md' | wc -l | tr -d ' '
    else
        echo 0
    fi
}

count_test_suites_json() {
    # IMP-205: per-suite test-CASE counts for every regression suite under
    # hooks/tests/*.sh and scripts/tests/*.sh — generated, never hand-counted.
    # Docs drifted the same way IMP-083 already found for rules/commands/
    # skills/hooks: serena-gate-regression.sh was documented as "35 cases",
    # disk truth is 37; gate-regression.sh was documented as "73 cases", disk
    # truth is 147. Emits a JSON array of {file, cases, note} — cases is null
    # (with a note explaining why) wherever the static heuristic below can't
    # confidently resolve a suite, per fail-loud.md: a wrong number is worse
    # than an honest "unknown".
    #
    # PURE STATIC ANALYSIS — never executes any suite, must run in well under
    # a second per file (no side effects, no risk to the real
    # global-observation state the suites themselves are careful to isolate
    # from). Verified by literally running the three mandated suites and
    # diffing their own final line against this analyzer's output:
    #   gate-regression.sh                    -> 147 (heuristic) == 147 (live run)
    #   serena-gate-regression.sh             ->  37 (heuristic) ==  37 (live run)
    #   dispatch-specialist-regression.sh     ->  15 (heuristic) ==  15 (live run)
    # (also cross-checked against a live run of every OTHER suite that
    # existed at the time this was written — see the task report.)
    #
    # THE ALGORITHM (why a plain `grep -c` of the assertion-helper name is not
    # enough): every suite maintains a pair of sibling counters (PASS/FAIL,
    # GRUEN/ROT, or a single running counter like N) that get incremented
    # exactly once per test case — either directly inline, or inside a small,
    # per-file-different set of "verdict" helper functions (assert/check/t/
    # pruefe_rc/ok+bad/decision/...). The analyzer:
    #   1. Masks quotes/heredocs/comments (recursively, so a `"$(jq '... "x"
    #      ...' f)"` nested-quote construct — common in this repo's suites —
    #      doesn't desync quote parity for the rest of the file) so brace
    #      matching and identifier scanning only see real bash syntax.
    #   2. Finds every top-level function and its body span (brace matching).
    #   3. Parses bash BLOCK structure (for/while/until, if/elif/else, case)
    #      via a recursive-descent pass over the block keywords, so it can
    #      model if/elif/else as MAX-across-branches rather than summing
    #      every branch — a flat sum overcounts the moment a branch pair is
    #      asymmetric (an "infra couldn't even set up the test" 1-line
    #      fallback next to a normal 3-assert happy path is exactly one
    #      branch executing, not both; two suites in this repo hit this
    #      pattern and were off by +1 before this was modeled).
    #   4. Picks a counter variable and recursively computes, for the
    #      top-level script body and every function, "how many times does
    #      this counter get incremented per invocation" — a wrapper function
    #      that itself calls other counted functions inherits their
    #      contribution (handles check()->ok()/bad() indirection, not only
    #      single-level assert()-style patterns).
    #   5. A `for VAR in <literal words>; do ... done` loop wrapping a verdict
    #      multiplies by the statically-parsed word count; any other loop
    #      (while/until, or a for-list with $.../`...`) is only a problem if
    #      its body actually contributes something (a setup loop that never
    #      touches the counter is safely ignored regardless of how many times
    #      it runs, or whether that's even knowable).
    #   6. Cross-checks EVERY counter variable the file defines against every
    #      other by majority vote — a genuine PASS/FAIL(/N) sibling set
    #      always agrees (each verdict touches exactly one), so agreement is
    #      the trust signal; an unrelated variable that happens to match the
    #      increment pattern (e.g. a session-id sequence counter) disagrees
    #      and is silently excluded, named in the note.
    local files=()
    local f
    for f in "$CLAUDE_DIR"/hooks/tests/*.sh "$CLAUDE_DIR"/scripts/tests/*.sh; do
        [[ -f "$f" ]] || continue
        case "$f" in *.bak*) continue ;; esac
        files+=("$f")
    done
    if [[ ${#files[@]} -eq 0 ]]; then
        echo "[]"
        return 0
    fi
    python3 - "$CLAUDE_DIR" "${files[@]}" <<'PY' | jq -s -c '.'
import json
import os
import re
import sys


class Unresolvable(Exception):
    def __init__(self, why):
        self.why = why


# ── quote/heredoc/comment masking (recursive, $()-aware — see rationale above) ──
def _mask_double_quoted(text, i, n, out):
    out[i] = ' '
    j = i + 1
    while j < n and text[j] != '"':
        ch = text[j]
        if ch == '\\' and j + 1 < n:
            out[j] = ' '
            out[j + 1] = ' '
            j += 2
            continue
        if ch == '$' and text[j:j + 3] == '$((':
            j = _skip_arithmetic_expansion(text, j, n)
            continue
        if ch == '$' and text[j:j + 2] == '$(':
            out[j] = ' '
            out[j + 1] = ' '
            j = _mask_command_context(text, j + 2, n, out, stop_at_paren=True)
            if 0 < j <= n and j - 1 < n:
                out[j - 1] = ' '
            continue
        if ch == '`':
            j = _mask_backtick(text, j, n, out)
            continue
        if out[j] != '\n':
            out[j] = ' '
        j += 1
    if j < n:
        out[j] = ' '
        j += 1
    return j


def _skip_arithmetic_expansion(text, i, n):
    # i points at the '$' of a $((...)) arithmetic expansion. Left completely
    # UNMASKED on purpose: this is the literal syntax the increment-pattern
    # regexes (VAR=$((VAR+1)), ((VAR++))) match against.
    depth = 2
    j = i + 3
    while j < n and depth > 0:
        if text[j] == '(':
            depth += 1
        elif text[j] == ')':
            depth -= 1
        j += 1
    return j


def _mask_backtick(text, i, n, out):
    out[i] = ' '
    j = i + 1
    while j < n and text[j] != '`':
        if text[j] == '\\' and j + 1 < n:
            out[j] = ' '
            out[j + 1] = ' '
            j += 2
            continue
        if out[j] != '\n':
            out[j] = ' '
        j += 1
    if j < n:
        out[j] = ' '
        j += 1
    return j


def _mask_command_context(text, i, n, out, stop_at_paren=False):
    while i < n:
        c = text[i]
        if stop_at_paren and c == ')':
            return i + 1
        if c == '\\' and i + 1 < n:
            i += 2
            continue
        if c == "'":
            j = text.find("'", i + 1)
            if j == -1:
                j = n - 1
            for k in range(i, min(j + 1, n)):
                if out[k] != '\n':
                    out[k] = ' '
            i = j + 1
            continue
        if c == '"':
            i = _mask_double_quoted(text, i, n, out)
            continue
        if c == '`':
            i = _mask_backtick(text, i, n, out)
            continue
        if c == '$' and text[i:i + 3] == '$((':
            i = _skip_arithmetic_expansion(text, i, n)
            continue
        if c == '$' and text[i:i + 2] == '$(':
            out[i] = ' '
            out[i + 1] = ' '
            j = _mask_command_context(text, i + 2, n, out, stop_at_paren=True)
            if 0 < j <= n and j - 1 < n:
                out[j - 1] = ' '
            i = j
            continue
        if not stop_at_paren and c == '<' and text[i:i + 2] == '<<':
            m = re.match(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1", text[i:])
            if m:
                delim = m.group(2)
                eol = text.find('\n', i)
                if eol == -1:
                    eol = n
                body_start = eol + 1
                pat = re.compile(r'(?m)^[ \t]*' + re.escape(delim) + r'[ \t]*$')
                mm = pat.search(text, body_start)
                if mm:
                    body_end = mm.start()
                    for k in range(body_start, min(body_end, n)):
                        if out[k] != '\n':
                            out[k] = ' '
                    i = eol + 1
                    continue
            i += 2
            continue
        if not stop_at_paren and c == '#':
            prev = text[i - 1] if i > 0 else '\n'
            if prev in ' \t\n;&|(' or i == 0:
                j = text.find('\n', i)
                if j == -1:
                    j = n
                for k in range(i, j):
                    out[k] = ' '
                i = j
                continue
        i += 1
    return i


def mask_source(text):
    n = len(text)
    out = list(text)
    _mask_command_context(text, 0, n, out, stop_at_paren=False)
    return ''.join(out)


# ── top-level function definitions via brace matching ──
FUNC_DEF_RE = re.compile(r'(?m)^[ \t]*([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{')


def find_functions(masked):
    funcs = {}
    for m in FUNC_DEF_RE.finditer(masked):
        name = m.group(1)
        open_idx = m.end() - 1
        depth = 0
        j = open_idx
        closed = None
        while j < len(masked):
            ch = masked[j]
            if ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0:
                    closed = j
                    break
            j += 1
        if closed is None:
            raise Unresolvable(f"unbalanced braces in function '{name}'")
        funcs[name] = (m.start(), m.end(), open_idx + 1, closed)
    return funcs


def toplevel_mask(masked, funcs):
    chars = list(masked)
    for _name, (def_start, _hdr_end, _body_start, closed) in funcs.items():
        for k in range(def_start, closed + 1):
            if chars[k] != '\n':
                chars[k] = ' '
    return ''.join(chars)


# ── counter-variable discovery ──
GENERIC_INCR_RE = re.compile(
    r'\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\$\(\(\s*\1\s*\+\s*1\s*\)\)'
    r'|\(\(\s*([A-Za-z_][A-Za-z0-9_]*)\+\+\s*\)\)'
    r'|\(\(\s*\+\+([A-Za-z_][A-Za-z0-9_]*)\s*\)\)'
)


def find_counter_vars(masked):
    found = []
    for m in GENERIC_INCR_RE.finditer(masked):
        v = m.group(1) or m.group(2) or m.group(3)
        if v not in found:
            found.append(v)
    return found


def incr_regex(var):
    return re.compile(
        r'\b' + re.escape(var) + r'\s*=\s*\$\(\(\s*' + re.escape(var) + r'\s*\+\s*1\s*\)\)'
        r'|\(\(\s*' + re.escape(var) + r'\+\+\s*\)\)'
        r'|\(\(\s*\+\+' + re.escape(var) + r'\s*\)\)'
    )


def call_regex(name):
    return re.compile(r'(?<![\w$])' + re.escape(name) + r'\b(?!\s*\(\))')


# ── block structure (for/while/until, if/elif/else, case) — recursive descent ──
BLOCK_KEYWORD_RE = re.compile(r'\b(for|while|until|do|done|if|then|elif|else|fi|case|esac)\b')


def parse_segments(masked, i, n, stop_words):
    segments = []
    text_start = i
    pos = i
    while True:
        m = BLOCK_KEYWORD_RE.search(masked, pos)
        if not m:
            segments.append(('text', text_start, n))
            return segments, n, None, None
        kw = m.group(1)
        if kw in stop_words:
            segments.append(('text', text_start, m.start()))
            return segments, m.start(), kw, m.end()

        if kw in ('for', 'while', 'until'):
            segments.append(('text', text_start, m.start()))
            hdr_start = m.start()
            _hdr_segs, do_pos, hit, do_end = parse_segments(masked, m.end(), n, {'do'})
            if hit != 'do':
                raise Unresolvable(f"'{kw}' loop header never reaches a matching 'do'")
            body_segs, done_pos, hit2, done_end = parse_segments(masked, do_end, n, {'done'})
            if hit2 != 'done':
                raise Unresolvable(f"'{kw}' loop body never reaches a matching 'done'")
            segments.append(('loop', kw, hdr_start, do_pos, body_segs))
            pos = done_end
            text_start = pos
            continue

        if kw == 'if':
            segments.append(('text', text_start, m.start()))
            branches = []
            cursor = m.end()
            while True:
                _cond_segs, then_pos, hit, then_end = parse_segments(masked, cursor, n, {'then'})
                if hit != 'then':
                    raise Unresolvable("'if'/'elif' never reaches a matching 'then'")
                body_segs, next_pos, hit2, next_end = parse_segments(
                    masked, then_end, n, {'elif', 'else', 'fi'}
                )
                branches.append(body_segs)
                if hit2 == 'fi':
                    pos = next_end
                    break
                if hit2 == 'else':
                    else_segs, fi_pos, hit3, fi_end = parse_segments(masked, next_end, n, {'fi'})
                    if hit3 != 'fi':
                        raise Unresolvable("'else' never reaches a matching 'fi'")
                    branches.append(else_segs)
                    pos = fi_end
                    break
                cursor = next_end
            segments.append(('if', branches))
            text_start = pos
            continue

        if kw == 'case':
            segments.append(('text', text_start, m.start()))
            inner_segs, _esac_pos, hit, esac_end = parse_segments(masked, m.end(), n, {'esac'})
            if hit != 'esac':
                raise Unresolvable("'case' never reaches a matching 'esac'")
            segments.append(('case', inner_segs))
            pos = esac_end
            text_start = pos
            continue

        raise Unresolvable(f"unexpected block keyword '{kw}'")


def static_for_list_length(original_slice):
    m = re.match(r'\s*for\s+[A-Za-z_][A-Za-z0-9_]*\s+in\s+(.*?)\s*(?:;|\n)?\s*$',
                 original_slice, re.S)
    if not m:
        raise Unresolvable("non-standard for-header (not 'for VAR in ...')")
    list_text = m.group(1)
    if re.search(r'\$|`|<\(|>\(', list_text):
        raise Unresolvable("for-list is dynamic ($..., `...`, or process substitution)")
    import shlex
    try:
        tokens = shlex.split(list_text)
    except ValueError as e:
        raise Unresolvable(f"for-list could not be tokenized: {e}")
    if not tokens:
        raise Unresolvable("for-list parsed to zero tokens")
    return len(tokens)


# ── recursive contribution computation (tree-walk over parse_segments) ──
def eval_segments(segments, region_masked, region_original, funcs, counter_var,
                   memo, in_progress, func_body_cache):
    total = 0
    for seg in segments:
        kind = seg[0]
        if kind == 'text':
            _, s, e = seg
            text_slice = region_masked[s:e]
            total += len(incr_regex(counter_var).findall(text_slice))
            for name in funcs:
                calls = len(call_regex(name).findall(text_slice))
                if calls:
                    total += calls * contribution_per_call(
                        name, funcs, counter_var, memo, in_progress, func_body_cache
                    )
        elif kind == 'loop':
            _, kind_word, hdr_start, do_pos, body_segs = seg
            body_contribution = eval_segments(
                body_segs, region_masked, region_original, funcs, counter_var,
                memo, in_progress, func_body_cache
            )
            if body_contribution == 0:
                pass
            elif kind_word == 'for':
                header_orig = region_original[hdr_start:do_pos]
                n_iter = static_for_list_length(header_orig)
                total += n_iter * body_contribution
            else:
                raise Unresolvable(
                    f"non-static '{kind_word}' loop wraps {body_contribution} "
                    f"contributing verdict site(s) per iteration — iteration "
                    f"count cannot be determined statically"
                )
        elif kind == 'if':
            _, branches = seg
            contribs = [
                eval_segments(b, region_masked, region_original, funcs, counter_var,
                               memo, in_progress, func_body_cache)
                for b in branches
            ]
            total += max(contribs) if contribs else 0
        elif kind == 'case':
            _, inner_segs = seg
            contribution = eval_segments(
                inner_segs, region_masked, region_original, funcs, counter_var,
                memo, in_progress, func_body_cache
            )
            if contribution != 0:
                raise Unresolvable(
                    f"'case' block contributes {contribution} verdict site(s) — "
                    f"arm selection isn't modeled"
                )
        else:
            raise Unresolvable(f"internal: unknown segment kind '{kind}'")
    return total


def analyze_region(region_masked, region_original, funcs, counter_var, memo, in_progress, func_body_cache):
    segments, _end, hit, _hit_end = parse_segments(region_masked, 0, len(region_masked), set())
    if hit is not None:
        raise Unresolvable(f"region parse stopped at an unexpected '{hit}'")
    return eval_segments(
        segments, region_masked, region_original, funcs, counter_var,
        memo, in_progress, func_body_cache
    )


def contribution_per_call(name, funcs, counter_var, memo, in_progress, func_body_cache):
    if name in memo:
        return memo[name]
    if name in in_progress:
        raise Unresolvable(f"recursive call cycle through '{name}'")
    in_progress.add(name)
    body_masked, body_original = func_body_cache[name]
    contribution = analyze_region(
        body_masked, body_original, funcs, counter_var, memo, in_progress, func_body_cache
    )
    in_progress.discard(name)
    memo[name] = contribution
    return contribution


def count_for_var(masked, original, funcs, top_masked, counter_var):
    memo = {}
    func_body_cache = {}
    for name, (_ds, _he, body_start, closed) in funcs.items():
        func_body_cache[name] = (masked[body_start:closed], original[body_start:closed])
    return analyze_region(top_masked, original, funcs, counter_var, memo, set(), func_body_cache)


# ── per-file orchestration ──
def analyze_file(path):
    try:
        with open(path, 'r', errors='replace') as fh:
            original = fh.read()
    except OSError as e:
        return {"cases": None, "note": f"could not read file: {e}"}

    try:
        masked = mask_source(original)
    except Exception as e:
        return {"cases": None, "note": f"masking failed: {e}"}

    try:
        funcs = find_functions(masked)
    except Unresolvable as e:
        return {"cases": None, "note": f"function parsing failed: {e.why}"}
    except Exception as e:
        return {"cases": None, "note": f"function parsing crashed: {e}"}

    top_masked = toplevel_mask(masked, funcs)

    counters = find_counter_vars(masked)
    if len(counters) == 0:
        return {"cases": None, "note": "no PASS/FAIL-style counter-increment pattern found"}

    resolved = {}
    failures = {}
    for cv in counters:
        try:
            resolved[cv] = count_for_var(masked, original, funcs, top_masked, cv)
        except Unresolvable as e:
            failures[cv] = e.why
        except RecursionError:
            failures[cv] = "region nesting too deep to analyze statically"
        except Exception as e:
            failures[cv] = f"unexpected analysis error: {e}"

    if not resolved:
        return {
            "cases": None,
            "note": "; ".join(f"{k}: {v}" for k, v in failures.items())
                    or "heuristic could not resolve any counter",
        }

    if len(resolved) == 1:
        cv = next(iter(resolved))
        note = f"only one counter variable ('{cv}') could be resolved — no cross-check possible"
        if failures:
            note += "; unresolved: " + ", ".join(f"{k} ({v})" for k, v in failures.items())
        return {"cases": resolved[cv], "note": note}

    from collections import Counter as _Counter
    tally = _Counter(resolved.values())
    best_value, best_count = tally.most_common(1)[0]
    if best_count >= 2:
        disagreeing = {cv: v for cv, v in resolved.items() if v != best_value}
        parts = []
        if disagreeing:
            parts.append("counters ignored as non-verdict (disagreed with the majority): "
                         + ", ".join(f"{k}={v}" for k, v in disagreeing.items()))
        if failures:
            parts.append("unresolved counters ignored: "
                         + ", ".join(f"{k} ({v})" for k, v in failures.items()))
        return {"cases": best_value, "note": "; ".join(parts) or None}

    note = "counters disagree with no majority: " + ", ".join(f"{k}={v}" for k, v in resolved.items())
    if failures:
        note += "; " + "; ".join(f"{k}: {v}" for k, v in failures.items())
    return {"cases": None, "note": note}


def main():
    claude_dir = sys.argv[1]
    for path in sys.argv[2:]:
        result = analyze_file(path)
        result["file"] = os.path.relpath(path, claude_dir)
        print(json.dumps(result))


if __name__ == '__main__':
    main()
PY
}

RULES=$(count_rules)
COMMANDS=$(count_commands)
SKILLS=$(count_skills)
HOOKS_DISK=$(count_hooks_disk)
HOOKS_REGISTERED=$(count_hooks_registered) || exit 2
AGENTS=$(count_agents)
SCHEDULED_TASKS=$(count_scheduled_tasks)
TEST_SUITES_JSON=$(count_test_suites_json) || exit 2
GENERATED_AT=$(date '+%Y-%m-%dT%H:%M:%S%z')

value_of() {
    case "$1" in
        rules)            echo "$RULES" ;;
        commands)         echo "$COMMANDS" ;;
        skills)           echo "$SKILLS" ;;
        hooks_disk)       echo "$HOOKS_DISK" ;;
        hooks_registered) echo "$HOOKS_REGISTERED" ;;
        agents)           echo "$AGENTS" ;;
        scheduled_tasks)  echo "$SCHEDULED_TASKS" ;;
        *)                echo "" ;;
    esac
}

emit_json() {
    jq -n \
        --arg generated_at "$GENERATED_AT" \
        --arg claude_dir "$CLAUDE_DIR" \
        --argjson rules "$RULES" \
        --argjson commands "$COMMANDS" \
        --argjson skills "$SKILLS" \
        --argjson hooks_disk "$HOOKS_DISK" \
        --argjson hooks_registered "$HOOKS_REGISTERED" \
        --argjson agents "$AGENTS" \
        --argjson scheduled_tasks "$SCHEDULED_TASKS" \
        --argjson test_suites "$TEST_SUITES_JSON" \
        '{
            generated_at: $generated_at,
            claude_dir: $claude_dir,
            rules: $rules,
            commands: $commands,
            skills: $skills,
            hooks_disk: $hooks_disk,
            hooks_registered: $hooks_registered,
            agents: $agents,
            scheduled_tasks: $scheduled_tasks,
            test_suites: $test_suites
        }'
}

emit_test_suites_table() {
    # IMP-205: readable rendering of $TEST_SUITES_JSON under the main table.
    local n total unresolved
    n=$(jq 'length' <<<"$TEST_SUITES_JSON")
    total=$(jq '[.[] | .cases // 0] | add // 0' <<<"$TEST_SUITES_JSON")
    unresolved=$(jq '[.[] | select(.cases == null)] | length' <<<"$TEST_SUITES_JSON")
    echo ""
    echo "  test suites (hooks/tests + scripts/tests) — disk truth, never executed"
    echo "  ─────────────────────────────────────────────────────────────────────"
    echo "  $n suites · $total counted cases · $unresolved unresolved (cases=null — see its NOTE)"
    echo ""
    jq -r '.[] | [.file, (if .cases == null then "n/a" else (.cases|tostring) end), (.note // "")] | @tsv' \
        <<<"$TEST_SUITES_JSON" \
        | while IFS=$'\t' read -r f cases note; do
            printf '  %-52s %6s' "$f" "$cases"
            [[ -n "$note" ]] && printf '   NOTE: %s' "$note"
            printf '\n'
        done
}

emit_table() {
    cat <<EOF
Framework Inventory — disk truth for $CLAUDE_DIR ($GENERATED_AT)

  Component          Count   Source
  ─────────────────  ─────   ─────────────────────────────────────────────
  rules              $(printf '%5s' "$RULES")   rules/*.md (non-.bak, archive/ excluded)
  commands           $(printf '%5s' "$COMMANDS")   commands/*.md
  skills             $(printf '%5s' "$SKILLS")   skills/*/SKILL.md
  hooks (disk)       $(printf '%5s' "$HOOKS_DISK")   hooks/*.sh (non-.bak, tests/ excluded)
  hooks (registered) $(printf '%5s' "$HOOKS_REGISTERED")   unique *.sh paths in settings.json hooks
  agents             $(printf '%5s' "$AGENTS")   agents/*.md (top-level only)
  scheduled tasks    $(printf '%5s' "$SCHEDULED_TASKS")   scheduled-tasks/*/SKILL.md
EOF
    emit_test_suites_table
}

# ── Modes ─────────────────────────────────────────────────────────────────
MODE="full"
if [[ "${1:-}" == "--json" ]]; then
    MODE="json"
elif [[ "${1:-}" == "--check" ]]; then
    MODE="check"
    shift
fi

case "$MODE" in
    json)
        emit_json
        ;;
    check)
        if [[ $# -eq 0 ]]; then
            echo "ERROR: --check requires at least one key=expected pair, e.g. --check rules=$RULES skills=$SKILLS" >&2
            echo "       valid keys: rules commands skills hooks_disk hooks_registered agents scheduled_tasks" >&2
            exit 2
        fi
        MISMATCH=0
        for pair in "$@"; do
            key="${pair%%=*}"
            expected="${pair#*=}"
            actual=$(value_of "$key")
            if [[ -z "$actual" ]]; then
                echo "ERROR: unknown key '$key' (valid: rules commands skills hooks_disk hooks_registered agents scheduled_tasks)" >&2
                exit 2
            fi
            if [[ ! "$expected" =~ ^[0-9]+$ ]]; then
                echo "ERROR: expected count for '$key' is not a number: '$expected'" >&2
                exit 2
            fi
            if [[ "$actual" -eq "$expected" ]]; then
                echo "OK       $key = $actual"
            else
                echo "MISMATCH $key: expected $expected, disk truth is $actual"
                MISMATCH=1
            fi
        done
        exit "$MISMATCH"
        ;;
    full)
        emit_table
        echo ""
        emit_json
        ;;
esac
