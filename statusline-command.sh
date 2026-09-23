#!/bin/bash

# Custom Claude Code Status Line
# Displays: Model Name | Context Usage | Active Plugins

# Read JSON input from stdin
INPUT=$(cat)

# === 1. MODEL NAME ===
# Extract model display name from JSON input
MODEL_DISPLAY=$(echo "$INPUT" | jq -r '.model.display_name // "Claude"')

# === 2. CONTEXT USAGE ===
# Extract context window data from JSON
USAGE=$(echo "$INPUT" | jq '.context_window.current_usage')

# Calculate percentage only if we have usage data
if [[ "$USAGE" != "null" ]]; then
    # Get current context usage (input + cache creation + cache read)
    CONTEXT_USED=$(echo "$USAGE" | jq '.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens')
    CONTEXT_MAX=$(echo "$INPUT" | jq '.context_window.context_window_size')

    # Calculate percentage
    if [[ $CONTEXT_MAX -gt 0 ]]; then
        CONTEXT_PCT=$((CONTEXT_USED * 100 / CONTEXT_MAX))
    else
        CONTEXT_PCT=0
    fi
else
    # No messages yet
    CONTEXT_PCT=0
fi

# Create progress bar (20 characters wide)
BAR_WIDTH=20
FILLED=$((CONTEXT_PCT * BAR_WIDTH / 100))
EMPTY=$((BAR_WIDTH - FILLED))

# Build progress bar with block characters
BAR=""
for ((i=0; i<FILLED; i++)); do
    BAR+="█"
done
for ((i=0; i<EMPTY; i++)); do
    BAR+="░"
done

# === 3. ACTIVE PLUGINS ===
# Read enabled plugins from settings.json
SETTINGS_FILE="$HOME/.claude/settings.json"

get_plugins() {
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        echo "No plugins"
        return
    fi

    # Extract enabled plugins and get short names
    PLUGINS=$(jq -r '.enabledPlugins | to_entries | map(select(.value == true) | .key) | .[]' "$SETTINGS_FILE" 2>/dev/null | \
        sed 's/@claude-plugins-official//' | \
        sed 's/^plugin://' | \
        sort)

    if [[ -z "$PLUGINS" ]]; then
        echo "No plugins"
        return
    fi

    # Count total plugins
    TOTAL=$(echo "$PLUGINS" | wc -l | tr -d ' ')

    # Define priority plugins to show (most commonly used)
    PRIORITY="serena context7 playwright"

    # Build display list of priority plugins that are enabled
    DISPLAY_PLUGINS=""
    for plugin in $PRIORITY; do
        if echo "$PLUGINS" | grep -qi "^${plugin}"; then
            # Capitalize first letter (portable method)
            FIRST_CHAR=$(echo "$plugin" | cut -c1 | tr '[:lower:]' '[:upper:]')
            REST=$(echo "$plugin" | cut -c2-)
            PLUGIN_NAME="${FIRST_CHAR}${REST}"
            DISPLAY_PLUGINS="${DISPLAY_PLUGINS}${PLUGIN_NAME}, "
        fi
    done

    # Remove trailing comma and space
    DISPLAY_PLUGINS=$(echo "$DISPLAY_PLUGINS" | sed 's/, $//')

    # Count how many priority plugins are shown
    SHOWN=$(echo "$DISPLAY_PLUGINS" | grep -o ',' | wc -l | tr -d ' ')
    SHOWN=$((SHOWN + 1))

    # Calculate remaining plugins
    REMAINING=$((TOTAL - SHOWN))

    if [[ $REMAINING -gt 0 ]]; then
        echo "${DISPLAY_PLUGINS} +${REMAINING}"
    else
        echo "$DISPLAY_PLUGINS"
    fi
}

PLUGINS_DISPLAY=$(get_plugins)

# === 4. ASSEMBLE STATUS LINE ===
echo "$MODEL_DISPLAY | Context: $BAR $CONTEXT_PCT% | Plugins: $PLUGINS_DISPLAY"
