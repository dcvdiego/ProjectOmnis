# Contributing to Project Omnis

Thanks for helping build a game its players own. The rules below exist so that a small group of volunteer maintainers can keep up with a large community. The reasoning behind them is in [research/community-and-open-source-ai.md](research/community-and-open-source-ai.md).

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
4. **Keep PRs small.** One concern per PR. For balance changes, edit the `.tres` file in `game/weapons/data/` and nothing else.

## Before you open a PR

- Run the tests (see the [README](../README.md#run-the-tests)). CI runs them too.
- GDScript: follow the [official style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html). Use static types everywhere, and add `##` doc comments on public functions.
- **Server authority:** anything that decides an outcome (hits, damage, ammo, scoring) must run on the server and validate the sender. See [architecture.md](architecture.md).
- Commit `.gd.uid` / `.import` files that Godot generates. Never commit `.godot/`.
- **Sign off every commit** (`git commit -s`). This certifies the [Developer Certificate of Origin](https://developercertificate.org/): you have the right to submit the work under the project's licences.

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
- Prefer text formats Godot can diff (`.tscn`, `.tres`). Large binaries (textures, audio, models) will move to Git LFS once we have some. Ask in the issue before adding more than a few MB.

## Security

Report vulnerabilities privately through GitHub's "Report a vulnerability" (Security tab), not in public issues. Include a reproducer.

## Code of Conduct

Be decent. Critique ideas, not people. Harassment, brigading and coordinated vote manipulation (sock puppets or bot accounts) get you removed. A fuller Code of Conduct will be adopted before the community channels open.
