"""tmux rules (rule A): global-option parsing, subcommand classification, format allow-list."""
import re

from cockpit_secret_common import DENY_WORDS, DYN, R_TMUX, SUB_OPEN, Deny, ask
from cockpit_secret_tmuxcmds import RUNNERS, READERS, resolve

SAFE_FORMATS = {"session_name", "session_id", "session_windows", "session_attached", "window_index",
                "window_name", "window_id", "window_active", "window_panes", "pane_id", "pane_index",
                "pane_active", "pane_width", "pane_height", "pane_pid", "pane_tty", "pane_dead",
                "pane_in_mode", "pane_left", "pane_top", "pane_right", "pane_bottom", "pane_current_path",
                "pane_current_command", "host", "host_short", "client_name", "client_tty", "client_width",
                "client_height", "socket_path"}
SAFE_SHORT = set("SIWPFHhD")
PLACEHOLDER = re.compile(r"\{\}|%[sS]|\{[0-9]*\}|@")
TAKES_ARG = "LSfcT"   # global flags that consume a value (getopt-style, may be glued)
COPY_CMDS = ("copy-pipe", "copy-selection", "pipe", "append-selection")


def dynamic(w):
    return DYN in w or SUB_OPEN in w or bool(PLACEHOLDER.fullmatch(w)) or bool(re.search(r"[*?\[]", w))


def check_formats(fmts):
    for f in fmts:
        if "#(" in f:
            raise Deny(R_TMUX + ": a #(...) shell expansion inside a tmux format")
        for m in re.finditer(r"#\{([^}]*)\}", f):
            if m.group(1) not in SAFE_FORMATS:
                raise Deny(R_TMUX + ": format variable '%s' is not on the metadata allow-list" % m.group(1))
        for m in re.finditer(r"#([A-Za-z])", re.sub(r"#\{[^}]*\}|##", "", f)):
            if m.group(1) not in SAFE_SHORT:
                raise Deny(R_TMUX + ": short format #%s is not on the metadata allow-list" % m.group(1))


def formats_of(sub, rest):
    """Format strings a subcommand will print: every -F value, plus display-message's positional one."""
    fmts, k = [], 0
    while k < len(rest):
        a = rest[k]
        if a.startswith("-") and not a.startswith("--") and len(a) > 1:
            if a.endswith("F") and k + 1 < len(rest):
                fmts.append(rest[k + 1])
                k += 1
            elif "F" in a[1:] and not a.endswith("F"):
                fmts.append(a[a.index("F") + 1:])
            elif a[-1] in "cdt" and k + 1 < len(rest):
                k += 1
            elif sub == "display-message" and "a" in a[1:]:
                raise Deny(R_TMUX + ": display-message -a dumps every format variable")
        elif sub == "display-message":
            fmts.append(a)
        k += 1
    return fmts


def parse_globals(args, ctx):
    """Index of the first subcommand word; handles -L/-S/-f/-c/-T values, -C and clusters."""
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--":
            return i + 1
        if not a.startswith("-") or len(a) == 1:
            return i
        for k, ch in enumerate(a[1:], 1):
            if ch == "C":
                raise Deny(R_TMUX + ": tmux control mode (-C) executes commands read from stdin")
            if ch in TAKES_ARG:
                val = a[k + 1:] or (args[i + 1] if i + 1 < len(args) else "")
                i += 0 if a[k + 1:] else 1
                if ch == "c":
                    ctx.scan(val, ctx.depth + 1)
                if ch == "f" and val != "/dev/null":
                    ask("tmux -f runs a config file's commands (can contain capture-pane/run-shell)")
                break
        i += 1
    return i


def split_sequences(words):
    seqs, cur = [], []
    for w in words:
        if w == ";" or (w.endswith(";") and len(w) > 1):
            if w != ";":
                cur.append(w[:-1])
            seqs.append(cur)
            cur = []
        else:
            cur.append(w)
    return seqs + [cur]


def check_sequence(seq, ctx):
    sub, rest = seq[0], seq[1:]
    if dynamic(sub):
        raise Deny(R_TMUX + ": tmux subcommand '%s' cannot be determined (stdin/variable/substitution)" % sub)
    name = resolve(sub)
    if name in READERS:
        raise Deny(R_TMUX + ": tmux " + sub)
    letters = "".join(a[1:] for a in rest if a.startswith("-") and not a.startswith("--"))
    if name == "find-window" and ("N" not in letters or "C" in letters or "T" in letters):
        raise Deny(R_TMUX + ": find-window searches pane contents (an oracle for the token)")
    if name == "show-environment":
        ask("tmux show-environment can expose secrets set in the tmux environment")
    if name == "source-file":
        ask("tmux source-file runs a command file the agent may have written (capture-pane/run-shell)")
    if name in ("show-options", "show-window-options") and any(r.startswith("@") for r in rest):
        ask("tmux show-options of a user option (@name) can expose a stored secret")
    if name == "send-keys" and "X" in letters and any(r.startswith(COPY_CMDS) for r in rest):
        raise Deny(R_TMUX + ": copy-mode copy-pipe/copy-selection/pipe")
    check_formats(formats_of(name, rest))
    for w in rest:
        for inner in re.findall(r"#\(([^)]*)\)", w):
            ctx.scan(inner, ctx.depth + 1)
    text = " ".join(rest)
    if name in RUNNERS and DENY_WORDS.search(text):
        raise Deny(R_TMUX + ": a capture command is queued as tmux command text")
    for t in [text] + [w for w in rest if re.search(r"\s", w)]:
        ctx.scan(t, ctx.depth + 1)
        if name in RUNNERS:
            ctx.scan("tmux " + t, ctx.depth + 1)


def check_tmux(args, ctx):
    """ctx supplies scan(text, depth), depth and via_stdin (xargs/parallel feed the arguments)."""
    seqs = split_sequences(args[parse_globals(args, ctx):])
    if ctx.via_stdin and not seqs[0]:
        raise Deny(R_TMUX + ": tmux subcommand comes from stdin (xargs/parallel)")
    for seq in seqs:
        if seq:
            check_sequence(seq, ctx)
