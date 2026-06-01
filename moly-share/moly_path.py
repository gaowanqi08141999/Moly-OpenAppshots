#!/usr/bin/env python3
"""Extract moly_path from PNG metadata. Usage: python3 moly_path.py <png_file>"""
import struct, sys

if len(sys.argv) < 2:
    print("Usage: python3 moly_path.py <screenshot.png>")
    sys.exit(1)

with open(sys.argv[1], 'rb') as f:
    data = f.read()

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

print("")  # not found
sys.exit(1)
