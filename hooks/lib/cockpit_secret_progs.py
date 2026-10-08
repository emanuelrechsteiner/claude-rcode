"""Program-name classification for cockpit-secret-guard: basename normalisation (case, glob,
zsh =cmd), the shell/data-only/wrapper sets and which later words of a command run as programs."""
import fnmatch
import posixpath
import re

import cockpit_secret_exec as xe
from cockpit_secret_common import DYN, SUB_OPEN

SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "fish", "ash", "csh", "tcsh"}
DATA_PROGS = {"echo", "printf", "grep", "egrep", "fgrep", "zgrep", "rg", "ag", "ack", "git", "gh", "man", "which",
              "type", "whereis", "whatis", "brew", "apt", "apt-get", "dpkg", "pip", "pip3", "cargo", "gem", "cat",
              "head", "tail", "less", "more", "bat", "wc", "ls", "stat", "file", "diff", "cmp", "sort", "uniq",
              "cut", "tr", "touch", "mkdir", "rm", "cp", "mv", "chmod", "test", "[", "cd", "pushd", "popd",
              "export", "unset", "true", "false", "sleep", "date", "pwd", "realpath", "dirname", "basename",
              "du", "df", "alias", "jq"}
LATER = SHELLS | xe.PID_TOOLS | xe.DEBUGGERS | xe.AWKISH | set(xe.READBACK) | {
    "tmux", "eval", "ps", "find", "xargs", "parallel", "osascript"}
GLOB_TARGETS = ("tmux", "bash", "zsh", "sh", "dash", "ksh", "python3", "python", "node", "perl", "ruby", "php",
                "osascript", "ps", "find", "xargs", "screen", "zellij")
CMD_END = (";", "+")


def pname(w):
    """Lower-cased program basename; a glob word resolves to the first program it could expand to."""
    w = w.replace(DYN, "")
    if SUB_OPEN in w:
        return "tmux" if "tmux" in w.lower() else ""
    if len(w) > 1 and w[0] == "=":
        w = w[1:]   # zsh =cmd expands to the full path of cmd
    base = posixpath.basename(w.rstrip("/")).lower()
    if re.search(r"[*?\[]", base) and len(re.sub(r"[*?\[\]]", "", base)) >= (1 if "/" in w else 2):
        for cand in GLOB_TARGETS:
            if fnmatch.fnmatchcase(cand, base):
                return cand
    return base


def programs(words, i, base):
    """(index, name) of every word that runs as a program: the first one, wrapper targets after it
    (up to the first data-only program, whose remaining words are just its arguments), find -exec."""
    starts = [i] + [k + 1 for k, w in enumerate(words) if base == "find" and w in ("-exec", "-execdir", "-ok", "-okdir")
                    and k + 1 < len(words)]
    out = []
    for s in starts:
        b = pname(words[s])
        out.append((s, b))
        for k in range(s + 1, len(words)):
            n = pname(words[k])
            if b in DATA_PROGS or n in DATA_PROGS or words[k] in CMD_END:
                break
            if n in LATER or xe.is_interp(n):
                out.append((k, n))
    return out
