# Credits and asset provenance

Every asset that isn't code is listed here. See [docs/contributing.md](docs/contributing.md#assets) for the rules.

No asset in this repository was made with generative AI. Every audio file can be rebuilt from its sources with `tools/build_audio.py`.

| Asset | Path | Author | Licence | Source | Tools (incl. AI) | Notes |
|---|---|---|---|---|---|---|
| App icon | `icon.svg` | Project Omnis contributors | CC BY 4.0 | original | hand-written SVG | |
| Map layout, materials setup | `game/world/*.tscn`, `game/world/materials/` | Project Omnis contributors | CC BY 4.0 | original | Godot CSG + Poly Haven textures | |
| Shot effects, HUD | `game/fx/fx.gd`, `game/player/hud.gd` | Project Omnis contributors | MIT (code) | original | drawn in code, no textures | |
| Sky HDRI, PBR textures, props (20 assets) | `game/assets/polyhaven/` | Poly Haven artists, listed per asset in [`AUTHORS.md`](game/assets/polyhaven/AUTHORS.md) | CC0 1.0 | [polyhaven.com](https://polyhaven.com) | photogrammetry / hand-made by the authors | fetched with `tools/fetch_polyhaven.py` (MD5-checked) |
| AK-47 and M1911 models + textures | `game/assets/weapons/` | Stein Games | CC0 1.0 | [Free Classic Weapons Pack](https://stein-indie.itch.io/classic-weapons-pack) v1.1 | author states "No generative AI was used" | textures converted: RMAO → ORM channel order, DirectX → OpenGL normals, PNG → JPG |
| Character mesh and animations (also the first-person arms) | `game/assets/characters/quaternius/` | Quaternius | CC0 1.0 | [Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html) (Standard) | hand-made by the author | materials replaced in code; arms posed by IK |
| AK-47 and M1911 gunshots (near and mid distance) | `game/assets/audio/weapons/*_shot_*.ogg` | The Free Firearm Sound Library team | CC0 1.0 | [The Free Firearm Sound Library](https://opengameart.org/content/the-free-firearm-sound-library) (freefirearmsfx.com), Prepared library | field recordings | single shots cut, normalised, OGG |
| Reload sounds | `game/assets/audio/weapons/*_reload.ogg` | SpringySpringo | CC0 1.0 | [Gun Reload Sounds](https://opengameart.org/content/gun-reload-sounds) | recordings | trimmed |
| Weapon switch, dry fire, metal impacts, body fall | `game/assets/audio/weapons/`, `game/assets/audio/impacts/` | BMacZero | CC0 1.0 | [Gun Reload Sound Effects](https://opengameart.org/content/gun-reload-sound-effects), [Metal Impact Sounds](https://opengameart.org/content/metal-impact-sounds) | recordings | trimmed |
| Concrete and flesh impacts | `game/assets/audio/impacts/` | rubberduck | CC0 1.0 | [100 CC0 SFX #2](https://opengameart.org/content/100-cc0-sfx-2) | recordings | trimmed |
| Concrete footsteps | `game/assets/audio/footsteps/concrete_*.ogg` | Fantozzi (via OpenGameArt) | CC0 1.0 | [Fantozzi's Footsteps](https://opengameart.org/content/fantozzis-footsteps-grasssand-stone) (originally freesound.org pack 10338) | recordings | stone steps, trimmed |
| Metal footsteps | `game/assets/audio/footsteps/metal_*.ogg` | Thimras | CC0 1.0 | [Metal footsteps on concrete](https://opengameart.org/content/metal-footsteps-on-concrete) | recordings | trimmed |
| Gear rustle | `game/assets/audio/footsteps/gear_*.ogg` | OpenGameArt submitter of "Footsteps (leather, cloth, armor)" | CC0 1.0 (dual-licensed CC0 / OGA-BY 3.0; used under CC0) | [Footsteps (leather, cloth, armor)](https://opengameart.org/content/footsteps-leather-cloth-armor) | recordings | cloth steps, trimmed |
| Wind, slide, jump-jet, landing thump, hit-marker and kill ticks | `game/assets/audio/movement/`, `game/assets/audio/ui/` | Project Omnis contributors | CC BY 4.0 | original | synthesised from seeded noise / sine waves by `tools/build_audio.py` | no samples, no AI |

CC0 doesn't require credit, but these artists gave their work away and deserve it. If you use Project Omnis assets elsewhere, please credit them too.

## Third-party software

- [Godot Engine](https://godotengine.org): MIT License
