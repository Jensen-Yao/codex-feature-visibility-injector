$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceScript = Join-Path $repoRoot "user_scripts\codex-feature-visibility-injector.js"

if (-not (Test-Path -LiteralPath $sourceScript)) {
  throw "Source script not found: $sourceScript"
}

$codexPlusPlusRoot = Join-Path $env:APPDATA "Codex++"
$userScriptsDir = Join-Path $codexPlusPlusRoot "user_scripts"
$configPath = Join-Path $codexPlusPlusRoot "user_scripts.json"
$targetScript = Join-Path $userScriptsDir "codex-feature-visibility-injector.js"
$scriptKey = "user:codex-feature-visibility-injector.js"

New-Item -ItemType Directory -Force -Path $userScriptsDir | Out-Null
Copy-Item -LiteralPath $sourceScript -Destination $targetScript -Force

if (Test-Path -LiteralPath $configPath) {
  $raw = Get-Content -Raw -LiteralPath $configPath
  if ([string]::IsNullOrWhiteSpace($raw)) {
    $config = [pscustomobject]@{}
  } else {
    $config = $raw | ConvertFrom-Json
  }
} else {
  $config = [pscustomobject]@{}
}

if ($null -eq $config.enabled) {
  $config | Add-Member -NotePropertyName "enabled" -NotePropertyValue $true
} else {
  $config.enabled = $true
}

if ($null -eq $config.scripts) {
  $config | Add-Member -NotePropertyName "scripts" -NotePropertyValue ([pscustomobject]@{})
}

$config.scripts | Add-Member -NotePropertyName $scriptKey -NotePropertyValue $true -Force

$json = $config | ConvertTo-Json -Depth 20
Set-Content -LiteralPath $configPath -Value $json -Encoding UTF8

Write-Host "Installed Codex Feature Visibility Injector:"
Write-Host "  $targetScript"
Write-Host "Updated Codex++ user script config:"
Write-Host "  $configPath"
Write-Host "Restart Codex Desktop to load the script."
