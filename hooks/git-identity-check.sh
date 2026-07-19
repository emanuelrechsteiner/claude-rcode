#!/bin/bash
# SessionStart hook — verifies git identity does not leak across projects.
#
# Background: If you operate under multiple git identities (work vs.
# personal, client A vs. client B), commits under the wrong identity have
# real cost — retroactive author-rewrites are history-invasive and hard to
# clean up. This hook warns at session start; it never blocks.
#
# Behavior:
#   - Reads personal identity mappings from ~/.claude/rules/identity.local.md
#     if present (gitignored, see templates/identity.local.md.template).
#   - If you don't have multiple identities, omit the .local.md file → no-op.
#   - When the file is missing, this hook also recognizes two legacy
#     identity placeholders (WORK_IDENTITY / PERSONAL_IDENTITY) the
#     author seeded for backward compatibility. Edit below to match your
#     own identities, or rely on the .local.md mapping.
# Always exits 0.

CWD=$(pwd)
NAME=$(git config user.name 2>/dev/null)
EMAIL=$(git config user.email 2>/dev/null)

# No git repo → nothing to check
[[ -z "$NAME" && -z "$EMAIL" ]] && exit 0

# Optional personal mapping file (gitignored). If absent, this hook
# falls back to the placeholder checks below and silently no-ops if
# no patterns match the cwd.
PERSONAL_MAP="$HOME/.claude/rules/identity.local.md"

WORK_CTX=false
PERSONAL_CTX=false

# Placeholder path patterns — edit to match your own identity contexts,
# or define them in identity.local.md instead.
if echo "$CWD" | grep -qiE "(WORK_IDENTITY_PATH_PATTERN)"; then
    WORK_CTX=true
fi
if echo "$CWD" | grep -qiE "(PERSONAL_IDENTITY_PATH_PATTERN)"; then
    PERSONAL_CTX=true
fi

# IMP-067 (2026-07-03): parse identity.local.md and apply its mappings.
# Before this, the hook NEVER read the file despite two rules claiming it did
# (metareview finding K8: guard functionally inert). Format parsed:
#   ### Identity N: <label>
#   - Git name: `Name`
#   - Git email: `email`
#   - Path patterns ...:
#     - `pattern`
# Semantics per identity.md: cwd matches pattern (case-insensitive substring)
# AND git email differs → warn (never block). <<TODO>> placeholders are skipped.
if [[ -r "$PERSONAL_MAP" ]]; then
    CWD_LC=$(printf '%s' "$CWD" | tr '[:upper:]' '[:lower:]')
    while IFS='|' read -r pat exp_name exp_email; do
        [[ -n "$pat" && -n "$exp_email" ]] || continue
        case "$exp_email" in *"<<TODO"*) continue ;; esac
        pat_lc=$(printf '%s' "$pat" | tr '[:upper:]' '[:lower:]')
        if [[ "$CWD_LC" == *"$pat_lc"* ]]; then
            if [[ -n "$EMAIL" && "$EMAIL" != "$exp_email" ]]; then
                echo "⚠️  IDENTITY MISMATCH: cwd matches '$pat' → expected $exp_name <$exp_email>,"
                echo "    but git config is '$NAME <$EMAIL>'. Fix: git config user.email '$exp_email'"
            fi
        fi
    done < <(awk '
        /^### Identity/ { name=""; email=""; inpat=0 }
        /^- Git name:/  { if (match($0, /`[^`]+`/)) name=substr($0, RSTART+1, RLENGTH-2) }
        /^- Git email:/ { if (match($0, /`[^`]+`/)) email=substr($0, RSTART+1, RLENGTH-2) }
        /^- Path patterns/ { inpat=1; next }
        /^##/ || /^### / { inpat=0 }
        inpat && /^[[:space:]]+- / {
            if (match($0, /`[^`]+`/)) print substr($0, RSTART+1, RLENGTH-2) "|" name "|" email
        }' "$PERSONAL_MAP")
fi

if $PERSONAL_CTX && echo "$NAME$EMAIL" | grep -qi "WORK_IDENTITY"; then
    echo "⚠️  IDENTITY LEAK RISK: Project path suggests PERSONAL_IDENTITY context, but git user is '$NAME <$EMAIL>'."
    echo "    Fix: git config user.name 'Personal Name' && git config user.email '<personal-email>'"
fi

if $WORK_CTX && echo "$NAME$EMAIL" | grep -qi "PERSONAL_IDENTITY"; then
    echo "⚠️  IDENTITY LEAK RISK: Project path suggests WORK_IDENTITY context, but git user is '$NAME <$EMAIL>'."
    echo "    Fix: git config user.name 'Work Name' && git config user.email '<work-email>'"
fi

exit 0
