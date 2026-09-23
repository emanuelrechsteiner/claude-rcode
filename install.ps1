# Claude R.Code — Windows Install
#
# Windows support is community-maintained / best-effort. The framework's
# value is mostly in its ~30 bash hooks, which need WSL or Git Bash to run
# on Windows — this script does NOT set that up for you. It only covers the
# "fresh" and "overwrite" modes (clone/backup, self-update-via-pull); there
# is no "augment" mode here (the scan+merge logic in install.sh is bash-only).
# If you're on Windows, WSL2 + running install.sh there is the fully-supported
# path.
#
# Mac/Linux users: use install.sh instead.
#
#   git clone https://github.com/emanuelrechsteiner/claude-rcode.git; cd claude-rcode; .\install.ps1
#   iwr -useb https://raw.githubusercontent.com/emanuelrechsteiner/claude-rcode/main/install.ps1 | iex
#
# install.ps1 never touches your Claude Code credentials. Login (Pro/Max
# OAuth or API key) happens inside Claude Code itself on first launch.
$ErrorActionPreference = "Stop"

$ClaudeDir = if ($env:CLAUDE_DIR) { $env:CLAUDE_DIR } else { "$HOME\.claude" }
$RepoUrl = "https://github.com/emanuelrechsteiner/claude-rcode.git"

Write-Host "Claude R.Code — Install (Windows, community-maintained)"
Write-Host "Target: $ClaudeDir"
Write-Host ""

# Detect: in-repo run vs remote
$ScriptDir = $PSScriptRoot
if ($ScriptDir -and (Test-Path "$ScriptDir\.git")) {
    Write-Host "Running from inside an existing clone at $ScriptDir"
    $TemplatesDir = "$ScriptDir\templates"
} elseif (Test-Path "$ClaudeDir\.git") {
    # Existing clone at the target — self-update via pull rather than
    # backup+reclone (mirrors install.sh's "auto" self-update path).
    Write-Host "Existing clone detected at $ClaudeDir — running git pull"
    Push-Location $ClaudeDir
    git pull --ff-only
    Pop-Location
    $TemplatesDir = "$ClaudeDir\templates"
} else {
    # Backup any other pre-existing ~/.claude (non-clone content) — the
    # "overwrite" mode; there is no separate flag, matching D6's minimal
    # fresh/overwrite-only scope.
    if (Test-Path $ClaudeDir) {
        $Backup = "$ClaudeDir.backup-$([int][double]::Parse((Get-Date -UFormat %s)))"
        Write-Host "Backing up existing $ClaudeDir to $Backup"
        Move-Item $ClaudeDir $Backup
    }

    Write-Host "Cloning $RepoUrl to $ClaudeDir"
    git clone $RepoUrl $ClaudeDir
    $TemplatesDir = "$ClaudeDir\templates"
}

# Copy templates → *.local.* files (only if missing)
#
# Deliberately the same whitelist as install.sh copy_templates(), NOT a
# "*.template" glob: templates\ also holds command-contract.template (a
# reference snippet library) and serena_config.yml.template (machine-
# specific, own opt-in flow) — neither should ever be silently
# materialized into a fresh ~/.claude. A glob here made the Windows
# installer materialize exactly those two and nothing else.
Write-Host ""
Write-Host "Setting up local overlays..."
# settings.local.json is NOT in this list: Claude Code does not read a
# user-level settings.local.json (the `local` scope is per-project only),
# so its template was removed 2026-08-04 and the README table with it.
$Overlays = @("CLAUDE.local.md", "MEMORY_FIRST.local.md", "identity.local.md")
$Created = 0
$Existing = 0
$Absent = 0
if (Test-Path $TemplatesDir) {
    foreach ($basename in $Overlays) {
        $tmpl = Join-Path $TemplatesDir "$basename.template"
        if (-not (Test-Path $tmpl)) {
            # Loud, per rules/fail-loud.md — a missing template is a
            # packaging defect, not an optional feature.
            Write-Warning "no template for $basename (expected $tmpl) - overlay NOT created"
            $Absent++
            continue
        }

        $target = "$ClaudeDir\$basename"

        # identity.local.md → rules\identity.local.md
        if ($basename -eq "identity.local.md") {
            $target = "$ClaudeDir\rules\$basename"
        }

        if (-not (Test-Path $target)) {
            $targetDir = Split-Path $target -Parent
            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
            Copy-Item $tmpl $target
            Write-Host "  Created $target"
            $Created++
        } else {
            Write-Host "  Skipped $target (already exists)"
            $Existing++
        }
    }
} else {
    $Absent = $Overlays.Count
}
if ($Created -eq 0 -and $Existing -eq 0) {
    Write-Warning "no local overlays were set up ($Absent template(s) missing in $TemplatesDir)."
    Write-Warning "  This install is incomplete - see README 'Local overlays'."
}

if (Test-Path "$ClaudeDir\settings.framework.json") {
    Write-Host "Removing stale settings.framework.json (superseded by the single settings.json)"
    Remove-Item "$ClaudeDir\settings.framework.json" -Force
}

Write-Host ""
Write-Host "Claude R.Code installed at $ClaudeDir"
Write-Host ""
Write-Host "Setup complete. Start Claude Code with:  claude"
Write-Host "On first launch, Claude Code runs its OWN login flow - choose either:"
Write-Host "  - Pro/Max subscription  -> browser OAuth (claude.ai)"
Write-Host "  - Anthropic API key      -> paste when prompted, or set ANTHROPIC_API_KEY"
Write-Host "R.Code never stores or reads your credentials."
Write-Host ""
Write-Host "Note: .sh hooks require WSL or Git Bash to run on Windows. There is no"
Write-Host "'augment' mode here — for a selective merge into an existing config, run"
Write-Host "install.sh (via WSL/Git Bash) instead."
