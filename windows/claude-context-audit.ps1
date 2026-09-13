# Context Floor — audit. Copyright (c) 2026 PIGENAI LLC. MIT licensed.
<#
  claude-context-audit.ps1 — measure the FIXED cost you pay on every single turn.

  Claude Code re-reads and re-injects your CLAUDE.md files on every turn, and it
  FOLLOWS @imports. A 2 KB CLAUDE.md that imports a 57 KB file costs ~14,000
  tokens per turn, forever. A check that sizes only the top file is a false green.

    powershell -File claude-context-audit.ps1                  # current project
    powershell -File claude-context-audit.ps1 -CodeRoot C:\src # rank a tree
#>
param([string]$CodeRoot = '', [int]$MaxDepth = 5)
$ErrorActionPreference = 'SilentlyContinue'
$E=[char]27; $cRed="$E[31m"; $cYel="$E[33m"; $cGrn="$E[32m"; $cBold="$E[1m"; $cDim="$E[2m"; $cOff="$E[0m"
function Tok($bytes) { [int]($bytes/4) }   # ~4 chars per token for English prose
function Band($t) { if ($t -ge 5000) { "${cRed}${cBold}heavy$cOff" } elseif ($t -ge 2000) { "${cYel}moderate$cOff" } else { "${cGrn}light$cOff" } }

# @import targets: an @token at line start or after whitespace (so foo@bar is not matched)
function Get-Imports($file) {
  $txt = Get-Content $file -Raw -EA SilentlyContinue
  if (-not $txt) { return @() }
  [regex]::Matches($txt, '(?m)(?:^|\s)@(\S+)') | ForEach-Object { $_.Groups[1].Value.TrimEnd(').,;:`') }
}
function Resolve-Import($from, $target) {
  if ($target.StartsWith('~/') -or $target.StartsWith('~\')) { return (Join-Path $HOME $target.Substring(2)) }
  if ([IO.Path]::IsPathRooted($target)) { return $target }
  return (Join-Path (Split-Path $from -Parent) $target)
}
# returns @{Path;Bytes;Depth} for the file and everything it imports, each once
function Walk($file, $depth, $seen) {
  if (-not (Test-Path $file -PathType Leaf)) { return @() }
  $full = (Resolve-Path $file).Path
  if ($seen.Contains($full)) { return @() }
  [void]$seen.Add($full)
  $out = @([pscustomobject]@{ Path=$full; Bytes=(Get-Item $full).Length; Depth=$depth })
  if ($depth -ge $MaxDepth) { return $out }
  foreach ($t in Get-Imports $full) { $out += Walk (Resolve-Import $full $t) ($depth+1) $seen }
  return $out
}

Write-Host "$cBold=== Per-turn fixed context overhead ===$cOff"
Write-Host "$cDim`Estimated at 4 characters per token. Paid again on EVERY turn. @imports followed.$cOff`n"
$seen = New-Object System.Collections.Generic.HashSet[string]
$total = 0
$roots = @((Join-Path $HOME '.claude\CLAUDE.md'), (Join-Path $HOME '.claude\MEMORY.md'),
           (Join-Path $PWD 'CLAUDE.md'), (Join-Path $PWD 'CLAUDE.local.md'), (Join-Path $PWD '.claude\CLAUDE.md'))
foreach ($r in $roots) {
  foreach ($e in (Walk $r 0 $seen)) {
    $t = Tok $e.Bytes; $total += $t
    $label = $(if ($e.Depth -gt 0) { (' ' * ($e.Depth*2)) + '@ ' + $e.Path } else { $e.Path })
    Write-Host ("  {0,-56} {1,8} B  ~{2,6} tok  {3}" -f $label, $e.Bytes, $t, (Band $t))
  }
}
if ($total -eq 0) { Write-Host "  ${cDim}no CLAUDE.md or MEMORY.md found here$cOff" }
else {
  Write-Host "`n  ${cBold}Fixed overhead per turn: ~$total tokens$cOff"
  foreach ($n in 20,50,100) { Write-Host "  $cDim`over $n turns that alone is ~$($total*$n) tokens$cOff" }
  if ($total -ge 4000) {
    Write-Host "`n  $cRed$cBold`ACTION: this is worth trimming. Every 1,000 tokens you cut here$cOff"
    Write-Host "  $cRed$cBold        saves 1,000 tokens on every turn of every session.$cOff"
  } else { Write-Host "`n  ${cGrn}Fixed overhead is reasonable.$cOff" }
}
Write-Host "`n  ${cDim}Over 4,000 tokens of fixed overhead? The full kit fixes it in one command $([char]0x2014) see the README.$cOff"

if ($CodeRoot -and (Test-Path $CodeRoot)) {
  Write-Host "`n${cBold}Largest project CLAUDE.md files under $CodeRoot (own size + @imports)$cOff"
  Get-ChildItem -Path $CodeRoot -Recurse -Depth 3 -File -Filter 'CLAUDE.md' -EA SilentlyContinue |
    Where-Object { $_.FullName -notlike '*\node_modules\*' } | ForEach-Object {
      $s = New-Object System.Collections.Generic.HashSet[string]
      $all = (Walk $_.FullName 0 $s | Measure-Object -Property Bytes -Sum).Sum
      [pscustomobject]@{ All=$all; Own=$_.Length; Path=$_.FullName }
    } | Sort-Object All -Descending | Select-Object -First 12 | ForEach-Object -Begin { $rowCount = 0 } -Process {
      $rowCount++
      $t = Tok $_.All
      $extra = $(if ($_.All -gt $_.Own) { "$cDim(+$($_.All - $_.Own) B imported)$cOff" } else { '' })
      Write-Host ("  {0,-58} {1,8} B  ~{2,6} tok  {3} {4}" -f $_.Path.Replace($CodeRoot,'').TrimStart('\'), $_.All, $t, (Band $t), $extra)
    } -End { if ($rowCount -eq 0) { Write-Host "  $cDim(none found)$cOff" } }
}
Write-Host "`n$cDim`Live figure for the real thing: start claude and run /context$cOff"
