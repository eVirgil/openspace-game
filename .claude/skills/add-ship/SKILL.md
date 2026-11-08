---
name: add-ship
description: Add a ship to the game as a variation of a ship that is already modelled. Ships are data, so a new one is a JSON file with its own stats and a look that reuses an existing model (the same airframe, repainted, rescaled or with bolt-on parts). A new render is the last resort and must match the art style. Use whenever the user asks to add, make, sell, park or design a ship, fighter, freighter, gunship, frigate, enemy ship, starter ship, or a variant or livery of one ("add a heavier interceptor", "I want a bounty hunter's ship", "sell a cargo hauler at T-89"). Picks the nearest ship to copy, asks what matters, sets the stats in proportion to the fleet, chooses the cheapest look that reads right, places it, checks it and opens the PR.
---

# Adding a ship

Ships are data, and the code never names one. A ship is
`content/core/ships/<id>.json` (how it flies and fights) plus a look in
`content/look/ships.json` (what it looks like), plus one manifest line. The
full reference is [`docs/ADDING_SHIPS.md`](../../../docs/ADDING_SHIPS.md).

**The rule: a new ship is an airframe we already have, with stats of its own.**
Prefer an existing model, repainted or rescaled, over anything new. A new
variant of a model is fine. A new render is the last step, and it has to look
like it came from the same game.

If the user only wants an issue written, use the `write-issue` skill instead.

## The steps

1. **Say back what the player wants** in one sentence: what the ship is for,
   who flies it, and how it feels next to the ships already there.
2. **Check what is in flight:** `gh issue list --state open --search ship`.
3. **Ask** (next section) with AskUserQuestion.
4. **Copy the nearest ship** (the fleet table) to `content/core/ships/<id>.json`,
   change `id`, `label`, `faction`, `pilot`, `look`, and set the stats.
5. **Pick its look** on the lowest rung that reads right (see "Looks").
6. **Add the id** to `"ships"` in `content/core/manifest.json`.
7. **Place it** (see "Where it shows up").
8. **Check it**, shoot it, and **open the PR** on a `feature/<id>-ship` branch
   in the PR format of the `write-issue` skill.

## Questions to ask

Put the option that reuses the most first, marked "(Recommended)".

- **What is it for?** Fast and fragile, all-round, a gun platform, a hauler,
  a capital ship. That decides which airframe to start from.
- **Who flies it?** The player (bought, found or stolen), the Remnant (an
  enemy in fights or parked at outposts), the locals, or a story character.
- **Where does the player meet it?** On T-89's or T-99's lot, parked in a bay,
  at an outpost, on the station's pads, or only in a space fight.
- **How does it compare?** Name the two ships it sits between ("tougher than
  the gunship, slower than the freighter"). Offer the fleet table.
- **What does Shift do?** `boost` (default), `drift` (slide while the nose
  turns faster) or `brake` (air brake).
- **What does it look like?** Offer the existing airframes in another paint
  first (see "Looks"). Ask before any new render.
- **Price?** If sold, where it sits on the price list.

## The fleet

Numbers as of v1.6.4; read the files before quoting them.

| Ship | Airframe (model) | Hull | Shield | Space speed | Air speed / boost | Guns, `blaster_power` | Shift | Price |
|---|---|---|---|---|---|---|---|---|
| `courier` | `courier.glb` | 80 | 60 | 60 | 210 / 380 | 2 cannons + seekers, 0.7 | boost | 900 |
| `interceptor` | `interceptor.glb` | 120 | 80 | 48 | 170 / 300 | 2 + seekers, 1.0 | boost | 1200 |
| `gunship` | `gunship.glb` (the courier's source, repainted, with bolt-on guns) | 220 | 100 | 40 | 150 / 240 | 2 + seekers, 1.8 | brake | 1800 |
| `freighter` | `freighter.glb` | 260 | 130 | 36 | 130 / 220 | 4 + seekers, 0.8 | drift | 2400 |
| `frigate` | `freighter.glb` at `scale` 2.0 | 620 | 300 | 30 | 110 / 180 | 4 + 2 seeker racks, 0.8 | drift | not sold |
| `remnant_interceptor` | `interceptor.glb`, look `interceptor_dark` | as the interceptor | | | | | | enemy, outposts |
| `remnant_freighter` | `freighter.glb`, look `freighter_dark` | as the freighter | | | | | | enemy |
| `remnant_fighter`, `remnant_heavy` | stand-ins from primitives (`blade`, `hauler`) | 60 / 180 | 0 / 60 | 52 / 38 | space only | | | enemy |

Prices are in `content/core/npcs/t89.json` and `t99.json` `prices`
(`default_price` for any ship not listed).

## Stats

Copy every block from the nearest ship and move only the numbers that make it
different. The fields are explained in `docs/ADDING_SHIPS.md`.

- **`hull`, `shield`** (`max`, `regen`, `delay`), `hit_radius`.
- **`flight`:** speeds, `accel`, turn rates, boost, `ability`. Written at the
  old slow scale: a space fight multiplies them by `speed_scale`
  (`content/core/flow/space_fight.json`).
- **`atmosphere`:** needed for any ship flown near the ground. Without it T-89
  will not sell it and it is space only. Keep `body_radius` and `clearance`
  true to the model.
- **`hardpoints`:** guns and where they mount (forward is -Z). **Every ship
  carries a `ship_missile`** (`tests/test_ship_combat.gut.gd` checks it).
- **`blaster_power`:** multiplies gun damage.
- **`dogfight_foe`:** optional numbers it uses only as an enemy in a space
  fight (the Remnant interceptor is slower and worse-piloted there so the fight
  can be won).
- **`naming`:** `kind`, `callsign`, `vessel`, so its pilots and the player's
  ship get names. `label` (make and model) comes from the name engine
  (`equipment`, class `ship`; `docs/names/NAMING.md`), never invented by hand.
- **`sold: false`** keeps it off the lots.

Keep it in proportion. A new ship sits between two in the table on every
number, or it is better at one thing and worse at another. Nothing should beat
the whole fleet. T-89's upgrades (`t89.json` `upgrades`: shields, hull, boost)
multiply its numbers, so leave room for them.

## Looks

Stop at the first rung that reads right. Write the rung into the PR. Rungs 1
to 4 need no new render.

1. **An existing look.** Point `look` at a look id that exists. Same model,
   same paint, new stats (`remnant_freighter` wears `freighter_dark`).
2. **A new look on an existing model,** one entry in `content/look/ships.json`
   `looks` with the same `scene`, `length`, `span`, `height` and `flames_at`:
   - `recolor`: `swap` (`{ "#from": "#to" }`, or a faction colour like
     `"locals.band"`) and `tint` for textured parts. The locals' and the LAN
     liveries are this (`interceptor_locals`, `interceptor_crimson`).
   - `darken`: the dark-gun shader over the model (the Remnant's ships).
   - `scale`: the same airframe bigger or smaller (the frigate is the
     freighter at 2.0; scale `length`, `span` and `height` with it).
   - `parts`: bolt-on boxes, cylinders and glows from primitives (the
     gunship's extra guns). Keep it to a few parts.
   - `locals`: the look it wears while the locals hold its place.
3. **A repaint baked into a new .glb** from an existing source: an entry in
   `content/look/vehicle_models.json` with the same `source` and a `paint`
   block (`body`, `trim`, `glow`, `metallic`, `roughness`), then
   `godot --headless --path . -s res://tools/look/prep_vehicle.gd -- id=<id>`.
   The gunship is the courier's source repainted; `freighter_shields`,
   `_hull` and `_boost` are the freighter's upgrade paints.
4. **A runner-up that is already rendered.** `vehicle_models.json` `options`
   lists generations kept in `assets/vehicles/source/` but not in the game.
   Check each against the art style first: some are noted as off-style. Prep
   it like rung 3.
5. **A new render.** Only when 1 to 4 cannot read right, and only after asking
   the user. See "A new render".

## A new render

Pre-rendered is better. A new model has to match the ones already flying:

- **The style:** `docs/ART_DIRECTION.md`, "Ships". Big clean shapes that read
  as a silhouette at 200 m; the 60/30/10 palette. The smuggler side is pale
  worn hull, saffron trim, teal glass. The Remnant is dark plate, oxblood trim,
  amber glass. **No franchise silhouettes** (no wedge-shaped capital ships).
- **Prompt like the fleet's:** the generation ids and notes are in
  `vehicle_models.json`; the stills to match are in `docs/lookdev/vehicles/`.
  Put the raw .glb in `assets/vehicles/source/`.
- **Prep it:** an entry in `vehicle_models.json` (`source`, `out`, `yaw_deg`:
  180 for Rodin, whose noses face +Z; `length`; `max_span`). A ship that parks
  in a pit bay fits in 9.2 m long and 8.0 m wide. Run `prep_vehicle.gd`, then
  set the look's `scene`, `flames_at` at its nozzles, and the stand-in fields
  as the fallback.
- **Review it beside the fleet** before the PR:
  `godot --path . -s res://tools/look/shoot_vehicles.gd -- sheet=tools/look/sheets/vehicles_final.json`
  and `./tools/lookdev/shoot_dogfight.sh` (`lineup.png`). If it looks like
  another game's ship, it does not ship.

## Where it shows up

| Where | How |
|---|---|
| T-89's and T-99's lots | Automatic for any ship with `atmosphere`, a `look`, and no `sold: false` (`ShipSalesman.stock`). Set its price in `t89.json` and `t99.json` `prices`. |
| A bay in the port | A `ship` box in `content/core/towns/port_square.json` with `"ship": "<id>"`, sized to the model. E boards it. |
| Generated towns' bays | `bay_ships` and `ship_boxes` (its box size) in `content/core/planets/town_kit.json`. |
| An outpost | The location file's `"ship"` (`content/core/locations/remnant_outpost_*.json`). Taking it sets off the alarm. |
| The station's pads | A pad's `"ship"` in `content/core/stations/orbital_station.json` (the frigate). |
| A space fight | A wave's `ships` in `content/core/encounters/<id>.json`; an AI personality from `content/core/pilots/`. |
| A LAN guest's ship | `content/core/flow/lan.json` `guest_ship`, and its `liveries`. |

## What a ship can not do

From "What can not change" in the `write-issue` skill. Say so and offer the
nearest thing instead:

- **One flight model for every ship.** A ship that flies differently is
  different numbers and a Shift `ability`, not a new flight model.
- **No space scene.** It fights in a planet's own sky or in open space.
- **Looks are optional.** With `use_look = false` it must still fly; a missing
  model falls back to its stand-in, never invisible.
- **No franchise names or shapes** in the label, the look or the model
  (`tests/test_ip_neutral.gut.gd`).

A new model or bolt-on parts follow [`docs/RENDER_RULES.md`](../../../docs/RENDER_RULES.md):
share materials, few parts, no new shaders.

## Check it

The gate is `tests/test_smoke.gut.gd` plus a headless boot of the town. Don't
run `./scripts/ci.sh` or batches of suites; name what you did not run in the PR
(`test_ship_combat`, `test_ship_kit`, `test_ship_salesman` and `test_dogfight`
cover ships; run them only if the user asks).

```bash
godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/test_smoke.gut.gd -gexit
```

- **Boot the town** where it parks: a scratch `extends SceneTree` script that
  sets `GameFlow.resumed = true` and `GameFlow.planet_id`, instances
  `town_demo.tscn` with `use_look = false`, runs about 300 frames and quits.
  Wrap godot runs in `perl -e 'alarm 240; exec @ARGV' godot ...`.
- **Back up the saves first.** Any boot can rewrite every `user://save*.json`
  (`save.json`, `save_freeplay.json`, `save_story.json` in
  `~/Library/Application Support/Godot/app_userdata/Desert Spaceport Slice/`).
  Never buy a ship in a probe without restoring them.
- **Shoot it:** `./tools/lookdev/shoot_dogfight.sh` for the lineup, the vehicle
  sheet for a close look. Windowed runs use `--rendering-driver vulkan`.
  Commit stills under `docs/lookdev/vehicles/` and embed them in the PR.

## Leaves behind

A look entry the next ship can wear in another paint, and a stats file the next
one can copy. Say in the PR which airframe it reused.
