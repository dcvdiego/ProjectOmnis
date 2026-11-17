# Contributing to Project Omnis

Thanks for helping build a game its players own. The rules below exist so that a small group of volunteer maintainers can keep up with a large community. The reasoning is in two research notes:

- [community-and-open-source-ai.md](research/community-and-open-source-ai.md): governance, AI and abuse.
- [engineering-practices.md](research/engineering-practices.md): how game and Godot engineering differ from web or backend work, with sources. If you come from web development, its [toolbox table](research/engineering-practices.md#2-your-toolbox-translated) maps your tools to ours.

## How changes get in

```
idea / bug / balance gripe
   └─► Issue (anyone)
         └─► maintainer triage: accepted / needs-proposal / declined
               ├─ small fix or accepted issue ─► Pull request ─► review ─► merge
               └─ gameplay or balance change ─► Proposal ─► experimental playlist
                                                   └─► playtest + match data ─► decision ─► PR
```

1. **Open an issue first.** PRs must link an issue a maintainer has labelled `accepted`. Typo and docs fixes are exempt. Unsolicited large PRs may be closed without review.
2. **Gameplay and balance changes go through a proposal**: an issue using the "Proposal" template that states the problem, the change, and how we'll know it worked. Promising proposals ship to an *experimental playlist* so they're judged on real matches, not just opinions.
3. **Community votes are input, not a trigger.** Signals from players who actually play weigh more than raw counts. Nothing merges automatically because of votes or repeated submissions.
4. **The problem comes first.** Describe a problem players or contributors actually have, not one they might have someday. The fix is weighed against how hard or how frequent the workaround is. This is the same rule as Godot's [best practices](https://contributing.godotengine.org/en/latest/development/engine/best_practices.html).
5. **One change per PR.** If a PR could be split into two without breaking anything, split it. The exception is one mechanical change applied in many places. For balance changes, edit the `.tres` file in `game/weapons/data/` (or `game/player/movement/`) and nothing else.

## Engineering practices

### Where things go

This follows Godot's [project organization guide](https://docs.godotengine.org/en/stable/tutorials/best_practices/project_organization.html) and what larger open-source Godot games do ([survey](research/engineering-practices.md#8-how-godot-game-repositories-are-structured)).

- **Group by feature, not by file type.** A feature's scenes, scripts and resources live together under `game/<feature>/` (`player/`, `weapons/`, `world/`, …). Don't create top-level `scripts/` or `scenes/` folders.
- **Data next to its feature:** `game/weapons/data/` and `game/player/movement/`. Add one `.tres` file per item, such as one per weapon, not a big table in code.
- **Third-party art** goes in `game/assets/<source>/`, so the fetch and build scripts and CREDITS.md can work per source. Every file there must be covered by a CREDITS.md entry; a test checks this.
- **Third-party code and plugins** go in `addons/`, vendored and pinned, and listed in CREDITS.md.
- **Source files** (`.blend`, `.psd`, raw recordings) don't go inside the project. Keep them outside the repo, or in a folder with an empty `.gdignore`, so Godot doesn't import them.
- **Names:** use snake_case for new files and folders. Godot's exported filesystem is case-sensitive while Windows and macOS aren't, so mixed case causes bugs that only appear in exported builds. Files from a vendor keep their original names.
- **Autoloads** (global singletons) are for truly global services: `Network` and `Settings` today. Prefer signals on the node that owns the event. Add an autoload only with a reason in the PR.
- **Tooling:** `tools/` holds Python helpers for assets and `tests/` holds tests. Neither is part of the game.

### Code

- **Static types everywhere.** Untyped declarations are compile errors (`[debug]` in `project.godot`), and the test runner compiles every script before it runs any test. Use `## ` doc comments on public functions.
- **Style:** the [official GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html), checked by `gdlint` (settings in `gdlintrc`). Aim for lines under 100 characters; CI fails above 120. We don't enforce a formatter.
- **Server authority:** anything that decides an outcome (hits, damage, ammo, scoring) runs on the server. Client RPCs validate the sender. See [architecture.md](architecture.md).
- **Simulation vs. rendering:**
  - Gameplay runs on the 60 Hz physics tick.
  - Anything moved per rendered frame (`_process`) sets `physics_interpolation_mode = OFF` and follows `get_global_transform_interpolated()`.
  - Breaking this rule doesn't crash anything; the game just judders on high-refresh screens.
- **Numbers belong in data:** weapon balance in `game/weapons/data/*.tres`, movement in `game/player/movement/*.tres`. Don't hard-code them in scripts.
- **Prefer local solutions.** Put code next to the problem, even with a little duplication, rather than adding hooks to shared code "in case".
- **Compatibility:**
  - Changing an RPC signature, a replicated property or a resource's exported properties can break other clients or existing `.tres` files.
  - Say so in the PR, and update every `.tres` that uses the resource.

### Tests

Run these before you push. CI runs the same steps.

```bash
godot --headless --path . --import                 # once, or after adding assets
godot --headless --path . -s tests/run_tests.gd    # compile every script, then unit, rule and movement tests
GODOT=godot tests/smoke_multiplayer.sh             # real dedicated server + client
gdlint game tests tools                            # pip install gdtoolkit==4.5.0
```

Optional: `pre-commit install` runs the lint and basic file checks on each commit (see `.pre-commit-config.yaml`).

- **Put the test in the same commit as the change.** A bug-fix test should fail without the fix.
- **Test through the game's own entry points.** For example, drive `PlayerMotor` with `MoveInput` the way the keyboard does, in a scene built in code.
- **Never wait on wall-clock time.** Wait for a fixed number of physics frames or for a condition. Sleeps make tests flaky (Riot found the same; see the research note).
- **Keep the suite fast** (seconds, not minutes) so everyone runs it.
- **Tests don't replace playing.** Gameplay, movement and feel changes also need a playtest, and the PR should say what you tried.

### Performance

- **Budget:** the game should hold 144 FPS on mid-range hardware. That's about 6.9 ms per frame for CPU *and* GPU together. The worst frames matter more than the average: a stutter is a bug even if the average FPS looks fine.
- **Profile before you optimise.** Use Godot's profiler and visual profiler (or RenderDoc and Nsight for the GPU).
- **Optimisation PRs must show before/after numbers** from the same scene and settings. Take several runs; ±10 % noise is normal. Code that doesn't show up in a profile isn't worth making harder to read.
- **Say what hardware you measured on.** Rendering changes should be checked on more than one GPU vendor if possible.

### Multiplayer

- **Test with two processes.** Run host + join, or `tests/smoke_multiplayer.sh`, not just single-player.
- **Netcode changes** (prediction, lag compensation, replication) must also be tested with added latency and packet loss: about 100 ms and 1–2 % loss. Tools: `tc netem` on Linux, clumsy on Windows, or an in-engine simulator. Bugs here don't show up on localhost.
- **Version compatibility:** until releases are versioned, client and server must come from the same commit.

### Commits and PRs

- **Commits:**
  - Write titles in the imperative ("Fix wall-run exit speed"), under about 72 characters, with an optional area prefix ("Audio: …").
  - Explain the *why* in the body.
  - Squash review fixes into the commit they fix, and rebase on `main` instead of merging it in.
- **PR description:** what changed and why (link the issue), how you tested it (tests, playtest, profiling, network conditions), and risks or compatibility notes. A typo fix needs one line; a netcode change needs all of it.
- **Contribute only what you understand**, and say which parts you didn't write yourself.
- **Sign off every commit** (`git commit -s`). This certifies the [Developer Certificate of Origin](https://developercertificate.org/): you have the right to submit the work under the project's licences.
- Commit the `.uid` and `.import` files Godot generates. Never commit `.godot/`, which is a local cache.

### Reviewing

Anyone can review. Go in this order, and stop at the first "no":

1. Is the PR linked to an accepted issue?
2. Is the problem real?
3. Is the approach right?
4. Does it work when you run it?
5. Only then, the code.

When reviewing:
- Review everything in one pass.
- Skip nitpicks the linter doesn't care about, and don't ask for "while you're at it" extras.
- Always leave a summary that says what you checked and what you didn't, e.g. "read the code, didn't playtest".
- A merge needs an approval from someone who knows that area.

### Bug reports

- Include exact steps, the commit or build you used, your OS and GPU, and whether you were host, client or dedicated server.
- A clip or log helps a lot.
- If you can, make a **minimal reproduction**: the smallest scene or steps that show the bug. If it used to work, `git bisect` to the commit that broke it; it needs no programming and saves maintainers hours.

## AI-assisted contributions

1. You may use AI tools to help write code, docs or tools. You must understand, test and be able to explain everything you submit. "The AI wrote it" is not an answer in review.
2. Disclose AI assistance in the PR description, and add an `Assisted-by: <tool>` trailer to the relevant commits.
3. Every commit needs a human `Signed-off-by`. Agents may not sign off.
4. **Autonomous agents may not open PRs, issues, reviews or comments** unless a maintainer has opted that agent in. The human operator is responsible for the agent's conduct under the Code of Conduct, including anything it posts elsewhere about the project or its people.
5. **Player-facing content** (art, models, textures, audio, voice, music, in-game text) made with generative AI must be declared in [CREDITS.md](../CREDITS.md). It may be rejected, or accepted only as clearly labelled optional content. It's fine for greybox and placeholders that are marked for replacement. **No voice or likeness cloning of any person without their written consent.**
6. Low-effort, unverified or fabricated bug or security reports lead to a ban.

## Assets

- **Only original work or permissively licensed work** (CC0, CC BY, CC BY-SA). Never commit store or marketplace assets whose licences forbid redistribution in source form.
- Add every asset to [CREDITS.md](../CREDITS.md) with author, licence, source and tools used (including AI tools).
- Prefer text formats Godot can diff (`.tscn`, `.tres`). Ask in the issue before adding more than a few MB of binaries. Keep textures at 1K (2K for large surfaces such as floors), as JPG unless they need alpha. The repo has about 60 MB of assets today; if that grows a lot we'll move binaries to Git LFS.
- **Poly Haven** (CC0) assets: add them to `tools/polyhaven_manifest.json` and run `python3 tools/fetch_polyhaven.py`. Downloads are MD5-checked and the authors are recorded automatically.
- **Audio:** OGG Vorbis, mono for positional sounds. Add sources and cut points to `tools/build_audio.py` so every sound can be rebuilt from its original.
- After adding textures, run `python3 tools/fix_texture_imports.py` and re-import. Headless imports otherwise leave textures uncompressed and without mipmaps.

## Security

Report vulnerabilities privately through GitHub's "Report a vulnerability" (Security tab), not in public issues. Include a reproducer.

## Code of Conduct

Be decent. Critique ideas, not people. Harassment, brigading and coordinated vote manipulation (sock puppets or bot accounts) get you removed. A fuller Code of Conduct will be adopted before the community channels open.
