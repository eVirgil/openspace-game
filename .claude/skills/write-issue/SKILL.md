---
name: write-issue
description: Write a GitHub issue for this game from what the player (the user) wants, and the PR that closes it. Use whenever the user asks to write, file, draft, open, split or scope an issue, a feature, a milestone or an epic, describes something they want in the game ("I want a lava planet", "add a bounty hunter in the cantina"), or asks to open a PR for work done here. Checks open issues and recent PRs first, builds the request out of the game's existing parts (planets, towns, cantinas, outposts, native packs, the NPC kit) with as few new renders as possible, asks follow-up questions to settle must-haves and could-haves, and never re-architects the game.
---

# Writing an issue

The game is a box of lego. Almost everything a player asks for is a new
arrangement of parts that already exist: a planet config, a town layout, a
cantina with a club block, a soldier profile on the NPC kit, an AI card, a
location file. The job is to find those parts, ask the user what really
matters, and write an issue a builder can finish in one sitting.

**The rule: everything is a variation of something.** Prefer ten repeatable,
low-stakes tasks (town layouts, building variants, planet configs, profiles,
cards) over one piece of new logic with no wiring behind it. When something
really has to be new, shape it so the next issue can turn it into something
else.

## The steps

1. **Say back what the player wants** in one plain sentence, in the player's
   terms (what they see and do, not how it is coded).
2. **Look at what is being built already** (next section). Every time.
3. **Find the parts** in the table below. Open the doc or file for each one
   that fits and check it still does what the table says. Note what happens
   in the game today ("Right now there is none: `landed` fires and nothing
   checks the speed").
4. **Sort every piece of the request:**
   - **data only**: a config, a profile, a card, a layout, a manifest line.
   - **small code on an existing part**: a new mode, block, action or variant.
   - **a new part**: only when nothing in the table can do it. Build it in the
     pattern of its neighbours (a planet block, a director, a pure brain) and
     name the second thing it could become.
   - **architecture**: it needs something in "What can not change". Leave it
     out, say why in one line, and offer the nearest thing the parts can do.
5. **Ask follow-up questions** (see "Questions") with AskUserQuestion, before
   drafting, even when the request looks complete.
6. **Draft the issue** in the format below and show it.
7. **Create it** with `gh issue create` once the user okays it, with labels.
   If it is big, make it a milestone with a few sub-issues, each valuable on
   its own.

You only write the issue. Do not start building it.

## Look at what is being built already

Before finding parts, read the open issues and the last few weeks of PRs.
Issues say what is planned; merged PRs say what landed and how it was done.

```bash
gh issue list --state open --limit 50
```

```bash
gh pr list --state all --limit 30
```

```bash
gh issue list --state all --search "<keyword>"
```

Use what you find:
- **Same thing already open:** add to that issue or split from it (`Part of
  #N`, `Follows #N`), do not open a twin.
- **A neighbour landed recently:** read its PR body. Its parts and its test
  are the pattern for this issue.
- **Something in flight overlaps:** mark the new issue `blocked` on it, or
  scope around it.

## The three questions every issue answers

Write the answers into "Built from" and "What this leaves behind".

1. **Potential.** What else could this become? A new outpost dressing should
   be a second outpost with a different file. A new planet block should fit
   any planet. A new NPC profile should run on a director that is already
   there.
2. **Future builders.** What does it leave behind: a new config shape, a new
   kit piece, a new block, a layout others can copy? If the answer is
   "nothing reusable", it is probably the wrong shape.
3. **Efficiency.** Which existing pieces do the work, and which one line of
   data or code is the only new thing? The fewer new files, the better the
   issue.

A request that does not have good answers to all three is sized down, split,
or turned into a variation of something that does.

## Questions

Ask until you know the **must-haves** and the **could-haves**. Two or three
rounds of AskUserQuestion, up to four questions each, is normal.

- **Must have:** the issue fails without it. Goes in "Done looks like".
- **Could have:** wanted, ships without it. Goes in "Could have", built only
  if it comes cheap.
- **Nice to have:** leave it out unless it is data only or falls out of a part
  already in use (a style word, a colour variant, one more card line).

Good questions are about what the player experiences, with the options drawn
from the parts that already exist:

- **Where is it?** Which planet; the town, the desert, an outpost, the cantina.
- **Who is there?** Locals, Remnant, a native pack, droids. Armed? Do they
  share the town brain and fight back?
- **Do they talk?** An AI character with a card, or authored barks.
- **What does the player get or lose?** Credits, an item, standing, a story
  flag.
- **How does it end, and does it come back?** Respawn, gone for good, saved
  with the world.
- **What must it look like?** Offer existing kit pieces and colours before a
  new render.

Put the recommended option first, marked "(Recommended)", usually the one that
reuses a part. When a request needs architecture, ask it as a choice between
the nearest buildable options and say in one line why the original cannot be
done.

## Renders: as few as possible

A Hyper3D render is the expensive step. Stop at the first rung that works and
write which one you chose into the issue.

1. **Data only:** an existing model, archetype or look id.
2. **Mix and recolour:** kit pieces on the one skeleton, colour variants, a
   `tint`, a `base` archetype listing only what differs.
3. **Simple shapes:** props from primitives in code (`LookMeshKit`,
   `ClubProps`, `NativeCamp`).
4. **One new render:** only when 1 to 3 cannot read right. Name exactly what
   is rendered, prefer a reusable kit piece on the mannequin
   (`docs/kit/HYPER3D_PROMPTS.md`), and ask the user first.

## The parts

Check paths before citing them; things move. Each row is "what you get for
free" and where to start reading.

| Part | What it gives you | Start here |
|---|---|---|
| **Planet** | One JSON file (type, town size 1 to 100, style, place in a neighbour's sky) gives a town, cantina with stage, merchants, locals, its own Oda, landing bay, smuggling, contracts. Optional blocks: `natives`, `beast`, `barge`, `club`, `cantina_owner`, `encounter`. A thing that lives on some planets is a new block like these. | `content/core/planets/`, `types.json`, `src/systems/planets/planet_gen.gd`, `docs/planets/PLANETS.md` |
| **Town** | Boxes, markers, routes, zones; generated at any size or built to a saved layout; valid by construction (V1 to V9); decor, guards, nav, bar and ship work on any town. A style restyles every material from one line of words. | `src/systems/planets/town_gen.gd`, `content/core/planets/town_kit.json`, `content/core/towns/`, `src/systems/world/town_layout.gd`, `docs/town/TOWN_PLAN.md` |
| **Buildings** | Doors, windows and variants from a box's `look`; stalls, stair towers, ring walls, the pit, decor. Visual only, never collision beyond props. | `town_buildings.gd`, `town_market.gd`, `town_decor.gd`, `content/look/town_styles.json` |
| **Cantina and club** | Bar, stage, owner on every planet; a `club` block adds band, crowd and the club mix. New social scenes belong here first. | `cantina_dressing.gd`, `club_dressing.gd`, `club_props.gd`, `src/systems/audio/`, `docs/club/` |
| **Outpost or desert place** | A footprint in world data plus a node that dresses it and stands people in it. Ships and speeders already collide with it. Copy one: `remnant_outposts.gd`, `droid_merchant_outposts.gd`, `speeder_post.gd`, `mechanic_yard.gd`, `starcruiser_wreck.gd`. | `content/core/locations/`, `content/core/worlds/port_desert.json`, `src/systems/flow/territory.gd` |
| **Native pack or animal** | A people with camps, trade, hostile mode and reputation; animals to hunt. New people, weapons, colours, goods or animals are data. | `content/core/species/`, `content/core/fauna/`, `src/systems/natives/`, `docs/natives/NATIVES.md` |
| **NPC** | Five layers, all existing: look (`characters.json` archetype, kit pieces as `piece:colour`), body (`npc_body.gd`, the player's movement), profile (`content/core/soldiers/`), director and brain (`Garrison`, `Townsfolk`, `NativesDirector`), talk (a card in `content/core/npcs/`, run by `NpcBrain` through `ActionValidator`). A new NPC is a profile plus a look. | `content/look/characters.json`, `src/systems/npc/`, `docs/npc/` |
| **Names** | Everything that spawns is named by the name engine, never by hand. | `src/systems/names/`, `docs/names/NAMING.md` |
| **Droids** | Assassin, cargo and floating models, tinted per variant. | `content/core/droids/`, `src/systems/droids/` |
| **Items, vendors, pickups** | A new item, shop or drop is data. | `content/core/items/`, `vendors/`, `pickups/`, `docs/ADDING_ITEMS.md` |
| **Ships, guns, pilots, fights** | Data-driven ships, weapons, AI pilots and encounters; one flight model for all. Speeders and the barge drive on `hover_model.gd`. | `content/core/ships/`, `src/systems/flight/`, `src/systems/vehicles/`, `docs/ADDING_SHIPS.md` |
| **Story, jobs, rumors, state** | Chapters and quests, the job board, rumors; `WorldState` is what is true now and is saved with the world. | `content/core/story/`, `content/core/board/`, `content/core/rumors/`, `src/systems/world/world_state.gd` |
| **Sound and effects** | Playlists, moods, NPC sounds, explosions, materials. | `content/look/sound.json`, `src/systems/audio/`, `src/systems/look/` |

## What can not change

Load-bearing. An issue never asks to replace, fork or work around these. The
reasons are in `DECISIONS.md`.

1. **One scene for every planet.** `town_demo.tscn` builds whatever
   `GameFlow.planet()` says; travel reloads it.
2. **Space is the town's own sky.** No separate space scene for gameplay.
3. **Planets are round and walkable all the way round**, with seamless
   handoffs.
4. **The town data format.** Boxes, markers, routes and zones, read only by
   `town_layout.gd`, passing the validator.
5. **The look layer is optional.** `use_look = false` must still play; styles
   go through `LookMaterials`, never per building.
6. **One movement for player and NPCs, one flight model for every ship.**
7. **Pure brains, run by the existing directors.** No second AI framework.
8. **`WorldState` is the one truth**, saved with the world. No second store.
9. **One LLM pipe.** A new AI character is a card, not a pipeline; effects go
   through `ActionValidator`.
10. **One human skeleton.** Kit pieces on the one rig, recoloured.
11. **Data layer and IP neutrality.** Names and numbers in `content/core/`,
    looks in `content/look/`, no franchise names
    (`tests/test_ip_neutral.gut.gd`).
12. **The engine.** Godot 4.7.2, GDScript, no new autoloads or plugins
    without the user saying so.

## Issue format

Match the issues already in the repo (#272, #276, #291 are good ones). Plain
English, short sentences, the player's view first.

```markdown
<Title: Thing: what the player sees, in a few words>

Part of #N. / Follows #N. / Split out of #N.   (when it has one)

# What and why
Two or three sentences: what the player gets and why it matters.
What happens today, if it helps ("Right now there is none").

# Done looks like
* **Bold lead-in:** one behaviour the player can see or do.
* Numbers (sizes, speeds, prices) are tunable in content data, not code.
* **Headless test:** a concrete scenario and its outcome.

# Could have
* Wanted, but the issue ships without it.

# Built from
The parts and files, and the render rung (data / mix / shapes / one render).

# What this leaves behind
One line: the config shape, block, piece or layout the next issue can reuse.

# Not in this issue
* Deferred nice-to-haves and the issues they belong to.

# Still open
* Only questions the user chose to leave for later.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

Rules: must-haves in "Done looks like", could-haves in "Could have", nothing
else slips in. Every behaviour is something the player can check. Link
related issues by number. Use the game's own names (Oda, Skrugs, Grit
Station, the Remnant), never franchise names.

**Labels:** one type (`enhancement`, `bug`); one size (`size: S` one focused
PR, `size: M` one solid PR, `size: L` two or three PRs, `size: XL` split
into a milestone with sub-issues); areas that fit (`area: world`, `area: cantina`,
`area: visuals`, `area: llm-npcs`, `area: saves`, `area: performance`);
`blocked` if it waits on another issue.

# Writing the PR

One feature per branch (`feature/...`, `fix/...`), off the latest `main`,
merged by PR. The gate is `tests/test_smoke.gut.gd` plus a clean headless
boot of the town; name anything else you did not run.

**Every PR comes down to what the user wanted.** The body opens with their
words: a quote from the chat when you have one, otherwise a one-sentence
paraphrase of the issue's ask in the player's terms, marked as a paraphrase.
A reviewer reads that line, then checks the rest against it.

```markdown
<Title: Thing: what changed, in the player's terms>

> "I want the boost to run out, not last for ever."   (the user, or: paraphrased from #N)

Closes #N.

## What changed
* **Bold lead-in:** one change the player can see, and the part it rides on.
* Keep to the issue's "Done looks like"; say what from "Could have" came along.

## Screenshots
Before and after stills, or a short clip, for anything visual. Commit them
under `docs/lookdev/<area>/` (or `docs/<area>/`) and embed with the raw
GitHub URL on this branch. `tools/lookdev/shoot.sh` captures stills.

## Checked
* The suites and probes that ran, with their counts, and what failed on
  `main` already.
* Not run: the rest, by name.

## Leaves behind
One line: what the next builder can reuse from this.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

Rules: a PR does one issue. Anything found on the way goes in a new issue,
not the PR. If a behaviour in "Done looks like" is not in the PR, say so
under "What changed".
