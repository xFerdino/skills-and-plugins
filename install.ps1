# For agents without a plugin CLI (the Codex app): junction every plugin's skills into
# ~/.codex/skills. Claude Code uses the plugin instead (see README).
# Junctions point at this clone, so `git pull` updates them in place.
# Existing entries are never overwritten.
$target = "$HOME\.codex\skills"
New-Item -ItemType Directory -Force $target | Out-Null
foreach ($s in Get-ChildItem (Join-Path $PSScriptRoot 'plugins\*\skills') -Directory | Get-ChildItem -Directory) {
  $link = Join-Path $target $s.Name
  if (Test-Path $link) { Write-Host "exists, skipped: $link"; continue }
  New-Item -ItemType Junction -Path $link -Target $s.FullName | Out-Null
  Write-Host "linked: $link -> $($s.FullName)"
}
