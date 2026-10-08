"""The tmux command table (3.5): exact names, aliases and unique-prefix resolution,
exactly as tmux's own command lookup does it (aliases match exactly, names by unique prefix)."""

_TABLE = """attach-session:attach bind-key:bind break-pane:breakp capture-pane:capturep choose-buffer
choose-client choose-tree clear-history:clearhist clear-prompt-history:clearphist clock-mode
command-prompt confirm-before:confirm copy-mode customize-mode detach-client:detach
delete-buffer:deleteb display-menu:menu display-message:display display-panes:displayp
display-popup:popup find-window:findw has-session:has if-shell:if join-pane:joinp kill-pane:killp
kill-server kill-session kill-window:killw link-window:linkw list-buffers:lsb list-clients:lsc
list-commands:lscm list-keys:lsk list-panes:lsp list-sessions:ls list-windows:lsw load-buffer:loadb
lock-client:lockc lock-server:lock lock-session:locks move-pane:movep move-window:movew
new-session:new new-window:neww next-layout:nextl next-window:next paste-buffer:pasteb
pipe-pane:pipep previous-layout:prevl previous-window:prev refresh-client:refresh rename-session:rename
rename-window:renamew resize-pane:resizep resize-window:resizew respawn-pane:respawnp
respawn-window:respawnw rotate-window:rotatew run-shell:run save-buffer:saveb select-layout:selectl
select-pane:selectp select-window:selectw send-keys:send send-prefix server-access set-buffer:setb
set-environment:setenv set-hook set-option:set set-window-option:setw show-buffer:showb
show-environment:showenv show-hooks show-messages:showmsgs show-options:show
show-prompt-history:showphist show-window-options:showw source-file:source split-window:splitw
start-server:start suspend-client:suspendc swap-pane:swapp swap-window:swapw switch-client:switchc
unbind-key:unbind unlink-window:unlinkw wait-for:wait"""

NAMES = []
ALIASES = {}
for _item in _TABLE.split():
    _name, _, _alias = _item.partition(":")
    NAMES.append(_name)
    if _alias:
        ALIASES[_alias] = _name


def resolve(word):
    """Canonical tmux command name for a typed subcommand, or None (unknown / ambiguous)."""
    if word in ALIASES:
        return ALIASES[word]
    if word in NAMES:
        return word
    hits = [n for n in NAMES if n.startswith(word)] if word else []
    return hits[0] if len(hits) == 1 else None


# Commands that read pane or buffer content (or search it): always denied.
READERS = {"capture-pane", "pipe-pane", "save-buffer", "show-buffer", "list-buffers", "choose-buffer"}
# Commands whose arguments are tmux/shell command text that tmux will run later.
RUNNERS = {"run-shell", "if-shell", "confirm-before", "command-prompt", "bind-key", "set-hook",
           "display-popup", "display-menu", "choose-tree", "choose-client", "set-option",
           "set-window-option", "respawn-pane", "respawn-window", "new-session", "new-window",
           "split-window"}
