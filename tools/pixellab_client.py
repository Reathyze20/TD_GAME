"""Mini MCP klient pro PixelLab (streamable HTTP).

Proc existuje: MCP server je v ~/.claude.json zapsany pod projektovym klicem
'C:/Users/reath/Projects/TD Project' (velke C), zatimco session bezi na 'c:\\...',
takze se do session nenacte. Primy JSON-RPC je fallback dokumentovany v ART_PIPELINE.md 3.

Token se cte z promenne prostredi PIXELLAB_TOKEN — do repa nepatri:
    $env:PIXELLAB_TOKEN = "..."      # PowerShell
    export PIXELLAB_TOKEN=...        # bash
"""
import json
import os
import sys
import urllib.error
import urllib.request

URL = "https://api.pixellab.ai/mcp"

_session = {"id": None, "n": 0}


def _token():
    t = os.environ.get("PIXELLAB_TOKEN")
    if not t:
        raise RuntimeError("chybi PIXELLAB_TOKEN v promennych prostredi")
    return t


def _post(payload, extra_headers=None):
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
        "Authorization": "Bearer " + _token(),
    }
    if _session["id"]:
        headers["Mcp-Session-Id"] = _session["id"]
    if extra_headers:
        headers.update(extra_headers)
    req = urllib.request.Request(URL, data=json.dumps(payload).encode(),
                                 headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            sid = r.headers.get("Mcp-Session-Id")
            if sid:
                _session["id"] = sid
            raw = r.read().decode("utf-8", "replace")
            ctype = r.headers.get("Content-Type", "")
    except urllib.error.HTTPError as e:
        return {"_http_error": e.code, "_body": e.read().decode("utf-8", "replace")[:2000]}
    if "text/event-stream" in ctype:
        # SSE: posbirej data: radky, vrat posledni JSON objekt
        out = None
        for line in raw.splitlines():
            if line.startswith("data:"):
                chunk = line[5:].strip()
                if chunk:
                    try:
                        out = json.loads(chunk)
                    except json.JSONDecodeError:
                        pass
        return out if out is not None else {"_raw": raw[:2000]}
    if not raw.strip():
        return {"_empty": True}
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {"_raw": raw[:2000]}


def _rpc(method, params=None):
    _session["n"] += 1
    payload = {"jsonrpc": "2.0", "id": _session["n"], "method": method}
    if params is not None:
        payload["params"] = params
    return _post(payload)


def init():
    r = _rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                            "clientInfo": {"name": "td-project-cli", "version": "1.0"}})
    _post({"jsonrpc": "2.0", "method": "notifications/initialized"})
    return r


def tools():
    return _rpc("tools/list")


def call(name, args):
    return _rpc("tools/call", {"name": name, "arguments": args})


def text_of(resp):
    """Vytahne textovy obsah z tools/call odpovedi."""
    try:
        parts = resp["result"]["content"]
    except (KeyError, TypeError):
        return json.dumps(resp)[:4000]
    return "\n".join(p.get("text", "") if p.get("type") == "text"
                     else "<" + p.get("type", "?") + ">" for p in parts)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    init()
    cmd = sys.argv[1] if len(sys.argv) > 1 else "tools"
    if cmd == "tools":
        for t in tools().get("result", {}).get("tools", []):
            print("-", t["name"], "|", (t.get("description") or "")[:110].replace("\n", " "))
    else:
        print(text_of(call(cmd, json.loads(sys.argv[2]) if len(sys.argv) > 2 else {})))
