# Research: engineering practices for games and for Godot

_Research date: 1 November 2026. Written for contributors who know web or backend engineering (linters, test runners, bundlers, monorepos) but haven't worked on games. The rules that came out of it are in [contributing.md](../contributing.md); this page explains why._

## TL;DR

1. **Most of your tooling habits carry over.** Lint, type-check, test in CI, small PRs and review all apply. The [table in §2](#2-your-toolbox-translated) maps each one to its Godot equivalent.
2. **Four things are new:**
   - **A hard time budget.** At 144 Hz every frame must finish in 6.9 ms, and the worst frames matter more than the average.
   - **"Correct" includes "feels right".** Feel can only be judged by people playing.
   - **Multiplayer runs on a network you don't control.**
   - **Most of the repo is binary content** with its own licences.
3. **Godot's own project is a good model** for running a volunteer codebase:
   - The problem comes first: no speculative features.
   - One change per PR.
   - Reviewers check that the problem exists and that the approach is right before they read the code.
   - Optimisations need profiler evidence.
4. **Real Godot game repos** (15 surveyed in [§8](#8-how-godot-game-repositories-are-structured)) agree on the basics:
   - `project.godot` at the root, `.import` and `.uid` files committed, third-party code in `addons/`.
   - Folders grouped by feature or system rather than by file type.
   - Balance and content kept as data files.

   Most have **no automated tests**: only 2 of 15 do. Only 3 lint in CI, and 5 build exports in CI. Our tests and lint are already ahead of the norm; export builds are the gap.
5. **Studios that ship live games automate heavily and still playtest.**
   - Rare tested *Sea of Thieves* on every check-in from day one.
   - Riot runs about 100,000 functional test cases a day on *League of Legends*.
   - Valve treats designs as hypotheses and playtests as experiments.
6. **Adopted in this repo now:**
   - Untyped GDScript declarations are compile errors, and the test runner compiles every script.
   - `gdlint`, pinned, runs in CI.
   - Optional pre-commit hooks.
   - A test that fails if any file under `game/assets/` isn't covered by CREDITS.md.
   - A rewritten contributing guide, including where files go (see [§9](#9-what-we-adopted-deferred-and-rejected)).

## 1. What is actually different about games

**The frame budget is a hard deadline.** A game runs one loop: read input, simulate, render, repeat ([Game Programming Patterns: Game Loop](https://gameprogrammingpatterns.com/game-loop.html)). Every frame has to fit the display's refresh interval:

| Refresh | Budget per frame |
|---|---|
| 60 Hz | 16.7 ms |
| 144 Hz | 6.9 ms |

A web page that takes 30 ms longer is slightly slower. A game that misses its budget visibly stutters. So **averages lie**: Godot's own optimisation guidelines note that "optimizing for the worst case can be more important than optimizing for the best case, as worst cases can cause dropped frames" ([Godot: optimization guidelines](https://contributing.godotengine.org/en/latest/development/engine/optimization.html)). Measure frame-time spikes, such as the 1 % lows, not just the average FPS.

**Simulation and presentation run at different rates.** Gameplay runs on a fixed tick (60 Hz here), so physics and netcode are stable and reproducible. Rendering runs as fast as the display allows, interpolating between ticks. The standard explanation is [Glenn Fiedler's "Fix Your Timestep!"](https://gafferongames.com/post/fix_your_timestep/). Godot implements it as [physics interpolation](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/physics_interpolation_introduction.html). It's why our rule "anything moved in `_process` opts out of interpolation" exists. Breaking it doesn't crash anything; it makes the game judder at 144 Hz.

**"Correct" includes "feels right", and you can't unit-test fun.** Tests can pin down rules: damage, speed caps, jump height. Whether a slide *feels* good is decided by people playing. Valve's playtesting talk puts it bluntly: "Game designs are hypotheses. Playtests are experiments", and "We don't know what's best (players do)" ([Ambinder, GDC 2009](https://cdn.fastly.steamstatic.com/apps/valve/2009/GDC2009_ValvesApproachToPlaytesting.pdf)). So a gameplay PR needs both tests *and* a playtest.

**Multiplayer is a distributed system with a 100 ms speed of light.**
- The server must be authoritative, or clients can cheat.
- Clients must predict their own movement, or input feels laggy.
- The server must rewind time to judge hits fairly (lag compensation).

The classic references are [Valve's latency compensation paper](https://developer.valvesoftware.com/wiki/Latency_Compensating_Methods_in_Client/Server_In-game_Protocol_Design_and_Optimization) and [Gabriel Gambetta's series](https://www.gabrielgambetta.com/client-server-game-architecture.html). In Blizzard's *Overwatch*, only three gameplay systems (movement, weapons and the state script) deal with netcode directly. That kept the hard part small ([Ford, GDC 2017](https://gdcvault.com/play/1024001/-Overwatch-Gameplay-Architecture-and); [summary](https://edgegap.com/blog/game-backend-deep-dive-overwatch-2016-netcode-architecture-rollback)). Our `PlayerMotor` is built to be that kind of piece.

**Content outweighs code.** Most of the repo is textures, models and audio. Each file has a licence, and binaries don't diff or merge. Asset licensing and repo size are engineering problems here, not legal footnotes (see §6).

**Hardware varies far more than browsers do.** GPUs, drivers and power-saving modes change performance. Godot asks GPU-related PRs to be tested on several platforms, because "changes which increase performance on one platform can often reduce performance on another" ([optimization guidelines](https://contributing.godotengine.org/en/latest/development/engine/optimization.html)).

## 2. Your toolbox, translated

| Web / backend | In this project | Notes |
|---|---|---|
| ESLint | **`gdlint`** ([godot-gdscript-toolkit](https://github.com/Scony/godot-gdscript-toolkit), v4.5.0 pinned) | Naming, definition order, line length, duplicate loads. Config in `gdlintrc`. |
| `tsc --noEmit`, `strict` | **Static typing**, plus `untyped_declaration` set to *error* in `project.godot`. `tests/run_tests.gd` compiles every script first. | Typed GDScript catches more errors before running, and it is faster too: it "improves performance by using optimized opcodes" ([Godot: static typing](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/static_typing.html)). |
| Prettier | `gdformat`, same toolkit; **not enforced** (see §9) | Follow the [official style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html). |
| Jest / Vitest | `tests/suite.gd` (headless, dependency-free). [GUT](https://github.com/bitwes/Gut) or [gdUnit4](https://github.com/MikeSchulze/gdUnit4) when it grows. | Movement is tested in a code-built arena with scripted input. |
| Playwright / E2E | `tests/smoke_multiplayer.sh` (real server and client); bots later | Riot drives the real game over RPC from Python (§4). |
| Lockfile | Godot version **and checksum** pinned in CI; add-ons vendored in the repo | An engine upgrade is a deliberate PR, like a major dependency bump. |
| Vite dev server / HMR | The Godot editor: F5 runs the game, scripts hot-reload, assets import automatically | The importer writes `.import` files: commit them. `.godot/` is a cache: never commit it ([Godot: VCS](https://docs.godotengine.org/en/stable/tutorials/best_practices/version_control_systems.html)). |
| Bundler / build | Export templates plus export presets | Not set up yet; release builds come later. |
| Nx / monorepo tooling | Not needed | One project, one repo. Godot scenes and resources already give module boundaries. |
| Lighthouse / perf budgets | Frame-time budget plus Godot's [profiler](https://docs.godotengine.org/en/stable/tutorials/scripting/debug/the_profiler.html) and visual profiler | Measure on modest hardware. Headless CI can't measure GPU time. |
| Feature flags, canary | **Experimental playlist** for gameplay changes; settings and presets for players | See the proposal process in contributing.md. |
| Sentry / observability | [sentry-godot](https://github.com/getsentry/sentry-godot) (MIT; GDScript stack traces, native crash reports) | Deferred: needs a privacy policy and opt-in. |
| API versioning | Network protocol and `.tres` compatibility | Client and server must agree on RPC signatures; old maps and resources should still load. |
| DB migrations | Resource format changes | Changing a resource's exported properties can silently break existing `.tres` files. Tests load every weapon `.tres`. |

## 3. How the Godot project runs itself

Godot is the most relevant model we have: a large volunteer project with more PRs than reviewers. Its contributor guide moved to [contributing.godotengine.org](https://contributing.godotengine.org/en/latest/) in 2025–26. What it asks for:

**Problem first** ([Best practices for engine contributors](https://contributing.godotengine.org/en/latest/development/engine/best_practices.html)):
- "The problem always comes first." "To solve the problem, it has to exist in the first place." Speculative "future proofing" is "generally considered a bad habit".
- A problem is worth solving in proportion to how *complex* or *frequent* the workaround is.
- Discuss the problem before coding, unless the area has a clear owner.
- "To each problem, its own solution": targeted fixes beat do-everything systems.
- "Prefer local solutions": put code near the problem, even if that means some duplication, rather than adding hooks to core layers.
- Godot favours ease of use and maintenance over absolute performance.

**Contribution rules** ([Rules for contributions](https://contributing.godotengine.org/en/latest/development/contribution_rules.html)):
- **One change per PR.** "If your pull request could be split into two pull requests without breaking anything, it should probably be two separate pull requests." The exception is the same mechanical change applied in many places.
- **No features from new contributors.** Someone with 3 or fewer merged PRs needs a maintainer's explicit permission before starting a feature or a significant refactor. Bug fixes and docs build trust first.
- **The PR description should cover** summary, motivation (linked issue), related work, technical overview, testing, risks and compatibility, and follow-up work. Scale it to the change.
- **"Contribute only what you understand"**, and disclose any part you didn't author yourself.

**Commits** ([CONTRIBUTING.md](https://github.com/godotengine/godot/blob/master/CONTRIBUTING.md), [merge guidelines](https://contributing.godotengine.org/en/latest/development/workflows/release_management/merge_guidelines.html)):
- Titles are imperative ("Fix…", "Add…") and under about 72 characters. Reference issues in the PR description.
- Rebase instead of merging main into your branch, and squash review fixes into the commit they fix.
- PRs normally land as one commit.
- Tests go in the same commit as the fix. A bug-fix test should fail without the fix.

**Review** ([Reviewing pull requests](https://contributing.godotengine.org/en/latest/development/workflows/review_guidelines.html)) follows a fixed order, and the reviewer stops early if a step fails:
1. Is the PR valid?
2. Does the problem exist?
3. Is the approach appropriate?
4. Test it.
5. Only then review the code.

Reviewers should:
- Avoid repeat rounds of review, nitpicks, purely subjective style comments, and "while you're at it" scope creep.
- Always write a summary that says what they did and did *not* check, for example "read the code, didn't test".

Before merging, Godot wants approval from someone who knows the area plus a second maintainer.

**Optimisation** ([optimization guidelines](https://contributing.godotengine.org/en/latest/development/engine/optimization.html)):
- "If an area of the engine is not appearing in a profile, no matter how inefficient the code, then a PR is unlikely to be approved."
- Profile before and after, in an optimised build. Run each test at least 2 s and several times; ±10 % noise is normal.
- Prefer real games to synthetic benchmarks.

**Compatibility** ([Handling compatibility breakages](https://contributing.godotengine.org/en/latest/development/engine/compatibility.html)): patch releases never break compatibility; minor releases only to fix bugs; major releases can.

**Bug reports** ([issue report writing](https://contributing.godotengine.org/en/latest/feedback/issues/issue_report_writing.html), [bisecting](https://contributing.godotengine.org/en/latest/feedback/issues/bisecting.html)):
- Clear steps plus a **minimal reproduction project (MRP)**, which "should be the least amount of content necessary to replicate the bug". Full games are not valid MRPs.
- Check the latest version.
- Bisect regressions (`git bisect`) to the commit that caused them.

**Tooling** ([.pre-commit-config.yaml](https://github.com/godotengine/godot/blob/master/.pre-commit-config.yaml)): pre-commit runs clang-format, clang-tidy, ruff, mypy, codespell, eslint and file-format checks. The same checks run in CI.

**AI policy: theirs is stricter than ours.** Godot's [AI-assisted contributions](https://contributing.godotengine.org/en/latest/development/contribution_rules.html#ai-assisted-contributions) rules forbid:
- AI-generated text in human-to-human communication.
- Letting an AI agent submit PRs.
- Using AI "to generate substantial pieces of code". Their rule of thumb is that changes under about 15 lines are trivial.
- AI-generated user-facing media.

Maintainers aren't obliged to review AI-assisted PRs.

Other open-source games are similar:
- [Luanti](https://github.com/luanti-org/luanti/blob/master/doc/developing/ai_policy.md) bans "vibe-coding", autonomous AI use and AI-generated media, but allows AI for search, local review and boilerplate. It also closes non-roadmap PRs that don't get "concept approval" within a month ([CONTRIBUTING](https://github.com/luanti-org/luanti/blob/master/.github/CONTRIBUTING.md)).
- [Veloren](https://gitlab.com/veloren/veloren/-/blob/master/CONTRIBUTING.md) presumes all LLM output is "tainted content" that must not be committed.

Our policy allows AI-written code if the human understands, tests, discloses and signs off on it, and agents may act only when opted in. That is a deliberate difference, and this repo's own history leans heavily on an AI agent. **This is a decision for the maintainers, not something this research changes** (see §9).

## 4. How studios test games

**Rare, *Sea of Thieves*** ([GDC 2019](https://www.gdcvault.com/play/1026366/Automated-Testing-of-Gameplay-Features); [Game Developer summary](https://gamedeveloper.com/design/how-rare-automates-testing-for-ai-and-more-in-sea-of-thieves-part-4-of-4-)):
- Automated tests from day one, because a live game has no finish line and each feature can undo earlier fixes.
- Most tests are unit tests. Integration tests run in small test maps.
- Larger suites (multiplayer, performance, network latency, platform) run overnight.
- Every check-in must pass the relevant tests. When the build breaks, nobody else commits until it's fixed or reverted.
- Over 100 internal builds were playable before launch. Human QA shifted from regression checks to polish and the overall experience.

**Riot, *League of Legends*** ([Automated Testing for League of Legends](https://www.riotgames.com/en/news/automated-testing-league-legends)):
- Python functional tests drive the real client and server over RPC.
- About 5,500 test cases run in 18 minutes per build, about 100,000 a day.
- The suite finds about half of critical bugs, and those bugs get fixed about 8× faster.
- New tests sit in a staging set for a week before they can block builds, which is how they handle flaky tests.
- "We expose no form of pure sleep in the standard test library". Tests wait on conditions, because "early test-writers made heavy use of sleeps, which led to a number of fragile tests."

**John Carmack** on static analysis: "The most important thing I have done as a programmer in recent years is to aggressively pursue static code analysis" ([In-Depth: Static Code Analysis](https://www.gamedeveloper.com/programming/in-depth-static-code-analysis)). For GDScript, the equivalent is the typed compiler plus warnings as errors.

**For this project, the test pyramid looks like this:**

| Layer | Example | Where |
|---|---|---|
| Pure logic | Weapon damage rules, spring maths, argument parsing | `tests/suite.gd` |
| Simulation | `PlayerMotor` in a code-built arena, driven by scripted `MoveInput` | `tests/suite.gd` |
| Scene and integration | Scenes instantiate; arms reach the grips; audio banks load | `tests/suite.gd` |
| Networked | Real dedicated server plus a client | `tests/smoke_multiplayer.sh` |
| Bots (future) | Scripted clients run a match, under simulated lag | not yet |
| Humans | Feel, fun, balance | Playtests and the experimental playlist |

Rules that follow from the evidence:
- Test behaviour through the same entry points the game uses. `PlayerMotor` takes the same `MoveInput` from tests and from the keyboard.
- Wait on conditions or a fixed number of physics ticks, never on wall-clock sleeps.
- Quarantine a new flaky test rather than letting it make the build red at random.
- Keep the whole suite fast enough to run before every push (currently a few seconds).

## 5. Performance and multiplayer practice

**Performance:**
- Use [Godot's general optimisation guide](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html): "**Always use profiling and timing to guide your efforts.**"
- The bottleneck is often on the GPU, where a CPU profiler can't see it. Use the visual profiler or a GPU tool such as RenderDoc or Nsight.
- When you can't tell where time goes, bisect by disabling half of the work.
- Set budgets for the minimum-spec machine, not your development machine.
- A shooter that feels like Titanfall should hold 144 Hz on mid-range hardware. That means about 6.9 ms of CPU *and* GPU time per frame, with headroom for spikes.

**Testing under bad networks:**
- [netfox's NetworkSimulator](https://foxssake.github.io/netfox/latest/netfox.extras/guides/network-simulator) and LaggyMultiplayerPeer (Godot ≥ 4.4) add latency and packet loss inside Godot.
- `tc netem` (Linux) and clumsy (Windows) do it at the OS level.
- Test every netcode change at about 100 ms latency with 1–2 % loss, not just on localhost. Prediction and lag compensation bugs only show up there.

**Protocol compatibility:** changing an RPC signature or a replicated property breaks old clients against new servers. Until releases are versioned, client and server must come from the same commit. Once community servers exist, the network protocol needs a version number that is checked when a client joins.

## 6. Content, licences and the repo

- **Licences:**
  - Use only CC0 or permissive licences, and read the licence file *inside* the download (lesson recorded in [tooling-2026.md](tooling-2026.md)).
  - Godot itself takes only MIT-compatible code, and warns against reading "source-available" engine code (Unreal, Unity) before contributing ([contribution rules](https://contributing.godotengine.org/en/latest/development/contribution_rules.html)). The same hygiene applies to us.
- **Git LFS** keeps binaries out of git history, but Godot's docs warn that it has to be set up *before* binaries are committed; migrating later "is more in-depth and requires a good understanding of Git" ([Godot: VCS](https://docs.godotengine.org/en/stable/tutorials/best_practices/version_control_systems.html)).
  - GitHub's free tier includes 10 GiB of LFS storage and 10 GiB of download bandwidth a month. Downloads count against the *repository owner*, including every CI checkout and every contributor's clone ([GitHub docs](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-storage-and-bandwidth-usage)).
  - For a public repo with CI on every push, plain git with small, compressed assets is cheaper until the asset set grows a lot.
  - **Current decision:** stay on plain git, keep textures at 1K or 2K, and revisit when the repo passes about 500 MB.
- **Reproducible asset builds:** asset processing is scripted (`tools/fetch_polyhaven.py`, `tools/fix_texture_imports.py`, `tools/build_audio.py`), so anyone can rebuild an asset from its source and a reviewer can see exactly what was done. This is the content equivalent of "no hand-edited build output".

## 7. Playtesting and data

From Valve's talk ([Ambinder, GDC 2009](https://cdn.fastly.steamstatic.com/apps/valve/2009/GDC2009_ValvesApproachToPlaytesting.pdf)):
- Watch what players *do*; don't just ask them. "People don't know why they do what they do", and group Q&A suffers from anchoring and social pressure.
- Playtests are for fun. They are "not bug testing", "not game balancing" and "DEFINITELY not focus testing". Balance comes from stats.
- Collect stats (deaths, times, heatmaps) for an objective, aggregate view, but "averages hide extreme examples" and stats lack context. Combine them with observation.
- "Get data early, get data often. Iterate constantly." Playtesting continues after release.

For a community game:
- A balance proposal states up front what should change in the data. That is the "how we'll know it worked" field in the proposal template.
- It ships to an experimental playlist, and the decision uses both match stats and observed play.
- Votes are one input among several ([community research §3.3](community-and-open-source-ai.md)).

## 8. How Godot game repositories are structured

Godot imposes almost no project structure ([Godot: project organization](https://docs.godotengine.org/en/stable/tutorials/best_practices/project_organization.html)), so we looked at what working projects do. We surveyed 15 open-source Godot games and apps, mostly Godot 4.6–4.7, in November 2026, by reading their repository trees and config files. They range from the official TPS demo and Kenney's FPS starter kit to a commercial Steam game released into the public domain.

| Repo | What it is | Layout | Tests | CI | Git LFS |
|---|---|---|---|---|---|
| [Sunder](https://codeberg.org/sunder/sunder) | Tribes-style multiplayer shooter (4.7) | by type: `scenes/`, `scripts/`, `assets/`, `autoloads/`, `configs/` | **GUT** (`tests/`: health, flags, teams, scoreboard) | none in repo | no |
| [LibreAim](https://codeberg.org/Nokorpo/LibreAim) | FPS aim trainer (4.7) | `modules/` (gameplay manager, main menu, shared) | none | none | no |
| [Thrive](https://github.com/Revolutionary-Games/Thrive) | evolution game, C# (4.7) | `src/` by game stage, `simulation_parameters/` for balance data, `test/` | **gdUnit4** and C# tests | custom CI image; pre-commit | **self-hosted** |
| [Super Tux Party](https://gitlab.com/SuperTuxParty/SuperTuxParty) | online party game (4.2) | `client/`, `server/`, `common/`, `plugins/` (each minigame and board is a plugin) | none | exports for every platform plus a Linux server | GitLab |
| [Source of Mana](https://github.com/sourceofmana/sourceofmana) | 2D MMORPG (4.7) | `sources/` (code by system), `data/` (art, maps, database) | none | **exports on every push**, dev builds to itch.io | no (art sources in a separate repo) |
| [Reia](https://github.com/Quaint-Studios/Reia) | action RPG with an MMO mode (4.7) | `godot/` subfolder with `client/`, `server/`, `core/`; plus `rust/` and `sql/` | none | exports (Windows, Linux, Mac, server) | **self-hosted** |
| [Worlds Upon The Wind](https://github.com/max99x/wutw-public) | commercial Steam game released CC0 (4.7) | `wutw/` project folder by system (`cards/`, `run/`, `hub/`…), `art_src/` outside it, C++ GDExtension | none | shell scripts that build and upload to Steam | source PSDs and WAVs only |
| [Pixelorama](https://github.com/Orama-Interactive/Pixelorama) | pixel-art editor (4.7) | `src/` by area (`UI/`, `Tools/`, `Autoload/`) | none | **gdformat, gdlint, codespell**; dev and release exports | no |
| [TPS demo](https://github.com/godotengine/tps-demo) | Godot's official third-person shooter demo (4.7) | by feature: `player/`, `enemies/red_robot/{audio,laser}`, `level/` | none | file-format check (UTF-8, LF, trailing spaces) | no |
| [Starter Kit FPS](https://github.com/KenneyNL/Starter-Kit-FPS) | Kenney's FPS template (4.6) | by type: `objects/`, `scripts/`, `models/`, `sounds/` | none | none | no |
| [Open RPG](https://github.com/gdquest-demos/godot-open-rpg) | GDQuest's RPG demo (4.7) | `src/` code plus content folders (`combat/`, `overworld/`) | none | none | no |
| [A Dark Forest](https://github.com/TinyTakinTeller/GodotProjectZero) | incremental game (4.4) | `scenes/`, `resources/`, `global/` | none | **gdlint** | no |
| [Tanks of Freedom II](https://github.com/P1X-in/Tanks-of-Freedom-3-D) | voxel strategy game (4.4) | `scenes/`, `scripts/`, `campaign/`, `tools/` | none | none | no |
| [OpenLiberty](https://github.com/FOSS-Supremacy/OpenLiberty) | GTA III reimplementation (4.7) | `scripts/core`, `prefabs/`, `mods/` (cars, weapons) | none | none | no |
| [Librerama](https://codeberg.org/Yeldham/librerama) | minigame collection (4.6) | `nanogames/` (one folder per minigame), `managers/`, `places/` | none | none | no |

**What nearly everyone does (our repo already does all of this):**
- `project.godot` sits at the repo root. Projects whose repo also holds native code or a separate server move it to a subfolder: `wutw/`, `godot/`.
- **`.import` files are committed** in 15/15 repos, and `.uid` files in every 4.4+ project. `.godot/` is always ignored.
- Third-party code goes in `addons/` (11/15). One project, OpenLiberty, nests a whole controller template there.
- **Content as data:**
  - Thrive keeps balance in `simulation_parameters/`.
  - Worlds Upon The Wind has one `Resource` file per card, relic and event.
  - Source of Mana edits its database in an editor tab.
  - We do the same with `game/weapons/data/*.tres` and `game/player/movement/*.tres`.

**Where they differ, and what we chose:**
- **Feature folders vs type folders.**
  - By feature or system: the official demo, the commercial game, Thrive, Source of Mana and most of the larger projects. Godot's docs also recommend grouping assets "as close to scenes as possible".
  - By type (`scenes/` vs `scripts/`): smaller projects such as Sunder, Kenney's kit and Tanks of Freedom II.
  - Ours is by feature (`game/player/`, `game/weapons/`, `game/world/`). Keep it.
- **Third-party art location.** Super Tux Party puts each asset next to the scene that uses it. Godot's docs allow either, as long as it's consistent. We keep third-party art grouped by source (`game/assets/polyhaven/`, `…/quaternius/`), because our fetch and build scripts and CREDITS.md work per source.
- **Client/server split.** Super Tux Party and Reia split their code into `client/`, `server/` and `common/`. Sunder and we use one codebase with authority checks, which Godot's high-level multiplayer is built for. A split starts to pay off when the dedicated-server build needs to strip client-only content.
- **Autoloads (global singletons).** Counts range from 1 to 29, with a median of 5.
  - Open RPG and Worlds Upon The Wind use dedicated "event bus" singletons, such as `CombatEvents` and `run_signals.gd`.
  - Godot's [scene organization](https://docs.godotengine.org/en/stable/tutorials/best_practices/scene_organization.html) guide recommends autoloads only for truly global systems.
  - We have two (`Network`, `Settings`). Add more only with a reason.
- **`export_presets.cfg`.** It's committed in 9/15 repos, mostly the ones that export in CI. Since Godot 4.1, export credentials live in `.godot/export_credentials.cfg`, not in this file ([Godot: VCS](https://docs.godotengine.org/en/stable/tutorials/best_practices/version_control_systems.html)), so committing it is safe. We'll commit it when we add exports.

**Typing warnings.**
- 6/15 tighten Godot's warnings:
  - Sunder makes shadowing and unreachable code errors.
  - Source of Mana treats every warning as an error.
  - Worlds Upon The Wind, Reia, Librerama and A Dark Forest raise `untyped_declaration` to a warning.
- Two others only relax them.
- Our `untyped_declaration = error` is at the strict end, alongside Sunder and Source of Mana.

**Testing and tooling are rare.**
- **Tests:** only Sunder (GUT) and Thrive (gdUnit4) have automated tests. Sunder's README runs them with `godot --headless -s addons/gut/gut_cmdln.gd -gdir tests/ -gexit`. Sunder is the project most like ours, which makes GUT the natural choice if we outgrow our own runner.
- **Lint in CI:** only Pixelorama (`gdformat --diff`, `gdlint`, codespell), A Dark Forest (`gdlint`) and the TPS demo (a text-format script).
- **Licence checks:** Super Tux Party's `check_license.py` checks that every asset is listed in a licence file. We adopted the same idea as a test.

**Git LFS is the minority choice, and it has a cost.**
- Only 4/15 use it.
- Thrive and Reia run their *own* LFS servers.
- Thrive's guide warns that "it is not possible [to] commit changes to Git LFS if you are not a team member", which is real friction for outside contributors.
- Worlds Upon The Wind uses LFS only for source files (PSDs, WAVs), not the assets the game loads.
- Source of Mana keeps art source files in a separate repository.
- This supports our current choice: plain git, compressed runtime assets in the repo, and no large source files (`.blend`, `.psd`) inside the Godot project.

**Release engineering is where we're behind.** Five projects export builds in CI:
- Source of Mana, Super Tux Party and Reia use the [barichello/godot-ci](https://github.com/abarichello/godot-ci) container or cached export templates.
- Super Tux Party and Reia build a separate dedicated-server export.
- Source of Mana uploads a dev build of every push to itch.io.

Worlds Upon The Wind adds what a shipped game needs:
- An exporter plugin that stamps the git commit into builds.
- An in-game bug reporter that sends logs, the save file and a screenshot.
- A debug console.
- An editor dock that starts the game from any story point.

These are on our roadmap.

**How contributions are governed:**
- **Sunder** (the closest project to ours):
  - Requires AI disclosure, and states that "an AI agent may not contribute directly to the project", which is stricter than our opt-in rule.
  - AI-only changes must be "non-creative".
  - Grants repository membership after one merged PR.
- **Source of Mana:** asks people to chat before "anything bigger than a trivial fix" and refuses AI-generated assets.
- **Super Tux Party:** requires sign-off and licence-file updates, and uses a `dev` integration branch.
- **Thrive:** has a PR testing checklist and an `AGENTS.md` for AI coding tools, the equivalent of our `CLAUDE.md`.

## 9. What we adopted, deferred and rejected

**Adopted in this change:**

| Change | Why |
|---|---|
| `untyped_declaration` is an **error** (`project.godot`) | Turns the "static typing everywhere" convention into something the compiler checks (Carmack; Godot static typing docs). Five `for` loops needed types. |
| The test runner compiles **every** script first | A script no test loads could otherwise ship broken. This is the equivalent of `tsc --noEmit`. |
| `gdlint` 4.5.0 in CI, with a pinned version and `gdlintrc` | Cheap, catches order and naming drift. Line limit 120 (the style guide asks for under 100; 120 is the hard ceiling). |
| Optional `.pre-commit-config.yaml` | Same idea as Godot's pre-commit setup, for people who want failures before pushing. |
| Contributing guide rewritten around problem-first issues, one-change PRs, a PR description checklist, review order, profiler evidence for performance work, network-condition testing and MRP bug reports | Godot, Luanti, Rare, Riot and Valve evidence above. |
| "Where things go" rules in contributing.md: feature folders, snake_case for new files, third-party code in `addons/`, source art outside `res://`, few autoloads | Repo survey (§8) and Godot's project organization guide. |
| Test: every file under `game/assets/` is covered by a path in CREDITS.md | Super Tux Party's `check_license.py`; provenance checked by CI, not memory. |

**Deferred:**

| Item | Revisit when |
|---|---|
| GUT or gdUnit4 instead of the custom runner | The suite needs per-file runs, fixtures or reports (it has 89 checks now). |
| Automated performance benchmarks in CI | We have a GPU runner. Headless CI only measures CPU, and noisily. |
| Network simulator in tests | Client prediction lands (it's on the roadmap). |
| Crash reporting (sentry-godot) | There is a release build and a privacy policy, with opt-in. |
| Git LFS | The repo passes about 500 MB, or contributors complain about clone size. If we do, use it only for runtime assets: only 4 of 15 surveyed repos use it, and external contributors can't push to a self-hosted LFS server. |
| Export presets and CI builds (client and dedicated server), with the git commit stamped into each build | We have something to playtest outside the editor. This is the next step, following the Source of Mana, Super Tux Party and Reia pattern. |
| In-game bug reporter, debug console | The first public playtest (Worlds Upon The Wind pattern). |

**Rejected for now:**
- **Enforcing `gdformat`.** It would rewrite 16 of our 21 scripts, including awkward dictionary layouts, and it's a third-party tool rather than Godot's own. Unlike Prettier, it isn't a near-universal default. The style guide plus `gdlint` covers what matters. Revisit if formatting starts to clutter reviews.
- **The `unsafe_*` warnings as errors.** They flag about 100 places today, mostly `Dictionary` results from physics ray queries and RPC payloads. That costs more than it catches right now. Turn them on one by one as code gets typed wrappers.

**Open decision for maintainers:** whether to move our AI policy towards Godot's and Luanti's stricter rules (§3). Our current policy was a deliberate choice for a project bootstrapped with an AI agent. It should be revisited before the community channels open, because that's when the review load starts.

## Sources

**Godot:**
- [Contributing site](https://contributing.godotengine.org/en/latest/): [best practices](https://contributing.godotengine.org/en/latest/development/engine/best_practices.html), [contribution rules and AI policy](https://contributing.godotengine.org/en/latest/development/contribution_rules.html), [review guidelines](https://contributing.godotengine.org/en/latest/development/workflows/review_guidelines.html), [merge guidelines](https://contributing.godotengine.org/en/latest/development/workflows/release_management/merge_guidelines.html), [optimization](https://contributing.godotengine.org/en/latest/development/engine/optimization.html), [compatibility](https://contributing.godotengine.org/en/latest/development/engine/compatibility.html), [issue reports](https://contributing.godotengine.org/en/latest/feedback/issues/issue_report_writing.html), [bisecting](https://contributing.godotengine.org/en/latest/feedback/issues/bisecting.html)
- [CONTRIBUTING.md](https://github.com/godotengine/godot/blob/master/CONTRIBUTING.md), [.pre-commit-config.yaml](https://github.com/godotengine/godot/blob/master/.pre-commit-config.yaml)
- Docs: [GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html), [static typing](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/static_typing.html), [warning system](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/warning_system.html), [version control](https://docs.godotengine.org/en/stable/tutorials/best_practices/version_control_systems.html), [general optimization](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html), [profiler](https://docs.godotengine.org/en/stable/tutorials/scripting/debug/the_profiler.html), [physics interpolation](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/physics_interpolation_introduction.html)

**Tools:**
- [godot-gdscript-toolkit](https://github.com/Scony/godot-gdscript-toolkit) (gdlint, gdformat)
- Test frameworks: [GUT](https://github.com/bitwes/Gut), [gdUnit4](https://github.com/MikeSchulze/gdUnit4)
- [netfox network simulator](https://foxssake.github.io/netfox/latest/netfox.extras/guides/network-simulator)
- [sentry-godot](https://github.com/getsentry/sentry-godot) and its [1.0 announcement](https://blog.sentry.io/introducing-sentrys-godot-sdk-1-0-alpha-with-support-for-godot-4-5-beta)
- [GitHub LFS billing](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-storage-and-bandwidth-usage)

**Surveyed Godot repositories** (§8; trees and config files read on 1 Nov 2026):
- Games and demos: [Sunder](https://codeberg.org/sunder/sunder), [LibreAim](https://codeberg.org/Nokorpo/LibreAim), [Thrive](https://github.com/Revolutionary-Games/Thrive), [Super Tux Party](https://gitlab.com/SuperTuxParty/SuperTuxParty), [Source of Mana](https://github.com/sourceofmana/sourceofmana), [Reia](https://github.com/Quaint-Studios/Reia), [Worlds Upon The Wind](https://github.com/max99x/wutw-public), [TPS demo](https://github.com/godotengine/tps-demo), [Starter Kit FPS](https://github.com/KenneyNL/Starter-Kit-FPS), [Open RPG](https://github.com/gdquest-demos/godot-open-rpg), [A Dark Forest](https://github.com/TinyTakinTeller/GodotProjectZero), [Tanks of Freedom II](https://github.com/P1X-in/Tanks-of-Freedom-3-D), [OpenLiberty](https://github.com/FOSS-Supremacy/OpenLiberty), [Librerama](https://codeberg.org/Yeldham/librerama)
- App: [Pixelorama](https://github.com/Orama-Interactive/Pixelorama)
- Selected from [awesome-godot](https://github.com/godotengine/awesome-godot)
- Godot docs: [project organization](https://docs.godotengine.org/en/stable/tutorials/best_practices/project_organization.html), [scene organization](https://docs.godotengine.org/en/stable/tutorials/best_practices/scene_organization.html)

**Other open-source games:**
- Luanti: [CONTRIBUTING](https://github.com/luanti-org/luanti/blob/master/.github/CONTRIBUTING.md), [AI policy](https://github.com/luanti-org/luanti/blob/master/doc/developing/ai_policy.md), [direction](https://github.com/luanti-org/luanti/blob/master/doc/direction.md)
- Veloren: [CONTRIBUTING](https://gitlab.com/veloren/veloren/-/blob/master/CONTRIBUTING.md)

**Industry:**
- Rare: [Masella, GDC 2019](https://www.gdcvault.com/play/1026366/Automated-Testing-of-Gameplay-Features); [Game Developer on Rare's testing](https://gamedeveloper.com/design/how-rare-automates-testing-for-ai-and-more-in-sea-of-thieves-part-4-of-4-)
- Riot: [Automated Testing for League of Legends](https://www.riotgames.com/en/news/automated-testing-league-legends)
- Valve: [Ambinder, GDC 2009 slides](https://cdn.fastly.steamstatic.com/apps/valve/2009/GDC2009_ValvesApproachToPlaytesting.pdf); [latency compensation](https://developer.valvesoftware.com/wiki/Latency_Compensating_Methods_in_Client/Server_In-game_Protocol_Design_and_Optimization)
- Blizzard: [Ford, GDC 2017](https://gdcvault.com/play/1024001/-Overwatch-Gameplay-Architecture-and); [Edgegap summary](https://edgegap.com/blog/game-backend-deep-dive-overwatch-2016-netcode-architecture-rollback)
- [Carmack, In-Depth: Static Code Analysis](https://www.gamedeveloper.com/programming/in-depth-static-code-analysis)
- [Fiedler, Fix Your Timestep!](https://gafferongames.com/post/fix_your_timestep/); [Gambetta, client-server game architecture](https://www.gabrielgambetta.com/client-server-game-architecture.html); [Nystrom, Game Programming Patterns](https://gameprogrammingpatterns.com/game-loop.html)
