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
  [int]$AppProcessId, [string]$LogPath, [string]$ReadyPath
)
$ErrorActionPreference = 'Stop'
$backup = "$Target.snapcraft-previous"
$backedUp = $false
$canRestart = $false
function Copy-Bundle([string]$From, [string]$To) {
  # Robocopy retries files temporarily held by Windows or antivirus software.
  & robocopy $From $To /E /COPY:DAT /IS /IT /R:10 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "Bundle copy failed: $LASTEXITCODE" }
}
try {
  Add-Content -LiteralPath $LogPath -Value "$(Get-Date -Format o) Starting update"
  if ($ReadyPath) { [IO.File]::WriteAllText($ReadyPath, 'ready') }
  $process = Get-Process -Id $AppProcessId -ErrorAction SilentlyContinue
  if ($process) {
    try { Wait-Process -InputObject $process -Timeout 60 -ErrorAction Stop }
    catch {
      if (Get-Process -Id $AppProcessId -ErrorAction SilentlyContinue) { throw }
    }
  }
  $canRestart = $true
  foreach ($entry in @($Executable, 'flutter_windows.dll', 'data\flutter_assets')) {
    if (!(Test-Path -LiteralPath (Join-Path $Source $entry))) {
      throw "Incomplete update package: $entry"
    }
  }
  if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
  Copy-Bundle $Target $backup
  $backedUp = $true
  Copy-Bundle $Source $Target
  Start-Process -FilePath (Join-Path $Target $Executable) -WorkingDirectory $Target
  Add-Content -LiteralPath $LogPath -Value "$(Get-Date -Format o) Update launched" -ErrorAction SilentlyContinue
} catch {
  Add-Content -LiteralPath $LogPath -Value "$(Get-Date -Format o) Update failed: $_" -ErrorAction SilentlyContinue
  if ($backedUp) {
    try { Copy-Bundle $backup $Target }
    catch { Add-Content -LiteralPath $LogPath -Value "Restore failed; backup retained at $backup : $_" -ErrorAction SilentlyContinue; exit 1 }
  }
  if ($canRestart -and (Test-Path -LiteralPath (Join-Path $Target $Executable))) {
    Start-Process -FilePath (Join-Path $Target $Executable) -WorkingDirectory $Target
  }
  exit 1
}
''';
}
