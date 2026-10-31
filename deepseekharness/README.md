# deepseekharness

A harness for the DeepSeek API that humans and AI agents (Claude Code, Qwen, scripts) can all use
to code and architect. Each **session** keeps its own memory, and agents can share one. When a
session's history gets long, the harness **auto-compacts** it: older turns are summarised into a
running memory, and recent turns are kept word for word.

Pure Python 3.10+ stdlib. Nothing to install.

## Setup

1. Copy `.env.example` to `.env` and set `DEEPSEEK_API_KEY` (or set the env var).
2. Test it: `python -m deepseekharness ask "say hi"` from the folder above this one, or
   `deepseekharness\ds.cmd ask "say hi"` from anywhere.

## CLI

```
ds ask "design a plugin system for X" -s myproj -m architect
ds ask "implement step 1 of the plan" -s myproj -m code -f src/app.py -f src/db.py
type error.log | ds ask "why is this failing?" -s myproj
ds ask "hard question" -r -e max --show-reasoning   # thinking mode, max effort
ds ask "..." --model deepseek-v4-pro            # different model (default deepseek-v4-flash)
ds ask "..." --json --as qwen                   # machine-readable, tagged with the sender
ds ask "..." --stateless                        # no memory
ds chat -s myproj                               # interactive; /help for commands
ds sessions | history -s myproj -n 6 | summary -s myproj
ds note -s myproj "Target is Python 3.12, no external deps"   # pinned, never compacted
ds compact -s myproj | reset -s myproj [--all]
```

Modes (`-m`): `chat`, `code`, `architect`, `review`, `agent` (terse, structured output for
agents to parse).

## For AI agents

- **Claude Code (MCP):** register once:
  ```
  claude mcp add deepseek --scope user -- python "C:\Users\New User\OneDrive\Desktop\cheating\deepseekharness" mcp
  ```
  That gives Claude two tools: `deepseek_ask` (prompt, session, mode, files, reason, effort, model, stateless)
  and `deepseek_memory` (summary, history, sessions, compact, note, unnote, reset).
- **Any agent with a shell:** run
  `python "<path>\deepseekharness" ask "<prompt>" -s <project> -m code --as <agent-name> --json`
  and read `.content` from the JSON. Pass files with `-f` rather than pasting them.
- **Python:** `from deepseekharness import ask` →
  `ask(prompt, session=, mode=, files=, reason=, sender=)` returns a dict.

Give each project its own session name so its memory stays focused. When several agents use the
same session they share context, and every message is tagged `[from: <sender>]` so DeepSeek can
tell who said what. A lock file makes concurrent calls to the same session wait their turn.

## How memory works

Session files live in `sessions/<name>.json`. They hold three things: `notes` (pinned),
`summary` (compacted memory), and `messages` (recent turns). Before each call, if
summary + history + the new message would go over `DEEPSEEK_COMPACT_AT` (100k tokens by default),
everything except the newest `DEEPSEEK_KEEP_RECENT` (20k) tokens is merged into the summary by
DeepSeek. The summary keeps decisions, file paths, the current state and open tasks. All
settings are listed in `config.py` and `.env.example`.
