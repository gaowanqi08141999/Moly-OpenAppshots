# MCP Setup — OpenClaw / Claude Desktop / Cursor

`moly_mcp.py` exposes Moly tools via the **Model Context Protocol (MCP)**.
Any MCP-compatible client can use it.

## Requirements

- Python 3.10+
- Capture daemon running on `127.0.0.1:19876`

## Hermes

```bash
hermes mcp add moly -- python3 ~/.moly/moly_mcp.py
```

Or add manually to `~/.hermes/config.yaml`:

```yaml
mcp_servers:
  moly:
    command: python3
    args:
      - ~/.moly/moly_mcp.py
```

Restart Hermes. Tools appear automatically via MCP.

## OpenClaw

Add to `~/.openclaw/openclaw.json`:

```json
{
  "mcpServers": {
    "moly": {
      "command": "python3",
      "args": ["/path/to/moly_mcp.py"]
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
    "moly": {
      "command": "python3",
      "args": ["/path/to/moly_mcp.py"]
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
    "moly": {
      "command": "python3",
      "args": ["/path/to/moly_mcp.py"]
    }
  }
}
```

## Verify

```bash
python3 moly_mcp.py
# Then send: {"jsonrpc":"2.0","id":1,"method":"tools/list"}
# Expected: 5 tools listed
```
