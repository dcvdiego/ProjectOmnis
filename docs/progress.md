# Roadmap

The 2022 plan (BR map + 2 × 5v5 + 2 MP maps + rig) was studio-sized. The restart aims at a **vertical slice** first: one small mode that's fun with a handful of people on community-hosted servers. Bigger modes come once that loop works.

## Done

- 2022: initialized repo with Lyra (UE 5.0)
- 2026: research on running a community game in the AI era ([research/](research/))
- 2026: **moved to Godot 4.7**, removed Lyra/Unreal content
- Training Garage greybox: range lanes, cover, platform, target dummies
- First-person controller, rifle + pistol (hitscan, magazines, reloads), data-driven weapon balance
- Host / join / dedicated server, server-authoritative combat, respawns
- Headless unit tests, two-process multiplayer smoke test, CI
- **Movement:** sprint, crouch, slide (slide-hop), double jump, wall-run, wall-jump, mantle, air strafing; tuning in a text resource
- **Feel:** physics interpolation, per-frame camera, remote snapshot interpolation, view-model sway, bob and recoil, landing dip, speed FOV, wall-run camera tilt
- **Look:** CC0 photoscanned materials, HDRI sky, props, realistic weapon models, animated third-person characters, muzzle flash, tracers, impacts, bullet holes
- Graphics presets (Low to Ultra), FOV and sensitivity settings, pause menu

## Next: playable vertical slice

- [ ] Server-side movement validation, then client prediction + lag compensation (evaluate [netfox](https://github.com/foxssake/netfox))
- [ ] Server-side visibility culling (don't replicate enemies a player can't see)
- [ ] Sync current state to late joiners (other players' health and weapons)
- [ ] Simple FFA / TDM scoring and round loop
- [ ] First small arena map (greybox), 2–8 players
- [ ] Audio: CC0 weapon, footstep and impact sounds (e.g. Sonniss GDC bundles, Kenney audio, freesound CC0)
- [ ] First-person arms (hands on the gun) and reload animations
- [ ] 8-way locomotion blending and a proper slide / wall-run pose for third-person characters
- [ ] Key rebinding
- [ ] Test the graphics presets on low-end GPUs and the Steam Deck; set frame-time budgets
- [ ] Export presets and release builds (Windows, Linux, macOS), plus a dedicated-server build

## Then: community tooling

- [ ] **Creative mode** in the Training Garage: tweak weapon stats live, then export the change as a proposal (`.tres` diff)
- [ ] Experimental playlist support (server flag to load proposed balance data)
- [ ] Opt-in match telemetry for balance decisions (privacy policy first)
- [ ] Issue / proposal templates, labels, governance doc, Code of Conduct
- [ ] Server browser or master server list (community-hosted)
- [ ] Bots for backfill and the Training Garage

## Later

- [ ] 5v5 objective mode and maps
- [ ] Battle-royale-scale map (needs relevancy/interest management)
- [ ] Mod support (user content packs)
