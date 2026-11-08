---
name: add-npc
description: Add an NPC to the game with the NPC kit, which already exists. An NPC is a soldier profile (who they are and how they fight) plus a look (kit pieces and colours on the one skeleton), placed by a town marker or a place's data; a talking one adds an AI card. Use whenever the user asks to add, make or place an NPC, character, person, guard, trooper, local, merchant, bartender, dancer, crowd, crew, bounty target, or someone to talk to ("put a bounty hunter in the cantina", "add guards to the station", "I want a new AI character"). Picks the nearest existing profile and look to copy, asks what matters, writes the data, checks it and opens the PR.
---

# Adding an NPC

The NPC kit exists already. Every person in the game is the same five layers,
and a new NPC is almost always **a profile plus a look**, placed by data:

| Layer | What it is | Where |
|---|---|---|
| **Look** | An archetype: kit pieces on the one human skeleton, as `piece:colour`, or a tint on another archetype. | `content/look/characters.json` |
| **Body** | `NpcBody`: the player's own movement, senses, weapon. Never changes. | `src/systems/npc/npc_body.gd` |
| **Profile** | Who they are: faction, role, hp, speed, sight, weapon, combat, patrol, name kind. One with `base` lists only what differs. | `content/core/soldiers/<id>.json` |
| **Director and brain** | Who runs them: `Townsfolk` (the locals), `Garrison` (troopers and guards), `NativesDirector` (native packs). Picked by the profile's faction. | `src/systems/npc/` |
| **Talk** | An AI card run by `NpcBrain` through `ActionValidator`, or authored lines. | `content/core/npcs/` |

If the user only wants an issue written, use the `write-issue` skill instead.

## The steps

1. **Say back what the player wants** in one sentence: who they meet, where,
   and what happens.
2. **Check what is in flight:** `gh issue list --state open --search npc`, and
   the same for the place (`cantina`, `station`, `outpost`).
3. **Ask** (next section) with AskUserQuestion.
4. **Find the nearest profile and look** (tables below) and copy them, changing
   only what differs.
5. **Add the profile id** to `"soldiers"` in `content/core/manifest.json`.
   Without it `CoreContent.get_soldier()` returns `{}` and nothing spawns, with
   no error.
6. **Place them** (see "Where they stand").
7. **Check it**, shoot it, and **open the PR** on a `feature/<name>-npc` branch
   in the PR format of the `write-issue` skill.

## Questions to ask

Put the option that reuses the most first, marked "(Recommended)".

- **Where?** Which planet, and where in it: the cantina, the street, the gate,
  an outpost, the barge, the station, the cruiser.
- **Whose side?** The locals (`locals`, run by `Townsfolk`: they fight back
  together if you hurt one), the Remnant (`imperial_remnant`, run by `Garrison`
  with the alarm and the checkpoint), a native pack, or a performer who never
  fights (`ambient: true`).
- **What do they do?** Walk a loop (`role: local`), mind a stall
  (`merchant`), stand a post (`gate`, `sentry`, `yard`), dance or play
  (`ambient`), crew a heist (`crew`).
- **Armed?** Which gun (a `weapon.base` from `content/core/weapons/`), and do
  they draw it only when the alarm goes up (`sidearm`)?
- **Do they talk?** Not at all (barks only), an AI character with a card, or
  authored lines.
- **What do they look like?** Offer existing archetypes and kit colours first
  (see "Looks").
- **Named?** Everyone who spawns is named by the name engine (`naming.kind`),
  never by hand. Only a unique character gets a written name, and it must pass
  the IP check.

## Copy the nearest profile

| New NPC is like... | Copy (`base`) |
|---|---|
| a local walking the street | `local_resident` |
| a stall keeper | `local_merchant` |
| a local guard at a gate or post | `local_guard`, `local_gate_guard`, `local_sentry` |
| an armed local standing about | `ranch_local` (a guard with nowhere to walk) |
| a bar patron or club crowd | `local_patron`, `local_raver` |
| a dancer or band member | `cantina_dancer`, `club_dj`, `club_drummer`, `club_bassist` |
| a Remnant trooper on a post | `gate_guard`, `outpost_trooper`, `tower_sentry`, `roof_rifleman` |
| a Remnant officer or boss | `barracks_general`, `cruiser_general`, `bounty_target` |
| a boss's private guard | `barge_guard`, `general_guard` |
| a heist crew member | `heist_crew_local`, `heist_crew_remnant` |

A new profile should usually be four to ten lines:

```json
{
  "id": "station_bouncer",
  "base": "local_guard",
  "label": "Bouncer",
  "archetype": "barge_guard",
  "note": "What they are, where they stand, who runs them.",
  "hp": 90,
  "patrol": { "pause_s": 12.0 }
}
```

Dictionaries merge key by key (`CoreContent._merge`), so `"patrol": {...}`
changes only the keys given. Numbers stay in proportion to the profiles
around them: a trooper has about 70 to 90 hp, a local 40.

## Looks

Stop at the first rung that reads right. Write the rung into the PR.

1. **An archetype that exists.** `archetype` in the profile. There are about
   twenty in `content/look/characters.json` (locals, station locals, troopers,
   commanders, desert guards, barge guards, nomads, dancers, the band...).
2. **A variant of one.** A new archetype with `"base": "<archetype>"` and only
   what differs: other kit pieces or colours in `model.parts`, or a
   `model.tint` (`cantina_owner_station` is Oda tinted steel-blue;
   `desert_guard` and `barge_guard` are the trooper in other plates).
3. **A new colour of a piece.** The colours are textures in
   `assets/characters/kit/colors/` (`guard_navy`, `local_red`, `player_olive`...).
   A new one is one line in `content/look/character_models.json` and a rerun:
   `recolor` with `tools/look/recolor_parts.gd` for the locals, `part_colors`
   with `tools/look/recolor_fitted.gd` for the fitted pieces (guard, player,
   cantina owner). No render.
4. **A new piece.** A Hyper3D render of a kit piece fitted to the mannequin
   (`docs/kit/HYPER3D_PROMPTS.md`). Ask the user first. It must keep to
   `docs/ART_DIRECTION.md`: no white armour, no franchise silhouettes, the
   60/30/10 palette.

Review a look with the sheets in `tools/look/sheets/` (`./tools/look/shoot_sheet.sh <sheet>`).

## Where they stand

| Where | How |
|---|---|
| A hand-built town (the port) | A marker in `content/core/towns/<layout>.json`: `{ "id", "pos", "role": "ambient" or "trooper_post", "soldier": "<profile>", "face": [x, y, z], "patrol": "<route id>" }`. Any marker with `soldier` spawns one. |
| Every generated town | The counts in `content/core/planets/town_kit.json` (`guards`, `residents`, `merchants`, `roamers`); `TownGen` (`src/systems/planets/town_gen.gd`) writes the same kind of markers with the profiles it gives them (patrons, ravers, the dancer, the DJ). A new crowd member there is a small change to it. |
| An outpost or desert place | Its location file in `content/core/locations/` names its points (`guard_a`, `target`...); the place's node stands people on them (`remnant_outposts.gd`, `ranches.gd`). |
| The barge, the cruiser, the station | Their own files: `content/core/barges/party_barge.json`, `content/core/cruiser/remnant_cruiser.json`, `content/core/stations/orbital_station.json`. |
| A native pack | A people in `content/core/species/` (see `docs/natives/NATIVES.md`). |
| A planet's cantina owner | The planet's `cantina_owner` block (`{ "card", "look" }`; see the `add-planet` skill). |

## Making them talk

- **Barks only:** lines in `content/core/dialogue/` (the locals' are
  `locals_lines.json`).
- **Authored lines, no model:** an `npcs/<id>.json` with `"kind": "authored"`
  and a `dialogue` file, and a `role: "npc"` marker (the fixer).
- **An AI character:** a card, `content/core/npcs/<id>_card.json`. Copy the
  nearest: `fence_card.json` (a stall keeper), `skrugs_card.json` (a seller
  with shortcuts), `heist_crew_card.json` (a crew member),
  `cantina_owner_card.json` (Oda). Write `identity`, `backstory`, `voice`,
  `rules`, `secrets`, `greetings` and `canned` lines (what they say with AI
  off: AI characters are off until the player turns them on, so canned lines
  must carry the scene).
  - **Actions** are only the ones `src/systems/llm/action_validator.gd` knows:
    `share_rumor`, `offer_job`, `hint_secret`, `trust`, `pour_drink`,
    `offer_speeder`, `offer_ship`, `offer_ship_buy`, `offer_item`,
    `club_vibe`, `refuse_topic`, `end_conversation`, plus a few tied to one
    scene (`comrade`, `let_go`, `search`, `join`, `refuse`, `call_guards`). A
    new kind of effect is a new action there (small code), never a second
    pipeline.
  - **Wiring is about ten lines:** there is no data-only talker marker yet.
    Bind a `TalkSpot` to the body: `TalkSpot.new(NpcBrain.new(null, CARD), body, stand)`
    then `bar.add_spot(spot)`. `TownDemo._build_fence()` in
    `scenes/town_demo.gd` is the pattern: it finds the local posted at a
    marker and gives him the fence's card.

## What an NPC can not do

From "What can not change" in the `write-issue` skill. Say so and offer the
nearest thing instead:

- **One skeleton, one movement.** No new rig, no special locomotion: new looks
  are kit pieces and colours.
- **Pure brains, existing directors.** No second AI framework. A new behaviour
  is a role or a mode on `Townsfolk`, `Garrison` or `NativesDirector`.
- **One LLM pipe.** A new AI character is a card; effects go through
  `ActionValidator`.
- **`WorldState` is the one truth.** What they remember or whether they are
  dead is saved there, not in a store of their own.
- **A unique story character** (the general, the dark master) has its own post
  script. That is new code: write an issue with `write-issue` first.
- **No franchise names** in names, labels, cards or notes.

People cost frames: they follow rule 10 of
[`docs/RENDER_RULES.md`](../../../docs/RENDER_RULES.md) (sleep past the draw
distance, think less further out). Say how many you add, and where.

## Check it

The gate is `tests/test_smoke.gut.gd` plus a headless boot of the town where
they stand. Don't run `./scripts/ci.sh` or batches of suites; name what you did
not run in the PR.

```bash
godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/test_smoke.gut.gd -gexit
```

- **Boot where they are:** a scratch `extends SceneTree` script that sets
  `GameFlow.resumed = true` and `GameFlow.planet_id` (`"port_desert"` for home),
  instances `town_demo.tscn` with `use_look = false`, runs about 300 frames, and
  checks the new NPC is in `characters` (keyed by marker id). Wrap godot runs in
  `perl -e 'alarm 240; exec @ARGV' godot ...`.
- **Back up the saves first.** Any boot can rewrite every `user://save*.json`
  (`save.json`, `save_freeplay.json`, `save_story.json` in
  `~/Library/Application Support/Godot/app_userdata/Desert Spaceport Slice/`).
  Copy them out, restore after, and `cmp` them.
- **AI off in probes.** Never let a probe call the model with the user's key.
- **Shoot it:** a sheet for the look alone (`./tools/look/shoot_sheet.sh`),
  and a still in place from a short windowed probe (`--rendering-driver vulkan`;
  Metal crashes). Commit stills under `docs/npc/` and embed them in the PR.

## Leaves behind

A profile with `base` and an archetype with `base` are the next NPC's starting
point. Say in the PR what else could wear them.
