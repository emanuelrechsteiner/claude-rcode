"""Classifier for hooks/governing-path-guard.sh (IMP-239).

Usage: governing-path-classify.py <live-dir> < PreToolUse-JSON
Prints, one per line (tab separated):
  HIT <path-or-description>   a governed live-install write was found
  PARSEFAIL <reason>          Bash parse failed; a HIT line may follow (raw scan)
Nothing printed = no governed write.

Known limits (fence against ACCIDENTAL writes by an unattended routine, not a
wall against deliberate evasion): rm/ln/dd/truncate/touch/chmod, rsync/ditto/
patch/perl -pi/awk -i/curl -o/wget -O, python/node writes, variables other
than ~ and $HOME, xargs/eval/backticks, mcp filesystem/serena write tools.
"""
import json
import os
import re
import shlex
import sys

HOME = os.environ.get("HOME", "")
DIRS = {"agents", "skills", "commands", "hooks", "rcode", "scheduled-tasks",
        "scripts", "cockpit", "output-styles", "templates"}
FILES = {"claude.md", "settings.json", "settings.framework.json", "settings.local.json"}
PFX = tuple(d + "/" for d in DIRS)
SEP = {";", ";;", "&&", "||", "|", "|&", "&", "(", ")"}
KW = {"do", "then", "else", "elif", "{", "}", "!", "if", "while", "until", "time"}
WRAP = {"sudo", "command", "env", "nohup", "exec", "builtin"}
ARGOPT = {"-u", "-g", "-h", "-p", "-C", "-D", "-r", "-t", "-U", "-S"}
GITW = {"checkout", "restore", "apply", "am", "merge", "pull", "stash", "reset", "cherry-pick", "rebase"}
PUNCT = re.compile(r"&>>|\|\||&&|;;|\|&|>>|&>|>\||>&|<<<|<<|\(|\)|;|\||&|>|<")
REDIR = re.compile(r"^(>>?|>\||&>>?|>&)$")
HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1[^\n]*\n(.*?)\n[ \t]*\2[ \t]*(?=\n|$)", re.S)

def norm(p, base):
    """Absolute, ~/$HOME-expanded, collapsed path with the existing parent realpath'd."""
    p = p.replace("${HOME}", HOME).replace("$HOME", HOME)
    if p == "~" or p.startswith("~/"):
        p = HOME + p[1:]
    if not os.path.isabs(p):
        p = os.path.join(base, p)
    p = re.sub(r"^/+", "/", os.path.normpath(p))
    parent, name = os.path.split(p)
    existing, tail = parent, []
    while existing != "/" and not os.path.exists(existing):
        existing, t = os.path.split(existing)
        tail.insert(0, t)
    return os.path.join(os.path.realpath(existing), *tail, name)

LIVE_RAW = re.sub(r"^/+", "/", os.path.normpath(sys.argv[1].replace("$HOME", HOME)))
LIVE = os.path.realpath(LIVE_RAW)
LIVE_L = LIVE.lower()

def in_live(p):
    return (p.lower() + "/").startswith(LIVE_L + "/")

def governed(p):
    lp = p.lower()
    if not lp.startswith(LIVE_L + "/"):
        return False
    rel = lp[len(LIVE_L) + 1:]
    if rel in DIRS or rel in FILES or rel == "rules" or rel.startswith(PFX):
        return True
    return rel.startswith("rules/") and rel.endswith(".md") and not rel.endswith(".local.md")

def clean(cmd):
    """Drop comments, turn unquoted newlines into ';' and join line continuations."""
    out, q, i, prev = [], None, 0, " "
    while i < len(cmd):
        c = cmd[i]
        if q:
            out.append(c)
            if c == "\\" and q == '"' and i + 1 < len(cmd):
                out.append(cmd[i + 1]); i += 1
            elif c == q:
                q = None
        elif c == "\\" and i + 1 < len(cmd):
            out.append(" " if cmd[i + 1] == "\n" else c + cmd[i + 1]); i += 1
        elif c in "'\"":
            q = c; out.append(c)
        elif c == "#" and prev in " \t\n;|&()":
            j = cmd.find("\n", i)
            i = len(cmd) if j < 0 else j; continue
        elif c == "\n":
            out.append(" ; ")
        else:
            out.append(c)
        prev = c; i += 1
    return "".join(out)

def tokens(cmd):
    lx = shlex.shlex(cmd, posix=True, punctuation_chars=True)
    lx.whitespace_split, lx.commenters = True, ""
    res = []
    for t in lx:
        if t and all(c in "();<>|&" for c in t):
            res += PUNCT.findall(t)
        else:
            res.append(t)
    return res

def strip_head(words):
    i = 0
    while i < len(words):
        w, b = words[i], os.path.basename(words[i])
        if re.match(r"^\w+=", w) or w in KW:
            i += 1
        elif b in WRAP:
            i += 1
            while i < len(words) and (words[i].startswith("-") or re.match(r"^\w+=", words[i])):
                opt = words[i]; i += 1
                if b in ("sudo", "env") and opt in ARGOPT and i < len(words):
                    i += 1
        else:
            break
    return words[i:]

def redirects(words, base, out):
    kept, i = [], 0
    while i < len(words):
        w = words[i]
        nxt = words[i + 1] if i + 1 < len(words) else ""
        if w.isdigit() and (nxt.startswith(">") or nxt.startswith("<") or nxt.startswith("&>")):
            i += 1; continue
        if REDIR.match(w) or w in ("<", "<<", "<<<"):
            if REDIR.match(w) and nxt and not (nxt.isdigit() or nxt == "-"):
                out.append(norm(nxt, base))
            i += 2; continue
        kept.append(w); i += 1
    return kept

def positional(args):
    """Non-flag args, skipping the value of -t / --target-directory."""
    res, skip = [], False
    for a in args:
        if skip:
            skip = False
        elif a in ("-t", "--target-directory"):
            skip = True
        elif not a.startswith("-"):
            res.append(a)
    return res

def git_check(args, base, hits):
    cpath, i, sub = None, 0, None
    while i < len(args):
        a = args[i]
        if a == "-C" and i + 1 < len(args):
            cpath = args[i + 1]; i += 2
        elif a in ("-c", "--git-dir", "--work-tree", "--namespace", "--exec-path") and i + 1 < len(args):
            i += 2
        elif a.startswith("-"):
            i += 1
        else:
            sub = a; break
    where = norm(cpath, base) if cpath else norm(base, "/")
    if sub in GITW and in_live(where):
        hits.append("git -C %s %s" % (where, sub))

def scan(cmd, base, out, hits, depth=0):
    bodies = []

    def grab(m):
        pre = m.string[:m.start()].rsplit("\n", 1)[-1]
        if re.search(r"\b(ba|z)?sh\b", pre):
            bodies.append(m.group(3))
        return m.string[m.start():m.start(3) - 1].rstrip("\n")

    cmd = HEREDOC.sub(grab, cmd)
    for body in bodies:
        if depth < 3:
            scan(body, base, out, hits, depth + 1)
    segs, seg = [], []
    for t in tokens(clean(cmd)):
        if t in SEP:
            segs.append(seg); seg = []
        else:
            seg.append(t)
    segs.append(seg)
    for words in segs:
        words = strip_head(redirects(words, base, out))
        if not words:
            continue
        head, args = os.path.basename(words[0]), words[1:]
        plain = positional(args)
        if head == "cd" and plain:
            base = norm(plain[0], base)
        elif head == "git":
            git_check(args, base, hits)
        elif head in ("sh", "bash", "zsh") and depth < 3:
            for k, a in enumerate(args):
                if re.match(r"^-[a-zA-Z]*c[a-zA-Z]*$", a) and k + 1 < len(args):
                    scan(args[k + 1], base, out, hits, depth + 1); break
        elif head == "tee":
            out += [norm(a, base) for a in plain]
        elif head == "sed" and any(re.match(r"^(-[^-]*i|--in-place)", a) for a in args):
            out += [norm(a, base) for a in plain]
        elif head in ("cp", "mv", "install") and plain:
            tdir = next((args[k + 1] for k, a in enumerate(args) if a in ("-t", "--target-directory") and k + 1 < len(args)), None)
            tdir = tdir or next((a.split("=", 1)[1] for a in args if a.startswith("--target-directory=")), None)
            srcs = plain if tdir else plain[:-1]
            tgt = norm(tdir if tdir else plain[-1], base)
            out.append(tgt)
            out += [os.path.join(tgt, os.path.basename(s.rstrip("/"))) for s in srcs]
            if head == "mv":
                out += [norm(s, base) for s in srcs]

def raw_hit(cmd):
    c = cmd.lower().replace("${home}", HOME.lower()).replace("$home", HOME.lower())
    c = c.replace("~/", HOME.lower() + "/")
    names = r"(?:rules/|agents|skills|commands|hooks|rcode|scheduled-tasks|scripts|cockpit|output-styles|templates|claude\.md|settings)"
    for v in {LIVE_L, LIVE_RAW.lower()}:
        m = re.search(re.escape(v) + "/" + names, c)
        if m:
            return m.group(0)
    return None

def main():
    d = json.load(sys.stdin)
    ti = d.get("tool_input") or {}
    cwd = d.get("cwd") or os.getcwd()
    out, hits = [], []
    if ti.get("file_path"):
        out.append(norm(ti["file_path"], cwd))
    elif ti.get("command"):
        try:
            scan(ti["command"], cwd, out, hits)
        except Exception as e:  # parse failure must fail closed, see raw scan below
            print("PARSEFAIL\t%s: %s" % (type(e).__name__, e))
            raw = raw_hit(ti["command"])
            if raw:
                print("HIT\t" + raw)
            return
    for p in out:
        if governed(p):
            print("HIT\t" + p); return
    if hits:
        print("HIT\t" + hits[0])

main()
