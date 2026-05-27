"""
MCP resource definitions for QClaw Appshots.

Resources expose snapshot data as addressable URIs:
  appshot://recent               → Most recent snapshot summary
  appshot://{id}/screenshot      → PNG image (base64)
  appshot://{id}/accessibility   → Accessibility Tree JSON
  appshot://{id}/metadata        → Snapshot metadata JSON
"""

import json
from typing import Any

from mcp.server import Server

from .daemon_client import DaemonClient


def register_resources(server: Server, daemon: DaemonClient):
    """Register all 4 resources on the MCP server.

    In MCP SDK 1.x, resources are registered by overriding the
    list_resources and read_resource handler functions.
    """

    async def list_resources_impl() -> list[dict[str, Any]]:
        return [
            {
                "uri": "appshot://recent",
                "name": "Recent Appshot",
                "description": "Most recent snapshot summary",
                "mimeType": "application/json",
            },
            {
                "uri": "appshot://{snapshot_id}/screenshot",
                "name": "Snapshot Screenshot",
                "description": "PNG screenshot of the captured window",
                "mimeType": "image/png",
            },
            {
                "uri": "appshot://{snapshot_id}/accessibility",
                "name": "Snapshot Accessibility Tree",
                "description": "Full Accessibility tree in JSON format",
                "mimeType": "application/json",
            },
            {
                "uri": "appshot://{snapshot_id}/metadata",
                "name": "Snapshot Metadata",
                "description": "Snapshot metadata (app name, timestamp, etc.)",
                "mimeType": "application/json",
            },
        ]

    async def read_resource_impl(uri: str) -> dict[str, Any]:
        # Parse URI: appshot://<id>/<type> or appshot://recent
        if not uri.startswith("appshot://"):
            raise ValueError(f"Unknown resource: {uri}")

        path = uri.replace("appshot://", "")

        if path == "recent":
            snapshots = await daemon.list_snapshots(limit=1)
            items = snapshots.get("items", [])
            content = json.dumps(
                items[0] if items else {"message": "No snapshots yet"},
                ensure_ascii=False, indent=2
            )
            return {
                "contents": [{"uri": uri, "mimeType": "application/json", "text": content}]
            }

        # Parse {snapshot_id}/{type}
        parts = path.split("/", 1)
        if len(parts) != 2:
            raise ValueError(f"Invalid resource URI: {uri}")

        snapshot_id, resource_type = parts
        data = await daemon.get_snapshot(snapshot_id)
        if data is None:
            raise ValueError(f"Snapshot {snapshot_id} not found")

        if resource_type == "screenshot":
            return {
                "contents": [{
                    "uri": uri,
                    "mimeType": "image/png",
                    "blob": data.get("imageBase64", "")
                }]
            }
        elif resource_type == "accessibility":
            content = json.dumps(data.get("axTree", {}), ensure_ascii=False, indent=2)
            return {
                "contents": [{"uri": uri, "mimeType": "application/json", "text": content}]
            }
        elif resource_type == "metadata":
            content = json.dumps(data.get("metadata", {}), ensure_ascii=False, indent=2)
            return {
                "contents": [{"uri": uri, "mimeType": "application/json", "text": content}]
            }
        else:
            raise ValueError(f"Unknown resource type: {resource_type}")

    # Register handlers
    server.list_resources_impl = list_resources_impl
    server.read_resource_impl = read_resource_impl
