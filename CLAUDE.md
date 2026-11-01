# Notes for AI coding assistants

Project Omnis is a Godot 4.7 (GDScript) multiplayer FPS. Read `docs/architecture.md` before changing gameplay or networking code, and follow `docs/contributing.md`, including the AI-assistance policy.

## Commands

```bash
godot --headless --path . --import                 # refresh import cache / class registry
godot --headless --path . -s tests/run_tests.gd    # compiles every script, then unit, server-rule and movement tests (must pass)
GODOT=godot tests/smoke_multiplayer.sh             # dedicated server + client smoke test
gdlint game tests tools                            # lint (gdtoolkit 4.5.0); CI fails on any finding
```

## Conventions

- Static typing everywhere: untyped declarations are compile errors. Tabs for indentation. `##` doc comments on public API. Lines under 100 characters (hard limit 120).
- Follow the engineering practices in `docs/contributing.md`: problem first, one change per PR, a test in the same commit, no wall-clock waits in tests, profiler evidence for optimisations.
- The server (peer 1) decides outcomes. Client-callable RPCs must validate `multiplayer.get_remote_sender_id()`. Server→player RPCs accept only sender 1.
- Balance values live in `game/weapons/data/*.tres` and movement tuning in `game/player/movement/*.tres`. Don't hard-code them in scripts.
- Physics interpolation is on. Anything you move in `_process` must set `physics_interpolation_mode = OFF` and follow `get_global_transform_interpolated()`. Call `reset_physics_interpolation()` after teleports.
- Layout: feature folders under `game/`, snake_case for new files, third-party code in `addons/`, no source art (`.blend`, `.psd`) inside the project. See "Where things go" in `docs/contributing.md`.
- Assets: CC0 or original only, logged in `CREDITS.md` (a test fails if a file under `game/assets/` isn't covered). Use `tools/fetch_polyhaven.py` for Poly Haven, then run `tools/fix_texture_imports.py` before importing.
- Edit `.tscn`/`.tres` as text carefully. Keep `ext_resource` ids consistent, and re-run the tests to make sure scenes still load.
- Commit generated `.uid` and `.import` files. Never commit `.godot/`.
- Don't add generative-AI art, audio or voice. Placeholders must be listed in `CREDITS.md`.
- Commits need a human `Signed-off-by`. Add `Assisted-by:` when an AI tool helped.
