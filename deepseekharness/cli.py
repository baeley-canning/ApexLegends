"""Command-line interface. Run `python -m deepseekharness -h`."""

import argparse
import json
import sys

from . import config, prompts
from .client import DeepSeekError
from .session import Session, ask, list_sessions


def _out(text="", end="\n"):
    sys.stdout.write(text + end)
    sys.stdout.flush()


def _err(text):
    sys.stderr.write(text + "\n")
    sys.stderr.flush()


def _add_ask_opts(p):
    p.add_argument("-s", "--session", default=config.DEFAULT_SESSION,
                   help="session name (shared memory); default: %(default)s")
    p.add_argument("-m", "--mode", default="chat", choices=list(prompts.MODES))
    p.add_argument("-f", "--file", action="append", default=[], help="attach a file (repeatable)")
    p.add_argument("-r", "--reason", action="store_const", const=True, default=None,
                   help="enable thinking mode")
    p.add_argument("--no-reason", dest="reason", action="store_const", const=False,
                   help="disable thinking mode (overrides DEEPSEEK_THINKING=on)")
    p.add_argument("-e", "--effort", choices=["low", "high", "max"],
                   help=f"thinking effort; default {config.EFFORT}")
    p.add_argument("--model", help=f"model id; default {config.MODEL} (e.g. deepseek-v4-pro)")
    p.add_argument("--as", dest="sender", help="who is asking, e.g. claude, qwen, user")
    p.add_argument("-t", "--temperature", type=float)
    p.add_argument("--show-reasoning", action="store_true", help="print reasoning to stderr")


def cmd_ask(a):
    prompt = " ".join(a.prompt)
    if not sys.stdin.isatty():
        piped = sys.stdin.read()
        if piped.strip():
            prompt = f"{prompt}\n\n{piped}" if prompt else piped
    if not prompt.strip() and not a.file:
        _err("nothing to ask: give a prompt, pipe stdin, or attach files with -f")
        return 2

    streaming = not (a.json or a.no_stream)
    on_reasoning = (lambda t: (sys.stderr.write(t), sys.stderr.flush())) if (streaming and a.show_reasoning) else None
    r = ask(prompt, session=a.session, mode=a.mode, files=a.file, reason=a.reason,
            effort=a.effort, model=a.model, stateless=a.stateless, sender=a.sender, temperature=a.temperature,
            on_token=(lambda t: _out(t, end="")) if streaming else None,
            on_reasoning=on_reasoning)

    if a.json:
        _out(json.dumps(r, ensure_ascii=False, indent=1))
    elif streaming:
        _out()
    else:
        if a.show_reasoning and r["reasoning"]:
            _err(r["reasoning"])
        _out(r["content"])
    if r.get("compacted") and not a.json:
        _err(f"[session '{r['session']}' was auto-compacted]")
    return 0


REPL_HELP = """Commands:
  /mode <chat|code|architect|review|agent>   switch mode
  /file <path>      attach a file to your next message (repeatable)
  /reason           toggle thinking mode
  /effort <low|high|max>   thinking effort
  /note <text>      pin a fact to this session (never compacted)
  /notes            list pinned notes
  /summary          show the compacted memory
  /compact          compact now
  /reset            clear history and summary (keeps notes)
  /session <name>   switch session
  /exit             quit
End a line with \\ to keep typing on the next line."""


def cmd_chat(a):
    session, mode, effort, pending = a.session, a.mode, a.effort, list(a.file)
    reason = config.THINKING if a.reason is None else a.reason
    s = Session.peek(session)
    _err(f"DeepSeek harness | session '{session}' ({len(s.messages)} msgs, "
         f"~{s.context_tokens()} tokens, {s.data['compactions']} compactions) | mode {mode}")
    _err("Type /help for commands.")
    while True:
        try:
            lines = [input(f"\n[{session}:{mode}{'+R' if reason else ''}] > ")]
            while lines[-1].endswith("\\"):
                lines[-1] = lines[-1][:-1]
                lines.append(input("... "))
        except (EOFError, KeyboardInterrupt):
            _out()
            return 0
        line = "\n".join(lines).strip()
        if not line:
            continue

        if line.startswith("/"):
            cmd, _, arg = line[1:].partition(" ")
            arg = arg.strip()
            if cmd in ("exit", "quit", "q"):
                return 0
            elif cmd == "help":
                _err(REPL_HELP)
            elif cmd == "mode" and arg in prompts.MODES:
                mode = arg
            elif cmd == "file" and arg:
                pending.append(arg.strip('"'))
                _err(f"will attach: {', '.join(pending)}")
            elif cmd == "reason":
                reason = not reason
                _err(f"thinking {'on' if reason else 'off'}")
            elif cmd == "effort" and arg in ("low", "high", "max"):
                effort = arg
            elif cmd == "note" and arg:
                with Session.open(session) as s:
                    s.notes.append(arg)
                _err("pinned.")
            elif cmd == "notes":
                for i, n in enumerate(Session.peek(session).notes):
                    _err(f"  {i}: {n}")
            elif cmd == "summary":
                _err(Session.peek(session).summary or "(no summary yet)")
            elif cmd == "compact":
                with Session.open(session) as s:
                    _err("compacted." if s.compact(force=True) else "nothing to compact.")
            elif cmd == "reset":
                with Session.open(session) as s:
                    s.reset()
                _err("reset.")
            elif cmd == "session" and arg:
                session = arg
                _err(f"switched to session '{session}'")
            else:
                _err("unknown command; /help")
            continue

        def show_reasoning(t):
            sys.stderr.write(t)
            sys.stderr.flush()

        try:
            r = ask(line, session=session, mode=mode, files=pending, reason=reason,
                    effort=effort, model=a.model, sender=a.sender, temperature=a.temperature,
                    on_token=lambda t: _out(t, end=""),
                    on_reasoning=show_reasoning if a.show_reasoning else None)
            _out()
            pending = []
            if r["compacted"]:
                _err("[auto-compacted older history into the session summary]")
        except (DeepSeekError, FileNotFoundError, TimeoutError) as e:
            _err(f"error: {e}")


def cmd_sessions(a):
    rows = list_sessions()
    if a.json:
        _out(json.dumps(rows, indent=1))
    elif not rows:
        _out("(no sessions)")
    else:
        for r in rows:
            _out(f"{r['name']:<24} {r['messages']:>4} msgs  ~{r['tokens']:>6} tok  "
                 f"{r['compactions']} compactions  {r['notes']} notes  {r['updated']}")
    return 0


def cmd_history(a):
    s = Session.peek(a.session)
    msgs = s.messages[-a.n:] if a.n else s.messages
    if a.json:
        _out(json.dumps({"summary": s.summary, "notes": s.notes, "messages": msgs},
                        ensure_ascii=False, indent=1))
        return 0
    if s.summary:
        _out("=== COMPACTED MEMORY ===\n" + s.summary + "\n")
    for m in msgs:
        who = m["role"] + (f" ({m['from']})" if m.get("from") else "")
        _out(f"=== {who} @ {m.get('ts', '')} ===\n{m['content']}\n")
    return 0


def cmd_summary(a):
    _out(Session.peek(a.session).summary or "(no summary yet)")
    return 0


def cmd_compact(a):
    with Session.open(a.session) as s:
        before = s.context_tokens()
        done = s.compact(force=True)
        _out(f"compacted ~{before} -> ~{s.context_tokens()} tokens" if done else "nothing to compact")
    return 0


def cmd_note(a):
    with Session.open(a.session) as s:
        if a.rm is not None:
            removed = s.notes.pop(a.rm)
            _out(f"removed: {removed}")
        elif a.text:
            s.notes.append(" ".join(a.text))
            _out("pinned.")
        for i, n in enumerate(s.notes):
            _out(f"{i}: {n}")
    return 0


def cmd_reset(a):
    with Session.open(a.session) as s:
        s.reset(keep_notes=not a.all)
    _out(f"session '{a.session}' reset" + (" (notes cleared too)" if a.all else " (notes kept)"))
    return 0


def cmd_mcp(a):
    from .mcp_server import serve
    serve()
    return 0


def main(argv=None):
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except AttributeError:
            pass

    ap = argparse.ArgumentParser(prog="deepseekharness",
                                 description="DeepSeek harness with persistent, auto-compacting sessions.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("ask", help="one-shot question (prompt args and/or stdin)")
    p.add_argument("prompt", nargs="*")
    _add_ask_opts(p)
    p.add_argument("--json", action="store_true", help="machine-readable output")
    p.add_argument("--no-stream", action="store_true")
    p.add_argument("--stateless", action="store_true", help="don't read or write session history")
    p.set_defaults(fn=cmd_ask)

    p = sub.add_parser("chat", help="interactive chat")
    _add_ask_opts(p)
    p.set_defaults(fn=cmd_chat)

    p = sub.add_parser("sessions", help="list sessions")
    p.add_argument("--json", action="store_true")
    p.set_defaults(fn=cmd_sessions)

    for name, fn, helptext in [("history", cmd_history, "show session history"),
                               ("summary", cmd_summary, "show compacted memory"),
                               ("compact", cmd_compact, "force compaction now"),
                               ("note", cmd_note, "pin / list / remove notes"),
                               ("reset", cmd_reset, "clear history and summary")]:
        p = sub.add_parser(name, help=helptext)
        p.add_argument("-s", "--session", default=config.DEFAULT_SESSION)
        p.set_defaults(fn=fn)
        if name == "history":
            p.add_argument("-n", type=int, default=0, help="last N messages only")
            p.add_argument("--json", action="store_true")
        elif name == "note":
            p.add_argument("text", nargs="*")
            p.add_argument("--rm", type=int, help="remove note by index")
        elif name == "reset":
            p.add_argument("--all", action="store_true", help="also clear pinned notes")

    p = sub.add_parser("mcp", help="run as an MCP server over stdio (for Claude Code etc.)")
    p.set_defaults(fn=cmd_mcp)

    a = ap.parse_args(argv)
    try:
        return a.fn(a)
    except (DeepSeekError, FileNotFoundError, TimeoutError, ValueError, IndexError) as e:
        _err(f"error: {e}")
        return 1
