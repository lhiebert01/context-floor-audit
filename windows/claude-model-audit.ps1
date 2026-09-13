# Context Floor — audit. Copyright (c) 2026 PIGENAI LLC. MIT licensed.
<#
  claude-model-audit.ps1 — show EVERY layer that can decide which model runs,
  in Claude Code's real precedence order, and flag anything that is not the
  model you expect. Exits 1 if it finds one, so it works in a scheduled check.

    powershell -File claude-model-audit.ps1                 # this machine
    powershell -File claude-model-audit.ps1 -CodeRoot C:\src  # + project pins
    $env:CLAUDE_EXPECT_MODEL='sonnet'; powershell -File claude-model-audit.ps1

  Precedence, highest wins:
    1. /model in-session (never persists)   2. claude --model FLAG
    3. ANTHROPIC_MODEL env                  4. .claude\settings.local.json
    5. .claude\settings.json (project)      6. ~\.claude\settings.json (user)
    7. ANTHROPIC_DEFAULT_MODEL env
  Managed/enterprise policy overrides everything.
#>
param([string]$CodeRoot = '')
$ErrorActionPreference = 'SilentlyContinue'
$E=[char]27; $cRed="$E[31m"; $cGrn="$E[32m"; $cBold="$E[1m"; $cDim="$E[2m"; $cOff="$E[0m"
$expect = if ($env:CLAUDE_EXPECT_MODEL) { $env:CLAUDE_EXPECT_MODEL } else { 'opus' }
$bad = $false

function Get-Model($file) {
  if (-not (Test-Path $file)) { return $null }
  try { return (Get-Content $file -Raw | ConvertFrom-Json).model } catch { return '!INVALID' }
}
function Verdict($v) {
  if (-not $v) { return "$cDim(not set)$cOff" }
  if ($v -eq '!INVALID') { $script:bad = $true; return "${cRed}INVALID JSON - Claude Code may ignore this file$cOff" }
  if ($v -match [regex]::Escape($expect) -or $v -in @('best','opusplan','default')) { return "$cGrn$v  OK$cOff" }
  $script:bad = $true; return "$cRed$cBold$v  <-- NOT $($expect.ToUpper())$cOff"
}

Write-Host "$cBold=== Claude Code model audit ===$cOff"
Write-Host "$cDim$(Get-Date)  host $env:COMPUTERNAME  user $env:USERNAME  expecting '$expect'$cOff`n"

Write-Host "${cBold}Environment variables (override both settings files)$cOff"
foreach ($v in 'ANTHROPIC_MODEL','ANTHROPIC_DEFAULT_MODEL','ANTHROPIC_SMALL_FAST_MODEL') {
  $val = [Environment]::GetEnvironmentVariable($v)
  Write-Host ("  {0,-28} {1}" -f $v, $(if ($val) { Verdict $val } else { "$cDim(unset)$cOff" }))
}
Write-Host "`n${cBold}Settings files, lowest precedence first$cOff"
$userSettings = Join-Path $HOME '.claude\settings.json'
foreach ($f in @($userSettings, (Join-Path $PWD '.claude\settings.json'), (Join-Path $PWD '.claude\settings.local.json'))) {
  if (-not (Test-Path $f)) { Write-Host ("  {0,-52} {1}" -f $f, "$cDim(absent)$cOff"); continue }
  Write-Host ("  {0,-52} {1}" -f $f, (Verdict (Get-Model $f)))
}

Write-Host "`n${cBold}Other settings worth seeing in the user file$cOff"
if (Test-Path $userSettings) {
  $s = $null; try { $s = Get-Content $userSettings -Raw | ConvertFrom-Json } catch {}
  $show = [ordered]@{
    'permissions.defaultMode' = $s.permissions.defaultMode
    'statusLine'              = $(if ($s.statusLine -is [string]) { "$cRed$($s.statusLine)  <-- STRING FORM, SILENTLY IGNORED$cOff" } else { $s.statusLine.command })
    'autoCompactEnabled'      = $s.autoCompactEnabled
    'autoCompactWindow'       = $s.autoCompactWindow
    'effortLevel'             = $s.effortLevel
    'autoMemoryEnabled'       = $s.autoMemoryEnabled
    'disableBundledSkills'    = $s.disableBundledSkills
  }
  foreach ($k in $show.Keys) { Write-Host ("  {0,-26} {1}" -f $k, $(if ($null -ne $show[$k] -and "$($show[$k])" -ne '') { $show[$k] } else { "$cDim(not set)$cOff" })) }
  if ($s.statusLine -is [string]) { $bad = $true }
} else { Write-Host "  $cRed$userSettings does not exist$cOff" }

if ($CodeRoot -and (Test-Path $CodeRoot)) {
  Write-Host "`n${cBold}Project-level pins under $CodeRoot$cOff"
  Write-Host "$cDim`These OVERRIDE your user file. This is the step people miss.$cOff"
  $n = 0
  Get-ChildItem -Path $CodeRoot -Recurse -Depth 4 -File -Include 'settings.json','settings.local.json' -EA SilentlyContinue |
    Where-Object { $_.DirectoryName -like '*\.claude' -and $_.FullName -notlike '*\node_modules\*' } | ForEach-Object {
      $m = Get-Model $_.FullName
      if ($m) { $n++; Write-Host ("  {0,-62} {1}" -f $_.FullName.Replace($CodeRoot,'').TrimStart('\'), (Verdict $m)) }
    }
  if ($n -eq 0) { Write-Host "  ${cGrn}no project-level model pins found - good$cOff" }
}

Write-Host ''
if ($bad) { Write-Host "$cRed$cBold`RESULT: at least one layer is wrong. Fix the red lines above.$cOff"; exit 1 }
Write-Host "$cGrn$cBold`RESULT: no conflicting model pin found in any layer checked.$cOff"
Write-Host "$cDim`Confirm the live session too: start claude and run /status$cOff"
exit 0
