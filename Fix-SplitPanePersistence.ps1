<#
.SYNOPSIS
    設定 PowerShell、Oh My Posh 與 Windows Terminal，讓分割窗格與分頁能保留目前工作目錄。

.DESCRIPTION
    本腳本會確保：
    - PowerShell 設定檔（profile）存在，且 Oh My Posh 初始化正確
    - Oh My Posh 主題透過 OSC99 送出目錄資訊
    - Windows Terminal 的按鍵繫結在分割/複製時能保留目錄

.PARAMETER WhatIf
    顯示將會做哪些變更，但不會真的套用。

.PARAMETER Verbose
    顯示所有操作的詳細記錄。

.PARAMETER ThemePath
    選用：指定「使用者可寫入」的主題資料夾路徑。

.PARAMETER Copilot
    新增一個按鍵繫結（Ctrl+Shift+.），用於分割窗格並啟動 GitHub Copilot CLI。

.EXAMPLE
    .\Fix-SplitPanePersistence.ps1

.EXAMPLE
    .\Fix-SplitPanePersistence.ps1 -WhatIf -Verbose

.EXAMPLE
    .\Fix-SplitPanePersistence.ps1 -Copilot
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ThemePath,
    [switch]$Copilot
)

# 需要 PowerShell 7+
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host ""
    Write-Host "  等等！你目前正在使用 PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Red
    Write-Host ""
    Write-Host "  此腳本需要 PowerShell 7+（而且各方面都更好）：" -ForegroundColor Yellow
    Write-Host "    - 更快" -ForegroundColor Gray
    Write-Host "    - 跨平台" -ForegroundColor Gray
    Write-Host "    - 更好的錯誤處理" -ForegroundColor Gray
    Write-Host "    - 現代化的 JSON 支援" -ForegroundColor Gray
    Write-Host "    - 仍在積極維護" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  安裝方式：" -ForegroundColor Cyan
    Write-Host "    winget install Microsoft.PowerShell" -ForegroundColor White
    Write-Host ""
    Write-Host "  接著在 Windows Terminal 將 PowerShell 7 設為預設設定檔" -ForegroundColor Cyan
    Write-Host "  （設定 -> 啟動 -> 預設設定檔 -> PowerShell）" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  然後執行：pwsh .\Fix-SplitPanePersistence.ps1" -ForegroundColor White
    Write-Host ""
    exit 1
}

$script:ChangesMode = $false

function Write-Log {
    param(
        [string]$Message,
        [switch]$Verbose
    )
    if ($Verbose -and $VerbosePreference -ne 'Continue') { return }
    $prefix = if ($WhatIfPreference) { "[DryRun] " } else { "" }
    Write-Host "$prefix$Message"
}

function Get-Timestamp {
    return (Get-Date -Format "yyyyMMdd-HHmmss-fff")
}

function Backup-File {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $backupPath = "$Path.bak-$(Get-Timestamp)"
    # 若備份檔名已存在，確保產生唯一的備份路徑
    $counter = 0
    while (Test-Path $backupPath) {
        $counter++
        $backupPath = "$Path.bak-$(Get-Timestamp)-$counter"
    }
    if ($WhatIfPreference) {
        Write-Log "將會備份：$Path -> $backupPath" -Verbose
        return $backupPath
    }
    Copy-Item -Path $Path -Destination $backupPath
    Write-Log "已備份：$Path -> $backupPath" -Verbose
    return $backupPath
}

function Ensure-ProfileExists {
    $profilePath = $PROFILE.CurrentUserCurrentHost
    $profileDir = Split-Path $profilePath -Parent

    if (-not (Test-Path $profileDir)) {
        if ($PSCmdlet.ShouldProcess($profileDir, "建立資料夾")) {
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
            Write-Log "已建立設定檔資料夾：$profileDir"
        }
    }

    if (-not (Test-Path $profilePath)) {
        if ($PSCmdlet.ShouldProcess($profilePath, "建立空白設定檔")) {
            New-Item -ItemType File -Path $profilePath -Force | Out-Null
            Write-Log "已建立 PowerShell 設定檔：$profilePath"
        }
    }

    return $profilePath
}

function Get-OMPInstalled {
    $omp = Get-Command oh-my-posh -ErrorAction SilentlyContinue
    return $null -ne $omp
}

function Get-OMPVersion {
    try {
        $versionOutput = oh-my-posh --version 2>&1
        if ($versionOutput -match '(\d+)\.(\d+)\.(\d+)') {
            return [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])"
        }
        return $null
    }
    catch {
        return $null
    }
}

function Test-OMPVersionCompatible {
    param([version]$CurrentVersion)

    # "pwd": "osc99" 功能所需的最低版本
    $minVersion = [version]"3.151.0"

    if ($null -eq $CurrentVersion) {
        return $false
    }

    return $CurrentVersion -ge $minVersion
}

function Show-OMPVersionWarning {
    param([version]$CurrentVersion)

    Write-Host ""
    Write-Host "  ⚠️  Oh My Posh 版本警告" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  你的 Oh My Posh 版本：$CurrentVersion" -ForegroundColor White
    Write-Host "  最低需求版本：3.151.0" -ForegroundColor White
    Write-Host ""
    Write-Host "  本腳本將會在你的 Oh My Posh 主題加入 " -ForegroundColor Gray -NoNewline
    Write-Host '"pwd": "osc99"' -ForegroundColor Cyan -NoNewline
    Write-Host "。" -ForegroundColor Gray
    Write-Host "  這個功能僅支援 Oh My Posh v3.151.0 與更新版本。" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  如果你使用過舊版本仍選擇繼續，你的 Oh My Posh 設定可能會壞掉！" -ForegroundColor Red
    Write-Host ""
    Write-Host "  建議先升級 Oh My Posh：" -ForegroundColor Cyan
    Write-Host "    winget upgrade JanDeDobbeleer.OhMyPosh" -ForegroundColor White
    Write-Host ""
    Write-Host "  或者（從 ohmyposh.dev 下載並執行安裝腳本）：" -ForegroundColor Gray
    Write-Host "    Set-ExecutionPolicy Bypass -Scope Process -Force; " -ForegroundColor DarkGray -NoNewline
    Write-Host "Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://ohmyposh.dev/install.ps1'))" -ForegroundColor DarkGray
    Write-Host ""
}

function Get-OMPInitLines {
    param([string]$ProfileContent)
    $pattern = '^\s*oh-my-posh\s+init\s+pwsh\s+--config\s+[''"]?([^''"|\s]+)[''"]?\s*\|\s*Invoke-Expression'
    $matches = [regex]::Matches($ProfileContent, $pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    return $matches
}

function Get-ThemePathFromProfile {
    param([string]$ProfileContent)
    $pattern = "oh-my-posh\s+init\s+pwsh\s+--config\s+['""]?([^'""|\s]+)['""]?\s*\|\s*Invoke-Expression"
    if ($ProfileContent -match $pattern) {
        $themePath = $Matches[1]
        # 展開環境變數（支援 %VAR% 語法）
        $themePath = [System.Environment]::ExpandEnvironmentVariables($themePath)
        # 處理 PowerShell 變數語法，例如 $env:POSH_THEMES_PATH 或 $env:COMPUTERNAME
        while ($themePath -match '\$env:(\w+)') {
            $varName = $Matches[1]
            $varValue = [System.Environment]::GetEnvironmentVariable($varName)
            if ($varValue) {
                $themePath = $themePath -replace [regex]::Escape("`$env:$varName"), $varValue
            } else {
                break
            }
        }
        # 將 ~ 展開為使用者家目錄
        if ($themePath.StartsWith('~')) {
            $themePath = $themePath -replace '^~', $env:USERPROFILE
        }
        return $themePath
    }
    return $null
}

function Fix-ProfileOMPInit {
    param([string]$ProfilePath)

    if (-not (Test-Path $ProfilePath)) { return $false }

    try {
        $content = Get-Content $ProfilePath -Raw -ErrorAction Stop
        if (-not $content) { $content = "" }
    $originalContent = $content
    $modified = $false

    # 將自訂 prompt 函式註解起來
    $promptPattern = '(?ms)^(\s*function\s+prompt\s*\{.*?\n\})'
    if ($content -match $promptPattern) {
        Backup-File -Path $ProfilePath
        $content = [regex]::Replace($content, $promptPattern, @"
# [Fix-SplitPanePersistence] 已註解自訂 prompt，讓 Oh My Posh 能正常接管
<#
`$1
#>
"@)
        $modified = $true
        Write-Log "已在設定檔中註解自訂 prompt 函式"
    }

    # 找出所有 Oh My Posh 初始化行
    $initLines = Get-OMPInitLines -ProfileContent $content

    if ($initLines.Count -eq 0) {
        # 沒有找到初始化行：使用預設主題新增一行
        $defaultTheme = if ($env:POSH_THEMES_PATH) {
            Join-Path $env:POSH_THEMES_PATH "jandedobbeleer.omp.json"
        } else {
            "~/.oh-my-posh/themes/jandedobbeleer.omp.json"
        }
        $initLine = "`noh-my-posh init pwsh --config '$defaultTheme' | Invoke-Expression`n"
        $content += $initLine
        $modified = $true
        Write-Log "已在設定檔加入 Oh My Posh 初始化行"
    }
    elseif ($initLines.Count -gt 1) {
        # 有多個初始化行：保留第一行，其餘全部註解
        if (-not $modified) { Backup-File -Path $ProfilePath }
        $first = $true
        foreach ($match in $initLines) {
            if ($first) { $first = $false; continue }
            $original = $match.Value
            $commented = "# [Fix-SplitPanePersistence] 已註解重複的初始化行：`n# $original"
            $content = $content.Replace($original, $commented)
        }
        $modified = $true
        Write-Log "已註解重複的 Oh My Posh 初始化行"
    }

    if ($modified -and $content -ne $originalContent) {
        if ($PSCmdlet.ShouldProcess($ProfilePath, "更新設定檔")) {
            Set-Content -Path $ProfilePath -Value $content -ErrorAction Stop
            $script:ChangesMode = $true
        }
        return $true
    }
    return $false
    }
    catch {
        Write-Log "更新設定檔時發生錯誤：$_"
        return $false
    }
}

function Get-UserThemePath {
    param([string]$OriginalThemePath)

    $userThemeDir = if ($ThemePath) { $ThemePath } else {
        Join-Path $env:LOCALAPPDATA "oh-my-posh\themes"
    }

    if (-not (Test-Path $userThemeDir)) {
        if ($PSCmdlet.ShouldProcess($userThemeDir, "建立主題資料夾")) {
            New-Item -ItemType Directory -Path $userThemeDir -Force | Out-Null
            Write-Log "已建立使用者主題資料夾：$userThemeDir" -Verbose
        }
    }

    $themeName = Split-Path $OriginalThemePath -Leaf
    return Join-Path $userThemeDir $themeName
}

function Ensure-ThemeIsWritable {
    param([string]$ProfilePath, [string]$CurrentThemePath)

    if (-not $CurrentThemePath -or -not (Test-Path $CurrentThemePath)) {
        Write-Log "找不到主題檔案：$CurrentThemePath" -Verbose
        return $null
    }

    # 檢查主題是否位於內建主題資料夾
    $poshThemesPath = $env:POSH_THEMES_PATH
    $isBuiltIn = $poshThemesPath -and $CurrentThemePath.StartsWith($poshThemesPath, [StringComparison]::OrdinalIgnoreCase)

    if ($isBuiltIn) {
        $userThemePath = Get-UserThemePath -OriginalThemePath $CurrentThemePath

        if ($PSCmdlet.ShouldProcess($CurrentThemePath, "將主題複製到使用者資料夾")) {
            Copy-Item -Path $CurrentThemePath -Destination $userThemePath -Force
            Write-Log "已將主題複製到使用者資料夾：$userThemePath"

            # 更新設定檔以使用新的主題路徑
            $profileContent = Get-Content $ProfilePath -Raw
            $escapedOld = [regex]::Escape($CurrentThemePath)
            # 同時處理 $env: 版本的路徑
            $envPath = $CurrentThemePath.Replace($poshThemesPath, '$env:POSH_THEMES_PATH')
            $escapedEnvOld = [regex]::Escape($envPath)

            $newContent = $profileContent -replace $escapedOld, $userThemePath
            $newContent = $newContent -replace [regex]::Escape('$env:POSH_THEMES_PATH'), $userThemePath.Replace((Split-Path $userThemePath -Leaf), '').TrimEnd('\')

            if ($newContent -ne $profileContent) {
                Backup-File -Path $ProfilePath
                Set-Content -Path $ProfilePath -Value $newContent -NoNewline
                Write-Log "已更新設定檔，改用使用者主題路徑"
            }
            $script:ChangesMode = $true
        }
        return $userThemePath
    }

    return $CurrentThemePath
}

function Update-ThemePwd {
    param([string]$ThemePath)

    if (-not $ThemePath -or -not (Test-Path $ThemePath)) {
        Write-Log "無法更新主題：找不到檔案 $ThemePath" -Verbose
        return $false
    }

    try {
        $themeContent = Get-Content $ThemePath -Raw
        $theme = $themeContent | ConvertFrom-Json -AsHashtable

        $currentPwd = $theme['pwd']
        if ($currentPwd -eq 'osc99') {
            Write-Log "主題已包含 pwd: osc99" -Verbose
            return $false
        }

        $theme['pwd'] = 'osc99'

        if ($PSCmdlet.ShouldProcess($ThemePath, "將 pwd 設為 osc99")) {
            Backup-File -Path $ThemePath
            $theme | ConvertTo-Json -Depth 100 | Set-Content -Path $ThemePath
            Write-Log "已更新主題：加入 pwd: osc99"
            $script:ChangesMode = $true
        }
        return $true
    }
    catch {
        Write-Log "更新主題時發生錯誤：$_"
        return $false
    }
}

function Find-TerminalSettings {
    $locations = @(
        # 封裝版（Microsoft Store）
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
        # 預覽版
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
        # 非封裝/可攜版
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    )

    foreach ($loc in $locations) {
        if (Test-Path $loc) {
            Write-Log "已找到 Windows Terminal 設定檔：$loc" -Verbose
            return $loc
        }
    }
    return $null
}

function Update-TerminalActions {
    param([string]$SettingsPath)

    if (-not $SettingsPath -or -not (Test-Path $SettingsPath)) {
        Write-Log "找不到 Windows Terminal settings.json"
        return $false
    }

    try {
        $settingsContent = Get-Content $SettingsPath -Raw
        # 解析前移除註解（Windows Terminal 允許 // 註解）
        $cleanJson = $settingsContent -replace '(?m)^\s*//.*$', '' -replace ',(\s*[}\]])', '$1'
        $settings = $cleanJson | ConvertFrom-Json -AsHashtable

        # 驗證 settings 結構
        if ($settings -isnot [hashtable] -and $settings -isnot [System.Collections.Specialized.OrderedDictionary]) {
            Write-Log "Windows Terminal settings 的結構不符合預期"
            return $false
        }

        if (-not $settings.ContainsKey('actions')) {
            $settings['actions'] = @()
        }

        # 檢查是否使用新版格式（獨立的 keybindings 陣列）
        $useKeybindingsArray = $settings.ContainsKey('keybindings')

        $desiredActions = @(
            @{
                keys = 'alt+shift+minus'
                command = @{
                    action = 'splitPane'
                    split = 'horizontal'
                    splitMode = 'duplicate'
                }
            },
            @{
                keys = 'alt+shift+plus'
                command = @{
                    action = 'splitPane'
                    split = 'vertical'
                    splitMode = 'duplicate'
                }
            },
            @{
                keys = 'ctrl+shift+d'
                command = @{
                    action = 'duplicateTab'
                }
            }
        )

        # 若要求 Copilot 按鍵：注意，這裡改由設定檔函式處理
        # Windows Terminal 無法同時使用 splitMode: duplicate 與自訂 commandline（目錄繼承會失效）

        $modified = $false

        if ($useKeybindingsArray) {
            # 新版 Windows Terminal 格式：actions 具有 id，keybindings 透過 id 參照
            foreach ($desired in $desiredActions) {
                $actionId = "User.custom.$($desired.keys -replace '[+]', '')"

                # 檢查是否已存在按鍵繫結
                $existingBinding = $settings['keybindings'] | Where-Object { $_.keys -eq $desired.keys }

                if (-not $existingBinding) {
                    # 新增帶有 id 的 action
                    $actionWithId = @{
                        command = $desired.command
                        id = $actionId
                    }
                    $settings['actions'] += $actionWithId

                    # 新增 keybinding
                    $settings['keybindings'] += @{
                        keys = $desired.keys
                        id = $actionId
                    }
                    $modified = $true
                    Write-Log "已新增動作：$($desired.keys)" -Verbose
                }
                else {
                    # 檢查是否需要更新動作（依 id 找 action）
                    $bindingId = $existingBinding.id
                    $existingAction = $settings['actions'] | Where-Object { $_.id -eq $bindingId }

                    if ($existingAction) {
                        $needsUpdate = $false
                        if ($desired.command.splitMode -and $existingAction.command.splitMode -ne 'duplicate') {
                            $needsUpdate = $true
                        }
                        if ($needsUpdate) {
                            $existingAction.command = $desired.command
                            $modified = $true
                            Write-Log "已更新動作：$($desired.keys)" -Verbose
                        }
                    }
                }
            }
        }
        else {
            # 舊版格式：actions 直接包含 keys
            foreach ($desired in $desiredActions) {
                $existingIndex = -1
                for ($i = 0; $i -lt $settings['actions'].Count; $i++) {
                    $action = $settings['actions'][$i]
                    if ($action.keys -eq $desired.keys) {
                        $existingIndex = $i
                        break
                    }
                }

                if ($existingIndex -ge 0) {
                    $existing = $settings['actions'][$existingIndex]
                    $needsUpdate = $false

                    if ($desired.command.splitMode) {
                        if ($existing.command -is [hashtable]) {
                            if ($existing.command.splitMode -ne 'duplicate') {
                                $needsUpdate = $true
                            }
                        } else {
                            $needsUpdate = $true
                        }
                    }

                    if ($needsUpdate) {
                        $settings['actions'][$existingIndex] = $desired
                        $modified = $true
                        Write-Log "已更新動作：$($desired.keys)" -Verbose
                    }
                }
                else {
                    $settings['actions'] += $desired
                    $modified = $true
                    Write-Log "已新增動作：$($desired.keys)" -Verbose
                }
            }
        }

        if ($modified) {
            if ($PSCmdlet.ShouldProcess($SettingsPath, "更新 Windows Terminal 動作/按鍵繫結")) {
                Backup-File -Path $SettingsPath
                $settings | ConvertTo-Json -Depth 100 | Set-Content -Path $SettingsPath
                Write-Log "已更新 Windows Terminal settings.json"
                $script:ChangesMode = $true
            }
            return $true
        }
        else {
            Write-Log "Windows Terminal 動作/按鍵繫結已設定完成" -Verbose
            return $false
        }
    }
    catch {
        Write-Log "更新 Windows Terminal settings.json 時發生錯誤：$_"
        return $false
    }
}

# Main execution
Write-Log "開始執行 Fix-SplitPanePersistence..."

# 步驟 1：確保設定檔存在
$profilePath = Ensure-ProfileExists
Write-Log "設定檔路徑：$profilePath" -Verbose

# 步驟 2：檢查 Oh My Posh
$ompInstalled = Get-OMPInstalled

if ($ompInstalled) {
    Write-Log "偵測到 Oh My Posh" -Verbose

    # 步驟 2a：檢查 Oh My Posh 版本
    $ompVersion = Get-OMPVersion
    $versionCompatible = Test-OMPVersionCompatible -CurrentVersion $ompVersion

    if ($ompVersion) {
        Write-Log "Oh My Posh 版本：$ompVersion" -Verbose
    }

    $proceedWithOMP = $true

    if (-not $versionCompatible) {
        Show-OMPVersionWarning -CurrentVersion $ompVersion

        # WhatIf 模式下：只顯示警告並繼續
        if ($WhatIfPreference) {
            Write-Host "  [DryRun] 原本會詢問你是否確認繼續，但目前為 WhatIf 模式，因此直接繼續" -ForegroundColor Gray
            Write-Host ""
        }
        else {
            # 詢問使用者是否確認繼續
            # 除了 'y' 或 'Y' 以外（包含直接按 Enter 空白）一律視為「否」（安全預設）
            $response = Read-Host "仍要繼續嗎？這可能會破壞你的 Oh My Posh 設定。（y/N）"
            if ($response -notmatch '^[Yy]') {
                Write-Host ""
                Write-Host "  將略過 Oh My Posh 主題修改。" -ForegroundColor Yellow
                Write-Host "  請先更新 Oh My Posh，然後再次執行本腳本。" -ForegroundColor Yellow
                Write-Host ""
                $proceedWithOMP = $false
            }
            else {
                Write-Host ""
                Write-Host "  將繼續執行 Oh My Posh 相關修改..." -ForegroundColor Yellow
                Write-Host ""
            }
        }
    }

    if ($proceedWithOMP) {
        # 步驟 3：修正設定檔的 OMP 初始化
        $null = Fix-ProfileOMPInit -ProfilePath $profilePath

        # 步驟 4：取得並確保主題可寫
        $profileContent = Get-Content $profilePath -Raw
        $themePath = Get-ThemePathFromProfile -ProfileContent $profileContent
        Write-Log "偵測到主題路徑：$themePath" -Verbose

        if ($themePath) {
            $writableThemePath = Ensure-ThemeIsWritable -ProfilePath $profilePath -CurrentThemePath $themePath

            # 步驟 5：更新主題的 pwd 設定
            if ($writableThemePath) {
                $null = Update-ThemePwd -ThemePath $writableThemePath
            }
        }
        else {
            Write-Log "無法從設定檔偵測主題路徑"
        }
    }
}
else {
    Write-Log "未安裝 Oh My Posh：將加入會送出 OSC 9;9 的 prompt 函式"

    # 加入 prompt 函式：送出 OSC 9;9 以供 Windows Terminal 追蹤目前目錄
    $profileContent = Get-Content $profilePath -Raw
    if (-not $profileContent) { $profileContent = "" }

    # 檢查是否已存在 OSC 9;9 prompt 或其標記
    if ($profileContent -notmatch 'OSC 9;9' -and $profileContent -notmatch '\[char\]27\]\]9;9') {
        $oscPromptFunction = @'

# OSC 9;9 - 告訴 Windows Terminal 目前目錄（用於分割窗格/複製分頁時繼承目錄）
# 由 Fix-SplitPanePersistence.ps1 新增
function prompt {
    $loc = $executionContext.SessionState.Path.CurrentLocation
    $out = ""
    if ($loc.Provider.Name -eq "FileSystem") {
        $out += "$([char]27)]9;9;`"$($loc.ProviderPath)`"$([char]27)\"
    }
    $out += "PS $loc$('>' * ($nestedPromptLevel + 1)) "
    return $out
}
'@
        if ($PSCmdlet.ShouldProcess($profilePath, "加入 OSC 9;9 prompt 函式")) {
            Backup-File -Path $profilePath
            Add-Content -Path $profilePath -Value $oscPromptFunction
            Write-Log "已在設定檔加入 OSC 9;9 prompt 函式"
            $script:ChangesMode = $true
        }
    }
    else {
        Write-Log "設定檔已包含 OSC 9;9 prompt 設定" -Verbose
    }
}

# 步驟 6：更新 Windows Terminal
$terminalSettings = Find-TerminalSettings
if ($terminalSettings) {
    $null = Update-TerminalActions -SettingsPath $terminalSettings
}
else {
    Write-Log "找不到 Windows Terminal settings.json：略過 Terminal 設定"
}

# 步驟 7：若有指定，加入 Copilot 分割窗格函式
if ($Copilot) {
    $profileContent = Get-Content $profilePath -Raw
    if ($profileContent -notmatch 'Split-Copilot') {
        $copilotFunction = @'

# 分割窗格並在目前目錄啟動 GitHub Copilot CLI
function Split-Copilot {
    wt -w 0 split-pane -d "$PWD" pwsh -NoLogo -NoExit -Command "copilot"
}
Set-Alias -Name spc -Value Split-Copilot
'@
        if ($PSCmdlet.ShouldProcess($profilePath, "加入 Split-Copilot 函式")) {
            Backup-File -Path $profilePath
            Add-Content -Path $profilePath -Value $copilotFunction
            Write-Log "已在設定檔加入 Split-Copilot 函式（別名：spc）"
            $script:ChangesMode = $true
        }
    }
    else {
        Write-Log "設定檔已包含 Split-Copilot 函式" -Verbose
    }
}

# 步驟 8：檢查並修復 WSL 設定檔（Ubuntu.exe 問題）
if ($terminalSettings) {
    try {
        $settingsContent = Get-Content $terminalSettings -Raw
        $settings = $settingsContent | ConvertFrom-Json
        $wslProfiles = $settings.profiles.list | Where-Object {
            $_.source -like "*WSL*" -or $_.source -like "*Ubuntu*" -or $_.name -like "*Ubuntu*" -or $_.name -like "*WSL*"
        }

        $wslFixed = $false

        foreach ($wslProfile in $wslProfiles) {
            # 若已使用 wsl.exe -d，直接略過
            if ($wslProfile.commandline -match '^wsl(\.exe)?\s+-d\s+') {
                continue
            }

            # 檢查是否使用預設啟動器（無 commandline）或 Ubuntu.exe
            if (-not $wslProfile.commandline -or $wslProfile.commandline -match 'Ubuntu.*\.exe') {
                # 嘗試找出對應的發行版名稱
                $distroName = $null
                $wslDistros = wsl -l -q 2>$null | Where-Object { $_ -and $_.Trim() }

                foreach ($distro in $wslDistros) {
                    $distro = $distro.Trim() -replace '\x00', ''  # 移除 wsl 輸出中的 NUL 字元
                    if ($wslProfile.name -match [regex]::Escape($distro) -or $distro -match 'Ubuntu') {
                        $distroName = $distro
                        break
                    }
                }

                if ($distroName) {
                    $newCommandline = "wsl.exe -d $distroName"

                    if ($PSCmdlet.ShouldProcess("WSL 設定檔 '$($wslProfile.name)'", "將 commandline 變更為 '$newCommandline'")) {
                        # 更新設定檔
                        $wslProfile | Add-Member -NotePropertyName 'commandline' -NotePropertyValue $newCommandline -Force
                        $wslFixed = $true
                        Write-Log "已修復 WSL 設定檔 '$($wslProfile.name)'：改用 $newCommandline"
                    }
                }
            }
        }

        if ($wslFixed) {
            Backup-File -Path $terminalSettings
            $settings | ConvertTo-Json -Depth 100 | Set-Content -Path $terminalSettings
            $script:ChangesMode = $true
            Write-Host ""
            Write-Host "  已更新 WSL 設定檔：分割窗格時會保留目錄！" -ForegroundColor Green
            Write-Host "  參考：https://github.com/microsoft/terminal/issues/3158" -ForegroundColor Gray
            Write-Host ""
        }
    }
    catch {
        Write-Log "無法檢查 WSL 設定檔：$_" -Verbose
    }
}

# Summary
if ($WhatIfPreference) {
    Write-Log "乾跑完成：未做任何變更"
}
elseif ($script:ChangesMode) {
    Write-Log "完成！請重新啟動終端機讓變更生效。"
}
else {
    Write-Log "完成！不需要任何變更——目前已設定完成。"
}
