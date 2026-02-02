# Fix-SplitPanePersistence

**一鍵修復 Windows Terminal 的分割窗格與複製分頁，讓它們保留你目前的工作目錄。**

當你在 Windows Terminal 分割窗格或複製分頁時，新開的窗格常常會跑回家目錄，而不是停留在你原本所在的位置。本腳本會把這件事一次修好、長治久安。

## 問題在哪裡

預設情況下，Windows Terminal 並不知道你的 Shell 目前在哪個目錄——它不可能自己知道，因為必須由你的 Shell 主動告訴它！請記住：Terminal（終端機）、Console（主控台）、Shell（殼層）、以及 Prompt（提示字元）是不同層次的東西。當你按下 `Alt+Shift+-` 做水平分割，或按下 `Ctrl+Shift+D` 複製分頁時，新啟動的 Shell 往往會從 `~` 或 `C:\Users\YourName` 重新開始。

當你已經深入某個專案資料夾、或正在使用 Agent 而想要「就在同一個目錄再開一個終端」時，這種行為真的很惱人。

## 解法是什麼

本腳本會把三件事設定到可以互相配合：

1. **Oh My Posh** 送出 [OSC 99 逸出序列](https://github.com/JanDeDobbeleer/oh-my-posh/discussions/1532)，把目前目錄告訴 Windows Terminal
2. **Windows Terminal** 的按鍵繫結使用 `splitMode: duplicate` 來繼承該目錄
3. **你的 PowerShell 設定檔**（profile）會被整理到正確狀態，讓上述機制確實生效

## 快速開始

```powershell
# 預覽將會變更的內容（不會真的修改）
.\Fix-SplitPanePersistence.ps1 -WhatIf

# 套用修復
.\Fix-SplitPanePersistence.ps1

# 重新啟動終端機，接著使用：
#   Alt+Shift+-    → 水平分割（同一目錄）
#   Alt+Shift++    → 垂直分割（同一目錄）
#   Ctrl+Shift+D   → 複製分頁（同一目錄）

# 選用：加入 GitHub Copilot CLI 整合
.\Fix-SplitPanePersistence.ps1 -Copilot
#   之後輸入 'spc'，即可分割窗格 + 在目前目錄啟動 Copilot
```

## 它會做什麼

### 1. PowerShell 設定檔（`$PROFILE`）

- 若你的設定檔不存在，會先建立
- 確保 Oh My Posh 以 `oh-my-posh init pwsh --config '<theme>' | Invoke-Expression` 正確初始化
- 將任何會覆蓋 Oh My Posh 的自訂 `function prompt { }` 區塊註解起來（並先備份）
- 若存在重複的 Oh My Posh 初始化行，會將多餘的行註解掉

### 2. Oh My Posh 主題（若已安裝）

- **檢查你的 Oh My Posh 版本**：若低於 v3.151.0（`pwd: osc99` 所需的最低版本）會警告
- 從設定檔中找出你目前使用的主題
- 在主題 JSON 根物件加入 `"pwd": "osc99"`
- 若主題位於內建主題資料夾，會先複製到 `%LOCALAPPDATA%\oh-my-posh\themes`（避免更新時覆蓋你的修改）
- 若版本不相容，會要求你確認是否繼續，以避免破壞現有設定

### 2b. 沒有 Oh My Posh？沒問題

如果你沒有安裝 Oh My Posh，本腳本會在你的設定檔加入一個 `prompt` 函式，直接送出 [OSC 9;9 逸出序列](https://learn.microsoft.com/en-us/windows/terminal/tutorials/new-tab-same-directory#powershell-powershellexe-or-pwshexe)。這樣 Windows Terminal 也能得知你目前的目錄，而不需要 OMP。

### 3. Windows Terminal 設定

- 在 `settings.json` 新增或更新按鍵繫結：

| 快捷鍵 | 動作 |
| ---------- | -------- |
| `Alt+Shift+-` | 水平分割窗格（同一目錄） |
| `Alt+Shift++` | 垂直分割窗格（同一目錄） |
| `Ctrl+Shift+D` | 複製分頁（同一目錄） |

> **注意：** 以上是 Windows Terminal 的預設快捷鍵。本腳本會把它們更新為使用 `splitMode: duplicate`，以便保留目前目錄。若你曾自訂這些按鍵，本腳本會更新你既有的繫結，而不是新增一堆重複項；你的其他自訂動作也會被保留。

### 加分項：GitHub Copilot CLI 整合

以 `-Copilot` 執行，會在你的 PowerShell 設定檔加入一個輔助函式：

```powershell
.\Fix-SplitPanePersistence.ps1 -Copilot
```

它會加入 `Split-Copilot`（別名：`spc`）。重新啟動終端機後：

```powershell
spc   # 分割窗格，並在目前目錄啟動 Copilot CLI
```

> **為什麼用函式而不是按鍵繫結？** Windows Terminal 無法把 `splitMode: duplicate`（用於繼承目錄）與自訂 `commandline` 合併使用。`spc` 函式透過 `wt split-pane -d "$PWD"` 明確傳入目前目錄，繞過此限制。

這會在新的窗格中開啟 [GitHub Copilot CLI](https://github.com/github/gh-copilot)，而且就位於你正在工作的目錄。

## 為什麼這應該是預設行為

目前的預設行為既出人意料，也不利生產力：

- **使用者期待**：「我想要在 *這裡* 再開一個終端」
- **實際行為**：新終端開在家目錄
- **切換成本**：每次都得再 `cd` 回專案資料夾

多數人會先被這個痛點折磨一陣子，接著花時間研究 OSC 逸出碼、Shell 整合、以及 Windows Terminal 設定。本腳本把這些研究濃縮成一個指令。

### 技術背景

Windows Terminal 能保留工作目錄，但前提是 Shell 必須主動「告訴」它你在哪裡。PowerShell 預設並不會做這件事。Oh My Posh 在主題加入 `"pwd": "osc99"` 後，就能送出必要的逸出序列（OSC 99）。

Windows Terminal 按鍵繫結中的 `splitMode: duplicate` 會指示它使用 Shell 整合機制（例如 OSC 99），而不是啟動一個全新的 Shell（自然就回到家目錄）。

## 參數

| 參數 | 說明 |
| ----------- | ------------- |
| `-WhatIf` | 乾跑模式。只顯示將會變更的內容，不會真的修改任何檔案。 |
| `-Verbose` | 顯示所有操作的詳細記錄。 |
| `-ThemePath` | 指定使用者可寫入的主題資料夾（預設：`%LOCALAPPDATA%\oh-my-posh\themes`）。 |
| `-Copilot` | 在設定檔加入 `Split-Copilot`（別名：`spc`），用於在分割窗格中啟動 Copilot CLI。 |

## 安全設計

- **版本檢查**：偵測 Oh My Posh 版本，若不相容（< v3.151.0）會先警告再動手
- **備份**：每個被修改的檔案都會建立含時間戳的備份（例如 `settings.json.bak-20240115-143022-789`）
- **可重複執行（Idempotent）**：重複執行是安全的；若已設定完成，就不會再做多餘變更
- **優雅降級**：若未安裝 Oh My Posh，腳本會改在設定檔加入 OSC 9;9 的 `prompt` 函式作為替代方案

## 回復（Rollback）

要取消變更，從備份還原即可：

```powershell
# 尋找備份
Get-ChildItem $env:USERPROFILE -Filter "*.bak-*" -Recurse
Get-ChildItem "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal*" -Filter "*.bak-*" -Recurse

# 還原某個備份（範例）
Copy-Item "settings.json.bak-20240115-143022" "settings.json"
```

## 需求

- Windows 11（或安裝 Windows Terminal 的 Windows 10）
- PowerShell 7+（`pwsh`）
- Windows Terminal（Store 版或獨立版）
- Oh My Posh v3.151.0+（選用——若未安裝，腳本會加入替代用的提示字元函式）
  - **注意**：目前 Oh My Posh 主流版本為 v11+。這裡的 v3.151.0 最低版本指的是 `pwd: osc99` 功能開始支援的版本（在版本號跳到 v11 之前就已加入）。

### Oh My Posh 版本提醒

本腳本會修改你的 Oh My Posh 主題，在根物件加入 `"pwd": "osc99"`；這需要 **Oh My Posh v3.151.0 或更新版本**（所有 v11+ 版本都支援）。如果你的版本較舊，腳本會：

1. 偵測你目前的版本
2. 顯示警告與升級方式
3. 在修改前要求你確認
4. 若你拒絕，則略過 Oh My Posh 的主題修改

檢查版本：`oh-my-posh --version`

升級：

```powershell
winget upgrade JanDeDobbeleer.OhMyPosh
```

## WSL 支援

本腳本為 Windows Terminal 設定的按鍵繫結同樣適用於 WSL 的設定檔！腳本也會自動偵測並修復一個常見問題。

### 自動修復 WSL 設定檔

預設情況下，Windows Terminal 可能使用發行版的啟動器（例如 `Ubuntu.exe`），而它**不會把目前工作目錄傳給 Shell**。腳本會自動偵測此狀況，並把設定檔改為使用 `wsl.exe -d <distro>`。

```powershell
# 腳本在乾跑時會顯示類似內容：
What if：在目標「WSL 設定檔 'Ubuntu-24.04'」上執行作業「將 commandline 變更為 'wsl.exe -d Ubuntu-24.04'」。
```

為什麼需要這樣做，請參考 [microsoft/terminal#3158](https://github.com/microsoft/terminal/issues/3158#issuecomment-2789336476)。

### 設定你的 Shell

請確保你的 Shell 會送出 OSC 9;9 逸出序列：

#### 選項 1：在 WSL 使用 Oh My Posh（建議）

如果你在 WSL 也使用 Oh My Posh，只要確保主題根層級有 `pwd: osc99`：

```json
{
  "version": 4,
  "pwd": "osc99",
  ...
}
```

接著在 `~/.bashrc` 初始化（不要放在 `.profile`；bashrc 會在分割窗格這種「非登入 Shell」情境下執行）：

```bash
eval "$(oh-my-posh init bash --config '~/your-theme.omp.json')"
```

Oh My Posh 會自動幫你處理 `wslpath` 的路徑轉換。

#### 選項 2：不使用 Oh My Posh

把以下內容加入 `~/.bashrc`：

```bash
PROMPT_COMMAND=${PROMPT_COMMAND:+"$PROMPT_COMMAND; "}'printf "\e]9;9;%s\e\\" "$(wslpath -w "$PWD")"'
```

`wslpath -w` 會把 Linux 路徑（`/home/user/project`）轉成 Windows 路徑（`\\wsl$\Ubuntu\home\user\project`），讓 Windows Terminal 能理解。

#### Zsh 使用者

加入到 `~/.zshrc`：

```zsh
keep_current_path() {
  printf "\e]9;9;%s\e\\" "$(wslpath -w "$PWD")"
}
precmd_functions+=(keep_current_path)
```

修改完成後請重新啟動終端機。此後分割窗格與複製分頁也會保留你的 WSL 目錄。

## 參考資料

- [Microsoft 文件：在相同目錄開新分頁](https://learn.microsoft.com/en-us/windows/terminal/tutorials/new-tab-same-directory#powershell-powershellexe-or-pwshexe) - Shell 整合的官方教學
- [Oh My Posh 討論 #1532](https://github.com/JanDeDobbeleer/oh-my-posh/discussions/1532) - OSC 99 支援的原始討論
- [Windows Terminal：Shell 整合](https://learn.microsoft.com/en-us/windows/terminal/tutorials/shell-integration) - 逸出序列與整合機制深度解說
- [Oh My Posh：pwd 設定](https://ohmyposh.dev/docs/configuration/general#settings) - OSC 99/7/51 設定文件

## 授權

MIT
