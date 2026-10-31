"""Settings. Everything can be overridden by env vars or deepseekharness/.env."""

import os
import pathlib

HOME = pathlib.Path(__file__).resolve().parent


def _load_dotenv():
    env = HOME / ".env"
    if not env.exists():
        return
    for line in env.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        os.environ.setdefault(key.strip(), val.strip().strip("\"'"))


_load_dotenv()


def _int(name, default):
    return int(os.environ.get(name, default))


API_KEY = os.environ.get("DEEPSEEK_API_KEY", "")
BASE_URL = os.environ.get("DEEPSEEK_BASE_URL", "https://api.deepseek.com").rstrip("/")
MODEL = os.environ.get("DEEPSEEK_MODEL", "deepseek-v4-flash")
# V4 models are hybrid: thinking is a request flag, not a separate model.
# The API defaults thinking ON; the harness defaults it off unless asked (--reason).
THINKING = os.environ.get("DEEPSEEK_THINKING", "off").lower() in ("1", "on", "true", "yes")
EFFORT = os.environ.get("DEEPSEEK_EFFORT", "high")  # low | high | max

SESSIONS_DIR = pathlib.Path(os.environ.get("DEEPSEEK_SESSIONS_DIR", HOME / "sessions"))
DEFAULT_SESSION = os.environ.get("DEEPSEEK_SESSION", "default")

# Compaction: when history + summary exceeds COMPACT_AT tokens (estimated),
# everything except the most recent KEEP_RECENT tokens is folded into the summary.
COMPACT_AT = _int("DEEPSEEK_COMPACT_AT", 100_000)
KEEP_RECENT = _int("DEEPSEEK_KEEP_RECENT", 20_000)
SUMMARY_CHUNK = _int("DEEPSEEK_SUMMARY_CHUNK", 30_000)

MAX_TOKENS = _int("DEEPSEEK_MAX_TOKENS", 8192)
MAX_FILE_CHARS = _int("DEEPSEEK_MAX_FILE_CHARS", 200_000)
TIMEOUT = _int("DEEPSEEK_TIMEOUT", 600)
