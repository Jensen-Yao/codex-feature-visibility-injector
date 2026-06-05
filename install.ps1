#requires -Version 5.1
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$codexPlusPlusRoot = Join-Path $env:APPDATA "Codex++"
$userScriptsDir = Join-Path $codexPlusPlusRoot "user_scripts"
$pluginRepairDir = Join-Path $codexPlusPlusRoot "plugin-repair"
$configPath = Join-Path $codexPlusPlusRoot "user_scripts.json"

$featureSource = Join-Path $repoRoot "user_scripts\codex-feature-visibility-injector.js"
$connectorTemplate = Join-Path $repoRoot "user_scripts\codex-plugin-connector.template.js"
$pluginRepairSource = Join-Path $repoRoot "plugin-repair"

if (-not (Test-Path -LiteralPath $featureSource)) {
  throw "Missing source: $featureSource"
}
if (-not (Test-Path -LiteralPath $connectorTemplate)) {
  throw "Missing source: $connectorTemplate"
}
if (-not (Test-Path -LiteralPath $pluginRepairSource)) {
  throw "Missing source: $pluginRepairSource"
}

function Convert-ToJsStringLiteral {
  param([string]$Value)
  return $Value.Replace("\", "\\").Replace('"', '\"')
}

function Ensure-ObjectProperty {
  param(
    [object]$Object,
    [string]$Name,
    [object]$Value
  )

  if ($null -eq $Object.PSObject.Properties[$Name]) {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
  }
}

New-Item -ItemType Directory -Force -Path $userScriptsDir | Out-Null
New-Item -ItemType Directory -Force -Path $pluginRepairDir | Out-Null

Copy-Item -LiteralPath $featureSource -Destination (Join-Path $userScriptsDir "codex-feature-visibility-injector.js") -Force
Copy-Item -LiteralPath (Join-Path $pluginRepairSource "*") -Destination $pluginRepairDir -Recurse -Force

$connectorText = Get-Content -Raw -LiteralPath $connectorTemplate
$connectorText = $connectorText.Replace("__CODEXPP_ROOT__", (Convert-ToJsStringLiteral $codexPlusPlusRoot))
Set-Content -LiteralPath (Join-Path $userScriptsDir "codex-plugin-connector.js") -Value $connectorText -Encoding UTF8

if (Test-Path -LiteralPath $configPath) {
  $raw = Get-Content -Raw -LiteralPath $configPath
  $config = if ([string]::IsNullOrWhiteSpace($raw)) { [pscustomobject]@{} } else { $raw | ConvertFrom-Json }
} else {
  $config = [pscustomobject]@{}
}

Ensure-ObjectProperty -Object $config -Name "enabled" -Value $true
$config.enabled = $true
Ensure-ObjectProperty -Object $config -Name "scripts" -Value ([pscustomobject]@{})
Ensure-ObjectProperty -Object $config -Name "market" -Value ([pscustomobject]@{})

$config.scripts | Add-Member -NotePropertyName "user:codex-feature-visibility-injector.js" -NotePropertyValue $true -Force
$config.scripts | Add-Member -NotePropertyName "user:codex-plugin-connector.js" -NotePropertyValue $true -Force

$config.market | Add-Member -NotePropertyName "user:codex-feature-visibility-injector.js" -NotePropertyValue ([pscustomobject]@{
  id = "codex-feature-visibility-injector"
  name = "Codex Feature Visibility Injector"
  version = "1"
  script_url = "local"
  homepage = "https://github.com/Jensen-Yao/CodexUnhide"
  installed_at = [string][DateTimeOffset]::Now.ToUnixTimeSeconds()
}) -Force

$config.market | Add-Member -NotePropertyName "user:codex-plugin-connector.js" -NotePropertyValue ([pscustomobject]@{
  id = "codex-plugin-connector"
  name = "Codex Plugin Connector"
  version = "2"
  script_url = "local"
  homepage = "https://github.com/Jensen-Yao/CodexUnhide"
  installed_at = [string][DateTimeOffset]::Now.ToUnixTimeSeconds()
}) -Force

$config | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $configPath -Encoding UTF8

Write-Host "Installed:"
Write-Host "  $userScriptsDir"
Write-Host "  $pluginRepairDir"
Write-Host "Updated:"
Write-Host "  $configPath"
Write-Host "Restart Codex / Codex++."
