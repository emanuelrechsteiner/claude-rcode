"""Cockpit runtime-file rules (rule B) as segment-wise path/glob matching, with home-agnostic,
case-insensitive (APFS) and Unicode-folded comparison; Read/Grep/Glob tool checks."""
import fnmatch
import functools
import os
import posixpath
import re
import unicodedata

from cockpit_secret_common import DYN, SUB_CLOSE, SUB_OPEN

NAMES = ("web-1.out", "web-1.pid", "web-abc.out", "web.out")
_real = [p.casefold() for p in os.path.expanduser("~").split("/") if p]
HOMES = [["h"], ["users", "x"], ["home", "x"], ["root"], ["var", "root"]] + ([_real] if _real else [])
FILES = [h + [".claude", "cockpit", n] for h in HOMES for n in NAMES]
COCKPIT_DIRS = [h + [".claude", "cockpit"] for h in HOMES]
ANCESTORS = HOMES + [h + [".claude"] for h in HOMES] + [[], ["users"], ["home"]]
LITERAL = re.compile(r"\.claude/cockpit/web-")
HOME_PREFIX = re.compile(r"(~[^/]*|\$home|\$\{home\})(?=/|$)")
DYN_PART = re.compile(DYN + r"(\$\{[^}]*\}|\$[A-Za-z_0-9]+)?|" + SUB_OPEN + r".*?" + SUB_CLOSE, re.S)
RECURSIVE_GREP = {"grep", "egrep", "fgrep", "ugrep"}
ALWAYS_RECURSIVE = {"rg", "ag", "ack"}


def fold(p):
    """Case/Unicode-folded text with dynamic parts as '*' (APFS is case- and normalization-insensitive)."""
    return unicodedata.normalize("NFKC", DYN_PART.sub("*", p)).casefold()


def split_path(p):
    """-> (anchor, segments): anchor is 'home' (~, ~user, $HOME), 'abs' or 'rel'."""
    p = re.sub(r"/+", "/", fold(p))
    m = HOME_PREFIX.match(p)
    anchor, rest = ("home", p[m.end():]) if m else ("abs" if p.startswith("/") else "rel", p)
    rest = posixpath.normpath(rest) if rest not in ("", "/") else ""
    segs = [s for s in rest.split("/") if s not in ("", ".")]
    if anchor == "abs":   # macOS firmlink and mounted-volume spellings of the same home
        if segs[:3] == ["system", "volumes", "data"]:
            segs = segs[3:]
        elif segs[:1] == ["volumes"] and len(segs) > 2 and segs[2] in ("users", "home", "root", "var"):
            segs = segs[2:]
    return anchor, segs


@functools.lru_cache(maxsize=8192)
def _seg_match(pat, sample):
    while len(pat) > 1 and pat[0] == "**" and pat[1] == "**":
        pat = pat[1:]
    if not pat:
        return not sample
    if pat[0] == "**":
        return any(_seg_match(pat[1:], sample[k:]) for k in range(len(sample) + 1))
    return bool(sample) and fnmatch.fnmatchcase(sample[0], pat[0]) and _seg_match(pat[1:], sample[1:])


def seg_match(pat, sample):
    """Shell-style glob match segment by segment ('*' never crosses '/', '**' does); memoised."""
    return _seg_match(tuple(pat), tuple(sample))


def home_len(smp):
    return next((len(h) for h in HOMES if smp[:len(h)] == h), 0)


def matches(anchor, segs, samples):
    """Does the path (anchor + segments) name one of the sample paths?"""
    for smp in samples:
        if anchor == "abs" and seg_match(segs, smp):
            return True
        if anchor == "home" and seg_match(segs, smp[home_len(smp):]):
            return True
        if anchor == "rel" and any(seg_match(segs, smp[k:]) for k in range(len(smp))):
            return True
    return False


def candidates(v, cwd):
    if v.startswith("~+") and cwd:
        return [cwd.rstrip("/") + v[2:]]
    if v.startswith(("~+", "~-")):
        return [v[2:].lstrip("/") or "."]
    if DYN_PART.match(v):
        return [v]   # leading $PWD/$VAR/$(...): unanchored, matched by its tail
    if cwd is not None and not v.startswith(("/", "~", "$")):
        return [cwd.rstrip("/") + "/" + v]
    return [v]


def norm(p):
    return posixpath.normpath(re.sub(r"/+", "/", p)) if p not in ("", "/") else p


def path_hit(v, cwd=None):
    """True when path/glob v (relative to the known cwd, else unanchored) names a cockpit web-* file."""
    for c in candidates(v, cwd):
        anchor, segs = split_path(c)
        if LITERAL.search("/" + "/".join(segs)) or matches(anchor, segs, FILES):
            return True
        k = next((i for i in range(len(segs) - 1) if segs[i:i + 2] == [".claude", "cockpit"]), None)
        if k is not None and any(seg_match(segs[k + 2:], [n]) for n in NAMES) and len(segs) > k + 2:
            return True
    return False


def dir_hit(v, cwd=None):
    """The cockpit directory itself (any spelling)."""
    for c in candidates(v, cwd):
        anchor, segs = split_path(c)
        if segs[-2:] == [".claude", "cockpit"] or (anchor != "rel" and matches(anchor, segs, COCKPIT_DIRS)):
            return True
    return False


def ancestor_hit(v, cwd=None):
    """A directory that CONTAINS the cockpit dir (~/.claude, ~, the home dir, /): recursion reaches web-*."""
    return any(a != "rel" and matches(a, s, ANCESTORS) for a, s in map(split_path, candidates(v, cwd)))


def word_variants(w):
    if DYN_PART.search(w) and not re.search(r"[A-Za-z0-9]", DYN_PART.sub("", w)):
        return []   # nothing literal left: a bare $VAR / $(...) says nothing about the path
    w = DYN_PART.sub("*", w)
    if re.search(r"\s", w):
        return []
    cuts = [m.end() for m in re.finditer(r"[=:,]|//", w)] + [m.start() for m in re.finditer(r"\$\{?HOME\}?|~", w)]
    return [w] + [w[c:] for c in cuts[:12]]


def recursive_kind(base, words):
    """True when this grep/rg-style command would search a directory tree and could include web-*."""
    inc = [w.split("=", 1)[-1] for w in words if w.startswith(("--include", "--glob", "-g"))]
    exc = [w.split("=", 1)[-1] for w in words if w.startswith("--exclude")]
    if any(fnmatch.fnmatchcase("web-1.out", e) for e in exc):
        return False
    if inc and not any(fnmatch.fnmatchcase("web-1.out", g) for g in inc):
        return False
    recursive = any(re.fullmatch(r"-[A-Za-z]*[rR][A-Za-z]*", w) or w == "--recursive" for w in words)
    return base in ALWAYS_RECURSIVE or recursive


def glob_admits_web(glob):
    if not isinstance(glob, str) or not glob:
        return True
    hit = any(fnmatch.fnmatchcase(n, glob.lstrip("!")) for n in NAMES)
    return (not hit) if glob.startswith("!") else hit


def check_tool(name, ti, cwd):
    """'D' (hard deny), 'K' (ask) or None for a Read/Grep/Glob call."""
    def hit(p, base=cwd):
        return isinstance(p, str) and bool(p) and path_hit(p, base)
    path, glob = ti.get("path"), ti.get("glob")
    base = path if isinstance(path, str) and path else cwd
    if name == "Read":
        return "D" if hit(ti.get("file_path")) else None
    if name == "Glob":
        pat = ti.get("pattern") or ""
        joined = (base.rstrip("/") + "/" + pat) if base and not pat.startswith(("/", "~")) else pat
        return "D" if hit(joined, None) else None
    if name == "Grep" and isinstance(base, str) and base:
        if hit(base) or (isinstance(glob, str) and hit(base.rstrip("/") + "/" + glob, None)):
            return "D"
        if not ti.get("type") and glob_admits_web(glob):
            if dir_hit(base, cwd):
                return "D"
            if ancestor_hit(base, cwd):
                return "K"
    return None
