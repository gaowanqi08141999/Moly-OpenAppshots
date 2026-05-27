"""QClaw Appshots MCP Server — entry point."""

import asyncio
import sys
from .server import main

if __name__ == "__main__":
    asyncio.run(main())
