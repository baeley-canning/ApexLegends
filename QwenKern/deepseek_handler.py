#!/usr/bin/env python3
"""
DeepSeek handler: the only thing allowed to talk to the DeepSeek API.

Usage:
    python deepseek_handler.py request.json
    cat request.json | python deepseek_handler.py -

Request JSON:
    {
      "kind": "code" | "component_design" | "review" | "tests",
      "language": "python",
      "task": "self-contained description of one isolated piece of work",
      "constraints": ["optional", "list"],
      "snippets": ["optional small code excerpts"]
    }

Reply JSON (stdout):
    {"ok": true, "code_blocks": [...], "notes": "...", "flags": [...], "usage": {...}}
    {"ok": false, "blocked": ["reason", ...]}

Standard library only. The API key is read from deepseek.env or the
DEEPSEEK_API_KEY environment variable, and is never shown to the caller.
"""

import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ENV_FILE = os.path.join(HERE, "deepseek.env")
REDACTION_FILE = os.path.join(HERE, "redaction_list.txt")
AUDIT_LOG = os.path.join(HERE, "deepseek_audit.log")

API_URL = "https://api.deepseek.com/chat/completions"
MODEL_CODE = "deepseek-chat"
MODEL_REASONING = "deepseek-reasoner"

MAX_TASK_CHARS = 4000
MAX_SNIPPET_CHARS = 6000
MAX_SNIPPETS = 4
MIN_SECONDS_BETWEEN_CALLS = 2

VALID_KINDS = {"code", "component_design", "review", "tests"}

SYSTEM_PROMPT = (
    "You are a contract software engineer. You are given one isolated, self-contained "
    "task. You do not know what larger system it belongs to and you must not ask. "
    "Do not request more context. Make reasonable assumptions and state them briefly. "
    "Return clean, well-structured, production-quality code in fenced code blocks, "
    "with a short note outside the code blocks listing assumptions and any edge cases. "
    "Do not include network calls, shell execution, telemetry, or extra dependencies "
    "unless the task explicitly requires them."
)

KIND_INSTRUCTIONS = {
    "code": "Implement the following.",
    "component_design": (
        "Design the internals of the following component: structure, data types, "
        "function signatures and key algorithms. Include concise reference code."
    ),
    "review": "Review the following code for bugs, edge cases and quality. Provide fixes.",
    "tests": "Write thorough unit tests for the following.",
}

# Patterns that must never leave the machine.
SECRET_PATTERNS = [
    (r"sk-[A-Za-z0-9]{16,}", "looks like an API key (sk-...)"),
    (r"AKIA[0-9A-Z]{16}", "looks like an AWS access key"),
    (r"-----BEGIN [A-Z ]*PRIVATE KEY-----", "contains a private key"),
    (r"(?i)\b(api[_-]?key|secret|token|passwd|password|bearer)\b\s*[:=]\s*\S{6,}",
     "contains a credential assignment"),
    (r"(?i)\b(postgres|mysql|mongodb|redis|amqp)://\S+", "contains a connection string"),
    (r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", "contains an email address"),
    (r"\b(?:\d{1,3}\.){3}\d{1,3}\b", "contains an IP address"),
    (r"(?i)(/home/|/users/|c:\\users\\)[^\s/\\]+", "contains a local user path"),
    (r"\b[A-Za-z0-9+/]{80,}={0,2}\b", "contains a long encoded blob"),
]

# Flags raised on DeepSeek's output for the orchestrator to review.
OUTPUT_FLAGS = [
    (r"\b(eval|exec)\s*\(", "uses eval/exec"),
    (r"\b(os\.system|subprocess\.|Popen|child_process|Runtime\.getRuntime)", "runs shell commands"),
    (r"https?://[^\s\"')]+", "contains a hard-coded URL"),
    (r"\b(requests\.|urllib|httpx|aiohttp|fetch\(|XMLHttpRequest|socket\.)", "makes network calls"),
    (r"\b(shutil\.rmtree|os\.remove|os\.unlink|rm\s+-rf|Remove-Item)", "deletes files"),
    (r"(?m)^\s*(pip install|npm install|apt(-get)? install|curl |wget )", "installs or downloads something"),
    (r"\b(base64\.b64decode|atob\()", "decodes encoded data"),
    (r"[A-Za-z0-9+/]{60,}={0,2}", "contains a long encoded blob"),
    (r"(?i)\b(import|require|using)\b.*\b(ctypes|winreg|pty)\b", "uses low-level system modules"),
]


def load_key():
    key = os.environ.get("DEEPSEEK_API_KEY", "").strip()
    if key:
        return key
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line.startswith("DEEPSEEK_API_KEY="):
                    return line.split("=", 1)[1].strip().strip('"').strip("'")
    return ""


def load_redactions():
    terms = []
    if os.path.exists(REDACTION_FILE):
        with open(REDACTION_FILE, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    terms.append(line)
    return terms


def sanitize(req):
    """Return a list of reasons the request must be blocked (empty means clean)."""
    problems = []

    kind = req.get("kind")
    if kind not in VALID_KINDS:
        problems.append("kind must be one of: " + ", ".join(sorted(VALID_KINDS)))

    task = req.get("task", "")
    if not isinstance(task, str) or not task.strip():
        problems.append("task is missing or empty")
        task = ""
    if len(task) > MAX_TASK_CHARS:
        problems.append("task is longer than %d characters; split it into smaller pieces" % MAX_TASK_CHARS)

    snippets = req.get("snippets", []) or []
    if not isinstance(snippets, list):
        problems.append("snippets must be a list of strings")
        snippets = []
    if len(snippets) > MAX_SNIPPETS:
        problems.append("too many snippets (max %d); send only what is essential" % MAX_SNIPPETS)
    if sum(len(str(s)) for s in snippets) > MAX_SNIPPET_CHARS:
        problems.append("snippets total more than %d characters; this looks like too much of the project" % MAX_SNIPPET_CHARS)

    constraints = req.get("constraints", []) or []
    if not isinstance(constraints, list):
        problems.append("constraints must be a list of strings")
        constraints = []

    haystack = "\n".join([task, req.get("language", "")] + [str(c) for c in constraints] + [str(s) for s in snippets])

    for pattern, reason in SECRET_PATTERNS:
        if re.search(pattern, haystack):
            problems.append("blocked: " + reason)

    lowered = haystack.lower()
    for term in load_redactions():
        if term.lower() in lowered:
            problems.append("blocked: contains a protected term from the redaction list")
            break  # do not echo which term, to avoid leaking it into logs or replies

    return problems


def build_prompt(req):
    parts = [KIND_INSTRUCTIONS[req["kind"]]]
    if req.get("language"):
        parts.append("Language: " + req["language"])
    parts.append("Task:\n" + req["task"].strip())
    if req.get("constraints"):
        parts.append("Constraints:\n" + "\n".join("- " + str(c) for c in req["constraints"]))
    if req.get("snippets"):
        for i, s in enumerate(req["snippets"], 1):
            parts.append("Snippet %d:\n```\n%s\n```" % (i, s))
    return "\n\n".join(parts)


def call_deepseek(prompt, kind, key):
    model = MODEL_REASONING if kind == "component_design" else MODEL_CODE
    body = {
        "model": model,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt},
        ],
        "stream": False,
    }
    if model == MODEL_CODE:
        body["temperature"] = 0.2
    data = json.dumps(body).encode("utf-8")
    http_req = urllib.request.Request(
        API_URL,
        data=data,
        headers={"Content-Type": "application/json", "Authorization": "Bearer " + key},
        method="POST",
    )
    with urllib.request.urlopen(http_req, timeout=300) as resp:
        return json.loads(resp.read().decode("utf-8")), model


def parse_output(text):
    blocks = []
    for m in re.finditer(r"```([\w+#.-]*)\n(.*?)```", text, re.DOTALL):
        blocks.append({"language": m.group(1) or "text", "code": m.group(2).rstrip()})
    notes = re.sub(r"```[\w+#.-]*\n.*?```", "[code block]", text, flags=re.DOTALL).strip()
    flags = []
    for pattern, reason in OUTPUT_FLAGS:
        if re.search(pattern, text):
            flags.append(reason)
    return blocks, notes, sorted(set(flags))


def audit(entry):
    entry["time"] = time.strftime("%Y-%m-%d %H:%M:%S")
    try:
        with open(AUDIT_LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError:
        pass


def rate_limit():
    stamp = os.path.join(HERE, ".last_call")
    try:
        if os.path.exists(stamp):
            elapsed = time.time() - os.path.getmtime(stamp)
            if elapsed < MIN_SECONDS_BETWEEN_CALLS:
                time.sleep(MIN_SECONDS_BETWEEN_CALLS - elapsed)
        with open(stamp, "w") as f:
            f.write(str(time.time()))
    except OSError:
        pass


def delegate(req):
    problems = sanitize(req)
    if problems:
        audit({"event": "blocked", "reasons": problems})
        return {"ok": False, "blocked": problems}

    key = load_key()
    if not key:
        return {"ok": False, "blocked": ["no API key configured; the user must add it to deepseek.env"]}

    prompt = build_prompt(req)
    req_hash = hashlib.sha256(prompt.encode("utf-8")).hexdigest()[:12]
    rate_limit()

    try:
        result, model = call_deepseek(prompt, req["kind"], key)
    except urllib.error.HTTPError as e:
        audit({"event": "http_error", "status": e.code, "hash": req_hash})
        return {"ok": False, "blocked": ["DeepSeek API returned HTTP %d" % e.code]}
    except Exception as e:  # network, timeout, bad JSON
        audit({"event": "error", "error": type(e).__name__, "hash": req_hash})
        return {"ok": False, "blocked": ["request failed: " + type(e).__name__]}

    try:
        text = result["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError):
        audit({"event": "bad_response", "hash": req_hash})
        return {"ok": False, "blocked": ["unexpected response format from DeepSeek"]}

    blocks, notes, flags = parse_output(text)
    audit({
        "event": "ok",
        "hash": req_hash,
        "model": model,
        "kind": req["kind"],
        "sent": prompt,
        "flags": flags,
        "usage": result.get("usage", {}),
    })
    return {
        "ok": True,
        "code_blocks": blocks,
        "notes": notes,
        "flags": flags,
        "usage": result.get("usage", {}),
    }


def main():
    if len(sys.argv) != 2:
        print(json.dumps({"ok": False, "blocked": ["usage: deepseek_handler.py request.json (or - for stdin)"]}))
        sys.exit(1)
    src = sys.argv[1]
    try:
        raw = sys.stdin.read() if src == "-" else open(src, "r", encoding="utf-8").read()
        req = json.loads(raw)
    except Exception:
        print(json.dumps({"ok": False, "blocked": ["request is not valid JSON"]}))
        sys.exit(1)
    print(json.dumps(delegate(req), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
