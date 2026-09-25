# Junction every skill in skills/ into Claude Code's and Codex's user skill folders.
# Junctions point at this clone, so `git pull` updates installed skills in place.
# Re-run after adding a skill. Existing entries are never overwritten.
$skills = Join-Path $PSScriptRoot 'skills'
foreach ($target in "$HOME\.claude\skills", "$HOME\.codex\skills") {
  New-Item -ItemType Directory -Force $target | Out-Null
  foreach ($s in Get-ChildItem $skills -Directory) {
    $link = Join-Path $target $s.Name
    if (Test-Path $link) { Write-Host "exists, skipped: $link"; continue }
    New-Item -ItemType Junction -Path $link -Target $s.FullName | Out-Null
    Write-Host "linked: $link -> $($s.FullName)"
  }
}
