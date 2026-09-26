#!/usr/bin/env bash
# PreToolUse|Bash hook — DETERMINISTIC CLASSIFIER for the Autonomy Arbiter (IMP-044 Layer B).
#
# History:
#   2026-05-26  Added per Wave 4 (KB cluster 09 — OWASP "Excessive Agency" LLM07 + Casco YC).
#   2026-06-09  REWRITE block-list → classifier (IMP-044). Filename kept to preserve the
#               PreToolUse|Bash chain order in settings.json
#               (guard-unsafe → git-state → git-identity → excessive-agency-gate).
#   2026-07-26  IMP-108: env-assignment prefixes whose values contain SPACED
#               $(…)/${…}/`…` spans no longer dodge command-position matching
#               (`GH_TOKEN=$(gh auth token --user X) gh release create` ran
#               unblocked); $( itself now opens a command position.
#
# What it is / is NOT:
#   This hook does NOT make the autonomy judgment — a PreToolUse hook is a synchronous
#   shell script and cannot call an LLM. The JUDGMENT lives in ~/.claude/rules/autonomy-arbiter.md
#   (always loaded) and, for delegated work, in the control-agent. This hook only
#   CLASSIFIES a command into a band and emits a deterministic verdict:
#
#     AUTO      → exit 0, silent. The common case — bash flows freely.
#     SOFT-ACK  → exit 0, one non-blocking NOTE line on stderr (arbiter self-acks observably).
#     ESCALATE  → exit 2, block + structured reason + the exact ack line to re-run after y/n.
#     CRITICAL  → not emitted here; guard-unsafe.sh runs FIRST and hard-blocks the floor
#                 (rm -rf / ~ $HOME *, sudo, dd, mkfs, …). This hook is the second opinion.
#
# Precedence (per settings.json): deny[] > ask[] > allow[]/defaultMode, THEN PreToolUse hooks.
#   git push --force, git reset --hard, npm publish are in native ask[] → they fire a real y/n
#   BEFORE this hook. This hook MUST NOT double-block them.
#
# Override (single-use, op-bound — replaces the broken session-wide CLAUDE_GATEGUARD_OFF):
#   After the user approves an ESCALATE op, re-run the SAME command with
#     CLAUDE_AGENCY_ACK_ONCE=<sha256-of-normalized-op-signature>  prepended.
#   The hook recomputes the sha from the data-stripped, whitespace-collapsed command and
#   allows it ONCE if the sha matches and has not been consumed. Replays re-block.

set -euo pipefail

# Read tool input (CC hook protocol)
INPUT=$(cat 2>/dev/null || printf '{}')

# Extract the bash command + session id.
# IMP-076/081: jq instead of a python3 spawn — this hook fires on EVERY Bash call
# and the python3 startup dominated the measured ~258ms gate latency; jq is ~10ms
# and already a hard dependency of the hook chain (guard-unsafe, session-end).
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || printf '')
HOOK_SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || printf '')

LOG_DIR="$HOME/.claude/global-observation"
LOG_FILE="$LOG_DIR/excessive-agency.log"

# ── D8: fail OPEN on empty/unparseable command ────────────────────────────────
# guard-unsafe.sh + native deny[] remain the CRITICAL floor regardless.
if [ -z "$COMMAND" ]; then
  exit 0
fi

# ── D6: test-mode exemption ───────────────────────────────────────────────────
# Lets the gate's own regression tests and excessive-agency.log analysis commands
# run without self-blocking. Logged, explicit, opt-in.
if [ "${CLAUDE_GATE_TESTMODE:-}" = "1" ]; then
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  # IMP-058: testmode records go to a SEPARATE log so regression-test bursts do not
  # drown the operational excessive-agency.log (observed 489/509 records = test noise).
  printf '{"ts":"%s","band":"TESTMODE","authorizer":"testmode","cwd":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(pwd)" >> "$LOG_DIR/excessive-agency-test.log" 2>/dev/null || true
  exit 0
fi

# ── Classifier (Python: command-position matching + rm -rf raw-target allowlist) ──
# Emits one line on stdout:  <BAND>\t<OP>\t<REASON>\t<SIG>
#   BAND  : AUTO | ESCALATE
#   OP    : short op label (for log + message)
#   REASON: one-line human reason (why irreversible)
#   SIG   : sha256 of the normalized (data-stripped, whitespace-collapsed) command
# SOFT-ACK is currently advisory-only and handled by the arbiter rule, so the hook
# emits AUTO for soft-ack-class ops (it never blocks them); ESCALATE is the only block.
VERDICT=$(EAG_CMD="$COMMAND" python3 <<'PYEOF' 2>/dev/null
import os, re, hashlib, sys

cmd = os.environ.get("EAG_CMD", "")
if not cmd.strip():
    sys.stdout.write("AUTO\t\t\t"); sys.exit(0)

# ---- normalize: strip heredoc bodies + quoted strings, collapse whitespace ----
# Used BOTH for command-position matching (so an op inside a string/heredoc/path
# is not treated as executed) AND for the op-bound ack signature.
def strip_data(s):
    out, in_h, tag = [], False, None
    hd = re.compile(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?")
    for ln in s.split("\n"):
        if in_h:
            if ln.strip() == tag:
                in_h = False
            continue
        m = hd.search(ln)
        if m:
            tag = m.group(1); in_h = True; out.append(ln[:m.start()]); continue
        out.append(ln)
    s = "\n".join(out)
    s = re.sub(r"'[^']*'", "", s)      # single-quoted strings → data
    s = re.sub(r'"[^"]*"', "", s)      # double-quoted strings → data
    return s

# Remove the ack-token assignment BEFORE normalizing, so the signature is identical
# whether or not the user has prepended CLAUDE_AGENCY_ACK_ONCE=<sha> — that is what
# makes "re-run with the suggested token" match the originally-shown signature.
cmd_for_sig = re.sub(r"CLAUDE_AGENCY_ACK_ONCE=[A-Fa-f0-9]+\s*", "", cmd)

stripped = strip_data(cmd_for_sig)
norm = re.sub(r"\s+", " ", stripped).strip()

# ── SIGNATURE: hash the command WITH its data, not the data-stripped form ────
# IMP-119 (2026-08-01) — SECURITY FIX. The signature used to be sha256(norm),
# i.e. of the string AFTER strip_data() removed every quoted span. That made
#     rm -rf "/pfad/A"   and   rm -rf "/pfad/B"
# hash IDENTICALLY (verified: both 3aa78388a06d8af1…), so an ack token minted
# after the user approved deleting A also authorized deleting B. The token's
# whole premise — "op-bound, single-use" — silently did not hold for any op
# whose target was quoted.
#
# strip_data() is still exactly right for COMMAND-POSITION MATCHING (an op name
# inside a string must not count as executed). It is wrong for identity. The
# two uses are now separated: `norm` classifies, `sig_src` identifies.
sig_src = re.sub(r"\s+", " ", cmd_for_sig).strip()
sig = hashlib.sha256(sig_src.encode("utf-8", "replace")).hexdigest()

def emit(band, op, reason):
    sys.stdout.write("%s\t%s\t%s\t%s" % (band, op, reason, sig)); sys.exit(0)

# ---- command-position helper -------------------------------------------------
# An op fires only at the START of a command, immediately after  ; && || | newline,
# or at the head of a $(…) command substitution — a substitution EXECUTES its
# content, so `V=$(gh pr merge 1) x` performs the merge while parsing as a mere
# assignment (IMP-108). Backticks are deliberately NOT anchors: open and close
# are indistinguishable, and anchoring both would FP on `echo \`date\` gh pr merge`
# (op as data AFTER a substitution).
#
# It also tolerates leading `VAR=value` env-assignments (so `FOO=bar gh pr merge`
# is not a dodge) and, for git, intervening `git -c key=value` global options.
# IMP-108: the assignment VALUE may contain whitespace inside $(…), ${…} or
# backticks — `GH_TOKEN=$(gh auth token --user X) gh release create` ran
# unblocked because the old \S* stopped at the first inner space, the assignment
# loop died on the next word, and the command head was never reached. ENV_VAL
# matches those spans structurally; its alternatives are first-char disjoint, so
# there is no backtracking blowup. Quoted values are already neutralized upstream
# by strip_data. Unparseable values (nested $(…$(…)…), spaced $((…))) simply end
# the prefix match → fail-open exactly as before; guard-unsafe.sh + native
# deny[] remain the CRITICAL floor.
ENV_VAL = r"(?:\$\([^()]*\)|\$\{[^{}]*\}|`[^`]*`|\$(?![({])|[^\s$`])*"
CP = (r"(?:^|[\n;]|&&|\|\||(?<![|&])\|(?![|&])|\$\()[ \t]*"
      r"(?:[A-Za-z_][A-Za-z0-9_]*=" + ENV_VAL + r"[ \t]+)*")

def cp_match(op_regex):
    return re.search(CP + op_regex, stripped) is not None

# git, tolerating any number of  -c key=value / -C path  global options
GIT = r"git(?:\s+-[cC]\s+\S+)*\s+"

# ---- IMP-163-followup (2026-08-24 security-review finding) --------------------
# aws/gcloud/vercel all accept their own global options BETWEEN the binary and
# the subcommand (`aws --profile p configure set …`, `gcloud --verbosity=none
# config set account …`, `vercel --debug switch …`) — measured live: every one
# of those forms exited 0 (AUTO) against the strict "<tool> <subcommand>"
# adjacency the checks below used to require. OPT tolerates one such flag
# (short or long, with or without a value); the value-branch's negative
# lookahead (`(?!-)`) stops a bare boolean flag from swallowing the NEXT flag
# as its own value — when that would block the real subcommand from matching,
# Python's re backtracks the optional value away and still finds it (verified
# against `vercel --debug switch other-team` below).
OPT = r"(?:--?[A-Za-z][A-Za-z0-9-]*(?:=\S+|\s+(?!-)\S+)?)"
AWS = r"aws(?:\s+" + OPT + r")*\s+"
GCLOUD = r"gcloud(?:\s+" + OPT + r")*\s+"
VERCEL = r"vercel(?:\s+" + OPT + r")*\s+"

# ---- ESCALATE: GitHub state/comms (irreversible + notifies others) -----------
if cp_match(r"gh\s+pr\s+merge"):
    emit("ESCALATE", "gh pr merge", "merges + closes the PR and notifies others; cannot be unmerged cleanly")
if cp_match(r"gh\s+pr\s+close"):
    emit("ESCALATE", "gh pr close", "closes the PR and notifies others")
if cp_match(r"gh\s+release\s+create"):
    emit("ESCALATE", "gh release create", "publishes a release visible to others; not silently revertible")
if cp_match(r"gh\s+workflow\s+disable"):
    emit("ESCALATE", "gh workflow disable", "disables CI/CD for the repo; affects all contributors")

# ---- ESCALATE: global machine/account-identity changes (IMP-163) -------------
# These commands change identity or config OUTSIDE the current project/session —
# the shell's active gh account, vercel team, global git/npm config, or the
# active gcloud/aws account/profile. Unlike a file edit this state persists
# after the session ends and the NEXT, unaware run silently inherits it.
# Evidence: `gh auth switch --user <account>` ran without a y/n and was
# reported only afterward; 3 documented wrong-repo/wrong-deploy-account
# incidents trace to exactly this (rules/agency-bands.md "Global Machine-State
# Changes"). Read-only / repo-local forms stay AUTO — see each check below.
if cp_match(r"gh\s+auth\s+switch"):
    emit("ESCALATE", "gh auth switch", "changes the active GitHub identity for ALL future gh calls in this shell; inherited by the next unaware session")
# vercel/gcloud/aws: tolerate an intervening global flag (--debug, --verbosity=…,
# --profile p, …) between the binary and the subcommand — see OPT/VERCEL/
# GCLOUD/AWS above. Bare-form cases (no intervening flag) match unchanged.
if cp_match(VERCEL + r"switch\b"):
    emit("ESCALATE", "vercel switch", "changes the active Vercel team/scope for ALL future deploys in this shell")
if cp_match(GCLOUD + r"config\s+set\s+account\b"):
    emit("ESCALATE", "gcloud config set account", "changes the active gcloud account for this shell")
# `aws configure list`/`get` are read-only; the wizard and `set` write credentials/profile.
if cp_match(AWS + r"configure\b") and not re.search(AWS + r"configure\s+(?:list|get)\b", stripped):
    emit("ESCALATE", "aws configure", "writes AWS CLI credentials/profile globally, outside this project")
# npm config set: -g/--global writes OUTSIDE the project's .npmrc — and so does
# the documented equivalent -L/--location=global (npm-config(1): "location …
# Default: 'user' unless --global is passed, which will also set this value to
# 'global' … Type: 'global', 'user', or 'project' … When passed to npm config
# this refers to which config file to use."). --location=global/--location
# global/-L global/-L=global therefore write the SAME global npmrc as -g —
# only the flag spelling differs. --location=project (and the default,
# unqualified form) still write inside the user/project scope and are
# intentionally left AUTO here — see the Nicht-Auftrag note for the
# unqualified/--location=user case.
#
# IMP-163-followup (2026-08-24 security-review finding): the original check
# required literal `npm config set` adjacency, so `npm -g config set …` /
# `npm --global config set …` (the global flag placed BEFORE the subcommand,
# which npm accepts) silently bypassed it. Fix: capture the WHOLE npm
# invocation up to the next command terminator and test for "config" and
# "set" tokens ANYWHERE in it (in that order), then test -g/--global/location
# anywhere in the same segment — this covers the flag landing before OR after
# `config set` without needing a per-flag tolerant prefix.
#
# IMP-163-followup (2026-09-09 security-review findings, x2): the location-
# value check used to run against `_npm_seg`, itself sliced from `stripped` —
# the output of strip_data(), which erases the CONTENTS of every quoted span.
# `--location='global'` therefore read as `--location=` by the time this
# regex ran, and the trailing `['\"]?global['\"]?` was dead code (the quotes
# AND the word were already gone). Measured live: `--location=global` (bare)
# exited 2, `--location='global'` exited 0 — same effective npm behavior,
# different verdict. Fix: re-locate the same, already-position-confirmed
# invocation inside `cmd_for_sig` (quotes intact — same technique classify_rm()
# below already relies on for quoted rm targets) and match the value with an
# explicit backreference (`(['"]?)global\1`) instead of two independent
# optional-quote groups, so a quote on one side without its pair cannot match.
# Chose this over widening strip_data itself: strip_data is shared by every
# other classifier arm (rm targets, SQL runner, git's global-flag check), and
# narrowing its quote-erasure behavior risks reopening the op-name-as-data
# false-positive class (IMP-040) that strip_data exists to prevent — a fix
# local to the one check that needs quote-preserved data is safer.
_npm_m = re.search(CP + r"npm\b[^\n;|&]*", stripped)
if _npm_m:
    _npm_seg = _npm_m.group(0)
    if re.search(r"\bconfig\b.*\bset\b", _npm_seg):
        if re.search(r"(?:^|\s)(?:-g|--global)(?:\s|$)", _npm_seg):
            emit("ESCALATE", "npm config set -g/--global", "writes an npm config value globally, outside the project's .npmrc")
        _npm_raw_m = re.search(CP + r"npm\b[^\n;|&]*", cmd_for_sig)
        _npm_seg_raw = _npm_raw_m.group(0) if _npm_raw_m else _npm_seg
        if re.search(r"(?:^|\s)(?:-L|--location)(?:=|\s+)(['\"]?)global\1(?:\s|$)", _npm_seg_raw):
            emit("ESCALATE", "npm config set --location=global", "writes an npm config value globally via --location=global (documented equivalent of -g), outside the project's .npmrc")
# git config: only a WRITE outside the repo's own scope is gated; read-only
# global forms stay AUTO, and plain `git config` (no scope flag, i.e.
# repo-local) never matches at all.
#
# IMP-163-followup (2026-08-24 security-review finding): --global was the only
# gated scope-flag, but `--system` (writes /etc/gitconfig, machine-wide) and
# `--file <path>`/`-f <path>` (writes to ANY attacker-chosen path, which can
# just as easily be the user's own ~/.gitconfig) have the identical
# outside-this-repo effect and were not checked at all. Each gets its own
# honest op label rather than being lumped under "git config --global".
_gitcfg_m = re.search(CP + GIT + r"config\b[^\n;|&]*", stripped)
if _gitcfg_m:
    _seg = _gitcfg_m.group(0)
    _gitcfg_readonly = re.search(
        r"(?:^|\s)(?:-l|--list|--get\b|--get-all\b|--get-regexp\b)(?:\s|$)", _seg
    )
    if not _gitcfg_readonly:
        if re.search(r"(?:^|\s)--global(?:\s|$)", _seg):
            emit("ESCALATE", "git config --global", "writes to the user's GLOBAL git config, not just this repo")
        if re.search(r"(?:^|\s)--system(?:\s|$)", _seg):
            emit("ESCALATE", "git config --system", "writes to the machine-wide /etc/gitconfig, outside this repo and this user")
        if re.search(r"(?:^|\s)(?:--file(?:=|\s+)\S|-f(?:=|\s+)\S)", _seg):
            emit("ESCALATE", "git config --file/-f", "writes to an explicit, attacker-choosable config path outside this repo's default scope (e.g. the user's own ~/.gitconfig)")

# ---- ESCALATE: package / image publish + cluster delete ----------------------
if cp_match(r"cargo\s+publish"):
    emit("ESCALATE", "cargo publish", "publishes a crate to the registry; cannot be unpublished")
if cp_match(r"pip\s+upload") or cp_match(r"twine\s+upload"):
    emit("ESCALATE", "pip/twine upload", "publishes a package to the index; cannot be unpublished")
if cp_match(r"docker\s+push"):
    emit("ESCALATE", "docker push", "publishes an image to the registry; visible/pullable by others")
if cp_match(r"kubectl\s+delete"):
    emit("ESCALATE", "kubectl delete", "deletes live cluster resources; not recoverable")

# ---- ESCALATE: force-delete branch / clean untracked -------------------------
# (git push --force / reset --hard / npm publish are in native ask[] → NOT here, D2.)
if cp_match(GIT + r"branch\s+-D\b"):
    emit("ESCALATE", "git branch -D", "force-deletes a branch with possibly-unmerged commits")
if cp_match(GIT + r"clean\s+-[a-z]*f"):
    emit("ESCALATE", "git clean -f", "permanently deletes untracked files")

# ---- ESCALATE: SQL destructive via a SQL-runner at command position (D3b) ----
# DROP TABLE / TRUNCATE always live INSIDE a quoted arg, so command-position alone
# would miss real `psql -c "DROP TABLE ..."`. Special-case: a SQL-runner CLI at
# command head WHOSE ARGUMENT (the raw, unstripped cmd) contains the keyword.
SQL_RUNNER = r"(?:psql|mysql|mariadb|sqlite3|mysqlsh|usql|cockroach\s+sql)"
if cp_match(SQL_RUNNER):
    if re.search(r"\bDROP\s+TABLE\b", cmd, re.IGNORECASE):
        emit("ESCALATE", "DROP TABLE", "drops a table via a SQL runner; irreversible data/schema loss")
    if re.search(r"\bTRUNCATE\b", cmd, re.IGNORECASE):
        emit("ESCALATE", "TRUNCATE", "truncates a table via a SQL runner; irreversible data loss")

# ---- rm -rf raw-target classification (D4, on the UNSTRIPPED target) ----------
# AUTO-PASS disposable / re-buildable / relative targets; ESCALATE the rest.
# guard-unsafe.sh keeps the CRITICAL hard floor on  rm -rf / ~ $HOME *.
def classify_rm(c):
    # find every  rm ... -rf/-fr/-r -f ... <targets...>  occurrence at command position
    for m in re.finditer(CP + r"rm\b((?:\s+-[A-Za-z]+)*)((?:\s+(?:--[A-Za-z-]+))*)\s+(.*)", c):
        # require a recursive+force intent (-rf, -fr, -r ... -f, or long opts)
        head = c[m.start():]
        # only care when both recursive and force present somewhere in the rm invocation
        seg = re.split(r"(?:[\n;]|&&|\|\|)", head)[0]
        # IMP-108: a $(-anchored rm ends at the substitution's close paren — tokens
        # after `)` belong to the OUTER command (data), not to this rm's target list.
        # ("$" + "(" instead of a literal "$(" — this heredoc sits inside a bash
        # $(...) substitution whose scanner parses the body; an active $( inside
        # double quotes opens a nested substitution that never closes → the whole
        # hook dies with a syntax error. Same defusal as \$\( in the regexes.)
        if seg.startswith("$" + "("):
            seg = seg.split(")", 1)[0]
        if not re.search(r"-[A-Za-z]*r", seg):   # recursive
            continue
        if not (re.search(r"-[A-Za-z]*f", seg) or "--force" in seg):  # force
            continue
        # collect target tokens = non-flag tokens after the `rm`
        toks = seg.split()
        targets = []
        seen_rm = False
        for t in toks:
            if not seen_rm:
                # IMP-108: the anchor char(s) can be glued to the first token
                # ($(rm, ;rm) — strip them before recognizing the rm word.
                # ("$" + "(" is the bash-$()-scanner defusal, see classify_rm.)
                tc = t.lstrip(";|&").removeprefix("$" + "(")
                if tc == "rm" or tc.endswith("/rm"):
                    seen_rm = True
                continue
            if t.startswith("-"):
                continue
            # strip surrounding quotes so a quoted target is classified by its path
            t = t.strip('"').strip("'")
            targets.append(t)
        if not targets:
            # `rm -rf` with no explicit target → ambiguous → escalate
            return ("ESCALATE", "rm -rf (no target)", "recursive force-delete with no explicit target")
        for raw in targets:
            verdict = classify_rm_target(raw)
            if verdict is not None:
                return verdict
    return None

DISPOSABLE_BASENAMES = {
    "node_modules", "dist", "build", ".next", ".nuxt", "target",
    ".cache", ".venv", "coverage", ".turbo",
    # IMP-063a: additional well-known build/cache artifact dirs (safe to AUTO-delete).
    "out", "storybook-static", ".svelte-kit", ".astro", ".output",
    ".vite", ".parcel-cache", ".angular",
}

def classify_rm_target(raw):
    t = raw
    # NOTE (IMP-059): the glob check was MOVED below the temp-root check so that a glob
    # under a disposable temp root (e.g. `rm -rf /tmp/o_*.png`) is AUTO, not ESCALATE.
    # The ".." traversal guard below still runs first, so `/tmp/../*` cannot sneak through.
    # ".." anywhere in the path → escalate (traversal can climb out of disposable scope,
    # e.g. /tmp/../etc or node_modules/../src). Must precede temp/disposable AUTO checks.
    if ".." in t.split("/"):
        return ("ESCALATE", "rm -rf (parent traversal)", "recursive force-delete with '..' in path: %s" % raw)
    # explicit dangerous dotfiles/dirs even if relative
    base = t.rstrip("/").split("/")[-1]
    if base in {".ssh", ".git", ".env"} or base.startswith(".env"):
        return ("ESCALATE", "rm -rf (sensitive dotpath)", "recursive force-delete of a sensitive path: %s" % raw)
    if t in {".", "..", "./", "../"} or t.rstrip("/") in {".", ".."}:
        return ("ESCALATE", "rm -rf (cwd/parent)", "recursive force-delete of '.' or '..': %s" % raw)
    # home / tilde
    if t == "~" or t.startswith("~/") or t.startswith("$HOME") or t.startswith("${HOME}"):
        return ("ESCALATE", "rm -rf ($HOME)", "recursive force-delete under $HOME: %s" % raw)
    # temp roots → AUTO
    # IMP-102: the /private/* entries are the macOS-RESOLVED forms of the three
    # temp roots (/tmp -> /private/tmp, /var/tmp -> /private/var/tmp,
    # /var/folders -> /private/var/folders, which is where $TMPDIR really lives).
    # The session scratchpad path handed to sub-agents is already resolved, so
    # without these a sub-agent deleting its OWN scratch dir hit "absolute
    # non-temp path" → ESCALATE. Listed as EXACT prefixes on purpose: /private
    # itself is NOT a temp root (/private/etc, /private/var/db are real system
    # state) and must never become auto-pass. The match below anchors on a path
    # boundary, so /private/tmpfoo does not slip through /private/tmp.
    TMP_PREFIXES = ("/tmp/", "/tmp", "/var/tmp", "/var/folders",
                    "/private/tmp", "/private/var/tmp", "/private/var/folders",
                    "$TMPDIR", "${TMPDIR}")
    for p in TMP_PREFIXES:
        if t == p or t.startswith(p.rstrip("/") + "/") or t == p.rstrip("/"):
            return None  # AUTO
    # glob AFTER the temp-root check (IMP-059): globs under /tmp already returned AUTO
    # above; only NON-temp globs reach here (can't reason about their expansion) → escalate.
    if "*" in t or "?" in t or "[" in t:
        return ("ESCALATE", "rm -rf (glob)", "recursive force-delete with a glob target: %s" % raw)
    # absolute non-temp path → escalate
    if t.startswith("/"):
        return ("ESCALATE", "rm -rf (absolute path)", "recursive force-delete of an absolute non-temp path: %s" % raw)
    # disposable basename anywhere (relative) → AUTO
    if base in DISPOSABLE_BASENAMES or base.endswith(".egg-info"):
        return None
    # relative path (./x or bare name, not ~) → AUTO per D4
    return None

# IMP-076: pre-gate on the DATA-STRIPPED command. An `rm` that exists only inside
# quoted data (grep -E 'a|rm -rf|b', echo "... rm -rf ...") creates a fake command
# position in the RAW string (the | inside quotes reads as a pipe) and must not be
# classified at all. Target extraction still runs on cmd_for_sig so quoted rm
# TARGETS ('foo bar') keep their real path for the allowlist check.
rm_verdict = classify_rm(cmd_for_sig) if cp_match(r"rm\b") else None
if rm_verdict is not None:
    emit(rm_verdict[0], rm_verdict[1], rm_verdict[2])

# ---- default: AUTO -----------------------------------------------------------
emit("AUTO", "", "")
PYEOF
) || VERDICT=$(printf 'AUTO\t\t\t')

BAND=$(printf '%s' "$VERDICT" | cut -f1)
OP=$(printf '%s' "$VERDICT" | cut -f2)
REASON=$(printf '%s' "$VERDICT" | cut -f3)
SIG=$(printf '%s' "$VERDICT" | cut -f4)

# D8: if the classifier somehow produced nothing, fail open.
if [ -z "$BAND" ]; then
  exit 0
fi

# AUTO → allow (the common case).
#
# IMP-113 (2026-08-01): allow-side decisions used to leave NO trace anywhere.
# excessive-agency.log held only ESCALATE/TESTMODE/ABSENT, so "no gate escapes
# occurred" was never a supported conclusion — the correct statement was
# "escapes are unobservable" (meta-proposal-2026-30 F-004, and the reason open
# IMP-106 could not be measured at all).
#
# SAMPLED, not complete: this hook fires on EVERY Bash call, and IMP-076/081
# already had to remove a python3 spawn because gate latency dominated at
# ~258ms. So we spend nothing on the 19-in-20 case: $RANDOM is a bash builtin
# (no subprocess), and `date`/`pwd` only run when the sample actually hits.
#
# Consumers MUST NOT read AUTO counts from this log as exhaustive — every
# record carries "sampled":1 and its rate so a reader can scale, or refuse to.
# Set CLAUDE_AGENCY_AUTO_SAMPLE=1 for full logging (debugging), 0 to disable.
if [ "$BAND" = "AUTO" ]; then
  _sample_rate="${CLAUDE_AGENCY_AUTO_SAMPLE:-20}"
  case "$_sample_rate" in
    ''|*[!0-9]*) _sample_rate=20 ;;   # non-numeric → fall back, never crash the gate
  esac
  if [ "$_sample_rate" -gt 0 ] 2>/dev/null && [ $(( RANDOM % _sample_rate )) -eq 0 ]; then
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    # The classifier emits an empty OP for AUTO (there is no named op to
    # report), which would make every sampled record read "unclassified" and
    # carry no signal. Log the COMMAND HEAD instead — the first bare token,
    # via builtin parameter expansion only (no subprocess on the hot path).
    # Head only: never the arguments, which routinely carry paths, tokens and
    # untrusted content that has no business in an audit log.
    _head="${COMMAND%%[$' \t\n']*}"
    _head="${_head##*/}"
    case "$_head" in *[!A-Za-z0-9._-]*|'') _head="other" ;; esac
    printf '{"ts":"%s","band":"AUTO","sampled":1,"sample_rate":%s,"cmd_head":"%s","sig":"%s","cwd":"%s"}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$_sample_rate" "$_head" "${SIG:-}" "$(pwd)" \
      >> "$LOG_FILE" 2>/dev/null || true
  fi
  exit 0
fi

# Everything below is ESCALATE.
mkdir -p "$LOG_DIR" 2>/dev/null || true
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
CWD=$(pwd)

# Session/consumed-token store key (D5)
# IMP-076: prefer the session_id from the hook JSON (stable across the whole
# session) over $PPID (process-topology dependent — a consumed token could be
# replayed from a sibling process if PPIDs differ between approve and re-run).
SESS="${HOOK_SESSION_ID:-${CLAUDE_SESSION_ID:-$PPID}}"
CONSUMED_FILE="/tmp/agency-ack-consumed-$SESS"

# ── D5: op-bound, single-use ack token ────────────────────────────────────────
# Recognized FROM the command string (like guard-unsafe's CLAUDE_GUARD_OVERRIDE),
# because the PreToolUse hook fires before any inline `export` would run.
PROVIDED_ACK=$(printf '%s' "$COMMAND" \
  | grep -oE 'CLAUDE_AGENCY_ACK_ONCE=[A-Fa-f0-9]{64}' \
  | head -1 | cut -d= -f2 || true)

if [ -n "$PROVIDED_ACK" ]; then
  if [ "$PROVIDED_ACK" = "$SIG" ]; then
    # op matches — single-use check
    if [ -f "$CONSUMED_FILE" ] && grep -qxF "$SIG" "$CONSUMED_FILE" 2>/dev/null; then
      printf '{"ts":"%s","op":"%s","band":"ESCALATE","token":"replay","sig":"%s","cwd":"%s","authorizer":"none"}\n' \
        "$TS" "$OP" "$SIG" "$CWD" >> "$LOG_FILE" 2>/dev/null || true
      {
        echo ""
        echo "AUTONOMY ARBITER — ack token already consumed (replay) for: $OP"
        echo "Each approval is single-use and op-bound. Re-ask the user before re-running."
      } >&2
      exit 2
    fi
    # accept once
    printf '%s\n' "$SIG" >> "$CONSUMED_FILE" 2>/dev/null || true
    printf '{"ts":"%s","op":"%s","band":"ESCALATE","token":"consumed","sig":"%s","cwd":"%s","authorizer":"user"}\n' \
      "$TS" "$OP" "$SIG" "$CWD" >> "$LOG_FILE" 2>/dev/null || true
    echo "NOTE: autonomy-arbiter ack token valid — allowing this single user-approved op ($OP), logged." >&2
    exit 0
  else
    # token present but op changed → re-block
    printf '{"ts":"%s","op":"%s","band":"ESCALATE","token":"ack-mismatch","sig":"%s","cwd":"%s","authorizer":"none"}\n' \
      "$TS" "$OP" "$SIG" "$CWD" >> "$LOG_FILE" 2>/dev/null || true
    {
      echo ""
      echo "AUTONOMY ARBITER — ack-token MISMATCH for: $OP"
      echo "The provided CLAUDE_AGENCY_ACK_ONCE does not match this command's signature."
      echo "Re-run with the exact token below (op-bound, single-use):"
      echo "  CLAUDE_AGENCY_ACK_ONCE=$SIG $COMMAND"
    } >&2
    exit 2
  fi
fi

# ── ESCALATE with no (valid) token → block + ask user ─────────────────────────
printf '{"ts":"%s","op":"%s","band":"ESCALATE","token":"none","sig":"%s","cwd":"%s","authorizer":"none"}\n' \
  "$TS" "$OP" "$SIG" "$CWD" >> "$LOG_FILE" 2>/dev/null || true

{
  echo ""
  echo "AUTONOMY ARBITER — ESCALATE (irreversible op, requires user y/n even in YOLO mode)"
  echo ""
  echo "  Op:      $OP"
  echo "  Reason:  $REASON"
  echo "  Command: $COMMAND"
  echo ""
  echo "Per ~/.claude/rules/autonomy-arbiter.md: surface this to the user VERBATIM and ask y/n."
  echo "Do NOT route around it with a different tool/language."
  echo ""
  echo "After the user approves, re-run EXACTLY (op-bound, single-use, logged):"
  echo "  CLAUDE_AGENCY_ACK_ONCE=$SIG $COMMAND"
} >&2

exit 2
