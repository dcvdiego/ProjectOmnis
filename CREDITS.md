# Credits and asset provenance

Every asset that isn't code is listed here. See [docs/contributing.md](docs/contributing.md#assets) for the rules.

No asset in this repository was made with generative AI.

| Asset | Path | Author | Licence | Source | Tools (incl. AI) | Notes |
|---|---|---|---|---|---|---|
| App icon | `icon.svg` | Project Omnis contributors | CC BY 4.0 | original | hand-written SVG | |
| Map layout, materials setup | `game/world/*.tscn`, `game/world/materials/` | Project Omnis contributors | CC BY 4.0 | original | Godot CSG + Poly Haven textures | |
| Shot effects, HUD | `game/fx/fx.gd`, `game/player/hud.gd` | Project Omnis contributors | MIT (code) | original | drawn in code, no textures | |
| Sky HDRI, PBR textures, props (20 assets) | `game/assets/polyhaven/` | Poly Haven artists, listed per asset in [`AUTHORS.md`](game/assets/polyhaven/AUTHORS.md) | CC0 1.0 | [polyhaven.com](https://polyhaven.com) | photogrammetry / hand-made by the authors | fetched with `tools/fetch_polyhaven.py` (MD5-checked) |
| AK-47 and M1911 models + textures | `game/assets/weapons/` | Stein Games | CC0 1.0 | [Free Classic Weapons Pack](https://stein-indie.itch.io/classic-weapons-pack) v1.1 | author states "No generative AI was used" | textures converted: RMAO → ORM channel order, DirectX → OpenGL normals, PNG → JPG |
| Character mesh and animations | `game/assets/characters/quaternius/` | Quaternius | CC0 1.0 | [Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html) (Standard) | hand-made by the author | materials replaced in code |

CC0 doesn't require credit, but these artists gave their work away and deserve it. If you use Project Omnis assets elsewhere, please credit them too.

## Third-party software

- [Godot Engine](https://godotengine.org): MIT License
