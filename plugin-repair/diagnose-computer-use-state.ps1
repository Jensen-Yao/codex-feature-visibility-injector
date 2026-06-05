#requires -Version 5.1
[CmdletBinding()]
param(
  [string]$CodexHome = (Join-Path $env:USERPROFILE ".codex"),
  [string[]]$Plugins = @("browser", "computer-use", "chrome")
)

$ErrorActionPreference = "Stop"

function Write-Section {
  param([string]$Title)
  Write-Host ""
  Write-Host "==> $Title"
}

function Write-Status {
  param(
    [bool]$Ok,
    [string]$Message,
    [string]$Kind = "CHECK"
  )

  $prefix = if ($Ok) { "OK" } else { "FAIL" }
  if ($Kind -eq "WARN") { $prefix = "WARN" }
  Write-Host ("{0}: {1}" -f $prefix, $Message)
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
            (Test-Path -LiteralPath (Join-Path $resources "plugins\openai-bundled\.agents\plugins\marketplace.json"))) {
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

function Get-PluginConfigSection {
  param(
    [string]$ConfigText,
    [string]$PluginId
  )

  $escaped = [regex]::Escape(('[plugins."{0}"]' -f $PluginId))
  $match = [regex]::Match($ConfigText, "(?ms)^$escaped\s*(.*?)(?=^\[|\z)")
  if ($match.Success) { return $match.Value }
  return $null
}

function Test-PluginConfigEnabled {
  param(
    [string]$ConfigText,
    [string]$PluginId
  )

  $section = Get-PluginConfigSection -ConfigText $ConfigText -PluginId $PluginId
  return $section -ne $null -and $section -match '(?m)^\s*enabled\s*=\s*true\s*$'
}

function Get-PluginListLine {
  param(
    [string[]]$PluginList,
    [string]$PluginId
  )

  return $PluginList |
    Where-Object { $_ -match ("^\s*" + [regex]::Escape($PluginId) + "\s+") } |
    Select-Object -First 1
}

function Invoke-ExternalCapture {
  param(
    [string]$FilePath,
    [string[]]$Arguments,
    [string]$WorkingDirectory
  )

  $oldLocation = Get-Location
  try {
    if ($WorkingDirectory) { Set-Location -LiteralPath $WorkingDirectory }
    $output = & $FilePath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
  } finally {
    Set-Location $oldLocation
  }

  $text = ($output | ForEach-Object { $_.ToString() }) -join "`n"
  $json = $null
  try {
    $trimmed = $text.Trim()
    if ($trimmed.StartsWith("{") -or $trimmed.StartsWith("[")) {
      $json = $trimmed | ConvertFrom-Json
    }
  } catch {
    $json = $null
  }

  [pscustomobject]@{
    ExitCode = $exitCode
    Text = $text
    Json = $json
  }
}

function Get-RegistryDefaultValue {
  param([string]$KeyPath)

  $prefix = "HKCU\"
  if (-not $KeyPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
    return $null
  }

  $subKeyPath = $KeyPath.Substring($prefix.Length)
  $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($subKeyPath)
  if ($null -eq $key) { return $null }

  try {
    return $key.GetValue("")
  } finally {
    $key.Dispose()
  }
}

$coreFailed = $false
$chromeConnectionFailed = $false

$configPath = Join-Path $CodexHome "config.toml"
$configText = if (Test-Path -LiteralPath $configPath) { Get-Content -Raw -LiteralPath $configPath } else { "" }
$mirror = Join-Path $CodexHome "bundled-marketplaces\openai-bundled"
$resourcesMirrorRoot = Join-Path $CodexHome "bundled-resources"
$resourcesMirror = Join-Path $resourcesMirrorRoot "plugins\openai-bundled"

Write-Section "Codex runtime"
$resourcesRoot = Resolve-CodexResourcesRoot
$codexCli = Resolve-CodexCli -ResourcesRoot $resourcesRoot
$nodeExe = Join-Path $resourcesRoot "node.exe"
$nodeReplExe = Join-Path $resourcesRoot "node_repl.exe"
$codexVersion = (& $codexCli "--version" 2>$null) -join " "
Write-Host "Codex resources: $resourcesRoot"
Write-Host "Codex CLI: $codexCli"
Write-Host "Codex version: $codexVersion"
Write-Status -Ok (Test-Path -LiteralPath $nodeExe) -Message "Bundled node.exe exists"
Write-Status -Ok (Test-Path -LiteralPath $nodeReplExe) -Message "Bundled node_repl.exe exists"

Write-Section "Persistent bundled source"
$marketplaceList = & $codexCli plugin marketplace list
$marketplaceText = $marketplaceList -join "`n"
$marketplaceOk = $marketplaceText.Contains("bundled-marketplaces\openai-bundled") -and
  (Test-Path -LiteralPath (Join-Path $mirror ".agents\plugins\marketplace.json"))
$resourcesMirrorOk = Test-Path -LiteralPath (Join-Path $resourcesMirror ".agents\plugins\marketplace.json")
$envName = "CODEX_ELECTRON_BUNDLED_PLUGINS_RESOURCES_PATH"
$userResourcesEnv = [Environment]::GetEnvironmentVariable($envName, "User")
$envOk = $userResourcesEnv -eq $resourcesMirrorRoot

Write-Status -Ok $marketplaceOk -Message "openai-bundled marketplace points to stable mirror: $mirror"
Write-Status -Ok $resourcesMirrorOk -Message "resources-shaped mirror exists: $resourcesMirror"
Write-Status -Ok $envOk -Message "$envName user value is $resourcesMirrorRoot"
if (-not ($marketplaceOk -and $resourcesMirrorOk -and $envOk)) {
  $coreFailed = $true
}

Write-Section "Plugin install/config/cache layer"
$pluginList = & $codexCli plugin list

foreach ($plugin in $Plugins) {
  $pluginId = "$plugin@openai-bundled"
  $line = Get-PluginListLine -PluginList $pluginList -PluginId $pluginId
  $cliOk = $line -and $line -match "installed, enabled"
  $configOk = Test-PluginConfigEnabled -ConfigText $configText -PluginId $pluginId
  $cache = Get-LatestPluginCache -CodexHome $CodexHome -PluginName $plugin
  $cacheOk = $cache -and (Test-Path -LiteralPath (Join-Path $cache.FullName ".codex-plugin\plugin.json"))

  Write-Host ""
  Write-Host $pluginId
  Write-Status -Ok $cliOk -Message ("CLI status is installed/enabled" + $(if ($line) { ": $line" } else { "" }))
  Write-Status -Ok $configOk -Message "config.toml has enabled plugin section"
  Write-Status -Ok $cacheOk -Message ($(if ($cache) { "plugin cache exists: $($cache.FullName)" } else { "plugin cache is missing" }))

  if (-not ($cliOk -and $configOk -and $cacheOk)) {
    $coreFailed = $true
  }
}

Write-Section "Computer Use helper layer"
$computerUseCache = Get-LatestPluginCache -CodexHome $CodexHome -PluginName "computer-use"
if ($computerUseCache) {
  $helper = Join-Path $computerUseCache.FullName "node_modules\@oai\sky\bin\windows\codex-computer-use.exe"
  $helperOk = Test-Path -LiteralPath $helper
  $notifyOk = $helperOk -and $configText.Contains($helper.Replace("\", "\\"))
  Write-Status -Ok $helperOk -Message "Computer Use helper exists: $helper"
  Write-Status -Ok $notifyOk -Message "config.toml notify points at current Computer Use helper"
  if (-not ($helperOk -and $notifyOk)) { $coreFailed = $true }
} else {
  Write-Status -Ok $false -Message "computer-use cache is missing"
  $coreFailed = $true
}

Write-Section "Chrome extension/native host layer"
$chromeCache = Get-LatestPluginCache -CodexHome $CodexHome -PluginName "chrome"
if (-not $chromeCache) {
  Write-Status -Ok $false -Message "chrome plugin cache is missing; cannot check Chrome extension layer"
  $coreFailed = $true
} else {
  $chromePath = $chromeCache.FullName
  $extensionConfigPath = Join-Path $chromePath "scripts\extension-id.json"
  $extensionConfigOk = Test-Path -LiteralPath $extensionConfigPath
  Write-Status -Ok $extensionConfigOk -Message "extension-id.json exists: $extensionConfigPath"

  if ($extensionConfigOk) {
    $extensionConfig = Get-Content -Raw -LiteralPath $extensionConfigPath | ConvertFrom-Json
    $extensionId = $extensionConfig.extensionId
    $extensionHostName = $extensionConfig.extensionHostName
    $webstoreUrl = "https://chromewebstore.google.com/detail/codex/$extensionId"
    Write-Host "Chrome extension ID: $extensionId"
    Write-Host "Chrome extension page: $webstoreUrl"

    $nativeRegistryKey = "HKCU\Software\Google\Chrome\NativeMessagingHosts\$extensionHostName"
    $registryManifestPath = Get-RegistryDefaultValue -KeyPath $nativeRegistryKey
    Write-Status -Ok ($registryManifestPath -ne $null) -Message "Native Messaging Host registry key exists: $nativeRegistryKey"
    if ($registryManifestPath) {
      Write-Status -Ok (Test-Path -LiteralPath $registryManifestPath) -Message "Native Messaging Host manifest exists: $registryManifestPath"
    }

    if (Test-Path -LiteralPath $nodeExe) {
      $extensionCheckScript = Join-Path $chromePath "scripts\check-extension-installed.js"
      $nativeHostCheckScript = Join-Path $chromePath "scripts\check-native-host-manifest.js"

      if (Test-Path -LiteralPath $extensionCheckScript) {
        $extensionCheck = Invoke-ExternalCapture -FilePath $nodeExe -Arguments @($extensionCheckScript, "--json") -WorkingDirectory $chromePath
        if ($extensionCheck.Json) {
          $selectedProfile = $extensionCheck.Json.selectedProfileDirectory
          Write-Status -Ok ($extensionCheck.ExitCode -eq 0) -Message ("Chrome extension selected-profile status: installed={0}, enabled={1}, profile={2}" -f $extensionCheck.Json.installed, $extensionCheck.Json.enabled, $selectedProfile)
          if ($extensionCheck.ExitCode -ne 0) {
            $chromeConnectionFailed = $true
          }
        } else {
          Write-Status -Ok $false -Message "Could not parse Chrome extension check output: $($extensionCheck.Text)"
          $chromeConnectionFailed = $true
        }
      } else {
        Write-Status -Ok $false -Message "check-extension-installed.js is missing"
        $chromeConnectionFailed = $true
      }

      if (Test-Path -LiteralPath $nativeHostCheckScript) {
        $nativeCheck = Invoke-ExternalCapture -FilePath $nodeExe -Arguments @($nativeHostCheckScript, "--json") -WorkingDirectory $chromePath
        if ($nativeCheck.Json) {
          Write-Status -Ok ($nativeCheck.ExitCode -eq 0) -Message ("Native host manifest correct={0}; manifest={1}" -f $nativeCheck.Json.correct, $nativeCheck.Json.manifestPath)
          if ($nativeCheck.ExitCode -ne 0) {
            if ($nativeCheck.Json.problem) { Write-Host "Native host problem: $($nativeCheck.Json.problem)" }
            $chromeConnectionFailed = $true
          }
        } else {
          Write-Status -Ok $false -Message "Could not parse native host check output: $($nativeCheck.Text)"
          $chromeConnectionFailed = $true
        }
      } else {
        Write-Status -Ok $false -Message "check-native-host-manifest.js is missing"
        $chromeConnectionFailed = $true
      }
    } else {
      Write-Status -Ok $false -Message "Bundled node.exe is missing, cannot run Chrome extension checks"
      $chromeConnectionFailed = $true
    }
  } else {
    $chromeConnectionFailed = $true
  }
}

Write-Section "Result"
if ($coreFailed) {
  Write-Host "RESULT: CORE_PLUGIN_LAYER_BROKEN"
  Write-Host "Meaning: Settings can legitimately show Install until the plugin config/cache/marketplace layer is repaired."
  exit 1
}

if ($chromeConnectionFailed) {
  Write-Host "RESULT: PLUGINS_INSTALLED_BUT_CHROME_CONNECTION_INCOMPLETE"
  Write-Host "Meaning: Any App / Google Chrome plugin rows should be installed, but Chrome extension/native host still needs connection repair."
  exit 2
}

Write-Host "RESULT: INSTALLED_AND_CONNECTED_AT_LOCAL_CHECK_LAYER"
Write-Host "Meaning: plugin config/cache/helper and Chrome extension/native host checks passed. If Settings still shows Install, the current Codex window has a stale plugin list."
exit 0
