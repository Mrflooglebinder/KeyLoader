# KeyLoader — Load Secure Session Key into PowerShell

`KeyLoader.ps1` loads a secret key into the current PowerShell session as a process-level environment variable.

It is designed for short-lived API keys, LLM keys, service tokens, internal tool secrets, and other session-only credentials where you want the key available to the current shell and any child processes you deliberately launch from it.

The loader:

- prompts for a provider/name, key mode, and key value;
- hides the key while it is entered;
- generates a predictable environment variable name;
- stores the key in the current process environment only;
- optionally updates the PowerShell window title as a reminder that keys are loaded;
- returns a structured result object so parent scripts can use the generated variable name;
- avoids provider-specific variable-name assumptions such as `OPENAI_API_KEY` unless your own downstream script chooses to use them.

The loader does **not** write the key to disk, the registry, the user environment, or the machine environment.

---

## Contents

- [1. Quick start](#1-quick-start)
  - [1.1 Download from the release package](#11-download-from-the-release-package)
  - [1.2 First-time PowerShell setup](#12-first-time-powershell-setup)
  - [1.3 Run interactively](#13-run-interactively)
  - [1.4 Run with parameters](#14-run-with-parameters)
- [2. What the loader creates](#2-what-the-loader-creates)
  - [2.1 Naming pattern](#21-naming-pattern)
  - [2.2 Sanitising names](#22-sanitising-names)
  - [2.3 Read/write mode is a label](#23-readwrite-mode-is-a-label)
- [3. Interactive menu flow](#3-interactive-menu-flow)
  - [3.1 Provider menu](#31-provider-menu)
  - [3.2 Provider menu controls](#32-provider-menu-controls)
  - [3.3 Custom provider names](#33-custom-provider-names)
  - [3.4 Mode menu](#34-mode-menu)
  - [3.5 Key input](#35-key-input)
- [4. Parameters](#4-parameters)
- [5. Return object](#5-return-object)
- [6. Top-to-bottom script walkthrough](#6-top-to-bottom-script-walkthrough)
  - [6.1 Header and scope notes](#61-header-and-scope-notes)
  - [6.2 Comment-based help](#62-comment-based-help)
  - [6.3 Parameter block](#63-parameter-block)
  - [6.4 Execution wrapper](#64-execution-wrapper)
  - [6.5 Help exit path](#65-help-exit-path)
  - [6.6 Provider list](#66-provider-list)
  - [6.7 Screen clearing helper](#67-screen-clearing-helper)
  - [6.8 Environment-name sanitiser](#68-environment-name-sanitiser)
  - [6.9 Result object builder](#69-result-object-builder)
  - [6.10 Provider menu function](#610-provider-menu-function)
  - [6.11 Mode menu function](#611-mode-menu-function)
  - [6.12 Window-title function](#612-window-title-function)
  - [6.13 Warning setup](#613-warning-setup)
  - [6.14 Provider selection and validation](#614-provider-selection-and-validation)
  - [6.15 Mode selection and validation](#615-mode-selection-and-validation)
  - [6.16 Environment variable name construction](#616-environment-variable-name-construction)
  - [6.17 Secure key prompt](#617-secure-key-prompt)
  - [6.18 SecureString to environment variable conversion](#618-securestring-to-environment-variable-conversion)
  - [6.19 Key-content warnings](#619-key-content-warnings)
  - [6.20 Environment write](#620-environment-write)
  - [6.21 Cleanup block](#621-cleanup-block)
  - [6.22 Failure result paths](#622-failure-result-paths)
  - [6.23 Success result path](#623-success-result-path)
- [7. Calling from another PowerShell script](#7-calling-from-another-powershell-script)
  - [7.1 Correct parent call](#71-correct-parent-call)
  - [7.2 What not to do](#72-what-not-to-do)
  - [7.3 Parent script pattern](#73-parent-script-pattern)
- [8. Worker and subprocess pattern](#8-worker-and-subprocess-pattern)
- [9. Security model](#9-security-model)
  - [9.1 What is protected](#91-what-is-protected)
  - [9.2 Known limitations](#92-known-limitations)
  - [9.3 Safe handling rules](#93-safe-handling-rules)
- [10. Window title behaviour](#10-window-title-behaviour)
- [11. Troubleshooting](#11-troubleshooting)
- [12. Package/release download option](#12-packagerelease-download-option)
- [13. License](#13-license)
- [14. Handoff summary for other scripts or agents](#14-handoff-summary-for-other-scripts-or-agents)

---

## 1. Quick start

### 1.1 Download from the release package

For normal use, download the packaged release.

```text
https://github.com/Mrflooglebinder/KeyLoader/releases/latest
```

Download the release asset:

```text
KeyLoader.ps1
```

Place it somewhere convenient, for example:

```text
C:\Tools\KeyLoader\KeyLoader.ps1
```

or inside your project folder:

```text
.\tools\KeyLoader.ps1
```

This README explains how the script works. The released `KeyLoader.ps1` file is the source of truth for execution.

### 1.2 First-time PowerShell setup

If Windows blocks downloaded scripts, run these once for your current user:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
Unblock-File -Path .\KeyLoader.ps1
```

The execution policy command allows locally saved scripts to run for your user profile. `Unblock-File` removes the Windows downloaded-from-internet marker from this specific file.

### 1.3 Run interactively

Run the script:

```powershell
& .\KeyLoader.ps1
```

The script then walks through:

1. provider selection;
2. mode selection;
3. hidden key entry;
4. environment variable creation;
5. result output.

Interactive use normally creates a variable without `Type`, because `Type` is not prompted for in the menus.

Example result:

```text
Provider: OpenAI
Mode: Write
Generated environment variable: OPENAI_WRITE_KEY
```

### 1.4 Run with parameters

For predictable naming, pass the parameters directly:

```powershell
$result = & .\KeyLoader.ps1 -Name "OpenAI" -Mode "write" -Type "API"
```

This creates:

```text
OPENAI_WRITE_API_KEY
```

Use this form when a parent script needs to capture and reuse the generated variable name.

---

## 2. What the loader creates

### 2.1 Naming pattern

The loader creates a process-level environment variable using this pattern:

```text
<NAME>_<MODE>_<TYPE>_KEY
```

If `Type` is omitted:

```text
<NAME>_<MODE>_KEY
```

Examples:

```text
Name: OpenAI
Mode: write
Type: API
Generated environment variable: OPENAI_WRITE_API_KEY
```

```text
Name: OpenAI
Mode: read
Type omitted
Generated environment variable: OPENAI_READ_KEY
```

```text
Name: My Local LLM
Mode: write
Type: API
Generated environment variable: MY_LOCAL_LLM_WRITE_API_KEY
```

```text
Name: GitHub
Mode: write
Type: TOKEN
Generated environment variable: GITHUB_WRITE_TOKEN_KEY
```

`Type` should be a category word such as:

```text
API
TOKEN
SECRET
CLIENT
OAUTH
```

Do not pass a compound suffix like:

```text
API_KEY
```

because the loader always appends `_KEY`, so this would produce:

```text
OPENAI_WRITE_API_KEY_KEY
```

### 2.2 Sanitising names

The loader normalises each name part before joining them.

The sanitising rules are:

1. trim whitespace;
2. convert to uppercase;
3. replace anything that is not `A-Z` or `0-9` with `_`;
4. collapse repeated underscores;
5. remove leading and trailing underscores.

Examples:

```text
OpenAI            -> OPENAI
My Local LLM      -> MY_LOCAL_LLM
my-tool/api       -> MY_TOOL_API
  test key!!!     -> TEST_KEY
```

This keeps the generated environment variable readable and safe for PowerShell environment-variable access.

### 2.3 Read/write mode is a label

The loader accepts only:

```text
read
write
```

It stores them as:

```text
READ
WRITE
```

These are naming and intent labels only.

The loader does **not** enforce read-only or write permissions. Actual permissions come from the key you paste.

If you paste a write-capable key into a `read` slot, the loader cannot make it read-only.

---

## 3. Interactive menu flow

The interactive interface is deliberately simple and menu-driven.

### 3.1 Provider menu

If `-Name` is omitted, the script shows a provider menu.

Current provider list:

```text
1. OpenAI
2. Anthropic
3. Google
4. Microsoft
5. AWS
6. GitHub
7. HuggingFace
8. Cohere
9. Mistral
0. Other (User Defined)
```

The list is stored in the script near the top of the execution block:

```powershell
$KeyLoaderProviders = @(
  "OpenAI"
  "Anthropic"
  "Google"
  "Microsoft"
  "AWS"
  "GitHub"
  "HuggingFace"
  "Cohere"
  "Mistral"
  "Other"
)
```

The menu supports up to nine named providers using keys `1` through `9`.

`Other` is detected by value and shown as `0`.

### 3.2 Provider menu controls

In a host that supports single-key input, provider selection uses `ReadKey`.

Controls:

```text
1-9       choose one of the visible named providers
0         choose Other / User Defined
Q         abort
Escape    abort
H         show help
```

If `ReadKey` is unavailable, the script falls back to typed input using `Read-Host`.

Typed fallback accepts:

```text
1-9       choose one of the visible named providers
0         choose Other / User Defined
Q         abort
H         show help
```

The typed fallback is useful in hosts that do not support raw single-key input, such as some remote terminals, integrated terminals, or automation contexts.

### 3.3 Custom provider names

Choosing `0. Other` prompts:

```text
Enter provider name
```

The typed provider name is then sanitised the same way as any other `Name` value.

Examples:

```text
Input:  My Local LLM
Stored name part: MY_LOCAL_LLM
```

```text
Input:  internal/service A
Stored name part: INTERNAL_SERVICE_A
```

If no custom provider name is entered, the menu loops back and asks again.

### 3.4 Mode menu

If `-Mode` is omitted, the script shows the mode menu:

```text
1. Read
2. Write
Q or Escape to abort. H for help.
```

Single-key controls:

```text
1         read
2         write
Q         abort
Escape    abort
H         show help
```

Typed fallback accepts:

```text
1
2
read
write
q
h
```

After a valid typed fallback selection, the script clears the screen before continuing.

### 3.5 Key input

The key prompt uses:

```powershell
Read-Host "Paste key for $envVarName" -AsSecureString
```

The key is hidden while typed or pasted.

If no key is entered, the script aborts cleanly and returns a failure result.

---

## 4. Parameters

All parameters are optional. Supplied parameters skip their corresponding interactive prompt.

| Parameter | Type | Default | Behaviour |
|---|---|---:|---|
| `-Name` | string | prompted | Provider/system name. Skips provider menu when supplied. |
| `-Mode` | string | prompted | Must be `read` or `write`. Skips mode menu when supplied. |
| `-Type` | string | omitted | Optional category word included before `_KEY`. |
| `-MinimumKeyLength` | int | `8` | Adds a warning if pasted key is shorter. Set `0` to disable. Maximum is `512`. |
| `-NeutralTitle` | switch | off | Uses `KEYS LOADED` instead of provider-specific window title. |
| `-NoWindowTitle` | switch | off | Does not change the PowerShell window title. |
| `-Help` | switch | off | Shows comment-based help and exits. |

Examples:

```powershell
& .\KeyLoader.ps1
```

```powershell
& .\KeyLoader.ps1 -Name "OpenAI" -Mode "write" -Type "API"
```

```powershell
& .\KeyLoader.ps1 -Name "GitHub" -Mode "write" -Type "TOKEN" -NeutralTitle
```

```powershell
& .\KeyLoader.ps1 -Name "Internal Tool" -Mode "read" -MinimumKeyLength 0 -NoWindowTitle
```

```powershell
& .\KeyLoader.ps1 -Help
```

---

## 5. Return object

Every exit path returns a structured object.

Shape:

```text
Success
Message
Name
Mode
Type
EnvVarName
WindowTitle
Warnings
```

Successful example:

```text
Success     : True
Message     : Key loaded.
Name        : OPENAI
Mode        : WRITE
Type        : API
EnvVarName  : OPENAI_WRITE_API_KEY
WindowTitle : OPENAI WRITE KEY
Warnings    : {}
```

Failure example:

```text
Success     : False
Message     : No valid mode was selected.
Name        : OPENAI
Mode        :
Type        :
EnvVarName  :
WindowTitle :
Warnings    : {}
```

The result object lets parent scripts use the loader without guessing the generated environment variable name.

Typical parent script check:

```powershell
$result = & .\KeyLoader.ps1 -Name "OpenAI" -Mode "write" -Type "API"

if (-not $result.Success) {
  throw $result.Message
}

$keyEnvVarName = $result.EnvVarName
```

---

## 6. Top-to-bottom script walkthrough

This section explains the script in the same order the script runs.

It does **not** duplicate the full 700+ line script. Instead, it breaks the script into the same functional blocks used by the code and explains what each block is responsible for.

### 6.1 Header and scope notes

The header explains the core behaviour:

```powershell
# Securely load a key into this PowerShell session only.
# Stores the key in a generated environment variable:
# <NAME>_<MODE>_<TYPE>_KEY
# or, if Type is omitted:
# <NAME>_<MODE>_KEY
```

It also states the process-scope rule:

```powershell
# Scope note: the key is not written to disk or the user/machine environment.
# It lives in the current PowerShell process environment block only.
# Child processes started from this session may inherit it.
# Closing the parent PowerShell session removes it.
```

This is the main security boundary of the loader.

The key exists only in the current process environment block. It is not saved permanently by the loader.

### 6.2 Comment-based help

The script includes PowerShell comment-based help.

That allows:

```powershell
Get-Help .\KeyLoader.ps1
Get-Help .\KeyLoader.ps1 -Full
Get-Help .\KeyLoader.ps1 -Examples
```

It also supports:

```powershell
& .\KeyLoader.ps1 -Help
```

The help block covers:

1. synopsis;
2. description;
3. parameters;
4. examples;
5. first-time setup;
6. security notes;
7. repository link.

For best help support, run the script as a saved `.ps1` file. Direct console paste does not always provide a reliable `$PSCommandPath` for `Get-Help`.

### 6.3 Parameter block

The parameter block defines user inputs:

```powershell
param(
  [string]$Name,
  [string]$Mode,
  [string]$Type,
  [int]$MinimumKeyLength = 8,
  [switch]$NeutralTitle,
  [switch]$NoWindowTitle,
  [switch]$Help
)
```

The design rule is:

- if a value is supplied, use it;
- if a required value is missing, prompt interactively;
- if prompting fails, return a structured failure.

### 6.4 Execution wrapper

The script body is wrapped:

```powershell
& {
  $ErrorActionPreference = "Stop"
  ...
}
```

This wrapper keeps the loader self-contained and allows early `return` statements to return result objects without exiting the caller's whole PowerShell session.

`$ErrorActionPreference = "Stop"` turns many non-terminating errors into catchable terminating errors inside the loader.

### 6.5 Help exit path

The first runtime check is the help flag:

```powershell
if ($Help) {
  Get-Help $PSCommandPath -Full
  return
}
```

If `-Help` is supplied, the script displays help and exits before asking for provider, mode, or key input.

### 6.6 Provider list

The provider list is editable:

```powershell
$KeyLoaderProviders = @(
  "OpenAI"
  "Anthropic"
  "Google"
  "Microsoft"
  "AWS"
  "GitHub"
  "HuggingFace"
  "Cohere"
  "Mistral"
  "Other"
)
```

The provider list is only for convenience.

You can still bypass it entirely:

```powershell
& .\KeyLoader.ps1 -Name "Anything You Want" -Mode "write"
```

Provider-list rules:

1. named providers are displayed as numbered choices;
2. only the first nine named providers are shown;
3. `Other` is detected by value;
4. `Other` is shown as `0`;
5. selecting `Other` prompts for a custom name.

### 6.7 Screen clearing helper

The script uses a helper for screen clearing:

```powershell
function Clear-KeyLoaderScreen {
  try {
    Clear-Host
  }
  catch {
  }
}
```

Purpose:

1. reduce visible old prompts;
2. reduce shoulder-surfing context;
3. make repeated menu prompts cleaner;
4. avoid failing if a host does not support `Clear-Host`.

Screen clearing is not a security boundary. It only reduces casual exposure in the visible terminal area.

### 6.8 Environment-name sanitiser

`Convert-ToKeyPart` turns a user/provider/type value into a safe environment variable part:

```powershell
$clean = $Value.Trim().ToUpperInvariant()
$clean = $clean -replace '[^A-Z0-9]+', '_'
$clean = $clean -replace '_+', '_'
$clean = $clean.Trim('_')
```

This is used for:

```text
Name
Mode
Type
```

Mode is first validated as `read` or `write`, then normalised to `READ` or `WRITE`.

### 6.9 Result object builder

`New-LoaderResult` creates the object returned by the script.

The result includes:

```powershell
[pscustomobject]@{
  Success     = $Success
  Message     = $Message
  Name        = $Name
  Mode        = $Mode
  Type        = $Type
  EnvVarName  = $EnvVarName
  WindowTitle = $WindowTitle
  Warnings    = @($Warnings)
}
```

This prevents callers from having to parse console text.

Parent scripts should always inspect:

```powershell
$result.Success
$result.EnvVarName
$result.Warnings
```

### 6.10 Provider menu function

`Read-KeyLoaderName` is responsible for provider selection.

Process:

1. build the visible provider list;
2. display numbered options;
3. display `0. Other` if available;
4. accept single-key input if supported;
5. fall back to typed input if not;
6. loop on invalid input;
7. return `$null` if aborted.

The single-key path reads:

```powershell
$key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
$keyStr = $key.Character.ToString().ToUpperInvariant()
$vk = $key.VirtualKeyCode
```

Then it handles:

```text
Escape
Q
H
1-9
0
```

The typed fallback uses `Read-Host` and accepts the same meaningful options.

### 6.11 Mode menu function

`Read-KeyLoaderMode` handles `read`/`write` selection.

The mode menu is smaller than the provider menu:

```text
1. Read
2. Write
Q or Escape to abort. H for help.
```

The function returns exactly one of:

```text
read
write
null
```

The main script later converts this to:

```text
READ
WRITE
```

### 6.12 Window-title function

`Set-KeyLoaderWindowTitle` manages the optional reminder in the terminal title bar.

Inputs:

```powershell
[string]$Name
[string]$Mode
[string]$Type
[string]$EnvVarName
[switch]$NeutralTitle
[switch]$NoWindowTitle
```

Behaviour:

1. if `-NoWindowTitle` is set, do nothing;
2. track loaded key metadata in `$global:KeyLoaderLoadedKeys`;
3. remove stale entries whose environment variables no longer exist;
4. add the current key metadata;
5. generate a title;
6. attempt to assign `$Host.UI.RawUI.WindowTitle`;
7. return an object describing whether title update worked.

Example titles:

```text
OPENAI WRITE KEY
OPENAI READ+WRITE KEYS
MULTI KEYS
MULTI READ+WRITE KEYS
KEYS LOADED
```

The title contains no secret values.

With `-NeutralTitle`, the title is always:

```text
KEYS LOADED
```

### 6.13 Warning setup

Before user interaction, the script prepares warnings:

```powershell
$warnings = @()
$maximumMinimumKeyLength = 512
```

Then it clamps `MinimumKeyLength`:

```powershell
if ($MinimumKeyLength -lt 0) {
  $MinimumKeyLength = 0
} elseif ($MinimumKeyLength -gt $maximumMinimumKeyLength) {
  $MinimumKeyLength = $maximumMinimumKeyLength
}
```

Warnings are returned in the result object.

They do not normally stop the key from being stored.

### 6.14 Provider selection and validation

If `-Name` is missing, the script calls the provider menu:

```powershell
$Name = Read-KeyLoaderName -Providers $KeyLoaderProviders
```

Then it sanitises the result:

```powershell
$safeName = Convert-ToKeyPart $Name
```

If no valid name is available, it returns:

```text
Success: False
Message: No valid provider was selected.
```

or:

```text
Success: False
Message: No valid key name was provided.
```

### 6.15 Mode selection and validation

If `-Mode` is missing, the script calls the mode menu:

```powershell
$Mode = Read-KeyLoaderMode
```

Then it normalises and validates:

```powershell
$Mode = $Mode.Trim().ToLowerInvariant()

switch ($Mode) {
  "read"  { $safeMode = "READ" }
  "write" { $safeMode = "WRITE" }
  default { ... }
}
```

Invalid mode values return a structured failure.

### 6.16 Environment variable name construction

The script sanitises `Type` if present:

```powershell
$safeType = Convert-ToKeyPart $Type
```

Then it builds the name parts:

```powershell
$envNameParts = @($safeName, $safeMode)

if ($safeType) {
  $envNameParts += $safeType
}

$envNameParts += "KEY"
$envVarName = $envNameParts -join "_"
```

Examples:

```text
OPENAI + WRITE + API + KEY = OPENAI_WRITE_API_KEY
OPENAI + READ + KEY       = OPENAI_READ_KEY
```

This value becomes the official environment variable name returned to parent scripts.

### 6.17 Secure key prompt

The script prompts for the key after the generated variable name is known:

```powershell
$secureKey = Read-Host "Paste key for $envVarName" -AsSecureString
```

If the host cannot provide secure input, the script returns:

```text
Success: False
Message: Secure key input is not available in this host.
```

If the key is empty or `$null`, the script disposes the `SecureString` if needed and returns:

```text
Success: False
Message: No key was entered.
```

### 6.18 SecureString to environment variable conversion

PowerShell environment variables require a normal string value.

That means the script must briefly convert the `SecureString`:

```powershell
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
$plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
```

The script tracks conversion success explicitly:

```powershell
$conversionSucceeded = $false
```

If conversion fails, it returns a generic failure and does not include raw exception text in warnings.

Important limitation:

- the unmanaged BSTR is zeroed later;
- the managed .NET string cannot be forcibly zeroed;
- the string reference is removed, but the memory is reclaimed by .NET garbage collection later.

This is a limitation of storing secrets in process environment variables.

### 6.19 Key-content warnings

After conversion, the script checks for common paste mistakes.

Whitespace check:

```powershell
$startsWithWhitespace = [char]::IsWhiteSpace($plainKey[0])
$endsWithWhitespace   = [char]::IsWhiteSpace($plainKey[$plainKey.Length - 1])
```

Minimum length check:

```powershell
if (($MinimumKeyLength -gt 0) -and ($plainKey.Length -lt $MinimumKeyLength)) {
  ...
}
```

These checks are warning-only.

The script stores the key exactly as pasted.

If leading or trailing whitespace is present, the loader warns but does not trim it.

### 6.20 Environment write

The actual environment variable write is:

```powershell
Set-Item -Path "Env:$envVarName" -Value $plainKey
```

The script uses an explicit success flag:

```powershell
$setItemSucceeded = $false
```

Only if `Set-Item` returns without error does the script set:

```powershell
$setItemSucceeded = $true
```

This avoids relying on exception-message text as the success/failure indicator.

### 6.21 Cleanup block

The cleanup block runs whether the write succeeds or fails.

It zeroes the unmanaged BSTR:

```powershell
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
```

It removes the local plain-string variable reference:

```powershell
Remove-Variable -Name plainKey -Scope Local -Force -ErrorAction SilentlyContinue
```

It disposes the `SecureString`:

```powershell
$secureKey.Dispose()
```

Then it removes the local `secureKey` variable reference:

```powershell
Remove-Variable -Name secureKey -Scope Local -Force -ErrorAction SilentlyContinue
```

This cleanup is important, but it does not change the fact that the key is now intentionally stored in the process environment variable.

### 6.22 Failure result paths

The script has structured failure exits for:

1. unavailable interactive name selection;
2. invalid provider;
3. invalid name after sanitising;
4. unavailable or invalid mode selection;
5. invalid supplied mode;
6. unavailable secure key input;
7. empty key input;
8. SecureString conversion failure;
9. environment variable write failure;
10. defensive final check failure.

Failure result shape:

```text
Success: False
Message: <reason>
EnvVarName: <name if already generated>
Warnings: <warnings gathered so far>
```

The script avoids returning raw exception text for key conversion or environment write failures.

### 6.23 Success result path

After `Set-Item`, the script verifies the environment variable is readable:

```powershell
[Environment]::GetEnvironmentVariable($envVarName, "Process")
```

If present, it prints a success summary and returns:

```text
Success: True
Message: Key loaded.
Name: <sanitised name>
Mode: <READ or WRITE>
Type: <sanitised type or blank>
EnvVarName: <generated environment variable>
WindowTitle: <title or blank>
Warnings: <warning list>
```

This is the path parent scripts should expect when the key has loaded successfully.

---

## 7. Calling from another PowerShell script

### 7.1 Correct parent call

Call the loader in the same PowerShell process:

```powershell
$result = & .\KeyLoader.ps1 -Name "OpenAI" -Mode "write" -Type "API"
```

This makes the created environment variable available to the parent script.

### 7.2 What not to do

Do not call it like this if the parent needs the key afterward:

```powershell
powershell.exe -File .\KeyLoader.ps1 -Name "OpenAI" -Mode "write" -Type "API"
pwsh -File .\KeyLoader.ps1 -Name "OpenAI" -Mode "write" -Type "API"
```

Those create a child PowerShell process. The key will be loaded there, then lost when that process exits.

### 7.3 Parent script pattern

```powershell
$loaderResult = & .\KeyLoader.ps1 -Name "OpenAI" -Mode "write" -Type "API"

if (-not $loaderResult.Success) {
  throw "Key load failed: $($loaderResult.Message)"
}

$keyEnvVarName = $loaderResult.EnvVarName

# Pass the variable name around, not the actual key value.
Write-Host "Loaded key environment name: $keyEnvVarName"
```

When the parent needs to use the key:

```powershell
$key = [Environment]::GetEnvironmentVariable($keyEnvVarName, "Process")

if ([string]::IsNullOrWhiteSpace($key)) {
  throw "Key was not found in this PowerShell session: $keyEnvVarName"
}

$headers = @{
  Authorization = "Bearer $key"
}

# Use $headers in the request.
# Do not print $headers because it contains the key.

Remove-Variable key -ErrorAction SilentlyContinue
```

The provider does not care what the local environment variable is called. Your script reads the key value and sends the key value in the request.

---

## 8. Worker and subprocess pattern

If a parent script loads the key first, worker processes started afterward may inherit the environment variable.

Pass the environment variable name to the worker, not the key value.

Parent:

```powershell
$loaderResult = & .\KeyLoader.ps1 -Name "OpenAI" -Mode "write" -Type "API"

if (-not $loaderResult.Success) {
  throw "Key load failed: $($loaderResult.Message)"
}

& .\Worker.ps1 -KeyEnvVarName $loaderResult.EnvVarName
```

Worker:

```powershell
param(
  [string]$KeyEnvVarName
)

$key = [Environment]::GetEnvironmentVariable($KeyEnvVarName, "Process")

if ([string]::IsNullOrWhiteSpace($key)) {
  throw "Key was not found: $KeyEnvVarName"
}

$headers = @{
  Authorization = "Bearer $key"
}

# Make the request here.
# Do not print $key or $headers.

Remove-Variable key -ErrorAction SilentlyContinue
```

Multiple workers can read the same environment variable at the same time.

No lock is needed just to read the key.

A lock is only needed if different parts of your system try to overwrite the same shared variable name. This loader avoids that by generating specific names such as:

```text
OPENAI_READ_API_KEY
OPENAI_WRITE_API_KEY
```

---

## 9. Security model

### 9.1 What is protected

The loader protects against common accidental exposure:

- the key is not typed visibly;
- the key is not hard-coded in the script;
- the key is not written to disk by this loader;
- the key is not saved to the user or machine environment;
- raw exception text is not returned for key conversion/write failures;
- the BSTR copy is zeroed after conversion;
- the `SecureString` is disposed;
- local variable references are removed where practical.

### 9.2 Known limitations

The loader cannot avoid every in-memory exposure.

Known limitations:

1. Environment variables store string values.
2. The key must briefly exist as a normal managed .NET string.
3. Managed .NET strings cannot be forcibly zeroed.
4. Process environment variables may be inherited by child processes.
5. Any script running in the same session can read the process environment variable if it knows or discovers the name.
6. The window title can reveal provider/mode metadata unless `-NeutralTitle` or `-NoWindowTitle` is used.

These are expected tradeoffs for a session-only environment-variable loader.

### 9.3 Safe handling rules

Do:

- close the PowerShell window when finished;
- pass environment variable names between scripts, not key values;
- read the key only when needed;
- avoid printing request headers if they contain the key;
- use `-NeutralTitle` on shared or recorded screens;
- use `-NoWindowTitle` if even neutral title changes are undesirable.

Do not:

- paste real keys into source code;
- pass the actual key as a command-line argument;
- print the key;
- log the key;
- write the key to disk;
- rely on `read`/`write` labels to enforce permissions.

---

## 10. Window title behaviour

By default, the loader updates the PowerShell window title as a reminder that session keys are loaded.

Examples:

```text
OPENAI WRITE KEY
OPENAI READ+WRITE KEYS
MULTI KEYS
MULTI READ+WRITE KEYS
```

With `-NeutralTitle`:

```text
KEYS LOADED
```

With `-NoWindowTitle`, the loader does not change the title.

The title contains no key values.

It may still reveal metadata such as provider or mode unless `-NeutralTitle` is used.

---

## 11. Troubleshooting

### The script will not run

Run once:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
Unblock-File -Path .\KeyLoader.ps1
```

### Help does not display correctly

Use the saved script file:

```powershell
Get-Help .\KeyLoader.ps1 -Full
```

The `-Help` flag depends on `$PSCommandPath`, which is reliable when running as a `.ps1` file.

### The key is not available to the parent script

Make sure you called the loader with call operator `&` inside the same PowerShell process:

```powershell
$result = & .\KeyLoader.ps1 -Name "OpenAI" -Mode "write" -Type "API"
```

Do not launch a separate `powershell.exe` or `pwsh` process if the parent needs to keep the key.

### The title did not change

Some hosts do not allow title changes.

This does not mean the key failed to load.

Check:

```powershell
$result.Success
$result.EnvVarName
$result.Warnings
```

### The key has a whitespace warning

The loader stores the key exactly as pasted.

If the key has leading or trailing whitespace, the loader warns but does not trim it.

Re-run the loader and paste the key again if the whitespace was accidental.

### The generated name ended in `_KEY_KEY`

You probably passed a compound `Type` such as:

```powershell
-Type "API_KEY"
```

Use:

```powershell
-Type "API"
```

---

## 12. Package/release download option

This project will be published as an initial package-style GitHub release.

The release should include at least:

```text
KeyLoader.ps1
README.md
LICENSE
```

Optional release assets:

```text
KeyLoader.zip
SHA256SUMS.txt
```

Recommended user install path:

1. open the latest release page;
2. download `KeyLoader.ps1` or `KeyLoader.zip`;
3. unblock the file if required;
4. run it with `& .\KeyLoader.ps1`.

Latest release URL pattern:

```text
https://github.com/Mrflooglebinder/KeyLoader/releases/latest

Direct source repository:

```text
https://github.com/Mrflooglebinder/KeyLoader/releases/tag/v1.0.0
```

---

## 13. License

This project is licensed under the MIT License.

License file:

```text
https://github.com/Mrflooglebinder/KeyLoader/blob/main/LICENSE
```

The license lives at the root of the repository.

---

## 14. Handoff summary for other scripts or agents

Use `KeyLoader.ps1` as the only source of truth for generated key names.

Other scripts should:

1. call `KeyLoader.ps1` in the same PowerShell process;
2. capture the returned result object;
3. check `Success`;
4. keep `EnvVarName`;
5. pass `EnvVarName` to workers;
6. have workers read the key from that environment variable;
7. never pass the actual key value as a command-line argument;
8. never print or log the key value;
9. avoid provider-specific mapping unless a third-party SDK explicitly requires it.

Minimal parent call:

```powershell
$result = & .\KeyLoader.ps1 -Name "OpenAI" -Mode "write" -Type "API"

if (-not $result.Success) {
  throw $result.Message
}

$keyEnvVarName = $result.EnvVarName
```

Minimal key read:

```powershell
$key = [Environment]::GetEnvironmentVariable($keyEnvVarName, "Process")
```

For scripts you control, use the generated environment variable name returned by the loader.

No provider-specific environment variable mapping is required unless a third-party SDK or tool explicitly demands a specific variable name.
