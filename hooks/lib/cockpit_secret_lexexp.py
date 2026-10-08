"""Expansion helpers for the cockpit-secret-guard lexer: ANSI-C/printf escapes,
${...} parameter expansion (literal subset) and bash brace expansion.

Quoted braces/commas are masked to private chars (\\x03 { / \\x04 } / \\x05 ,) while a
word is being built, so only UNQUOTED braces expand, exactly like the shell."""
import re

MASK = str.maketrans({"{": "\x03", "}": "\x04", ",": "\x05"})
UNMASK = str.maketrans({"\x03": "{", "\x04": "}", "\x05": ","})
SIMPLE = {"a": 7, "b": 8, "e": 27, "E": 27, "f": 12, "n": 10, "r": 13, "t": 9, "v": 11,
          "\\": 92, "'": 39, '"': 34, "?": 63}
MAX_ALTERNATIVES = 256


def decode_ansic(s):
    """Decode $'...' / printf escapes (\\xHH, \\NNN, \\uHHHH, \\n ...); unknown escapes stay literal."""
    out, i, n = bytearray(), 0, len(s)
    while i < n:
        c = s[i]
        if c != "\\" or i + 1 >= n:
            out += c.encode("utf-8", "replace")
            i += 1
            continue
        d = s[i + 1]
        m = re.compile(r"[0-7]{1,3}").match(s, i + 1)
        if d in "xuU" and re.compile(r"[0-9a-fA-F]{1,%d}" % {"x": 2, "u": 4, "U": 8}[d]).match(s, i + 2):
            h = re.compile(r"[0-9a-fA-F]{1,%d}" % {"x": 2, "u": 4, "U": 8}[d]).match(s, i + 2)
            v = int(h.group(0), 16)
            out += bytes([v]) if d == "x" else chr(v).encode("utf-8", "replace")
            i = h.end()
        elif m:
            out.append(int(m.group(0), 8) & 255)
            i = m.end()
        elif d in SIMPLE:
            out.append(SIMPLE[d])
            i += 2
        else:
            out += ("\\" + d).encode("utf-8", "replace")
            i += 2
    return out.decode("utf-8", "replace")


def decode_twice(s):
    """Escape decoding applied up to twice (printf '%b' / echo -e double-decode)."""
    once = decode_ansic(s)
    return decode_ansic(once) if once != s else once


def _strip(val, pat, front, longest):
    if re.search(r"[*?\[]", pat):
        return None
    if front:
        return val[len(pat):] if val.startswith(pat) else val
    return val[:len(val) - len(pat)] if pat and val.endswith(pat) else val


def expand_param(expr, vars_):
    """Value of ${expr} for the literal subset of bash, or None when it cannot be resolved."""
    if expr.startswith("!"):
        inner = vars_.get(expr[1:])
        return vars_.get(inner) if inner is not None else None
    if expr.startswith("#"):
        v = vars_.get(expr[1:])
        return None if v is None else str(len(v))
    m = re.match(r"([A-Za-z_][A-Za-z0-9_]*)(.*)$", expr, re.S)
    if not m:
        return None
    name, op = m.group(1), m.group(2)
    val = vars_.get(name)
    if op == "":
        return val
    colon = op.startswith(":") and len(op) > 1 and op[1] in "-=+?"
    kind = op[1] if colon else op[0]
    arg = op[2:] if colon else op[1:]
    unset = val is None or (colon and val == "")
    if kind in "-=":
        return arg if unset else val
    if kind == "+":
        return "" if unset else arg
    if kind == "?":
        return None if unset else val
    if val is None:
        return None
    if op.startswith("##") or op.startswith("%%"):
        return _strip(val, op[2:], op[0] == "#", True)
    if op[0] in "#%":
        return _strip(val, op[1:], op[0] == "#", False)
    if op[0] == "/":
        g = op.lstrip("/").split("/", 1)
        return val.replace(g[0], g[1] if len(g) > 1 else "") if op.startswith("//") else val.replace(
            g[0], g[1] if len(g) > 1 else "", 1)
    if op[0] == ":":
        g = re.fullmatch(r":\s*(-?\d+)(?::\s*(-?\d+))?", op)
        if not g:
            return None
        a = int(g.group(1))
        a = a if a >= 0 else max(len(val) + a, 0)
        return val[a:] if g.group(2) is None else val[a:a + int(g.group(2))]
    if op in ("^^", "^"):
        return val.upper()
    if op in (",,", ","):
        return val.lower()
    return None


def _split_top(body):
    parts, depth, cur = [], 0, ""
    for ch in body:
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    return parts + [cur]


def brace_expand(w, budget=None):
    """Bash brace expansion of unquoted {a,b} and {1..3}; raises ValueError when too large."""
    budget = [MAX_ALTERNATIVES] if budget is None else budget
    i = w.find("{")
    while i >= 0:
        depth, j = 0, i
        while j < len(w):
            depth += (w[j] == "{") - (w[j] == "}")
            if depth == 0:
                break
            j += 1
        if j >= len(w):
            i = w.find("{", i + 1)
            continue
        body = w[i + 1:j]
        alts = _split_top(body)
        seq = re.fullmatch(r"(-?\d+)\.\.(-?\d+)|([a-zA-Z])\.\.([a-zA-Z])", body)
        if len(alts) < 2 and seq:
            if seq.group(1):
                a, b = int(seq.group(1)), int(seq.group(2))
                alts = [str(k) for k in range(a, b + (1 if b >= a else -1), 1 if b >= a else -1)][:16]
            else:
                a, b = ord(seq.group(3)), ord(seq.group(4))
                alts = [chr(k) for k in range(a, b + (1 if b >= a else -1), 1 if b >= a else -1)][:16]
        if len(alts) >= 2:
            out = []
            for alt in alts:
                out.extend(brace_expand(w[:i] + alt + w[j + 1:], budget))
                if len(out) > budget[0]:
                    raise ValueError("brace expansion too large to inspect")
            return out
        i = w.find("{", i + 1)
    return [w]
