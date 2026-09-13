#!/usr/bin/env bash
# Context Floor — audit. Copyright (c) 2026 PIGENAI LLC. MIT licensed.
# claude-context-audit.sh — measure the FIXED cost you pay on every single turn.
#
# Claude Code re-reads and re-injects your CLAUDE.md files on every turn. A
# 20 KB CLAUDE.md is roughly 5,000 tokens paid again on turn 1, turn 2, turn 57.
# This script shows that fixed overhead so you can shrink it once and benefit
# on every request forever.
#
# It FOLLOWS @imports (recursively, max 5 hops — the same limit Claude Code
# applies). An earlier version sized only the CLAUDE.md file itself and
# reported a 2 KB file as "light" while its `@claude-lessons-learned.md` line
# was pulling 57 KB (~14,000 tokens) into every turn (found 12 Sep 2026).
# A guard is only as good as what it can see.
#
# Usage:  bash ~/.claude/claude-context-audit.sh            # current project
#         bash ~/.claude/claude-context-audit.sh ~/code     # rank a whole tree

set -uo pipefail
TREE="${1:-}"
R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[1m'; DIM=$'\e[2m'; N=$'\e[0m'
MAXDEPTH=5

# ~4 characters per token is the standard rough estimate for English prose.
tok() { echo $(( ${1:-0} / 4 )); }
sizeof() { [ -f "$1" ] && wc -c < "$1" | tr -d ' ' || echo 0; }
short() { printf '%s' "${1/#$HOME/~}"; }

band() { # $1 tokens
  if   [ "$1" -ge 5000 ]; then printf '%s' "${R}${B}heavy${N}"
  elif [ "$1" -ge 2000 ]; then printf '%s' "${Y}moderate${N}"
  else printf '%s' "${G}light${N}"; fi
}

# @import targets in a file: an @token at line start or after whitespace
# (so emails and handles like foo@bar are not matched). Trailing punctuation
# is stripped so an inline "see @README.md." still resolves.
imports_of() { # $1 = file
  [ -f "$1" ] || return 0
  grep -oE '(^|[[:space:]])@[^[:space:]]+' "$1" 2>/dev/null \
    | sed -E 's/^[[:space:]]*@//; s/[),.;:`]+$//'
}

# resolve an @import target the way Claude Code does: ~/ , absolute, or
# relative to the directory of the importing file
resolve() { # $1 = importing file, $2 = raw target
  case "$2" in
    "~/"*) printf '%s' "$HOME/${2#\~/}" ;;
    /*)    printf '%s' "$2" ;;
    *)     printf '%s' "$(dirname "$1")/$2" ;;
  esac
}

# walk a file and everything it imports, depth-first, each file once.
# prints  bytes<TAB>path<TAB>depth  — one line per file actually loaded
walk() { # $1 = file, $2 = depth, $3 = visited-list file
  local f d seen t
  f=$(readlink -f -- "$1" 2>/dev/null || printf '%s' "$1"); d="${2:-0}"; seen="$3"
  [ -f "$f" ] || return 0
  grep -qxF -- "$f" "$seen" 2>/dev/null && return 0
  printf '%s\n' "$f" >> "$seen"
  printf '%s\t%s\t%s\n' "$(sizeof "$f")" "$f" "$d"
  [ "$d" -ge "$MAXDEPTH" ] && return 0
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    walk "$(resolve "$f" "$t")" $((d+1)) "$seen"
  done < <(imports_of "$f")
}

# total bytes of a file plus everything it imports
total_of() { # $1 = file
  local s tot=0 b
  s=$(mktemp)
  while IFS=$'\t' read -r b _ _; do tot=$((tot + b)); done < <(walk "$1" 0 "$s")
  rm -f "$s"; echo "$tot"
}

printf '%s\n' "${B}=== Per-turn fixed context overhead ===${N}"
printf '%s\n' "${DIM}Estimated at 4 characters per token. Paid again on EVERY turn. @imports followed.${N}"
echo

SEEN=$(mktemp); trap 'rm -f "$SEEN"' EXIT
TOTAL=0
# the project memory index is loaded into context each session too
MEMIDX="$HOME/.claude/projects/${PWD//\//-}/memory/MEMORY.md"
for root in "$HOME/.claude/CLAUDE.md" "$HOME/.claude/MEMORY.md" "$MEMIDX" \
            "$PWD/CLAUDE.md" "$PWD/CLAUDE.local.md" "$PWD/.claude/CLAUDE.md"; do
  while IFS=$'\t' read -r b f d; do
    [ "${b:-0}" -eq 0 ] && continue
    t=$(tok "$b"); TOTAL=$((TOTAL + t))
    if [ "$d" -gt 0 ]; then
      pre="$(printf '%*s' $((d*2)) '')↳ @"
    else pre=""; fi
    printf '  %-52s %7s B  ~%6s tok  %s\n' "${pre}$(short "$f")" "$b" "$t" "$(band "$t")"
  done < <(walk "$root" 0 "$SEEN")
done

if [ "$TOTAL" -eq 0 ]; then
  printf '  %s\n' "${DIM}no CLAUDE.md or MEMORY.md found here${N}"
else
  echo
  printf '  %s\n' "${B}Fixed overhead per turn: ~${TOTAL} tokens${N}"
  for n in 20 50 100; do
    printf '  %s\n' "${DIM}over ${n} turns that alone is ~$(( TOTAL * n )) tokens${N}"
  done
  echo
  if [ "$TOTAL" -ge 4000 ]; then
    printf '  %s\n' "${R}${B}ACTION: this is worth trimming. Every 1,000 tokens you cut here${N}"
    printf '  %s\n' "${R}${B}        saves 1,000 tokens on every turn of every session.${N}"
  else
    printf '  %s\n' "${G}Fixed overhead is reasonable.${N}"
  fi
fi
echo
printf '  %s\n' "${DIM}Over 4,000 tokens of fixed overhead? The full kit fixes it in one command — see the README.${N}"

if [ -n "$TREE" ] && [ -d "$TREE" ]; then
  echo; printf '%s\n' "${B}Largest project CLAUDE.md files under ${TREE} (own size + @imports)${N}"
  find "$TREE" -maxdepth 3 -type d -name node_modules -prune -o \
       -type f -name 'CLAUDE.md' -print 2>/dev/null |
  while IFS= read -r f; do
    own=$(sizeof "$f"); all=$(total_of "$f")
    printf '%s\t%s\t%s\n' "$all" "$own" "$f"
  done |
  sort -rn | head -12 |
  { rows=0
    while IFS=$'\t' read -r all own f; do
      rows=$((rows+1)); t=$(tok "$all"); extra=""
      [ "$all" -gt "$own" ] && extra="${DIM}(+$((all - own)) B imported)${N}"
      printf '  %-58s %7s B  ~%6s tok  %s %s\n' "${f#$TREE/}" "$all" "$t" "$(band "$t")" "$extra"
    done
    [ "$rows" -eq 0 ] && printf '  %s\n' "${DIM}(none found)${N}"; : ; }
fi
echo
printf '%s\n' "${DIM}Live figure for the real thing: start claude and run /context${N}"
