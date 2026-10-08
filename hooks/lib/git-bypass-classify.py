#!/usr/bin/env python3
"""Classifier for hooks/git-bypass-guard.sh (IMP-240).

Reads the Bash command from env GBG_CMD, prints `ALLOW` or
`BLOCK<TAB>reason<TAB>gate<TAB>sha256-of-normalized-command`.
Mechanism adapted from everything-claude-code block-no-verify.js
(Copyright (c) 2026 Affaan Mustafa, MIT License, commit c70874f); not a copy.
See the hook header for the full list of blocked forms and known limits.
"""
import hashlib, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gbg_lex import lex  # noqa: E402

cmd = os.environ.get("GBG_CMD", "")
MAX_DEPTH = 6
PROTECTED = {"commit", "push", "merge", "pull", "cherry-pick", "rebase", "am", "revert"}
SHELLS = {"sh", "bash", "zsh", "dash", "ksh"}
KEYWORDS = {"if", "then", "else", "elif", "while", "until", "do", "!", "time", "{", "}"}
VALFLAGS = {"nice": {"-n", "--adjustment"}, "timeout": {"-s", "-k", "--signal", "--kill-after"},
            "caffeinate": {"-t", "-w"}, "stdbuf": {"-i", "-o", "-e"}, "env": {"-u", "-C", "-S"},
            "sudo": {"-u", "-g", "-h", "-p", "-C", "-T", "-R", "-D", "-U"},
            "doas": {"-u", "-C"}}
WRAPPERS = {"command", "builtin", "exec", "nohup", "nice", "timeout", "arch", "caffeinate",
            "stdbuf", "setsid", "env", "sudo", "doas"}
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*\+?=")
GATE = {"commit": "the pre-commit vault + scrub gate", "push": "the pre-push scrub gate",
        "merge": "the pre-merge-commit gate", "pull": "the pre-merge-commit gate"}

def noverify_long(a):
    head = a.split("=", 1)[0]
    return a.startswith("--") and len(head) >= 6 and "--no-verify".startswith(head)

def commit_short(a):
    for k, ch in enumerate(a[1:]):
        if ch == "n": return "n"
        if ch in "mFCct": return "skip" if k == len(a) - 2 else "none"
        if ch in "uS": return "none"
    return "none"

COMMIT_VALUE = {"--message", "--file", "--reuse-message", "--reedit-message", "--author", "--date",
                "--template", "--fixup", "--squash", "--pathspec-from-file", "--cleanup"}

def env_bypass(env):
    for k, v in env.items():
        lv = v.lower()
        if k == "HUSKY" and v.strip() == "0": return "HUSKY=0"
        if k == "HUSKY_SKIP_HOOKS" and v.strip(): return "HUSKY_SKIP_HOOKS"
        if k == "VAULT_PRECOMMIT_BYPASS": return "VAULT_PRECOMMIT_BYPASS"  # any value, even blank
        if k == "GIT_CONFIG_PARAMETERS" and "core.hookspath" in lv: return "GIT_CONFIG_PARAMETERS core.hooksPath"
        if re.match(r"GIT_CONFIG_KEY_\d+$", k) and lv.strip() == "core.hookspath": return k + "=core.hooksPath"
    return None

def check_config(args):
    pos, unset, write, get, k = [], False, False, False, 0
    while k < len(args):
        a = args[k]
        if a in ("--unset", "--unset-all", "--remove-section"): unset = True
        elif a in ("--add", "--replace-all"): write = True
        elif a in ("--get", "--get-all", "--get-regexp", "--get-urlmatch", "--list", "-l"): get = True
        elif a in ("-f", "--file", "--blob", "--type", "--default", "--comment"): k += 1
        elif not a.startswith("-"): pos.append(a)
        k += 1
    if pos and pos[0] in ("set", "unset", "get", "list"):
        s2 = pos.pop(0); unset |= s2 == "unset"; write |= s2 == "set"; get |= s2 in ("get", "list")
    if not pos or pos[0].lower() != "core.hookspath" or get: return None
    if unset or write or len(pos) > 1: return "git config write to core.hooksPath"
    return None

def check_git(words, env):
    i, override = 1, False
    while i < len(words) and words[i].startswith("-"):
        w, lw = words[i], words[i].lower()
        if w in ("-c", "--config-env"):
            if (words[i + 1] if i + 1 < len(words) else "").lower().startswith("core.hookspath"): override = True
            i += 2; continue
        if lw.startswith("-ccore.hookspath") or lw.startswith("--config-env=core.hookspath"): override = True
        i += 2 if w in ("-C", "--git-dir", "--work-tree", "--namespace", "--super-prefix") else 1
    sub = words[i] if i < len(words) else None
    args = words[i + 1:]
    if sub == "config": return check_config(args)
    if sub not in PROTECTED: return None
    if override: return f"git -c core.hooksPath override on git {sub}"
    hit = env_bypass(env)
    if hit: return f"{hit} set before git {sub}"
    skip = False
    for a in args:
        if skip: skip = False; continue
        if noverify_long(a): return f"--no-verify on git {sub}"
        if sub == "commit":
            if a in COMMIT_VALUE or a in ("-m", "-F", "-C", "-c", "-t"): skip = True
            elif a.startswith("-") and not a.startswith("--") and len(a) > 1:
                r = commit_short(a)
                if r == "n": return "git commit -n (= --no-verify)"
                skip = r == "skip"
    return None

def split_assign(w):
    k, _, v = w.partition("=")
    return k.rstrip("+"), v

def check_cmd(c, sticky, depth):
    words, env, i = list(c["words"]), {}, 0
    while i < len(words):
        w = words[i]; base = os.path.basename(w)
        if ASSIGN.match(w): k, v = split_assign(w); env[k] = v; i += 1
        elif w in KEYWORDS: i += 1
        elif base in WRAPPERS:
            i += 1
            while i < len(words) and words[i].startswith("-"):
                i += 2 if words[i] in VALFLAGS.get(base, ()) else 1
            if base == "timeout" and i < len(words): i += 1  # DURATION
        else: break
    words = words[i:]
    if not words: sticky.update(env); return None
    name = os.path.basename(words[0])
    if name in ("export", "declare", "typeset", "readonly"):
        for w in words[1:]:
            if ASSIGN.match(w): k, v = split_assign(w); sticky[k] = v
        return None
    if name == "git": return check_git(words, {**sticky, **env})
    if name in SHELLS:
        for j in range(1, len(words)):
            if words[j].startswith("-") and not words[j].startswith("--") and "c" in words[j][1:]:
                return analyze(words[j + 1], depth + 1) if j + 1 < len(words) else None
        srcs = list(c["heredocs"]) + list(c["herestrings"]); p = c["piped"]
        while p:  # any pipe producer may feed the shell: echo, printf, cat <<EOF, ...
            srcs += [" ".join(p["words"][1:])] + p["heredocs"] + p["herestrings"]
            p = p["piped"]
        for s in srcs:
            r = analyze(s, depth + 1)
            if r: return r
    elif name == "eval":
        return analyze(" ".join(w for w in words[1:] if w != "--"), depth + 1)
    return None

def analyze(s, depth=0):
    if depth > MAX_DEPTH: return "shell nesting too deep to verify"
    sticky = {}
    for c in lex(s):
        for sub in c["nested"]:
            r = analyze(sub, depth + 1)
            if r: return r
        r = check_cmd(c, sticky, depth)
        if r: return r
    return None

norm = re.sub(r"\s+", " ", re.sub(r"CLAUDE_GIT_BYPASS_ACK=[A-Fa-f0-9]{64}\s*", "", cmd)).strip()
sig = hashlib.sha256(norm.encode()).hexdigest()
reason = analyze(cmd)
if not reason: sys.stdout.write("ALLOW"); sys.exit(0)
m = re.search(r"\bgit\b.*?\b(commit|push|merge|pull|cherry-pick|rebase|am|revert)\b", norm)
gate = GATE.get(m.group(1) if m else "", "every git hook (incl. the pre-commit vault + scrub gate)")
sys.stdout.write(f"BLOCK\t{reason}\t{gate}\t{sig}")
