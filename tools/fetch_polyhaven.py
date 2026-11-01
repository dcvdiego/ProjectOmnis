#!/usr/bin/env python3
"""Download CC0 assets from Poly Haven (https://polyhaven.com) into the project.

The downloaded files are committed, so players and CI never need this script.
It exists so anyone can see exactly where each asset came from, re-fetch it at
another resolution, or add a new one the same way.

    python3 tools/fetch_polyhaven.py                # fetch everything in the manifest
    python3 tools/fetch_polyhaven.py barrel_03      # fetch one asset
    python3 tools/fetch_polyhaven.py --list         # show the manifest

Every file is checked against the MD5 published by the Poly Haven API.
Authors are written to game/assets/polyhaven/AUTHORS.md (CC0 needs no
attribution, but we credit people anyway: see CREDITS.md).
Standard library only.
"""

from __future__ import annotations

import hashlib
import json
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = Path(__file__).with_name("polyhaven_manifest.json")
OUT = ROOT / "game" / "assets" / "polyhaven"
API = "https://api.polyhaven.com"
UA = {"User-Agent": "ProjectOmnis-asset-fetch/1.0 (+https://github.com/dcvdiego/ProjectOmnis)"}


def get(url: str) -> bytes:
	with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r:
		return r.read()


def fetch_file(url: str, md5: str | None, dest: Path) -> None:
	if dest.exists() and md5 and hashlib.md5(dest.read_bytes()).hexdigest() == md5:
		return
	data = get(url)
	if md5 and hashlib.md5(data).hexdigest() != md5:
		raise SystemExit(f"checksum mismatch for {url}")
	dest.parent.mkdir(parents=True, exist_ok=True)
	dest.write_bytes(data)
	print(f"  {dest.relative_to(ROOT)} ({len(data) // 1024} KiB)")


def fetch_asset(entry: dict) -> dict:
	asset_id, kind, res = entry["id"], entry["kind"], entry["res"]
	files = json.loads(get(f"{API}/files/{asset_id}"))
	info = json.loads(get(f"{API}/info/{asset_id}"))
	print(f"{asset_id} ({kind}, {res})")
	if kind == "hdri":
		f = files["hdri"][res]["hdr"]
		fetch_file(f["url"], f.get("md5"), OUT / "hdri" / f"{asset_id}_{res}.hdr")
	elif kind == "texture":
		# Diffuse, OpenGL normal, and ARM (AO/rough/metal = Godot's ORM layout).
		for key, suffix in (("Diffuse", "diff"), ("nor_gl", "nor_gl"), ("arm", "arm")):
			f = files[key][res]["jpg"]
			fetch_file(f["url"], f.get("md5"), OUT / "textures" / asset_id / f"{asset_id}_{suffix}_{res}.jpg")
	elif kind == "model":
		g = files["gltf"][res]["gltf"]
		base = OUT / "models" / asset_id
		fetch_file(g["url"], g.get("md5"), base / f"{asset_id}.gltf")
		for rel, f in g["include"].items():
			fetch_file(f["url"], f.get("md5"), base / rel)
	else:
		raise SystemExit(f"unknown kind {kind}")
	return {"id": asset_id, "name": info.get("name", asset_id), "kind": kind, "authors": sorted(info.get("authors", {}))}


def main(argv: list[str]) -> None:
	manifest = json.loads(MANIFEST.read_text())
	if "--list" in argv:
		for e in manifest:
			print(f"{e['kind']:8} {e['res']:3} {e['id']}  — {e.get('use', '')}")
		return
	wanted = [a for a in argv if not a.startswith("-")]
	credits = [fetch_asset(e) for e in manifest if not wanted or e["id"] in wanted]
	if wanted:
		return
	lines = ["# Poly Haven assets", "", "All CC0 1.0 (https://polyhaven.com/license). Fetched by `tools/fetch_polyhaven.py`.", "",
		"| Asset | Kind | Authors | Page |", "|---|---|---|---|"]
	for c in credits:
		lines.append(f"| {c['name']} (`{c['id']}`) | {c['kind']} | {', '.join(c['authors'])} | https://polyhaven.com/a/{c['id']} |")
	(OUT / "AUTHORS.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
	main(sys.argv[1:])
