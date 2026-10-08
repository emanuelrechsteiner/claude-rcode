"""Classifier for cockpit-secret-guard.sh: one PreToolUse JSON on stdin, one
tab-separated line out: ALLOW|DENY|ASK|ERROR, the reason, a redacted summary.

Rules (see the hook header for the threat model and the residual-risk register):
  A  tmux pane/buffer capture at COMMAND position (cockpit_secret_tmux.py)
  B  any reference to ~/.claude/cockpit/web-* in any spelling (cockpit_secret_paths.py)
  C  environment dumps of the cockpit server (cockpit_secret_exec.py)
Quoted DATA (git commit -m "...", echo, grep patterns) is not a command, so rule A
ignores it. ERROR only for unparseable hook JSON; any failure caused by the command
itself (size, nesting, tokenizer error, scan budget) is a DENY. ASK = a native user prompt.
"""
import json
import os
import re
import signal
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cockpit_secret_cmds as cm  # noqa: E402
import cockpit_secret_exec as xe  # noqa: E402
import cockpit_secret_lex as lex  # noqa: E402
from cockpit_secret_common import (ASKS, DENY_WORDS, DYN, R_FILE, R_OBF, R_TMUX, SUB_OPEN, Deny, ask,  # noqa: E402
                                   loose_tmux)
from cockpit_secret_exec import decoders_in, is_interp  # noqa: E402
from cockpit_secret_lexexp import decode_twice  # noqa: E402
from cockpit_secret_paths import NAMES, check_tool, dir_hit, fold, norm, path_hit, word_variants  # noqa: E402
from cockpit_secret_progs import DATA_PROGS, SHELLS, pname, programs  # noqa: E402
from cockpit_secret_tmux import check_tmux  # noqa: E402

MAX_COMMAND_BYTES = 64 * 1024
SCAN_BUDGET_SECONDS = 3
EXEC_STRING = {"watch", "parallel", "ssh", "su", "sg", "script", "flock", "at", "batch"}
ZSH_GLOB = re.compile(r"\.claude/cockpit/[(^]")
READ_TOOL = re.compile(r"read|get|view|open|cat|list|search|grep|glob|find|tree|info|stat|head|tail", re.I)


def run_prog(k, b, words, cmd, st, script, depth):
    args = words[k + 1:]
    via = any(pname(w) in ("xargs", "parallel") for w in words[:k + 1])
    ctx = cm.Ctx(lambda t, d: scan(t, d, st), depth, via)
    if b == "tmux":
        if via and any(DENY_WORDS.search(t) for t in cm.stdin_texts(cmd)):
            raise Deny(R_TMUX + ": a capture subcommand is fed to tmux through xargs/parallel")
        check_tmux(args, ctx)
    elif b in SHELLS or (b in ("source", ".") and k == 0):
        cm.check_shell(args, cmd, ctx, st)
    elif b == "eval":
        text = " ".join(args)
        ctx.scan(re.sub(r"[\x01\x02]", " ", text), depth + 1)
        cm.marker_payloads(text, ctx, st)
        if SUB_OPEN in text and loose_tmux(text):
            raise Deny(R_TMUX + ": eval of a substitution")
    elif is_interp(b) or b in xe.AWKISH:
        xe.check_code(b, " ".join(args) + "\n" + "\n".join(cm.stdin_texts(cmd)), st.cwd)
    elif b == "ps":
        xe.check_ps(args, script)
    elif b == "find":
        cm.check_find(args, st)
    else:
        xe.check_readback(b, args, words)


def track_written(cmd, st, words, i, base, depth):
    """echo/printf/heredoc written to a file in this command, then run by a shell/interpreter: scan the payload."""
    for op, tgt in cmd.redirs:
        if op in (">", ">>", ">|", "&>") and (base in ("echo", "printf") or cmd.heredoc):
            st.written[norm(tgt)] = cmd.heredoc or " ".join(words[i + 1:])
    runner = base in SHELLS or is_interp(base) or base in ("source", ".")
    for a in words[i:] if runner else words[i:i + 1]:
        if norm(a) in st.written:
            payload = st.written[norm(a)]
            for text in {payload, decode_twice(payload)}:
                scan(text, depth + 1, st)
                if is_interp(base):
                    xe.check_code("python", text, st.cwd)


NO_READ = {"ls", "cd", "pushd", "echo", "printf", "pwd", "true", "false", "test", "[", "stat", "wc", "du", "file",
           "basename", "dirname", "realpath", "sleep", "date", "export", "unset", "alias"}


def check_dynamic_in_cockpit(words, i, base, st):
    """Inside the cockpit dir a generated argument ($(ls), $f, ...) may name a web-* file."""
    if st.cwd is None or base in NO_READ or not dir_hit(st.cwd):
        return
    for w in words[i + 1:]:
        if re.search(r"[\x01\x06]", w):
            lit = re.split(r"[\x01\x06]", w, 1)[0].casefold()
            if "/" not in lit and any(n.startswith(lit) for n in NAMES):
                raise Deny(R_FILE + ": generated argument inside the Cockpit directory could name web-*")


def check_cmd(cmd, st, script, depth):
    words = cmd.words
    for w in words + [t for _, t in cmd.redirs]:
        if any(path_hit(v, st.cwd) for v in word_variants(w)):
            raise Deny(R_FILE)
    xe.check_proc_environ(words)
    i = 0
    while i < len(words) and lex.ASSIGN.match(words[i]):
        i += 1
    if i >= len(words):
        return
    if pname(words[i]) in st.aliases:
        sub = lex.State(st)
        lex.parse(st.aliases[pname(words[i])], sub, depth + 1)
        if sub.cmds:
            words = words[:i] + sub.cmds[0].words + words[i + 1:]
    base = pname(words[i])
    if base in ("cd", "pushd"):
        t = next((w for w in words[i + 1:] if not w.startswith("-") or w == "-"), "~")
        st.cwd = None if t == "-" else norm(t if t.startswith(("/", "~", "$")) or st.cwd is None else st.cwd + "/" + t)
    for w in words[i + 1:]:
        if base == "alias" and "=" in w:
            scan(w.partition("=")[2], depth + 1, st)
        if base == "git" and (w.startswith("!") or "=!" in w):
            scan(w.split("!", 1)[1], depth + 1, st)
    pw = words[i]
    if DYN in pw or SUB_OPEN in pw:
        if any(DENY_WORDS.fullmatch(w) for w in words[i + 1:]):
            raise Deny(R_TMUX + ": a capture command run through a dynamic program word")
        decoders_in(pw)
        bare = re.sub(r"\x06(\$\{[^}]*\}|\$\w+)|\x01.*?\x02", "", pw, flags=re.S)
        if st.built and not re.search(r"[A-Za-z0-9]", bare):
            ask(R_OBF + " (program word built from read/printf -v/eval data)")
    xe.check_plugins(words)
    check_dynamic_in_cockpit(words, i, base, st)
    track_written(cmd, st, words, i, base, depth)
    progs = programs(words, i, base)
    for k, b in progs:
        run_prog(k, b, words, cmd, st, script, depth)
    if base in EXEC_STRING or (base == "env" and any(a.startswith(("-S", "--split-string")) for a in words)):
        for a in words[i + 1:]:
            if re.search(r"\s", a):
                scan(a, depth + 1, st)
    cm.check_dirs(base, words[i + 1:], cmd, st)
    if base not in DATA_PROGS and not any(b == "tmux" for _, b in progs):
        if any(DENY_WORDS.fullmatch(a) for a in words[i + 1:]):
            ask("a tmux read subcommand passed to '%s' (renamed or symlinked tmux?)" % base)


def scan(script, depth=0, parent=None, cwd=None):
    st = lex.State(parent)
    if cwd is not None:
        st.cwd = cwd
    if parent is None and ZSH_GLOB.search(fold(script)):
        raise Deny(R_FILE + ": zsh extended-glob syntax right after the Cockpit directory")
    lex.parse(script, st, depth)
    for cmd in st.cmds:
        check_cmd(cmd, st, script, depth)


def redact(text):
    text = re.sub(r"\s+", " ", text[:2000])
    text = re.sub(r"(?i)(token|secret|key|passw\w*|bearer|authorization)([=: ]+)\S+", r"\1\2[REDACTED]", text)
    return re.sub(r"[A-Za-z0-9_\-]{24,}", "[REDACTED]", text)[:120]


def strings_of(obj, out):
    if isinstance(obj, str):
        out.append(obj)
    elif isinstance(obj, dict):
        for v in list(obj.values())[:50]:
            strings_of(v, out)
    elif isinstance(obj, list):
        for v in obj[:200]:
            strings_of(v, out)
    return out


def on_timeout(_sig, _frm):
    raise TimeoutError("scan budget of %ds exceeded" % SCAN_BUDGET_SECONDS)


def main():
    try:
        data = json.load(sys.stdin)
        ti = data.get("tool_input") or {}
        name = data.get("tool_name") or ("Bash" if "command" in ti else "")
        cwd = data.get("cwd") if isinstance(data.get("cwd"), str) and data.get("cwd") else None
    except (ValueError, AttributeError):
        print("ERROR\tunparseable hook input\t")
        return
    subject = ""
    try:
        signal.signal(signal.SIGALRM, on_timeout)
        signal.alarm(SCAN_BUDGET_SECONDS)
        if name == "Bash":
            subject = ti.get("command") or ""
            if len(subject.encode("utf-8", "replace")) > MAX_COMMAND_BYTES:
                raise Deny("command too long to inspect (over %d bytes); fail closed" % MAX_COMMAND_BYTES)
            if subject:
                scan(subject, 0, None, cwd)
        else:
            subject = str(ti.get("file_path") or ti.get("path") or ti.get("pattern") or "")
            verdict = check_tool(name, ti, cwd) if name in ("Read", "Grep", "Glob") else None
            if name.startswith("mcp__") and READ_TOOL.search(name):
                verdict = "D" if any(path_hit(s, cwd) for s in strings_of(ti, []) if not re.search(r"\s", s)) else None
            if verdict == "D":
                raise Deny(R_FILE)
            if verdict == "K":
                ask(cm.R_ANC)
    except Deny as d:
        print("DENY\t%s\t%s %s" % (d, name, redact(subject)))
        return
    except Exception as e:  # noqa: BLE001 - ANY scanner failure on a parsed call must fail closed
        print("DENY\tcommand too complex to inspect (%s: %s); fail closed\t%s %s"
              % (type(e).__name__, e, name, redact(subject)))
        return
    finally:
        signal.alarm(0)
    if ASKS:
        print("ASK\t%s\t%s %s" % ("; ".join(ASKS), name, redact(subject)))
        return
    print("ALLOW\t\t")


if __name__ == "__main__":
    main()
