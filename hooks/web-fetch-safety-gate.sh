#!/bin/bash
# web-fetch-safety-gate.sh — IMP-088 (2026-07-09)
# ──────────────────────────────────────────────────────────────────────
# Standing-allow for web research fetching; escalate to a native `ask`
# ONLY for URLs that trip a DETERMINISTIC danger signal. Pairs with
# rules/web-research-trust.md (the LLM-judgment layer).
#
# WHY a hook AND a rule (see agency-bands.md): a PreToolUse hook is a
# synchronous shell script — it CANNOT invoke an LLM. So it screens only
# the PATTERN-MATCHABLE danger subset; the nuanced "≥10% malicious"
# judgment (reputation, typosquat, warez) lives in the always-loaded rule.
#
# Fires on PreToolUse for:
#   • WebFetch                          (native — screened)
#   • WebSearch                         (native — no URL visited → allow)
#   • mcp__*__firecrawl_scrape|crawl|map|extract, *fetch*, web_fetch_*
#   • Bash: (a) curl|bash-style fetch-then-execute (RCE) on ANY command;
#           (b) fetch-CLI head (curl/wget/…) → its target URLs screened
#
# Deterministic danger signals (v2 — hardened after IMP-088 red-team):
#   - credentials embedded in URL (user:pass@)
#   - raw / obfuscated IP host: the TLD is not alphabetic (catches dotted,
#     decimal, hex 0x…, octal, and bracketed IPv6 in ONE rule)
#   - punycode / homograph label (xn--)
#   - abused / file-confusable TLD (.tk .ml .ga .cf .gq .zip .mov)
#   - URL shortener (hides the destination)
#   - direct executable / installer download (.exe .msi .dmg .deb .rpm …)
#   - fetched content piped/substituted into an interpreter (curl … | bash)
#
# Decision: danger → permissionDecision:"ask" (never silent-allow, never
# hard-deny). Clean / no-URL → exit 0 (falls through to settings `allow`).
#
# Hardening vs. red-team bypasses (3 rounds, 21 gaps closed / 87 pinned tests):
# case-insensitive + scheme-normalized extraction; scheme-less CLI targets;
# shell-metachar-terminated URL tokens; trailing-dot FQDN stripped; raw non-ASCII
# host (un-encoded homograph); last-path-segment ext (non-empty basename, %2e-
# decoded); `com` deliberately NOT an executable ext (commonest TLD); numeric host
# must be a full dotted-quad (curl `--retry 5`/`-m 30` is not a host); output-target
# filenames (`-o backup.zip`) stripped before host screening; ANY scheme screened
# (ftp/gopher raw-IP too); fetch CLI screened ANYWHERE in the command (env-prefix /
# cd&& / wrappers / chains, not just head); RCE detection newline-normalised and
# survives a trailing metachar (`sh -c "curl|bash"`, `(curl|bash)`, `curl|bash;…`,
# `$(curl|bash)`, line-split `curl|⏎bash`); iex/invoke-expression + iwr covered.
#
# SCOPE — the URL-screening path (WebFetch/Firecrawl/Bash-target-URLs) is the
# exhaustively-verified core. The Bash fetch-then-execute (curl|bash) detection is
# BEST-EFFORT defence-in-depth: a shell script cannot fully parse shell, so exotic
# composition (xargs/parallel/base64-decode/variable-indirection two-step download-
# then-run without a pipe, `/x.exe/download` mid-path ext, `# | bash` comment over-
# ask) is NOT robustly gated here — that is the remit of guard-unsafe.sh (CRITICAL
# floor) + rules/web-research-trust.md (the LLM judgment layer), per agency-bands.md.
#
# Fails OPEN (exit 0) on parse failure. Bypass: CLAUDE_WEBFETCH_GATE_OFF=1
# Self-test exemption: CLAUDE_WEBFETCH_GATE_TESTMODE=1 (prints "ASK: …" to stderr)
# Logged to global-observation/web-fetch-gate.log
set -u

[ "${CLAUDE_WEBFETCH_GATE_OFF:-0}" = "1" ] && exit 0

INPUT=$(cat 2>/dev/null || printf '{}')
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || printf '')
[ -n "$TOOL" ] || exit 0

LOG_FILE="$HOME/.claude/global-observation/web-fetch-gate.log"
# Metachars that must terminate a URL token (so `curl http://ip|sh` splits).
URLCLASS='[^"'"'"' 	|;&()<>\\]'

reason=""

# ── helper: screen one URL string, set $reason on the first danger hit ──
screen_url() {
  local url="$1" rest authority userinfo host tld seg base ext
  # strip ANY scheme, case-insensitively
  rest=$(printf '%s' "$url" | sed -E 's#^[A-Za-z][A-Za-z0-9+.-]*://##')
  authority="${rest%%/*}"; authority="${authority%%\?*}"; authority="${authority%%#*}"
  case "$authority" in *@*) userinfo="${authority%@*}"; authority="${authority##*@}" ;; *) userinfo="" ;; esac

  # bracketed IPv6 literal
  case "$authority" in
    \[*) reason="Roh-IPv6-Adresse statt Domain — verschleiert die Identität des Ziels"; return ;;
  esac
  host="${authority%%:*}"                       # drop :port
  host="${host%.}"                              # strip a single trailing FQDN dot
  host=$(printf '%s' "$host" | tr 'A-Z' 'a-z')
  [ -n "$host" ] || return

  # (a) credentials in URL
  if [ -n "$userinfo" ]; then
    reason="URL enthält eingebettete Zugangsdaten (user:pass@) — klassisches Phishing-/Verschleierungsmuster"; return
  fi
  # (b) punycode / homograph  (before the alphabetic-TLD test)
  case "$host" in
    xn--*|*.xn--*) reason="Punycode-/Homograph-Domain ($host) — häufig zur Markenimitation genutzt"; return ;;
  esac
  # raw non-ASCII bytes in the host = un-encoded IDN / Unicode homograph (e.g.
  # Cyrillic а in "раypal.com"); a legit hostname is LDH (letters/digits/.-_) only.
  if printf '%s' "$host" | LC_ALL=C grep -q '[^a-z0-9._-]'; then
    reason="Host enthält Nicht-ASCII-/Sonderzeichen — möglicher Unicode-Homograph-Angriff"; return
  fi
  # (c) raw / obfuscated IP: a real domain always ends in an alphabetic TLD.
  #     Non-alphabetic final label ⇒ dotted/decimal/hex/octal IP or numeric host.
  tld="${host##*.}"
  if ! printf '%s' "$tld" | grep -qE '^[a-z]{2,}$'; then
    reason="Roh-/verschleierte IP-Adresse oder numerischer Host ($host) — verschleiert die Identität des Ziels"; return
  fi
  # (d) abused / file-confusable TLD
  if printf '%s' "$tld" | grep -qE '^(tk|ml|ga|cf|gq|zip|mov)$'; then
    reason="Missbrauchsanfällige/dateiverwechselbare TLD (.$tld) — überdurchschnittlich für Malware/Phishing genutzt"; return
  fi
  # (e) URL shortener hides the destination
  if printf '%s' "$host" | grep -qE '(^|\.)(bit\.ly|tinyurl\.com|t\.co|goo\.gl|is\.gd|ow\.ly|buff\.ly|rebrand\.ly|cutt\.ly|shorturl\.at|tiny\.cc|rb\.gy|bit\.do|adf\.ly|shorte\.st|t\.ly|snip\.ly|lnkd\.in|v\.gd|s\.id|shrtco\.de)$'; then
    reason="URL-Shortener ($host) verbirgt das eigentliche Ziel — nicht bewertbar"; return
  fi
  # (f) direct executable / installer download — last path segment, non-empty basename
  seg="${rest#*/}"; case "$rest" in */*) ;; *) seg="" ;; esac   # part after host
  seg="${seg##*/}"; seg="${seg%%\?*}"; seg="${seg%%#*}"          # final segment, no query/frag
  seg=$(printf '%s' "$seg" | sed -E 's/%25([0-9a-fA-F]{2})/%\1/g; s/%2[eE]/./g')  # decode %2e (single/double-encoded dot)
  case "$seg" in
    ?*.?*)                                                       # name.ext, non-empty name
      base="${seg%.*}"; ext=$(printf '%s' "${seg##*.}" | tr 'A-Z' 'a-z')
      if [ -n "$base" ] && printf '%s' "$ext" | grep -qE '^(exe|msi|scr|bat|cmd|pif|apk|dmg|pkg|deb|rpm|run|bin|appimage|iso|jar|dll|cab|vbs|hta|wsf|reg|gadget|cpl|msc|jse|vbe|wsh|ps1)$'; then
        reason="Direkter Download einer ausführbaren/Installer-Datei (.$ext) — primärer Malware-Vektor"; return
      fi ;;
  esac
}

# ── 1. Route: is this a fetch we screen? Extract candidate URLs. ───────
URLS=""
case "$TOOL" in
  WebSearch) exit 0 ;;
  WebFetch)
    URLS=$(printf '%s' "$INPUT" | jq -r '
        [ .tool_input.url?, (.tool_input.urls?[]?), (.tool_input.links?[]?) ]
        | map(select(type=="string" and test("^https?://";"i"))) | .[]' 2>/dev/null | head -50)
    if [ -z "$URLS" ]; then
      URLS=$(printf '%s' "$INPUT" | jq -r '.tool_input | tostring' 2>/dev/null \
             | grep -oiE "https?://$URLCLASS+" | head -50)
    fi
    ;;
  mcp__*)
    case "${TOOL##*__}" in
      *firecrawl_scrape|*firecrawl_crawl|*firecrawl_map|*firecrawl_extract|*firecrawl_batch*|fetch|web_fetch_*|*_fetch|download_file_content) ;;
      *) exit 0 ;;
    esac
    URLS=$(printf '%s' "$INPUT" | jq -r '
        [ .tool_input.url?, (.tool_input.urls?[]?), (.tool_input.links?[]?) ]
        | map(select(type=="string" and test("^https?://";"i"))) | .[]' 2>/dev/null | head -50)
    if [ -z "$URLS" ]; then
      URLS=$(printf '%s' "$INPUT" | jq -r '.tool_input | tostring' 2>/dev/null \
             | grep -oiE "https?://$URLCLASS+" | head -50)
    fi
    ;;
  Bash)
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || printf '')
    [ -n "$CMD" ] || exit 0
    # (a) fetch-then-execute (RCE): a fetch CLI whose output feeds an interpreter
    #     via pipe / <(…) / $(…). Newlines/CRs/tabs are normalised to spaces FIRST
    #     so a line-split pipe (`curl x |⏎bash`) cannot straddle grep's per-line
    #     match. The interpreter token may be followed by ANY non-word char or EOL
    #     — so `sh -c "curl x | bash"`, `(curl x|bash)`, `curl x|bash;echo` match.
    CMD_RCE=$(printf '%s' "$CMD" | tr '\n\r\t' '   ')
    INTERP='bash|sh|zsh|dash|python[0-9.]*|ruby|perl|node|pwsh|powershell|osascript|iex|invoke-expression|eval'
    if printf '%s' "$CMD_RCE" | grep -qiE '(curl|wget|aria2c|httpie|invoke-webrequest|iwr|fetch)' \
       && printf '%s' "$CMD_RCE" | grep -qiE "\|[[:space:]]*($INTERP)([^a-zA-Z0-9]|\$)|($INTERP)[[:space:]]+<\(|($INTERP)[[:space:]]+[^|]{0,8}\\\$\((curl|wget|fetch)"; then
      reason="Gefetchter Remote-Inhalt wird in einen Interpreter gepiped/substituiert (curl|bash / iex-Muster) — Remote-Code-Execution-Vektor"
    fi
    # (b) screen the target URL(s) of any fetch CLI appearing ANYWHERE in the
    #     command — env-prefix (FOO=1 curl), cd&&…, timeout/nice wrappers, ;/&&
    #     chains — not only when it is the literal first token. Output-target
    #     filenames (-o X, --output X, >X, -T X) are stripped first so a saved
    #     name like `-o backup.zip` is not misread as an abused-TLD host.
    HEAD=$(printf '%s' "$CMD" | sed -E 's/^[[:space:]]*//' | awk '{print $1}')
    if printf '%s' "$CMD" | grep -qiE '(^|[^a-z0-9._-])(curl|wget|aria2c|httpie|firecrawl|iwr|invoke-webrequest|lynx|w3m|links2?)([^a-z0-9._-]|$)' \
       || case "$HEAD" in curl|wget|firecrawl|http|https|httpie|lynx|w3m|links|links2|aria2c|fetch) true ;; *) false ;; esac; then
      CMD_SL=$(printf '%s' "$CMD" | sed -E 's/(^|[[:space:]])(-o|--output|-T|--upload-file|>>?)[[:space:]]*[^[:space:]]+/ /g')
      schemed=$(printf '%s' "$CMD" | grep -oiE "[a-z][a-z0-9+.-]*://$URLCLASS+")
      # scheme-less targets: only a full dotted-quad IP counts as numeric (a bare
      # number like curl's `--retry 5` / `-m 30` is NOT a host).
      schemeless=$(printf '%s' "$CMD_SL" | tr ' \t\n' '\n\n\n' | grep -vE '^-' \
        | grep -iE '^((([a-z0-9_-]+\.)+[a-z0-9-]{2,})|([0-9]{1,3}(\.[0-9]{1,3}){3})|(0x[0-9a-f.]+))(:[0-9]+)?(/[^ ]*)?$' \
        | sed -E 's#^#http://#')
      # keep ANY scheme (ftp/gopher raw-IP fetches are screened too, not only http).
      URLS=$(printf '%s\n%s\n' "$schemed" "$schemeless" | grep -iE '^[a-z][a-z0-9+.-]*://' | head -50)
    fi
    ;;
  *) exit 0 ;;
esac

# ── 2. Screen each candidate URL (unless RCE already flagged) ──────────
if [ -z "$reason" ] && [ -n "$URLS" ]; then
  while IFS= read -r u; do
    [ -n "$u" ] || continue
    screen_url "$u"
    [ -n "$reason" ] && break
  done <<EOF
$URLS
EOF
fi

# ── 3. Emit decision ───────────────────────────────────────────────────
if [ -n "$reason" ]; then
  if [ "${CLAUDE_WEBFETCH_GATE_TESTMODE:-0}" = "1" ]; then
    printf 'ASK: %s\n' "$reason" >&2
    exit 0
  fi
  printf '{"ts":"%s","gate":"web-fetch","tool":"%s","decision":"ask","reason":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TOOL" "$reason" >> "$LOG_FILE" 2>/dev/null || true
  MSG="web-fetch-safety-gate (web-research-trust.md): ${reason}. Diese Anfrage überschreitet die deterministische Gefahrschwelle — bitte das Abrufen/Ausführen ausdrücklich bestätigen (y/n). Die Standing-Erlaubnis gilt nur für unauffällige Research-URLs."
  REASON_JSON=$(printf '%s' "$MSG" | jq -Rs '.')
  cat <<JSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": ${REASON_JSON}
  }
}
JSON
  exit 0
fi

exit 0
