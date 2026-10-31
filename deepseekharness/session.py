"""Persistent sessions with automatic compaction.

A session is one JSON file in SESSIONS_DIR:
  summary   running memory of everything that was compacted away
  notes     pinned facts, never compacted
  messages  recent turns kept verbatim
A lock file serialises access, so several agents can share a session safely.
"""

import contextlib
import json
import os
import pathlib
import re
import time
from datetime import datetime

from . import client, config, prompts

STALE_LOCK_SECS = 30 * 60


def estimate_tokens(text):
    # ~3.5 chars/token is a conservative average for mixed prose and code.
    return int(len(text) / 3.5) + 1


def _now():
    return datetime.now().isoformat(timespec="seconds")


def _safe_name(name):
    name = re.sub(r"[^A-Za-z0-9_.-]+", "_", name.strip()) or config.DEFAULT_SESSION
    return name[:80]


def session_path(name):
    return config.SESSIONS_DIR / f"{_safe_name(name)}.json"


def list_sessions():
    config.SESSIONS_DIR.mkdir(parents=True, exist_ok=True)
    out = []
    for p in sorted(config.SESSIONS_DIR.glob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True):
        try:
            d = json.loads(p.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        out.append({
            "name": p.stem,
            "updated": d.get("updated"),
            "messages": len(d.get("messages", [])),
            "compactions": d.get("compactions", 0),
            "notes": len(d.get("notes", [])),
            "tokens": Session(p.stem, d).context_tokens(),
        })
    return out


@contextlib.contextmanager
def _file_lock(path, timeout=900):
    lock = path.with_suffix(".lock")
    start = time.time()
    while True:
        try:
            fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.write(fd, str(os.getpid()).encode())
            os.close(fd)
            break
        except FileExistsError:
            try:
                if time.time() - lock.stat().st_mtime > STALE_LOCK_SECS:
                    lock.unlink()
                    continue
            except FileNotFoundError:
                continue
            if time.time() - start > timeout:
                raise TimeoutError(f"session {path.stem!r} is busy (lock: {lock})")
            time.sleep(0.3)
    try:
        yield
    finally:
        with contextlib.suppress(FileNotFoundError):
            lock.unlink()


def _atomic_write(path, text):
    tmp = path.with_suffix(".tmp")
    tmp.write_text(text, encoding="utf-8")
    for attempt in range(10):  # OneDrive/AV can briefly hold the target open
        try:
            os.replace(tmp, path)
            return
        except PermissionError:
            if attempt == 9:
                raise
            time.sleep(0.2)


class Session:
    def __init__(self, name, data=None):
        self.name = _safe_name(name)
        self.path = session_path(self.name)
        self.data = data or {
            "name": self.name, "created": _now(), "updated": _now(),
            "summary": "", "notes": [], "messages": [],
            "compactions": 0, "usage": {"prompt_tokens": 0, "completion_tokens": 0},
        }

    # ---- persistence -------------------------------------------------------

    @classmethod
    @contextlib.contextmanager
    def open(cls, name, save=True):
        """Lock, load, yield, and save the session."""
        config.SESSIONS_DIR.mkdir(parents=True, exist_ok=True)
        path = session_path(name)
        with _file_lock(path):
            data = json.loads(path.read_text(encoding="utf-8")) if path.exists() else None
            s = cls(name, data)
            yield s
            if save:
                s.save()

    @classmethod
    def peek(cls, name):
        """Read without locking (for display only)."""
        path = session_path(name)
        data = json.loads(path.read_text(encoding="utf-8")) if path.exists() else None
        return cls(name, data)

    def save(self):
        self.data["updated"] = _now()
        _atomic_write(self.path, json.dumps(self.data, indent=1, ensure_ascii=False))

    # ---- accessors ---------------------------------------------------------

    @property
    def messages(self):
        return self.data["messages"]

    @property
    def summary(self):
        return self.data["summary"]

    @property
    def notes(self):
        return self.data["notes"]

    def context_tokens(self):
        text = self.summary + "".join(self.notes) + "".join(m["content"] for m in self.messages)
        return estimate_tokens(text)

    def build_messages(self, mode, user_content):
        msgs = [{"role": "system", "content": prompts.system_prompt(mode, self.notes, self.summary)}]
        msgs += [{"role": m["role"], "content": m["content"]} for m in self.messages]
        msgs.append({"role": "user", "content": user_content})
        return msgs

    def record(self, user_content, reply, sender=None, mode=None, usage=None):
        self.messages.append({"role": "user", "content": user_content, "ts": _now(),
                              "from": sender, "mode": mode})
        self.messages.append({"role": "assistant", "content": reply, "ts": _now()})
        for k in ("prompt_tokens", "completion_tokens"):
            self.data["usage"][k] = self.data["usage"].get(k, 0) + (usage or {}).get(k, 0)

    def reset(self, keep_notes=True):
        self.data["summary"] = ""
        self.data["messages"] = []
        self.data["compactions"] = 0
        if not keep_notes:
            self.data["notes"] = []

    # ---- compaction --------------------------------------------------------

    def needs_compaction(self, incoming_tokens=0):
        return self.context_tokens() + incoming_tokens > config.COMPACT_AT

    def compact(self, force=False, incoming_tokens=0):
        """Fold older messages into the summary. Returns True if anything was compacted."""
        if not force and not self.needs_compaction(incoming_tokens):
            return False

        # Keep the newest messages verbatim, up to KEEP_RECENT tokens, starting on a user turn.
        keep_from, budget = len(self.messages), config.KEEP_RECENT
        for i in range(len(self.messages) - 1, -1, -1):
            budget -= estimate_tokens(self.messages[i]["content"])
            if budget < 0:
                break
            keep_from = i
        while keep_from < len(self.messages) and self.messages[keep_from]["role"] != "user":
            keep_from += 1
        if force and keep_from == 0:
            keep_from = len(self.messages)  # everything fits, but compaction was forced
        old, recent = self.messages[:keep_from], self.messages[keep_from:]
        if not old:
            return False

        summary = self.summary
        for chunk in _chunk_transcript(old, config.SUMMARY_CHUNK):
            summary = _summarise(summary, chunk)

        self.data["summary"] = summary
        self.data["messages"] = recent
        self.data["compactions"] += 1
        return True


def _format_turn(m):
    who = m["role"].upper()
    if m.get("from"):
        who += f" (from {m['from']})"
    return f"### {who}\n{m['content']}"


def _chunk_transcript(messages, max_tokens):
    chunk, size = [], 0
    max_chars = int(max_tokens * 3.5)
    for m in messages:
        text = _format_turn(m)
        if len(text) > max_chars:  # one giant message: keep head and tail
            half = max_chars // 2
            text = text[:half] + "\n\n[... middle truncated for summarisation ...]\n\n" + text[-half:]
        t = estimate_tokens(text)
        if chunk and size + t > max_tokens:
            yield "\n\n".join(chunk)
            chunk, size = [], 0
        chunk.append(text)
        size += t
    if chunk:
        yield "\n\n".join(chunk)


def _summarise(existing, transcript):
    r = client.chat([
        {"role": "system", "content": prompts.COMPACT_SYSTEM},
        {"role": "user", "content":
            f"EXISTING SUMMARY:\n{existing or '(none yet)'}\n\nNEW TRANSCRIPT:\n{transcript}\n\n"
            "Write the updated summary now."},
    ], model=config.MODEL, thinking=False, temperature=0.2, max_tokens=4096)
    return r["content"].strip()


# ---- high-level entry point used by the CLI and MCP server ---------------------

def read_files(paths):
    blocks = []
    for p in paths or ():
        path = pathlib.Path(p).expanduser()
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError as e:
            raise FileNotFoundError(f"cannot read {p}: {e}") from None
        if len(text) > config.MAX_FILE_CHARS:
            text = text[:config.MAX_FILE_CHARS] + f"\n[... truncated at {config.MAX_FILE_CHARS} chars ...]"
        blocks.append(f'<file path="{path}">\n{text}\n</file>')
    return blocks


def ask(prompt, session=None, mode="chat", files=(), reason=None, effort=None, model=None,
        stateless=False, sender=None, temperature=None, on_token=None, on_reasoning=None):
    """Ask DeepSeek. Returns dict with content, reasoning, usage, model, session, compacted.

    reason: enable thinking mode (None -> DEEPSEEK_THINKING). effort: low | high | max.
    """
    parts = read_files(files)
    parts.append(prompt)
    content = "\n\n".join(p for p in parts if p)
    if sender:
        content = f"[from: {sender}] {content}"
    thinking = config.THINKING if reason is None else bool(reason)
    stream = on_token is not None or on_reasoning is not None
    kwargs = dict(model=model or config.MODEL, thinking=thinking, effort=effort,
                  temperature=temperature, stream=stream,
                  on_token=on_token, on_reasoning=on_reasoning)

    if stateless:
        msgs = [{"role": "system", "content": prompts.system_prompt(mode, [], "")},
                {"role": "user", "content": content}]
        r = client.chat(msgs, **kwargs)
        return {**r, "session": None, "compacted": False}

    with Session.open(session or config.DEFAULT_SESSION) as s:
        compacted = s.compact(incoming_tokens=estimate_tokens(content))
        r = client.chat(s.build_messages(mode, content), **kwargs)
        s.record(content, r["content"], sender=sender, mode=mode, usage=r["usage"])
        return {**r, "session": s.name, "compacted": compacted,
                "context_tokens": s.context_tokens()}
