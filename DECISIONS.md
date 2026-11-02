# Decisions Log

Every significant technical choice, the alternative, and why. Newest on top.

## 2026-11-01 — Places repaint for whoever holds them (issue #393)

- **Repaint the materials in place, never rebuild the meshes.** The Remnant's
  red marks (the barracks' bands, the gate towers, the lintel, the wall, the
  watchtower banners, an outpost's band, door frame and lamps) are made through
  `LookMaterials.faction_*`, which remembers each material and its role, and
  `repaint(owner, group)` sets the colour on the material the meshes already
  share. Alternative: re-dress the barracks and the outposts on a swap.
  Rejected: the town's buildings are batched into MultiMeshes and the swap
  happens out of sight anyway; a parameter change is free and cannot leave a
  half-built block.
- **The town is one group, each outpost its own.** The town follows the
  barracks' owner with the guard swap (`_locals_take_barracks`,
  `_return_town_remnant`); an outpost follows `RemnantOutposts.swap`. An
  outpost's flats are duplicated out of the shared cache so one outpost can be
  green while the next is red.
- **Colours are data by role** (`content/look/town_styles.json` `factions`:
  `band`, `wall`, `mark`, `lamp`), so the holo table or the F1 screen can read
  the same two colours later. The locals' guard is the trooper kit recoloured
  (`guard:locals`: bone plate, green trim), not white: the art direction keeps
  white armour out.

## 2026-11-01 — A story save and a free roam save, side by side

- **One file per mode** (`SaveSlots`: `save_story.json`, `save_freeplay.json`),
  not one file with two worlds in it. Each file stays the same SaveSystem v3
  shape, so nothing that reads a save had to change. Alternative: numbered
  slots. Rejected: the player asked for exactly story and free roam, and the
  mode is already in the save.
- **A switch is a launch.** `SaveSlots.fresh_launch()` puts back everything a run
  keeps across town reloads (GameFlow's planet, flown ship and resume, the free
  roam tweaks, the F11 town layout, T-89's hello), then the other save's world is
  loaded *before* the town reloads, so every part of the build sees the right
  mode. The town being left saves first, then stops saving (`autosave` off), so
  its exit cannot write the next game into its file.
- **The outfit and the names go with the save.** The outfit file is per slot. A
  new game keeps the names of its own slot, not the game you were playing.
- **The old `save.json` is copied, not moved,** into the slot its mode says, once
  (the pick file marks it done). Builds from before the slots, in other
  worktrees, keep finding it.

## 2026-11-01 — The barracks change hands back and forth

- **Dead troopers at the barracks stay dead once the fleet is beaten.** The
  town's troopers came back after 60 s, so the locals could never win the
  barracks by fighting for it. A tally per post in `WorldState.control`
  (`remnant_dead`, like the locals' `barracks_dead`) and no respawn after the
  fleet is beaten make "kill them all" possible and keep it over a reload.
  Alternative: pause the respawn only while you are fighting there. Rejected:
  leaving and coming back would undo the fight.
- **The swap waits until you can't see the barracks.** Same idea as the
  outposts (`RemnantOutposts._tick_control`), but stricter: the locals don't
  walk in after `move_in_s` while you watch. The first look at load is free,
  so a save loads with the right side already there.
- **Driven off, the Remnant come back only through the barracks.** The
  player's choice: no slow return on their own. Killing every local guard at
  the barracks clears `remnant_driven_off`, and the locals' outposts start
  again from a full hold so they don't all fall on the next tick.

## 2026-10-31 — AI characters off by default; the cloud picks its provider from the key (issue #328)

- **AI characters are one switch, off on a fresh install** (`ai_enabled` in
  `content/core/llm/defaults.json`). Off, `LLMService.active_chain()` is empty, no
  health checks run and the sidecar never starts, so the town makes no network
  call and every turn is canned at once. It is a flag beside `mode`, not a sixth
  mode, so the player's choice of local / ollama / cloud survives turning it off
  and on. Alternative: an "off" mode. Rejected: switching back on would have to
  remember the mode it replaced.
- **The story never needs a model.** Every AI character gets a topic menu built
  from `content/core/npcs/topics.json` and their card's canned lines, which already
  read real `WorldState`. Card hints carry an authored `line`, added after the
  three-sentence cap. The general's pit meeting and the dark master's offer reach
  their verdicts after `turns_offline` written lines. `tests/test_ai_off.gut.gd`
  plays land → free with a spy provider that must never be asked anything.
- **Local models warm in the background, and player turns skip them meanwhile.**
  `LLMService.warm()` sends a one-token request (Ollama loads its model on the
  first one) with a long timeout. Until it answers, that provider is out of the
  chain, so the player's turn goes to the next provider or is canned now, and the
  next turn tries again. Alternative: let the player's turn wait on the load.
  Rejected: a 30B model can take far longer to load than anyone waits at a bar,
  and cutting the request off on a timeout can stop the load. `gen.give_up_ms`
  still caps any turn with no first word.
- **A turn with nothing to try finishes next frame, not inside `chat()`.** Before,
  an empty chain called `finished` before the caller had stored the turn id, so the
  brain (and F10 Test) never heard back. The brain now answers canned straight
  away when the chain is empty.
- **The cloud key picks its provider** (`key_presets`: `sk-ant-` → Anthropic,
  `sk-or-` → OpenRouter) unless the player set the URL or type by hand. Why: a
  stored Anthropic key was being sent to the OpenRouter profile, which was also
  switched off, so cloud never answered. The cloud profile is now on by default
  (it still needs a key, and the whole AI is off until the player says).

## 2026-10-31 — Divergent endings: the Remnant can be gone and still your friends (issue #303)

- **"Gone" and "hostile" are two questions now.** `Story.remnant_gone()` (the
  fleet is beaten: the town garrison leaves, the general wears the desert
  armour, the barracks go to the locals) and `Story.remnant_hostile()` (gone,
  and you did not swear the dark master's oath: fighters, outposts and droids
  shoot on sight). Alternative: keep one predicate and special-case the oath at
  each call site. Rejected: the barracks owner needs "gone" while the troopers
  need "hostile", and the two would drift apart.
- **The fleet is beaten at the general's death, not at the end card.** The
  locals have to hold the barracks while the oath is open (their guards are its
  target), so the `debrief` chapter starts with the Remnant already gone. Free
  roam does the same in `WorldState.on_cruiser_taken`.
- **The town changes hands on a world rule, not on the pact.** Every local guard
  on the barracks posts dead (saved per post in `WorldState.control`) hands the
  town to the Remnant in any mode; the oath only decides whether they come back
  friendly and whether it ends the story. Alternative: a pact-only scripted
  takeover. Rejected: the free-roam game is meant to diverge the same way.
- **The dark master is driven by his own node, not a garrison.** A sword fighter
  does not fit GuardBrain (cover, bursts, aim). DarkMasterPost moves his NpcBody
  with a small pure brain (BladeFighter) the way NativesDirector runs the
  nomads' melee; NpcBody only gained a damage hook (deflect/parry), a held pose
  and a held sword.
- **Checkpoint saves.** `WorldState.checkpoint(why)` runs the hooks the town's
  ConversationHost (which owns the save) registers. Before this the game only
  saved when a talk ended or the scene closed, so a crash after the general's
  death lost it.

## 2026-10-30 — The Remnant cruiser is part of the home planet's map (issue #193)

- **Not a planet of its own.** The cruiser is a landmark of the home world
  (`kind: "cruiser"` in `content/core/worlds/port_desert.json`), like the wreck:
  its boxes go into the ship's WorldGround, its look and crew are a node in the
  home town scene (RemnantCruiser), and its data is one file
  (`content/core/cruiser/remnant_cruiser.json`). Alternative: a new planet type
  with its own scene and a space.handoff, as the asteroid has. Rejected: a
  planet's scene is a town (TownGen, a cantina, an Oda, a ball of terrain), and
  the cruiser has none of that; and a handoff ends a running space fight, while
  Oda's job is a fight on the way up that you can run from straight into the
  bay. In one scene the escort, the flight across and the landing are one sky.
  The cost (a 690 m ship in the home scene) is kept small: its parts merge into a
  dozen meshes, its crew is built only when you come within 2.6 km, and they
  sleep when you are not near them.
- **Level with the port, not with the ground under it.** It hangs 75 degrees
  round the ball, where "up" is nearly sideways to the port's. Its decks are
  square to world up instead, and a gravity zone (PlanetSphere.gravity_zones)
  makes up world up aboard. The crew's walking, eyes, aim and paths (NpcBody,
  NpcLocomotion, Perception, TownNav) all assume up is close to world up, as it
  is round the port; aboard it is exactly that, so all of it works unchanged.
  Alternative: the cruiser level with the ground below it and every NPC system
  made frame-aware. Rejected for now: dozens of world-up assumptions, for a ship
  in orbit, which can hold any attitude it likes.
- **Hidden by the curve.** 7 km up (4.6 at first) over a point 6.5 km east along the ground,
  the line from the port to it passes through the ball: you cannot see it from
  town, and it is plain to see from space.

## 2026-10-30 — A shooter's feedback in the ship (issue #181)

- **The cockpit is painted, not modelled.** CockpitView draws the canopy tint, two
  struts and the dash (with its instruments) on a CanvasLayer. The cockpit camera
  is locked to the ship, so a flat frame never moves against the view, exactly as a
  model would not; it needs no per-ship geometry, so one cockpit fits every ship,
  and the instruments are plain 2D drawing that headless tests can call.
  Alternative: a 3D cockpit mesh on the camera with SubViewport textures for the
  dials. Rejected: a model per ship size (or one that clips through big ships),
  extra viewports to render, and nothing gained while the camera cannot look round.
- **Hits on ships count only when the owner took them.** ShipHull now carries the
  same `damage_usec` stamp and `dead` flag NPCs do, set by its owner (ShipPilot for
  parked ships, AtmoFighter for the interceptor), so HitFeedback can tell a hit that
  hurt from one shrugged off. Before, any bolt on any hull counted. In space the
  director already reports its hits and kills, so those drive the marker directly
  (HitFeedback.confirm).
- **Bursts report what they caught** (bolt.gd `on_splash`), so strafing troopers
  shows a marker even when the bolt lands beside them, not on them.

## 2026-10-27 — Dead droids across the home planet (issue #93)

- **Seed a field once, then replenish slowly.** The home ball starts with eight
  saved wrecks and can hold twelve; later finds keep the existing timed chance.
  Flat worlds retain their old three-wreck ring. Alternatives: only raise the
  timer chance (a new game would still start empty) or seed every scene load
  (fixed wrecks would immediately be replaced). The initial field is sampled by
  spherical area, kept 900 m from town and 500 m apart along the surface, then
  checked against WorldGround's buildings and landforms.
- **Place against WorldGround, not the flat height callback.** A wreck's stored
  position is the spherical ground point and its body is aligned to local up.
  This uses the same surface and tangent frame as the ship and living droids;
  flat worlds continue using their existing height callback and placement.

## 2026-10-27 — Finer far-planet sand (issue #93)

- **64 samples per far chunk, with the chunk layout and terrain unchanged.** The
  whole-ball mesh previously used 4 chunks per cube-face side and 48 cells per
  chunk side. Raising only the latter to 64 reduces far-cell spacing by 25% while
  retaining 96 chunks, their matching borders, the same `PlanetSphere.elevation`
  source and radial `radius + elevation` placement. Near and mid meshes, their
  colliders, and map scale are untouched. Alternative: more chunks, which would
  also raise draw calls; or a larger mid ring, which does not improve the far
  silhouette. Rejected for this coarse-horizon item.
- **Bounded cost:** far vertex and index counts rise about 1.8x (roughly 221k to
  393k vertices and 1.27M to 2.29M indices across the ball); the packed vertex,
  normal and index arrays total about 10.4 MB to 18.6 MB before engine/GPU copies.
  The same 96 chunks are still generated in parallel at load, so far-mesh CPU work
  also rises about 1.8x; no recurring rebuild or collision work is added. The
  focused sphere test checks the chunk vertex budget, finer spacing and radial
  height agreement.

## 2026-10-27 — New player, guard and cantina owner art, built like the locals (issue #79)

- **Do not run the full test suite.** We are not going to run this because it takes way too long, and the human builders can test if it matters for gameplay faster than the tests can run. Instead, run a small baseline tests and smoke tests (e.g. app loads, new feature seems to work), if it seems to pass, open the PR and tell them **how** to test it.
- **Costumes come from the concept sheets now.** Each is one Hyper3D generation
  from its sheet's front and back views plus a prompt, rigged with the human
  template and fitted onto the kit's base body, so all three are cut at the same
  neck and waist seams and every head, upper body and lower body mixes. The prompts
  ask for a collar ring and a thick belt at those seams and an A-pose with space
  under the arms. Alternative: prompt only (#48). Rejected: the owner wanted the
  concepts' looks, and the references were followed closely.
- **The guard is the simple white run, baked grey.** A gunmetal re-run came back
  too detailed for the game's look. The fit recolours the white armour to gunmetal
  (`recolor` in `dress`), so the plain guard is grey and its colours start from
  there.
- **The cantina owner's legs are a separate piece.** Her tunic came back
  mid-thigh with no body under it, so a cut at the belt left a hole. The hem goes
  to her upper body by colour (`move`, pushed out a little so the legs stay under
  it); its back half is dropped (`drop_back`), since it did not render well behind
  her, so it hangs in front like a tattered apron. Her legs are a prompt-only generation (skin-tight leather trousers,
  boots) fitted into the legs slot. Alternative: fill the gap with the base body's
  hips in her trouser colour. Rejected: it read as a flat patch.
- **Outfits keep their own Hyper3D weights.** Copying each vertex's weights from
  the nearest base-body vertex gave belt pouches and the owner's apron hand and
  forearm weights (the hands hang beside the hips in the A-pose), so they
  stretched after the arms when running. Each outfit was rigged with the same
  human template, so its own weights are kept, bones matched by name
  (`own_weights`); the copied weights only decide the cut.
- **Accents get their own tolerance.** A colour variant's swap can carry its own
  tolerance and brightness floor (`recolor_fitted.gd`): a saturated red spreads
  further in chroma than a grey, and its dark folds sit under the floor that keeps
  the black undersuit out of the grey swap.

## 2026-10-27 — P1, the planet generator (issue #45)

- **A planet is data, and so is its town.** A config file becomes a town layout
  in the port's own format (boxes, markers, routes, zones), a world dict and a
  style. The town scene builds whatever `GameFlow.planet()` says. Travel reloads
  the same scene as another planet. Alternative: a scene per planet. Rejected:
  every new planet would be a scene plus wiring, and the issue asks for "mostly
  boilerplate with configurations".
- **Generate in the port's conventions, not a new format.** TownGen emits the
  cantina's ids, the pad's `ship` box, the gate markers, the market's stall pairs
  and the residential zone names the decor already understands. The validator,
  decor, bar, garrison, townsfolk, nav and ship pilot needed no new code paths for
  generated towns. The port stays hand-built: its planet config names
  `port_town` and `port_desert`.
- **Size is area, not a building count.** The area inside the walls is
  (size / 50) ^ 2.32 of the port's, so 100 is 5x. Counts of guards, stalls,
  residents and bays scale with that area. The minimums make size 1 the issue's
  "cantina, one guard at the door, one merchant out back". Layout is blocks along
  a main street, then a lot grid that keeps a lane clear of every block, so towns
  are valid by construction. All 100 sizes are tested.
- **Styles restyle materials, not buildings.** Every town material is made by
  LookMaterials, so the style is a filter there: walls, bands, paving, hull metal,
  props and cloth. Plaster and hull shaders gained finish settings (metallic,
  roughness), with defaults that leave the port as it was. Metal styles draw walls
  with the hull shader. Free words go through a small vocabulary (colours, shades,
  finishes, materials) in data. Alternative: per-building style variants.
  Rejected: every new style would mean touching every building.
- **Platforms instead of terrain for element worlds.** Water, lava, gas and
  asteroids put the town on a deck with a hull underneath, so nothing can fall
  through.
  - The glass rises from the existing perimeter walls and is solid to the player
    and to ships through WorldGround. The gate's shield has no collision.
  - The deck's own fall replaces the fall guard: fade, a line, wake by the bay,
    nothing taken.
  - The ship's ground over the void is the surface far below, and it may only land
    on the town's floors.
- **Neighbours are where their config says.** A planet's `at` is where it hangs
  in its `near` planet's sky. The way back is computed from the same numbers, so
  one line places both directions. Flying within a body's radius plus 400 m
  travels. The ship you flew is parked on the other planet's pad, and its twin bay
  in the port is skipped, so you never see two of one ship.
- **The station's owner is a variant, not a new model.** Character archetypes can
  name a `base` and list only what differs. A `tint` on the model multiplies every
  surface colour and swaps the glow colour, so Ilka is Oda's rig and mesh with
  copied, tinted materials.
## 2026-10-27 — Gear and droid models, ragdoll deaths (issue #25)

- **Rodin text mode, two rounds, picks reviewed on a sheet.** The first round's
  prompts were long and detailed. Rodin drifted toward familiar archetypes (a red
  sniper rifle, a quadcopter, a wheeled rover, a generic android). Round two used
  shorter prompts that lead with the silhouette and the main colour. The owner picked
  round 2 for the rifle and the floating and cargo droids, and round 1 for the
  assassin droid. Every id is in `content/look/gear_models.json`; rejected sources
  were deleted and can be fetched again from Hyper3D Mine.
- **Pistol, jetpack and cargo case came later, in the same short style.** The
  first pistol was a plain real-world revolver and the first jetpack a diving rig on
  wheels; the second tries were kept. The jetpack keeps the kit's flames
  (`flames_at`), so a model never flies without them.
- **The assassin is rigged by Hyper3D, not by the kit.** The human template rig
  plus four stock clips (Walking, Running, OffensiveIdle, StandingDeathBackward01)
  came with the model. Walk and run are made in-place at load (the root bone keeps
  only its bob), because the controller moves the droid. The eye and muzzle ride
  the head and hand bones. Alternative: retarget the CharacterKit animator onto it,
  as the guards do. Rejected: the droid has no kit joints, and stock clips were one call.
- **The fused pistol is cut out, not regenerated.** The owner's pick was generated
  holding a gun. Prep drops right-hand triangles further than 0.16 m from the
  wrist (`cut`), and DroidKit pins the pistol model to the hand bone. Its place in
  the bone's frame (`carry.bone_local`) was solved so it sits level and forward
  in the idle clip. Alternative: a new generation without the gun. Rejected: text
  mode would not give the same droid back. T-89 uses the same model without the
  pistol, and the extra HappyIdle clip from a second rigging run as his idle.
- **Droids follow with a leash.** A droid starts closing the gap only once the
  player is `leash` metres away, and stops inside `settle` of its slot. Before, it
  chased its slot every frame, so any step the player took moved every droid.
- **One cargo case model for every cargo.** It is a 1 m cube in prep, and each look
  stretches it to its own width, height and depth and tints it toward its shell
  colour. Alternative: a model per cargo. Rejected: four generations for what is a
  size and a colour.
- **The energy sword stays code-built.** Four attempts failed: an ornate fantasy
  sword, three crossed katanas, a scissor-like hilt, and a hammer with a stub of
  light. Text mode cannot hold a long, thin, two-material object. Alternatives were
  agentic mode fed renders of the current sword, or more text prompts. The owner
  chose to keep the procedural sword, which already ignites a yellow laser blade.
- **Droids tint one model per kind.** The variant's body colour multiplies the
  model's albedo (`look.tint`). The cargo droid came out yellow, so prep washes its
  texture toward grey first (`desaturate`). Glowing eyes and the muzzle are placed
  from data, so `set_awake`, wrecks and the guns did not change. Alternative: one
  generation per variant. Rejected: eight more models for a colour change.
- **A point-mass ragdoll on the kit joints, not PhysicalBone3D.** Characters are a
  CharacterKit joint hierarchy (a SkinnedBody copies it onto the rig each frame).
  So a Verlet sim of 21 particles, with bone-length links, two rigid torso blocks,
  hinge and reach limits and one ray per particle against the world, writes joint
  rotations, and primitive and skinned bodies fall the same. Alternative: Godot's
  PhysicalBone3D. Rejected: it needs a Skeleton3D under every body, and the
  primitives have none. It would also be a second pose source fighting the
  animator, and getting up would mean blending back from bone poses.
- **The kick comes from the shooter.** Bolts already pass their shooter
  (`apply_damage_from`). The player body now records where hits come from too, so a
  knocked-out player falls away from the guard who shot them.
- **The dead drop their rifle as a real rigid body** (`Ragdoll.drop`). It is frozen
  after 20 s so the town does not keep simulating it.

## 2026-10-27 — The port's fleet: every parked ship is flyable (issue #43)

- **Agentic models for the interceptor and speeder.** Hyper3D's agentic (n-gon) mode,
  fed orthographic crops of the old stand-ins, gave clean, minimal hard-surface models that
  keep the originals' silhouettes. Alternatives tried:
  - Rodin high-poly with the same references copied the primitive boxes as they were.
  - Rodin text-only drifted toward real-world jets, and a speeder with wheels.

  The freighter, courier and gunship are Rodin text-only picks, after one retry each to
  fix the shape. Runner-ups are kept in `assets/vehicles/source/` (listed in
  `content/look/vehicle_models.json`), which carries a `.gdignore`, so Godot does not
  import them.
- **No copy of a film ship.** The issue's saucer spec described one franchise ship
  feature for feature. ART_DIRECTION pillar 6 rules out franchise silhouettes, so the
  freighter keeps the idea (an industrial disc, sensor dish, turret, blue engine glow)
  and drops the signature parts: the twin front mandibles and the side-mounted
  cockpit. Bolts stay cyan for the player's side, not red: in ART_DIRECTION, red-orange
  means remnant fire.
- **Berths, not a ship picker.** `ShipPilot` keeps one `AtmoFlight` and swaps which
  berth it drives when you board another parked ship: its data, model, hull and home
  bay. Alternative: an `AtmoFlight` per ship. Rejected: only one ship flies at a time,
  and the others only need a hull to bump into. The space fight takes the boarded
  ship's id (`SpaceFight.begin(player_ship)`), so the ship you take up is the ship
  that fights.
- **Shift is a per-ship ability on the boost meter.** `flight.ability.kind` is one of:
  - `boost`: as before.
  - `drift`: velocity is held along the old heading while the nose turns faster.
  - `brake`: speed bleeds toward `brake_speed`, never under `min_speed`, while the ship turns faster.

  They live in `FlightModel`, so atmosphere flight, the dogfight and the AI share one
  rule. Alternative: abilities in `ShipPilot`. Rejected: the space fight would not
  see them.
- **Blaster power is one multiplier.** `blaster_power` scales every bolt's damage in
  `ShipLoadout`, so a ship's punch is one number, and guns stay shared weapon data.
## 2026-10-27 — The player and the guards wear pieces of one kit (issue #48)

- **One base body sets the skeleton and the seams.** A featureless mannequin
  (Hyper3D Rodin, rigged with the human template) is split once into head, torso
  and legs. Every costume is fitted onto it, and each vertex takes the bone weights
  and the part of the nearest mannequin vertex (`fit_parts.gd`, `dress`), so every
  outfit is cut in the same places and pieces mix freely.
- **Costumes are generated from a prompt alone, then re-posed.** Reference images
  win over the prompt: renders of the mannequin, even tinted, came back as the bare
  mannequin. So each costume is a prompt-only whole character, rigged with the same
  template, and its arms and legs are turned to the mannequin's rest pose before
  fitting. Alternative: generate each piece separately from crops of the mannequin.
  Rejected: separate pieces did not meet at the seams and kept their own style.
- **Cleanup is in the config, not by hand.** `trim_top` and `trim_below` drop
  stray triangles (a scarf poking above the collar, armour hanging between the
  hands), and a piece can be replaced on its own (the player's head was regenerated
  alone and fitted into the old head's bounds).
- **Colours are recoloured textures, like the locals'.** One texture per outfit,
  so a variant is written once and fits all its pieces; a piece with its own
  texture (the player's head) has its own variants, looked up first.
## 2026-10-27 — The sound library and the music (issue #16)

- **One static library, `Sound`, lazy like GameFlow (no autoload).** The first call
  puts one node under the tree root, so it outlives `change_scene_to_file()` and the
  music does not restart on a launch or a landing. Callers say `Sound.play(key, at)`,
  `Sound.loop(key, parent)`, `Sound.battle()`, `Sound.set_space(on)`. Alternative:
  an autoload. Rejected: the project keeps nothing running that no scene asked for,
  and the lazy node needs no project setting.
- **Existing sounds stay where they were.** The blade, guns, steps and NPC sounds
  keep their own players and data files; they only moved onto the SFX bus. The new
  library covers what had no sound. Alternative: move every sound into
  `content/look/sound.json`. Not worth the churn for this issue.
- **Two buses (`default_bus_layout.tres`): Music and SFX.** The F11 panel sets each;
  saved in `user://settings/sound.cfg`. Voices (Kokoro) stay on Master.
- **Synthesized, not downloaded.** Every new effect is made by
  `tools/audio/make_game_sfx.py` (standard library only, no numpy), like the blade
  and NPC sounds before it: nothing to license, nothing to attribute, and re-runnable.
  The free libraries the issue lists (Kenney, Sonniss, 99Sounds, ...) stay an option
  for a later pass if a sound needs more than synthesis gives.
- **Music is free tracks from Pixabay** (https://pixabay.com/music/, the Pixabay
  Content License: free to use, no attribution needed), downloaded by the owner
  (Ambient1-3, Battle, Space),
  loudness-matched and re-encoded to 160 kb/s MP3 by `tools/audio/rip_music.sh`
  (this machine's ffmpeg has no Vorbis encoder; Godot loops MP3 natively).
- **Battle music is triggered by an NPC's shot, not by alarm state.** Every NPC that
  fires only fires at the player (locals and troopers ignore each other), so
  `NpcBody.fire_at` calls `Sound.battle()`. The track starts and loops at 30 s.
  Priority: space > battle > ambient.
- **Coin sounds watch `WorldState.credits`** each frame instead of hooking every
  place credits change (jobs, bribes, payouts, vendors, the pit's fine). One
  check catches all of them, including ones added later.
- **Dogfight shots became events.** `dogfight.gd` adds `shot` events (and a position
  on `missile`), and `DogfightView.on_event` plays them, so the stand-alone space
  scene and the fight in the town's sky sound the same.

## 2026-10-27 — Space is the town's own sky (issue #46)

- **One scene, not two.** The space fight runs inside the town scene (`SpaceFight`,
  the same pure `dogfight.gd` director) instead of `change_scene_to_file` to
  `dogfight_demo.tscn` and back. Alternative: keep two scenes and hide the load
  (a loading screen, or background-loading the next scene). Rejected: it still
  throws away the town's state, and you cannot come down where you went up
  without re-creating the whole port.
- **The fight flies your ship while it runs.** On reaching space the director's
  player ship takes the town ship's transform and speed; each frame ShipPilot
  copies it back onto the AtmoFlight model, so the parked model, chase camera, sky
  and HUD need no second path. Alternative: one flight model for both. Rejected
  for now: the atmosphere and space blocks of each ship are tuned separately.
- **The encounter is placed, not re-authored.** `SpaceFight.placed()` moves the
  encounter's spawns onto the ship and turns them by its heading; `Dogfight` got a
  `wave_yaw` so waves arrive ahead. Encounter JSON is unchanged.
- **The stand-alone space scene stays.** `dogfight_demo.tscn` still runs on its own
  (F6, the M10 trace, review renders), and the GameFlow pad launch still works for
  a quick-launch pad. Only the town ship stopped using it.
- **Detail by altitude, from data.** The lag was most likely SDFGI: it rebuilds its
  cascades as the camera moves, and a ship moves hundreds of metres a second. Tiers
  in the world JSON switch render features off (through `LookEnvironment`, so the
  L key cannot bring them back mid-flight) and hide and pause node groups. The
  thresholds are first guesses, to tune on the Mac.
- **A smaller planet, the same desert.** Planet radius halved and the skirt cut at
  the horizon. The 6 km desert was kept: two mesas sit near its edge, and the
  flight and walking traces use it.

## 2026-10-26 — Locals are mix-and-match: one model, three parts, six colours

- **One rigged model, split in prep.** Generated with Hyper3D Rodin from a prompt
  (sand head scarf, goggles with black lenses, no face; loose linen shirt and
  trousers), rigged with the human template, then cut by `prep_character.gd`'s new
  `split` step into `head`, `torso` and `legs` meshes on the same skeleton. The
  cut is by height (collar, belt top), with the arm bones keeping the gloves on the
  torso. Alternative: generate each part separately, or Rodin's BANG part splitter.
  Rejected: separate generations would not meet at the seams, and BANG's parts
  lose the rig.
- **Colours are recoloured textures, not generations.** All parts share one
  texture, so `tools/look/recolor_parts.gd` writes one recoloured copy per colour
  (cloth only: dark texels such as the lenses, belt, gloves and boots stay) and any
  colour fits any part. Six colours (sand, darker, lighter, blue, red, yellow) on
  three parts make 216 locals. A new colour is a line in `character_models.json`
  plus a rerun; a new part list is a line in `characters.json`. Alternative: a
  tint shader at runtime. Rejected for now: the request was for edited files, and a
  texture keeps the stitching and shading the generator painted.
- **`CharacterKit.build()` picks the outfit.** Random per part from the kit's
  `rng`, or fixed with the new `outfit` argument; the choice is the body's
  `outfit` meta. Materials are shared per colour, so a crowd costs six materials.
- **Known gaps.** The staff and woven pack of the old primitive local are gone
  with the primitives (the model has neither). The goggle frames take the head's
  colour, and the foot wraps take the legs' colour.

## 2026-10-26 — N1, the naming system (issue #15)

- **One engine, many kinds, all data.** A kind is a weighted list of templates
  over word lists, shared rules and made-up words. People, callsigns, ships,
  equipment, makers, towns, planets, moons and stars are all just kinds in
  `content/core/names/kinds.json`. Alternative: a generator per thing -- rejected,
  because the issue asked for one engine, and a new kind of name is a JSON entry.
- **Deterministic, keyed, then checked.** The seed is a hash of (world seed, kind,
  the thing's stable key, attempt), using FNV-1a, which is stable on every machine,
  unlike String.hash(). The same thing gets the same name across scenes and new
  games. A clash re-rolls with the next attempt, so even the re-roll is
  repeatable. Alternative: random names saved once -- rejected, because the issue
  asked for a deterministic process, and a seed is something a save can carry.
- **"Elegant yet complicated but not complex."** The grammar has seven tokens and
  no conditions. The variety comes from the library's size and from tongues:
  per-culture sound tables that build words syllable by syllable, with a
  vowel-run cap and banned clusters to keep them pronounceable.
- **Original words, not another game's.** The issue suggested training on a
  shooter's NPC names. That is franchise IP, and the repo must stay IP-neutral.
  The library is written in that spirit instead. Franchise names are blocked as
  whole words (`name_terms` in the IP blocklist, beside the substring `terms`), so
  "Han" is out but "Hanna" is fine.
- **Data says how a thing is named.** A `naming` block on a soldier, ship, item or
  world picks the kind, the title list and the callsign. `NameHooks` is the one
  place spawners call. Titles are picked deterministically from the key, not
  generated, so they never use up a name.
- **The book lives in WorldState and is saved.** Names, the labels as shown and
  the world seed go into the save. Authored names (the bartender's) are reserved up
  front.
- **The library has a source script.** `tools/names/lexicon_source.py` holds the
  word lists as plain space-separated text, which is easier to grow than JSON
  arrays. It writes the JSON the game reads. Both are committed.

## 2026-10-26 — Oda wears a rigged model with a gas mask and glowing goggles

- **The body comes from the concept's back view only.** Given the front and side
  views, Rodin copied the concept's cloth face wrap and ignored the prompt's gas
  mask. A text-only run made a good mask on the wrong outfit (khaki hazmat). The
  back view plus a prompt kept the outfit (hood, long scarf tail, dark jacket, belt
  and pouches) and left the face free.
- **The gas mask is a separate Rodin prop welded on in prep.** A new `attach` step
  in `tools/look/prep_character.gd` scales and places the prop, skins it all to
  `Head`, and cuts the parts we don't want: the mannequin bust the generator put
  inside the mask and the straps that poked through the hood. It stays one .glb, so
  the game code doesn't change. Alternative: hang the mask on the head joint at
  runtime. That would put a second model on every scene that builds her.
- **The goggles glow from flat emissive discs over the lenses.** The prop's lenses
  were clear glass with a face behind them; the discs hide that face and give the
  yellow cyborg eyes.
- **Decimated in prep.** These were Rodin's high tier (500k triangles each; the
  first export was 110 MB, over GitHub's file limit). A `decimate` step keeps
  meshoptimizer's coarsest LOD above a target: body 125k, mask 44k, 35 MB. The next
  body LOD (~42k) collapsed the top of the hood, so she stays heavier than the
  smuggler (26k). She is one NPC behind a counter.
- **BartenderNPC syncs the skin every frame** after its IK, as the player does.
- **Known gap: the apron.** The model wears a long split coat; the concept's
  bib apron didn't come through. Left as is for review.
## 2026-10-26 — The smuggler is regenerated without a jetpack

- **Flattening the concept's jetpack did not hold up in game.** The pressed-flat
  plate z-fought the coat and showed as blotchy patches on the upper back.
- **Regenerated from a front render of the first model.** The jetpack cannot be
  seen from the front, so Hyper3D modelled a plain coat back, and the look stayed
  the same. Alternative: hand-model a coat patch. Rejected: a new generation gave a
  real back for the same effort. The prep step no longer flattens anything; the
  arm-weight fix and the goggle glow still apply.
## 2026-10-26 — M15 part 3 (garrison, sound, crouching, smuggling)

- **One alarm for the town, not one per gate.** `TownAlarm` (pure) owns whether
  the garrison is fighting and how it ends (everyone down, fled, downed); the gate
  `Checkpoint` only decides when the gate starts one, and follows the alarm with
  `set_alarm()` (no second bark, no second standing hit). The director became
  `Garrison` (was `GateCheckpoint`) and runs every soldier in town by its
  profile's `role`: gate, sentry, yard.
- **Profiles inherit.** `tower_sentry.json` and `yard_trooper.json` start from
  `gate_guard.json` (`"base"`, merged block by block in `CoreContent.get_soldier`),
  so shared numbers live once.
- **Troopers are leashed.** Without it the barracks pair chased a fleeing player
  out into the desert forever and the alarm never calmed. `chase_leash` (gate 30 m,
  barracks 55 m) caps where a trooper will go in a fight, and the alarm's escape
  distance (40 m from the nearest trooper) sits below what the desert allows past
  the leash. A unit test checks the two numbers agree.
- **The sentry fights from the rim.** From the middle of the 6 m tower top the
  roof edge hides the street both ways (the sentry could not see the player at the
  tower's foot, nor be seen). On the alarm it steps `hold_radius` (2.3 m) toward
  the threat and never further.
- **Sound: stock where there was stock, synthesized where there was not.** The
  Kenney FPS kit (CC0, already in the repo) covers rifles, footsteps and hurt. No
  voice or siren pack was reachable from the build machine (only the game's own
  repo and package registries), so the radio chatter and the klaxon are
  synthesized by `tools/audio/make_npc_sfx.py`, like the blade sounds. No speech
  engine: the line stays on screen. Mapping in `content/look/npc_sounds.json`.
- **Crouch shrinks the player's capsule** (it used to only lower the pose), in
  `character_body.gd` so the guards share it, with a stand-up check so you cannot
  rise into a ceiling. The camera eye drops with it.
- **Contraband is an item flag** (`"contraband": true`), so a new smuggling good
  is a JSON file. A search checks the player's inventory; papers can still turn
  into a spot search, so the papers band is not a free pass; a bribe before the
  search skips it. The fence is an ordinary vendor that buys the `contraband`
  kind at full value.
- **Cover spots are checked against the navmesh a slice a frame.** The town has
  ~2,900 spots now (the barracks troopers fight anywhere), and checking them all on
  the first cover request cost an 88 ms frame.

## 2026-10-26 — M15 part 2 (combat NPCs at the gate)

- **Two brains, two jobs.** `Checkpoint` (pure) decides what the gate does for
  everyone (wave, papers, search, bribe, warn, fight, disengage, remember).
  `GuardBrain` (pure, one per guard) decides how a guard does it. `GateCheckpoint`
  is the director: it reads the bodies and WorldState in, writes commands, the card
  and WorldState out. Alternative: one brain per guard that also owns the gate
  rules -- rejected, two guards would disagree about whether you are cleared.
- **Standing bands, night bribes and fight outcomes are the product owner's**
  (40 / 0 / -1 / -40; one band lower after dark; kill and run costs standing, but
  you can win). The numbers (prices, deltas, timers) are first guesses in the
  profile.
- **The player can be downed.** Without it "you can win" means nothing. Health on
  the player body (`character_body.gd`) with regen, and a `downed` signal that does
  nothing on its own; the checkpoint turns it into a knockout to the pit. Traces
  that are not about guards switch the brains off (`npc_brains = false`), so the
  older traces keep walking through the gate unbothered.
- **Opening burst, then cover.** A warned target gets shot at once, not after the
  guards have jogged to a crate; the cover dance starts after the first burst.
- **Cover comes from the town's boxes** (`CoverPicker`): spots around every box
  tall enough to hide a crouched body, kept only if the box sits between the spot
  and the threat, on the guard's side of the gate, reachable on the navmesh, and
  not claimed by the other guard. `squad_coordinator.gd` is not used: it looks up
  member positions by cover index and never asks whether a spot hides anyone.
- **Two barricades added inside the gate** (`checkpoint_barricade_n/s`, 1.1 m).
  The gate had no cover a guard could use against the desert side, so every fight
  was two guards standing in the open.
- **Crouching shrinks the guard's capsule**, so a bolt aimed over a barricade
  really misses. The player's capsule does not shrink yet (guards aim at a crouched
  player's lower chest instead, which the barricade blocks).
- **No friendly fire.** Bolts now tell the target who fired them
  (`apply_damage_from`); a guard ignores its own faction's bolts.
- **Corners are only cut on level ground.** With combat sprinting, a guard took
  the pit-ramp foot early and walked into the ramp's side ledge (the part 1 bug
  again, by another route). Taking a corner early, or skipping it when stuck, is
  now only allowed where the path stays level.
- **Footsteps.** A guard facing the gate never noticed a player standing behind it
  in the checkpoint. A moving, standing target within ~6 m is now heard
  (crouch-walking is silent), and a calm guard turns to look at what it heard.
- **Barks are de-duplicated on game time**, not wall time (traces run faster than
  real time), so two guards never shout the same line together.

## 2026-10-26 — M15 part 1 (guards on foot: body, pathing, senses)

- **Guards are not LLM driven** (product owner). The bartender stays the only LLM
  NPC; guards get authored barks and choices in part 2.
- **The fighter pattern on foot.** `NpcBody` extends the player's own
  `character_body.gd`: the same CharacterController, capsule and move_and_slide.
  A brain (part 2) writes `command` (go_to, face, sprint, crouch) and the body
  carries it out, exactly as `FighterBrain` writes a command into the flight model
  the player flies. Alternative: a separate NPC mover -- rejected, two movement
  systems drift apart and the AI ends up doing things the player cannot.
- **Navmesh baked at runtime from the box data**, not baked in the editor. The
  town is data (TOWN_PLAN D-rules), so a baked file would go stale the moment a box
  moves. Triangles are generated from the boxes directly (not BoxMesh, which makes
  Godot read geometry back from the GPU). The bake is ~0.3-0.4 s, so it runs on a
  worker thread; NPCs wait for `TownNav.is_ready`.
- **Godot 4.7 quirk: add the region after the async bake.** A NavigationRegion3D
  added empty and given its mesh later was never picked up by the map. The region
  is now created holding the finished mesh, and readiness is "the map says a point
  of our mesh belongs to our region" (the map ticks once for an empty region, so
  "the iteration changed" lied).
- **Blocking boxes are bake obstructions.** Recast sees surfaces, not solids, so
  the floor inside the closed barracks box baked as a walkable island and a
  "nearest point" query could hand a guard a spot inside a building. Every
  blocking kind is a projected obstruction, except a box a marker stands on (the
  watchtower top keeps its floor for the tower post).
- **Climb 0.1 m, not the usual 0.4.** The capsule (r 0.4, 45 degree floor angle)
  rolls over ~0.12 m and treats anything taller as a wall. At 0.4 the mesh let a
  guard step onto the side of the pit ramp near its foot, where it pinned itself
  for good. The bake must describe what the body can really do.
- **Stuck means "no progress along the path", not "did not move".** A running
  guard (6.2 m/s, with the controller's acceleration lag) circled a pit-ramp corner
  forever: it moved plenty, so a movement check never fired. Corners are now taken
  earlier at speed (`corner_lead_s`) and a window with no progress skips the corner
  and repaths.
- **`map_get_path`, not NavigationAgent3D.** Deterministic and testable, one call
  per repath. Cost: no agent avoidance yet (two guards can bump on a narrow path).
  Revisit when squads move together.
- **Senses as a stealth meter.** Awareness 0..1 rises while seen (x2 close to x0.5
  at the edge of sight, x1.6 armed) and decays when not; noticed latches at 1 and
  clears under 0.3 after `forget_s` out of sight. A heard shot raises awareness to
  0.6 and gives a place to look, never the shooter. Rays only while the target is
  in the cone, at `ray_hz`. Alternative: instant binary sight -- rejected, it gives
  the player no window to duck back behind cover.
- **Noises are a static event list** (`NoiseEvents`) with serial ids, like
  WorldState: any system reports, any listener reads, nothing heard twice, no
  wall-clock time in it. Range-practice shots are tagged `shot_range` so a brain
  can shrug them off.

## 2026-10-26 — Every Remnant wears the rigged guard model

- **One model for trooper and commander.** Generated with Hyper3D Rodin from the
  guard concept sheet (front, side and back views), rigged there, and prepped like
  the smuggler (arm weights moved off the cloak and tunic). The two archetypes keep
  their own height, bulk and pose. Alternative: a separate commander model. Not
  needed yet: the concept is a single design.
- **Rigged models are dressed in `CharacterKit.build()`.** Any archetype with a
  `model` in `characters.json` wears it (the player included), and posed NPCs are
  synced once at build. Alternative: each caller dresses its own body, as the player
  did. That would mean every scene learning about skins.
- **The trooper keeps the kit rifle.** The concept's hands are empty, and so is the
  model; the rifle is the game's prop, and the posed hands hold it.
- **Known gap: the visor.** The art direction says to avoid T-visors. The concept
  has one, and the prompt asked for a single slit, but the model still reads as a
  T. Left as is for review.

## 2026-10-26 — The player smuggler gets a rigged model

- **Generated with Hyper3D Rodin from the concept art, then rigged there.** The
  human-template rig is retargeted onto the CharacterKit joints each frame
  (`src/systems/look/skinned_body.gd`), so BodyAnimator, the hand IK, holsters and
  weapons are unchanged. Alternative: swap to imported clips on the new skeleton.
  Rejected for now: the procedural animator and its tests already cover every
  state, and the NPCs still share it.
- **Raw downloads stay untouched; a script makes the game asset.**
  `tools/look/prep_character.gd` reads `content/look/character_models.json`. It
  flattens the concept's jetpack into coat (the game draws the jetpack as an item,
  and there is no coat modelled under it, so deleting it leaves a hole). It moves
  coat weights off the arms (auto-rigging made a raised arm drag a plank of coat),
  and it attaches the separate goggle-glow texture.
- **First person shows the kit's primitive forearms.** The skin is one mesh, so it
  cannot hide everything but the arms; it renders shadow-only instead.
- **Only the player for now.** The beauty-corner smuggler NPC keeps its primitives.

## 2026-10-26 — M14 (fly the ship from the port to space and back)

- **The atmosphere is the town scene, space is the dogfight scene.** The town got a
  world around it and a flyable ship; space stays the M10 scene. The hand-off is at
  the edge of space (8 km), through GameFlow, like the old pad launch. Alternative:
  one continuous scene from the ground to orbit -- rejected for now: two very
  different scales (a 200 m town, 20 km of desert, a 6 km planet sphere in space)
  and large-world precision. Fading at the edge of space hides the cut, and each
  scene keeps what it is good at.
- **Fly over the seamless desert, do not ship a second one.** M14 was first built
  with its own desert (terrain mesh, walkable patch, mesas); the seamless desert
  (PR #17) landed first. M14 now reads it: the ship's ground is
  `DesertTerrain.height_at`, its mesas and hoodoos (from
  `content/look/desert_landforms.json`, same skip rule) are columns the ship hits,
  and the walkable ground is its collider. M14 only adds what it lacks: the planet
  past its 6 km edge, the outpost, and `prefetch()`.
- **The walkable collider follows feet, not ships.** A ship at 300 m/s would drag
  it into a rebuild every frame and a synchronous snap at every edge. So it stops
  following while you are seated, `prefetch()` builds it under a landing ship (or
  at the pad before a tow) with the same per-frame budget, and it follows you
  again when you get out. Landing is allowed only inside the desert (beyond it
  there is nothing to stand on).
- **Same pattern: pure spine, thin node.** `WorldTerrain` (height), `WorldGround`
  (ground under a point, obstacles) and `AtmoFlight` (the ship's states and
  physics) are RefCounted and headless; `ShipPilot`, `WorldScenery` and
  `AltitudeSky` only read keys and draw. The trace flies the ship with the M10
  fighter brain's steering through `set_external_command()`.
- **AtmoFlight wraps the M10 flight model, it does not fork it.** The flight model
  gained `speed_scale` and `accel_scale` (1.0 in space, so the dogfight is
  unchanged). The atmosphere sets them each frame: thin air is faster, nose-up is
  slower. Its own tuning is the ship's new `atmosphere` block.
- **A VTOL fighter, not a plane.** Zero throttle hovers, lift-off is vertical, and
  landing (C) brakes, levels and settles straight down. Alternative: runway landings
  and stalls -- rejected: the pit is the spaceport, and a keyboard plane is hard to
  land. GTA-style flying is the cruise, not the landing.
- **30-40 s to space, tuned and measured.** Space at 8 km; 170 m/s top speed near the
  ground rising to 4x at the edge; 30% speed lost straight up; 8 s of boost. Nose up
  at full throttle: 33 s with boost, 39 s without (measured in the trace and a unit
  test, not just computed). A 45-60 degree climb takes 41-47 s.
- **Ship collision is pure, not physics.** The ship asks `WorldGround` for the ground
  under it and for obstacles (town boxes, landmark cylinders and boxes) every frame.
  That keeps the whole flight headless-provable and cheap. Floors and ramps are
  ground, not obstacles; the town's "ship" box is skipped (it is the parked ship).
- **The parked ship carries its own collision.** A box from the model's bounds rides
  on the ship, solid while parked, off in flight. The pad's static box is retired
  (it would stay behind as an invisible wall when the ship leaves). The town walk
  traces still route around it at the pad.
- **The planet curves past the desert's edge.** From the desert's 6 km edge the
  surface falls away on a 120 km sphere (flat until then, so the sand and the ship's
  ground agree), and a skirt continues it to 100 km. The ship's ground and "altitude" use the same
  curve, so at 7 km you see a curved horizon below black sky. Altitude is measured
  above that curved sea level.
- **The sky is the preset, darkened by altitude.** `AltitudeSky` reads the current
  time-of-day preset and blends its sky colours, cloud cover, fog and volumetric fog
  toward the space values in `content/look/world.json`, and fades in a star field.
  Cycling the lighting still works at any height.
- **Re-entry is player-driven.** Diving at the planet in space comes back any time
  (outcome "left", no payout, if the fight was not won). After a win you get
  `reentry_delay` (25 s) to do it yourself. A lost fighter still returns you on foot
  to the pad (arrival mode "pad"), as in M9.
- **Keys reuse what exists.** E boards and (when landed) gets out; Space takes off
  (it is fire in space); C lands (crouch: "go down"); flight keys are M10's. E is also
  roll right in flight, so it only means "get out" once landed.
- **A jetpack over the wall lands in the dunes**, in the M14 trace too (the fall
  guard itself is the seamless desert's, measured from the ground under you).
## 2026-10-26 — Seamless desert

- **Seat the town on the dunes at its own floor level, not on the beauty corner's
  plinth.** The town's data puts its floor at y = 0 and its gate on open ground;
  the beauty corner's port stands on a 74 m cliff above a basin with no way down.
  Putting the town on the plinth would mean roads down the cliff (unplanned) and a
  rework of every route. So `DesertTerrain` gained a site mode beside the plinth:
  flat sand at the floor around the town, a faint swell, then the open dunes
  (lowered 12 m so the town sits among them, not on a ridge). Plinth mode is
  untouched, so the beauty corner (the art reference) does not change.
- **The footprint comes from the town data, no coordinates in code.** Floor boxes
  at floor level (town and aprons) are the flat area; `bounds` is the walled area;
  floor boxes below it (the pit) are dips. Change the town file and the ground
  follows.
- **Inside the walls the ground sits 12 cm under the paving,** inside the 0.5 m
  floor boxes, so it is never seen and never fights the paving for the same pixels.
  It rises to the floor at the wall line so the sand outside meets the walls.
- **Aprons are hidden, not removed.** The two aprons outside the walls keep their
  boxes and collision (the M9 routes and validator are unchanged) but are not
  drawn, so the terrain's sand, lying exactly at their top, is what you see.
  Alternative: give them the sand material. Rejected: two coplanar surfaces with
  slightly different normals shimmer.
- **The collider dips further than the mesh under the pit** (one collider cell
  more), so the 2 m collider grid never interpolates an invisible slope up inside
  the pit. Tested on every vertex near the pit.
- **A collider that follows the player, rebuilt over several frames.** 512 m square
  at 2 m cells, re-centred when the player is 96 m from its centre, filled at most
  2 ms per frame (about 2.5 s for a full rebuild; the old collider still covers
  160 m ahead) and swapped in whole. 4 ms was tried first: on a busy 2-core box the
  M13 trace's worst frame went from about 6 ms to 30 to 60 ms while a rebuild ran. A teleport past its edge (a rescue, a script)
  rebuilds at once: a one-off hitch beats falling through the world. Alternatives:
  one huge static collider (a 6 km heightmap is 9 million samples), or Terrain3D
  (a plugin and a GDExtension binary to pin, for one terrain). Revisit Terrain3D if
  we start sculpting by hand.
- **The visible terrain stays one static 6 km mesh** (as in the beauty corner). It
  costs about 0.6 s to build at load; the greybox (CI) builds only the collider.
- **Desert on in the greybox too.** It is gameplay (ground), not look. So every
  trace that builds the town walks on the same ground the game has. Landforms are
  look only.
- **The fall guard measures from the ground under the player.** With ground
  outside the walls, flying out is no longer a fall; the old threshold (20 m under
  the lowest floor) would have fired in any deep dune trough. Over the town the
  pit floor still counts.
- **Landforms are a copy of the beauty corner's recipe, driven by data.** The
  beauty corner is not edited, so `DesertLandforms` reads
  `content/look/desert_landforms.json` (same mesas and hoodoos plus two, boulders
  kept 25 m clear of the town). Mesas and hoodoos are solid; boulders are one
  MultiMesh without collision, as before.

## 2026-10-26 — M13 (jetpack, issue #5)

- **Same pattern as M1-M12: pure spine, thin node.** `Jetpack` (fuel + thrust) and
  `Inventory` (own, attach, pick up, sell, buy) are RefCounted and headless;
  `GearController` only places things, reads E and G, and syncs the player node.
  The trace calls the same `interact()` / `toggle_gear()` the keys do.
- **The jetpack is extra lift in the existing controller, not a second movement
  mode.** `CharacterController` gained `lift` (upward acceleration this frame) and
  `max_rise` (a climb cap while lifting); `set_command()` gained an optional
  `jump_held` that defaults to false, so every M1-M12 caller and trace is unchanged.
  Alternative: a separate flying state with its own physics -- rejected because the
  pack only changes vertical speed; walking, collision and air control already work.
- **Tap = jump, hold = fly.** Thrust starts only after jump has been held 0.18 s in
  the air (`kick_in`), so a tap never burns fuel and an ordinary jump feels the same
  with or without the pack. The issue asked for "jump really high by holding".
- **Fuel recharges on the ground only, after a delay.** With an air refill, short
  feathered bursts could hover indefinitely. `recharge_air` is data (0 today) if a
  later pack should allow it. An empty pack needs `min_fuel_to_start` before it will
  relight, so it does not stutter on fumes.
- **Inventory lives in WorldState and is saved inside the world block.** WorldState
  is already static (survives town -> flight -> town) and already saved and loaded
  by the bar. Adding `inventory` to its save means no new save version and no new
  save call sites; an older save loads with an empty inventory.
- **Picking up attaches when the slot is free; buying does too.** One less key
  press for the common case. G is the explicit attach/detach (the issue's
  "attached"). Detached gear stays owned.
- **Selling is real: the vendor keeps what it buys and sells it back.** A sale moves
  the item into the vendor's stock (saved), so selling is not a delete and the item
  can be bought back at `sell_rate`. Prices are `value x rate` from data. Money stays
  in `WorldState.credits` (the bartender's drinks and jobs already use it).
- **Pickups and vendors are placed by town marker + offset.** No coordinates in
  code, and the town file is untouched (its validator and the M9 walk trace are
  unchanged). The jetpack sits at the top of the pit ramp, not in the pit, because
  the ship's launch pad covers the whole pit and also uses E.
- **A fall guard, because the pack can leave the town.** The walls are 6 m; a full
  tank climbs ~17 m; the town has ground only inside the walls. Alternatives: a
  ceiling (kills the point of the pack) or invisible walls (new geometry outside the
  town data). Chosen: if the player drops 20 m below the lowest floor, put them back
  where they last stood on the ground, with a toast.
- **Gameplay and look are separate files, as with ships.** `items/*.json` says how
  the pack behaves; `content/look/items.json` says what it looks like, keyed by a
  `look` id, with a `scene` path for a real model and a stand-in fallback. Flames
  are raked back 20 degrees so the player's long coat does not hide them (found in
  the first review render).
- **The worn pack is mounted from outside the avatar.** `GearController` hangs it on
  the avatar's chest joint and handles first person itself (shadow only, like the
  body), so `player_avatar.gd` is unchanged; open PR #12 rewrites part of that file.

## 2026-10-26 — M11 (body + hand weapons) and M12 (live bartender)

- **One PR for both, by product-owner call.** Order inside it: the bartender pipe
  and brain first (her own stated first priority), body second, weapons third.
- **Procedural animation, not imported clips.** CharacterKit characters are jointed
  (no skinned mesh), and the free CC0 clip libraries (Quaternius UAL 1/2) ship for a
  humanoid skeleton we do not have; retargeting them means a skinned rebuild of
  every character. `BodyAnimator` drives the existing joints with a gait cycle,
  jump/fall/land and crouch, and the kit's two-bone IK puts hands on weapons. Every
  number is tunable in one file and the state machine is unit tested. Alternative
  kept open: if a skinned body arrives, UAL clips drop in behind the same inputs.
- **One body for both cameras.** First person keeps the full body (real feet, real
  shadow) and renders everything except forearms, hands and the weapon as shadow
  only; the chest follows the camera pitch. Alternative was a separate viewmodel
  rig: two things to animate and keep in sync.
- **Free assets: Kenney (CC0 models, in the MIT Starter Kit FPS).** The kit repo is
  reachable from CI-like sandboxes (GitHub); kenney.nl and itch.io are not. Its
  blaster and repeater are retinted at runtime by `weapon_retint.gdshader` (palette
  atlas -> gunmetal ramp + accent) so they read as worn, not toys. Sounds from the
  same kit. The energy sword's sounds are synthesized from scratch
  (`tools/audio/make_blade_sfx.py`), so there is nothing to license.
- **The sword is the duelist's sword.** `CharacterKit.make_energy_sword()` is shared;
  yellow by default, from `energy_blade.json`.
- **Ammo + reload kept (not heat).** M2's tested Weapon state machine already does
  magazines and reloads; switching to heat was churn without a player-facing win.
- **Swap = holster then draw (0.18 s + 0.17 s), retargetable mid-swap.** Pressing the
  weapon already out holsters it. `WeaponHolder` is pure and spam tested.
- **Deflection uses M3's EnergyBlade unchanged.** A block started within 0.18 s of a
  bolt reaching the blade sends it back at its shooter; later blocks absorb it; a live
  swing also deflects. Bolts gained opt-in `shooter`, `sweep` (ray test per step, no
  tunnelling) and `stylize` (glowing streak); the M2 trooper bolts are unchanged.
- **A sanctioned range in the pit.** Shooting there is practice; shooting in the
  street sets `shots_in_street` and costs Remnant standing (once per 45 s). The
  sparring remote only fires stun bolts while your blade is out.
- **Keys 1/2/3 are weapons now;** lighting moved to L (cycle).
- **WorldState is static, like GameFlow (no autoload).** It survives town -> flight
  -> town and is saved (save v2). Systems write facts when they happen; the bartender
  only reads it. Rumors and jobs carry conditions and are shown to her only when true.
- **Jobs on her board are real.** "Thin the orbital patrol" completes when a flight
  is won; "the range bet" when the range record is set. No job exists that the game
  cannot verify.
- **The LLM service is a Node owned by the bar, not an autoload,** for the same reason
  as GameFlow: nothing runs unless the bar exists. Providers are pure request
  builders/parsers; the service streams with HTTPClient polled in `_process`.
- **Anthropic replies via a forced tool and streamed input_json_delta,** which
  concatenates to the same JSON every other provider sends, so parsing is shared.
- **No network retry on malformed JSON.** `ReplyParser` repairs (code fences, chatter,
  plain text) instead; a second round trip costs more latency than it saves.
- **The IP blocklist moved to data** (`content/core/llm/ip_blocklist.json`), shared by
  the CI scan and her runtime output filter. The test reads it.
- **CI proves the real HTTP path** against `tools/llm/mock_llm_server.py` (standard
  library only) when python3 exists: SSE cut at awkward byte offsets, UTF-8 split mid
  character, timeouts, 500s, non-JSON replies, health checks.

## 2026-10-26 — M9 (port town) and the single demo

- **The town is data.** `content/core/locations/port_town.json` holds every box,
  marker, route and zone; `town_layout.gd` is the only reader and validates it with
  the same 8 rules as `docs/town/validate_town.py`. Why: the IP rule (names and
  places live in content only) and tuning without code changes.
- **+X is toward the gate, the desert and the outpost**, matching the M4 streamer,
  which already walks along +X.
- **A sunken landing pit** is the town's landmark and a combat space, and now the
  launch point for flight. **The back gap** in the west wall gives the smuggler a way
  out that avoids the gate.
- **Defaults D6 to D9 kept as planned:** spawn on the pit floor beside the ship;
  trooper posts placed now as markers; the market is atmosphere only; nothing is
  built over the pit.
- **Ramps: no fix needed.** The T5 ramp formula and 0.4 m thickness walked first
  try; no `floor_snap_length` change.
- **Town decor is a visual-only layer.** `town_decor.gd` only sets materials and
  adds lamps and two banners; it never adds collision or touches box data. Market
  and character art are deferred to their own passes; capsules and plain stalls are
  intentional. `use_look = false` gives the plain greybox, which the CI walk trace
  uses so its numbers never depend on art.
- **One demo, not several scenes to pick from.** F5 opens the town. The pad around
  the ship in the pit launches the dogfight; when the fight ends, the player lands
  back beside the ship. Under the hood flight is still its own scene (loaded by
  `GameFlow`), because the dogfight builds a whole different world (space, planet,
  sun); the player never picks a scene. Alternative: build the dogfight inside the
  town scene -- rejected for now: two lighting setups in one tree, and the town would
  keep simulating during flight. Revisit if a seamless take-off is wanted.
- **The beauty corner is back to being only the art reference.** The pad briefly
  lived there; it moved to the town and `beauty_corner.gd` is unchanged from main.
- **The parked ship is the flight model, and its box was resized to fit it.** The
  decor layer builds the pit ship with the same ShipKit and look id the dogfight
  uses (pad encounter, then player ship, then look), so one data change restyles
  both. The planned 24 x 14 x 8 m ship box would have left invisible walls around a
  9 m fighter, so `ship` in `port_town.json` (and the docs copy) is now
  9.4 x 2.7 x 8.2 m. Validator: 0 errors; routes and walk frames unchanged.
- **Pads are data, anchored to town boxes.** `content/core/flow/launch_pads.json`
  names a `town_box` (the ship) and an `arrive_marker` (the spawn); the scene turns
  those into positions, so no coordinates are typed anywhere.

## 2026-10-26 — M10 (starfighter flight and dogfights)

- **Arcade flight, not Newtonian.** The ship always moves along its nose and speed
  eases toward the throttle target. Alternative: full 6-DOF momentum -- rejected for
  the slice: it is harder to fly with a keyboard and harder for the AI. The model is one pure file; a Newtonian variant could replace it behind the same
  `step()`/`set_command()` shape.

- **Same pattern as M1-M8: pure spine, node wraps it.** The flight model, lead solver,
  seeker lock, shield, loadout, projectile field, fighter brain and dogfight director
  are all RefCounted and headless. `ship_node.gd` and `dogfight_demo.gd` only draw and
  read input. That is why the whole fight is provable in CI.

- **The bot flies the player with the same AI as the enemies.** The headless trace
  turns on the player's autopilot (a fighter brain with the ace profile) instead of
  scripting inputs. This is the M5 rule: bot and human share one implementation, so
  the trace proves the real flight model and guns.

- **Ship guns reuse the M2 weapon state machine.** A hardpoint is a `weapon.gd`
  instance, so ship guns get the same rate/mag/reload rules as the hand blasters.
  `mag` + `reload_time` double as a heat limit on cannons. Alternative: a separate
  ship-weapon class -- rejected as a second copy of the same rules. One addition:
  ship weapons start reloading on their own when empty (the hand blaster waits for the
  trigger), because a seeker rack must recharge while the trigger is never pulled.

- **Bolts inherit the shooter's velocity, and the lead solver accounts for it.** A
  fighter at 70 m/s firing 300 m/s bolts would otherwise see its own shots fall behind
  in a chase. The solve runs in the shooter's frame (relative position and velocity).

- **Hits are swept, not sampled.** A bolt travels ~5 m per frame; a fighter is ~3 m
  across. A point-in-sphere check would miss most hits. The projectile field tests the
  frame's travel segment against each hit sphere.

- **Hit spheres, not physics bodies.** Ships and bolts are pure data with a radius,
  not Area3D/RigidBody3D. Alternative: Godot physics -- rejected because it ties the
  fight to the scene tree (no headless proof) and costs more per bolt. Ship-to-ship
  collision is deferred (KNOWN_ISSUES).

- **New data categories use one generic loader path.** `ships`, `pilots` and
  `encounters` load through `_load_category()` from the manifest, the same way
  missions and locations do. Ship guns are ordinary `weapons` entries with a
  `fire_group`. A test builds a new ship, gun, pilot and encounter in `user://` and
  flies it: the "zero code change to add content" rule, proven for flight.

- **Gameplay and look are separate files.** `content/core/ships/*.json` says how a
  ship flies and fights; `content/look/ships.json` says what it looks like, keyed by a
  `look` id. A look is either a `scene` path (any .glb/.tscn, forward -Z, metres) or a
  primitive stand-in from `ship_kit.gd`. A missing model falls back to the stand-in
  so a bad path never makes a ship invisible. This mirrors the character kit:
  stand-ins now, real models later, no gameplay change.

- **AI pilots are data too.** Aim cone, aim error, engage/break/extend distances, and
  the chance to break when hit or when a seeker is launched at them live in
  `content/core/pilots/*.json`. Missile evasion was added after the first trace: with
  seekers that never missed, the player's wingman and then the player died to the
  heavy fighter's rack every run. A break on launch makes seekers dodgeable (they turn
  slower than a fighter), and the trace now shows both hits and misses.

- **The AI is deterministic per seed.** Each brain gets its own seeded RNG (from the
  encounter seed and the ship id), so the trace is reproducible run to run.

- **Glow is off in the space backdrop.** In the Linux software-renderer review stills,
  Godot's glow lifted the black of space to navy whatever blend mode or threshold was
  used. The value is data (`content/look/space.json`); it can be turned back on after
  a check on the Mac.

- **Fixed two CI gaps found while doing this.** The IP scan never read files at the
  top of a scanned folder (missing slash in the path join), and `ci.sh` passed on a
  fresh checkout without running any test (GUT cannot load before an import). Both
  were silent passes, so they are fixed here rather than left.

## 2026-10-25 — M8 (polish pass: bug list, performance report, cross-system trace)

- **The "3-minute gameplay recording" is the manual/recorded path, not a headless
  artifact.** A rendered clip needs a window a CI run does not have. So M8 ships the
  *machine* proof of the same content -- a single cross-system playthrough trace
  (`scenes/m8_playthrough.gd`) and a per-frame performance report -- and hands the human
  a guide (`LAUNCH.md`) to open the game and record the clip. This is the same posture
  as M6/M7 (real inference / real voice / real render are manual + recorded; CI proves
  the behavior deterministically). Alternative: a headless render -- rejected, Godot
  `--headless` has no window and a synthetic render would not prove the *look*, only the
  *behavior*.

- **"No hitch over 50ms" is proven over a whole playthrough, not one frame.** M4 proved
  the streaming budget for the port->desert walk; M8 extends it to a full session that
  interposes every system, and the report's `over_budget=0` + `worst_ms` are the
  measured "no hitch" across that session. The per-frame work is a load-cost figure the
  trace itself accounts for, so the proof stays honest and reproducible.

- **The "bug list" was the one standing artifact; it was a timing mismatch, not a logic
  bug.** GUT's "1 orphan" at exit was a detached test node cleared with
  `queue_free()`, which the engine only honors on the next idle frame -- never, because
  GUT quits immediately. `free()` on a detached node is correct; that change clears the
  orphan. The suite now reports 0.

- **A cross-system integration trace, not more isolated unit tests, is the M8 proof.**
  Each milestone proved its own system; M8's job is to show them *together*. One SceneTree
  run threads movement -> camera -> combat -> squad -> duel -> mission -> voice -> save,
  and a test reads the resulting log. This is what "hangs together end to end" means, and
  it complements (does not replace) the per-milestone traces.

## 2026-10-25 — M7 (voice input: typed default, whisper fallback)

- **Typed is the DEFAULT speech source; whisper is the optional, dependency-bearing
  upgrade.** This deliberately supersedes the M0 assumption that whisper/VAD was the
  primary voice-in pipeline. The product owner's M7 direction: type the speech by
  default (zero dependency, easy) and only wire whisper as a fallback. A speech source
  is dependency-aware (`dependency()` says "none" for typed, "whisper runtime" for
  whisper), and the controller prefers the typed source unless voice is both preferred
  AND the whisper runtime is actually loaded. Alternative: keep whisper primary —
  rejected because it forces an STT model + mic into the default path for no gameplay
  gain and makes the slice harder to ship.

- **One door, the same brain.** The push-to-talk routes every captured request to the
  M6 `bartender.respond()`, so the "text is read but never executed as a command, only
  an allowed model tool may act" guardrail is unchanged. No new code path can move
  world state except through the M6 guardrail.

- **A degraded voice turn is a typed turn, never nothing.** When voice is preferred
  but whisper is absent (the CI case, and any build without the model) or a sample
  transcribes to empty, the controller serves the request through the typed source, so a
  conversation never dead-ends on a missing model. This is the same "graceful null,
  not a crash" posture as M6's Kokoro and Ollama.

- **The whisper runtime is a stand-in that loads only when a model is present**,
  mirroring M6's Ollama client (pure parts tested, I/O part a documented stub). This
  keeps "does the voice path work when wired?" answerable headless while the real
  whisper.cpp + mic capture stays the manual + recorded path.

- **Latency is measured from an injected clock.** The press/release core takes
  start/end ms, so a headless trace records a deterministic per-turn latency — the M7
  "latency measured" requirement — without a mic. Real wall-time timing is the manual
  wiring.

- **GUT/GDScript-4.7 gotchas (carried from M6):** GUT 9.7.1 uses snake-case asserts
  (`assert_true`/`assert_eq`/`assert_gt`/`assert_false`), not Java-style; and
  `Object.has("field")` does not exist in this engine -- use `has_method(...)` for a
  presence guard. Both surfaced in M7 and are noted here so a future test does not redo
  the work.

## 2026-10-25 — M6 (LLM bartender, text + Kokoro voice)

- **The bartender talks to the model through a client interface, not a hardcoded
  model call.** `llm_client.gd` is the contract (`pop_next() -> response or null`);
  `scripted_client` (canned, deterministic) and `ollama_client` (real, local) both
  satisfy it. Alternative: hardcode Ollama into the brain — rejected because it would
  make the conversation untestable headless and lock the brain to one backend. Same
  reasoning as the M1-M4 "pure spine, node wraps it" pattern. Real inference stays a
  manual + recorded check; CI uses the canned client.

- **Text is read but never executed; only a model tool proposal may act on the
  world, and only one in the npc's allowed set.** This is the guardrail the spec asks
  for ("the player's typed text is never a command"). It is enforced in one place
  (`respond()`): the request string is logged/read but no branch acts on it; an
  effect happens only via `_apply_tool`, which refuses any tool not in `allowed_tools`
  (loaded from the npc data entry). A disallowed tool is dropped, so no effect leaks
  into memory.

- **A disallowed tool is ignored, not partially applied.** When the model proposes a
  tool outside the allowed set, the brain zeroes out `tool`/`args` before applying, so
  the conversation can never smuggle an out-of-scope action through. This is asserted
  in `test_disallowed_tool_is_ignored`.

- **Kokoro ships as a deterministic signature + a graceful null render.** The
  text+speaker -> signature mapping is pure and tested (same input, same signature;
  different speaker, different signature). The audio render needs the Kokoro/ONNX run,
  which is not in headless CI, so `synthesize()` returns null instead of crashing --
  the conversation never dead-ends on sound. A real recorded voice is M8. This follows
  the M0 decision to use NobodyWho's bundled Kokoro/Whisper/VAD rather than separate
  builds.

- **Client `pop_next()` returns `Variant`, not `Dictionary`.** GDScript forbids
  returning `null` against a `Dictionary` return type; the interface needs "a response
  or null," so `Variant` is correct. Same class of fix as the M5 parse bugs.

- **The Ollama client is pure except for the HTTP post.** Request-building and
  response-parsing are plain functions tested on canned JSON (the real `/api/chat`
  shape: `message.content` + `message.tool_calls[].function`); only `_post()` does I/O
  and is a documented stub. This keeps the "is the response parsed right?" question
  answerable without a running server.

## 2026-10-25 — M5 (mission loop + save)

- **Missions are a generic data category, like `locations` was at M4.** The slice
  mission lives in content/core/missions/crate_retrieval.json and the loader loads it
  from the manifest with the same code path as every other category. Alternative: a
  hand-wired mission table — rejected because it would hardcode the one mission and
  break the "zero code change to add content" rule. New missions extend the manifest
  only.

- **The mission is a pure RefCounted state machine driven by events, not a Node3D
  scene.** This mirrors M1-M4: the gameplay spine (IDLE -> ... -> COMPLETE) is proven
  by GUT headless, and the live game wraps it. The same spine is what the bot bot
  plays and what a human plays, so the bot playthrough is a faithful proof.

- **The squad coordinator assigns each trooper a DISTINCT cover node.** With N nodes
  and N troopers, every trooper gets one node and none is left in the open; with
  fewer nodes than troopers the surplus is honestly left open. This is the "4
  troopers do not all stand in the open" the spec asks, on top of the single-unit
  M2 cover logic.

- **The save round-trip is a file test, not an LLM test.** The four named things
  (player position, credits, mission state, bartender memory) are written to user://
  and read back into a fresh instance; the trace asserts each survives. This is what
  "save/load all working end to end" means here, and it stays honest because it is a
  deterministic file round-trip, not inference.

## 2026-10-25 — M0

- **Engine pinned to Godot 4.7.2.** Latest stable at M0 start. Alternative: 4.6.x.
  Chose 4.7.2 so NobodyWho (lists 4.5+) and GUT 9.7.1 (tracks 4.7.x line per GUT's
  version matrix) both match. Version is enforced in `scripts/ci.sh` against `pin.txt`.

- **GUT 9.7.1 for testing.** MIT, is the standard Godot test framework, tracks the
  4.7.x line. Alternative: a hand-rolled runner — rejected, GUT gives JUnit XML +
  asserts for free. NOTE: GUT 9.7.1 uses `before_each()/after_each()`, NOT the old
  `setUp()/tearDown()`. Our tests use the former.

- **GUT is run headless via its CLI (`-s res://addons/gut/gut_cmdln.gd`).** A bare
  `godot --headless` invocation runs the project's main scene, which never quits, so
  it hangs forever. The CLI runner quits on its own and returns a non-zero exit code
  on failure; `scripts/ci.sh` relies on that exit code as the merge gate.

- **CI is a local shell script (`scripts/ci.sh`), not GitHub Actions.** Decision from
  the product owner: local-only repo. The script runs GUT headless and exits
  non-zero on any failure. If a remote host is wanted later, the same GUT command is
  the body of a GitHub Action.

- **IP-neutral data layer at `content/core/`, loaded at runtime.** This is the load
  path a future private "skin" layer would override with zero code changes — the
  loader takes a root path argument. No name is hardcoded outside this directory;
  `tests/test_ip_neutral.gut.gd` greps the source tree for franchise terms and fails
  the build on a hit.

- **Voice pipeline: use NobodyWho's bundled Kokoro (TTS) + Whisper (STT) + VAD**,
  not a separately-built whisper.cpp / Kokoro. The product owner approved this at
  M0 planning as a deliberate deviation from the literal spec wording, because it
  removes a second C++ build and a second license surface for no gameplay gain.
   This was logged as a deviation in the plan (PLAN.md); revisited at M7 only if
  quality demands.

- **LLM model: Qwen3 4B Q4 for the bartender.** Fits comfortably in 64 GB, strong
  tool-calling (which is what the 4-tool bartender needs). A fallback plan exists in
  KNOWN_ISSUES.md: drop to a 1-2B instruct model that supports tools if 4B is too
  slow or too large.

- **Bot playthrough (M5) drives the non-LLM loop live but talks to a deterministic
  stub model**, not real inference. Real LLM inference is a recorded/manual check.
  This is what makes "a failing bot blocks the merge" actually reliable; it is
  documented as a stub, not presented as a finished LLM loop.

- **No C#.** NobodyWho (the LLM plugin) is a Rust/C++ binding, not C#. Per the spec,
  GDScript is the default and C# is avoided unless a system genuinely needs it.

- **No GPL anywhere.** Godot MIT, GUT MIT, NobodyWho EUPL-1.2, llama.cpp/ONNX
  permissive, greybox assets CC0. Studied OpenJK for melee/deflection mechanics only;
  nothing is copied.

## 2026-10-25 — M3 (melee + duelist)

- **The energy blade and the duelist are pure, testable `RefCounted` state machines**
  (`src/systems/combat/energy_blade.gd`, `src/systems/ai/duelist_brain.gd`), with no
  Node3D. This mirrors M1/M2: the gameplay math is proven by GUT, and a node wraps it for
  the live game. A duelist that *uses the player's exact blade logic* is the design so
  "a melee duelist that blocks, parries, and pressures" and the "timed deflection" skill
  are the *same code* on both sides.

- **Timed deflection is modeled as a block-timing window, not as a separate input.**
  `intercept_bolt()` checks how long the current block has been held: a block opened
  within `deflect_window` reflects the bolt and refunds stamina; a block held longer only
  absorbs it. This is the "deflection of incoming bolts when blocking with correct
  timing" from the spec, and it reduces to one number (`deflect_window`) so the skill can
  be tuned from the data layer in a future skin.

- **Process-ordering rule for multi-stage timers.** When a single `update(dt)` both ends
  a state and starts the next, the *recovery* timer must be advanced before the *drain*/
  *end* logic of that frame, otherwise a state reached that frame is instantly advanced
  out of its own recovery. The `energy_blade.update` is structured in that order and the
  rule is noted here for the next timer-based system (reload, parry cooldowns).

- **M2 was committed before it was merged, so M3 was built on a base missing M2.**
  This is a process bug, not a code one: a feature branch can be complete and correct
  while not yet integrated. The fix was to merge the in-flight work into `main` before
  branching the next milestone, and to keep the rule **"branch each milestone off the
  latest main, and merge only when its tests pass."** If this pattern ever recurs, the
  recovery is `git merge --no-ff <branch>` because the branches are disjoint.

- **The trace, not the render, is the M2/M3 proof in CI.** Each combat milestone ships a
  headless *trace* (a text log of a simulated encounter) plus GUT assertions on that log.
  A rendered GUI fight with bullets and animation is M8 polish. This keeps the merge gate
  fast and deterministic while still proving the *behavior* the spec asks for.

- **One known non-failing artifact is disclosed, not hidden.** GUT flags "1 orphan" at
  process exit: a test bolt created without a scene tree is freed at exit. It does not
  fail the suite (exit 0, "All tests passed"); it is tracked in KNOWN_ISSUES.md for M8
  cleanup.

## 2026-10-25 — M4 (chunk streaming)

- **"No hitch over 50ms" is proven as an amortized frame-time budget, not a GPU
  measure.** The spec asks for "no loading screen at the boundary / no hitch over 50ms."
  We model chunk loading as a cost in milliseconds and a `chunk_streamer` that never lets
  one frame spend more than `work_budget_per_frame` (=50ms). The property "max per-frame
  work never exceeds the budget" is the exact anti-hitch invariant, and it is the part
  that can be proven headless. Real GPU frame-time of a rendered world is deferred to M8;
  this is the load-side budget that makes a seam hitch-free.

- **Streaming proof is a generated log, read by a test.** Rather than assert behavior in
  vacuum, M4 runs a full bay-to-outpost walk in a SceneTree harness that writes a
  per-frame log (frame, player_x, frame_work_ms) to `test_results/`, and a GUT test reads
  that file and checks "0 frames over 50ms" and "the walk crosses to x=1000." This is the
  same machine-evidence pattern as the M1/M2/M3 traces; it keeps the proof honest (read
  from a real run) and reproducible (CI regenerates it). It is disclosed that this is the
  load-cost model, not yet a recorded rendered frame time.

- **The data layer gained a `locations` category.** The outpost (3 buildings + 1 crate +
  its guards) is content/core data, not code, so a future skin or a new location needs
  zero code change — consistent with the M0 IP-neutral design. New categories extend the
  manifest (`"locations": ["outpost"]`), and the loader loads them the same generic way.

- **A 1-D chunk strip stands in for a rendered 3D world at M4.** Streaming logic and its
  frame cost don't depend on geometry; a 1-D coordinate (player position east) is enough
  to prove the window/coverage/amortization invariants without a 3D level. The visible 3D
  greybox is M8.

## 2026-10-31 — The club mix (issue #104)

- **The club is a layer over the score, not a fourth music mode.** Two more
  decks on a new Club bus play the playlist; ambient, battle and space moved to a
  new Score bus. Both send to Music, so the one Music slider still sets it all.
  Walking up raises the Club bus and lowers the Score bus by the same amount, so
  the blend by distance is two bus volumes, and gunfire inside cannot cut the
  club (the score is fully down there). Alternative: a "club" mode in the
  existing priority list. Rejected: modes swap, they do not blend by distance.
- **The wall's muffle is a low-pass on the Club bus**, its cutoff eased from
  500 Hz outside to 20 kHz inside the door. No geometry or raycasts: inside or
  outside is the cantina's zone in the town layout.
- **ClubMusic, a small node per town, reports where you are.** It measures the
  player to the cantina zone's rectangle each frame and calls
  `Sound.set_club(playlist, near, inside)`. Sound knows nothing about towns.
- **A dead band stops the club until the next visit.** One of the issue's open
  questions; the town is rebuilt every landing, and ClubMusic sets a new band
  live then. Easy to change to "never" with a WorldState flag.
- **Tracks: Pixabay and CC0, chosen against the issue's taste list, approved by
  the owner, downloaded once.** Each playlist entry keeps its source page, so the
  licence of every file is on record. Re-encoded like the score (160 kb/s MP3,
  one loudness) by `tools/audio/rip_club.py`, which finds downloads by the
  Pixabay id in their file names.

## 2026-10-31 — The cockpit's dash leans away, and its glass catches the light

- **The dash is painted flat, then warped into perspective.** CockpitDash draws
  the dash and instruments as before, into a SubViewport (1.5x, so it stays
  crisp), and `cockpit_tilt.gdshader` draws that texture back behind CockpitView
  with a one-parameter perspective (`CockpitView.TILT`): the bottom edge stays
  put, and higher up the panel shrinks toward the middle and its rows crowd
  together. The dials go oval and the plates' sides lean in, which a flat drawing
  could not show. The cockpit is still painted (see issue #181 above); only the
  dash is warped. `CockpitView.project()` is the same map forward, for the struts'
  feet and tests. Alternative: projecting every draw call by hand. Rejected:
  circles, arcs and text would each need their own warped version.
- **Glints come from the real lights.** Each frame CockpitView finds the scene's
  brightest DirectionalLight3D and the nearest nodes in the `glints` group (bolt.gd
  joins it unless it is a thrown rock; ShipKit.build_bolt's space bolts join too),
  in the camera's frame. `CockpitDash.glint()` reflects each one off a domed glass
  in the leaning panel to place its highlight on every dial, and the chamfer and the
  canopy pick them up too. The strength stays low (`SUN_GLINT`, `BOLT_FALLOFF`): it
  should read as glass, not as a light show.
- **The canopy frame is modelled, then projected.** The struts and the bow over the
  glass are centre lines in metres round your eye (`CockpitView.strut_path`),
  drawn through a 70° lens (`frame_project`) at a fixed thickness, so the nearer
  a part is the wider it draws. The struts stand on the dash, then swell and sweep
  out to the top corners as they pass over and behind your head; straight struts
  narrowing upward read as leaning away from you, not over you.
  The frame is lit like the dash, not shaded once: each member is drawn as a
  metal tube in strips across its width, and `metal_shade()` lights each strip
  from the same lights as the glints (a little sky, a wash, and a tight glare
  where it reflects a light at you), so the glare slides round it as the sun and
  bolts move.

## 2026-11-01 — Five more ambient tracks, CC0 from OpenGameArt

- **OpenGameArt, CC0 only, not Pixabay.** Pixabay refuses scripted downloads
  (403), and CC0 needs no licence record beyond the source page. Tracks under
  CC-BY or with no clear licence were skipped. Picked for calm and space:
  Galactic Temple (yd), Starfield Romance and The Budding of Consciousness
  (Yoiyami), Calm Ambient 1 / Synthwave 4k (The Cynic Project), Contemplation
  (joth). All are 2-4 minutes long, like the first three.
- **Encoded like the first three**: the `rip_music.sh` ffmpeg line (loudnorm
  I=-18, 160 kb/s MP3, 44.1 kHz), saved as `ambient4..8.mp3`.
- **The ambient list stays a list of paths.** The source pages go in a
  separate `music.ambient_sources` map that Sound never reads, so the shuffle
  code did not change.


## 2026-11-01 — The canopy frame and the dash are the ship's own metal

- **The frame and the dash's body are meshes on the camera now, not paint.**
  Painted metal (`metal_shade()`, the brushed dash) could only imitate the hull:
  it never reflected the sky or the sand, and the struts stopped dead at a grey
  dash. Now `CockpitView.frame_mesh` (round tubes along the same strut and bow
  curves) and `dash_mesh` (a face leaning back `CockpitDash.LEAN`, its top edge
  the painted rim, rolling over to a lip) hang on the cockpit camera, so the real
  sun, sky and reflections light them. The struts stand on the dash's face
  (`dash_point`) and run down into it, so they grow out of it. Instruments,
  plates, rivets and the yoke stay painted over the top. This replaces "the
  cockpit is painted, not modelled" (issue #181) for these two parts only; the
  meshes are built from the screen and lens, so one cockpit still fits every ship.
- **They wear the ship's skin.** `ShipKit.skin()` picks the material on most of
  the model, which ShipPilot hands the cockpit on boarding: the frame wears it as
  is, the dash a copy at `DASH_SHADE` of its colour with the same finish, so the
  instruments' panel reads darker than the struts.
- **The instruments are painted onto the modelled dash, not over it.** A 2D
  overlay always draws on top of the 3D view, so a modelled yoke could never sit
  in front of painted dials. CockpitDash's texture now goes on the dash mesh
  (`cockpit_dash.gdshader`); `dash_mesh` gives it UVs through `unproject()` (the
  old tilt shader's map, run per vertex), so it leans exactly as before. Where
  the paint is, the dash is glass (not metal, smoother) and lit from behind
  (`BACKLIGHT`), so the dials read at night and still pick up real glare by day.
  The tilt shader is gone.
- **The yoke is modelled** (`build_yoke`): a ram's-horn tube in the dash's shade
  of the hull, rubber grips, buttons, a boss and a column, turned and pulled by
  `yoke_pose` as before.
- **Dials are lit by LEDs in the HUD colour; the attitude card is backlit
  paper.** A soft wash and three pools of `RetroUI.accent` in from each dial's
  rim (`LED_GLOW`), and ticks printed in pale ink tinted by it. The attitude
  ball's sky and ground are muted paper colours, with ink lines, fibres mottling
  a lamp behind the middle, and a shadow at the rim.
