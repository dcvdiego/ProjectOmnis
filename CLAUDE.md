# Notes for AI coding assistants

Project Omnis is a Godot 4.7 (GDScript) multiplayer FPS. Read `docs/architecture.md` before changing gameplay or networking code, and follow `docs/contributing.md`, including the AI-assistance policy.

## Commands

```bash
godot --headless --path . --import                 # refresh import cache / class registry
godot --headless --path . -s tests/run_tests.gd    # unit, server-rule and movement tests (must pass)
GODOT=godot tests/smoke_multiplayer.sh             # dedicated server + client smoke test
```

## Conventions

- Static typing everywhere. Tabs for indentation. `##` doc comments on public API.
- The server (peer 1) decides outcomes. Client-callable RPCs must validate `multiplayer.get_remote_sender_id()`. Server→player RPCs accept only sender 1.
- Balance values live in `game/weapons/data/*.tres` and movement tuning in `game/player/movement/*.tres`. Don't hard-code them in scripts.
- Physics interpolation is on. Anything you move in `_process` must set `physics_interpolation_mode = OFF` and follow `get_global_transform_interpolated()`. Call `reset_physics_interpolation()` after teleports.
- Assets: CC0 or original only, logged in `CREDITS.md`. Use `tools/fetch_polyhaven.py` for Poly Haven, then run `tools/fix_texture_imports.py` before importing.
- Edit `.tscn`/`.tres` as text carefully. Keep `ext_resource` ids consistent, and re-run the tests to make sure scenes still load.
- Commit generated `.uid` and `.import` files. Never commit `.godot/`.
- Don't add generative-AI art, audio or voice. Placeholders must be listed in `CREDITS.md`.
- Commits need a human `Signed-off-by`. Add `Assisted-by:` when an AI tool helped.
