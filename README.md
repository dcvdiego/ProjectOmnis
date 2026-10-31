# Project Omnis

## A community-driven, open-source shooter

As an avid gamer myself, whenever a new game gets developed, you never know what you will get. From pay-to-win, to countless unbalanced characters/weapons and ultimately, a usually disappointed and angry fanbase.

Omnis' goal is to be the first community game. **You** play it, so if you don't like something or want to add something, you can!

That means a game that is open source end to end and can't be shut down: anyone can read the code, propose a change, or host a server.

![Training Garage prototype](docs/images/training-garage.png)

## Status

Early prototype. The project restarted in 2026 on **[Godot 4.7](https://godotengine.org)** (MIT-licensed) after the original 2022 Unreal/Lyra draft. [Why we moved](docs/research/community-and-open-source-ai.md#2-a-blocker-to-fix-first-engine-licensing-not-an-ai-issue) · [roadmap](docs/progress.md)

What works today:

- **Training Garage**: a greybox firing range with target dummies at 15/30/50 m, cover, and a raised platform
- First-person movement (walk, sprint, jump) and two hitscan weapons (rifle, pistol) with magazines and reloads
- Online multiplayer: host, join, or run a headless dedicated server. The server decides hits, damage, ammo and respawns.
- Weapon balance stored as plain-text data, so a balance change is a one-line diff

## Play it

1. Install **Godot 4.7.2** (standard build, not .NET): <https://godotengine.org/download>
2. Clone this repo, open Godot, **Import** → select `project.godot`
3. Press **F5**, click **Host**. To play together, a second player clicks **Join** with the host's IP (port `24680`, UDP).

Command line:

```bash
godot --path . -- --host                          # host and play
godot --path . -- --join=192.168.1.20             # join a server
godot --headless --path . -- --server --port=24680  # dedicated server
```

Controls: **WASD** move · **Shift** sprint · **Space** jump · **LMB** fire · **R** reload · **1/2** switch weapon · **Esc** free the mouse. Gamepad is supported too.

## Run the tests

```bash
godot --headless --path . --import
godot --headless --path . -s tests/run_tests.gd   # unit + server-rule tests
GODOT=godot tests/smoke_multiplayer.sh            # real server + client
```

CI runs the same steps on every push and PR.

## Project layout

```
game/
  autoload/network.gd     connection management (autoloaded as `Network`)
  main/                   entry scene: menu + launch flags
  player/                 first-person player, HUD, server-side combat rules
  weapons/weapon_data.gd  WeaponData resource
  weapons/data/*.tres     one text file per weapon (balance lives here)
  world/                  Training Garage map, game-mode script, target dummy
tests/                    headless tests and multiplayer smoke test
docs/                     roadmap, architecture, contributing, research
```

## Contributing

Read **[docs/contributing.md](docs/contributing.md)** first. It covers the proposal process, the AI-assistance policy, and asset rules. The design reasoning is in [docs/architecture.md](docs/architecture.md), and the background research is in [docs/research/](docs/research/).

A community Discord/Matrix will open once there's a playable loop worth gathering around.

## License

Code is under the [MIT License](LICENSE). Original art and audio are under CC BY 4.0 unless noted in [CREDITS.md](CREDITS.md).
