# Research: engine and AI tooling (2026)

_Research date: 31 October 2026. Written for a contributor with general software engineering experience but no game-dev background._

## Engine choice

| | **Godot 4.7** (chosen) | s&box | Unreal 5.8 |
|---|---|---|---|
| Open source | Fully (MIT) | Game layer MIT/C#; Source 2 underneath is closed | No. Engine and Lyra can only go to UE licensees |
| Language | GDScript (Python-like) or C# | C#, hot reload | C++ and Blueprints |
| Multiplayer | High-level API built in; [netfox](https://github.com/foxssake/netfox) (MIT) adds rollback and has an FPS example | Built-in networking, made for community games | Lyra gives the most shooter features out of the box |
| Review and AI friendliness | Scenes and resources are **text**: real diffs | Mostly code | Binary `.uasset` files: no diffs |
| Main cost | Build lag compensation and large-map tech ourselves | Platform tie-in to Facepunch | Licensing; steep solo learning curve |

**Why Godot:** it removes the licensing problem (see [§2 of the AI research](community-and-open-source-ai.md#2-a-blocker-to-fix-first-engine-licensing-not-an-ai-issue)). Text-based scenes make community PRs reviewable and work well with AI coding tools, and GDScript is quick to learn for a programmer.

Unreal is still possible for an open-source *game* if the public repo contains only your own permissively licensed (non-GPL) code and assets. Lyra, Fab/Megascans assets and engine modifications have to stay out of it. Epic's 2014 Unreal Tournament was developed that way and stalled when Epic moved its staff to Fortnite.

## MCP servers and connectors

| Tool | What for | Notes |
|---|---|---|
| **Claude Code** | Main coding agent | Use the repo's `CLAUDE.md`; tests run headless |
| Godot MCP (community: [ee0pdt/Godot-MCP](https://github.com/ee0pdt/Godot-MCP), `godot-mcp-server`, `minimal-godot-mcp`) | Read editor state, run the project, get diagnostics | Third-party. Start with the diagnostics-only one; servers that run scripts in the editor need permission prompts left on |
| **Blender**: official Blender Lab MCP server (v1.0, Apr 2026) or Claude's Blender connector | Greybox and model work, batch export to glTF | Avoid the older community `blender-mcp`, which had CVEs in 2026 |
| Adobe connector | Textures and UI art | If you have Creative Cloud |
| GitHub MCP | Issues, proposals, PR triage | Never give an AI triage bot write access or secrets (AI research §3.4) |
| Unreal 5.8 official MCP plugin / Unity MCP | Only relevant if switching engine | Both experimental or beta in 2026 |

## Assets without being an artist

1. **Human-made CC0 packs first:** Kenney, Quaternius. Mixamo for animations.
2. **AI 3D generation for greybox and placeholders only** (see the player-facing content policy in contributing.md):
   - TRELLIS.2 (MIT, self-hosted) has the fewest strings.
   - Meshy and Tripo: free tiers are reportedly non-commercial, and sources disagree, so check their terms.
   - Hunyuan3D's licence reportedly excludes the EU, UK and South Korea.
3. Log everything in `CREDITS.md`.

## Sources

- [PC Gamer: UE 5.8 launches with an MCP plugin](https://pcgamer.com/software/unreal-engine-5-8-launches-with-improved-terrain-and-vegetation-tools-a-lumen-lite-option-for-faster-global-illumination-and-for-the-times-we-now-live-in-an-open-standard-plugin-for-llm-systems/)
- [GamingOnLinux: Godot 4.7 released](https://www.gamingonlinux.com/2026/06/godot-engine-4-7-is-out-bringing-a-new-asset-store-hdr-support-steam-frame-support/comment_id=296481)
- [netfox](https://github.com/foxssake/netfox)
- [PC Gamer: s&box goes open source](https://www.pcgamer.com/gaming-industry/garrys-mod-successor-s-and-box-goes-open-source-and-even-opens-up-the-finances-garry-says-valve-gave-me-my-chance-im-already-rich-i-dont-want-to-f-ck-anyone-over)
- [Unity MCP docs](https://docs.unity3d.com/Packages/com.unity.ai.assistant@2.17/manual/integration/unity-mcp-get-started.html)
- [Anthropic: Claude for creative work](https://anthropic.com/news/claude-for-creative-work)
- [Blender MCP comparison (vendor blog)](https://www.strayspark.studio/blog/official-blender-mcp-server-comparison-2026)
- [Cinevva: AI 3D generators 2026](https://app.cinevva.com/guides/ai-3d-model-generators)
- [Fab licence summary](https://www.fab.com/cla) · [Forum: Can I publish my UE game as open source?](https://forums.unrealengine.com/t/can-i-publish-my-game-made-with-ue4-as-open-source-game/8005)
