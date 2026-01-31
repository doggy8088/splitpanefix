# Copilot Instructions for Fix-SplitPanePersistence

## Overview

Single PowerShell script that configures Windows Terminal + Oh My Posh for directory persistence in split panes. No build system, no tests, no dependencies.

## Running the Script

```powershell
# Dry run (preview changes)
.\Fix-SplitPanePersistence.ps1 -WhatIf -Verbose

# Apply changes
.\Fix-SplitPanePersistence.ps1

# With Copilot CLI integration
.\Fix-SplitPanePersistence.ps1 -Copilot
```

## Architecture

The script modifies three external files to make them work together:

1. **PowerShell Profile** (`$PROFILE`) - Ensures Oh My Posh init line exists
2. **Oh My Posh Theme** (JSON) - Adds `"pwd": "osc99"` for OSC 99 escape sequences
3. **Windows Terminal settings.json** - Updates keybindings with `splitMode: duplicate`

### Key Limitation

Windows Terminal cannot combine `splitMode: duplicate` with custom `commandline`. This is why `-Copilot` adds a shell function (`spc`) instead of a keybinding - see "Why a function instead of a keybinding?" in README.

## Conventions

- All file modifications create timestamped backups (`.bak-YYYYMMDD-HHMMSS-fff`)
- Script must be idempotent - re-running produces no changes if already configured
- Uses `[CmdletBinding(SupportsShouldProcess)]` for `-WhatIf` support
- Windows Terminal has two settings formats: old (keys in actions) and new (separate keybindings array referencing action IDs) - script handles both

## File Locations

Script discovers these dynamically:
- Profile: `$PROFILE.CurrentUserCurrentHost`
- Theme: Parsed from profile's `oh-my-posh init --config` line
- Terminal: Checks packaged (Store), preview, and unpackaged paths under `$env:LOCALAPPDATA`
