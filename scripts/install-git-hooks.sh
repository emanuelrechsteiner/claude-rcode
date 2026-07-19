#!/usr/bin/env bash
# install-git-hooks.sh — wire scripts/scrub-check.sh into this repo's local
# git hooks (pre-push layer of the release gate; see .github/workflows for
# the CI layer). Run once after cloning:
#
#   bash scripts/install-git-hooks.sh
#
# Idempotent when re-run against a hook this script installed: overwrites
# it with the current template version, no backup needed (it's already
# our own generated content). If a pre-push hook exists that this script
# did NOT install (no marker comment — e.g. a hook from another tool, or
# hand-written), the script ABORTS rather than clobbering it silently. Use:
#
#   bash scripts/install-git-hooks.sh --force
#
# to intentionally replace a foreign hook — this backs up the foreign hook
# to a numbered file first, then installs.
#
# Safe to run from any subdirectory of the repo.
set -euo pipefail

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ]; then
  echo "install-git-hooks: not inside a git repository — aborting" >&2
  exit 1
fi
cd "$REPO_ROOT"

HOOKS_DIR="$(git rev-parse --git-path hooks)"
mkdir -p "$HOOKS_DIR"

PRE_PUSH="$HOOKS_DIR/pre-push"

# Marker string embedded in every hook this script generates (see the
# heredoc below). Used to tell "a hook we installed, safe to overwrite"
# apart from "a foreign hook, do not touch without --force".
HOOK_MARKER="Installed by scripts/install-git-hooks.sh"

if [ -f "$PRE_PUSH" ] && ! grep -qF "$HOOK_MARKER" "$PRE_PUSH" 2>/dev/null; then
  if [ "$FORCE" -ne 1 ]; then
    echo "install-git-hooks: an existing pre-push hook at $PRE_PUSH was NOT" >&2
    echo "  installed by this script (no marker comment found) — aborting to" >&2
    echo "  avoid silently overwriting it." >&2
    echo "" >&2
    echo "  Re-run with --force to replace it (a numbered backup of the" >&2
    echo "  existing hook is written first): bash scripts/install-git-hooks.sh --force" >&2
    exit 1
  fi

  # --force: back up the foreign hook under a numbered, non-colliding
  # filename before overwriting it.
  n=1
  backup="$PRE_PUSH.foreign-backup.$n"
  while [ -e "$backup" ]; do
    n=$((n + 1))
    backup="$PRE_PUSH.foreign-backup.$n"
  done
  cp "$PRE_PUSH" "$backup"
  echo "install-git-hooks: --force given — existing foreign pre-push hook backed up to $backup"
fi

cat > "$PRE_PUSH" <<HOOK
#!/usr/bin/env bash
# ${HOOK_MARKER} — do not edit by hand, re-run
# that script to update. Blocks the push if scripts/scrub-check.sh finds a
# secret, personal-data fragment, or pre-rebrand name leftover.
set -euo pipefail
REPO_ROOT="\$(git rev-parse --show-toplevel)"
if [ -x "\$REPO_ROOT/scripts/scrub-check.sh" ]; then
  "\$REPO_ROOT/scripts/scrub-check.sh" || {
    echo "" >&2
    echo "pre-push: BLOCKED by scripts/scrub-check.sh — fix the findings above, or" >&2
    echo "  add a reviewed exemption to scripts/scrub-allowlist.txt, then push again." >&2
    exit 1
  }
else
  # Fail CLOSED: a missing or non-executable scrub-check.sh must not let a
  # push run unchecked. If you genuinely need to push without the gate
  # (e.g. scrub-check.sh itself is mid-repair), that is a conscious manual
  # decision — make it explicitly with:
  #   git push --no-verify
  # rather than have this hook silently wave the push through.
  echo "pre-push: BLOCKED — scripts/scrub-check.sh not found or not executable." >&2
  echo "  Restore it, or if you deliberately want to skip the scrub gate for" >&2
  echo "  this push, say so explicitly: git push --no-verify" >&2
  exit 1
fi
HOOK

chmod +x "$PRE_PUSH"
echo "install-git-hooks: pre-push hook installed at $PRE_PUSH"
echo "install-git-hooks: every 'git push' from this clone now runs scripts/scrub-check.sh first"
