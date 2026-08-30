#!/usr/bin/env python3
"""Vypíše první nedokončený úkol jako ID|MODEL|NEEDS_ME. Exit 1 = fronta hotová."""
import re, sys, pathlib

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
for block in re.split(r"^## ", text, flags=re.M)[1:]:
    def field(name, default=""):
        m = re.search(rf"^{name}:\s*(\S+)", block, flags=re.M)
        return m.group(1) if m else default
    if field("Status") == "todo":
        print(f"{block.split()[0]}|{field('Model', 'sonnet')}|{field('Needs-me', 'no')}")
        sys.exit(0)
sys.exit(1)