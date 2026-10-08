"""Minimal shell lexer for hooks/git-bypass-guard.sh (IMP-240).

Splits a command string into simple commands at command-position separators,
removes quoting (incl. $'..'), skips here-doc bodies, and collects $(...) /
backtick bodies as nested sources. Not a full shell parser: a fence against
accidental bypass, not a wall against deliberate evasion.
"""
import re

HEREDOC = re.compile(r"""(-?)[ \t]*['"]?([A-Za-z_][A-Za-z0-9_]*)['"]?""")


def read_heredoc(s, i, tag, strip):
    """Return (body, index after the terminator line) for a heredoc starting at s[i]."""
    body, n = [], len(s)
    while i < n:
        j = s.find("\n", i)
        j = n if j < 0 else j
        line = s[i:j]
        i = j + 1
        if (line.lstrip("\t") if strip else line).strip() == tag:
            break
        body.append(line)
    return "\n".join(body), i


def find_close(s, i):
    """Index of the ')' closing a $( opened before s[i]; heredoc bodies are skipped."""
    depth, q, tags, n = 1, None, [], len(s)
    while i < n:
        c = s[i]
        if q:
            if c == q:
                q = None
            elif c == "\\" and q == '"':
                i += 1
        elif c == "\n" and tags:
            for tag, strip in tags:
                _, i = read_heredoc(s, i + 1, tag, strip)
                i -= 1
            tags = []
        elif s[i:i + 2] == "<<" and s[i:i + 3] != "<<<":
            m = HEREDOC.match(s, i + 2)
            if m:
                tags.append((m.group(2), bool(m.group(1))))
                i = m.end() - 1
            else:
                i += 1
        elif c in "'\"":
            q = c
        elif c == "\\":
            i += 1
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return n


def ansi_c(raw):
    try:
        return raw.encode("latin-1", "backslashreplace").decode("unicode_escape")
    except (UnicodeError, ValueError):
        return raw


def new_cmd(prev=None):
    return {"words": [], "nested": [], "heredocs": [], "herestrings": [], "piped": prev}


def lex(s):
    cmds, cur, buf, inword, pending, hs = [], new_cmd(), [], False, [], [False]
    i, n = 0, len(s)

    def flush():
        nonlocal buf, inword
        if inword:
            cur["herestrings" if hs[0] else "words"].append("".join(buf))
            hs[0] = False
        buf, inword = [], False

    def endcmd(pipe=False):
        nonlocal cur
        flush()
        hs[0] = False
        prev = cur
        if prev["words"]:
            cmds.append(prev)
        cur = new_cmd(prev if (pipe and prev["words"]) else None)

    def sub(end, start):
        nonlocal i, inword
        cur["nested"].append(s[start:end])
        buf.append("$SUB")
        inword = True
        i = end + 1

    while i < n:
        c = s[i]
        if c in " \t":
            flush(); i += 1
        elif c == "\n":
            endcmd(); i += 1
            for tag, strip, obj in pending:
                body, i = read_heredoc(s, i, tag, strip)
                obj["heredocs"].append(body)
            pending = []
        elif c == "#" and not inword:
            j = s.find("\n", i); i = n if j < 0 else j
        elif c == "\\":
            if i + 1 < n and s[i + 1] != "\n":
                buf.append(s[i + 1]); inword = True
            i += 2
        elif c == "'":
            j = s.find("'", i + 1); j = n if j < 0 else j
            buf.append(s[i + 1:j]); inword = True; i = j + 1
        elif s[i:i + 2] == "$'":
            j = i + 2
            while j < n and s[j] != "'":
                j += 2 if s[j] == "\\" else 1
            buf.append(ansi_c(s[i + 2:j])); inword = True; i = j + 1
        elif c == '"':
            i += 1; inword = True
            while i < n and s[i] != '"':
                if s[i] == "\\" and i + 1 < n:
                    buf.append(s[i + 1]); i += 2
                elif s[i:i + 2] == "$(":
                    sub(find_close(s, i + 2), i + 2)
                elif s[i] == "`":
                    j = s.find("`", i + 1); sub(n if j < 0 else j, i + 1)
                else:
                    buf.append(s[i]); i += 1
            i += 1
        elif s[i:i + 2] == "$(":
            sub(find_close(s, i + 2), i + 2)
        elif c == "`":
            j = s.find("`", i + 1); sub(n if j < 0 else j, i + 1)
        elif s[i:i + 3] == "<<<":
            flush(); hs[0] = True; i += 3
        elif s[i:i + 2] == "<<":
            m = HEREDOC.match(s, i + 2)
            if m:
                pending.append((m.group(2), bool(m.group(1)), cur)); i = m.end()
            else:
                i += 2
        elif c == "&" and inword and buf and buf[-1][-1:] in "<>":
            buf.append(c); i += 1
        elif c in ";|&":
            if s[i:i + 2] in ("&&", "||"):
                endcmd(); i += 2
            else:
                endcmd(pipe=(c == "|")); i += 1
        elif c in "()":
            endcmd(); i += 1
        else:
            buf.append(c); inword = True; i += 1
    endcmd()
    return cmds
