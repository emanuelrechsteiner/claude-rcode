"""Per-command rules that need the pipeline/redirect context: shells and `source` (stdin,
here-strings, process substitution, -c text, positional args), find -exec, recursive
search/copy/link of the cockpit directory or its ancestors, xargs fed from a listing."""
import fnmatch
import re

import cockpit_secret_lex as lex
from cockpit_secret_common import DENY_WORDS, R_FILE, R_TMUX, SUB_CLOSE, SUB_OPEN, Deny, ask
from cockpit_secret_exec import decoders_in
from cockpit_secret_lexexp import decode_twice
from cockpit_secret_paths import (ALWAYS_RECURSIVE, NAMES, RECURSIVE_GREP, ancestor_hit, dir_hit,
                                  recursive_kind)

TRANSFER = {"ln", "cp", "mv", "rsync", "tar", "zip", "7z", "7za", "ditto", "scp", "cpio", "pax", "bsdtar",
            "gtar", "install", "mount", "hdiutil"}
DEST_LAST = {"cp", "mv", "rsync", "ln", "install", "scp", "ditto"}
R_ANC = "recursive search/copy of a directory that contains the Cockpit runtime files (web-* launch token)"
STDIN_OPERANDS = ("/dev/stdin", "-", "/proc/self/fd/0")


class Ctx:
    """scan(text, depth) re-inspects nested shell text; via_stdin: xargs/parallel feed the arguments."""

    def __init__(self, scan_fn, depth, via_stdin):
        self.scan, self.depth, self.via_stdin = scan_fn, depth, via_stdin


def stdin_texts(cmd):
    """Text that an upstream pipe stage, here-string or heredoc feeds to this command's stdin."""
    out = [cmd.heredoc] if cmd.heredoc else []
    for u in cmd.upstream:
        out.append(" ".join(u.words[1:]) + "\n" + u.heredoc)
    return [t for t in out if t.strip()]


def marker_payloads(arg, ctx, st):
    """Literal output of a <(echo ...) / "$(...)" body, scanned as shell text; decoders ask."""
    for body in re.findall(SUB_OPEN + "(.*?)" + SUB_CLOSE, arg, re.S):
        tmp = lex.State(st)
        lex.parse(body, tmp, ctx.depth + 1)
        lit = lex.literal_output(tmp.cmds, ctx.depth + 2)
        if lit is not None:
            ctx.scan(lit, ctx.depth + 1)
    if SUB_OPEN in arg:
        decoders_in(arg)


def check_shell(args, cmd, ctx, st):
    operands, has_c, k = [], False, 0
    while k < len(args):
        a = args[k]
        if a.startswith("-") and not a.startswith("--") and "c" in a[1:]:
            has_c = True
            if k + 1 < len(args):
                ctx.scan(args[k + 1], ctx.depth + 1)
                marker_payloads(args[k + 1], ctx, st)
                if any(DENY_WORDS.fullmatch(p) for p in args[k + 2:]):
                    raise Deny(R_TMUX + ": a capture subcommand is passed as a positional argument ($1...)")
            k += 1
        elif not a.startswith("-"):
            operands.append(a)
        k += 1
    for a in args:
        if re.search(r"\s", a) or SUB_OPEN in a:
            ctx.scan(a, ctx.depth + 1)
            marker_payloads(a, ctx, st)
    if cmd.heredoc:
        ctx.scan(cmd.heredoc, ctx.depth + 1)
    if not has_c and (not operands or operands[0] in STDIN_OPERANDS):
        for t in stdin_texts(cmd):
            for variant in {t, decode_twice(t)}:
                ctx.scan(variant, ctx.depth + 1)
            decoders_in(t)
        decoders_in(" ".join(w for u in cmd.upstream for w in u.words))


def check_find(args, st):
    starts = []
    for a in args:
        if a.startswith(("-", "(", "!")):
            break
        starts.append(a)
    names = [args[j + 1].casefold() for j, a in enumerate(args[:-1]) if a in ("-name", "-iname", "-path", "-ipath")]
    runs = any(a in ("-exec", "-execdir", "-ok", "-okdir") for a in args)
    if runs and (not names or any(fnmatch.fnmatchcase(n, nm) for n in NAMES for nm in names)):
        for p in starts:
            if dir_hit(p, st.cwd):
                raise Deny(R_FILE + ": find -exec over the Cockpit directory")
            if ancestor_hit(p, st.cwd):
                ask(R_ANC)


def check_dirs(base, args, cmd, st):
    """Directory-level access: recursion, copy/link/archive of the cockpit dir or one of its ancestors."""
    ops = [w for w in args if not w.startswith("-")]
    dest = ops[-1] if ops and base in DEST_LAST else None
    dirs = [w for w in args if dir_hit(w, st.cwd) and w != dest]
    ancs = [w for w in args if ancestor_hit(w, st.cwd) and w != dest]
    rec = base in RECURSIVE_GREP | ALWAYS_RECURSIVE and recursive_kind(base, args)
    if dirs:
        names = [w for w in ops if w not in dirs]
        if any(fnmatch.fnmatchcase(n, w.casefold()) for n in NAMES for w in names) or any(
                w.casefold().startswith("web-") for w in names):
            raise Deny(R_FILE + ": Cockpit directory searched for web-*")
        if rec or base in TRANSFER:
            raise Deny(R_FILE + ": recursive search/copy/link of the whole Cockpit directory")
    if ancs and (rec or base in TRANSFER):
        ask(R_ANC)
    if rec and st.cwd is not None and len(ops) <= 1:
        if dir_hit(st.cwd):
            raise Deny(R_FILE + ": recursive search in the Cockpit directory")
        if ancestor_hit(st.cwd):
            ask(R_ANC)
    if base in ("xargs", "parallel"):
        if any(dir_hit(w, st.cwd) for u in cmd.upstream for w in u.words[1:]):
            raise Deny(R_FILE + ": xargs fed from a listing of the Cockpit directory")
        if st.cwd is not None and dir_hit(st.cwd):
            raise Deny(R_FILE + ": xargs inside the Cockpit directory")
