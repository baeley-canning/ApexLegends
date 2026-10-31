"""Stdio MCP server (JSON-RPC 2.0, newline-delimited) exposing the harness as tools.

Register with Claude Code:
  claude mcp add deepseek -- python "<path>/deepseekharness" mcp
"""

import json
import sys
import traceback

from . import config, prompts
from .session import Session, ask, list_sessions

SERVER_INFO = {"name": "deepseekharness", "version": "1.0.0"}

_SESSION = {"type": "string", "description": f"Session name (shared memory). Default '{config.DEFAULT_SESSION}'."}

TOOLS = [
    {
        "name": "deepseek_ask",
        "description": (
            "Ask DeepSeek to write code, design architecture, review code, or discuss. "
            "Conversation memory persists per session and auto-compacts, so follow-ups can refer "
            "to earlier turns. Attach files by absolute path instead of pasting them."),
        "inputSchema": {
            "type": "object",
            "properties": {
                "prompt": {"type": "string"},
                "session": _SESSION,
                "mode": {"type": "string", "enum": list(prompts.MODES),
                         "description": "chat | code | architect | review | agent (terse, structured)"},
                "files": {"type": "array", "items": {"type": "string"},
                          "description": "Absolute paths of files to include as context"},
                "reason": {"type": "boolean", "description": "Enable thinking mode (slower, deeper)"},
                "effort": {"type": "string", "enum": ["low", "high", "max"],
                           "description": "Thinking effort when reason=true"},
                "model": {"type": "string", "description": f"Model id; default {config.MODEL}"},
                "stateless": {"type": "boolean", "description": "Don't use or update session memory"},
                "sender": {"type": "string", "description": "Who is asking (e.g. 'claude'). Default 'claude'."},
            },
            "required": ["prompt"],
        },
    },
    {
        "name": "deepseek_memory",
        "description": "Inspect or manage a session's memory: summary, history, list sessions, "
                       "compact now, pin/remove a note, or reset.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "action": {"type": "string",
                           "enum": ["summary", "history", "sessions", "compact", "note", "unnote", "reset"]},
                "session": _SESSION,
                "text": {"type": "string", "description": "Note text (action=note)"},
                "index": {"type": "integer", "description": "Note index (action=unnote) or last-N messages (history)"},
            },
            "required": ["action"],
        },
    },
]


def _call_ask(args):
    r = ask(args["prompt"], session=args.get("session"), mode=args.get("mode", "chat"),
            files=args.get("files", []), reason=args.get("reason"),
            effort=args.get("effort"), model=args.get("model"),
            stateless=bool(args.get("stateless")), sender=args.get("sender", "claude"))
    footer = f"\n\n---\n[model {r['model']}"
    if r.get("session"):
        footer += f" | session '{r['session']}' ~{r.get('context_tokens', 0)} tok"
    if r.get("compacted"):
        footer += " | auto-compacted"
    return r["content"] + footer + "]"


def _call_memory(args):
    action, name = args["action"], args.get("session") or config.DEFAULT_SESSION
    if action == "sessions":
        return json.dumps(list_sessions(), indent=1)
    if action == "summary":
        s = Session.peek(name)
        notes = "\n".join(f"{i}: {n}" for i, n in enumerate(s.notes)) or "(none)"
        return f"Pinned notes:\n{notes}\n\nSummary:\n{s.summary or '(none yet)'}"
    if action == "history":
        s = Session.peek(name)
        msgs = s.messages[-args["index"]:] if args.get("index") else s.messages
        return "\n\n".join(f"### {m['role']}{' (' + m['from'] + ')' if m.get('from') else ''}\n{m['content']}"
                           for m in msgs) or "(empty)"
    with Session.open(name) as s:
        if action == "compact":
            return "compacted" if s.compact(force=True) else "nothing to compact"
        if action == "note":
            s.notes.append(args["text"])
            return f"pinned note {len(s.notes) - 1}"
        if action == "unnote":
            return f"removed: {s.notes.pop(args['index'])}"
        if action == "reset":
            s.reset()
            return "reset (notes kept)"
    raise ValueError(f"unknown action {action!r}")


HANDLERS = {"deepseek_ask": _call_ask, "deepseek_memory": _call_memory}


def _handle(msg):
    method, params = msg.get("method"), msg.get("params") or {}
    if method == "initialize":
        return {"protocolVersion": params.get("protocolVersion", "2025-06-18"),
                "capabilities": {"tools": {}}, "serverInfo": SERVER_INFO}
    if method == "ping":
        return {}
    if method == "tools/list":
        return {"tools": TOOLS}
    if method == "tools/call":
        fn = HANDLERS.get(params.get("name"))
        if not fn:
            raise LookupError(f"unknown tool {params.get('name')!r}")
        try:
            text, is_error = fn(params.get("arguments") or {}), False
        except Exception as e:  # tool errors are reported to the model, not as protocol errors
            text, is_error = f"{type(e).__name__}: {e}", True
        return {"content": [{"type": "text", "text": text}], "isError": is_error}
    raise NotImplementedError(method)


def _send(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def serve():
    sys.stdin.reconfigure(encoding="utf-8")
    sys.stdout.reconfigure(encoding="utf-8")
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            _send({"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "parse error"}})
            continue
        if "id" not in msg:
            continue  # notification
        try:
            _send({"jsonrpc": "2.0", "id": msg["id"], "result": _handle(msg)})
        except NotImplementedError as e:
            _send({"jsonrpc": "2.0", "id": msg["id"],
                   "error": {"code": -32601, "message": f"method not found: {e}"}})
        except Exception as e:
            traceback.print_exc(file=sys.stderr)
            _send({"jsonrpc": "2.0", "id": msg["id"], "error": {"code": -32603, "message": str(e)}})
