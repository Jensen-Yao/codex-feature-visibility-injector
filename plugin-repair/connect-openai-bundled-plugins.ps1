#requires -Version 5.1
[CmdletBinding()]
param(
  [string]$CodexHome = (Join-Path $env:USERPROFILE ".codex"),
  [switch]$ForceCoreRepair,
  [switch]$SkipChromeWindow
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repairScript = Join-Path $scriptRoot "repair-openai-bundled-plugins.ps1"
$verifyScript = Join-Path $scriptRoot "verify-openai-bundled-plugins.ps1"
$diagnoseScript = Join-Path $scriptRoot "diagnose-computer-use-state.ps1"

if (-not (Test-Path -LiteralPath $repairScript)) {
  throw "Missing repair script: $repairScript"
}

if (-not (Test-Path -LiteralPath $verifyScript)) {
  throw "Missing verify script: $verifyScript"
}

if (-not (Test-Path -LiteralPath $diagnoseScript)) {
  throw "Missing diagnose script: $diagnoseScript"
}

function Write-Step {
  param([string]$Message)
  Write-Host ""
  Write-Host "==> $Message"
}

function Resolve-CodexResourcesRoot {
  $candidates = New-Object System.Collections.Generic.List[string]
  $roots = New-Object System.Collections.Generic.List[string]

  if ($env:ProgramFiles) {
    $roots.Add((Join-Path $env:ProgramFiles "WindowsApps"))
  }

  Get-PSDrive -PSProvider FileSystem | ForEach-Object {
    $roots.Add((Join-Path $_.Root "WindowsApps"))
  }

  foreach ($root in ($roots | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath $root)) { continue }

    Get-ChildItem -LiteralPath $root -Directory -Filter "OpenAI.Codex_*" -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending |
      ForEach-Object {
        $resources = Join-Path $_.FullName "app\resources"
        if ((Test-Path -LiteralPath (Join-Path $resources "codex.exe")) -and
            (Test-Path -LiteralPath (Join-Path $resources "node.exe")) -and
            (Test-Path -LiteralPath (Join-Path $resources "node_repl.exe"))) {
          $candidates.Add($resources)
        }
      }
  }

  foreach ($candidate in ($candidates | Select-Object -Unique)) {
    return [IO.Path]::GetFullPath($candidate)
  }

  throw "Could not locate the current Codex resources root."
}

function Resolve-CodexCli {
  param([string]$ResourcesRoot)

  $candidates = New-Object System.Collections.Generic.List[string]
  $bundled = Join-Path $ResourcesRoot "codex.exe"
  if (Test-Path -LiteralPath $bundled) { $candidates.Add($bundled) }

  $fromPath = Get-Command "codex" -ErrorAction SilentlyContinue
  if ($fromPath) { $candidates.Add($fromPath.Source) }

  foreach ($candidate in ($candidates | Select-Object -Unique)) {
    try {
      & $candidate "--version" *> $null
      if ($LASTEXITCODE -eq 0) { return $candidate }
    } catch {
      continue
    }
  }

  throw "Could not find a runnable codex CLI."
}

function Get-LatestPluginCache {
  param(
    [string]$CodexHome,
    [string]$PluginName
  )

  $root = Join-Path $CodexHome ("plugins\cache\openai-bundled\{0}" -f $PluginName)
  if (-not (Test-Path -LiteralPath $root)) { return $null }

  return Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    Select-Object -First 1
}

function Resolve-ChromePluginSourceRoot {
  param([string]$CodexHome)

  $candidates = @(
    (Join-Path $CodexHome "bundled-marketplaces\openai-bundled\plugins\chrome"),
    (Join-Path $CodexHome "bundled-resources\plugins\openai-bundled\plugins\chrome")
  )

  foreach ($candidate in $candidates) {
    if ((Test-Path -LiteralPath (Join-Path $candidate "scripts\installManifest.mjs")) -and
        (Test-Path -LiteralPath (Join-Path $candidate "extension-host\windows\x64\extension-host.exe"))) {
      return [IO.Path]::GetFullPath($candidate)
    }
  }

  $cache = Get-LatestPluginCache -CodexHome $CodexHome -PluginName "chrome"
  if ($cache -and
      (Test-Path -LiteralPath (Join-Path $cache.FullName "scripts\installManifest.mjs")) -and
      (Test-Path -LiteralPath (Join-Path $cache.FullName "extension-host\windows\x64\extension-host.exe"))) {
    return [IO.Path]::GetFullPath($cache.FullName)
  }

  throw "Could not locate a usable chrome plugin source root."
}

function Invoke-Diagnose {
  param([string]$CodexHome)

  $process = Start-Process -FilePath "powershell.exe" -ArgumentList @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $diagnoseScript,
    "-CodexHome",
    $CodexHome
  ) -NoNewWindow -Wait -PassThru
  return [int]$process.ExitCode
}

function Install-ChromeNativeHost {
  param(
    [string]$ChromePluginRoot,
    [string]$CodexCli,
    [string]$NodeExe,
    [string]$NodeReplExe
  )

  $installScript = Join-Path $ChromePluginRoot "scripts\installManifest.mjs"
  if (-not (Test-Path -LiteralPath $installScript)) {
    throw "Missing Chrome native host installer: $installScript"
  }

  $installerHelper = Join-Path $script:scriptRoot "install-chrome-native-host.mjs"
  if (-not (Test-Path -LiteralPath $installerHelper)) {
    throw "Missing helper script: $installerHelper"
  }

  Write-Host "Chrome plugin root: $ChromePluginRoot"
  Write-Host "Installing Native Messaging Host manifest and registry key..."
  & $NodeExe $installerHelper $installScript $CodexCli $NodeExe $NodeReplExe
  if ($LASTEXITCODE -ne 0) {
    throw "Chrome Native Messaging Host install failed with exit code $LASTEXITCODE."
  }
}

function Open-ChromeForSelectedProfile {
  param(
    [string]$ChromePluginRoot,
    [string]$NodeExe
  )

  $openScript = Join-Path $ChromePluginRoot "scripts\open-chrome-window.js"
  if (-not (Test-Path -LiteralPath $openScript)) {
    Write-Host "Chrome wake script is missing; skipped opening Chrome."
    return
  }

  Write-Host "Opening Chrome about:blank in the selected profile to wake the extension..."
  & $NodeExe $openScript
  if ($LASTEXITCODE -ne 0) {
    Write-Host "Opening Chrome failed with exit code $LASTEXITCODE. The plugin install layer is still repaired; open Chrome manually if needed."
  }
}

Write-Step "Diagnosing current state before repair"
$initialDiagnoseExit = Invoke-Diagnose -CodexHome $CodexHome

if ($ForceCoreRepair -or $initialDiagnoseExit -eq 1) {
  Write-Step "Core plugin layer is missing or forced; running full bundled-plugin repair"
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $repairScript -CodexHome $CodexHome -SetUserResourcesEnvironmentVariable
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }

  Write-Step "Rechecking after full repair"
  $postRepairDiagnoseExit = Invoke-Diagnose -CodexHome $CodexHome
  if ($postRepairDiagnoseExit -eq 1) {
    Write-Host "Core plugin layer is still broken after repair."
    exit 1
  }
} elseif ($initialDiagnoseExit -eq 0) {
  Write-Step "Core plugin layer and local Chrome checks already pass"
} elseif ($initialDiagnoseExit -eq 2) {
  Write-Step "Plugins are installed; repairing Chrome connection layer"
} else {
  Write-Host "Diagnose script failed with unexpected exit code $initialDiagnoseExit."
  exit $initialDiagnoseExit
}

$resourcesRoot = Resolve-CodexResourcesRoot
$codexCli = Resolve-CodexCli -ResourcesRoot $resourcesRoot
$nodeExe = Join-Path $resourcesRoot "node.exe"
$nodeReplExe = Join-Path $resourcesRoot "node_repl.exe"

try {
  Write-Step "Ensuring Chrome Native Messaging Host is registered"
  $chromePluginRoot = Resolve-ChromePluginSourceRoot -CodexHome $CodexHome
  Install-ChromeNativeHost -ChromePluginRoot $chromePluginRoot -CodexCli $codexCli -NodeExe $nodeExe -NodeReplExe $nodeReplExe

  if (-not $SkipChromeWindow) {
    Open-ChromeForSelectedProfile -ChromePluginRoot $chromePluginRoot -NodeExe $nodeExe
  }
} catch {
  Write-Host "Chrome connection repair failed: $($_.Exception.Message)"
}

Write-Step "Verifying CLI/config/cache layer"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifyScript -CodexHome $CodexHome
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

Write-Step "Final layered diagnosis"
$finalDiagnoseExit = Invoke-Diagnose -CodexHome $CodexHome

Write-Host ""
if ($finalDiagnoseExit -eq 0) {
  Write-Host "Connected at local check layer. If Settings still shows Install, reload the Codex window so the frontend re-reads the plugin list."
  exit 0
}

if ($finalDiagnoseExit -eq 2) {
  Write-Host "Plugins are installed, but Chrome extension connection is still incomplete. Check the Chrome extension row in the diagnosis above."
  exit 2
}

Write-Host "Connection script finished, but the core plugin layer is still not healthy."
exit $finalDiagnoseExit
