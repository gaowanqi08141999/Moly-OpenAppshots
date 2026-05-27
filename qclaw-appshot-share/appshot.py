"""
Hermes Agent tool registration — QClaw Appshots.
Direct HTTP calls to the capture daemon (127.0.0.1:19876).
Zero MCP dependency.
"""

import json
import os
import platform
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

from tools.registry import registry

DAEMON_URL = os.environ.get("QCLAW_DAEMON_URL", "http://127.0.0.1:19876")


def _check_macos_environment() -> bool:
    """Only available on macOS with the capture daemon running."""
    if platform.system() != "Darwin":
        return False
    try:
        with urllib.request.urlopen(f"{DAEMON_URL}/health", timeout=2) as resp:
            return json.loads(resp.read()).get("status") == "ok"
    except Exception:
        return False


def _daemon_request(method: str, path: str, timeout: int = 60) -> dict:
    """Make an HTTP request to the capture daemon and return parsed JSON."""
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


def take_appshot(args: dict, **kwargs) -> str:
    """Capture the current frontmost macOS window."""
    # Support PID-aware capture if caller provides it
    pid = args.get("pid")
    path = "/capture"
    if pid:
        path += f"?pid={pid}"
    result = _daemon_request("POST", path, timeout=30)
    return json.dumps(result, ensure_ascii=False, indent=2)


def list_appshots(args: dict, **kwargs) -> str:
    """List historical snapshots with optional filters."""
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


def get_appshot(args: dict, **kwargs) -> str:
    """Get full snapshot detail. Image and AX tree are OFF by default to save tokens."""
    snapshot_id = args.get("snapshot_id", "")
    if not snapshot_id:
        return json.dumps({"error": "snapshot_id required"}, ensure_ascii=False)

    include_image = args.get("include_image", False)
    include_ax_tree = args.get("include_ax_tree", False)
    image_max_width = args.get("image_max_width", 800)

    # Fetch metadata + fullText (always lightweight, ~2K tokens)
    data = _daemon_request("GET", f"/snapshots/{urllib.parse.quote(snapshot_id)}")
    if "error" in data:
        return json.dumps(data, ensure_ascii=False, indent=2)

    output: dict[str, Any] = {}
    if "metadata" in data:
        output["metadata"] = data["metadata"]
    if "fullText" in data:
        output["full_text"] = data["fullText"]

    # axTree — only when explicitly requested (~40K tokens)
    if include_ax_tree and "axTree" in data:
        output["accessibility_tree"] = data["axTree"]

    # Image — fetch resized version from dedicated endpoint (saves 90%+ tokens)
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


def search_appshots(args: dict, **kwargs) -> str:
    """Full-text search across snapshot metadata (client-side filter)."""
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


def delete_appshot(args: dict, **kwargs) -> str:
    """Delete a snapshot by ID."""
    snapshot_id = args.get("snapshot_id", "")
    if not snapshot_id:
        return json.dumps({"error": "snapshot_id required"}, ensure_ascii=False)

    result = _daemon_request("DELETE", f"/snapshots/{urllib.parse.quote(snapshot_id)}")
    return json.dumps(result, ensure_ascii=False, indent=2)


# ── Register all 5 tools ──

registry.register(
    name="take_appshot",
    toolset="appshot",
    schema={
        "name": "take_appshot",
        "description": (
            "Capture the frontmost macOS window: screenshot + accessibility text tree.\n\n"
            "Captures:\n"
            "1. High-fidelity PNG screenshot of the active window\n"
            "2. Structured Accessibility Tree — role, text, position for every UI element\n"
            "3. Metadata — app name, window title, timestamp\n\n"
            "Use when: user asks 'what's on my screen', 'analyze this page', "
            "'what does this error say', or needs visual context from any app.\n"
            "Note: captures current frontmost window. For capturing OTHER apps, "
            "advise user to press the hotkey (⌃⌥⌘Space) on the target window first, "
            "then use list_appshots + get_appshot to retrieve."
        ),
        "parameters": {"type": "object", "properties": {}, "required": []},
    },
    handler=take_appshot,
    check_fn=_check_macos_environment,
    is_async=False,
    emoji="📸",
    description="Capture screenshot and accessibility text of the frontmost macOS window",
    max_result_size_chars=8000,
)

registry.register(
    name="list_appshots",
    toolset="appshot",
    schema={
        "name": "list_appshots",
        "description": (
            "Browse historical snapshots with optional filters. "
            "Returns summaries (no full images or AX trees). "
            "Items are ordered by time (newest first). "
            "Use this to find snapshots captured via hotkey."
        ),
        "parameters": {
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
    handler=list_appshots,
    check_fn=_check_macos_environment,
    is_async=False,
    emoji="📋",
    description="Browse historical snapshot list",
)

registry.register(
    name="get_appshot",
    toolset="appshot",
    schema={
        "name": "get_appshot",
        "description": (
            "Get full snapshot detail. By default returns metadata + fullText only (~2K tokens). "
            "Use include_image=true only when visual analysis is needed (~10K-155K tokens depending on width). "
            "Use include_ax_tree=true only for spatial/debug analysis (~40K tokens)."
        ),
        "parameters": {
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
    handler=get_appshot,
    check_fn=_check_macos_environment,
    is_async=False,
    emoji="🔍",
    description="Get full detail for a single snapshot",
    max_result_size_chars=200000,
)

registry.register(
    name="search_appshots",
    toolset="appshot",
    schema={
        "name": "search_appshots",
        "description": "Full-text search across snapshot app names and window titles.",
        "parameters": {
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
    handler=search_appshots,
    check_fn=_check_macos_environment,
    is_async=False,
    emoji="🔎",
    description="Search historical snapshots by keyword",
)

registry.register(
    name="delete_appshot",
    toolset="appshot",
    schema={
        "name": "delete_appshot",
        "description": "Delete a snapshot and all associated files. Irreversible.",
        "parameters": {
            "type": "object",
            "properties": {
                "snapshot_id": {"type": "string", "description": "Snapshot ID to delete"},
            },
            "required": ["snapshot_id"],
        },
    },
    handler=delete_appshot,
    check_fn=_check_macos_environment,
    is_async=False,
    emoji="🗑️",
    description="Delete a snapshot permanently",
)
