#!/usr/bin/env python3

import sys
from pathlib import Path

input_dir = Path(sys.argv[1])

for p in input_dir.rglob("*"):
    if not p.is_dir():
        new_contents = p.read_bytes().rstrip(b"\0")
        p.write_bytes(new_contents)
