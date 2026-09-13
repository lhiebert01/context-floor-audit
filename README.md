# Context Floor — audit

**Find out what your Claude Code setup costs before any work happens.**

Claude Code re-reads your `CLAUDE.md` on every single turn — and it follows `@imports`. That fixed cost is your *context floor*: tokens you pay on turn 1 and again on turn 57, before anything useful happens. Most people have never measured it.

These two scripts measure it. They read files and print. **They write nothing, send nothing, and ask for no email address.** Read them before you run them — they are short.

---

## Run it

**Linux, macOS or WSL:**

```bash
git clone https://github.com/lhiebert01/context-floor-audit.git
cd context-floor-audit
bash claude-context-audit.sh ~/code     # your repo root
bash claude-model-audit.sh   ~/code
```

**Windows PowerShell:**

```powershell
git clone https://github.com/lhiebert01/context-floor-audit.git
cd context-floor-audit\windows
.\claude-context-audit.ps1 -CodeRoot C:\src
.\claude-model-audit.ps1   -CodeRoot C:\src
```

Requires `jq` for the bash scripts (`sudo apt-get install -y jq`). PowerShell 5.1+ for the Windows pair.

---

## What each one tells you

### `claude-context-audit.sh` — your fixed per-turn overhead

Sizes every `CLAUDE.md` that loads into a session **and follows `@imports` recursively**, five hops deep, the way Claude Code does. Then it ranks the largest project `CLAUDE.md` files under the tree you point it at.

This matters more than it sounds. On the machine this came from, the global `CLAUDE.md` was 2 KB — about 526 tokens, comfortably "light". Line 9 was `@claude-lessons-learned.md`, a 57 KB file. The real figure was **14,740 tokens on every turn**. A check that sizes only the top file reports green for the wrong reason.

```
=== Per-turn fixed context overhead ===
Estimated at 4 characters per token. Paid again on EVERY turn. @imports followed.

  ~/.claude/CLAUDE.md        2106 B  ~   526 tok  light
    ↳ @~/.claude/claude-lessons-learned.md  56859 B  ~ 14214 tok  heavy

  Fixed overhead per turn: ~14740 tokens
  over 50 turns that alone is ~737000 tokens
```

Token counts are estimated at roughly 4 characters per token. For the live figure, run `/context` in a session.

### `claude-model-audit.sh` — which model you are actually getting

Claude Code resolves the model through eight layers of precedence. `/model` typed in a session **never persists**, so re-picking it does nothing for the next session. And a `model` key in any single repository's `.claude/settings.json` silently overrides your user-level setting in that repo — which is the layer almost nobody checks.

This script reports all of them: environment variables, your user file, the current project's files, and every project-level pin under the tree you give it. **It exits non-zero if any layer disagrees**, so it also works as a weekly check or a CI step.

---

## What these scripts do not do

They do not change anything. They do not install anything. They do not contact any server. If you want to confirm that, the files are short enough to read in a couple of minutes, which is rather the point — a tool that inspects your configuration should be one you can inspect yourself.

They also cannot see a claude.ai browser session. `~/.claude/settings.json` governs Claude Code on one machine and nothing else.

---

## If your number is large

Over roughly 4,000 tokens of fixed overhead, it is worth doing something about, because you pay it on every turn of every session from now on. Every thousand tokens you cut is cut permanently.

You can fix it by hand — trim the file, replace a large `@import` with a short extract plus a pointer, and keep in `CLAUDE.md` only what a session must know before its first action.

Or the full **Context Floor** kit does it in one command: an installer for Windows, WSL, Linux and macOS that backs up and validates what it writes, a status line showing model, context in absolute tokens, spend and your 5-hour and 7-day meters on every turn, the runbook, and the browser-session playbook. https://pigenai.lemonsqueezy.com/checkout/buy/68e502b4-c483-4709-b679-9219b68e5254

---

## Licence

MIT. Copyright (c) 2026 PIGENAI LLC.

*Not affiliated with, endorsed by, or sponsored by Anthropic PBC. "Claude" and "Anthropic" are trademarks of their respective owners and are used here only to describe compatibility.*
