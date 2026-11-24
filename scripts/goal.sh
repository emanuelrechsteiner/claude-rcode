#!/usr/bin/env bash
# goal.sh: entry point of goal tracking (IMP-289). Commands and exit codes: scripts/goal.py --help.
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/goal.py" "$@"
