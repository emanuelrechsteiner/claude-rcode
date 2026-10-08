"""Shared constants, exceptions and the ask-collector for cockpit-secret-guard."""
import re

FAKE_HOME = "/h"
R_TMUX = "tmux pane/buffer capture (the Cockpit launch token is readable that way)"
R_FILE = "access to the Cockpit runtime files ~/.claude/cockpit/web-* (launch token)"
R_ENV = "environment dump of the Cockpit server process (launch token)"
R_OBF = "obfuscated or undecidable command that may reach the Cockpit launch token"
DYN = "\x06"        # lexer marker: an unresolved $VAR / ${...} expansion
SUB_OPEN, SUB_CLOSE = "\x01", "\x02"   # lexer markers around a $(...) / `...` / <(...) body

TMUX_WORD = r"(?<![\w.-])tmux(?![\w-])"
DENY_NAMES = ("capture-pane", "capturep", "pipe-pane", "pipep", "save-buffer", "saveb", "show-buffer",
              "showb", "list-buffers", "lsb", "choose-buffer")
_ALT = "|".join(re.escape(n) for n in DENY_NAMES)
DENY_WORDS = re.compile(r"(?<![\w-])(" + _ALT + r")(?![\w-])")
_TMUX = re.compile(TMUX_WORD)
DECODERS = re.compile(r"\b(base64|b64decode|atob|xxd|rev|openssl|uudecode|basenc|gunzip|zcat)\b|"
                      r"\\x[0-9a-fA-F]{2}|\\[0-7]{3}|\\u[0-9a-fA-F]{4}|\bchr\(|fromCharCode|\btr\s")

ASKS = []   # (reason) collected by ask(); a Deny anywhere still wins over an ask


class Deny(Exception):
    """Raised by any rule: the tool call must be blocked (message = reason)."""


def ask(reason):
    """Record an ask-level finding (a native user prompt, never a silent allow)."""
    if reason not in ASKS:
        ASKS.append(reason)


def loose_tmux(text):
    """True when the word `tmux` is followed, anywhere later, by a capture/buffer subcommand (linear time)."""
    m = _TMUX.search(text)
    return bool(m and DENY_WORDS.search(text, m.end()))
