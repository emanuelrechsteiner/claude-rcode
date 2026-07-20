#!/usr/bin/env bash
# Claude R.Code — install.sh
# One-command install for the Claude R.Code configuration framework.
#
#   git clone https://github.com/emanuelrechsteiner/claude-rcode.git && cd claude-rcode && ./install.sh
#   bash <(curl -fsSL https://raw.githubusercontent.com/emanuelrechsteiner/claude-rcode/main/install.sh)
#
# Windows users: use install.ps1 (minimal fresh/overwrite; hooks need WSL/Git Bash).
#
# Three modes (see --help):
#   fresh      no/empty ~/.claude          → clone/copy the framework into place
#   overwrite  existing ~/.claude, replace → full backup, then fresh
#   augment    existing ~/.claude, merge   → scan, report, per-category y/n merge
#
# install.sh never touches your Claude Code credentials. Login (Pro/Max
# OAuth or API key) happens inside Claude Code itself on first launch.
set -euo pipefail

# ---------------------------------------------------------------------------
# Constants & argument parsing
# ---------------------------------------------------------------------------
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
REPO_URL="https://github.com/emanuelrechsteiner/claude-rcode.git"

MODE="auto"
ASSUME_YES=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Claude R.Code — install.sh

Usage:
  install.sh [--mode auto|fresh|overwrite|augment] [--yes] [--dry-run]
  install.sh --fresh|--overwrite|--augment [--yes] [--dry-run]
  install.sh --help

Modes:
  auto (default)  Detect the right mode automatically:
                    - no/empty ~/.claude              -> fresh
                    - ~/.claude already tracks this repo -> self-update (git pull)
                    - ~/.claude has unrelated content  -> ask overwrite/augment/abort

  fresh           Install into a missing or empty ~/.claude. Clones (or, if
                  run from inside an existing clone of this repo, copies in
                  place) the framework, then creates *.local.* overlay files
                  from templates/*.template where they don't already exist.
                  If ~/.claude already exists AND is non-empty (e.g. running
                  --fresh a second time), it is moved to a timestamped
                  backup first — same mechanism as --overwrite, nothing is
                  deleted — so a repeat run never crashes. Asks for
                  confirmation first (default: yes) unless --yes is given,
                  same as --overwrite.

  overwrite       Back up the ENTIRE existing ~/.claude to
                  ~/.claude.backup-<unix-timestamp> (nothing is deleted),
                  then run the fresh flow. Asks for confirmation first
                  unless --yes is given.

  augment         Scan your existing ~/.claude, classify every R.Code unit
                  (rule/hook/skill/agent/command) as NEW, IDENTICAL, or
                  CONFLICT against what you already have, print a report
                  with a recommendation, then merge selectively:
                    - rules/*.md, hooks/*.sh       : per-file, conflicts ask
                      (default: keep yours)
                    - skills/*, agents/*.md,
                      commands/*.md                : per-unit (whole dir or
                      file), conflicts ask (default: keep yours)
                    - templates/, rcode/, scripts/  : NEW only, never
                      touches an existing file
                    - settings.json                 : NEVER replaced whole —
                      only hook registrations are merged in (jq); your env/
                      permissions/model stay untouched
                  Conflict prompts accept: y (replace this one), n/Enter
                  (keep yours), a (replace ALL remaining), k (keep ALL
                  remaining), d (show diff, re-ask), q (abort merge).
                  Use --dry-run to print the report without changing anything.

Flags:
  --yes           Non-interactive: accept every default/recommended action.
                  Required for unattended/CI use of overwrite and augment.
  --dry-run       augment only: print the scan report, change nothing.
  --help          Show this help and exit.

Environment:
  CLAUDE_DIR      Target directory (default: $HOME/.claude).
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)
      MODE="${2:-}"; shift 2 ;;
    --mode=*)
      MODE="${1#--mode=}"; shift ;;
    --fresh) MODE="fresh"; shift ;;
    --overwrite) MODE="overwrite"; shift ;;
    --augment) MODE="augment"; shift ;;
    --auto) MODE="auto"; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      echo "install.sh: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$MODE" in
  auto|fresh|overwrite|augment) ;;
  *)
    echo "install.sh: invalid --mode '$MODE' (expected auto|fresh|overwrite|augment)" >&2
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "$*"; }
warn() { echo "install.sh: $*" >&2; }
die()  { echo "install.sh: ERROR: $*" >&2; exit 1; }

confirm() {
  # confirm "prompt text" [default-y|default-n]  -> returns 0 for yes
  # Under --yes this returns the DEFAULT, not an unconditional yes: --yes
  # means "accept every default/recommended action" (see --help), and for
  # conflict prompts the documented default is "keep yours" (default-n).
  local prompt="$1" default="${2:-default-n}"
  if [ "$ASSUME_YES" -eq 1 ]; then
    if [ "$default" = "default-y" ]; then
      log "  -> --yes: auto-confirming (default): $prompt"
      return 0
    else
      log "  -> --yes: auto-declining (default): $prompt"
      return 1
    fi
  fi
  local hint="y/N"
  [ "$default" = "default-y" ] && hint="Y/n"
  local reply
  read -r -p "$prompt [$hint] " reply < /dev/tty || reply=""
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    n|N|no|NO) return 1 ;;
    "")
      [ "$default" = "default-y" ] && return 0 || return 1
      ;;
    *) return 1 ;;
  esac
}

# Sticky answer for conflict prompts: "" (ask each), "all" (replace all
# remaining), "keep" (keep yours for all remaining). Set by confirm_conflict
# when the user answers a/k; reset at the start of every merge_augment run.
AUG_STICKY=""

confirm_conflict() {
  # confirm_conflict "unit label" "repo path" "local path" -> 0 = replace
  #
  # Interactive conflict prompt with bulk answers (git add -p style):
  #   y = replace this one          n/Enter = keep yours (default)
  #   a = replace ALL remaining     k = keep yours for ALL remaining
  #   d = show diff, then re-ask    q = abort the merge here
  # Under --yes this behaves exactly like confirm default-n (keep yours) —
  # the documented "--yes accepts the default" semantics are unchanged.
  local label="$1" src="$2" dst="$3"
  case "$AUG_STICKY" in
    all)  log "  -> a (all): replacing $label"; return 0 ;;
    keep) log "  -> k (all): keeping yours: $label"; return 1 ;;
  esac
  if [ "$ASSUME_YES" -eq 1 ]; then
    log "  -> --yes: auto-declining (default keep yours): $label"
    return 1
  fi
  local reply
  while :; do
    read -r -p "$label differs from yours — replace with R.Code's version? [y/n/a/k/d/q] (default: keep yours) " reply < /dev/tty || reply=""
    case "$reply" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO|"") return 1 ;;
      a|A) AUG_STICKY="all";  return 0 ;;
      k|K) AUG_STICKY="keep"; return 1 ;;
      d|D)
        log "--- diff: yours (-) vs R.Code (+) — $label ---"
        if [ -d "$src" ]; then diff -ru "$dst" "$src" || true
        else diff -u "$dst" "$src" || true; fi
        log "--- end diff ---"
        ;;
      q|Q)
        warn "merge aborted by user at $label — units merged so far are kept, the rest is untouched. Re-run --augment to continue."
        exit 1
        ;;
      *) log "  (y = replace, n = keep yours, a = replace all, k = keep all, d = diff, q = quit)" ;;
    esac
  done
}

unique_backup_path() {
  # Build a timestamped backup path that's guaranteed not to collide even
  # when two runs land in the same second (date +%s has 1s granularity).
  # epoch + PID first; if that somehow still collides (e.g. PID reuse across
  # two runs in the same second), fall back to an incrementing counter so
  # the old backup is never nested inside/overwritten by the new one.
  local base="$1" candidate suffix n
  suffix="$(date +%s)-$$"
  candidate="${base}.backup-${suffix}"
  if [ ! -e "$candidate" ]; then
    echo "$candidate"
    return 0
  fi
  n=1
  while [ -e "${candidate}-${n}" ]; do
    n=$((n + 1))
  done
  echo "${candidate}-${n}"
}

sha256_of() {
  # Portable sha256 of a single file.
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    die "neither shasum nor sha256sum found — required for augment mode"
  fi
}

dirhash_of() {
  # Order-independent content hash of a directory tree (for whole-unit
  # comparison of skills/*, which are directories). Deliberately avoids
  # exporting a bash function into a subshell (xargs sh -c) — dash doesn't
  # support function export, so that pattern silently breaks on Debian/
  # Ubuntu where /bin/sh is dash, not bash.
  #
  # `cd`s into $dir first so every per-file digest line carries a RELATIVE
  # path (./foo/bar.sh). Hashing raw absolute paths made two identical
  # trees at different locations (repo checkout vs. $CLAUDE_DIR) always
  # digest differently, which reported every skill as CONFLICT on every
  # re-run even when the content was byte-identical.
  local dir="$1" f digest_cmd
  if command -v shasum >/dev/null 2>&1; then
    digest_cmd="shasum -a 256"
  elif command -v sha256sum >/dev/null 2>&1; then
    digest_cmd="sha256sum"
  else
    die "neither shasum nor sha256sum found — required for augment mode"
  fi
  (
    cd "$dir" 2>/dev/null && find . -type f 2>/dev/null | sort | while IFS= read -r f; do
      $digest_cmd "$f"
    done
  ) | $digest_cmd | awk '{print $1}'
}

print_oauth_notice() {
  cat <<'EOF'

Setup complete. Start Claude Code with:  claude
On first launch, Claude Code runs its OWN login flow — choose either:
  • Pro/Max subscription  → browser OAuth (claude.ai)
  • Anthropic API key      → paste when prompted, or export ANTHROPIC_API_KEY
R.Code never stores or reads your credentials.
EOF
}

copy_templates() {
  # Copy the 4 DOCUMENTED *.local.* overlay templates -> overlay files,
  # only if missing. (identity.local.md is special-cased into rules/.)
  #
  # Deliberately a whitelist, NOT a `templates/*.template` glob: that
  # directory also holds command-contract.template (a reference snippet
  # library per its own header, not a user overlay) and
  # serena_config.yml.template (a machine-specific config template with
  # its own opt-in flow) — neither should ever be silently materialized
  # into a fresh ~/.claude.
  local templates_dir="$1" target_dir="$2"
  [ -d "$templates_dir" ] || return 0
  log ""
  log "Setting up local overlays..."
  local overlays="CLAUDE.local.md MEMORY_FIRST.local.md identity.local.md settings.local.json"
  local basename_tmpl tmpl target
  for basename_tmpl in $overlays; do
    tmpl="$templates_dir/$basename_tmpl.template"
    [ -f "$tmpl" ] || continue
    target="$target_dir/$basename_tmpl"
    case "$basename_tmpl" in
      identity.local.md) target="$target_dir/rules/$basename_tmpl" ;;
    esac
    if [ ! -f "$target" ]; then
      mkdir -p "$(dirname "$target")"
      cp "$tmpl" "$target"
      log "  Created $target"
    else
      log "  Skipped $target (already exists)"
    fi
  done
}

ensure_executable() {
  local dir="$1"
  [ -d "$dir/hooks" ] && chmod +x "$dir"/hooks/*.sh 2>/dev/null || true
  [ -d "$dir/scripts" ] && chmod +x "$dir"/scripts/*.sh 2>/dev/null || true
}

# Resolve this script's own repo root, if it's running from inside a git
# clone of the framework (either the target ~/.claude itself, or a separate
# source checkout — e.g. this exact build tree, or a sandbox test harness).
resolve_repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || return 1
  if [ -n "$script_dir" ] && [ -d "$script_dir/.git" ]; then
    echo "$script_dir"
    return 0
  fi
  return 1
}

# Materialize a git-backed copy of the framework AT $CLAUDE_DIR, handling
# three cases: (a) the script is already running in place inside
# $CLAUDE_DIR (user cloned straight into ~/.claude and ran ./install.sh) —
# nothing to copy; (b) a local source checkout exists elsewhere (e.g. a dev
# build, or this repo used to install onto a sandbox HOME) — clone locally,
# then repoint origin at the public URL; (c) neither — clone from REPO_URL
# (the remote curl-pipe one-liner path).
materialize_repo_at_claude_dir() {
  local repo_root
  repo_root="$(resolve_repo_root || true)"

  if [ -n "$repo_root" ] && [ "$repo_root" = "$CLAUDE_DIR" ]; then
    log "Running from inside an existing clone at $repo_root — installing in place"
    return 0
  fi

  # `git clone` refuses to clone into a non-empty directory (exit 128). A
  # prior --fresh run (or a manual clone/copy) can leave $CLAUDE_DIR
  # populated, so a second --fresh run would otherwise crash here. Same
  # semantics as --overwrite: move the existing dir to a timestamped
  # backup first — nothing is deleted — so re-running --fresh is
  # idempotent instead of a fatal error. Consistency with --overwrite also
  # means: ask for confirmation first (default: yes) unless --yes is given —
  # do_overwrite() asks before backing up an existing config, so this path
  # (fresh-on-nonempty, reached e.g. by running --fresh a second time) must
  # not silently skip that same confirmation.
  if [ -e "$CLAUDE_DIR" ] && ! is_empty_dir "$CLAUDE_DIR"; then
    if ! confirm "$CLAUDE_DIR already exists and is not empty — this will move it to a timestamped backup (nothing is deleted), then install fresh. Proceed?" "default-y"; then
      die "aborted by user"
    fi
    local backup
    backup="$(unique_backup_path "$CLAUDE_DIR")"
    warn "$CLAUDE_DIR already exists and is not empty — moving it to $backup before cloning fresh (nothing is deleted; same mechanism as --overwrite)"
    mv "$CLAUDE_DIR" "$backup"
  fi

  mkdir -p "$(dirname "$CLAUDE_DIR")"
  if [ -n "$repo_root" ]; then
    log "Cloning local source $repo_root -> $CLAUDE_DIR"
    git clone -q "$repo_root" "$CLAUDE_DIR"
    # Track the public repo, not the local path, for future self-updates.
    git -C "$CLAUDE_DIR" remote set-url origin "$REPO_URL" 2>/dev/null || true
  else
    log "Cloning $REPO_URL -> $CLAUDE_DIR"
    git clone -q "$REPO_URL" "$CLAUDE_DIR"
  fi
}

# ---------------------------------------------------------------------------
# Mode: fresh
# ---------------------------------------------------------------------------
do_fresh() {
  log "Claude R.Code — fresh install"
  log "Target: $CLAUDE_DIR"
  log ""

  materialize_repo_at_claude_dir
  copy_templates "$CLAUDE_DIR/templates" "$CLAUDE_DIR"
  ensure_executable "$CLAUDE_DIR"

  log ""
  log "settings.framework.json check..."
  if [ -f "$CLAUDE_DIR/settings.framework.json" ]; then
    warn "found stale settings.framework.json — removing (superseded by the single settings.json, D1)"
    rm -f "$CLAUDE_DIR/settings.framework.json"
  fi

  if command -v jq >/dev/null 2>&1 && [ -f "$CLAUDE_DIR/settings.json" ]; then
    jq . "$CLAUDE_DIR/settings.json" >/dev/null 2>&1 || warn "settings.json did not validate as JSON — please inspect it"
  fi

  log ""
  log "Claude R.Code installed at $CLAUDE_DIR"
  print_oauth_notice
}

# ---------------------------------------------------------------------------
# Mode: overwrite
# ---------------------------------------------------------------------------
do_overwrite() {
  log "Claude R.Code — overwrite install"
  log "Target: $CLAUDE_DIR"
  log ""

  if [ -e "$CLAUDE_DIR" ]; then
    if ! confirm "This will move the existing $CLAUDE_DIR to a timestamped backup (nothing is deleted), then install fresh. Proceed?" "default-y"; then
      die "aborted by user"
    fi
    local backup
    backup="$(unique_backup_path "$CLAUDE_DIR")"
    mv "$CLAUDE_DIR" "$backup"
    log "Previous config backed up to $backup"
  fi

  do_fresh
}

# ---------------------------------------------------------------------------
# Mode: augment — scan, classify, recommend, selective merge
# ---------------------------------------------------------------------------

# Populated by scan_augment(); consumed by print_recommendation() and
# merge_augment().
AUG_NEW_RULES=(); AUG_CONFLICT_RULES=(); AUG_IDENTICAL_RULES=0
AUG_NEW_HOOKS=(); AUG_CONFLICT_HOOKS=(); AUG_IDENTICAL_HOOKS=0
AUG_NEW_UNITS=(); AUG_CONFLICT_UNITS=(); AUG_IDENTICAL_UNITS=0
AUG_TOTAL_RCODE_UNITS=0

scan_augment() {
  local repo_root
  repo_root="$(resolve_repo_root || true)"
  [ -n "$repo_root" ] || die "augment mode requires running from inside a clone of this repo"
  [ -d "$CLAUDE_DIR" ] || die "augment mode requires an existing $CLAUDE_DIR to scan"

  # Reset accumulators — scan_augment can legitimately be called more than
  # once per run (e.g. do_auto scans to build a recommendation, then calls
  # do_augment which scans again); without this reset, results would double
  # up on every re-scan.
  AUG_NEW_RULES=(); AUG_CONFLICT_RULES=(); AUG_IDENTICAL_RULES=0
  AUG_NEW_HOOKS=(); AUG_CONFLICT_HOOKS=(); AUG_IDENTICAL_HOOKS=0
  AUG_NEW_UNITS=(); AUG_CONFLICT_UNITS=(); AUG_IDENTICAL_UNITS=0
  AUG_TOTAL_RCODE_UNITS=0

  log "Scanning existing config at $CLAUDE_DIR against $repo_root ..."
  log ""

  # --- rules/*.md (per-file) ---
  local f base target
  if [ -d "$repo_root/rules" ]; then
    for f in "$repo_root"/rules/*.md; do
      [ -f "$f" ] || continue
      base="$(basename "$f")"
      target="$CLAUDE_DIR/rules/$base"
      AUG_TOTAL_RCODE_UNITS=$((AUG_TOTAL_RCODE_UNITS + 1))
      if [ ! -f "$target" ]; then
        AUG_NEW_RULES+=("$base")
      elif [ "$(sha256_of "$f")" = "$(sha256_of "$target")" ]; then
        AUG_IDENTICAL_RULES=$((AUG_IDENTICAL_RULES + 1))
      else
        AUG_CONFLICT_RULES+=("$base")
      fi
    done
  fi

  # --- hooks/*.sh (per-file) ---
  if [ -d "$repo_root/hooks" ]; then
    for f in "$repo_root"/hooks/*.sh; do
      [ -f "$f" ] || continue
      base="$(basename "$f")"
      target="$CLAUDE_DIR/hooks/$base"
      AUG_TOTAL_RCODE_UNITS=$((AUG_TOTAL_RCODE_UNITS + 1))
      if [ ! -f "$target" ]; then
        AUG_NEW_HOOKS+=("$base")
      elif [ "$(sha256_of "$f")" = "$(sha256_of "$target")" ]; then
        AUG_IDENTICAL_HOOKS=$((AUG_IDENTICAL_HOOKS + 1))
      else
        AUG_CONFLICT_HOOKS+=("$base")
      fi
    done
  fi

  # --- skills/* (whole-directory unit), agents/*.md, commands/*.md (file unit) ---
  local d
  if [ -d "$repo_root/skills" ]; then
    for d in "$repo_root"/skills/*/; do
      [ -d "$d" ] || continue
      base="skills/$(basename "$d")"
      target="$CLAUDE_DIR/$base"
      AUG_TOTAL_RCODE_UNITS=$((AUG_TOTAL_RCODE_UNITS + 1))
      if [ ! -d "$target" ]; then
        AUG_NEW_UNITS+=("$base")
      elif [ "$(dirhash_of "$d")" = "$(dirhash_of "$target")" ]; then
        AUG_IDENTICAL_UNITS=$((AUG_IDENTICAL_UNITS + 1))
      else
        AUG_CONFLICT_UNITS+=("$base")
      fi
    done
  fi
  for kind in agents commands; do
    [ -d "$repo_root/$kind" ] || continue
    for f in "$repo_root/$kind"/*.md; do
      [ -f "$f" ] || continue
      base="$kind/$(basename "$f")"
      target="$CLAUDE_DIR/$base"
      AUG_TOTAL_RCODE_UNITS=$((AUG_TOTAL_RCODE_UNITS + 1))
      if [ ! -f "$target" ]; then
        AUG_NEW_UNITS+=("$base")
      elif [ "$(sha256_of "$f")" = "$(sha256_of "$target")" ]; then
        AUG_IDENTICAL_UNITS=$((AUG_IDENTICAL_UNITS + 1))
      else
        AUG_CONFLICT_UNITS+=("$base")
      fi
    done
  done
}

# Sets the global AUG_RECOMMENDATION ("augment"|"abort") as a side effect
# and prints the human-readable report + recommendation to the terminal.
# Deliberately NOT called via `$(...)` command substitution anywhere — that
# would silently swallow every `log` line above and only surface the last
# one, hiding the report from the user. Call it as a plain statement, then
# read $AUG_RECOMMENDATION.
AUG_RECOMMENDATION=""
recommend_augment() {
  local total_new=$(( ${#AUG_NEW_RULES[@]} + ${#AUG_NEW_HOOKS[@]} + ${#AUG_NEW_UNITS[@]} ))
  local total_conflict=$(( ${#AUG_CONFLICT_RULES[@]} + ${#AUG_CONFLICT_HOOKS[@]} + ${#AUG_CONFLICT_UNITS[@]} ))
  local total=$AUG_TOTAL_RCODE_UNITS
  [ "$total" -eq 0 ] && total=1

  local has_existing_rules_hooks=1
  if [ ! -d "$CLAUDE_DIR/rules" ] && [ ! -d "$CLAUDE_DIR/hooks" ]; then
    has_existing_rules_hooks=0
  fi

  log "Report: $total_new new, $total_conflict conflicting, $((total - total_new - total_conflict)) identical (of $total R.Code units)"

  # List the conflicting units so a "conflict pass" can be planned without
  # re-deriving the list by hand (previously only the counts were printed).
  if [ "$total_conflict" -gt 0 ]; then
    log ""
    log "Conflicting units (yours differs from R.Code's):"
    local c
    for c in "${AUG_CONFLICT_RULES[@]:-}"; do [ -n "$c" ] && log "  rules/$c"; done
    for c in "${AUG_CONFLICT_HOOKS[@]:-}"; do [ -n "$c" ] && log "  hooks/$c"; done
    for c in "${AUG_CONFLICT_UNITS[@]:-}"; do [ -n "$c" ] && log "  $c"; done
  fi
  log ""

  if [ "$has_existing_rules_hooks" -eq 0 ]; then
    log "Recommendation: OVERWRITE / FULL AUGMENT"
    log "  Your config has no rules/ or hooks/ at all — it's minimal. R.Code adds"
    log "  substantial value here; overwriting or fully augmenting is recommended."
    AUG_RECOMMENDATION="augment"
    return
  fi

  # novelty = NEW / total ; conflict_rate = CONFLICT / total
  local novelty_pct=$(( total_new * 100 / total ))
  local conflict_pct=$(( total_conflict * 100 / total ))

  if [ "$novelty_pct" -ge 50 ] && [ "$conflict_pct" -le 20 ]; then
    log "Recommendation: AUGMENT"
    log "  R.Code adds $total_new new units with only $total_conflict conflicts ($novelty_pct% novelty, $conflict_pct% conflict rate)."
    AUG_RECOMMENDATION="augment"
  elif [ "$novelty_pct" -lt 15 ]; then
    log "Recommendation: DO NOT AUGMENT (abort)"
    log "  Your config already covers most of what R.Code offers ($novelty_pct% novelty) —"
    log "  R.Code would add little value here."
    AUG_RECOMMENDATION="abort"
  else
    log "Recommendation: AUGMENT (with a conflict pass)"
    log "  $total_new new units, $total_conflict conflicts to review individually."
    AUG_RECOMMENDATION="augment"
  fi
}

merge_settings_hooks() {
  local repo_root="$1"
  local target="$CLAUDE_DIR/settings.json"
  command -v jq >/dev/null 2>&1 || { warn "jq not found — skipping settings.json hook merge"; return 0; }
  [ -f "$target" ] || { cp "$repo_root/settings.json" "$target"; log "  Created $target"; return 0; }
  [ -f "$repo_root/settings.json" ] || return 0

  cp "$target" "$target.bak-$(date +%s)"
  local merged
  merged=$(jq -s '
    .[0] as $user | .[1] as $rcode |
    $user * { hooks: (
      reduce ($rcode.hooks | keys[]) as $ev ($user.hooks // {};
        .[$ev] = ((.[$ev] // []) + [ $rcode.hooks[$ev][] ]
          | unique_by(.hooks[0].command // (.matcher + (.hooks|tostring))) ))) }
  ' "$target" "$repo_root/settings.json") || { warn "jq merge failed — leaving settings.json untouched"; return 1; }

  echo "$merged" > "$target.new"
  if jq . "$target.new" >/dev/null 2>&1; then
    mv "$target.new" "$target"
    log "  Merged R.Code hook registrations into settings.json (your env/permissions/model preserved; backup at $target.bak-*)"
  else
    warn "merged settings.json failed to validate — leaving original untouched"
    rm -f "$target.new"
  fi
}

merge_augment() {
  local repo_root
  repo_root="$(resolve_repo_root)"

  log ""
  log "Merging..."
  AUG_STICKY=""

  # rules/*.md — per file, conflicts ask (default keep-yours)
  local base
  for base in "${AUG_NEW_RULES[@]:-}"; do
    [ -z "$base" ] && continue
    mkdir -p "$CLAUDE_DIR/rules"
    cp "$repo_root/rules/$base" "$CLAUDE_DIR/rules/$base"
    log "  + rules/$base (new)"
  done
  for base in "${AUG_CONFLICT_RULES[@]:-}"; do
    [ -z "$base" ] && continue
    if confirm_conflict "rules/$base" "$repo_root/rules/$base" "$CLAUDE_DIR/rules/$base"; then
      cp "$repo_root/rules/$base" "$CLAUDE_DIR/rules/$base"
      log "  ~ rules/$base (replaced)"
    else
      log "  = rules/$base (kept yours)"
    fi
  done

  # hooks/*.sh — per file, conflicts ask (default keep-yours) + chmod +x
  for base in "${AUG_NEW_HOOKS[@]:-}"; do
    [ -z "$base" ] && continue
    mkdir -p "$CLAUDE_DIR/hooks"
    cp "$repo_root/hooks/$base" "$CLAUDE_DIR/hooks/$base"
    chmod +x "$CLAUDE_DIR/hooks/$base"
    log "  + hooks/$base (new)"
  done
  for base in "${AUG_CONFLICT_HOOKS[@]:-}"; do
    [ -z "$base" ] && continue
    if confirm_conflict "hooks/$base" "$repo_root/hooks/$base" "$CLAUDE_DIR/hooks/$base"; then
      cp "$repo_root/hooks/$base" "$CLAUDE_DIR/hooks/$base"
      chmod +x "$CLAUDE_DIR/hooks/$base"
      log "  ~ hooks/$base (replaced)"
    else
      log "  = hooks/$base (kept yours)"
    fi
  done

  # skills/*, agents/*.md, commands/*.md — atomic unit, conflicts ask
  for base in "${AUG_NEW_UNITS[@]:-}"; do
    [ -z "$base" ] && continue
    mkdir -p "$CLAUDE_DIR/$(dirname "$base")"
    rm -rf "${CLAUDE_DIR:?}/$base"
    cp -R "$repo_root/$base" "$CLAUDE_DIR/$base"
    log "  + $base (new)"
  done
  for base in "${AUG_CONFLICT_UNITS[@]:-}"; do
    [ -z "$base" ] && continue
    if confirm_conflict "$base" "$repo_root/$base" "$CLAUDE_DIR/$base"; then
      rm -rf "${CLAUDE_DIR:?}/$base"
      cp -R "$repo_root/$base" "$CLAUDE_DIR/$base"
      log "  ~ $base (replaced)"
    else
      log "  = $base (kept yours)"
    fi
  done

  # templates/, rcode/, scripts/ — NEW only, never touch existing
  local top item name
  for top in templates rcode scripts; do
    [ -d "$repo_root/$top" ] || continue
    for item in "$repo_root/$top"/*; do
      [ -e "$item" ] || continue
      name="$(basename "$item")"
      if [ ! -e "$CLAUDE_DIR/$top/$name" ]; then
        mkdir -p "$CLAUDE_DIR/$top"
        cp -R "$item" "$CLAUDE_DIR/$top/$name"
        log "  + $top/$name (new)"
      fi
    done
  done
  ensure_executable "$CLAUDE_DIR"

  # settings.json — hook-registration merge only, never a full overwrite
  merge_settings_hooks "$repo_root"
}

do_augment() {
  log "Claude R.Code — augment install"
  log "Target: $CLAUDE_DIR"
  log ""

  scan_augment
  recommend_augment
  local recommendation="$AUG_RECOMMENDATION"

  if [ "$DRY_RUN" -eq 1 ]; then
    log ""
    log "--dry-run: no changes made."
    return 0
  fi

  if [ "$recommendation" = "abort" ]; then
    # --yes means "accept the RECOMMENDED action" (see --help) — when the
    # recommendation is abort, --yes must abort too, matching do_auto()'s
    # --yes handling. Only the interactive path lets the user consciously
    # override the recommendation via the confirm() prompt below.
    if [ "$ASSUME_YES" -eq 1 ]; then
      log ""
      log "--yes: following recommendation (abort) — no changes made."
      return 0
    fi
    if ! confirm "Recommendation was to skip augmenting — continue anyway?"; then
      log "Aborted — no changes made."
      return 0
    fi
  fi

  merge_augment
  log ""
  log "Augment complete."
  print_oauth_notice
}

# ---------------------------------------------------------------------------
# Mode: auto — detect the right mode
# ---------------------------------------------------------------------------
is_empty_dir() {
  # Empty (or nonexistent) path -> true (0). A path that EXISTS but is not a
  # directory (e.g. CLAUDE_DIR pointing at a regular file) is a distinct
  # error condition, not "empty" — die with a clear message rather than
  # silently treating it as empty. Silently treating it as empty used to
  # skip the backup-before-clone safeguard in materialize_repo_at_claude_dir
  # and let a bare `git clone` fail later with a confusing low-level error.
  [ -e "$1" ] || return 0
  [ -d "$1" ] || die "$1 exists but is not a directory — refusing to continue. Remove or rename it, or set CLAUDE_DIR to a different path."
  [ -z "$(ls -A "$1" 2>/dev/null)" ]
}

do_auto() {
  if [ ! -e "$CLAUDE_DIR" ] || is_empty_dir "$CLAUDE_DIR"; then
    log "auto: no/empty $CLAUDE_DIR -> fresh install"
    do_fresh
    return
  fi

  if [ -d "$CLAUDE_DIR/.git" ]; then
    local remote
    remote="$(git -C "$CLAUDE_DIR" remote get-url origin 2>/dev/null || true)"
    if [ "$remote" = "$REPO_URL" ] || [ "${remote%.git}" = "${REPO_URL%.git}" ]; then
      log "auto: $CLAUDE_DIR already tracks this repo -> self-update"
      git -C "$CLAUDE_DIR" pull --ff-only
      copy_templates "$CLAUDE_DIR/templates" "$CLAUDE_DIR"
      ensure_executable "$CLAUDE_DIR"
      log "Updated $CLAUDE_DIR"
      return
    fi
  fi

  log "auto: $CLAUDE_DIR exists with unrelated content."
  log ""
  scan_augment
  recommend_augment
  local recommendation="$AUG_RECOMMENDATION"
  log ""

  if [ "$ASSUME_YES" -eq 1 ]; then
    log "auto --yes: following recommendation ($recommendation)"
    [ "$recommendation" = "abort" ] && { log "Aborted — no changes made."; return 0; }
    do_augment
    return
  fi

  local choice
  read -r -p "Recommendation: $recommendation. Choose [o]verwrite / [a]ugment / [q]uit: " choice < /dev/tty || choice=""
  case "$choice" in
    o|O) do_overwrite ;;
    a|A) do_augment ;;
    *) log "Aborted — no changes made." ;;
  esac
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
case "$MODE" in
  auto) do_auto ;;
  fresh) do_fresh ;;
  overwrite) do_overwrite ;;
  augment) do_augment ;;
esac
