# MCP Setup — OpenClaw / Claude Desktop / Cursor

`appshot_mcp.py` exposes QClaw Appshot tools via the **Model Context Protocol (MCP)**.
Any MCP-compatible client can use it.

## Requirements

- Python 3.10+
- Capture daemon running on `127.0.0.1:19876`

## Hermes

```bash
hermes mcp add qclaw-appshot -- python3 ~/.qclaw-appshot/appshot_mcp.py
```

Or add manually to `~/.hermes/config.yaml`:

```yaml
mcp_servers:
  qclaw-appshot:
    command: python3
    args:
      - ~/.qclaw-appshot/appshot_mcp.py
```

Restart Hermes. Tools appear automatically via MCP.

## OpenClaw

Add to `~/.openclaw/openclaw.json`:

```json
{
  "mcpServers": {
    "qclaw-appshot": {
      "command": "python3",
      "args": ["/path/to/appshot_mcp.py"]
    }
  }
}
```

Restart OpenClaw. The 5 tools will appear automatically.

## Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "qclaw-appshot": {
      "command": "python3",
      "args": ["/path/to/appshot_mcp.py"]
    }
  }
}
```

Restart Claude Desktop.

## Cursor

Add to Cursor Settings → MCP:

```json
{
  "mcpServers": {
    "qclaw-appshot": {
      "command": "python3",
      "args": ["/path/to/appshot_mcp.py"]
    }
  }
}
```

## Verify

```bash
python3 appshot_mcp.py
# Then send: {"jsonrpc":"2.0","id":1,"method":"tools/list"}
# Expected: 5 tools listed
```
