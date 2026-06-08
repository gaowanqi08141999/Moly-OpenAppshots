#!/usr/bin/env python3
"""
Extract moly_path from PNG metadata.

Returns the snapshot directory path if found, empty string if not.
Exit code 0 = found, 1 = not found (image re-encoded, or not a Moly PNG).

When moly_path is missing, the agent should fall back to:
    curl -s 'http://127.0.0.1:19876/snapshots?limit=1'

Usage: python3 moly_path.py <screenshot.png>
"""
import struct, sys, os

if len(sys.argv) < 2:
    print("Usage: python3 moly_path.py <screenshot.png>", file=sys.stderr)
    sys.exit(1)

filepath = sys.argv[1]

with open(filepath, 'rb') as f:
    data = f.read()

# Detect image format
if data[:8] != b'\x89PNG\r\n\x1a\n':
    # Not a PNG — likely JPEG (image was re-encoded by an agent/cache).
    # moly_path is only embedded in the original PNG.
    print(f"# Not a PNG file ({len(data)} bytes, magic={data[:4].hex()})", file=sys.stderr)
    print(f"# This image was re-encoded — PNG metadata (tEXt) was lost.", file=sys.stderr)
    print(f"# Fallback: curl -s 'http://127.0.0.1:19876/snapshots?limit=1'", file=sys.stderr)
    print("")
    sys.exit(1)

pos = 8
while pos < len(data) - 12:
    length = struct.unpack('>I', data[pos:pos+4])[0]
    chunk_type = data[pos+4:pos+8].decode('ascii', 'ignore')
    if chunk_type == 'tEXt':
        chunk_data = data[pos+8:pos+8+length]
        parts = chunk_data.split(b'\x00', 1)
        if parts[0] == b'moly_path':
            snap_dir = parts[1].decode('utf-8')
            print(snap_dir)
            sys.exit(0)
    elif chunk_type == 'IEND':
        break
    pos += 12 + length

# PNG without moly_path — might be a regular screenshot
print(f"# PNG without moly_path metadata", file=sys.stderr)
print(f"# Fallback: curl -s 'http://127.0.0.1:19876/snapshots?limit=1'", file=sys.stderr)
print("")
sys.exit(1)
