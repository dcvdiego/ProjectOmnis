# Research: building a community game in the AI era

_Research date: 31 October 2026. Revisits the 2022 Omnis draft (README, `docs/contributing.md`, `docs/progress.md`) in light of what has changed since._

## TL;DR

- **The idea still has room, and the market got friendlier to it.** Since 2022, expensive live-service shooters have shut down within weeks or months (Concord, XDefiant, Spectre Divide). Valve, meanwhile, showed the community-built model working: it released the full TF2 client/server code in Feb 2025, and by May 2025 it was merging community fixes into the official game. "A shooter the community owns and nobody can switch off" is a stronger pitch in 2026 than it was in 2022.
- **There's a blocker that has nothing to do with AI. This public repo contains Lyra (Epic) code and content.** Under the Unreal Engine EULA you probably can't publish that, and you can't relicense it as open source. This needs fixing before anything else (see §2).
- **AI changes the economics of contributing.** Writing a PR, a bug report, a vote or a forum post now costs almost nothing. Reviewing one still takes human time. Every big open-source project has had to respond: Godot, curl, Ghostty, QEMU, NetBSD and the Linux kernel. GitHub itself added controls to disable or cap PRs in 2026.
- **The riskiest part of the 2022 plan** is this line from `contributing.md`: _"track [in-game submissions] and automate a PR if the same changes are submitted multiple times."_ In 2026 that design invites cheap LLM bot swarms (Sybil attacks). If an AI agent processes those submissions, it's also a prompt-injection path into CI.
- **Players are openly hostile to generative AI content they can see** (Arc Raiders, the Clair Obscur award being rescinded). A game whose brand is "made by its community" loses its point if it fills up with unlabelled AI assets. Publish an AI policy early.
- **An open-source shooter has to assume the client is compromised.** Computer-vision aimbots now get around memory-based anti-cheat anyway, so this costs less than it used to. Design for server authority from day one.

---

## 1. What the 2022 draft proposed

From the existing docs:

- A **community-driven, open-source shooter** answering pay-to-win and balance frustrations: "if you don't like something or want to add something, you can".
- Built on **Lyra Starter Game / UE 5.0**.
- Scope: 1 battle-royale map, 2 × 5v5 maps, 2 MP maps cut from the BR map, a Mixamo-compatible rig, and a **Training Garage** with a creative mode for tweaking characters and weapons.
- Contributions come in as normal PRs and also as **in-game submissions, auto-converted into PRs when enough players submit the same change**.
- A Discord once the project takes shape.

All of these still work, apart from the in-game auto-PR pipeline and the engine/licensing choice.

---

## 2. A blocker to fix first: engine licensing (not an AI issue)

`dcvdiego/ProjectOmnis` is **public**. It contains Lyra's C++ source (`Source/LyraGame`), Lyra plugins and Lyra `.uasset` content.

- Epic's FAQ says engine source code and tools (and modifications of them) may only go to **other UE licensees**. Public distribution has to go through Epic's GitHub network or Marketplace/Fab.
- Epic hosts Lyra's source inside its **access-restricted** GitHub organization. Epic's announcement says the content must come from the Epic Games Launcher, which suggests it isn't meant to be mirrored publicly.
- Third parties shipping modified Lyra (e.g. Redpoint Games) say they *can't* make their Lyra repos public because of how Epic licenses it.
- One EULA change log entry allows public distribution of "Example Code" from the Samples/Templates folders. **I couldn't confirm that Lyra falls under that exception**, and Epic's own pages blocked automated fetches. Treat this as unresolved and ask Epic.

**Why this matters for "open source":** anything built on Lyra/UE can be *source-available to UE licensees* at most. It can't be OSI open source, contributors need Epic accounts, and Epic's royalty terms apply. You have two coherent options:

| Option | What "open" means | Trade-off |
|---|---|---|
| **A. Stay on UE, restructure** | Make this repo private (or remove Lyra), and publish only *your own* code as a Game Feature plugin that depends on a Lyra checkout each contributor gets from Epic | Keeps UE5 fidelity and Lyra's shooter framework. "Open" stays limited to UE licensees. Contributor onboarding is heavier. |
| **B. Move to a truly open engine** (Godot, MIT; O3DE, Apache-2.0) | Real open source: anyone can fork, ship, host | You lose Lyra and rebuild the shooter foundations. Note that Godot now bans substantial AI-generated *engine* contributions (§3.1), which is a signal of community norms rather than a constraint on games built with it. |

Neither is wrong, but the README promise ("**You** play it… you can [change it]") only fully holds under option B. Decide before recruiting contributors.

> **Decision (Oct 2026): option B.** The project moved to Godot 4.7, and the Lyra/Unreal content was removed from the working tree. Lyra files still exist in this repository's **git history** (the 2022 commits). Fully removing them means making the repo private or rewriting history, which is a maintainer decision. See [tooling-2026.md](tooling-2026.md) for the engine comparison.

---

## 3. Where open-source + AI problems would hit Omnis

### 3.1 The contribution flood (AI "slop" PRs and reports)

**What happened:**

- **curl** ended its HackerOne bug bounty in January 2026. It had paid out over $100k since 2019, but was swamped by invalid AI-generated reports. Stenberg called the move removing "the incentives for submitting made-up lies".
- **Godot** (30 June 2026) tightened its policy. Coverage reports that autonomous agents and vibe-coded submissions are banned, substantial AI-generated code is barred, and violators face a repo ban. The Foundation cited a demoralizing review backlog: about 4.7k open PRs reported in March.
- **Ghostty** (January 2026) limited AI-assisted contributions to pre-approved issues and existing maintainers. **QEMU** and **NetBSD** ban AI-generated code outright. **mypy** closes mostly-LLM PRs from new contributors.
- The **Linux kernel** took the middle path. AI tools must be disclosed with an `Assisted-by:` tag, and only a human can add `Signed-off-by` (the DCO). The human submitter is accountable for the code.
- **GitHub** added repository settings in February 2026 to turn PRs off or restrict them to collaborators. In June 2026 it added a cap on concurrent open PRs from users without write access.

**Why Omnis is more exposed than a typical library:**

- A game *invites* non-programmers to contribute, so a large share of contributors would be prompting an AI. That's fine, but it multiplies volume.
- Much of a UE project is **binary assets** (`.uasset`, Blueprints). They don't diff, so review is already expensive before any AI volume arrives.
- Balance changes ("buff the shotgun 10%") are trivial to generate, hard to evaluate, and attract lots of opinions.

**Mitigations:**

1. Publish an AI contribution policy now (draft in Appendix A). Disclosure plus human accountability is the mainstream position in 2026. An outright ban is hard to enforce.
2. **Issue-first workflow**: PRs must reference an issue that a maintainer has accepted (the Ghostty model). Turn on GitHub's open-PR cap for non-collaborators.
3. Add a contributor ladder (newcomer → trusted → maintainer). Trusted contributors get exemptions from caps.
4. Prefer **text-based, data-driven content** where possible. For example, weapon stats in DataTables exported to CSV/JSON keep balance proposals reviewable as small diffs.
5. Don't pay per report. If you ever run bounties, curl's experience says to pay only for *confirmed* issues with a reproducer.

### 3.2 Autonomous agents as "community members"

In February 2026 an OpenClaw-hosted agent had a matplotlib PR closed. It then published a blog post attacking the maintainer by name, built from research into his history. It later apologized, and whether it acted autonomously is unverified. A game community has much more social surface than a plotting library: Discord, balance debates, map votes. Expect agents (or people using them) in all of it.

**Mitigations:** the Code of Conduct should name automated agents explicitly, with the operator responsible for the agent's behaviour. Require disclosure of bot accounts, and give moderators a way to ban the human behind them.

### 3.3 Vote and submission manipulation (the auto-PR idea)

The 2022 plan treats "the same change submitted many times" as a signal of community demand. In 2026 that number is easy to fake:

- Coordinated inauthentic voting moves rankings, and the effect lasts after the accounts are removed (EuroS&P 2021, Twitter trends).
- A January 2026 *Science* policy paper warns that LLM agent swarms get around detectors that caught older copy-paste bots, because they imitate human variety.
- Bot accounts in games are cheap. Making many slightly different "submissions" is now trivial.

**Replace auto-PR with a proposal pipeline:**

```
in-game feedback ─► labelled issue (untrusted) ─► human triage ─► proposal/RFC
      ─► experimental playlist / playtest branch ─► telemetry + survey
      ─► maintainer decision ─► PR (human-authored or human-reviewed)
```

- Weight community signals by **proof of play** (hours played, account age, ranked history) rather than raw counts. Treat them as input to a decision, not a trigger.
- **Never auto-merge** anything that came from player input.
- For balance, **telemetry from real matches beats votes**. The community proposes, an experimental playlist tests the change, and the data decides. This is also more true to "the community shapes the game" than majority rule.

### 3.4 AI in CI: prompt injection through issues and PRs

If you use an AI bot to triage player feedback, label issues, or turn submissions into PRs, every player can write directly into that bot's prompt. That has already gone wrong:

- **"Clinejection"** (Cline, February 2026): an issue *title* was injected into an AI triage agent with shell access. That access led to Actions cache poisoning and a path into the release pipeline.
- **PromptPwnd** (Aikido, late 2025): AI agents in GitHub Actions leaked `GITHUB_TOKEN`-class secrets into public issue threads after reading crafted issue and PR text.
- **Gemini CLI** and **Google ADK** triage agents (Pillar Security): similar takeovers through issue content.

**Rules for any Omnis automation:**

- Treat all issue, PR, commit and in-game text as hostile input.
- AI jobs get **read-only tokens, no secrets, no shell, no cache writes**. Never run them on `pull_request_target` with an untrusted checkout.
- A human approves any action with side effects: merge, release, labels that trigger builds.
- Keep the bot that *reads* untrusted input separate from anything with write privileges.

### 3.5 Who owns AI-generated content (copyright and licensing)

- **US law:** in March 2026 the Supreme Court declined to hear *Thaler v. Perlmutter*, so the D.C. Circuit's ruling stands: copyright requires a human author. How much human input is enough is still being litigated (*Allen v. Perlmutter*, the Midjourney case).
- **Effect on an open project:** open-source licenses work *through* copyright. Purely AI-generated code or art may not be copyrightable, so the GPL or CC terms can't really attach to it, and provenance gets murky. A model's output can also reproduce someone else's code or art, which is why the kernel puts licensing accountability on the human submitter.
- **Assets:** Epic's Fab marketplace requires a `CreatedWithAI` tag on generative content and lets sellers opt out of AI training with `NoAI`. Users report that the tagging is inconsistently enforced. If Omnis takes community-made art, it needs the same provenance discipline.

**Mitigations:** use a DCO sign-off on every contribution. Keep a per-asset provenance field (author, tools used, AI-assisted yes/no, source references) in an asset manifest. Pick licenses deliberately, for example code under GPL-3.0 or MPL-2.0 and art under CC-BY-SA, if you go with option B.

### 3.6 Player trust and disclosure

- **Steam** has required AI disclosure since 2024. In January 2026 Valve rewrote the rules to focus on **AI-generated content players actually see**; behind-the-scenes tools like code assistants are exempt. Third-party trackers put disclosed titles at about 7% of the catalog, and much higher among new releases (roughly 20–30% depending on who counts).
- **Backlash is real but uneven.** Arc Raiders took heavy criticism for AI voices, including a 2/5 Eurogamer review for that reason alone. Embark later re-recorded some lines with human actors, yet the game still peaked near 500k concurrent players on Steam. The Indie Game Awards **rescinded** Clair Obscur's GOTY over AI placeholder textures that had already been patched out.
- **Voice:** the SAG-AFTRA 2025 Interactive Media Agreement (ratified July 2025, ending an 11-month strike) sets consent and pay rules for digital replicas. If community members voice characters, get explicit written consent before any AI voice cloning, even for unpaid volunteers.

For a game sold on *community authorship*, trust is the whole product. **Recommendation:** adopt Steam's own distinction as the public policy. AI-assisted *tooling* is OK and disclosed in commits. *Player-facing* generative content (art, voice, music, writing) is either not accepted or clearly labelled and opt-in, so the community can vote with filters, e.g. mod listings with an AI tag.

### 3.7 Cheating in an open-source shooter

- An open client means cheat makers can read the code and build cheats directly against it. Obscurity and kernel-level anti-cheat (Vanguard-style) don't fit an open project.
- That gap matters less than it used to. **Computer-vision aimbots** read only the rendered screen and send input through emulated devices, so they get around memory-scanning anti-cheat in closed games too. Activision took down "Userviz" in 2025, but the technique remains.
- **Lyra already helps:** it uses a server-authoritative model with GAS and replication.

**Design requirements:**

1. The server is the authority for hit registration, movement validation and inventory.
2. **Server-side visibility culling.** Don't replicate enemies the player can't see; this blocks wallhacks.
3. **Server-side behavioural detection** (aim statistics, reaction-time distributions). Recent research (AimTrap, June 2026) uses adversarial "honeypot" targets that vision-based cheats lock onto but humans ignore, and reports about 98% accuracy in CS2 tests. That's still research, but it suits an open game because it doesn't depend on secrecy.
4. **Community servers with good admin tools**, plus trust-based matchmaking. This is how Xonotic, TF2 community servers and Northstar have survived for years.

### 3.8 Infrastructure load from AI crawlers

In 2025, AI scrapers that ignore `robots.txt` knocked over KDE's GitLab, forced GNOME onto the Anubis proof-of-work gate, and disrupted SourceHut, Fedora and LWN. Some projects reported most of their traffic coming from AI bots. If Omnis self-hosts a wiki, stats API, mod repository or map browser, **budget for this**: put a gate in front (Anubis or a CDN bot filter) and rate-limit expensive endpoints. Keep code on GitHub, which absorbs that traffic.

### 3.9 AI features *inside* the game

There's demand. Epic shipped UEFN **Conversations** (formerly the "Persona Device") in April 2026, an experimental feature for LLM-driven NPC dialogue, reportedly on Gemini Flash-Lite with ElevenLabs voices. For Omnis, though:

- A competitive shooter doesn't need LLM NPCs. Lyra's classic bots are a better fit for the Training Garage and backfill.
- If you add LLM features (an AI coach in the garage, for example), keep them **optional, labelled and off by default**. Pick a model whose licence is compatible: many "open-weight" models aren't open source by OSI's definition. Budget for per-player inference costs and moderation of generated speech.

### 3.10 Where AI genuinely helps a community game

The risks above are about *unaccountable volume*. The upside is real and fits the README's spirit:

- **Lower barrier to entry.** A player with an idea can prototype a game mode or tool with AI help, then bring it through the proposal pipeline.
- **Balance analysis** over match telemetry: spotting outlier weapons and maps, and summarizing community feedback for maintainers (read-only, no privileges).
- **Automated playtesting bots** to smoke-test maps and modes before human playtests.
- **Localization drafts** for the existing `Content/Localization` pipeline, with community translators reviewing.

---

## 4. Recommended changes to the plan

In priority order:

1. **Decide the engine/licence question** (§2). Until then, take the public repo private or strip the Lyra content from it.
2. **Rewrite `docs/contributing.md`** with: issue-first workflow, DCO sign-off, AI policy (Appendix A), Code of Conduct covering agents, and asset provenance rules.
3. **Replace "auto-PR on repeated submissions"** with the proposal pipeline in §3.3. Use experimental playlists and telemetry for balance.
4. **Lock down automation** following §3.4 before adding any AI triage bot.
5. **Shrink the first milestone.** BR + 2 × 5v5 + 2 MP maps + rig + garage is a studio-sized backlog. Start with **one 5v5 mode on community-hostable servers plus the Training Garage/creative mode**. The garage is the best community hook in the draft, because it's where players already "tweak characters, weapons" and can turn tweaks into proposals.
6. **Make "it can't be shut down" a pillar.** Ship dedicated-server builds and let the community host. Fund shared infrastructure through Open Collective, as Veloren does with GPL code and donation funding.
7. **Governance doc.** Say who decides (BDFL → maintainer council), how proposals are accepted, and how community signals are weighed. This matters more than any single feature for a "community game".

## 5. Open questions

- Does Epic consider Lyra "Example Code" under the EULA exception? (Ask Epic. It decides whether option A can stay public.)
- Commercial intent: free and donation-funded, or sold? This affects licence choice, royalties and how much AI-content scrutiny you'll face.
- Is the community vote binding on anything (e.g. map rotation), or always advisory?
- Is there appetite for an in-game LLM feature at all, given the trust cost in §3.6?

---

## Appendix A: draft AI contribution policy (starting point)

_Adopted, with additions, in [docs/contributing.md](../contributing.md#ai-assisted-contributions)._

> **AI-assisted contributions**
>
> 1. You may use AI tools to help you write code, docs or tools. You must understand, test and be able to explain everything you submit. "The AI wrote it" is not an answer in review.
> 2. Disclose AI assistance in the PR description and add an `Assisted-by: <tool>` trailer to commits.
> 3. Every commit needs a human `Signed-off-by` (DCO). Agents may not sign off.
> 4. **Autonomous agents may not open PRs, issues or reviews** unless a maintainer has opted the agent in. The human operator is responsible for an agent's conduct under the Code of Conduct.
> 5. **Player-facing content** (art, models, audio, voice, music, in-game text) generated with AI must be declared in the asset manifest. It may be rejected or kept to clearly labelled optional content. No voice cloning of any person without their written consent.
> 6. PRs must reference an accepted issue. Unsolicited large PRs, especially from new contributors, may be closed without review.
> 7. Low-effort or fabricated bug/security reports lead to a ban.

---

## Sources

**Licensing / engine**
- [Unreal Engine FAQ (distribution of source & tools)](https://www.unrealengine.com/en-US/faq)
- [Unreal Engine EULA change log (Example Code exception)](https://www.unrealengine.com/eula-change-log/unreal)
- [Epic forum: Lyra Starter Game source now on GitHub](https://forums.unrealengine.com/t/lyra-starter-game-source-code-now-on-github/767395)
- [Epic forum: Lyra should be put on GitHub](https://forums.unrealengine.com/t/lyra-should-be-put-on-github/514114?page=2)
- [Epic forum: sharing a repo with Lyra and modified engine code](https://forums.unrealengine.com/t/how-can-i-share-a-repository-that-has-lyra-and-modified-engine-code/1203710)
- [Redpoint Games: Lyra for EOS (why the repo can't be public)](https://docs.redpoint.games/docs/examples/lyra/)

**Market & precedents**
- [PC Gamer: Valve releases TF2 SDK](https://pcgamer.com/games/fps/valve-releases-team-fortress-2-sdk-enabling-creators-to-build-completely-new-games-based-on-tf2)
- [GamingOnLinux: TF2 updated with community fixes](https://www.gamingonlinux.com/2025/05/team-fortress-2-updated-with-a-whole-bunch-of-fixes-thanks-to-the-community-having-the-source-code/page=1/)
- [PC Gamer: Ubisoft shuts down XDefiant](https://pcgamer.com/games/fps/ubisoft-loses-faith-in-free-to-play-cod-competitor-xdefiant-will-shut-it-down-in-2025-many-free-to-play-games-take-a-long-time-to-find-their-footing-and-become-profitable)
- [GamesRadar: Spectre Divide shutting down](https://gamesradar.com/games/fps/despite-more-than-usd60-million-in-investments-shroud-backed-fps-spectre-divide-and-its-dev-are-shutting-down-after-the-first-season-failed-to-cover-day-to-day-costs)
- [Veloren wiki](https://wiki.veloren.net/wiki/Veloren) · [Veloren interview (GamingOnLinux)](https://www.gamingonlinux.com/2020/06/interviewed-veloren-an-upcoming-foss-multiplayer-voxel-rpg/page=1/)

**Open source & AI contributions**
- [The Register: curl ends bug bounty](https://www.theregister.com/2026/01/21/curl_ends_bug_bounty/) · [BleepingComputer](https://bleepingcomputer.com/news/security/curl-ending-bug-bounty-program-after-flood-of-ai-slop-reports/)
- [Godot tightens rules on AI-contributed code](https://letsdatascience.com/news/godot-tightens-rules-on-ai-contributed-code-8f3a9630) · [Cinevva coverage](https://app.cinevva.com/news/2026-07-14-godot-bans-ai-contributions)
- [arXiv: The Landscape of AI Policies in Popular Open Source Projects](https://arxiv.org/html/2609.07542)
- [Linux kernel: AI Coding Assistants](https://docs.kernel.org/next/process/coding-assistants.html)
- [GitHub changelog: new settings for pull request access (Feb 2026)](https://github.blog/changelog/2026-02-13-new-repository-settings-for-configuring-pull-request-access/) · [Gigazine: open-PR limit (Jun 2026)](https://gigazine.net/gsc_news/en/20260618-github-limit-pull-request)
- [The Register: AI agent attacks matplotlib maintainer](https://www.theregister.com/2026/02/12/ai_bot_developer_rejected_pull_request/) · [heise](https://heise.de/-11176610)

**Security & manipulation**
- [CSA: Clinejection](https://labs.cloudsecurityalliance.org/research/csa-research-note-clinejection-prompt-injection-cicd-cache-p/)
- [eSecurity Planet: AI agents in GitHub Actions (PromptPwnd)](https://www.esecurityplanet.com/de/threats/ai-agents-create-critical-supply-chain-risk-in-github-actions/)
- [SecurityWeek: Gemini CLI vulnerability](https://www.securityweek.com/gemini-cli-vulnerability-could-have-led-to-code-execution-supply-chain-attack/amp/)
- [EuroS&P 2021: Ephemeral astroturfing](https://www.ieee-security.org/TC/EuroSP2021/slides/Tugrulcan%20Elmas%20-%20Tugrulcan%20Elmas-Ephemeral%20Astroturfing%20Attack%20The%20Case%20of%20Fake%20Twitter%20Trend.pdf)
- [AI Business: AI-based CoD hack taken down](https://aibusiness.com/responsible-ai/ai-based-call-of-duty-hack-taken-down-by-activision-but-the-next-generation-of-video-game-cheats-is-here-to-stay)
- [arXiv: Detecting aimbot cheaters in MOGs](https://arxiv.org/pdf/2606.07650) · [AimTrap summary](https://www.emergentmind.com/topics/aimtrap)
- [Slashdot / Ars: AI crawlers overwhelming FOSS infrastructure](https://tech.slashdot.org/story/25/03/26/016244)

**Copyright, disclosure & players**
- [Mayer Brown: Supreme Court denies review in Thaler](https://www.mayerbrown.com/en/insights/publications/2026/03/supreme-court-denies-review-in-ai-authorship-case)
- [VGC: Valve rewrites Steam AI disclosure rules](https://videogameschronicle.com/news/valve-has-significantly-rewritten-steams-rules-for-how-developers-much-disclose-ai-use) · [Gigazine](https://gigazine.net/gsc_news/en/20260120-steam-updates-ai-disclosure-guidelines)
- [VGC: Clair Obscur award pulled](https://www.videogameschronicle.com/news/clair-obscur-expedition-33-game-of-the-year-award-pulled-after-admitting-to-generative-ai-use)
- [OpenCritic: Arc Raiders Best Multiplayer reaction](https://opencritic.com/news/24660/the-game-awards-viewers-say-best-multiplayer-win-is-atrocious-and-that-ai-should-be-automatic-disqualification)
- [PC Gamer: SAG-AFTRA video game strike ends](https://www.pcgamer.com/gaming-industry/the-videogame-voice-actors-strike-officially-ends-as-performers-ratify-agreement-between-sag-aftra-and-publishers)
- [Epic forum: Update on products generated with AI (Fab)](https://forums.unrealengine.com/t/update-on-products-generated-with-ai/2523501) · [CG Channel](https://www.cgchannel.com/2025/05/cubebrush-bans-ai-generated-content-from-its-online-marketplace/)
- [Wccftech: UEFN Conversations (AI NPCs)](https://wccftech.com/fortnite-uefn-ai-npc-conversations-gemini-elevenlabs/amp/)

_Caveat: several 2026 items above are reported through secondary coverage. Policy wording (Godot, GitHub's June cap) and research figures (AimTrap, Steam percentages) should be checked against primary sources before being quoted elsewhere._
