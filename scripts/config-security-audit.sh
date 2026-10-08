#!/bin/bash
# config-security-audit.sh - read-only static security audit of a Claude Code
# configuration tree (IMP-244). Re-implements, in bash+jq+perl, the check
# categories AgentShield documents. No network, no --fix, no writes except the
# optional --report file.
#
# Usage: config-security-audit.sh [--root <dir>] [--live] [--json] [--report]
#                                 [--allow <file>]
#   default root = the repo this script lives in (workshop); --live = ~/.claude
# Exit: 0 no CRITICAL, 1 CRITICAL found, 2 usage/internal error.
# Exceptions: <script dir>/config-security-audit.allow (rule-id<TAB>pattern<TAB>reason)
#
# Rules: CSA-001/002 permissions | CSA-010..014 hook files/bodies | CSA-020..022
#   MCP definitions | CSA-030 hidden Unicode | CSA-031 instruction-shaped HTML
#   comment | CSA-032 BOM | CSA-033 file could not be scanned | CSA-040 cloned
#   repo ships config | CSA-050/051 invalid settings JSON
#
# Known limits (not checked): MCP remote url/headers/args, bunx / pnpm dlx /
# docker launchers, @next / ^range pinning nuance, allowlist granularity (exact
# subject match only). Hook-body and comment-verb checks are line regexes: they
# can false-positive on pattern strings and miss exotic composition.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF_DIR/.." && pwd)"
ALLOW="$SELF_DIR/config-security-audit.allow"
JSON=0; REPORT=0

die() { echo "config-security-audit: $*" >&2; exit 2; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)   [[ $# -ge 2 ]] || die "--root needs a directory"; ROOT="$2"; shift 2 ;;
    --live)   ROOT="$HOME/.claude"; shift ;;
    --json)   JSON=1; shift ;;
    --report) REPORT=1; shift ;;
    --allow)  [[ $# -ge 2 ]] || die "--allow needs a file"; ALLOW="$2"; shift 2 ;;
    -h|--help) sed -n '2,13p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done
command -v jq >/dev/null || die "jq is required"
command -v perl >/dev/null || die "perl is required"
[[ -d "$ROOT" ]] || die "root is not a directory: $ROOT"
ROOT="$(cd "$ROOT" && pwd)"
[[ -f "$ALLOW" ]] || die "allowlist file not found: $ALLOW"

F=$(mktemp "${TMPDIR:-/tmp}/csa.XXXXXX")
trap 'rm -f "$F" "$F.files" "$F.json" "$F.seen" "$F.err"' EXIT
# add <id> <sev> <file> <line> <subject> <message> <remediation>
# Tabs/newlines in any field are flattened so no finding is lost in rendering.
add() { local a=("$@") i; for i in 0 1 2 3 4 5 6; do a[$i]="${a[$i]//[$'\t\n\r']/ }"; done
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${a[0]}" "${a[1]}" "${a[2]#$ROOT/}" "${a[3]}" "${a[4]}" "${a[5]:0:240}" "${a[6]}" >> "$F"; }
lineof() { local n; n=$(grep -nF -m1 -- "$2" "$1" 2>/dev/null | cut -d: -f1); echo "${n:-0}"; }

# --- CSA-050/051 JSON validity, CSA-001/002 permissions ---------------------
SETTINGS="$ROOT/settings.json"
[[ -f "$SETTINGS" ]] || add CSA-050 CRITICAL "$SETTINGS" 0 settings.json "settings.json not found under $ROOT" "Point --root at a Claude config dir."
for sf in settings.json settings.local.json settings.framework.json; do
  f="$ROOT/$sf"; [[ -f "$f" ]] || continue
  if ! jq -e . "$f" >/dev/null 2>&1; then
    id=CSA-050; [[ $sf == settings.framework.json ]] && id=CSA-051
    add $id CRITICAL "$f" 0 "$sf" "$sf is not valid JSON" "Fix the syntax: jq . $sf"; continue
  fi
  jq -r '.permissions.allow // [] | .[] | select(type=="string")' "$f" | while IFS= read -r p; do
    case "$p" in
      Bash|Write|Edit|'Bash(*)'|'Bash(**)'|'Bash(:*)'|'Bash(sudo:*)'|'Bash(rm:*)'|'Bash(curl:*)'|'Bash(wget:*)'|'Bash(sudo *)'|'Bash(rm *)'|'Bash(curl *)'|'Read(*)'|'Read(**)'|'Edit(*)'|'Edit(**)'|'Write(*)'|'Write(**)')
        add CSA-001 WARN "$f" "$(lineof "$f" "\"$p\"")" "$p" "permissions.allow contains $p (unrestricted tool access)" \
          "Narrow the pattern, or list it in the allowlist file with a reason if runtime gates offset it." ;;
    esac
  done
  [[ "$(jq -r '.permissions.defaultMode // .defaultMode // ""' "$f")" == bypassPermissions ]] &&
    add CSA-002 WARN "$f" "$(lineof "$f" bypassPermissions)" defaultMode=bypassPermissions "defaultMode is bypassPermissions" "Use a prompting mode, or allowlist with a reason."
  [[ "$(jq -r '.skipDangerousModePermissionPrompt // false' "$f")" == true ]] &&
    add CSA-002 WARN "$f" "$(lineof "$f" skipDangerousModePermissionPrompt)" skipDangerousModePermissionPrompt "skipDangerousModePermissionPrompt is true" "Remove it so dangerous-mode entry stays confirmed."
done

# --- CSA-010..014: hooks ---------------------------------------------------
NET_RE='(^|[;&|(\"'"'"'`]|\$\(|[[:space:]](then|do|if|exec|xargs|command|sudo))[[:space:]]*(curl|wget|nc|ncat)([[:space:]]|$)|^(then|do|if|exec|xargs|command|sudo)[[:space:]]+(curl|wget|nc|ncat)([[:space:]]|$)'
LOCAL_URL='://(localhost|127\.0\.0\.1|\[::1\])([:/]|$)'
# scan_body <label-file> <line-base> <subject>  (body on stdin)
scan_body() {
  local file="$1" base="$2" subj="$3" n text rest urls u nonlocal
  while IFS=$'\t' read -r n text; do
    [[ "$text" =~ ^[[:space:]]*# ]] && continue
    if [[ "$text" =~ (^|[\;\&\|\(]|then|do)[[:space:]]*eval[[:space:]] ]]; then
      add CSA-012 WARN "$file" "$((base + n - 1))" "$subj" "hook body uses eval: $text" "Remove eval; regex match is imprecise, review the line (pattern strings may be false positives)."
    fi
    if [[ "$text" =~ $NET_RE ]]; then
      rest="${text#*"${BASH_REMATCH[0]}"}"; nonlocal=1
      urls=$(printf '%s' "$rest" | grep -oE '[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]"'"'"')]+' || true)
      if [[ -n "$urls" ]]; then
        nonlocal=0; while IFS= read -r u; do [[ "$u" =~ $LOCAL_URL ]] || nonlocal=1; done <<< "$urls"
      elif [[ "$rest" =~ ^[[:space:]]*(-[^[:space:]]+[[:space:]]+)*(localhost|127\.0\.0\.1)([:/[:space:]]|$) ]]; then nonlocal=0; fi
      [[ $nonlocal -eq 1 ]] && add CSA-013 WARN "$file" "$((base + n - 1))" "$subj" "hook body calls a network tool without a localhost-only URL: $text" "Confirm the destination; the localhost exemption covers the URL argument only; heuristic, pattern strings may false-positive."
    fi
    if [[ "$text" =~ base64[[:space:]]+(-d|-D|--decode)[^\|]*\|[[:space:]]*(ba|z)?sh ]]; then
      add CSA-014 WARN "$file" "$((base + n - 1))" "$subj" "hook decodes base64 into a shell: $text" "Remove decode-and-execute."
    fi
  done < <(awk '{printf "%d\t%s\n", NR, $0}')
}
: > "$F.seen"
scan_hook_file() {   # scan_hook_file <path> <subject>
  grep -qxF -- "$1" "$F.seen" && return 0; echo "$1" >> "$F.seen"
  if [[ ! -r "$1" ]]; then add CSA-033 WARN "$1" 0 "$2" "hook file unreadable, not scanned: $1" "Fix permissions and re-run."; return 0; fi
  [[ -n "$(find "$1" -maxdepth 0 -perm -0002 2>/dev/null)" ]] && add CSA-011 WARN "$1" 0 "$2" "hook file is world-writable: $1" "chmod o-w on the file."
  grep -Iq . "$1" 2>/dev/null && scan_body "$1" 1 "$2" < "$1"
  return 0
}
for sf in settings.json settings.local.json; do
  f="$ROOT/$sf"; { [[ -f "$f" ]] && jq -e . "$f" >/dev/null 2>&1; } || continue
  jq -r '[.hooks // {} | .[] | .[]? | .hooks[]? | .command // empty] | unique | .[]' "$f" | while IFS= read -r cmd; do
    sl=$(lineof "$f" "$(printf '%s' "$cmd" | cut -c1-60)")
    printf '%s\n' "$cmd" | scan_body "$f" "$sl" "inline:${cmd:0:40}"
    for tok in $(set -f; printf '%s' "$cmd" | grep -oE '[^[:space:]"'\'';|&<>]+\.(sh|js|py|mjs|ts)' | sort -u); do
      path="$tok"
      case "$path" in
        '$HOME/.claude/'*) path="$ROOT/${path#\$HOME/.claude/}" ;;
        '${HOME}/.claude/'*) path="$ROOT/${path#\$\{HOME\}/.claude/}" ;;
        '~/.claude/'*) path="$ROOT/${path#\~/.claude/}" ;;
        /*) ;;
        *) add CSA-010 INFO "$f" "$sl" "$tok" "hook path not statically resolvable: $tok" "Resolve manually; variable or relative paths are not checked."; continue ;;
      esac
      if [[ ! -f "$path" ]]; then
        alt="$HOME/.claude/${path#$ROOT/}"   # workshop mode: runtime-only files live in the install
        if [[ "$ROOT" != "$HOME/.claude" && -f "$alt" ]]; then path="$alt"
        else add CSA-010 WARN "$f" "$sl" "$tok" "registered hook file does not exist: $tok" "Fix the path or remove the registration."; continue; fi
      fi
      scan_hook_file "$path" "$tok"
    done
  done
done
# every file under hooks/ (registered or not), tests excluded
[[ -d "$ROOT/hooks" ]] && find "$ROOT/hooks" -type f -not -path '*/hooks/tests/*' | sort | while IFS= read -r hf; do
  scan_hook_file "$hf" "${hf#$ROOT/}"; done

# --- CSA-020..022: MCP definitions -----------------------------------------
check_mcp() {   # check_mcp <json-file> <jq expression producing {name:server}>
  local file="$1" name pkg args cmd a ln k
  jq -e . "$file" >/dev/null 2>&1 || { add CSA-050 CRITICAL "$file" 0 "${file##*/}" "${file##*/} is not valid JSON" "Fix the syntax."; return; }
  jq -r "$2 | to_entries[] | [.key, (.value.command // \"\"), ((.value.args // []) | map(tostring) | join(\" \"))] | @tsv" "$file" |
  while IFS=$'\t' read -r name cmd args; do
    ln=$(lineof "$file" "\"$name\"")
    if [[ "$cmd" == "npx" || "$cmd" == "uvx" ]]; then
      [[ " $args " =~ \ (-y|--yes)\  ]] && add CSA-020 WARN "$file" "$ln" "$name" "MCP server '$name' runs '$cmd -y' (installs without prompt)" "Pin the version and install it once instead of auto-confirming."
      pkg=""; for a in $args; do [[ "$a" == -* ]] || { pkg="$a"; break; }; done
      if [[ "$pkg" == *@latest ]]; then add CSA-021 WARN "$file" "$ln" "$name" "MCP server '$name' uses @latest: $pkg" "Pin an exact version."
      elif [[ -n "$pkg" ]] && ! [[ "${pkg#@}" == *@* || "$pkg" == *==* ]]; then add CSA-021 WARN "$file" "$ln" "$name" "MCP server '$name' package is unpinned: $pkg" "Pin an exact version (pkg@1.2.3)."; fi
    fi
    jq -r --arg n "$name" "$2 | .[\$n].env // {} | to_entries[] | select((.key|test(\"KEY|TOKEN|SECRET|PASSWORD|AUTH\";\"i\")) and (.value|type==\"string\") and ((.value|length)>=8) and (.value|test(\"^\\\\$\\\\{?[A-Za-z_]\")|not)) | .key" "$file" |
    while IFS= read -r k; do
      add CSA-022 WARN "$file" "$(lineof "$file" "\"$k\"")" "$name:$k" "MCP server '$name' has a literal secret-like value in env.$k" "Reference an environment variable instead of inlining the value."
    done
  done
}
[[ -f "$ROOT/.mcp.json" ]] && check_mcp "$ROOT/.mcp.json" '.mcpServers // {}'
if [[ "$ROOT" == "$HOME/.claude" && -f "$HOME/.claude.json" ]]; then
  check_mcp "$HOME/.claude.json" '([.mcpServers // {}] + [.projects // {} | .[] | .mcpServers // {}]) | add'
fi

# --- CSA-030..033: instruction files ---------------------------------------
{ [[ -f "$ROOT/CLAUDE.md" ]] && echo "$ROOT/CLAUDE.md"
  for d in rules skills templates rcode docs agents commands output-styles; do
    [[ -d "$ROOT/$d" ]] && find "$ROOT/$d" -type f \( -name '*.md' -o -name '*.md.template' \) -not -path '*/node_modules/*'
  done
} | sort -u > "$F.files"
UNI='[\x{00AD}\x{034F}\x{180E}\x{200B}\x{200C}\x{200E}\x{200F}\x{2028}-\x{202E}\x{2060}-\x{2064}\x{2066}-\x{2069}\x{FEFF}\x{E0000}-\x{E007F}]'
CMT_SKIP='^\s*(Status:\s*[A-Za-z]+|Last Updated:\s*[\d-]+|controller-contract:v\d+(\s+exempt="[^"]*")?)\s*$'
CMT_VERB='\b(ignore|disregard|override|you must|do not tell|run|execute|curl|send|delete)\b'
while IFS= read -r f; do
  if [[ ! -r "$f" ]]; then add CSA-033 WARN "$f" 0 "${f#$ROOT/}" "instruction file unreadable, not scanned" "Fix permissions and re-run."; continue; fi
  out=$(perl -CSD -w -ne 'while (/('"$UNI"')/g) { printf "%d:%d:U+%04X\n", $., pos(), ord($1) }' "$f" 2>"$F.err"); rc=$?
  if [[ $rc -ne 0 || -s "$F.err" ]]; then add CSA-033 WARN "$f" 0 "${f#$ROOT/}" "hidden-Unicode scan failed or file is not valid UTF-8 (scan incomplete): $(head -c 120 "$F.err")" "Fix the file encoding and re-run."; fi
  while IFS=: read -r ln col cp; do
    [[ -n "$ln" ]] || continue
    if [[ "$cp" == U+FEFF ]]; then
      sev=WARN; [[ "$ln:$col" == "1:1" ]] && sev=INFO
      add CSA-032 $sev "$f" "$ln" "$cp" "byte-order mark U+FEFF at line $ln col $col" "Remove the BOM unless the file needs it."
    else
      add CSA-030 CRITICAL "$f" "$ln" "$cp" "hidden Unicode $cp at line $ln col $col" "Delete the invisible character (it can smuggle instructions); locate with perl -CSD -ne 'print if /[\\x{200B}-\\x{200F}]/' file"
    fi
  done <<< "$out"
  out=$(perl -CSD -w -0777 -ne 'while (/<!--(.*?)-->/gs) { my $c=$1; my $ln=1+(substr($_,0,$-[0])=~tr/\n//);
      my $b=join(" ", grep { !/^\s*$/ && !/'"$CMT_SKIP"'/ } split /\n/, $c);
      if ($b =~ /'"$CMT_VERB"'/i) { $b =~ s/\s+/ /g; printf "%d\t%s\n", $ln, substr($b,0,70) } }' "$f" 2>"$F.err"); rc=$?
  [[ $rc -ne 0 || -s "$F.err" ]] && add CSA-033 WARN "$f" 0 "${f#$ROOT/}" "HTML-comment scan failed (scan incomplete): $(head -c 120 "$F.err")" "Fix the file and re-run."
  while IFS=$'\t' read -r ln txt; do
    [[ -n "$ln" ]] || continue
    add CSA-031 WARN "$f" "$ln" comment "HTML comment with instruction verb: <!-- $txt" "Hidden from readers but seen by the model; delete it or move it into visible text. Verb match is heuristic."
  done <<< "$out"
done < "$F.files"

# --- CSA-040: cloned repos shipping config ---------------------------------
find "$ROOT" \( -name .git -o -path "$ROOT/projects" \) -prune -o -type f \( -name .mcp.json -o -path '*/.claude/settings.json' -o -path '*/.claude/settings.local.json' \) -print 2>/dev/null |
while IFS= read -r f; do
  case "$f" in "$ROOT/.mcp.json"|"$ROOT/.claude/settings.json"|"$ROOT/.claude/settings.local.json") continue ;; esac
  cloned=0; case "$f" in */research/*|*/node_modules/*) cloned=1 ;; esac
  d="$(dirname "$f")"
  while [[ "$d" != "$ROOT" && "$d" != "/" ]]; do [[ -e "$d/.git" ]] && cloned=1; d="$(dirname "$d")"; done
  [[ $cloned -eq 1 ]] && add CSA-040 WARN "$f" 0 "${f#$ROOT/}" "cloned repo ships its own config: ${f#$ROOT/}" "Never open a Claude session inside that tree without reviewing the file; delete the clone or the file if unused."
done

# --- allowlist, render ------------------------------------------------------
jq -R -s --rawfile allow "$ALLOW" '
  ($allow | split("\n") | map(select(length>0 and (startswith("#")|not)) | split("\t")) | map(select(length>=3) | {id:.[0],pat:.[1],reason:.[2]})) as $al
  | split("\n") | map(select(length>0) | split("\t")) | map(select(length==7)
  | {id:.[0],severity:.[1],file:.[2],line:(.[3]|tonumber),subject:.[4],message:.[5],remediation:.[6]}
  | . as $f | ($al | map(select(.id==$f.id and .pat==$f.subject)) | first) as $m
  | $f + {suppressed:($m!=null), reason:($m.reason // null)})' "$F" > "$F.json" || die "internal error rendering findings"
[[ "$(jq length "$F.json")" -eq "$(wc -l < "$F" | tr -d ' ')" ]] || die "internal error: findings lost while rendering"

NCRIT=$(jq '[.[]|select(.severity=="CRITICAL" and .suppressed==false)]|length' "$F.json")
NWARN=$(jq '[.[]|select(.severity=="WARN" and .suppressed==false)]|length' "$F.json")
NSUP=$(jq '[.[]|select(.suppressed)]|length' "$F.json")
text() { jq -r '.[] | (if .suppressed then "SUPPRESSED" else .severity end) as $s
  | "\($s) \(.id) \(.file):\(.line) - \(.message)\n    fix: \(.remediation)" + (if .suppressed then "\n    allowed: \(.reason)" else "" end)' "$F.json"
  echo "root: $ROOT | CRITICAL: $NCRIT | WARN: $NWARN | suppressed: $NSUP"; }

if [[ $JSON -eq 1 ]]; then
  jq --arg root "$ROOT" --argjson c "$NCRIT" --argjson w "$NWARN" --argjson s "$NSUP" \
    '{root:$root, critical:$c, warn:$w, suppressed:$s, findings:.}' "$F.json"
else text; fi
if [[ $REPORT -eq 1 ]]; then
  RD="$HOME/.claude/audit-reports"; mkdir -p "$RD" || die "cannot create $RD"
  { echo "# Config Security Audit - $(date +%Y-%m-%d)"; echo; echo '```'; text; echo '```'; } > "$RD/config-security-$(date +%Y-%m-%d).md" || die "cannot write report"
fi
[[ "$NCRIT" -eq 0 ]] || exit 1
exit 0
