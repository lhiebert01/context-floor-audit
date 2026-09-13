#!/usr/bin/env bash
# Context Floor — audit. Copyright (c) 2026 PIGENAI LLC. MIT licensed.
# claude-model-audit.sh — show EVERY layer that can decide which model runs,
# in Claude Code's real precedence order, and flag anything not set to Opus.
#
# Run it from anywhere:   bash ~/.claude/claude-model-audit.sh
# Sweep a code tree too:  bash ~/.claude/claude-model-audit.sh ~/code
#
# Precedence, highest wins:
#   1. /model in-session          (this session only, never persists)
#   2. claude --model FLAG        (that invocation only)
#   3. ANTHROPIC_MODEL env        (every session in that shell)
#   4. .claude/settings.local.json   (project, yours, gitignored)
#   5. .claude/settings.json         (project, shared/committed)
#   6. ~/.claude/settings.json       (user, all projects)
#   7. ANTHROPIC_DEFAULT_MODEL env
# Managed/enterprise policy overrides everything above it.

set -uo pipefail
SWEEP="${1:-}"
# verdict() runs inside $( ) subshells, so a plain variable cannot carry the
# failure back to the parent shell. Use a flag FILE instead. This exact bug
# made an earlier version of this script print "clean" while displaying three
# bad pins on screen.
FLAG=$(mktemp)
trap 'rm -f "$FLAG"' EXIT
R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[1m'; DIM=$'\e[2m'; N=$'\e[0m'
getmodel() { # $1 = json file -> prints model value or nothing
  [ -f "$1" ] || return 0
  jq -r '(.model // empty) | tostring' "$1" 2>/dev/null
}

# Which model this machine is supposed to be running. Override per-machine:
#   CLAUDE_EXPECT_MODEL=sonnet bash claude-model-audit.sh
EXPECT="${CLAUDE_EXPECT_MODEL:-opus}"
EXPECT_UC=$(printf '%s' "$EXPECT" | tr '[:lower:]' '[:upper:]')

verdict() { # $1 = value
  case "$1" in
    ""|null) printf '%s' "${DIM}(not set)${N}" ;;
    best|opusplan|default) printf '%s' "${G}${1}  OK${N}" ;;
    *) if printf '%s' "$1" | grep -qi -- "$EXPECT"; then printf '%s' "${G}${1}  OK${N}"
       else printf 1 > "$FLAG"; printf '%s' "${R}${B}${1}  <-- NOT ${EXPECT_UC}${N}"; fi ;;
  esac
}

printf '%s\n' "${B}=== Claude Code model audit ===${N}"
printf '%s\n' "${DIM}$(date)  host $(hostname)  user $(whoami)${N}"
echo

printf '%s\n' "${B}Environment variables (override both settings files)${N}"
for v in ANTHROPIC_MODEL ANTHROPIC_DEFAULT_MODEL ANTHROPIC_SMALL_FAST_MODEL; do
  val="${!v:-}"
  printf '  %-28s ' "$v"
  if [ -z "$val" ]; then printf '%s\n' "${DIM}(unset)${N}"; else printf '%s\n' "$(verdict "$val")"; fi
done
echo
printf '%s\n' "  ${DIM}If either of the first two is set, unset it and remove it from ~/.bashrc / ~/.zshrc.${N}"
echo

printf '%s\n' "${B}Settings files, lowest precedence first${N}"
for f in "$HOME/.claude/settings.json" \
         "$PWD/.claude/settings.json" \
         "$PWD/.claude/settings.local.json"; do
  printf '  %-46s ' "${f/#$HOME/~}"
  if [ ! -f "$f" ]; then printf '%s\n' "${DIM}(absent)${N}"; continue; fi
  if ! jq empty "$f" 2>/dev/null; then printf '%s\n' "${R}INVALID JSON — Claude Code may ignore this file${N}"; continue; fi
  printf '%s\n' "$(verdict "$(getmodel "$f")")"
done
echo

printf '%s\n' "${B}Other settings worth seeing in the user file${N}"
UF="$HOME/.claude/settings.json"
if [ -f "$UF" ]; then
  for k in defaultMode statusLine autoCompactEnabled autoCompactWindow effortLevel autoMemoryEnabled disableBundledSkills; do
    case "$k" in
      # On 2.1.269 the permission mode lives at permissions.defaultMode; a
      # top-level-only read printed a false "(not set)" (found 12 Sep 2026).
      defaultMode) q='(.permissions.defaultMode // .defaultMode // empty)' ;;
      # statusLine is an object {type:"command",command:"..."} on 2.1.269
      statusLine)  q='(.statusLine.command? // .statusLine // empty)' ;;
      *)           q="(.${k} // empty)" ;;
    esac
    v=$(jq -r "$q | tostring" "$UF" 2>/dev/null)
    printf '  %-24s %s\n' "$k" "${v:-${DIM}(not set)${N}}"
  done
else
  printf '  %s\n' "${R}~/.claude/settings.json does not exist${N}"
fi
echo

if [ -n "$SWEEP" ] && [ -d "$SWEEP" ]; then
  printf '%s\n' "${B}Project-level pins under ${SWEEP}${N}"
  printf '%s\n' "${DIM}These OVERRIDE your user file. This is the step people miss.${N}"
  n=0
  while IFS= read -r f; do
    v=$(getmodel "$f"); [ -z "$v" ] && continue
    n=$((n+1)); printf '  %-60s %s\n' "${f#$SWEEP/}" "$(verdict "$v")"
  done < <(find "$SWEEP" -maxdepth 4 -type d -name node_modules -prune -o \
              -type f \( -name settings.json -o -name settings.local.json \) \
              -path '*/.claude/*' -print 2>/dev/null)
  [ "$n" -eq 0 ] && printf '  %s\n' "${G}no project-level model pins found — good${N}"
  echo
fi

if [ -s "$FLAG" ]; then
  printf '%s\n' "${R}${B}RESULT: at least one layer is NOT set to ${EXPECT_UC}. Fix the red lines above.${N}"
  exit 1
else
  printf '%s\n' "${G}${B}RESULT: no conflicting model pin found in any layer checked.${N}"
  printf '%s\n' "${DIM}Confirm the live session too: start claude and run /status${N}"
fi
