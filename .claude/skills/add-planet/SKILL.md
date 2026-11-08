---
name: add-planet
description: Add a planet, moon or station world to the game with the planet generator, which already exists. A planet is one JSON file plus a manifest line, with no new scene and usually no code. Use whenever the user asks to add, make, build or try a planet, moon, asteroid, ice, lava, water or gas world, a station planet, or a new place to fly to ("I want a snow planet", "add a second moon", "make a jungle world"). Picks the nearest existing planet to copy, asks what matters (type, size, style, where in the sky, who runs the cantina, extras), writes the file, checks it and opens the PR.
---

# Adding a planet

The planet generator exists already (issue #45). A planet is **one small JSON
file** in `content/core/planets/` plus one line in the manifest. From that the
game builds a town of any size, a cantina with a stage, merchants, locals, its
own Oda, a landing bay, smuggling, contracts, a sky, and a place in a
neighbour's sky to fly to. Nothing here needs a new scene, and almost nothing
needs code.

The full reference is [`docs/planets/PLANETS.md`](../../../docs/planets/PLANETS.md).
Read it before anything unusual. This skill is the short path.

If the user only wants an issue written, use the `write-issue` skill instead.

## The steps

1. **Say back what the player wants** in one plain sentence: what they see when
   they fly there and land.
2. **Check what is in flight:** `gh issue list --state open --search planet` and
   `gh pr list --state all --limit 20`. Don't build a twin of an open issue.
3. **Ask** (next section) with AskUserQuestion, even when the ask looks complete.
4. **Copy the nearest planet** (table below) to `content/core/planets/<id>.json`
   and change only what differs.
5. **Add the id** to `"planets"` in `content/core/manifest.json`.
6. **Check it** and **shoot it** (see "Check it").
7. **Open the PR** on a `feature/<id>-planet` branch off the latest `main`, in
   the PR format of the `write-issue` skill, with stills.

## Questions to ask

Put the option that reuses the most first, marked "(Recommended)".

- **What kind of world?** One of the types in `content/core/planets/types.json`
  (next table). A new type is a new entry there, not code, as long as its
  ground and surface are ones that exist (see "A new type").
- **How big is the town?** `town_size` 1 to 100. 1 is a cantina, a guard, a
  merchant, three locals and a bay; 50 is the port's scale; 100 is five times
  its area. Small is cheap and loads fast: recommend 1 to 20 for a moon.
- **What does the town look like?** A preset (`desert`, `metallic`, `snowy`,
  `pastel`) or a line of words (`pale blue glossy ceramic with gold trim`).
  The words are in `content/look/town_styles.json`.
- **Where in the sky?** Which planet it hangs near (`near`) and roughly where
  (`at`). See "Where to hang it".
- **Who runs the cantina?** Default: a new Oda made for this planet (her own
  name, memory and save). Or a look of hers (`cantina_owner.look`), or a card of
  its own (`cantina_owner.card`; see the `add-npc` skill).
- **What else lives there?** Only blocks that already exist (the "Extras"
  table): a club, natives, a beast, a barge, domes, outposts, a space fight on
  the way up, or a station as the town.
- **Its name?** Leave `name` `""` and the name engine makes one, unique in the
  game. Hand-written names must pass the IP check.

## The types

| Type | What you get |
|---|---|
| `sand`, `snow`, `red_desert` | Biome worlds: the town on seamless dunes, walkable out into the desert. `snow` brings the frost folk. |
| `water`, `lava`, `gas` | Element worlds: the town floats on a deck over sea, lava or cloud, under a glass enclosure. Fall off the edge and you die. |
| `gas_ball` | A real ball of cloud you fly round. Deck town on top, or a station as its town (the ringed giant). |
| `asteroid` | A rock ball with a sealed station under a dome, a hallway and a landing pit (Grit Station). |
| `lava_moon` | The asteroid on a ball of lava rock: lava in the low ground that kills, heat shimmer (Cinder Station). Written as `"base": "asteroid"` plus what differs. |
| `open_space` | Not a planet: the space between planets. Never copy it. |

## Copy the nearest planet

| If the new one is like... | Copy | Why |
|---|---|---|
| a small station moon | `grit_station.json` | Asteroid, size-1 town, two domes, five outposts, its own Oda in a station look. |
| a hostile moon with a hazard | `cinder_station.json` | Built on a type with `base`, lava that kills, a club in a dome. |
| a big gas world with a station | `ringed_giant.json` | `gas_ball`, `station_town`, a custom `body` (bands and ring), quiet sky. |
| a plain new world | the example in `docs/planets/PLANETS.md` ("Make a new planet") | Seven fields: id, name, type, town_size, style, near, at. |

Never copy `port_desert.json`: it is the home planet, with a hand-built town
and world (`town`, `world`, `features`). Its `natives`, `beast` and `barge`
blocks are good examples to borrow from.

## The fields

The seven everyone sets: `id`, `name`, `type`, `town_size`, `style`, `near`,
`at`. The rest are optional; the full table is in `docs/planets/PLANETS.md`.

- `seed`: another number lays the same size of town out differently.
- `town_name`: otherwise generated.
- `home_at`: where `near` shows from here, if not just the mirror of `at`.
- `encounter`: the space fight on the way up (`"orbital_skirmish"`), or `""`
  for a quiet sky. Fights are `content/core/encounters/`.
- `body`: how it looks from a neighbour's sky (colours, `bands`, `ring`).
- `replaces_sky_painting`: only for a planet that takes over the painted giant.

## Extras: blocks that already exist

Each block is data. Copy it from the planet named and change the numbers.

| Block | What it adds | Copy from |
|---|---|---|
| `club`, `club_dome`, `stage_dancer` | A club night in the cantina or a dome: band or DJ, crowd, mix. `club` names a playlist in `content/look/sound.json` `club.playlists` (`dust_lounge`, `salvage_rave`); a new mix is a new playlist there. See `docs/club/`. | `cinder_station.json`, `port_desert.json` |
| `domes` | More domes off a sealed station's pit: `fill` `barracks` or `homes` (`town_kit.json` `"domes"`). Pit stations only. | `grit_station.json` |
| `landmarks` | Places on the ground. `kind: "location"` needs a location file in `content/core/locations/` and its manifest line; outposts also need a `"fronts"` block in `content/core/story/territory.json` to be taken. | `cinder_station.json` |
| `natives` | Native packs and animals: `people` from `content/core/species/`, animals from `content/core/fauna/`. A type's `natives` gives every planet of that type a people; a planet's own block replaces it; `false` means none. See `docs/natives/NATIVES.md`. | `port_desert.json`, `types.json` (`snow`) |
| `beast` | The centipede, with its numbers from `content/core/hazards/beast.json`. | `port_desert.json` |
| `barge` | A party barge, numbers from `content/core/barges/party_barge.json`. | `port_desert.json` |
| `cantina_owner` | `{ "card": "npcs/<file>.json", "look": "<archetype>" }`. No card: a new Oda. | `grit_station.json` |
| `station_town` | A station landmark as the whole town (bay only, no deck). | `ringed_giant.json` |

Smuggling on a new planet: a `kind: "smuggle"` job in `content/core/board/` with
the planet's town id as `location`, plus `content/core/pickups/<town_id>.json` and
its manifest line. Without it the board has no local run.

## Where to hang it

`at` is `[east, up, south]` in metres from the `near` planet's port. The way
back is automatic.

- **Keep it inside 20 km of the port.** The port draws 20 km (four times the
  home ball's radius); further out the ball's far side is cut off. Cinder
  Station, at 16.7 km, is about as far as it goes.
- **Keep the bubbles apart.** Each ball has a bubble (`space.handoff` in its
  type: the moons 1.2 km, home 8 km). Between any two bubbles there must be
  `bubble_margin` (1 km) of open space. `tests/test_planets.gut.gd` checks the
  data.
- **Pick an empty part of the sky.** The moon, the lava moon and the ringed
  giant are already up there. Turn the bearing so the new one does not sit
  behind another from the port.

## A new type

A new entry in `content/core/planets/types.json`, with no code change, when its
ground is `terrain`, `platform` or `ball` and its surface is `water`, `lava`,
`gas` or `rock`. Write it as `"base": "<nearest type>"` plus only what differs
(dictionaries merge key by key). Set its `sky`, `body`, `town_naming`,
`fall_text`, and its `natives` if it has a people.

A ground or surface that does not exist (a jungle canopy, ice you fall through)
is new code in `src/systems/planets/`. Stop and ask the user, then write an
issue with `write-issue` instead of building it here.

## What a planet can not do

From "What can not change" in the `write-issue` skill. Say so and offer the
nearest thing instead:

- **No scene of its own.** Every planet is `town_demo.tscn` built from its file.
- **No space scene.** Its space is its own sky; between planets is open space.
- **Round and walkable,** with seamless handoffs. No flat maps.
- **The town is boxes, markers, routes and zones,** generated or from a saved
  layout in `content/core/towns/`, and it must pass the validator.
- **No franchise names**, in the file or the `name` (`tests/test_ip_neutral.gut.gd`).

New props or people on it follow [`docs/RENDER_RULES.md`](../../../docs/RENDER_RULES.md).

## Check it

The gate is `tests/test_smoke.gut.gd` plus a headless boot of the town **on the
new planet**. Don't run `./scripts/ci.sh` or batches of suites. Name what you
did not run in the PR (`tests/test_planets.gut.gd` builds every planet and
checks the bubbles; run it only if the user asks).

```bash
godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/test_smoke.gut.gd -gexit
```

- **Boot on it:** a scratch `extends SceneTree` script that sets
  `GameFlow.resumed = true` and `GameFlow.planet_id = "<id>"`, instances
  `town_demo.tscn` with `use_look = false`, runs about 300 frames and quits.
  Wrap any godot run in `perl -e 'alarm 240; exec @ARGV' godot ...`.
- **Back up the saves first.** Any boot can rewrite every `user://save*.json`
  (`save.json`, `save_freeplay.json`, `save_story.json` in
  `~/Library/Application Support/Godot/app_userdata/Desert Spaceport Slice/`).
  Copy them out, restore after, and `cmp` them.
- **Shoot it:** `./tools/planets/shoot_planets.sh scenes=<id>,port_desert`
  renders it on the ground and from the port's sky. Windowed runs use
  `--rendering-driver vulkan` (Metal crashes). Commit the stills under
  `docs/planets/` and embed them in the PR.
- **Fly to it once** if the user wants to see it: take off from the port,
  climb, and it hangs where `at` says.

## Leaves behind

Every planet is a file the next one can copy. If it needed a new type, say in
the PR which planets could use it next.
