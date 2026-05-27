"""
QClaw Appshots MCP Server.

Exposes macOS appshot capture as MCP tools + resources.
Communicates with the Swift capture daemon via HTTP (localhost:19876).
"""

import os
import json
import asyncio
from pathlib import Path

from mcp.server import Server
from mcp.server.stdio import stdio_server

from .tools import register_tools
from .resources import register_resources
from .daemon_client import DaemonClient

DAEMON_URL = os.environ.get("QCLAW_DAEMON_URL", "http://127.0.0.1:19876")
SNAPSHOT_DIR = os.environ.get("QCLAW_SNAPSHOT_DIR",
                               str(Path.home() / "snapshots"))


def create_server() -> Server:
    """Create and configure the MCP server with tools and resources."""
    server = Server("qclaw-appshots")
    daemon = DaemonClient(DAEMON_URL)

    register_tools(server, daemon)
    register_resources(server, daemon)

    return server


async def main():
    """Run the MCP server over stdio."""
    server = create_server()

    async with stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            server.create_initialization_options(),
        )
