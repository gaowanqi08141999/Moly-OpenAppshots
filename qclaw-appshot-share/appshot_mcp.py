#!/usr/bin/env python3
"""
QClaw Appshot — MCP Server (Model Context Protocol)
Exposes 5 daemon tools via stdio JSON-RPC for OpenClaw, Claude Desktop, Cursor, etc.

Usage:
    python3 appshot_mcp.py

Zero external dependencies. Only requires the capture daemon running on :19876.
"""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

DAEMON_URL = os.environ.get("QCLAW_DAEMON_URL", "http://127.0.0.1:19876")


# ── Daemon HTTP client ──

def _daemon_request(method: str, path: str, timeout: int = 60) -> dict:
    url = f"{DAEMON_URL}{path}"
    req = urllib.request.Request(url, method=method)
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read())
    except urllib.error.URLError as e:
        return {"error": f"Daemon unreachable: {e.reason}"}
    except Exception as e:
        return {"error": str(e)}


# ── Tool handlers ──

def take_appshot(args: dict) -> str:
    pid = args.get("pid")
    path = "/capture"
    if pid:
        path += f"?pid={pid}"
    result = _daemon_request("POST", path, timeout=30)
    return json.dumps(result, ensure_ascii=False, indent=2)


def list_appshots(args: dict) -> str:
    params = []
    if args.get("app_name"):
        params.append(f"app={urllib.parse.quote(str(args['app_name']))}")
    if args.get("date_from"):
        params.append(f"from={urllib.parse.quote(str(args['date_from']))}")
    if args.get("date_to"):
        params.append(f"to={urllib.parse.quote(str(args['date_to']))}")
    limit = args.get("limit", 20)
    offset = args.get("offset", 0)
    params.append(f"limit={limit}")
    params.append(f"offset={offset}")

    path = "/snapshots"
    if params:
        path += "?" + "&".join(params)
    result = _daemon_request("GET", path)
    return json.dumps(result, ensure_ascii=False, indent=2)


def get_appshot(args: dict) -> str:
    snapshot_id = args.get("snapshot_id", "")
    if not snapshot_id:
        return json.dumps({"error": "snapshot_id required"}, ensure_ascii=False)

    include_image = args.get("include_image", False)
    include_ax_tree = args.get("include_ax_tree", False)
    image_max_width = args.get("image_max_width", 800)

    data = _daemon_request("GET", f"/snapshots/{urllib.parse.quote(snapshot_id)}")
    if "error" in data:
        return json.dumps(data, ensure_ascii=False, indent=2)

    output: dict = {}
    if "metadata" in data:
        output["metadata"] = data["metadata"]
    if "fullText" in data:
        output["full_text"] = data["fullText"]

    if include_ax_tree and "axTree" in data:
        output["accessibility_tree"] = data["axTree"]

    if include_image:
        img_data = _daemon_request(
            "GET",
            f"/screenshots/{urllib.parse.quote(snapshot_id)}?max_width={image_max_width}",
        )
        if "image_base64" in img_data:
            output["image_base64"] = img_data["image_base64"]
        elif "error" not in img_data:
            output["image_base64"] = img_data.get("imageBase64", "")

    return json.dumps(output, ensure_ascii=False, indent=2)


def search_appshots(args: dict) -> str:
    query = (args.get("query") or "").lower().strip()
    if not query:
        return json.dumps({"error": "query required"}, ensure_ascii=False)

    search_in = args.get("search_in", "all")
    result = _daemon_request("GET", "/snapshots?limit=500")
    items = result.get("items", [])

    matched = []
    for snap in items:
        if search_in in ("all", "app_name"):
            if query in (snap.get("appName") or "").lower():
                matched.append(snap)
                continue
        if search_in in ("all", "window_title"):
            if query in (snap.get("windowTitle") or "").lower():
                matched.append(snap)
                continue

    return json.dumps(
        {"query": query, "total": len(matched), "results": matched},
        ensure_ascii=False, indent=2,
    )


def delete_appshot(args: dict) -> str:
    snapshot_id = args.get("snapshot_id", "")
    if not snapshot_id:
        return json.dumps({"error": "snapshot_id required"}, ensure_ascii=False)

    result = _daemon_request("DELETE", f"/snapshots/{urllib.parse.quote(snapshot_id)}")
    return json.dumps(result, ensure_ascii=False, indent=2)


# ── MCP Tool definitions ──

TOOLS = [
    {
        "name": "take_appshot",
        "description": (
            "Capture the frontmost macOS window: screenshot + accessibility text tree.\n\n"
            "Use when user asks 'what's on my screen', 'analyze this page', "
            "'what does this error say', or needs visual context from any app.\n"
            "Note: captures current frontmost window. For capturing OTHER apps, "
            "advise user to press the hotkey (⌃⌥⌘Space) on the target window first, "
            "then use list_appshots + get_appshot to retrieve."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "list_appshots",
        "description": (
            "Browse historical snapshots with optional filters. "
            "Returns summaries (no full images or AX trees). "
            "Items are ordered by time (newest first). "
            "Use this to find snapshots captured via hotkey."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "app_name": {"type": "string", "description": "Filter by app name"},
                "date_from": {"type": "string", "description": "Start date YYYY-MM-DD"},
                "date_to": {"type": "string", "description": "End date YYYY-MM-DD"},
                "limit": {"type": "integer", "description": "Max results, default 20, max 100"},
                "offset": {"type": "integer", "description": "Pagination offset, default 0"},
            },
        },
    },
    {
        "name": "get_appshot",
        "description": (
            "Get full snapshot detail. By default returns metadata + fullText only (~2K tokens). "
            "Use include_image=true only when visual analysis is needed (~10K-155K tokens). "
            "Use include_ax_tree=true only for spatial/debug analysis (~40K tokens)."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "snapshot_id": {
                    "type": "string",
                    "description": "Snapshot ID from list_appshots or take_appshot"
                },
                "include_image": {
                    "type": "boolean",
                    "description": "Include resized base64 screenshot. Default false (saves tokens)."
                },
                "include_ax_tree": {
                    "type": "boolean",
                    "description": "Include full AX tree JSON. Default false (saves tokens)."
                },
                "image_max_width": {
                    "type": "integer",
                    "description": "Max image width in pixels, default 800. Lower = fewer tokens."
                },
            },
            "required": ["snapshot_id"],
        },
    },
    {
        "name": "search_appshots",
        "description": "Full-text search across snapshot app names and window titles.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Search keyword"},
                "search_in": {
                    "type": "string",
                    "enum": ["all", "app_name", "window_title"],
                    "description": "Where to search, default 'all'",
                },
            },
            "required": ["query"],
        },
    },
    {
        "name": "delete_appshot",
        "description": "Delete a snapshot and all associated files. Irreversible.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "snapshot_id": {"type": "string", "description": "Snapshot ID to delete"},
            },
            "required": ["snapshot_id"],
        },
    },
]

TOOL_MAP = {
    "take_appshot": take_appshot,
    "list_appshots": list_appshots,
    "get_appshot": get_appshot,
    "search_appshots": search_appshots,
    "delete_appshot": delete_appshot,
}


# ── MCP Protocol handlers ──

def handle_initialize(msg_id):
    return {
        "jsonrpc": "2.0",
        "id": msg_id,
        "result": {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "serverInfo": {
                "name": "qclaw-appshot-mcp",
                "version": "1.0.0",
            },
        },
    }


def handle_tools_list(msg_id):
    return {
        "jsonrpc": "2.0",
        "id": msg_id,
        "result": {"tools": TOOLS},
    }


def handle_tools_call(msg_id, params: dict):
    name = params.get("name", "")
    arguments = params.get("arguments", {})

    handler = TOOL_MAP.get(name)
    if not handler:
        return {
            "jsonrpc": "2.0",
            "id": msg_id,
            "error": {"code": -32601, "message": f"Unknown tool: {name}"},
        }

    try:
        result_text = handler(arguments)
        return {
            "jsonrpc": "2.0",
            "id": msg_id,
            "result": {
                "content": [{"type": "text", "text": result_text}],
            },
        }
    except Exception as e:
        return {
            "jsonrpc": "2.0",
            "id": msg_id,
            "error": {"code": -32603, "message": str(e)},
        }


# ── Main loop ──

def main():
    print("QClaw Appshot MCP Server started", file=sys.stderr)
    print(f"Connecting to daemon at {DAEMON_URL}", file=sys.stderr)

    while True:
        try:
            line = sys.stdin.readline()
            if not line:
                break

            line = line.strip()
            if not line:
                continue

            msg = json.loads(line)
            msg_id = msg.get("id")
            method = msg.get("method", "")
            params = msg.get("params", {})

            if method == "initialize":
                response = handle_initialize(msg_id)
            elif method == "tools/list":
                response = handle_tools_list(msg_id)
            elif method == "tools/call":
                response = handle_tools_call(msg_id, params)
            else:
                response = {
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "error": {"code": -32601, "message": f"Method not found: {method}"},
                }

            print(json.dumps(response), flush=True)

        except json.JSONDecodeError:
            continue
        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)
            continue


if __name__ == "__main__":
    main()
