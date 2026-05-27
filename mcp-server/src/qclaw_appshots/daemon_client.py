"""
HTTP client for the QClaw Swift capture daemon.

Supports both:
  - TCP:  http://127.0.0.1:19876  (default)
  - Unix socket: /tmp/qclaw-appshot.sock

Set QCLAW_DAEMON_URL env var to override.
"""

from __future__ import annotations

import os
from typing import Any
from urllib.parse import urlencode

import httpx


class DaemonClient:
    """Async client for the QClaw capture daemon."""

    def __init__(self, url: str | None = None):
        self.base_url: str = (url or os.environ.get("QCLAW_DAEMON_URL")
                              or "http://127.0.0.1:19876")
        # Timeout in seconds for capture (can be slow on first call)
        self._capture_timeout = 15.0
        self._default_timeout = 5.0

    async def health(self) -> bool:
        """Check if the daemon is running."""
        try:
            async with httpx.AsyncClient(timeout=self._default_timeout) as client:
                resp = await client.get(f"{self.base_url}/health")
                return resp.status_code == 200
        except Exception:
            return False

    async def capture(self) -> dict[str, Any]:
        """Trigger a new capture of the frontmost window."""
        async with httpx.AsyncClient(timeout=self._capture_timeout) as client:
            resp = await client.post(f"{self.base_url}/capture")
            resp.raise_for_status()
            return resp.json()

    async def list_snapshots(
        self,
        app_name: str | None = None,
        date_from: str | None = None,
        date_to: str | None = None,
        limit: int = 20,
        offset: int = 0,
    ) -> dict[str, Any]:
        """List snapshots with optional filters."""
        params: dict[str, str] = {
            "limit": str(min(limit, 100)),
            "offset": str(offset),
        }
        if app_name:
            params["app"] = app_name
        if date_from:
            params["from"] = date_from
        if date_to:
            params["to"] = date_to

        qs = urlencode(params)
        async with httpx.AsyncClient(timeout=self._default_timeout) as client:
            resp = await client.get(f"{self.base_url}/snapshots?{qs}")
            resp.raise_for_status()
            return resp.json()

    async def get_snapshot(self, snapshot_id: str) -> dict[str, Any] | None:
        """Get full snapshot data by ID."""
        async with httpx.AsyncClient(timeout=self._default_timeout) as client:
            resp = await client.get(f"{self.base_url}/snapshots/{snapshot_id}")
            if resp.status_code == 404:
                return None
            resp.raise_for_status()
            return resp.json()

    async def get_screenshot(self, snapshot_id: str) -> bytes | None:
        """Get raw PNG screenshot data."""
        async with httpx.AsyncClient(timeout=self._default_timeout) as client:
            resp = await client.get(f"{self.base_url}/screenshots/{snapshot_id}")
            if resp.status_code == 404:
                return None
            resp.raise_for_status()
            return resp.content

    async def delete_snapshot(self, snapshot_id: str) -> bool:
        """Delete a snapshot by ID."""
        async with httpx.AsyncClient(timeout=self._default_timeout) as client:
            resp = await client.delete(f"{self.base_url}/snapshots/{snapshot_id}")
            resp.raise_for_status()
            data = resp.json()
            return data.get("success", False)
