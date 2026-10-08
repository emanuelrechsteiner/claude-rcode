"""Tiny shell lexer for cockpit-secret-guard.sh (not a full shell parser).

parse(script, state, depth) appends simple commands to state.cmds. Each command is
a list of words with quoting and the LITERAL part of expansion resolved, so a rule
sees what the shell would run: "t'm'ux", $'t\\x6dux', $"tmux", {tmux,capture-pane},
${T:-tmux}, ${!x}, $T with T="tmux capture-pane" (word-split), tmux${IFS}capture-pane
and $(echo tmux) all become real words.

Also: redirections are kept apart from the argv (Cmd.redirs, here-strings feed
Cmd.heredoc), a pipeline remembers its upstream commands (Cmd.upstream), assignments
incl. export/declare/for-in/read feed state.vars, functions/aliases are unwrapped,
comments are dropped, heredoc bodies attach to the command that owns them. A substitution
whose output is not a literal stays as \\x01inner\\x02, an unresolved $VAR as \\x06$VAR.

What it does NOT do: command output, globbing, functions/aliases across tool calls,
script files. Documented limits, see the hook header.
"""
import re

import cockpit_secret_lexexp as ex
from cockpit_secret_lexbase import ASSIGN, Builder, Cmd, State, literal_output, matching, Q  # noqa: F401

VARNAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
REDIR = re.compile(r"&>>|&>|<<<|<>|>>|>\||>&|<&|>|<")
SPECIAL = re.compile(r"[0-9@*?$!#-]")
MAX_DEPTH = 8


def dquote(b, s, i):
    """Assemble a "..." string starting at s[i]; returns the index after the closing quote."""
    n = len(s)
    b.add("", True)
    i += 1
    while i < n and s[i] != '"':
        d = s[i]
        if d == "\\" and i + 1 < n:
            b.add((s[i + 1] if s[i + 1] in '"\\$`' else "\\" + s[i + 1]).translate(Q), True)
            i += 2
        elif d == "$" and s[i + 1:i + 2] == "(":
            j = matching(s, i + 1)
            b.sub(s[i + 2:j], True)
            i = j + 1
        elif d == "`":
            j = s.find("`", i + 1)
            j = n if j < 0 else j
            b.sub(s[i + 1:j], True)
            i = j + 1
        elif d == "$" and s[i + 1:i + 2] == "{":
            j = matching(s, i + 1, "{", "}")
            b.var(s[i + 2:j], "${" + s[i + 2:j] + "}", True)
            i = j + 1
        elif d == "$" and (m := VARNAME.match(s, i + 1)):
            b.var(m.group(0), "$" + m.group(0), True)
            i = m.end()
        elif d == "$" and SPECIAL.match(s[i + 1:i + 2] or " "):
            b.var(s[i + 1], "$" + s[i + 1], True)
            i += 2
        else:
            b.add(d.translate(Q), True)
            i += 1
    return i + 1


def dollar(b, s, i):
    """Unquoted '$' at s[i]; returns the new index."""
    n, nxt = len(s), s[i + 1:i + 2]
    if s.startswith("$((", i):
        b.add("0")
        return matching(s, i + 1) + 1
    if nxt == "(":
        j = matching(s, i + 1)
        b.sub(s[i + 2:j], False)
        return j + 1
    if nxt == "'":
        j = i + 2
        while j < n and s[j] != "'":
            j += 2 if s[j] == "\\" else 1
        b.add(ex.decode_ansic(s[i + 2:j]).translate(Q), True)
        return j + 1
    if nxt == '"':
        return i + 1
    if nxt == "{":
        j = matching(s, i + 1, "{", "}")
        b.var(s[i + 2:j], "${" + s[i + 2:j] + "}", False)
        return j + 1
    if m := VARNAME.match(s, i + 1):
        b.var(m.group(0), "$" + m.group(0), False)
        return m.end()
    if SPECIAL.match(nxt or " "):
        b.var(nxt, "$" + nxt, False)
        return i + 2
    b.add("$")
    return i + 1


def heredoc_bodies(s, i, tags):
    """Consume the bodies of pending heredocs starting at s[i]; returns (new index, bodies)."""
    n, bodies = len(s), []
    for tag in tags:
        body = []
        while i < n:
            j = s.find("\n", i)
            j = n if j < 0 else j
            line = s[i:j]
            i = min(j + 1, n)
            if line.strip() == tag:
                break
            body.append(line)
        bodies.append("\n".join(body))
    return i, bodies


def parse(s, st, depth=0):
    if depth > MAX_DEPTH:
        raise ValueError("command nesting too deep to inspect")
    s = s.replace("\\\n", "")
    n, i, pend = len(s), 0, []
    b = Builder(st, depth, parse)
    while i < n:
        c = s[i]
        if c == "\\":
            if i + 1 < n:
                b.add(s[i + 1].translate(Q), True)
            i += 2
        elif c == "'":
            j = s.find("'", i + 1)
            j = n if j < 0 else j
            b.add(s[i + 1:j].translate(Q), True)
            i = j + 1
        elif c == '"':
            i = dquote(b, s, i)
        elif c == "`":
            j = s.find("`", i + 1)
            j = n if j < 0 else j
            b.sub(s[i + 1:j], False)
            i = j + 1
        elif c == "$":
            i = dollar(b, s, i)
        elif c in "<>" and s[i + 1:i + 2] == "(":
            j = matching(s, i + 1)
            b.sub(s[i + 2:j], False, True)
            i = j + 1
        elif c == "<" and s.startswith("<<", i) and not s.startswith("<<<", i) and HEREDOC.match(s, i):
            m = HEREDOC.match(s, i)
            b.endword()
            pend.append(m.group(2))
            i = m.end()
        elif c in "<>&" and (m := REDIR.match(s, i)):
            if b.cur is not None and not b.cur[0] and "".join(b.cur[1]).isdigit():
                b.cur = None
            b.endword()
            b.rop = m.group(0)
            i = m.end()
        elif c == "#" and b.cur is None:
            j = s.find("\n", i)
            i = n if j < 0 else j
        elif c in " \t":
            b.endword()
            i += 1
        elif c == "\n":
            i, bodies = heredoc_bodies(s, i + 1, pend)
            b.bodies.extend(bodies)
            pend = []
            b.flush()
        elif c == "|" and s[i + 1:i + 2] != "|":
            b.flush("|")
            i += 2 if s[i + 1:i + 2] == "&" else 1
        elif c in ";|()&":
            b.flush()
            i += 1
        else:
            b.add(c)
            i += 1
    b.flush()
