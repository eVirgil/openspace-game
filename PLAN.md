# Plan — Desert Spaceport Vertical Slice

The milestones for the slice, in build order. After each, stop and report in
the milestone-report format (plain English): what works, how to see it, what is
faked or stubbed, what broke, what is needed from the user, and confidence the
next milestone fits its scope.

Status:
- DONE = merged to main, tests passing in CI.
- WIP  = in progress on a feature branch (tests passing locally, not yet merged).
- TODO = not started.

This table stops at P1, the planet generator (2026-10-27). Everything after it
was built from GitHub issues and milestones, and what shipped is in
`CHANGELOG.md`, newest on top. Each id appears once (`tests/test_docs.gut.gd`).

| # | Milestone | Done means | Status |
|---|---|---|---|
| M0 | Project setup | Repo, pinned Godot version, folder structure, data layer loader, test framework (GUT), headless CI script, README with run instructions | DONE |
| M1 | Movement and cameras | Player walks the greybox port; FPV/TPV toggle works; headless move+toggle trace | DONE |
| M2 | Ranged combat | Both blasters work; 1 trooper uses cover and fights back; headless combat trace | DONE |
| M3 | Melee and deflection | Energy blade, stamina, block, timed deflection; duelist enemy; headless melee trace | DONE |
| M4 | World streaming | Walk port to desert with no hitch over 50ms; outpost built; frame-time log | DONE |
| M5 | Mission loop and save | Fixer, contract, crate, payout, save/load all working end to end; bot playthrough on every merge | DONE |
| M6 | LLM cantina owner (text) | Typed conversation, memory, 4 tools, guardrails, fallback, Kokoro voice. **Scaffold only:** nothing talked to a real model (live HTTP was a stub and the player's text never reached it). The live path is M12. | DONE (scaffold) |
| M7 | Voice input | whisper.cpp push-to-talk with the cantina owner; latency measured | DONE |
| M8 | Polish pass | Bug list cleared, performance report, 3 minute gameplay recording | DONE |
| M9 | Port town greybox | Town built from data, validated, 4 routes walked headless with real collision, worst frame < 50ms; light art dressing (decor layer); the town is the one demo and its pit launches the dogfight | DONE |
| M10 | Starfighter flight and dogfights | Data-driven ships, guns, pilots and encounters; flight model; shields + hull; fixed guns + lock-on seekers; fighter AI (pursue, attack, break, extend, evade); playable dogfight scene with HUD; any ship design swaps in from data; headless dogfight trace won end to end | DONE |
| M11 | Player body and hand weapons | Animated smuggler body (procedural gait, jump, crouch, strafe); third person over the shoulder with wall collision; first person shows forearms and weapon; blaster pistol, rifle and energy sword with 1/2/3 swap, holster/draw, reload, aim; sword 3-hit chain, block, timed deflection; CC0 blaster models retinted; practice range with targets and a sparring remote; headless body + weapons trace | DONE |
| M12 | Live cantina owner | Real streaming LLM pipe (llama-server sidecar, Ollama, any OpenAI-compatible or Anthropic cloud key, canned floor) with timeouts, fallback and circuit breaker; persona card, trust tiers, secrets by tier, rumors true to WorldState, real jobs, drinks at menu prices, validator and output filter; her body behind the bar; dialogue panel, F3 debug, F10 settings; save v2; headless trace incl. real HTTP against a mock server; live gauntlet runner | DONE (model bake-off pending) |
| M13 | Jetpack (issue #5) | A jetpack item from data that can be picked up, attached and detached, sold and bought back; holding jump in the air flies it on a fuel meter that recharges; worn look on the body with flames; fuel HUD and prompts; inventory saved with the world; any item, vendor or pickup added from data; headless trace in the town with real physics | DONE |
| D1 | Seamless desert | The town sits on the dune terrain at floor level: out of the gate onto sand with no step, sand outside every wall, the pit still a pit; the collider follows the player (rebuilt over frames, under budget); landforms on the horizon; the fall guard measures from the ground; headless 700 m walk out and back with real physics | DONE |
| M14 | Fly the ship from the port to space | The pit ship is boarded (E), lifts off vertically, flies over the town and the seamless desert around it (its dunes, mesas and hoodoos are solid to the ship; the outpost stands 3 km out; the planet curves away past its 6 km edge), lands anywhere (C) and is got out of (E); crashes tow it home; the air thins with altitude (faster ship, darker sky, stars) until the edge of space at 8 km hands off to the pad's space encounter in 30-40 s from takeoff; diving at the planet in space re-enters the port's sky still flying; headless trace of the whole loop | DONE |
| M15 | Guards on foot (`docs/npc/GUARD_PLAN.md`) | Part 1: NPC body on the player's movement code, Health, flinch and death; navmesh baked from the town data off the main thread; path following; senses (sight cone, throttled rays, awareness, notice and forget, hearing). Part 2: the gate guards patrol; a checkpoint by Remnant standing (wave / papers / search / hostile; bribes one band lower after dark; weapons and gunfire escalate) with a choice card and authored barks; combat (opening burst, separate cover from the town boxes, crouch, bursts, no friendly fire, search on a leash, memory); player health with regen and a knockout to the pit; outcomes into WorldState and rumors; headless traces of every band and every way a fight ends. Part 3: the tower sentry and barracks troopers think, a town-wide alarm with a klaxon, NPC sound (rifles, steps, radio chatter, hurt), the player's crouch shrinks the hitbox and the eye, searches check your pockets for contraband, a cache and a fence to smuggle for, and an inventory screen on I | DONE |
| N1 | Sci-fi naming system (issue #15, `docs/names/NAMING.md`) | One deterministic, data-driven name engine (no LLM): ~2,300 original terms, per-culture tongues, a template grammar per kind (people x3 cultures, callsigns, ships, equipment, makers, towns, planets, moons, stars); a saved name book that keeps every name unique across the game and reserves authored ones; guards, pilots, your ship, the jetpack, the town and its planet named on spawn and shown in game; the cantina owner briefed with them; headless trace | DONE |
| S1 | Shooter feel (issue #65, `docs/shooter/SHOOTER_PLAN.md`) | Aim down sights (pistol iron sights 1.25x, rifle scope 2.5x), dark guns, sprint slide, hit markers + thud, enemy health bars, black first person arms | DONE |
| P1 | Planet generator (issue #45, `docs/planets/PLANETS.md`) | A planet is one config (name, type, town size 1-100, style, place in a neighbour's sky); TownGen lays out any size (50 = the port, 100 = 5x, 1 = cantina + door guard + merchant out back) passing the validator; seven types (sand, snow, red desert; water, lava, gas, asteroid on a glass-enclosed platform with a walkable gate shield and death off the edge); the town style kit (metallic, snowy, pastel, or words like "red matte metal"); Grit Station, a size-1 asteroid town you fly to from the port's sky and back, with its own AI cantina owner (Oda's sister, a tinted Oda); headless trace of the trip | DONE |

## Notes

- M9 is the port town, planned in `docs/town/TOWN_PLAN.md` (plus the decor
  addendum). M10 was numbered after it. Since M9 the town is the single demo:
  `run/main_scene` is `scenes/town_demo.tscn`, and flight is entered from the pit.

- One feature per branch, off the latest main; merge only when tests pass.
- Each gameplay system ships a headless trace/log plus GUT assertions; that trace
  is the CI proof. A rendered clip (scripts/record.sh) is the secondary proof.
- Cantina Owner is the only LLM-driven NPC; all others use authored data-layer lines.
- The M5 bot playthrough talks to a deterministic stub, never real inference.
  Since M12, CI also drives the real HTTP streaming path against a mock
  OpenAI-compatible server (`tools/llm/mock_llm_server.py`); real model quality is
  the live gauntlet (`tools/llm/eval_runner.gd`), run by hand on the Mac.
- `docs/cantina_owner/CANTINA_OWNER_PLAN.md` numbers its steps M10.0 to M10.6; they shipped
  as M12 (M10 was taken by flight). M10.6 (model bake-off + tuning her voice) is
  the remaining step and needs the Mac.
- See DECISIONS.md for why; CHANGELOG.md for what shipped; KNOWN_ISSUES.md for
  what is faked or outstanding.
