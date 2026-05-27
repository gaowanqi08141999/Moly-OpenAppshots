"""
MCP tool definitions for QClaw Appshots.

Five tools exposed to the Agent:
  - take_appshot     Capture frontmost window
  - list_appshots    Browse history
  - get_appshot      Full snapshot detail
  - search_appshots  Full-text search
  - delete_appshot   Remove a snapshot
"""

import json
import base64
from typing import Any

from mcp.server import Server
from mcp.types import Tool, TextContent, ImageContent

from .daemon_client import DaemonClient
from .image_processor import ImageProcessor


def register_tools(server: Server, daemon: DaemonClient):
    """Register all 5 tools on the MCP server."""

    @server.call_tool()
    async def take_appshot(**arguments: Any) -> list[TextContent]:
        """Capture the current frontmost macOS window.

        Returns a snapshot summary with app name, window title,
        text preview (first 500 chars), and counts.
        """
        result = await daemon.capture()
        return [TextContent(
            type="text",
            text=json.dumps(result, ensure_ascii=False, indent=2)
        )]

    @server.call_tool()
    async def list_appshots(**arguments: Any) -> list[TextContent]:
        """List historical snapshots with optional filters.

        Parameters: app_name, date_from, date_to, limit, offset
        """
        result = await daemon.list_snapshots(
            app_name=arguments.get("app_name"),
            date_from=arguments.get("date_from"),
            date_to=arguments.get("date_to"),
            limit=arguments.get("limit", 20),
            offset=arguments.get("offset", 0),
        )
        return [TextContent(
            type="text",
            text=json.dumps(result, ensure_ascii=False, indent=2)
        )]

    @server.call_tool()
    async def get_appshot(**arguments: Any) -> list[TextContent]:
        """Get full snapshot detail, including base64 image and AX tree.

        Parameters: snapshot_id (required), include_image (default true),
                    include_ax_tree (default true), image_max_width (default 2048)
        """
        snapshot_id = arguments.get("snapshot_id", "")
        if not snapshot_id:
            return [TextContent(type="text",
                     text=json.dumps({"error": "snapshot_id required"}))]

        data = await daemon.get_snapshot(snapshot_id)
        if data is None:
            return [TextContent(
                type="text",
                text=json.dumps({"error": f"Snapshot {snapshot_id} not found"})
            )]

        include_image = arguments.get("include_image", True)
        include_ax = arguments.get("include_ax_tree", True)
        max_width = arguments.get("image_max_width", 2048)

        output: dict[str, Any] = {"metadata": data["metadata"]}

        if include_image and "imageBase64" in data:
            resized = ImageProcessor.resize_base64(
                data["imageBase64"], max_width=max_width
            )
            output["image_base64"] = resized

        if include_ax and "axTree" in data:
            output["accessibility_tree"] = data["axTree"]
            output["full_text"] = _extract_flat_text(data["axTree"])

        return [TextContent(
            type="text",
            text=json.dumps(output, ensure_ascii=False, indent=2)
        )]

    @server.call_tool()
    async def search_appshots(**arguments: Any) -> list[TextContent]:
        """Full-text search across snapshot metadata and accessibility text.

        Parameters: query (required), search_in (default "all")
        """
        query = (arguments.get("query") or "").lower()
        if not query:
            return [TextContent(type="text",
                     text=json.dumps({"error": "query required"}))]
        search_in = arguments.get("search_in", "all")

        all_snapshots = await daemon.list_snapshots(limit=500)
        results = []

        for snap in all_snapshots.get("items", []):
            matched = False
            snippet = ""

            if search_in in ("all", "app_name"):
                if query in (snap.get("appName") or "").lower():
                    matched = True
                    snippet = f"app: {snap.get('appName')}"
            if search_in in ("all", "window_title"):
                if query in (snap.get("windowTitle") or "").lower():
                    matched = True
                    snippet = f"title: {snap.get('windowTitle')}"

            if matched:
                results.append({**snap, "matched_in": search_in, "snippet": snippet})

        return [TextContent(
            type="text",
            text=json.dumps({"query": query, "results": results},
                            ensure_ascii=False, indent=2)
        )]

    @server.call_tool()
    async def delete_appshot(**arguments: Any) -> list[TextContent]:
        """Delete a snapshot by ID. Removes all associated files.

        Parameters: snapshot_id (required)
        """
        snapshot_id = arguments.get("snapshot_id", "")
        if not snapshot_id:
            return [TextContent(type="text",
                     text=json.dumps({"error": "snapshot_id required"}))]

        success = await daemon.delete_snapshot(snapshot_id)
        return [TextContent(
            type="text",
            text=json.dumps({"success": success, "snapshot_id": snapshot_id})
        )]

    # ── Register tool schemas for LLM discovery ──

    server.list_tools_impl = lambda: [
        Tool(
            name="take_appshot",
            description="捕获当前 macOS 前台窗口的截图和完整的 Accessibility 文本树。不需要参数，自动识别并捕获当前前台窗口。",
            inputSchema={
                "type": "object",
                "properties": {},
                "required": []
            }
        ),
        Tool(
            name="list_appshots",
            description="列出所有历史快照，支持按应用名称、日期范围和分页筛选。",
            inputSchema={
                "type": "object",
                "properties": {
                    "app_name": {"type": "string", "description": "按应用名筛选"},
                    "date_from": {"type": "string", "description": "起始日期 YYYY-MM-DD"},
                    "date_to": {"type": "string", "description": "结束日期 YYYY-MM-DD"},
                    "limit": {"type": "integer", "description": "返回数量，默认20，最大100"},
                    "offset": {"type": "integer", "description": "分页偏移量，默认0"}
                }
            }
        ),
        Tool(
            name="get_appshot",
            description="获取单个快照的完整内容，包括 base64 截图和完整的 Accessibility 树。",
            inputSchema={
                "type": "object",
                "properties": {
                    "snapshot_id": {"type": "string", "description": "快照ID"},
                    "include_image": {"type": "boolean", "description": "是否包含base64截图，默认true"},
                    "include_ax_tree": {"type": "boolean", "description": "是否包含AX树，默认true"},
                    "image_max_width": {"type": "integer", "description": "截图最大宽度，默认2048"}
                },
                "required": ["snapshot_id"]
            }
        ),
        Tool(
            name="search_appshots",
            description="在快照元数据和Accessibility文本中进行全文搜索。",
            inputSchema={
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "搜索关键词"},
                    "search_in": {"type": "string", "description": "搜索范围: all, app_name, window_title"}
                },
                "required": ["query"]
            }
        ),
        Tool(
            name="delete_appshot",
            description="删除指定快照及其所有关联文件。此操作不可逆。",
            inputSchema={
                "type": "object",
                "properties": {
                    "snapshot_id": {"type": "string", "description": "要删除的快照ID"}
                },
                "required": ["snapshot_id"]
            }
        ),
    ]


def _extract_flat_text(ax_tree: dict) -> str:
    """Recursively extract all text content from an AX tree node."""
    texts = []

    def collect(node: dict):
        if node.get("value"):
            t = str(node["value"]).strip()
            if t and len(t) < 5000:
                texts.append(f"[{node.get('role', '?')}] {t}")
        if node.get("title"):
            t = str(node["title"]).strip()
            if t:
                texts.append(f"[{node.get('role', '?')}:title] {t}")
        for child in node.get("children", []):
            collect(child)

    collect(ax_tree)
    return "\n".join(texts)
