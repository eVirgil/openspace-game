# Desert Spaceport

**Status: playable.** Download the build and play it now (see [Play it](#play-it)).

## The story

An empire has just collapsed, and its desert frontier is up for grabs. You are a
smuggler who lands at a lawless spaceport days after the fall. The imperial
remnant still holds the gates, the locals plan to outlast everyone, and the
desert nomads want the outsiders gone. A droid in the pit points you toward Oda,
the cantina owner, who knows every rumor in town and pushes the plot on you
whether you ask or not. From there you take contracts, run contraband past the
guards, fight on foot and in the cockpit, and work your way up to a star cruiser
in orbit and the dark master who answers to it.

## Key features

- **Open space flight.** Board your ship in the pit, lift off, fly over the town
  and the dunes, climb until the sky goes dark, and drop into space. Dogfight
  with fixed guns and lock-on seekers, fly to other worlds such as Grit Station,
  and dive back into the atmosphere to land anywhere.
- **AI NPCs.** The cantina owner is driven by a live language model (local or
  cloud, with a canned fallback), with memory, trust tiers, secrets and rumors
  true to the world state. Guards, pilots and natives think for themselves:
  they patrol, see and hear you, challenge you at checkpoints, take cover and
  raise the alarm.
- **Status tracking with different groups.** Every faction keeps its own opinion
  of you: the imperial remnant, the port locals, the smugglers and each native
  pack. Standing changes what guards do (wave you through, ask for papers,
  search you, or open fire), what bribes cost, and what people say about you.
- **Planets from a config file.** Sand, snow, red desert, water, lava, gas and
  asteroid worlds, with towns from one cantina up to a hundred buildings.
- **On foot, too.** Blaster pistol, rifle, energy sword with blocks and timed
  deflection, a jetpack, and a smuggling economy with a fence and a cache.

## Play it

Download the latest build from the shared folder:

**[Download the game (Google Drive)](https://drive.google.com/drive/folders/1nJtlYMXnEM33q5tRZ0B1J47N1FofbV5i?usp=drive_link)**

Builds are packaged by `./scripts/package.sh` (see `docs/SHARING.md`). To run
from source instead, see [How to run](#how-to-run-macos-apple-silicon) below.

## Promo

[![OpenSpace promo: click to watch](docs/promo/openspace_promo.jpg)](docs/promo/openspace_promo.mp4)

**[▶ Watch the OpenSpace promo (44 s, 1080p60)](docs/promo/openspace_promo.mp4)**: real
gameplay and in-engine renders. Landing, rifle and blaster fights, the energy sword,
the beast, the moon rave, flying from the port to the star cruiser in orbit, and the
dark master.

## Engine

- **Godot 4.7.2** (pinned in `scripts/pin.txt`; CI checks it).
- GDScript (no C#).
- Dev/target: macOS on Apple Silicon, 64 GB unified memory.
- Windows and Mac share builds: `./scripts/package.sh` (see `docs/SHARING.md`).

## How to run (macOS, Apple Silicon)

```sh
# 1. Install the toolchain once (Homebrew)
brew install --cask godot
brew install rust ffmpeg

# 2. Open the editor and run, OR run headless tests
open project.godot            # in the Godot editor, F5

# 3. Run the headless test + CI gate (no editor needed)
./scripts/ci.sh
```

`./scripts/ci.sh` runs the full GUT suite and the IP-neutrality scan headless and
exits non-zero if anything fails. That non-zero exit is the merge gate.

To run the game on screen and record the 3-minute gameplay clip, see `LAUNCH.md`.

## What exists now

The game is playable end to end: land, roam the port, talk to locals, take
contracts, fight, fly to space and back, and get paid. The milestone-by-milestone
list, with status, is in `PLAN.md`; what shipped is in `CHANGELOG.md`; what is
faked or outstanding is in `KNOWN_ISSUES.md`.

## IP-neutrality rule

No franchise names in code, file names, class names, commit messages, or the data
layer. Generic terms only: "energy blade", "blaster", "imperial remnant", "trooper",
"smuggler". `tests/test_ip_neutral.gut.gd` fails the build if a banned term appears.

## Plan

`PLAN.md` holds the milestones in build order, with status and the "done means"
for each. M0-M12 are done (M10 is starfighter flight and dogfights; M11 the
player's body and hand weapons; M12 the live LLM cantina owner,
`docs/cantina_owner/CANTINA_OWNER_PLAN.md`; M13 the jetpack; M14 flying the ship from the
port to space and back). N1 is the naming system: everything that spawns gets a
generated, unique name (`docs/names/NAMING.md`). P1 is the planet generator: a planet is one
config file (type, town size 1-100, style), and Grit Station, an asteroid you can
fly to from the port's sky, is the first one (`docs/planets/PLANETS.md`). `LAUNCH.md` is how to run and
record the slice, fly the ship, fight in space and use the jetpack. `docs/ADDING_SHIPS.md` is how to add ships, guns, AI pilots and fights
from data; `docs/ADDING_ITEMS.md` is the same for items, vendors and pickups.

## Layout

```
content/core/      the only place names/weapons/dialogue live (swappable)
content/look/      palettes, ship and item looks, lighting (what things look like)
src/systems/       gameplay + support systems (dataloader, player, combat, ai, flight, ...)
scenes/            boot + level scenes; scenes/flight/ is the playable dogfight
tests/             GUT tests + (M5) the headless bot playthrough
scripts/           ci.sh, record.sh, pin.txt
addons/            godot plugins (gut; nobodywho added at M6)
assets/            third-party (CC0 / MIT, with licenses) and generated audio
tools/             render, eval and runtime helpers (tools/llm, tools/m11, ...)
```

## Third-party assets

`assets/third_party/kenney_starter_kit_fps/`: blaster models (CC0) and sounds from
Kenney's Starter Kit FPS (MIT; license text in that folder). The energy sword's
sounds in `assets/audio/blade/` are original, generated by
`tools/audio/make_blade_sfx.py`.

See `DECISIONS.md` for why each significant choice was made.
