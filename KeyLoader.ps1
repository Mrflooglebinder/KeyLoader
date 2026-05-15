# KeyLoader.ps1
# Securely load a key into this PowerShell session only.
# Stores the key in a generated environment variable:
# <NAME>_<MODE>_<TYPE>_KEY
# or, if Type is omitted:
# <NAME>_<MODE>_KEY
#
# Scope note: the key is not written to disk or the user/machine environment.
# It lives in the current PowerShell process environment block only.
# Child processes started from this session may inherit it.
# Closing the parent PowerShell session removes it.

<#
.SYNOPSIS
    Securely loads a secret key into the current PowerShell session.

.DESCRIPTION
    Prompts for a provider, mode, and key value, then stores the key as a
    process-level environment variable using a generated name:

        <NAME>_<MODE>_<TYPE>_KEY
        <NAME>_<MODE>_KEY          (Type omitted)

    The key is never written to disk and disappears when the window is closed.
    All menus support single-keypress input with a typed fallback for
    non-interactive hosts.

.PARAMETER Name
    Provider name. Skips the provider menu when supplied.

.PARAMETER Mode
    Key mode: read or write. Skips the mode menu when supplied.

.PARAMETER Type
    Optional category word, e.g. API, TOKEN, SECRET.
    Omit to exclude from the variable name.
    Do not pass a compound suffix like API_KEY — this produces a _KEY_KEY suffix.

.PARAMETER MinimumKeyLength
    Warn if the pasted key is shorter than this length. Set to 0 to disable.
    Default: 8. Maximum: 512.

.PARAMETER NeutralTitle
    Use KEYS LOADED as the window title instead of the provider-specific title.
    Useful on shared or recorded screens.

.PARAMETER NoWindowTitle
    Do not change the PowerShell window title at all.

.PARAMETER Help
    Display this help and exit.

.EXAMPLE
    & .\KeyLoader.ps1

    Runs interactively. Prompts for provider, mode, and key.

.EXAMPLE
    & .\KeyLoader.ps1 -Name "OpenAI" -Mode "write" -Type "API"

    Loads a key non-interactively as OPENAI_WRITE_API_KEY.

.EXAMPLE
    $result = & .\KeyLoader.ps1 -Name "Anthropic" -Mode "write"
    if (-not $result.Success) { throw $result.Message }
    $keyEnvVarName = $result.EnvVarName

    Captures the result object for use in a parent script.

.EXAMPLE
    & .\KeyLoader.ps1 -Help

    Displays this help.

.NOTES
    First-time setup (run once per machine):
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
        Unblock-File -Path .\KeyLoader.ps1

    Security note:
        The key must briefly exist as a plain .NET string to be written to the
        environment. The unmanaged BSTR buffer is zeroed immediately after use,
        but the managed string cannot be forcibly zeroed — this is a required
        limitation of process environment variables.

    The key is scoped to the current process only. Child processes started after
    loading may inherit it. Closing the PowerShell window removes it entirely.

.LINK
    https://github.com/Mrflooglebinder/Hash-Validator
#>
param(
  [string]$Name,
  [string]$Mode,
  [string]$Type,
  [int]$MinimumKeyLength = 8,
  [switch]$NeutralTitle,
  [switch]$NoWindowTitle,
  [switch]$Help
)

& {
  $ErrorActionPreference = "Stop"

  if ($Help) {
    Get-Help $PSCommandPath -Full
    return
  }

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

  function Clear-KeyLoaderScreen {
    try {
      Clear-Host
    }
    catch {
    }
  }

  function Convert-ToKeyPart {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
      return $null
    }

    $clean = $Value.Trim().ToUpperInvariant()
    $clean = $clean -replace '[^A-Z0-9]+', '_'
    $clean = $clean -replace '_+', '_'
    $clean = $clean.Trim('_')

    return $clean
  }

  function New-LoaderResult {
    param(
      [bool]$Success,
      [string]$Message,
      [string]$Name,
      [string]$Mode,
      [string]$Type,
      [string]$EnvVarName,
      [string]$WindowTitle,
      [string[]]$Warnings = @()
    )

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
  }

  function Read-KeyLoaderName {
    param([string[]]$Providers)

    $namedProviders = @($Providers | Where-Object { $_ -ne "Other" } | Select-Object -First 9)
    $hasOther       = @($Providers) -contains "Other"

    Write-Host "Choose a provider:"
    Write-Host ""

    for ($i = 0; $i -lt $namedProviders.Count; $i++) {
      Write-Host "  $($i + 1). $($namedProviders[$i])"
    }

    if ($hasOther) {
      Write-Host "  0. Other (User Defined)"
    }

    Write-Host ""
    Write-Host "  Q or Escape to abort. H for help."
    Write-Host ""

    try {
      while ($true) {
        $key    = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $keyStr = $key.Character.ToString().ToUpperInvariant()
        $vk     = $key.VirtualKeyCode

        if ($vk -eq 27 -or $keyStr -eq "Q") {
          return $null
        }

        if ($keyStr -eq "H") {
          Get-Help $PSCommandPath | Out-Host
          Write-Host ""
          continue
        }

        if ($keyStr -match '^[1-9]$') {
          $index = [int]::Parse($keyStr) - 1

          if ($index -lt $namedProviders.Count) {
            return $namedProviders[$index]
          }
        }

        if ($keyStr -eq "0" -and $hasOther) {
          Write-Host ""

          try {
            $custom = Read-Host "Enter provider name"

            if ([string]::IsNullOrWhiteSpace($custom)) {
              Clear-KeyLoaderScreen
              Write-Host "Choose a provider:"
              Write-Host ""
              for ($i = 0; $i -lt $namedProviders.Count; $i++) {
                Write-Host "  $($i + 1). $($namedProviders[$i])"
              }
              if ($hasOther) { Write-Host "  0. Other (User Defined)" }
              Write-Host ""
              Write-Host "  Q or Escape to abort. H for help."
              Write-Host ""
              Write-Host "  No name entered. Please try again." -ForegroundColor Yellow
              continue
            }

            return $custom.Trim()
          }
          catch {
            return $null
          }
        }

        Clear-KeyLoaderScreen
        Write-Host "Choose a provider:"
        Write-Host ""
        for ($i = 0; $i -lt $namedProviders.Count; $i++) {
          Write-Host "  $($i + 1). $($namedProviders[$i])"
        }
        if ($hasOther) { Write-Host "  0. Other (User Defined)" }
        Write-Host ""
        Write-Host "  Q or Escape to abort. H for help."
        Write-Host ""
        Write-Host "  Invalid key. Press 1-$($namedProviders.Count)$(if ($hasOther) { ', 0 for Other' }), Q to abort, H for help." -ForegroundColor Yellow
      }
    }
    catch {
      try {
        while ($true) {
          $raw = Read-Host "Enter number$(if ($hasOther) { ', 0 for Other' }), or Q to abort"

          if ([string]::IsNullOrWhiteSpace($raw)) {
            Write-Host "  Invalid input. Try again." -ForegroundColor Yellow
            continue
          }

          $rawStr = $raw.Trim().ToUpperInvariant()

          if ($rawStr -eq "Q") {
            return $null
          }

          if ($rawStr -eq "H") {
            Get-Help $PSCommandPath | Out-Host
            Write-Host ""
            continue
          }

          if ($rawStr -eq "0" -and $hasOther) {
            try {
              $custom = Read-Host "Enter provider name"

              if ([string]::IsNullOrWhiteSpace($custom)) {
                Write-Host "  No name entered. Please try again." -ForegroundColor Yellow
                continue
              }

              return $custom.Trim()
            }
            catch {
              return $null
            }
          }

          $parsed = 0

          if (-not [int]::TryParse($rawStr, [ref]$parsed)) {
            Write-Host "  Invalid input. Try again." -ForegroundColor Yellow
            continue
          }

          $index = $parsed - 1

          if ($index -ge 0 -and $index -lt $namedProviders.Count) {
            Clear-KeyLoaderScreen
            return $namedProviders[$index]
          }

          Write-Host "  Invalid input. Try again." -ForegroundColor Yellow
        }
      }
      catch {
        Write-Host ""
        Write-Host "Interactive name selection is not available in this host. Pass -Name." -ForegroundColor Red
        Write-Host ""
        return $null
      }
    }
  }

  function Read-KeyLoaderMode {
    Write-Host "Choose key mode:"
    Write-Host ""
    Write-Host "  1. Read"
    Write-Host "  2. Write"
    Write-Host ""
    Write-Host "  Q or Escape to abort. H for help."
    Write-Host ""

    try {
      while ($true) {
        $key    = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $keyStr = $key.Character.ToString().ToUpperInvariant()
        $vk     = $key.VirtualKeyCode

        if ($vk -eq 27 -or $keyStr -eq "Q") {
          return $null
        }

        if ($keyStr -eq "H") {
          Get-Help $PSCommandPath | Out-Host
          Write-Host ""
          continue
        }

        switch ($keyStr) {
          "1" { return "read" }
          "2" { return "write" }
          default {
            Clear-KeyLoaderScreen
            Write-Host "Choose key mode:"
            Write-Host ""
            Write-Host "  1. Read"
            Write-Host "  2. Write"
            Write-Host ""
            Write-Host "  Q or Escape to abort. H for help."
            Write-Host ""
            Write-Host "  Invalid key. Press 1 or 2, Q to abort, H for help." -ForegroundColor Yellow
          }
        }
      }
    }
    catch {
      try {
        while ($true) {
          $typedMode = Read-Host "Enter key mode (1, 2, read, write), or Q to abort"

          if ([string]::IsNullOrWhiteSpace($typedMode)) {
            Write-Host "  Invalid input. Try again." -ForegroundColor Yellow
            continue
          }

          $typedMode = $typedMode.Trim().ToLowerInvariant()

          if ($typedMode -eq "q") {
            return $null
          }

          if ($typedMode -eq "h") {
            Get-Help $PSCommandPath | Out-Host
            Write-Host ""
            continue
          }

          switch ($typedMode) {
            "1"     { Clear-KeyLoaderScreen; return "read" }
            "read"  { Clear-KeyLoaderScreen; return "read" }
            "2"     { Clear-KeyLoaderScreen; return "write" }
            "write" { Clear-KeyLoaderScreen; return "write" }
            default {
              Write-Host "  Invalid input. Try again." -ForegroundColor Yellow
            }
          }
        }
      }
      catch {
        Write-Host ""
        Write-Host "Interactive mode selection is not available in this host. Pass -Mode read or -Mode write." -ForegroundColor Red
        Write-Host ""
        return $null
      }
    }
  }

  function Set-KeyLoaderWindowTitle {
    param(
      [string]$Name,
      [string]$Mode,
      [string]$Type,
      [string]$EnvVarName,
      [switch]$NeutralTitle,
      [switch]$NoWindowTitle
    )

    if ($NoWindowTitle) {
      return [pscustomobject]@{
        Applied = $false
        Title   = $null
        Warning = $null
      }
    }

    try {
      if (-not (Get-Variable -Name KeyLoaderLoadedKeys -Scope Global -ErrorAction SilentlyContinue)) {
        Set-Variable -Name KeyLoaderLoadedKeys -Scope Global -Value @()
      }

      $existingLoadedKeys = @(Get-Variable -Name KeyLoaderLoadedKeys -Scope Global -ValueOnly)

      $existingLoadedKeys = @(
        $existingLoadedKeys |
          Where-Object {
            $isDifferentKey = $_.EnvVarName -ne $EnvVarName
            $isStillLoaded  = [bool][Environment]::GetEnvironmentVariable($_.EnvVarName, "Process")

            $isDifferentKey -and $isStillLoaded
          }
      )

      $existingLoadedKeys += [pscustomobject]@{
        Name       = $Name
        Mode       = $Mode
        Type       = $Type
        EnvVarName = $EnvVarName
      }

      Set-Variable -Name KeyLoaderLoadedKeys -Scope Global -Value $existingLoadedKeys

      if ($NeutralTitle) {
        $title = "KEYS LOADED"
      } else {
        $loaded = @($existingLoadedKeys)
        $names  = @($loaded.Name | Sort-Object -Unique)
        $modes  = @($loaded.Mode | Sort-Object -Unique)

        if ($names.Count -eq 1) {
          if (($modes -contains "READ") -and ($modes -contains "WRITE")) {
            $title = "$($names[0]) READ+WRITE KEYS"
          } else {
            $title = "$($names[0]) $($modes[0]) KEY"
          }
        } else {
          if (($modes -contains "READ") -and ($modes -contains "WRITE")) {
            $title = "MULTI READ+WRITE KEYS"
          } else {
            $title = "MULTI KEYS"
          }
        }
      }

      try {
        $Host.UI.RawUI.WindowTitle = $title

        return [pscustomobject]@{
          Applied = $true
          Title   = $title
          Warning = $null
        }
      }
      catch {
        return [pscustomobject]@{
          Applied = $false
          Title   = $title
          Warning = "This host does not support changing the window title."
        }
      }
    }
    catch {
      return [pscustomobject]@{
        Applied = $false
        Title   = $null
        Warning = "Window title state could not be updated by this host/session."
      }
    }
  }

  $warnings = @()

  $maximumMinimumKeyLength = 512

  if ($MinimumKeyLength -lt 0) {
    $warnings += "MinimumKeyLength was below 0 and was treated as 0."
    $MinimumKeyLength = 0
  } elseif ($MinimumKeyLength -gt $maximumMinimumKeyLength) {
    $warnings += "MinimumKeyLength was above $maximumMinimumKeyLength and was capped at $maximumMinimumKeyLength."
    $MinimumKeyLength = $maximumMinimumKeyLength
  }

  Clear-KeyLoaderScreen

  Write-Host ""
  Write-Host "========================================"
  Write-Host " Key Loader"
  Write-Host "========================================"
  Write-Host ""

  if ([string]::IsNullOrWhiteSpace($Name)) {
    try {
      $Name = Read-KeyLoaderName -Providers $KeyLoaderProviders
    }
    catch {
      Write-Host ""
      Write-Host "Aborted. Interactive name selection is not available. Pass -Name." -ForegroundColor Red
      Write-Host ""

      return New-LoaderResult `
        -Success $false `
        -Message "Interactive name selection is not available. Pass -Name." `
        -Name $null `
        -Mode $null `
        -Type $null `
        -EnvVarName $null `
        -WindowTitle $null `
        -Warnings $warnings
    }

    if ([string]::IsNullOrWhiteSpace($Name)) {
      Write-Host ""
      Write-Host "Aborted. No valid provider was selected." -ForegroundColor Red
      Write-Host ""

      return New-LoaderResult `
        -Success $false `
        -Message "No valid provider was selected." `
        -Name $null `
        -Mode $null `
        -Type $null `
        -EnvVarName $null `
        -WindowTitle $null `
        -Warnings $warnings
    }
  }

  $safeName = Convert-ToKeyPart $Name

  if (-not $safeName) {
    Write-Host ""
    Write-Host "Aborted. No valid key name was provided." -ForegroundColor Red
    Write-Host ""

    return New-LoaderResult `
      -Success $false `
      -Message "No valid key name was provided." `
      -Name $null `
      -Mode $null `
      -Type $null `
      -EnvVarName $null `
      -WindowTitle $null `
      -Warnings $warnings
  }

  Clear-KeyLoaderScreen

  Write-Host ""
  Write-Host "========================================"
  Write-Host " Key Loader"
  Write-Host "========================================"
  Write-Host ""
  Write-Host "Provider          : $safeName"
  Write-Host ""

  if ([string]::IsNullOrWhiteSpace($Mode)) {
    $Mode = Read-KeyLoaderMode

    if ([string]::IsNullOrWhiteSpace($Mode)) {
      Write-Host ""
      Write-Host "Aborted. No valid mode was selected." -ForegroundColor Red
      Write-Host ""

      return New-LoaderResult `
        -Success $false `
        -Message "No valid mode was selected." `
        -Name $safeName `
        -Mode $null `
        -Type $null `
        -EnvVarName $null `
        -WindowTitle $null `
        -Warnings $warnings
    }
  }

  $Mode = $Mode.Trim().ToLowerInvariant()

  switch ($Mode) {
    "read"  { $safeMode = "READ" }
    "write" { $safeMode = "WRITE" }
    default {
      Write-Host ""
      Write-Host "Aborted. Mode must be 'read' or 'write'." -ForegroundColor Red
      Write-Host ""

      return New-LoaderResult `
        -Success $false `
        -Message "Mode must be 'read' or 'write'." `
        -Name $safeName `
        -Mode $null `
        -Type $null `
        -EnvVarName $null `
        -WindowTitle $null `
        -Warnings $warnings
    }
  }

  $safeType = Convert-ToKeyPart $Type

  $envNameParts = @($safeName, $safeMode)

  if ($safeType) {
    $envNameParts += $safeType
  }

  $envNameParts += "KEY"

  $envVarName = $envNameParts -join "_"

  Clear-KeyLoaderScreen

  Write-Host ""
  Write-Host "========================================"
  Write-Host " Key Loader"
  Write-Host "========================================"
  Write-Host ""
  Write-Host "Name              : $safeName"
  Write-Host "Mode              : $safeMode"

  if ($safeType) {
    Write-Host "Type              : $safeType"
  } else {
    Write-Host "Type              : Not set"
  }

  Write-Host "Environment name  : $envVarName"
  Write-Host "Scope             : Current PowerShell session only"
  Write-Host ""

  try {
    $secureKey = Read-Host "Paste key for $envVarName" -AsSecureString
  }
  catch {
    Write-Host ""
    Write-Host "Aborted. Secure key input is not available in this host." -ForegroundColor Red
    Write-Host ""

    return New-LoaderResult `
      -Success $false `
      -Message "Secure key input is not available in this host." `
      -Name $safeName `
      -Mode $safeMode `
      -Type $safeType `
      -EnvVarName $envVarName `
      -WindowTitle $null `
      -Warnings $warnings
  }

  if (-not $secureKey -or $secureKey.Length -eq 0) {
    Write-Host ""
    Write-Host "Aborted. No key was entered." -ForegroundColor Red
    Write-Host ""

    if ($secureKey) {
      try { $secureKey.Dispose() } catch { }
    }
    Remove-Variable -Name secureKey -Scope Local -Force -ErrorAction SilentlyContinue

    return New-LoaderResult `
      -Success $false `
      -Message "No key was entered." `
      -Name $safeName `
      -Mode $safeMode `
      -Type $safeType `
      -EnvVarName $envVarName `
      -WindowTitle $null `
      -Warnings $warnings
  }

  $bstr                   = [IntPtr]::Zero
  $titleResult            = $null
  $conversionSucceeded    = $false
  $conversionErrorMessage = $null
  $setItemSucceeded       = $false
  $setItemErrorMessage    = $null

  $keyContentWarnings = @()

  try {
    try {
      $bstr     = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
      $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)

      if ($null -eq $plainKey) {
        $conversionErrorMessage = "Conversion returned a null string."
      } else {
        $conversionSucceeded = $true
      }
    }
    catch {
      $conversionErrorMessage = $_.Exception.Message
    }

    if ($conversionSucceeded) {
      if ($plainKey.Length -gt 0) {
        $startsWithWhitespace = [char]::IsWhiteSpace($plainKey[0])
        $endsWithWhitespace   = [char]::IsWhiteSpace($plainKey[$plainKey.Length - 1])

        if ($startsWithWhitespace -or $endsWithWhitespace) {
          $keyContentWarnings += "Key has leading or trailing whitespace. It was stored exactly as pasted."
        }
      }

      if (($MinimumKeyLength -gt 0) -and ($plainKey.Length -lt $MinimumKeyLength)) {
        $keyContentWarnings += "Key is shorter than the configured minimum length warning threshold. It was stored anyway."
      }

      try {
        Set-Item -Path "Env:$envVarName" -Value $plainKey
        $setItemSucceeded = $true
      }
      catch {
        $setItemErrorMessage = $_.Exception.Message
      }

      if ($setItemSucceeded) {
        $warnings += $keyContentWarnings

        $titleResult = Set-KeyLoaderWindowTitle `
          -Name $safeName `
          -Mode $safeMode `
          -Type $safeType `
          -EnvVarName $envVarName `
          -NeutralTitle:$NeutralTitle `
          -NoWindowTitle:$NoWindowTitle

        if ($titleResult.Warning) {
          $warnings += $titleResult.Warning
        }
      }
    }
  }
  finally {
    if ($bstr -ne [IntPtr]::Zero) {
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }

    if (Get-Variable -Name plainKey -Scope Local -ErrorAction SilentlyContinue) {
      Remove-Variable -Name plainKey -Scope Local -Force -ErrorAction SilentlyContinue
    }

    if (Get-Variable -Name secureKey -Scope Local -ErrorAction SilentlyContinue) {
      try { $secureKey.Dispose() } catch { }
      Remove-Variable -Name secureKey -Scope Local -Force -ErrorAction SilentlyContinue
    }
  }

  Clear-KeyLoaderScreen

  if (-not $conversionSucceeded) {
    Write-Host ""
    Write-Host "$envVarName was NOT loaded." -ForegroundColor Red
    Write-Host ""
    Write-Host "Error             : Secure key could not be converted for environment storage." -ForegroundColor Red
    Write-Host ""

    $warnings += "Secure key conversion failed. No key was stored."

    return New-LoaderResult `
      -Success $false `
      -Message "Secure key could not be converted for environment storage." `
      -Name $safeName `
      -Mode $safeMode `
      -Type $safeType `
      -EnvVarName $envVarName `
      -WindowTitle $null `
      -Warnings $warnings
  }

  if (-not $setItemSucceeded) {
    Write-Host ""
    Write-Host "$envVarName was NOT loaded." -ForegroundColor Red
    Write-Host ""
    Write-Host "Error             : Could not write the environment variable." -ForegroundColor Red
    Write-Host ""

    $warnings += "Environment variable could not be written. No key was stored."

    return New-LoaderResult `
      -Success $false `
      -Message "Environment variable could not be written." `
      -Name $safeName `
      -Mode $safeMode `
      -Type $safeType `
      -EnvVarName $envVarName `
      -WindowTitle $null `
      -Warnings $warnings
  }

  if ([Environment]::GetEnvironmentVariable($envVarName, "Process")) {
    Write-Host ""
    Write-Host "========================================"
    Write-Host " Key Loaded"
    Write-Host "========================================"
    Write-Host ""
    Write-Host "Environment name  : $envVarName" -ForegroundColor Green

    if ($titleResult -and $titleResult.Applied) {
      Write-Host "Window title      : $($titleResult.Title)"
    } elseif ($NoWindowTitle) {
      Write-Host "Window title      : Not changed"
    } else {
      Write-Host "Window title      : Not changed by this host"
    }

    Write-Host "Scope             : Current PowerShell session only"
    Write-Host ""

    foreach ($warning in $warnings) {
      Write-Host "Warning           : $warning" -ForegroundColor Yellow
    }

    if ($warnings.Count -gt 0) {
      Write-Host ""
    }

    Write-Host "The key will be gone when this PowerShell window is closed." -ForegroundColor Yellow
    Write-Host ""

    return New-LoaderResult `
      -Success $true `
      -Message "Key loaded." `
      -Name $safeName `
      -Mode $safeMode `
      -Type $safeType `
      -EnvVarName $envVarName `
      -WindowTitle $(if ($titleResult) { $titleResult.Title } else { $null }) `
      -Warnings $warnings
  }

  Write-Host ""
  Write-Host "$envVarName is NOT loaded." -ForegroundColor Red
  Write-Host ""

  return New-LoaderResult `
    -Success $false `
    -Message "Environment variable was not loaded." `
    -Name $safeName `
    -Mode $safeMode `
    -Type $safeType `
    -EnvVarName $envVarName `
    -WindowTitle $(if ($titleResult) { $titleResult.Title } else { $null }) `
    -Warnings $warnings
}
