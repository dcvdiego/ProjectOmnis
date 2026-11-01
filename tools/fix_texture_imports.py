#!/usr/bin/env python3
"""Set 3D-friendly import options on every texture under game/assets.

Godot only switches a texture to VRAM compression + mipmaps when the editor
notices it being used in 3D. Headless imports (CI, servers, fresh clones)
never do, so we set the options explicitly:

- VRAM compression (BPTC/S3TC on desktop): ~4-8x less video memory.
- Mipmaps: no shimmering at distance, faster sampling.
- Normal-map compression for files named *nor*/*normal*.

    python3 tools/fix_texture_imports.py && godot --headless --path . --import
"""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent / "game" / "assets"
SETTINGS = {
	"compress/mode": "2",
	"mipmaps/generate": "true",
	"detect_3d/compress_to": "0",
}

changed = 0
for imp in ROOT.rglob("*.import"):
	src = imp.with_suffix("")
	if src.suffix.lower() not in (".jpg", ".jpeg", ".png"):
		continue
	text = imp.read_text()
	if 'importer="texture"' not in text:
		continue
	wanted = dict(SETTINGS)
	name = src.name.lower()
	wanted["compress/normal_map"] = "1" if ("nor" in name or "normal" in name) else "0"
	new = text
	for key, value in wanted.items():
		new = re.sub(rf"^{re.escape(key)}=.*$", f"{key}={value}", new, flags=re.M)
	if new != text:
		imp.write_text(new)
		changed += 1
print(f"updated {changed} texture import files")
