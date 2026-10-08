#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2015
# Regression suite for hooks/cockpit-secret-guard.sh (Cockpit launch-token tripwire).
# (shellcheck: test inputs are deliberately unexpanded shell text; A && B || C is intended.)
#
# Locks in: every tmux capture spelling and every cockpit web-* file spelling
# denies (exit 2); every owner-legit operation and quoted-data near-miss allows;
# Read/Grep/Glob variants; the override is an `ask` prompt (never an allow);
# fail-closed on commands the scanner cannot inspect; fail-open only on garbled
# hook JSON / missing scanner (both loud + logged).
# HOME is redirected to a temp dir: nothing touches the real ~/.claude.
#
# Usage:  CLAUDE_HOOK=/path/to/cockpit-secret-guard.sh bash hooks/tests/cockpit-secret-guard-regression.sh
# Exit:   0 = ALL PASS, 1 = at least one failure

# Second suite (override, logging, fail-closed, fail-open): cockpit-secret-guard-regression-modes.sh.
# shellcheck source=lib/cockpit-secret-guard-harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/cockpit-secret-guard-harness.sh"

echo "== DENY: the five bypasses of the permissions.deny prefix rules =="
deny "-L option"                'tmux -L x capture-pane -p'
deny "env prefix"               'env tmux capture-pane'
deny "bash -c"                  'bash -c "tmux capture-pane -p"'
deny "command wrapper"          'command tmux save-buffer -'
deny "\$HOME path"              'cat $HOME/.claude/cockpit/web-*.out'
deny "python open()"            "python3 -c \"open('$U/.claude/cockpit/web-1.out')\""

echo "== DENY: tmux capture spellings =="
deny "plain capture-pane"       'tmux capture-pane -p -t %1'
deny "capturep alias"           'tmux capturep -p'
deny "pipe-pane"                'tmux pipe-pane -o "cat >> /tmp/x"'
deny "pipep alias"              'tmux pipep -t %1 "cat > /tmp/x"'
deny "save-buffer"              'tmux save-buffer /tmp/x'
deny "saveb alias"              'tmux saveb -'
deny "show-buffer"              'tmux show-buffer'
deny "showb alias"              'tmux showb'
deny "list-buffers"             'tmux list-buffers'
deny "lsb alias"                'tmux lsb'
deny "choose-buffer"            'tmux choose-buffer'
deny "unique prefix capture"    'tmux capture -p'
deny "-S socket + -f file"      'tmux -S /tmp/s -f /dev/null capture-pane -p'
deny "TMUX_TMPDIR env prefix"   'TMUX_TMPDIR=/tmp tmux capture-pane -p'
deny "absolute tmux path"       '/opt/homebrew/bin/tmux capture-pane -p'
deny "exec wrapper"             'exec tmux capture-pane -p'
deny "xargs wrapper"            'echo %1 | xargs -I{} tmux capture-pane -p -t {}'
deny "find -exec"               'find . -name x -exec tmux capture-pane -p \;'
deny "sh -c single quotes"      "sh -c 'tmux capture-pane -p'"
deny "eval string"              'eval "tmux capture-pane -p"'
deny "eval substitution"        'eval $(echo "tmux capture-pane -p")'
deny "command substitution"     'x=$(tmux capture-pane -p); echo "$x"'
deny "substitution in dquote"   'echo "$(tmux capture-pane -p)"'
deny "backticks"                'echo `tmux capture-pane -p`'
deny "substitution as program"  '$(which tmux) capture-pane -p'
deny "line continuation"        $'tmux \\\n  capture-pane -p'
deny "split quotes in program"  "t'm'ux capture-pane -p"
deny "backslash in program"     'tm\ux capture-pane -p'
deny "variable program"         'T=tmux; $T capture-pane -p'
deny "&& chain"                 'true && tmux capture-pane -p'
deny "pipe chain"               'tmux capture-pane -p | head -5'
deny "semicolon chain"          'echo hi; tmux save-buffer -'
deny "tmux \; sequence"         'tmux new-session -d -s x \; capture-pane -p'
deny "heredoc into bash"        $'bash <<EOF\ntmux capture-pane -p\nEOF'
deny "send-keys relays capture" 'tmux send-keys -t %1 "tmux capture-pane -p > /tmp/x" Enter'
deny "run-shell relays capture" 'tmux run-shell "tmux capture-pane -p"'
deny "control mode"             'printf "capture-pane -p\n" | tmux -C attach'
deny "node one-liner"           "node -e \"require('child_process').execSync('tmux capture-pane -p')\""
deny "for loop"                 'for p in 1 2; do tmux capture-pane -p -t $p; done'
deny "subshell"                 '(tmux capture-pane -p)'
deny "display-message buffer"   "tmux display-message -p '#{buffer_sample}'"
deny "display-message -a"       'tmux display-message -a -p'
deny "display-message #()"      "tmux display-message -p '#(cat /etc/hosts)'"
deny "display-message pane_title" "tmux display-message -p '#{pane_title}'"
deny "list-panes -F start_cmd"  "tmux list-panes -F '#{pane_start_command}'"
deny "copy-pipe via send-keys"  'tmux send-keys -X copy-pipe "cat > /tmp/x"'

echo "== DENY: cockpit runtime file spellings =="
deny ".claude/cockpit/web- rel" 'cat .claude/cockpit/web-1.out'
deny "tilde path"               'cat ~/.claude/cockpit/web-1.out'
deny "absolute /Users path"     "cat $U/.claude/cockpit/web-1.out"
deny "\${HOME} path"            'tail -f ${HOME}/.claude/cockpit/web-1.out'
deny "double slash + ./"        'cat ~/.claude//cockpit/./web-1.out'
deny "glob in file name"        'cat ~/.claude/cockpit/we?-*'
deny "glob *.out"               'head ~/.claude/cockpit/*.out'
deny "glob *.pid"               'cat ~/.claude/cockpit/*.pid'
deny "glob in dir part"         'cat ~/.claude/cock*/web-1.out'
deny "brace list"               'cat ~/.claude/cockpit/{web-1.out,x}'
deny "variable holds dir"       'D=~/.claude/cockpit; cat $D/web-1.out'
deny "cd then web-*"            'cd ~/.claude/cockpit && cat web-1.out'
deny "cd then glob w*"          'cd ~/.claude/cockpit; cat w*'
deny "cd then *.out"            'cd $HOME/.claude/cockpit && head *.out'
deny "pushd then *.pid"         'pushd ~/.claude/cockpit >/dev/null; cat *.pid'
deny "cd .claude then cockpit/" 'cd ~/.claude && cat cockpit/web-1.out'
deny "redirect from file"       'wc -c < ~/.claude/cockpit/web-1.out'
deny "cp the file"              'cp ~/.claude/cockpit/web-1.out /tmp/x'
deny "find -name web-*"         "find ~/.claude/cockpit -name 'web-*' -exec cat {} +"
deny "recursive grep of dir"    'grep -r token ~/.claude/cockpit'
deny "rg of dir"                'rg token ~/.claude/cockpit'
deny "perl one-liner"           "perl -ne 'print' ~/.claude/cockpit/web-1.out"
deny "node one-liner file"      "node -e \"console.log(require('fs').readFileSync('$U/.claude/cockpit/web-1.out','utf8'))\""
deny "python heredoc"           $'python3 - <<PY\nprint(open("/x/.claude/cockpit/web-1.out").read())\nPY'
deny "sh -c file read"          'sh -c "cat ~/.claude/cockpit/web-1.out"'
deny "substitution reads file"  'echo "$(cat ~/.claude/cockpit/web-1.out)"'

echo "== DENY: server environment dumps =="
deny "ps eww server.ts"         'ps eww -p 123 | grep server.ts'
deny "ps aeww cockpit"          'ps aeww | grep cockpit'
deny "ps -E cockpit"            'ps -E -p 123 # cockpit server'
deny "/proc environ server.ts"  'cat /proc/$(pgrep -f server.ts)/environ'

echo "== DENY: Read / Grep / Glob tool variants =="
tool_deny "Read web-1.out"      "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$U/.claude/cockpit/web-1.out\"}}"
tool_deny "Read tilde path"     '{"tool_name":"Read","tool_input":{"file_path":"~/.claude/cockpit/web-1.out"}}'
tool_deny "Grep path web-*"     '{"tool_name":"Grep","tool_input":{"pattern":"x","path":"~/.claude/cockpit/web-1.out"}}'
tool_deny "Grep dir no glob"    '{"tool_name":"Grep","tool_input":{"pattern":"x","path":"~/.claude/cockpit"}}'
tool_deny "Grep dir glob web-*" '{"tool_name":"Grep","tool_input":{"pattern":"x","path":"~/.claude/cockpit","glob":"web-*"}}'
tool_deny "Grep claude dir glob" '{"tool_name":"Grep","tool_input":{"pattern":"x","path":"~/.claude","glob":"cockpit/web-*"}}'
tool_deny "Glob web-*"          '{"tool_name":"Glob","tool_input":{"pattern":"web-*","path":"~/.claude/cockpit"}}'
tool_deny "Glob absolute"       '{"tool_name":"Glob","tool_input":{"pattern":"~/.claude/cockpit/web-*"}}'
tool_deny "Glob **/web-*"       '{"tool_name":"Glob","tool_input":{"pattern":"**/web-*","path":"~/.claude"}}'

echo "== ALLOW: owner-legit operations =="
allow "tmux list-sessions"      'tmux list-sessions'
allow "tmux list-panes -a"      'tmux list-panes -a'
allow "tmux list-panes -F safe" "tmux list-panes -a -F '#{session_name} #{pane_id} #{pane_index}'"
allow "tmux display-message -p" "tmux display-message -p '#{session_name}'"
allow "display-message no fmt"  'tmux display-message -p'
allow "display-message -t safe" "tmux display-message -t %1 -p '#{pane_pid} #{window_index}'"
allow "tmux send-keys"          'tmux send-keys -t %1 "npm test" Enter'
allow "tmux new-session"        'tmux new-session -d -s job1 "npm run build"'
allow "tmux kill-session"       'tmux kill-session -t job1'
allow "tmux -L other socket"    'tmux -L work list-windows'
allow "tmux has-session"        'tmux has-session -t job1'
allow "cat events jsonl"        'cat ~/.claude/cockpit/events-abc.jsonl'
allow "tail dashboard.log"      'tail -n 20 ~/.claude/cockpit/dashboard.log'
allow "cat status json"         'cat ~/.claude/cockpit/status-abc.json'
allow "cat subagents json"      'cat $HOME/.claude/cockpit/subagents-abc.json'
allow "cat current-session"     'cat ~/.claude/cockpit/current-session.json'
allow "cat config file"         'cat ~/.claude/cockpit/config/cockpit.json'
allow "ls cockpit dir"          'ls ~/.claude/cockpit'
allow "ls -la cockpit dir"      'ls -la ~/.claude/cockpit/'
allow "cd cockpit + events"     'cd ~/.claude/cockpit && cat events-abc.jsonl'
allow "cd cockpit + ls"         'cd ~/.claude/cockpit; ls'
allow "glob events-*.jsonl"     'cat ~/.claude/cockpit/events-*.jsonl'
allow "grep dir with include"   "grep -r token --include='events-*' ~/.claude/cockpit"
allow "ps aux server.ts"        'ps aux | grep server.ts'
allow "ps -ef cockpit"          'ps -ef | grep cockpit'
allow "ps eww unrelated"        'ps eww -p 1'
allow "ps -o etime cockpit"     'ps -o etime -p 123 # cockpit'

echo "== ALLOW: near-misses (the words only as data) =="
allow "grep -n capture-pane"    'grep -n capture-pane docs/x.md'
allow "git commit -m"           'git commit -m "tmux capture-pane is denied"'
allow "git commit -m web path"  'git commit -m "guard .claude/cockpit/web-* reads"'
allow "echo mentions"           'echo "tmux capture-pane and save-buffer are blocked"'
allow "echo single quotes"      "echo 'tmux show-buffer'"
allow "heredoc commit msg"      $'git commit -F - <<EOF\ntmux capture-pane -p\nEOF'
allow "comment mentions"        'ls # tmux capture-pane later'
allow "man tmux"                'man tmux'
allow "which tmux"              'which tmux'
allow "brew install tmux"       'brew install tmux'
allow "tmux -V"                 'tmux -V'
allow "grep pane_ in source"    "grep -n 'pane_start_command' hooks/x.sh"
allow "capture-pane no tmux"    'echo capture-pane'
allow "other dir web- file"     'cat ./src/web-view/index.ts'
allow "claude other web-"       'cat ~/.claude/other/web-1.out'
allow "cockpit repo docs"       'cat docs/superpowers/specs/2026-10-06-web-view.md'
allow "plain ls"                'ls -la'

echo "== ALLOW: Read / Grep / Glob tool variants =="
tool_allow "Read events jsonl"  '{"tool_name":"Read","tool_input":{"file_path":"~/.claude/cockpit/events-abc.jsonl"}}'
tool_allow "Read dashboard.log" '{"tool_name":"Read","tool_input":{"file_path":"~/.claude/cockpit/dashboard.log"}}'
tool_allow "Read project file"  '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x/README.md"}}'
tool_allow "Grep events glob"   '{"tool_name":"Grep","tool_input":{"pattern":"x","path":"~/.claude/cockpit","glob":"events-*.jsonl"}}'
tool_allow "Grep project dir"   '{"tool_name":"Grep","tool_input":{"pattern":"web-","path":"/tmp/x/src"}}'
tool_allow "Grep pattern only"  '{"tool_name":"Grep","tool_input":{"pattern":"cockpit/web-"}}'
tool_allow "Glob events"        '{"tool_name":"Glob","tool_input":{"pattern":"events-*.jsonl","path":"~/.claude/cockpit"}}'
tool_allow "Glob src ts"        '{"tool_name":"Glob","tool_input":{"pattern":"**/*.ts"}}'
tool_allow "unrelated tool"     '{"tool_name":"Write","tool_input":{"file_path":"~/.claude/cockpit/web-1.out"}}'

finish
