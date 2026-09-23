#!/bin/bash
# Auto-format hook - formats code files after write/edit operations
# Runs prettier or other formatters based on file type

# Get file path from argument or stdin
FILE_PATH="$1"

# If no argument, try to read from stdin (JSON input)
if [[ -z "$FILE_PATH" ]]; then
    INPUT=$(cat)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
fi

# Exit if no file path
if [[ -z "$FILE_PATH" ]] || [[ "$FILE_PATH" == "null" ]]; then
    exit 0
fi

# Exit if file doesn't exist
if [[ ! -f "$FILE_PATH" ]]; then
    exit 0
fi

# Find project root by looking for package.json
find_project_root() {
    local dir="$(dirname "$1")"
    while [[ "$dir" != "/" && "$dir" != "." ]]; do
        if [[ -f "$dir/package.json" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    echo ""
}

PROJECT_ROOT="$(find_project_root "$FILE_PATH")"

# Skip formatting if no project root found
if [[ -z "$PROJECT_ROOT" ]]; then
    exit 0
fi

# Check for prettier configuration
HAS_PRETTIER=false
for config in ".prettierrc" ".prettierrc.json" ".prettierrc.js" ".prettierrc.cjs" ".prettierrc.yaml" ".prettierrc.yml" "prettier.config.js" "prettier.config.cjs"; do
    if [[ -f "$PROJECT_ROOT/$config" ]]; then
        HAS_PRETTIER=true
        break
    fi
done

# Also check package.json for prettier key
if [[ "$HAS_PRETTIER" == "false" ]] && [[ -f "$PROJECT_ROOT/package.json" ]]; then
    if grep -q '"prettier"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
        HAS_PRETTIER=true
    fi
fi

# Format based on file type
case "$FILE_PATH" in
    *.ts|*.tsx|*.js|*.jsx|*.json|*.css|*.scss|*.md|*.html|*.yaml|*.yml)
        if [[ "$HAS_PRETTIER" == "true" ]]; then
            cd "$PROJECT_ROOT" || exit 0
            # Run prettier silently, don't fail the hook if formatting fails
            npx prettier --write "$FILE_PATH" 2>/dev/null || true
        fi
        ;;
    *.py)
        # Python formatting with ruff or black if available
        if command -v ruff &> /dev/null; then
            ruff format --quiet "$FILE_PATH" 2>/dev/null || true
        elif command -v black &> /dev/null; then
            black --quiet "$FILE_PATH" 2>/dev/null || true
        fi
        ;;
    *.go)
        # Go formatting with gofmt
        if command -v gofmt &> /dev/null; then
            gofmt -w "$FILE_PATH" 2>/dev/null || true
        fi
        ;;
    *.rs)
        # Rust formatting with rustfmt
        if command -v rustfmt &> /dev/null; then
            rustfmt "$FILE_PATH" 2>/dev/null || true
        fi
        ;;
esac

exit 0
