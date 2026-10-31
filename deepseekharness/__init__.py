"""DeepSeek harness: CLI, Python API and MCP server with persistent, auto-compacting sessions.

    from deepseekharness import ask
    print(ask("Design a job queue", session="myproj", mode="architect")["content"])
"""

from .client import DeepSeekError, chat
from .session import Session, ask, list_sessions

__all__ = ["ask", "chat", "Session", "list_sessions", "DeepSeekError"]
