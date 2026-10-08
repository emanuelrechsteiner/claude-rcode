#!/bin/bash
# secret-patterns.sh - ONE shared source for secret-shape regexes (IMP-244).
# Sourced (never executed) by hooks/security-audit.sh. scripts/scrub-check.sh
# can source it instead of its inline _pem_header / _jwt (drop-in: same names
# are NOT reused on purpose; map SECRET_RE_PEM -> _pem_header, SECRET_RE_JWT
# -> _jwt). All values are POSIX ERE for `grep -E`.
#
# The PEM header is written as an alternation so this file does not match its
# own pattern and stays editable through the Edit/Write secret gate.

# PEM private-key block header (RSA, OpenSSH, EC, DSA, encrypted, or plain).
SECRET_RE_PEM='-----BEGIN (RSA |OPENSSH |EC |DSA |ENCRYPTED )?PRIVATE KEY-----'

# JWT: three base64url segments, header and payload both start "eyJ" (a JSON
# object opening brace). A lone "eyJ..." token without the dots does not match.
SECRET_RE_JWT='eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
