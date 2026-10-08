"""Rules for code-carrying and process-inspecting programs: interpreters, awk/sed, terminal
read-back tools (screen/zellij/kitty/wezterm/osascript), debuggers, `ps` environment dumps."""
import re

from cockpit_secret_common import DECODERS, loose_tmux, R_ENV, R_FILE, R_OBF, R_TMUX, Deny, ask
from cockpit_secret_paths import LITERAL, dir_hit, fold, path_hit

INTERP = re.compile(r"^(python[0-9.]*|node|nodejs|deno|bun|perl|ruby|php|lua|osascript|pwsh|tclsh|swift|julia|r|rscript)$")
AWKISH = {"awk", "gawk", "mawk", "nawk", "sed", "gsed"}
CONCAT = re.compile(r"['\"]\s*[+.]\s*['\"]|\.join\(|\bjoin\s*\(|%s|\.format\(|\bf['\"]")
EXEC_PRIM = re.compile(r"os\.system|subprocess|popen|child_process|execsync|spawn|\bexec\b|\bsystem\s*\(|"
                       r"shell_exec|do shell script|\beval\b|`")
WALKERS = re.compile(r"listdir|scandir|walk|glob|iterdir|readdir|rglob|\bfind\b|opendir|\bls\b")
TERMINALS = re.compile(r"terminal|iterm|ghostty|kitty|alacritty|wezterm|\bwarp\b|hyper")
TERM_READ = re.compile(r"contents|history|\btext\b|scrollback|session")
TOKENS = re.compile(r"[~$/\w.*?\[\]{}-]{3,}")
PID_TOOLS = {"reptyr", "gcore", "vmmap", "sample", "leaks"}
DEBUGGERS = {"gdb", "lldb", "dtruss", "ktrace", "strace", "ltrace"}
READBACK = {"screen": ("hardcopy",), "zellij": ("dump-screen", "dump-layout"), "kitty": ("get-text",),
            "kitten": ("get-text",), "wezterm": ("get-text",)}


def is_interp(b):
    return bool(INTERP.match(b))


def check_code(base, text, cwd=None):
    """Interpreter / awk / sed program text: a named token path, a tmux capture, or an obfuscated builder."""
    flat = re.sub(r"/+", "/", fold(text))
    if LITERAL.search(flat):
        raise Deny(R_FILE + ": interpreter code names the file")
    if loose_tmux(text):
        raise Deny(R_TMUX + ": interpreter code runs a tmux capture")
    if any(path_hit(tok, cwd) for tok in TOKENS.findall(text) if re.search(r"claude|cockpit|web-|\*", tok, re.I)):
        raise Deny(R_FILE + ": interpreter code names a path or glob that reaches the file")
    low = fold(text)
    if base in AWKISH:
        return
    if cwd and dir_hit(cwd) and WALKERS.search(low):
        raise Deny(R_FILE + ": interpreter lists/globs files while in the Cockpit directory")
    if base == "osascript" and TERMINALS.search(low) and TERM_READ.search(low):
        ask("osascript reading a terminal app's contents/history (scrollback holds the launch token)")
    obf = bool(CONCAT.search(text) or DECODERS.search(text))
    if (".claude" in low or "cockpit" in low) and (obf or WALKERS.search(low)):
        ask("interpreter code builds or walks a path under ~/.claude (cannot prove it avoids web-*)")
    if EXEC_PRIM.search(low) and obf:
        ask("interpreter code runs a command built from string pieces/decoders (cannot be inspected)")


def check_readback(base, args, words):
    if base in READBACK and any(a in READBACK[base] for a in args):
        raise Deny(R_TMUX + ": %s %s reads terminal contents back (launch token in scrollback)" % (base, args[0]))
    if base in PID_TOOLS or (base in DEBUGGERS and any(re.fullmatch(r"-p|--pid|attach|\d+", a) or "\x01" in a
                                                       for a in args)):
        ask("%s attaches to / dumps another process (the Cockpit server holds the token in memory)" % base)


def check_plugins(words):
    if any("tmux-resurrect" in w or "tmux-continuum" in w for w in words):
        ask("tmux-resurrect/continuum scripts save pane contents (capture-pane) to disk")


def check_ps(args, script):
    """ps environment dumps: BSD 'e', -E, -o ...env..., with no numeric pid selector or naming the server."""
    env_flag, numeric_sel, skip = False, False, None
    for a in args:
        if skip:
            if skip in "oO" and re.search(r"env", a, re.I):
                raise Deny(R_ENV + ": ps -o %s" % a)
            numeric_sel = numeric_sel or (skip in "pq" and bool(re.fullmatch(r"[0-9, ]+", a)))
            skip = None
        elif a.startswith("-") and not a.startswith("--") and len(a) > 1 and a[-1] in "oOpqtugGUCs":
            skip = a[-1]
            env_flag = env_flag or "E" in a
        elif a.startswith("-") and not a.startswith("--") and "E" in a:
            env_flag = True
        elif re.fullmatch(r"[A-Za-z]{1,10}", a) and "e" in a:
            env_flag = True
        elif re.fullmatch(r"[0-9]+", a):
            numeric_sel = True
    named = re.search(r"server\.ts|cockpit", script)
    if env_flag and (named or not numeric_sel):
        raise Deny(R_ENV + ": ps with an environment flag" + ("" if named else " and no numeric pid"))


def check_proc_environ(words):
    text = " ".join(re.sub(r"\x01.*?\x02", "*", w, flags=re.S) for w in words)
    for m in re.finditer(r"/proc/([^/\s]*)/environ", text):
        if m.group(1) != "self":
            raise Deny(R_ENV + ": /proc/%s/environ (any pid but self may be the server)" % m.group(1))


def decoders_in(text):
    if DECODERS.search(text):
        ask(R_OBF + " (decoded/escaped text is executed)")
