"""Minimal DeepSeek (OpenAI-compatible) chat client using only the stdlib."""

import json
import time
import urllib.error
import urllib.request

from . import config

RETRY_CODES = {429, 500, 502, 503, 504}


class DeepSeekError(RuntimeError):
    pass


def chat(messages, model=None, temperature=None, max_tokens=None, thinking=None, effort=None,
         stream=False, on_token=None, on_reasoning=None, json_mode=False):
    """Send messages, return {"content", "reasoning", "usage", "model"}.

    thinking: True/False toggles V4 thinking mode (None leaves the API default).
    effort: "low" | "high" | "max", used when thinking.
    With stream=True, on_token / on_reasoning are called with each text delta.
    """
    if not config.API_KEY:
        raise DeepSeekError(
            "DEEPSEEK_API_KEY is not set. Set the env var or put it in deepseekharness/.env")

    model = model or config.MODEL
    body = {
        "model": model,
        "messages": messages,
        "max_tokens": max_tokens or config.MAX_TOKENS,
        "stream": stream,
    }
    if stream:
        body["stream_options"] = {"include_usage": True}
    if thinking is not None:
        body["thinking"] = {"type": "enabled" if thinking else "disabled"}
        if thinking:
            body["reasoning_effort"] = effort or config.EFFORT
    if temperature is not None and thinking is False:  # ignored in thinking mode
        body["temperature"] = temperature
    if json_mode:
        body["response_format"] = {"type": "json_object"}

    req = urllib.request.Request(
        f"{config.BASE_URL}/chat/completions",
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {config.API_KEY}",
            "Content-Type": "application/json",
            "Accept": "text/event-stream" if stream else "application/json",
        },
        method="POST",
    )

    for attempt in range(5):
        try:
            resp = urllib.request.urlopen(req, timeout=config.TIMEOUT)
            break
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", "replace")
            if e.code in RETRY_CODES and attempt < 4:
                time.sleep(2 ** attempt)
                continue
            raise DeepSeekError(f"HTTP {e.code}: {detail}") from None
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            if attempt < 4:
                time.sleep(2 ** attempt)
                continue
            raise DeepSeekError(f"Connection failed: {e}") from None

    with resp:
        if not stream:
            payload = json.load(resp)
            msg = payload["choices"][0]["message"]
            return {
                "content": msg.get("content") or "",
                "reasoning": msg.get("reasoning_content") or "",
                "usage": payload.get("usage", {}),
                "model": payload.get("model", model),
            }
        return _read_stream(resp, model, on_token, on_reasoning)


def _read_stream(resp, model, on_token, on_reasoning):
    content, reasoning, usage = [], [], {}
    for raw in resp:
        line = raw.decode("utf-8", "replace").strip()
        if not line.startswith("data:"):
            continue  # blank lines and ": keep-alive" comments
        data = line[5:].strip()
        if data == "[DONE]":
            break
        chunk = json.loads(data)
        if chunk.get("usage"):
            usage = chunk["usage"]
        for choice in chunk.get("choices", []):
            delta = choice.get("delta", {})
            if delta.get("reasoning_content"):
                reasoning.append(delta["reasoning_content"])
                if on_reasoning:
                    on_reasoning(delta["reasoning_content"])
            if delta.get("content"):
                content.append(delta["content"])
                if on_token:
                    on_token(delta["content"])
    return {"content": "".join(content), "reasoning": "".join(reasoning),
            "usage": usage, "model": model}
