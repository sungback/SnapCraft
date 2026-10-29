/// Installer helpers use process arguments rather than interpolating paths into code.
class UpdateScripts {
  static const macOS = r'''#!/bin/sh
set -u
target=$1
staged=$2
backup=$3
app_pid=$4
exec >> "$5" 2>&1
attempt=0
while kill -0 "$app_pid" 2>/dev/null; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 120 ]; then
    echo 'Timed out waiting for app to exit; original app retained.'
    exit 1
  fi
  sleep 0.5
done
# An earlier successful update may have left a recovery copy.
if [ -e "$backup" ]; then
  rm -rf "$backup" || exit 1
fi
mv "$target" "$backup" || exit 1
if mv "$staged" "$target" && open "$target"; then
  echo 'Update installed; previous app retained in backup.'
else
  echo 'Install or launch failed; restoring previous app.'
  if [ -e "$target" ]; then
    mv "$target" "$staged" || exit 1
  fi
  mv "$backup" "$target" || exit 1
  open "$target"
  exit 1
fi
''';

  static const windows = r'''
param(
  [string]$Target, [string]$Source, [string]$Executable,
  [int]$AppProcessId, [string]$LogPath
)
$ErrorActionPreference = 'Stop'
$stage = "$Target.snapcraft-new"
$backup = "$Target.snapcraft-previous"
$backedUp = $false
$canRestart = $false
Start-Transcript -Path $LogPath -Append
try {
  if (Get-Process -Id $AppProcessId -ErrorAction SilentlyContinue) {
    Wait-Process -Id $AppProcessId -Timeout 60 -ErrorAction Stop
  }
  $canRestart = $true
  if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
  New-Item -ItemType Directory -Path $stage | Out-Null
  & xcopy "$Source\*" $stage /E /Y /I /Q
  if ($LASTEXITCODE -ne 0) { throw "Package copy failed: $LASTEXITCODE" }
  foreach ($entry in @($Executable, 'flutter_windows.dll', 'data\flutter_assets')) {
    if (!(Test-Path -LiteralPath (Join-Path $stage $entry))) {
      throw "Incomplete update package: $entry"
    }
  }
  if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
  Move-Item -LiteralPath $Target -Destination $backup
  $backedUp = $true
  Move-Item -LiteralPath $stage -Destination $Target
  Start-Process -FilePath (Join-Path $Target $Executable) -WorkingDirectory $Target
} catch {
  Write-Output $_
  if ($backedUp) {
    if (Test-Path -LiteralPath $Target) { Move-Item -LiteralPath $Target -Destination $stage }
    Move-Item -LiteralPath $backup -Destination $Target
  }
  if ($canRestart -and (Test-Path -LiteralPath (Join-Path $Target $Executable))) {
    Start-Process -FilePath (Join-Path $Target $Executable) -WorkingDirectory $Target
  }
  exit 1
} finally {
  Stop-Transcript
}
''';
}
