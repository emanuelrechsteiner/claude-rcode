"""Lexer building blocks for cockpit-secret-guard: command/state records and the word builder
(quoting-aware word assembly, brace/word-split expansion, variable resolution, command flush)."""
import re

import cockpit_secret_lexexp as ex
from cockpit_secret_common import DYN, SUB_CLOSE, SUB_OPEN

ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
LEAD_KEYWORDS = {"{", "}", "!", "if", "then", "else", "elif", "do", "while", "until", "fi", "done", "time", "coproc"}
DECL = {"export", "declare", "typeset", "local", "readonly"}
BUILDERS = {"read", "mapfile", "readarray"}   # commands that create variable values from data
Q = ex.MASK


class Cmd:
    def __init__(self, words, heredoc, redirs, upstream, level):
        self.words, self.heredoc, self.redirs = words, heredoc, redirs
        self.upstream, self.level = upstream, level


class State:
    def __init__(self, parent=None):
        self.vars = dict(parent.vars) if parent else {}
        self.aliases = dict(parent.aliases) if parent else {}
        self.cwd = parent.cwd if parent else None
        self.written = dict(parent.written) if parent else {}
        self.built = parent.built if parent else False
        self.cmds = []


def matching(s, i, open_c="(", close_c=")"):
    """Index of the bracket closing the one at s[i], quote-aware; len(s) if none."""
    depth, q = 0, None
    while i < len(s):
        c = s[i]
        if q:
            if c == "\\" and q == '"':
                i += 1
            elif c == q:
                q = None
        elif c in "'\"":
            q = c
        elif c == "\\":
            i += 1
        elif c == open_c:
            depth += 1
        elif c == close_c:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return len(s)


def literal_output(cmds, level):
    """Literal stdout of a substitution that is a single echo/printf, else None."""
    top = [c for c in cmds if c.level == level]
    if len(top) != 1 or top[0].redirs or not top[0].words:
        return None
    w = top[0].words
    if w[0] == "echo":
        flags = [a for a in w[1:] if re.fullmatch(r"-[neE]+", a)]
        rest = " ".join(a for a in w[1:] if a not in flags)
        return ex.decode_ansic(rest) if any("e" in f for f in flags) else rest
    if w[0] == "printf" and len(w) > 1 and w[1] != "-v":
        out = ex.decode_ansic(w[1])
        for a in w[2:]:
            out = re.sub(r"%[sb]", lambda _m, a=a: a, out, count=1)
        return out
    return None


class Builder:
    """Mutable state of one parse() call: the word being assembled and the command being collected."""

    def __init__(self, st, depth, parse_fn):
        self.st, self.depth, self.parse_fn = st, depth, parse_fn
        self.words, self.cur, self.bodies, self.redirs, self.chain = [], None, [], [], []
        self.rop = None

    def add(self, t, quoted=False):
        if self.cur is None:
            self.cur = [False, []]
        self.cur[0] = self.cur[0] or quoted
        self.cur[1].append(t)

    def endword(self):
        if self.cur is None:
            return
        text, quoted, self.cur = "".join(self.cur[1]), self.cur[0], None
        if text == "" and not quoted:
            return
        outs = [x.translate(ex.UNMASK) for x in ex.brace_expand(text)] if "{" in text else [text.translate(ex.UNMASK)]
        if self.rop:
            self.redirs.append((self.rop, outs[0]))
            if self.rop == "<<<":
                self.bodies.append(outs[0])
            self.rop = None
        else:
            self.words.extend(outs)

    def split_add(self, text):
        """Unquoted expansion result: word-split on whitespace."""
        for k, piece in enumerate(re.split(r"(\s+)", text)):
            if k % 2:
                self.endword()
            elif piece:
                self.add(piece.translate(Q))

    def sub(self, inner, quoted, proc=False):
        st, n0 = self.st, len(self.st.cmds)
        self.parse_fn(inner, st, self.depth + 1)
        lit = None if proc else literal_output(st.cmds[n0:], self.depth + 2)
        if lit is None:
            self.add(SUB_OPEN + inner.translate(Q) + SUB_CLOSE, True)
        elif quoted:
            self.add(lit.translate(Q), True)
        else:
            self.split_add(lit)

    def var(self, name, text, quoted):
        if re.match(r"IFS($|[^A-Za-z0-9_])", name):
            self.add(" ", True) if quoted else self.endword()
            return
        if name == "" or re.fullmatch(r"[0-9@*]", name):
            self.add("")
            return
        if re.fullmatch(r"[?$!#-]", name):
            self.add("0")
            return
        vars_ = self.st.vars
        val = vars_.get(name) if name.isidentifier() else ex.expand_param(name, vars_)
        base = re.match(r"[A-Za-z_][A-Za-z0-9_]*", name.lstrip("!#"))
        if val is None:
            self.add(("" if name == "HOME" else DYN) + text, quoted)
            return
        if base and base.group(0) not in vars_ and not name.startswith("!"):
            self.add(DYN)   # value came from ${X:-default}: X may really be set to something else
        if quoted:
            self.add(val.translate(Q), True)
        else:
            self.split_add(val)

    def record(self, words):
        """Side effects of a finished simple command: for-in, assignments, export/alias, read here-string."""
        st = self.st
        if words and words[0] == "for" and "in" in words[:4] and words.index("in") + 1 < len(words):
            st.vars[words[1]] = words[words.index("in") + 1]
        k = 0
        while k < len(words) and ASSIGN.match(words[k]):
            name, _, val = words[k].partition("=")
            st.vars[name] = val
            k += 1
        if k < len(words) and words[k] in DECL | {"alias"}:
            for w in words[k + 1:]:
                if ASSIGN.match(w):
                    name, _, val = w.partition("=")
                    (st.aliases if words[k] == "alias" else st.vars)[name] = val
        if k < len(words) and (words[k] in BUILDERS or (words[k] == "printf" and "-v" in words)):
            st.built = True
        if k < len(words) and words[k] == "read" and self.bodies:
            names = [w for w in words[k + 1:] if not w.startswith("-")] or ["REPLY"]
            vals = (self.bodies[0].split("\n")[0]).split(None, len(names) - 1)
            for n, v in zip(names, vals + [""] * len(names)):
                st.vars[n] = v

    def flush(self, sep=";"):
        self.endword()
        self.rop = None
        words = self.words
        while words and (words[0] in LEAD_KEYWORDS or words[0] == "function"):
            if words[0] == "function":
                words = words[words.index("{") + 1:] if "{" in words else words[2:]
            else:
                words = words[1:]
        self.record(words)
        if words or self.redirs:
            c = Cmd(words, "\n".join(self.bodies), self.redirs, list(self.chain), self.depth + 1)
            self.st.cmds.append(c)
            if sep == "|":
                self.chain.append(c)
        if sep != "|":
            self.chain.clear()
        self.words, self.bodies, self.redirs = [], [], []
