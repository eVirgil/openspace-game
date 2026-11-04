# Known Issues / Stubs / Fakes

Honest list of what is broken or faked. Updated every milestone.

## After ship hulls that follow the model (2026-11-04)

**Checked:** test_smoke, a headless town boot with the models on (every parked
ship, the barracks interceptor and the outpost ships carry 48 to 95 convex
pieces, no box), and stills of the four flyable ships with their hull drawn over
them. No other suites were run, and it was not played.

- **The hull is a little fuller than the model.** Each ~1.2 m cell of the mesh is
  wrapped in one convex piece, so a dip smaller than a cell (between two engine
  pods, under a canopy lip) is filled in. Smaller `hull_fit.cell` follows closer
  for more pieces.
- **A friend's ship in space is still hit as a sphere** and the fight's own
  ships still by distance; only bolts that the physics world carries (the
  town's sky, a parked ship) see the new shape.
- **An upgrade T-89 bolts on mid-game** (`ShipPilot.refit`) is not in that
  ship's hull until the next load, as it was not in its box.

## After the LAN guest's cruiser crash fix (2026-11-04)

**Checked:** a two-process loopback probe (host and guest towns, the guest flies
up beside the cruiser, Z docks and gets out): no script errors in either game,
the host's crew woke for the guest and stood aboard in both games. test_smoke and
a headless town boot. Not flown on two computers; no GUT suite or trace for it.

- **The host's crew wake when the host's game sees the guest,** which is their
  ship (sent while they fly) or their body. Until the host's game hears of them
  the guest's cruiser is empty.
- **Killing the general as a guest pays the host,** not the guest: the cruiser
  is taken in the host's game (its story and purse), not in the guest's save.

## After LAN jobs shared by everyone (2026-11-03)

**Checked:** a two-process loopback trace, run by hand and not added to the repo
(the guest takes Oda's bounty: the host's game has it and puts the officer out,
the guest's town shows one copy and makes none of its own, the guest's kill makes
it collectable in both, and a drop the host takes lies in the guest's town; on
`main` the same steps give the guest about 1,200 script errors from its garrison
and the host never gets the bounty), test_smoke, test_ip_neutral, and a headless
town boot. Not played on two computers. One of the first two runs of the trace
crashed the guest's Godot (signal 11) right after its town loaded; the next run
passed, and I did not chase it.

- **Each player gets their own heist crew.** The crew member and the borrowed
  droid follow whoever's game they are in, and the others do not see them.
- **Only the jobs are shared, not the outposts.** Who holds each outpost, the
  resupply quests and the optional quests stay each game's own, so a guest can
  carry supplies to an outpost the host's game thinks someone else holds.
- **The last change sent wins.** If two players take or finish a job in the same
  quarter second, one of the two is lost.
- **A guest's own save keeps the host's jobs** after they leave: a bounty taken
  in the host's game is still out in the guest's solo game.
- **Joining shows the host's jobs as news,** a New Job banner for each one.

## After the ringed giant (2026-11-03)

**Checked:** tests/test_station.gut.gd (15/15, now in the giant's scene, plus a
save loaded on the giant starting you in the bay), the giant's tests in
tests/test_planets.gut.gd, test_smoke, test_ip_neutral, and stills. Flown by
hand once before the station moved in.

- ~~The clouds look like a smooth tan plain up close~~: fixed (2026-11-04), the
  haze shell and fog billows. Still: the fog is a look, not a volume. Clouds
  never pass between you and the station, and the cloud tops are one smooth
  height, with no towers of cloud to fly round.
- **Outside the station on the giant** (breathable, 2026-11-04) you are pulled
  back into the bay once you drop 40 m under its lowest floor. Nothing tells you
  you are close to that line before it happens.
- **No space fight on the way out** (`encounter: ""`): a fight's flight does not
  check the clouds, so a ship could dive into them mid-fight and live.
- **The ring is a look only.** No rocks in it yet (#312's belt), nothing to hit.
- **From the station you cannot see the home planet:** it is past the giant's
  view distance (as from Grit Station).
- **No cantina, Oda, board or merchant on the giant:** its town is only the
  station's bay until #314 to #316 fill the station.
- **A crash in the clouds is the normal crash:** towed back to the dock pad, you
  beside it, not a death screen.

## After the space station behind the moon (2026-11-03)

**Checked:** tests/test_station.gut.gd (14/14: the shape from data, the far
side of the moon, moving it to another planet, every floor, tunnel, roof walk
and the round bay stand, the dock path, Z docking in the moon's scene, the
elevator ride and call, the roof walk and the fall guard), test_smoke,
test_ip_neutral, and a headless boot of the home planet. Not played on screen;
stills only.

- **Nobody lives there yet.** The floors are empty shells (#314-#316 fill them),
  and NPCs cannot ride the elevator (only you can).
- **You only see it from its planet's own scene** (now the ringed giant's). From
  the home planet's sky it is not drawn, so flying out it vanishes when the home
  planet's scene takes over.
- **The F11 map and the cruiser's holo table do not show it,** and neither do
  the objective arrow and the waypoints.
- **The glass in the middle of each floor** means you cannot drop over the
  railing to the floor below, as #313 asks; the gap is a glass-floored well.
- **The roof hatches need the jetpack** (no ladder up to them).
- **The station uses the cruiser's metal and glass.** No look of its own yet.

## After LAN friendly fire for ships (2026-11-03)

**Checked:** tests/test_lan_ship_fire.gut.gd (4/4: the hull is solid only in the
air, a straight seeker hits it, space bolts and seekers on a friend's ship are sent once, a friend's hit
lands in the fight's director and can lose it), test_smoke, test_ship_combat,
test_seeker_warning, `scripts/test_lan.sh`, and a headless town boot. Two
players were not flown against each other on two computers.
`test_dogfight` ("three remnant fighters"), `test_m10_dogfight` and the guest
half of `scripts/test_lan_world.sh` ("people here are not all copies") fail on
`main` as well.

- **You hit where your friend's ship is drawn in your game,** which is up to
  a packet (1/20 s) behind where it is in theirs. Fast passes in space can land
  hits they did not see coming, or miss ones that looked close on their screen.
- **Shooting the host down in a space fight ends that fight for everyone,** as
  the host being shot down by a raider does.
- **A friend's ship in space is hit as a sphere** (half its longest side),
  not its box, as the fight's own ships are.
- **Their cannon fire in the sky is a picture** that flies to where their guns
  crossed and stops; it can pass through a hill in your game. Their seekers
  show only when unlocked (a locked one would turn after the interceptor).
- **A seeker locked on the interceptor still hits a friend in its way.** Nothing
  locks on a friend, but nothing steers round one either.

## After the Low graphics setting (2026-11-02)

**Checked:** the new test in test_lookdev (21 asserts), test_smoke, a headless
town boot, and rendered beauty-corner shots on the Mac at 1920x1080 (Vulkan):
GPU time per frame 2.5-3.2 ms with everything on, 0.8-1.1 ms with Low graphics
(golden and noon, three shots each). Not tried on a Windows PC or a slow GPU.

- **Low graphics looks cooler and crisper than full.** The warm haze and the
  sand's bounce light are what it drops, so metal (the wreck) and dark smoke
  read grey and black, not sand-tinted. The sand-coloured fill (`bounce`)
  warms the shade a little; it cannot warm reflections.
- **Timing on this Mac is noisy:** single runs had 3-5 ms stretches in either
  mode (CPU time rose with them). Compare medians over several runs.
- **Draw distances shrink to 0.6 in low graphics** (time_of_day.json
  "draw_scale"): a crate stops drawing at 132 m, not 220. Checked headless in
  the town (10,345 ranged meshes and lights, rescaled both ways), not watched
  on screen for popping. The barge, the wreck field and the camps keep the
  ranges they set themselves.

## After the draw distance rules (2026-11-02)

**Checked:** headless, with the look on: a probe that boots the port and counts
every light and mesh by system (lights fading 42 to 182 of 191, meshes with a range
about 2,400 to 12,600), tests/test_draw_distance (4/4) and test_smoke. Frame times
and draw calls were not measured on the Mac, and nothing was watched on screen.

- **Things to look at:** small props fading in at 120 to 220 m while walking
  across the plaza, people at 320 m, the town's lamps going out past 300 m at
  night (from a ship, too), and the cruiser's bay lights past 120 m.
- **NPCs are about 74 meshes each.** Ranges stop far ones being drawn, but a
  crowd close by is still the heaviest thing on screen. Not looked at here.
- **The space scene's nine lights and the player's own light have no fade.**

## After the side-by-side saves (2026-11-01)

**Checked:** tests/test_save_slots.gut.gd (10/10), test_player_outfit (6/6),
the two new-game tests, test_smoke, and a headless town boot (it copied a
real story `save.json` into `save_story.json`). A switch in a windowed game
wasn't tried. `test_story`'s "a new town after the fleet has no garrison"
fails (7 guards, not 3) on `main` as well.

- **Older builds still write `save.json`.** After the one-time copy, this build
  never reads it again, so whatever an older branch plays afterwards stays in
  `save.json`.
- **Only F11 > Game > Saves switches.** There is no title screen; the last save
  played opens on launch.
- **Switching mid-flight lands you.** The other save opens where it was left, and
  the one being left keeps its last spot on foot (as with any save, issue #113).
- **AI chat logs (`user://logs/`) are shared.** They are written, never read
  back, so nothing leaks into play.

## After issue #298, no air outside (2026-10-31)

**Checked:** tests/test_harmful_surface.gut.gd on its own (4/4). The full suite
and a walk outside in the game were not run.

- **A speeder counts as shelter** (riding sets `piloting`, the same as a ship).
- **No air meter or breathing sound.** Just the toast and the health bar.
- **Shelter is a plan-view check** (the ring, the hallway's rectangle, the pit's
  circle), not the actual walls.
## After issue #113, saves remember where you were (2026-10-31)

**Checked:** tests/test_save_where.gut.gd on its own (4/4), and the changed
scripts compile. A real quit-and-reload wasn't tried.

- **Only a spot where you stood on your own feet is saved.** Saved while
  flying, riding or down, you load on that planet's spawn, or at the last spot
  you stood on there.
- **Mid-flight isn't resumed.** You load on the ground, not in the ship.
- **Headless runs (traces, CI) never resume**, on purpose, so a save left
  behind can't move a trace's player.

## After issue #307, silent sword kills (2026-10-31)

**Checked:** compiles; not playtested. As the issue asked, there is no new
test. Headless `-s` runs can't build NPC bodies right now (NpcVoice isn't
loaded in that mode), so it can't be traced either.

- **Finding a body has no wall check.** A guard "sees" a body within 16 m in
  their sight cone, even through a wall.
- **Hiding bodies isn't possible.** They stay where they fall.

## After the beast's rock shell and unstick pass (2026-11-01)

**Checked:** `test_smoke`, a headless boot of the town, the beast trace (every
beast line true, including the new TURNS_SMOOTHLY, UNSTUCK and WALKED_OUT; run
with `-s`, so LOCAL_SPOKE_OF_IT is `no_locals` as before), rendered stills (golden hour, close up, night, noon), a headless probe of
two game hours of wandering (no circling, no stalls, the unstick never needed),
and a headless check that the stone materials, eye light and chase flare are
built with the look on.

- **Rendered on Vulkan only.** Godot's default Metal driver crashed at launch on
  this Mac (inside the GPU driver, even for an empty project), so the stills
  (docs/lookdev/hazards/desert_beast*.jpg) were rendered with
  `--rendering-driver vulkan`. The shader hasn't been seen on Metal.
- **The eyes bloom nearly white** at their default energy. Lower
  `look.eyes.energy` if you want more of the purple to show.
- **It still steps onto small rocks.** About once every half hour of game time
  its head pops up onto a rock (up to 2 m) and back off a moment later. The body
  still passes through rocks and buildings.
- **The shell is a shader on spheres**, not a sculpted model. The silhouette is
  the same chain of balls.

## After the party barge fights back (2026-11-01)

**Checked:** `test_smoke`, a headless boot of the town, and a probe run as a
main scene (look on, brains on): a killed dancer ragdolls onto the lower deck,
hurting one rouses all 29 crowd and guards (guards' rifles out), a killed
fighter ragdolls, after the alarm stands down they all go back to dancing,
everyone respawns, and standing and the street-shots flag never move. The
barge trace and its test were not run (it runs with brains off, so nobody
fights there). Nothing was played by hand or rendered.

- **A fighter's body is left behind if the barge drives off** while it lies
  there (the owner shooting their own crowd, then engaging the autopilot). It
  hangs in the air where the deck was until respawn_s is up. The dancers'
  own ragdolls ride along.
- **Fighters can chase you down the gangplank** onto the sand, as far as their
  short leash (14-18 m). There is no navmesh on the barge, so they walk
  straight at you; the ramps between decks work only when the line is clear.
- **Rousing everyone costs a kit build a tick** for about half a second (one
  NpcBody per person, nearest you first).
- **The fighters come back at full health.** A dancer you hurt but did not
  kill is swapped in fresh.

## After the fence, droid post and Skrugs's stall pass (2026-10-31)

**Checked:** `test_plot_buildout` (17/17: the armour bought, sold back and bought again), `test_skrugs_yard` (22/22, three new: the 100 m reach, the offer
the moment you talk, the stall by the gate and garage), `test_inventory` (the new
fence test passes; two old count checks fail on main too), `test_droid_merchant_outposts`,
`test_smoke`, a headless boot, and rendered stills of the stall from the back
gate and the droid post through the front gate. Nothing was played by hand.

- **Selling the gun in your hand to the fence** (story game) leaves it drawn
  until you switch weapons; after that it stays holstered.
- **Skrugs opens with a stolen ship only.** The ship T-89 sold you is still
  bought, but only when you ask him.
- **The 100 m reaches the port's two nearest landing pads** (surface pads 4
  and 5); a stolen ship parked there is his to buy too.
- **The droid post is small through the gate** at 310 m: a hut and a thin mast
  in the gap, easy to miss from the far side of the plaza.
## After the party barge perf fix (2026-10-31)

**Checked:** rendered on the Mac with the look on, a throwaway probe
(test_results/probe, not in the repo) that pauses each part of the town in turn:
the barge was 12 to 14 ms of physics a frame from anywhere; with the fix, physics
with the barge is within 1 to 3 ms of physics without it. The barge trace (every
line true), test_barge_trace, test_smoke and test_ip_neutral pass. The full suite
was not run.

- **Building its people costs a little on the way in:** one person a physics
  tick for 33 ticks the first time you come within 220 m. Not watched on screen
  for a hitch.
- **Standing on the deck is still the heaviest spot** (33 dancers animated at
  full rate within 50 m, every one skinned). Lower `anim_near_m` or the crowd if
  it is too much.
- **The rest of the frame:** with the barge out of the way, the town's people
  (Npcs), the speeder and Skrugs's post, and the droids are the next biggest
  per-frame costs (a few ms each, measured roughly). Not looked at here.
- **Frame time swings with where the camera points** (200 to 17,000 draw calls
  between spots around town), so compare physics and script time, not whole
  frames.

## After the cruiser pass: scope shake, computers, holo map, more droids (2026-10-31)

**Checked:** a rendered probe measuring the reticle scoped in on the cruiser's deck
while turning (before: 2.05 px per frame on average, 8.4 max; after: 0.000), stills
of the bridge, holo table, ramp shaft, corridor and both rooms, a probe that wakes
the crew (26 aboard, 17 droids: 14 assassins and 3 floating, none off the decks
after 15 s), `test_smoke`, `test_ads`, `test_remnant_cruiser` and a headless boot.
Nothing was played by hand; no fight against the new droids was tried.

- **Only the scope is pinned to the eye.** The pistol's iron sights and the arms
  are still drawn from world positions, so far out (the cruiser, 11.5 km from the
  origin) they keep about a millimetre of wobble. Aimed with the pistol (1.25x,
  26 cm from the eye) that is a few pixels. The fix would be the same pin on the
  weapon and glove materials.
- **Scoped in far out, the barrel under the scope casts no shadow.** It is pinned
  to the eye with the scope (its vertices are in the camera's space), so it is
  left out of the shadow pass while you aim; its shadow is back at the hip.
- **The scope's last few frames of aiming in** use world positions (the weapon is
  still blending in), so they can wobble that millimetre once.
- **The holo map is not to scale off the ball.** Heights are squeezed so the orbit
  fits over the table, and the moon sits at a set distance in its true direction.
  It spins as a whole, so north turns with it.
- **Screens are shader pictures**, four kinds picked per screen by where it is.
  They show nothing real (no live map, no alarms).
- **The cruiser trace still builds no crew** when run with `-s` (the NpcVoice
  autoload compile issue), as before.

## After issue #295, Skrugs's yard (2026-10-31)

**Checked:** `tests/test_skrugs_yard.gut.gd` (19/19: landmark per layout, the round
yard inside the wall and clear of every town box, the back gate's gap, a speeder
driven out of his garage and through the gate, both garages driven into and their
walls blocking, the bench in free roam and not in story, ship buying),
`test_speeder_upgrades` (19/19) and `test_speeders` (18/19: "no job board" also
fails on main, since #188 gave Skrugs jobs). The smoke test and a boot check. The
speeder trace was updated but not run.

- **The back gate is tight on purpose.** A speeder lined up on the lane goes
  through; swing into it fast off the turn from his garage and you scrape.
- **His bench box is there in story too.** Only its menu is free roam.
- **A sold stolen ship is back at its outpost next session**, as a lost one is
  (outpost ships are not saved).
- **The yard has no decor of its own** beyond his buildings: no crates, no lamps.
- **Speeders past the fourth park on top of the first spots**, as before.

## After issue #269, the party barge (2026-10-31)
## After the party barge cleanup (issue #269 follow-up, 2026-10-31)

**Checked:** the barge trace, run as a main scene (every line true), and rendered
stills. The full test suite was not run. The `-s` way CI runs the traces fails
to compile right now for every trace that touches WorldState ("Identifier not
found: NpcVoice"); that is not the barge's doing.

- **It floats level along the planet's up, not the dunes.** It lifts to keep
  the sand under its ends below the keel, but it never tilts.
- **It only stops for the world's data** (boxes, rocks, columns). A parked ship
  or a speeder is not in the way.
- **The barge goes back home on a reload.** Ownership is saved; where you
  parked it is not, and nor is a wreck.
- **The dead fall over stiffly** (a tip backwards, not a ragdoll), so they ride
  along with the deck.
- **The band and DJ are look-only bodies** posed by the barge (ClubMoves, the
  cantina's instruments), not NpcBody performers like the cantina's.

## After issue #266, the beetle-centipede beast (2026-10-31)

**Checked:** the headless beast trace (`scenes/beast_trace.gd`, every step
passed) and two rendered stills. The full test suite was not run for this PR.

- **The legs swing; they don't plant.** The steps are a wave keyed to distance
  crawled. Feet can slide or dip a little into slopes.
- **The body is a chain of spheres**, so it still passes through rocks and
  buildings like the blob did.
- **The puff from its tail is the blob's old puff.** It is not real particles.
- **Its fart sound is still the blob's.**

## After issue #220, the beast (2026-10-30)

**Checked:** the smoke test, a headless boot of the town, and the beast trace
(`scenes/beast_trace.gd`, all 38 lines true; `tests/test_beast_trace.gut.gd` 8/8:
named from the planet, rolls, farts, kills on touch, chases when hurt, gives up
at 1 km, 1000 health, stays dead, the locals talk of it). The rest of the suite
was not run for this PR. The trace drives hits and the chase directly (no bolts
are fired), and runs the locals itself since it turns the NPC brains off.

- **It goes through things.** The beast is moved by hand along the ground, not by
  physics. It rolls through rocks, wrecks, packs and buildings, and a chase can
  take it straight through the town walls.
- **Only the player dies.** NPCs, packs and sand pigs it rolls over are not hurt.
- **No health bar.** You can't see how hurt it is; it only squashes when hit.
- **Who hurt it is a guess for blades.** A blade hit (or anything that doesn't
  say who) counts as the player's.
- **Speeder touch uses a simple distance check** (the speeder's centre against the
  beast's radius plus a margin), so a glancing pass at the craft's nose or tail
  may miss.
- **The puff is a few fading spheres**, not real particles, and is skipped in
  headless runs.
- **One beast so far.** Only `port_desert` has a `beast` block. Generated
  planets get none unless their file adds one, and every beast is the same purple
  blob (only its numbers and colours can change per planet).

## After issue #229, first person graphics (2026-10-30)

**Checked:** rendered stills and frame strips (`tools/fpv/shoot_fpv.sh`, HUD
hidden), plus `test_weapon_motion`, `test_weapon_carry`, `test_weapons`,
`test_ads`, `test_sword_combo`, `test_fpv_arms`, `test_smoke`, and a headless
boot. Five stacked PRs: arms, scope, sword, feel and sprint, animations.

**Not done, honestly:**
- **Nothing here was felt by hand.** The sway, bob, landing dip, wall pull-back,
  reload, draw and the sword's first person swings are judged from stills and
  strips at 60 fps only. Spring rates and amplitudes will want a play pass.
- **The rifle reload shows little of the left hand**: its cell sits low, so the
  hand only shows at the bottom edge in a few frames. The pistol's reads well.
- **Walking unarmed, the hands stay out of view** (they pump into view only when
  sprinting).
- **The wall pull-back is one ray from the eye**: a rail or doorway edge not
  straight ahead does not pull the gun back.
- **The sword's first person swings hit from where the blade is drawn**, which is
  close to but not the same as third person. Not tested against the duelist.
- **The town turns hostile in long screenshot runs** (guards, bolts and smoke
  after a few minutes), so `shoot_fpv.sh` is best run a few shots at a time.
- `test_sword_combo`'s `test_early_press_does_not_buffer` and
  `test_pose_keys_are_continuous` fail, on main too.

**Follow-up polish (2026-10-31):** the sword hilt now sits in the closed fingers
(`fist_seat`), an upper arm that shows only near the elbow ends the floating
forearms when you look down, the muzzle light no longer turns the arm flat
orange, aimed in the rifle's barrel stays under the scope, and the scope has the
rifle's twill and an orange band. Checked from stills and the smoke test only.
- **The hilt is thicker than the closed fingers' hollow**, so the fingers sink a
  little into it; from the eye only the knuckles show, which is the intent.
- **The muzzle flash still tints the hand** warm for its few frames; that is meant.
- **Aimed in, the top of the barrel and rail reach into the bottom of the scope's
  front lens**, under the reticle; through the open tube they fill the lower ring.

## After issue #96, desert pack camps (2026-10-29)

**Checked:** headless only. `scenes/natives_trace.gd` (real physics, the real
town) covers the camps, the rest, the chests (taken unseen, then seen), the
rocks and club swings, and a camp shot down that comes back, as well as the
first milestone. Unit tests cover the steering, the moves and the camps
(`tests/test_native_steer.gut.gd`, `test_native_moves.gut.gd`,
`test_native_camps.gut.gd`). The town boots with the look on and builds both
camps. A probe walking the player into each camp found members dropping up to
90 m through the sand (7,600 of 39,000 samples); after the fix, none.

**Not done, honestly:**
- **Looked at in stills only, never played by hand.** The camps, tents (outside
  and in), the fire and the clutter were rendered on the Mac
  (`docs/natives/camp.jpg`, `tent.jpg`, `tent_door.jpg`, `camp_fire.jpg`,
  `camp_props.jpg`); a swing and a throw were seen once in a still.
  The gesture poses (`NativeMoves`) and the rocks in flight were not watched
  moving. The poses are first guesses at joint angles and may look wrong (an
  arm through the head, a wrist bent the wrong way).
- **A pack walking out of the player's reach slides frozen.** Members only get
  physics where the sand's collider is (it follows the player and can lag tens
  of metres behind on a run out). Until it arrives, near members slide along the
  ground in their last pose, as far ones always have.
- **The fire is three glowing cones.** No particles or smoke.
- **Members crowd the fire** on their way to their spots; they do not sit on
  the logs.
- **A camp levels the sand in a square** 34 m across with a 22 m blend
  (`PlanetTerrain.camp_flat_sites`); a camp moved by a rock on its spot can end
  up at the pad's edge, where the tents' low earth floors show again.
- **There is no running day and night.** Packs come in "at night" by the F11
  time-of-day hour, which only changes when you move the slider or rest. Camps
  and chests come back on in-game hours (`WorldState.game_hours`), which run on
  their own at half an hour a real minute and jump when you rest. The sky does
  not follow them.
- **Sitting is a crouch.** People round the fire and the keepers crouch; there
  is no sitting pose.
- **The camera may clip the tent roof** in third person inside a tent.
- **Steering is round known rocks only.** Dune faces, the starcruiser wreck and
  anything else not in WorldGround's boulders or columns are still walked
  straight at. Low boulders (under 0.8 m) are stepped over.
- **Spears and knives** still hang at a fixed angle from the hand, as before.
- **The trace still aborts at teardown**, after its file is written (as other
  traces here sometimes do).

## After the objective pointer and job log (2026-10-29)

**Checked:** `tests/test_objective.gut.gd` (10 tests: the pointer through every
story step, a smuggling run and a bounty; reading never rolls a job or moves the
story; the HUD resolves its targets; the job log on the inventory screen), the
smoke, story, smuggling and IP-neutrality suites, and a headless boot of the town
with no script errors.

**Not done, honestly:**
- **Rendered on foot in third person only** (1600x900, the default text scale):
  the arrow, the diamond and the I screen look right there. Not yet looked at in
  first person or from a ship. With a long job log the tally scrolls below the
  fold (mouse wheel).
- **No key to hide it.** It is always on in the full game (off in the CI greybox).
- **Off the home planet** the pointer only knows the station's drop and fence;
  a bounty out at the port's outposts just says to fly home.
- **`test_inventory` has two failures that were there before this change** (the
  food stall makes three port vendors, and the food look check).

## After the moon handoff smoothing (2026-10-29)

**Checked:** rendered on this Mac, port to the moon (`scenes/handoff_trace.gd`):
the switch frame ~130 ms (was ~680), then 55 and 75 ms, then normal; the first
frame after differs from the last before by 0.017 (mean RGB: the HUD numbers and
the ship's progress; was 0.085); the music and the engine drone carry on with the
same players. `test_handoff_seams`, `test_staged_build`, `test_space_fight`,
`test_sound`, `test_smoke` pass. The headless planets trace still hands the ship
over with 0 error both ways.

**Not done, honestly:**
- **Still about three long frames at the switch.** The station's shell is ~75 ms
  (decor ~25, desert ~15, outside of the station ~16) and its first render ~50 ms
  more; then the bar (~22 ms) and the player's body.
- **The way home is still the longer switch:** the port's shell is ~205 ms (town
  decor ~95, the ship's ground and scenery ~60, boxes ~20), then three ~75 ms
  frames. About 1.5 s later two staged steps still run long: the outposts' sites
  (~180 ms for one piece) and the natives' bodies (~145 ms). Not looked into yet.
- **`scenes/garrison_trace.gd` does not run with `-s`:** it compiles the town
  before the `NpcVoice` autoload exists ("Identifier not found: NpcVoice"), so
  `test_garrison_trace` has no trace to read. Not from this change.
- **The ALT read-out jumps** at the switch (altitude above the moon instead of
  the home planet). It is the true number for where you are.
- **One run had a 1.1 s navmesh step** on the moon's first staged frame; it did
  not happen again in five more runs.
- **`test_planets_trace` fails one check** (`STATION_BUILDINGS`: the station's
  town has had gray homes since they moved there; the test still expects none).

## After the orbit stutter fix (2026-10-29)

**Checked:** rendered on this Mac, pad to the moon handoff with the Remnant's
interceptor up (`scenes/orbit_trace.gd`): every altitude band p50 ~10 ms, p95
~12 ms, nothing over 25 ms (5-7 km was ~145 ms a frame). The ground index tests
pass, including high queries straight over every item (exactly the plain scan).

**Not done, honestly:**
- **`scenes/m14_flight_trace.gd` stops at its crash step:** it looks up
  `mesa_1500_1700`, which the desert's landforms no longer place (the code that
  places them was not touched here). Its GUT test fails for that reason.
- **The interceptor still circles under its ceiling while you are in orbit** (it
  cannot follow you up and keeps hunting until you come down or leave).
- **The pad's orbital fight still starts at the old edge** (space_altitude), with
  its "Contact!" toast: the board's orbital jobs need it.

## After issue #76 part 3, dogfights in the port's sky (2026-10-29)

**Checked:** headless tests drive the real town with the ship and the
interceptor stepped by hand (`tests/test_atmo_dogfight.gut.gd`). They cover
stealing, the scramble rules, the hunt (it closes, attacks and fires without
hitting the ground), being shot down both ways, giving up and landing home, and
the post-fleet rule. The dark ships were rendered on the GPU and looked at.

**Not done, honestly:**
- **A stolen ship is not saved.** It stays yours for the session (land it
  anywhere and it waits there). A new session finds it back at its outpost.
- **The dogfight has not been flown by hand on screen.** How hard the
  interceptor is, its pilot's ranges (`content/core/pilots/remnant_hunter.json`)
  and its ground margin (`scramble` in `remnant_interceptor.json`) are first
  guesses that need tuning at the Mac.
- **After the fleet is beaten it hunts every flight out of town** (the Remnant
  shoot on sight then). That may get tiresome; `wanted()` in
  `src/systems/flight/atmo_fighter.gd` is the one place to change it.
- It only fights in the air. If you land and get out it goes home; it never
  strafes you on foot.

## After issue #162, handoff stalls (2026-10-29)

**Checked** (headless, with the look on, `DUNE_PERF_VISUALS=1` planets trace):
- Worst staged frame: to the station 129.5 → 14.7 ms, home 100.1 → 26.5 ms.
  The cantina dancer (129 ms), the vendors and roamers (60-120 ms) and the
  outposts (55 ms each) were the long steps. Now no staged step is over 27 ms.
- The ship's position, speed, basis and throttle still carry over with 0 error.

**Not done, honestly:**
- **The first frame of a handoff is still long with the look on:** about 160 ms
  to the station and 360 ms home. That is the flight shell: the ball terrain
  (76-94 ms), the desert landforms (`dress_desert`, ~100 ms home), the town
  decor (~80 ms home) and the neighbour ball drawn in the sky (`SpaceTravel`,
  ~50 ms home). Splitting them means letting the ship's ground take the
  landforms later and building `TownDecor` in pieces. That is a bigger change.
- **Single staged steps still go over the 5 ms budget:** a trooper or droid is
  about 20-27 ms, the bar 15-22 ms, the player's body 12-17 ms. A step always
  runs to the end. Going lower needs threaded or cheaper character builds.
- **All 25 outfit textures stay loaded for the run** (2048², so up to about
  0.5 GB of video memory if every colour is used). A town already uses most of
  them.
- **Not looked at on a real screen.** The rendered checks from #162 (horizon
  popping for #122, p95/p99 frame times for #123, flying the handoffs for #121)
  still need someone at the Mac.

## After the on-foot frame rate fix (2026-10-29)

**Checked:** rendered on an Apple Silicon Mac, standing by the Red Wind pack,
a physics step went from 14-22 ms (so 3 to 8 catch-up steps a frame, 5 to 28 fps)
to about 4 ms (one step a frame). A ground query went from 671 to 7 microseconds.
The isolated tests for the ground index, the natives' far ticks, the render
smoothing, the camera rig and the natives trace pass headless.

**Not done, honestly:**
- **The render smoothing has not been watched on screen by us.** It is off
  headless (so traces and tests are unchanged), and its maths is unit tested.
  Things to look at: the gun sight while sprinting and turning, the first frame
  after leaving a ship or speeder, and a downed body.
- **NPC health bars and speech lines still step at 60 Hz** while the NPC's body
  is smoothed.
- **A ground query from a ship 4 km up is still a full scan** (about 0.6 ms):
  nearly every town box is within reach from that high. One a frame is fine.
- **Physics still ticks at 60 Hz.** Characters are drawn between ticks; their
  movement itself is not faster.

## After issue #121, staged planet handoffs (2026-10-29)

**Checked** (run on their own, headless; the full suite was not run):
- `scenes/planets_trace.gd`: both handoffs (port to station, station to port)
  are staged. The first frame was 72 ms on each (it was 1.6 s and 2.3 s with
  everything built at once). All 13 trace tests passed. The ship arrived exactly where, how fast, which
  way and on which throttle it left. It kept flying through the staged build,
  never moving further in a physics step than its speed allows. Exactly one
  town scene was in the tree, and people stayed hidden while high up.
- `tests/test_staged_build.gut.gd`: the runner keeps order and budget, and a
  failed step stops it. Late detail groups take the current tier. A staged
  station arrival (look on) ends with the same nodes, the same people and 96
  far chunks at 64 cells, like a build done all at once.
- With the look on (a profiling script, not in CI), the first frame went from
  6.3 s to 0.34 s (station) and from 12.8 s to 1.0 s (port).

**Not done, honestly:**
- **Some single steps are still long frames.** A step always runs to the end,
  and one procedural character costs tens to hundreds of milliseconds. With
  the look on, these were measured after arriving (container, headless):
  - the player's body: 1.2 to 2.5 s;
  - the port's outpost guards: 2.4 s;
  - the cantina owner: 0.6 s;
  - the station's stage dancer: 0.7 s.
  So the ship keeps flying between them, but each one is still a visible stall.
  They need cheaper or threaded character builds, or guards that build one body
  per step. (Fixed since: the native packs now build one body per step, about
  0.1 s each instead of 3.9 s in one go, and the settings panel builds its pages
  the first time F11 opens it instead of on every arrival.)
- **The port's shell is still about 1 s with the look on.** Most of it is the
  decor parking every bay's ship (0.5 s) and the station drawn in the port's
  sky. Parking only the flown ship first would need a small split in
  `TownDecor.dress`, which this change did not touch.
- **A square-desert planet** (not a ball) still builds its terrain whole on a
  handoff. Only ball planets can be handoff targets today, so this does not
  happen yet.
- **WORST_MS in the planets trace depends on how busy the machine is.** The
  last run passed at 30 ms. On a busy machine, some runs had a 0.22 to 0.26 s
  frame while flying out of the port, and the untouched code did the same
  (0.24 and 0.25 s). That port scene is built the normal way, not staged.
- **In the greybox trace the worst staged frame is now 27 ms (station) and
  0.27 s (home, Skrugs's speeder post).** The station's town collider still takes
  about 1.5 s on its worker thread, and the people wait for it, so the whole
  staged build takes about 90 frames there.
- **Not looked at on a real screen.** Everything above is headless; the look-on
  numbers come from a profiling script on a busy machine.

## After issue #96, desert packs (first milestone) (2026-10-28)

**Proven by the trace** (`scenes/natives_trace.gd`, run on its own; the full
suite was not run):
- food bought, traded for quartz and the quartz sold;
- a pig killed and butchered;
- the horn and the attack;
- 5 minutes survived ending in trade;
- a kill that locks the pack.

**Not done, honestly:**
- **Later milestones are not built:** camps, tents, resting, stealing, packs
  fighting each other and the Remnant, sandstorms, stealing vehicles.
- **Packs walk straight at their goal** (no navmesh out in the desert). They
  walk through boulders and up dune faces like anyone would, and round nothing.
- **No new animations:** no gesture poses, swings or throws. Gestures are lines
  over the leader's head, a hit lands when a member is in reach, and a throw is
  a slow brown bolt.
- **The horn is synthesized** (`tools/audio/make_npc_sfx.py battle_horn.wav`),
  and yells are text only.
- **Looks checked only in two stills** (`docs/natives/packs.jpg`, rendered with
  lavapipe). Spears and clubs hang at a fixed angle from the hand.
- **Teardown errors:** quitting the trace aborts at teardown (the trace's file is
  already written), as other traces in this project sometimes do.

## After issue #99, the asteroid as a real ball (2026-10-28)

**Checked:** `scenes/planets_trace.gd` was run on its own (not the full suite, as
asked) and every step passed:
- Port to station with no fade (ARRIVAL_MODE=handoff, 2.5 km over the station).
- Z landed the ship on its pad, 0.0 m off.
- The player walked out through the gate shield; the hallway's windows held.
- The player walked down over the ramp and through the round shield into the pit.
- The player stood on the rock 500 m out, and on the far side of the ball.
- The dome held people and ships.
- The trip home also had no fade.

Review stills were rendered with lavapipe (`docs/planets/issue_99_station.jpg`).
The unit tests and the trace's GUT test were updated but not run.

**Not done, honestly:**
- **(Mostly fixed by issue #121: the build is staged; see above.)**
  **The switch freezes the frame while the other planet's scene builds.** The
  picture before and after is the same (same spot, sun and stars), but the town
  scene takes as long to build as a landing does. In this container that was
  8 to 14 s, and it will be much less on a real GPU. Building the town in
  stages while you fly in would hide it; that is a follow-up.
- **WORST_MS in the planets trace was 273 ms.** Frame-budget tests already fail
  on main, and the trace teleports the player round the ball, which rebuilds
  the ground under them.
- **From the home planet the station is drawn coarse** (no floors, people or
  boulders), and only its outline shows from kilometres away.
- **In golden-hour light the grey rock reads tan.** It is grey at midday.

## After issue #75, planet generation cleanup (2026-10-27)

**Checked, not run in CI for this PR:** every town size passes the validator with and
without the pit; the station builds headless with and without looks (about 1 s
for the rock and the dome); Z flies the ship in from its arrival point and parks
it on its own pad; the player stands on the rock 150 m and 300 m out; the new Oda
is generated with the planet's name in her prompt; the board offers a smuggling
run and a contract on the station. The full suite was not run (as asked); the
planets trace and tests were updated to the new station but not run.

**Not done, honestly:**
- **(Fixed in #99: the asteroid is a real ball.)** ~~Gravity is the town's, straight down.~~ You could walk over the top of the
  asteroid until it gets too steep (about 450 m out from the town), not all the
  way round it. Walking round a ball needs gravity toward its centre for the
  player, the locals and the ship, which is a bigger change.
- **(Fixed in #99: review stills.)** ~~The rock was not looked at on a screen.~~ The headless runs cannot render, so
  the crater sizes, the faceted look, the boulders and the dome's ribs are only
  checked by numbers.
- **Bounty contracts off the home planet lead home.** The Remnant outposts are
  still the port's, so the station's Oda sends you back there for a contract.
  Smuggling runs are local now: the station has its own drop and buyer.
- **The landing pit's other three bays are empty pads** (the port parks flyable
  ships on two of them).
- **Bigger asteroid towns are untested in play.** Sizes up to 100 pass the
  validator with the pit, but only the size-1 station has been built.

## After issue #65, shooter feel (2026-10-27)

**Proven by tests:** sight on the screen centre within 1 mm at any pitch, rifle
zoom twice the pistol's, transparent scope glass, the slide's start and exit
rules (and that guards never slide), hit and kill markers, the thud rate limit,
health bars (hidden calm, filled after damage, gone on death), the new arms.

**Not done, honestly:**
- **Bounty targets lost their floating name** (it showed from 30 m). Nothing
  marks them now.
- ~~The sword view shows only a sliver of glove~~, ~~unarmed arms out of view~~,
  ~~the pistol one-handed aimed in~~, ~~the scope on the model's optic hump~~:
  fixed in issue #229 (see below).
- **Not felt by hand yet:** the slide, the camera tilt and the thud were checked
  headless and in still renders only.
- **The m11 body trace hangs on this Mac** (also on a clean main), so
  `test_m11_body_weapons` was not rerun against these changes.

## After P1, the planet generator (2026-10-27)

**What is real and proven by tests:**
- Every town size from 1 to 100 validates (two seeds each), and every planet type
  builds. The style parser handles presets and plain words, and the port is
  unchanged.
- The trip is proven in `test_results/planets_trace.txt`, with real physics in the
  real town scene:
  - port to the asteroid station by flying into it;
  - arriving flying the same ship;
  - the size-1 town (cantina, door guard, merchant out back, its own owner);
  - landing on the bay;
  - walking through the gate shield, falling off the edge and waking by the bay;
  - glass solid to people and ships;
  - flying home.

**Not done, honestly:**
- **Generated towns are plainer than the port.** They have no pit bowl (the bays
  are flat pads), no stair tower, stage or alley cables, and no fixer. Their
  layout is a tidy grid of lots, not the port's crooked lanes.
- **The port's extras stay in the port:** the practice range, Skrugs's speeders,
  the jetpack pickup and the outpost. Merchants in generated towns stand at their
  stalls but do not trade yet: no vendor data is generated for them.
- **Element surfaces are simple:** a flat sea or lava plane (lava glows and lights
  the keel) and flat cloud decks. No waves, no lava flow, no swimming.
- **The asteroid has no gravity of its own**, and its rock is solid to ships only
  as a simple column.
- **Planets are placed by hand** (`at`). Nothing stops two overlapping, and only
  planets that name each other through `near` are visible from each other.
- **Reviewed in software rendering only** (`docs/planets/`).
## After the gear models and ragdolls (2026-10-27, issue #25)

**What is real and proven by tests (`test_ragdoll`):** a body dropped on a floor
lands lying down, falls away from the shot, keeps every bone its length, sleeps,
and stands back up exactly as it was.

**Not done, honestly:**
- **The jetpack is big and bright yellow** (the owner's pick of two tries). It sits
  0.44 m deep on the back.
- **The pistol's grips and muzzle were placed by eye**, like the rifle's.
- **The energy sword was not replaced** (see DECISIONS). It is the code-built one.
- **The ragdoll has no self-collision.** An arm can pass through the torso.
  Particles collide with the world only (layer 1). The hips, knees, elbows and neck
  have limits, but the spine can still twist further than a real back.
- **The player in first person** sees the fall from eye height while the screen
  fades; the camera does not follow the body.
- **Droid deaths are unchanged:** a destroyed droid still snaps flat (`_lay_down`).
- **Floating droid legs:** the chosen model has four little legs and hovers 1.7 m
  up, as before.
- **The assassin droid's pistol follows the hand, not the aim.** It points forward
  in idle and walk but swings up while running. Bolts leave its muzzle wherever the
  clip has it. Its fist, where the baked-in gun was cut away, is a little ragged.
- **The rifle's grips and muzzle were placed by eye** from the side view.

## After the sound library and music (2026-10-27, issue #16)

**What is real and proven by tests (`test_sound`):** every sound and track the
library names loads; the music picks space over battle over ambient; battle holds
15 s after the last shot, starts 30 s in and loops back there; the ambient tracks
cycle; credits in and out each make a coin sound; the blade is quieter.

**Not done, honestly:**
- **Not listened to by a human yet.** Volumes, pitches and fade times are first
  guesses; tune them in `content/look/sound.json`.
- **There are no droids yet** except the sparring remote; it is the only thing that
  beeps. A new droid gets `Sound.loop("droid_hum", self)` and `Sound.play("droid_beep", pos)`.
- **Engine sound is one loop for every ship** (pitch only). The speeder borrows it,
  pitched up.
- **Every ship in a dogfight is heard,** each shot its own player (capped at 24 at
  once). A big fight may sound busy.
- **Loading a save can make a coin sound** if it changes your credits while a scene
  is already running.
- **Other things still have no sound:** the town ship's landing gear and crashes, UI
  clicks, ambient town noise.

## After locals on foot (2026-10-26)

**What is real and proven by tests:** with real physics (`test_results/locals_trace.txt`):
the five walkers walk their loops and the four stall keepers stay put facing the
aisle; shooting a shopper raises the locals' alarm (the garrison's stays calm), every
living local fights, the merchants shoot back without leaving the stall and the gear
trader stops trading; shooting a west-houses resident brings in the east-houses one.

**Not done, honestly:**
- **No skins.** Every local is the same placeholder "local" figure, holding a pistol
  it does not visibly have (the upper body poses as if holding a rifle).
- **Locals and troopers ignore each other.** A local's stray bolt hurts a trooper
  (and the other way round) but neither side fights the other over it; a firefight
  in the market does not bring the Remnant.
- **Locals have no flee or surrender.** "All locals fight" is literal: nobody runs.
- **Dead locals come back** when the scene reloads, and a dead keeper's stall
  reopens with them.
- **Two of the four stall keepers do not trade** (vendor_1 and vendor_4 have no
  vendor data yet).
- **Not played by a human.** Numbers (hp 40-55, pistol damage 7-9) are first guesses.

## After M15 part 3, garrison, sound, crouching, smuggling (2026-10-26)

**What is real and proven by tests:** with real physics (`test_results/garrison_trace.txt`):
hurting a barracks trooper raises the town alarm, the klaxon sounds, all five
troopers fight and the far one closes in; the tower sentry spots a wanted player in
the street, warns, raises the alarm, shoots, and stays on the tower; rifles,
footsteps, radio chatter, hurt and the klaxon play; crouching shrinks the capsule to
1.05 m and the eye to 1 m, a crouched player behind a barricade is not seen, and you
stay down under a low lid; a search finds contraband and every answer works (hand
over, pay to keep, run, bribe first); papers can become a spot search; the whole
smuggling loop runs (cache, checkpoint, fence, 90 cr). The combat trace's fights now
involve all five troopers and the bot still wins, runs and gets knocked out.

**Not done, honestly:**
- **Not played or listened to by a human.** The chatter and klaxon are synthesized
  and have only been checked as files that load and play; they may want a real
  sound pass. Volumes and distances are first guesses.
- **The search only knows the `contraband` flag.** Your blasters are never
  confiscated (everyone is armed out here), and nothing is "suspicious but legal".
- **One cache, once.** The drop does not refill; there is one fence and one good.
- **Dead troopers come back** when the scene reloads, as before.
- **Troopers do not climb the tower** or replace the sentry; nobody calls
  reinforcements from outside town.
- **The alarm has one stage.** No "investigate" stage between calm and war.
- **The barricades are still greybox crates** in the look.
- **No ragdolls**, and the death sound is the hurt sound pitched down.

## After M15 part 2, combat NPCs (2026-10-26) -- still current except "Only the gate", "No sounds", the crouch hitbox and "Search is a 3 s freeze", which part 3 did.

**What is real and proven by tests:** with real physics and a fresh town per
scenario (`test_results/combat_trace.txt`): both guards walk their loops and come
back; standing 55 is waved through, 10 shows papers (+1), -10 is searched (held
still) or bribed (-25 cr); -60 at dusk buys its way through; a drawn weapon or a
recent shot makes papers a search; mouthing off twice and pushing through both end
in a fight; at -60 by day they warn, go hostile after 3 s, take two distinct cover
spots that really hide them, crouch, and hit a player standing in the open (about 7
hits in 6 s); a good shooter wins in about 12 s (standing -40, checkpoint down,
rumors live); running gets you away, they search on a leash and go home, and
remember you; standing in the open gets you knocked out in about 8 s and you wake in
the pit lighter. Unit tests cover every checkpoint rule, the brain's states, the
cover picker and player health.

**Not done, honestly:**
- **Not played by a human.** Everything above is bots. Aim error, burst length,
  hide times, the 3 s warning, prices and standing deltas are first guesses. With F4
  on, it is a tuning session on the Mac.
- **Only the gate.** The tower and yard troopers are still statues, and the
  checkpoint is the only place guards think. No town-wide patrols or alarm.
- **Dead guards come back** when the scene reloads (after a flight, or a restart):
  bodies and "the checkpoint is down" are not saved, though the standing, flags and
  rumors are.
- **No ragdolls, no hit reactions** beyond a chest flinch and the tip-over; no
  sounds for their rifles, barks or footsteps (the barks are text only).
- **The player's capsule does not shrink when crouched.** Guards aim lower at a
  crouched player, so cover works, but a bolt aimed high would still hit you.
- **Search is a 3 s freeze.** Nobody looks at your inventory, so contraband means
  nothing yet.
- **The barricades are greybox crates** in the look (the decor pass does not know
  them).
- **Guards do not use the tower, flank, or throw anything**, and only the two gate
  guards fight; no reinforcements.
- **Only three ways a fight ends.** No surrender, no talking your way out mid-fight.

## After M15 part 1, guards on foot (2026-10-26) -- still current except "No brain" and "They do not shoot", which part 2 did.
## After N1, the naming system (2026-10-26)

**What is real and proven by tests:**
- The engine, the name book and its save, determinism, and uniqueness, including
  5,000 names with no repeats and 1,500 callsigns with re-rolls.
- Every grammar reference resolves.
- No franchise name in the library, and franchise and rude words are rejected.
- Names in the real scenes: guards, nameplates, the town and planet, your ship,
  the jetpack, pilots each sortie, and the cantina owner's briefing
  (`test_results/names_trace.txt`).

**Not done, honestly:**
- **Not everything is hooked in yet.** The fixer (old M6 scene), weapons, the
  outpost and the mission's crate are not named on screen. The engine can name
  them: each is one data block and one NameHooks call.
- **Names are generated at about 0.3 ms each** (5,000 in 1.6 s headless). That is
  fine at spawn time, but a crowd of hundreds spawned in one frame would hitch.
- **One world seed for everyone** (`config.world_seed`). A new game does not roll
  a new seed yet, so every player's port is Quartzspring on Namlunyn.
- **Taste is unreviewed.** Some planet words read oddly ("Gaexaegiki"). The
  rude-word and franchise lists are short, so an unlucky combination could still
  slip through.
- **English only**, three human cultures, no alien naming.

## After M15 part 1, guards on foot (2026-10-26)

**What is real and proven by tests:** the two gate guards are NpcBody nodes on the
player's movement code, with Health, flinch and death; the town navmesh bakes from
data on a worker thread; guards walk a patrol, 165 m across town and back, and down
the pit ramps and back up with real physics and no stuck events; their senses see,
miss (side, crouched far), are blocked by the watchtower, feel you close behind,
spot a weapon faster, hear shots within range, and forget
(`test_results/npc_trace.txt`). Unit tests cover the view cone, the awareness
meter, hearing, the ray throttle, path following, corner and stuck handling, the
nav source geometry and obstructions, and the soldier data.

**Not done, honestly:**
- **No brain.** Guards hold their posts. They see you, notice you and turn their
  heads, then do nothing about it: no challenge, no hostility from Remnant
  standing, no shooting back, no alerting each other. That is part 2.
- **They do not shoot.** The trooper brain and squad coordinator (M2/M5) are still
  only used by the old traces.
- **Death is a tip-over.** No ragdoll, no hit reactions beyond a chest flinch, no
  sound. A dead guard stays down until the scene reloads and is not saved, and
  killing one changes nothing in WorldState yet.
- **No avoidance between NPCs.** Paths come from `map_get_path`; two guards on
  one narrow path will bump (the capsule physics keeps them apart, crudely).
- **Navmesh covers the town and its apron only.** Nothing paths into the dunes.
  The bake does not rerun if the town changes at runtime (it does not today).
- **The tower and yard troopers are still statues.** Only markers with a
  `"soldier"` field get a body.
- **Head tracking only.** Eyes follow the body's facing; the head turns but the
  view cone does not.
- **Not played by a human yet.** The F4 line is the way to tune it on the Mac.
  Sight range, fov, reaction time and forget time are first guesses.

## After issue #46, seamless flight (2026-10-27)

**What is real and proven by tests:** no scene change on the way up or down; the
fight starts where the ship is, runs in the town scene, and ends won, lost or
broken off in place; the dogfight toggle; detail tiers switching on the climb
(`test_results/m14_flight_trace.txt`, `tests/test_space_fight.gut.gd`).

**Not done, honestly:**
- **Not flown or measured on the Mac.** The frame times are from the headless
  trace, which draws nothing. Whether SDFGI really was the lag, and where the tier
  thresholds should sit, needs a session with the FPS counter.
- **Raiders do not follow you down.** A fight you dive out of is removed at once; the
  raiders do not chase you into the atmosphere, they just vanish.
- **The town is still there in space.** At 4 km the port is a speck, but it is
  still in the scene (just with less detail). A much bigger world would need real
  streaming.
- **The space backdrop is the town sky.** The stand-alone scene's big planet
  sphere is not drawn above the port; you see the curving sand skirt and the
  stars instead.

## After M14 (2026-10-26) -- still current; the guard notes above add to it.

**What is real and proven by tests:** the whole port-to-space loop with real physics
and the real scenes (`test_results/m14_flight_trace.txt`): boarding, vertical
lift-off out of the pit, hovering, flight over the town and the desert, landing in
the dunes, getting out and walking on the sand, a crash into a mesa and the tow
home, landing on the pad, the climb to the edge of space in 30-40 s, the hand-off
to the space encounter, re-entry into the port's sky, and a jetpack landing on the
desert. Unit tests cover the terrain, the ground and obstacle queries, the flight
states, crash and bump rules, the climb time, and the GameFlow ascent/re-entry
paths.

**Not done, honestly:**
- **Not flown by a human yet.** Every flight in the tests is the bot. The feel
  (turn rates, throttle steps, the mouse stick, the landing speed limit) is
  first-pass and wants a session on the Mac.
- **Reviewed in software rendering only** (`docs/m14/`). Terrain shading, the dark
  sky at altitude and the frame time with the full desert on screen are unmeasured
  on real hardware.
- **Placeholder world.** The outpost is plain boxes. Past the desert's 6 km edge the
  planet is a smooth sand skirt (same sand, no dunes: from high up the desert square shows as a soft edge), and a ship cannot land out there. No
  wrecks, roads or other settlements yet.
- **The rocks are cylinders to the ship.** Mesas and hoodoos are solid as simple
  columns sized from their meshes, not their exact rocky shape: a wing can pass a
  hair inside a bulge or bump an overhang that is not quite there.
- **A collider re-centre can hop you a few cm.** When the desert's walkable collider
  swaps in under a player who is standing still, they can be lifted up to ~0.2 m and
  drop back over a few frames (seen in the desert-walk trace at the gate; it predates
  M14, which only shifted its timing). The trace now waits for you to settle.
- **One heavy frame as you get out** (~39 ms in the headless trace, physics step,
  not scripts or the collider rebuild). Unmeasured on the Mac.
- **Nothing else flies.** No traffic, no patrols, no enemies in the atmosphere.
  The outpost out in the desert has no guards or mission hooked to it.
- **No weapons in the atmosphere.** The ship's guns fire in space only.
- **Ships rest level** wherever they land, held up by the highest point under them,
  so a slope can leave one side hanging.
- **No landing gear, contrails, re-entry glow or camera shake.** (Engine sound: issue #16.)
- **The ship's position is not saved.** A new session starts with it on the pad; a
  ship left in the desert comes back to the pad.
- **One way up, one way down.** The same encounter every ascent, and the same
  re-entry point (5.2 km, south-west of the port, nose down at the town).
- **The tow after a crash is instant** (2.5 s): no wreck, no repair cost.

## After the seamless desert (2026-10-26) -- superseded by the notes above.

**What is real and proven by tests:** the town sits on the dunes at floor level.
With real physics (`test_results/desert_walk_trace.txt`), the player walks from the
pit through the gate onto sand, 700 m into the dunes and back with no fall, the
collider re-centring under them, and every frame under budget. Outside the north
wall there is sand at floor level, the jetpack lands you on it, and a fall through
the world in the desert is still caught. Unit tests cover the footprint from data,
the dip under the pit, nothing poking through the paving, the rebuild budget and
teleports, and the landforms staying clear of the town.

**Not done, honestly:**
- **The collider is coarser than the sand you see** (2 m cells against 1.5 m near
  the town). On sharp dune crests the feet can sit up to about 0.7 m off the drawn
  surface. A finer collider costs more rebuild time; the Mac playtest decides.
- **The visible terrain ends at about 6 km** (fog hides the edge). The collider
  follows you past it, so you can walk on, but there is nothing drawn out there.
- **No sand drifts against the walls,** no wind-blown sand at the gate, no
  footprints. The join is flat sand meeting a plaster wall.
- **The wreck, the orbital ring and the smoke plume are not around the town.**
  They are the beauty corner's horizon and would need moving out of that scene.
- **No navmesh in the desert.** Nothing walks out there yet but the player.
- **The M4 outpost is not placed in this desert.** It still lives in its own data
  for the M4/M5 traces.
- **Boulders have no collision** (as in the beauty corner): you walk through them.
- **Reviewed in software Vulkan only** (lavapipe, `docs/town/look/desert/`);
  re-shoot on the Mac with `tools/town/shoot_town.sh shots=gate_to_desert,desert_look_back,north_wall_outside,desert_aerial`.

## After M13 (2026-10-26) -- superseded by the notes above.

**What is real and proven by tests:** the jetpack with real physics in the town
(`test_results/m13_jetpack_trace.txt`): reached from the pit and picked up, attached,
a tap stays a 0.6 m jump, a hold climbs ~17 m and runs the tank dry, flames only
while burning, fuel refills on the ground after the delay, detach/reattach, flying
out over the north wall is caught, sold for 60, bought back for 120, can't-afford
handled, and a save reload keeps the pickup taken and the pack worn. Plus unit
tests for the fuel model, the controller hook, the inventory and trade rules, the
look kit, and gear added from data alone.

**Not done, honestly:**
- **The pack is a stand-in** (two tanks, a plate, two nozzles). The `scene` hook in
  `content/look/items.json` takes a real model with no code change.
- No dust kicked up (the thruster has sound since issue #16), no heat shimmer, no camera shake.
- **No flight pose.** The body uses its normal airborne/fall pose under the pack.
- **No fall damage.** The player has no health yet, so a 17 m drop is free.
- **Rooftops are reachable** with the pack. Nothing breaks, but nothing was designed
  for up there either, and the town's routes do not cover it.
- **The fall guard is a safety net, not a boundary.** You can fly out over the wall;
  you are put back once you drop 20 m below the lowest floor. (Since the seamless
  desert you land on sand outside instead; the guard measures from the ground.)
- **One item, one trader, one pickup.** No drop key, no inventory screen, no
  shop menu: E acts on the first sellable item, then on the first item in stock.
- **Fuel is not saved** (a reload refills the tank). Ownership, slot, taken pickups
  and vendor stock are.
- **Reviewed in software rendering only** (`docs/m13/`); not yet played on the Mac.

## After M11 + M12 (2026-10-26) -- superseded by the notes above.

**What is real and proven by tests:** the body's gait/jump/land/crouch states, view
toggle spam, camera wall collision, swap spam, blaster hits on range targets, the
3-hit sword chain landing hits, timed deflections sent back into the remote, street
shots changing WorldState (`test_results/m11_body_trace.txt`). The cantina owner's whole
pipe: player text reaches the model fenced, rumors/jobs/secrets only from the
briefing, trust clamps, menu prices, meta/IP filtering, fallback, circuit breaker,
first-token timeout with a beat, stalled streams, canned-but-true offline answers,
memory across visits and save v2; and the real HTTP streaming path against a mock
server (`test_results/m12_bar_trace.txt`).

**Not done, honestly:**
- **No real model with real weights has answered her yet.** The full path is now
  proven against a real llama-server (built from source) with a tiny random-weight
  model: start, load, grammar, streaming, say-first, validation. Quality, voice and
  latency on a real model are still the product owner's first run on the Mac
  (`brew install llama.cpp`, `tools/llm/fetch_runtime.sh`, then the gauntlet).
- **The M10 dogfight frame-budget test is timing sensitive:** it can read just over
  50 ms on a loaded CPU (seen once at 54 ms, passing on rerun).
- **Her confidant secret is a draft** marked "PRODUCT OWNER TO WRITE" in
  `content/core/npcs/cantina_owner_card.json`. The whole card is a first draft.
- **The visit summary** (2 to 3 facts written by the model when you leave) only runs
  when a model is up; offline she remembers only what the game wrote.
- **Bundling llama-server in an export build** is not done; the sidecar uses the
  Homebrew binary path from config.
- **Animation is procedural,** tuned by eye from software-GL renders, not on the Mac.
  No foot IK on slopes or ramps (feet can float a few cm on the pit ramps), no
  turn-in-place step, no hit reactions on the player.
- **Player hits have no consequence** beyond a flash and shake (no player health or
  death yet). Remote stun bolts do no damage by design.
- **The trooper posts and locals are static characters now** (were capsules): no AI,
  no collision, so bolts pass through them.
- **The Kenney blasters are still toy shapes** (rounded blocks), even retinted. Building our own blaster models from parts, like the energy sword, is the planned fix.
- **No crosshair spread feedback or hit markers.**
- **The old M6 scaffold** (`cantina_owner_ai.gd`, `ollama_client.gd`) is kept only for the
  M6/M7/M8 traces; the game uses `npc_brain.gd`.
- **Reviewed in software GL only** (`docs/m11/`); re-shoot on the Mac with
  `tools/m11/shoot_m11.sh`.

## After M9 (2026-10-26)

**What is real and proven by tests:** the town is built from data and validated
(V1 to V8, with a negative test per rule); a headless bot walks all 4 routes with
real collision (`test_results/town_walk_trace.txt`); the decor layer adds no
collision; the pit pad launches the dogfight and the player comes back to the pit
after it (`tests/test_flow.gut.gd`).

**Stubbed / deferred, honestly:**
- **NPCs are static capsules.** No AI, no collision. The cantina owner and fixer are not
  yet wired to their M6/M5 systems inside the town.
- **No navmesh.** The bot walks authored routes.
- **Residential is a uniform grid.** The art pass will vary it.
- **The ramps have no railings,** so you can fall into the pit (no fall damage exists).
- **Town streamer chunks are data only;** they do not load or unload geometry yet.
- ~~**The town is not on the beauty corner plinth or terrain.**~~ Fixed by the
  seamless desert: the town sits on the beauty corner's terrain (not its plinth)
  and the aprons show the sand shader.
- **The market stalls are bare boxes.** (The parked ship is now the real flight model.)
- **The parked ship is small in the pit.** The fighter is 9.3 m long and 2.6 m tall in a 36 by 44 m pit, 6 m deep, so it is hidden from the street until you reach the rim.
- **The gate lintel keeps its greybox color** (overhead outside the cantina has no
  decor rule).
- **Flight payout is shown, not saved.** No early abort from a flight.
- **Look reviewed in software GL only.** `docs/town/look/` was rendered on a machine
  without a GPU, where Godot falls back to OpenGL: no volumetric fog, SDFGI or SSIL.
  Re-shoot on the Mac with `tools/town/shoot_town.sh` for the real look.

## After M10 (2026-10-26)

**What is real and proven by tests:** everything through M8, plus starfighter flight
and dogfights. The headless trace (`test_results/m10_dogfight_trace.txt`) flies the
orbital_skirmish encounter to COMPLETE with the player flown by the AI; GUT checks the
flight model, guns, seekers, shields, AI actions, wave logic, ship looks, the playable
scene, and that a new ship/gun/pilot/fight works from data alone.

**Stubbed / deferred, honestly:**
- **Ships are primitive stand-ins.** `ship_kit.gd` builds them from boxes, cylinders
  and prisms. Real models plug in through the look's `scene` path; none exist yet.
- **No ship-to-ship collisions.** Ships pass through each other and through the
  planet. Hit spheres exist for bolts only.
- **The encounter is not tied to the fixer's contracts or the save file.** (Launch
  and return from the town pit landed in M9.) (The flight model has `to_dict()`/`from_dict()`
  ready for the save system.)
- **Not tested on a Mac.** Logic is proven headless; the look was reviewed in Linux
  software rendering (lavapipe), and the scene has not been played with a real GPU,
  keyboard or mouse.
- **Glow is off** in `content/look/space.json`: under lavapipe it lifted the black of
  space to navy. Try it on the Mac.
- **No gamepad bindings** for flight yet; keyboard and mouse only.
- **Balance is first-pass.** Tuned so the trace's AI-flown player wins with damage
  taken. A human will find it easier or harder; the numbers are all in JSON.
- **The 3D world on foot is still greybox**, as after M8 (unchanged by M10).

## After M8 (2026-10-25) -- superseded by the notes above.

**What is real and proven by tests:** everything in M1-M7, plus the M8 polish pass.
The vertical slice now hangs together in one playthrough
(`scenes/m8_playthrough.gd` / `test_results/m8_playthrough.txt`): walk + FPV/TPV toggle,
a trooper sealing to cover, the 4-trooper squad spreading, a timed-deflection duel with
the duelist, the mission loop to COMPLETE, a typed-default voice turn to the LLM
cantina owner, and a save/load round-trip of the four named things. A performance report
(`test_results/m8_perf_report.txt`) shows the worst frame under the 50ms budget across
the whole session. The GUT "1 orphan" artifact has been **cleared** (it was a
`queue_free` on a detached test node; now `free`). The suite is 0 orphans.

**Stubbed / deferred, honestly (the remaining polish):**
- **The 3-minute gameplay recording is the manual/recorded path**
  (`scripts/record.sh`, macOS screen capture; needs a display). The headless
  cross-system trace is its machine equivalent; this is the same posture as M6/M7.
- **Combat inputs are not yet bound to global input actions.** Fire / block / reload run
  the M2/M3 weapon + blade state machines in the playthrough, but they are not wired to
  on-screen inputs yet. The GUI input layer (and GUI feedback: hit flashes, blade swing,
  on-screen parry) is the remaining polish.
- **The visible 3D world is greybox; full geometry + rendered bolts/blades are
  outstanding.** World streaming is a load-cost model, not a rendered 3D walk (M4), and
  combat/movement are logic + traces, not rendered fights (M2/M3/M5).
- **Take-cover-against-marked-surfaces (movement)** remains deferred.
- **The cantina owner runs a scripted client in CI; live Ollama inference is the manual +
  recorded path.** Kokoro voice and the whisper STT are optional runtimes -- typed input
  is the dependency-free default.
- **Cloud LLM fallback** is an interface + stub only; no API key ever enters the client.

**Model risk (watch):** Qwen3 4B Q4 is the planned cantina owner model. If tool-calling
quality or speed on the dev machine is poor, the fallback is a 1-2B instruct model
that supports tool calls. Documented, not yet measured.

**Disk:** ~12 GB free at M0 start. A single 4B Q4 model is ~2.5 GB; fine; the full
windows export + model cache later will be watched.

**Headless proof limitation:** I can run the engine and capture logs/frames, but I
cannot open the GUI editor and "watch it on screen." The primary proof for each
milestone is the headless CI run + JUnit XML + a machine trace; a screen recording
(scripts/record.sh) is the secondary proof where the spec asks for one. `LAUNCH.md` is
the human-facing guide to running and recording the finished slice.

## After M7 (2026-10-25) -- superseded by the notes above.

**What is real and proven by tests:** everything in M1-M6, plus voice input on top of
the M6 cantina owner (M7). A push-to-talk routes a captured request to the same
`cantina owner.respond()`; **typed is the default and dependency-free path**, whisper is an
optional upgrade that degrades to typed when its runtime/model is absent; a captured
request is read but never executed as a command (no `TOOL=cut_power` in the trace); an
allowed tool still applies; and each turn records a latency.

**Stubbed / deferred, honestly:**
- **whisper.cpp + the STT model are not wired in CI.** The `whisper_runtime` is a
  stand-in that "loads" only when a model is set (mirroring M6's Ollama HTTP post);
  transcription in CI is a canned map. The real whisper run + mic capture is the manual
  + recorded path (scripts/record.sh), not a headless CI step, per DECISIONS.
- **Voice latency is measured from an injected clock**, not the real mic->transcribe
  wall time; real timing is the manual path.
- **Kokoro voice is a signature + graceful null in CI** (M6); a real recorded voice is
  M8.
- **World streaming is still a load-cost model, not a rendered 3D walk** (M8).
- **Combat/movement are logic + traces, not rendered fights** (M8).
- **Take-cover-against-marked-surfaces (movement)** remains deferred.
- **Cloud LLM fallback** is an interface + stub only; no API key ever enters the client.

**Known non-failing artifact:** GUT reports "1 orphan" at process exit (a detached
test bolt). It is a warning, not a test failure -- `ci.sh` exits 0 and "All tests
passed" shows. Tracked for M8 cleanup.

**Model risk (watch):** Qwen3 4B Q4 is the planned cantina owner model. If tool-calling
quality or speed on the dev machine is poor, the fallback is a 1-2B instruct model
that supports tool calls. Documented, not yet measured.

**Disk:** ~12 GB free at M0 start. A single 4B Q4 model is ~2.5 GB; M0 is fine; the
full windows export + model cache later will be watched.

**Headless proof limitation:** I can run the engine and capture logs/frames, but I
cannot open the GUI editor and "watch it on screen." The primary proof for each
milestone is the headless CI run + JUnit XML + a machine trace; a screen recording
(scripts/record.sh) is the secondary proof where the spec asks for one.

## After M6 (2026-10-25) -- superseded by the notes above.

**What is real and proven by tests:** movement + FPV/TPV toggle (M1), two blasters +
a covering trooper with health/death (M2), the energy blade with stamina, timed
deflection, and a duelist enemy (M3), chunk streaming with no >50ms frame-cost over
the port->desert walk plus a data-driven outpost (M4), the full mission loop
(fixer -> contract -> fight -> crate -> payout) with a save/load round-trip of the
four named things plus the 4-trooper squad coordinator (M5), and the cantina owner LLM
conversation (M6). Each milestone ships a headless trace or log plus GUT assertions.

**Stubbed / deferred, honestly:**
- **The cantina owner talks to a scripted client in CI, not a live model.** The
  conversation logic (read-but-never-execute text, 4-tool guardrails, fallback,
  memory) is the real thing and is proven headless; the model on the other end of the
  client is a canned stand-in. Live Ollama inference is a manual + recorded path
  (scripts/record.sh), not a headless CI step, per DECISIONS.
- **Kokoro voice is a signature + graceful null in CI.** The deterministic part
  (text+speaker -> signature) is proven; the audio render returns null when the TTS
  model is absent (headless). A real recorded voice is M8.
- **The Ollama HTTP post is a documented stub.** Request-building and
  response-parsing are live code tested on canned JSON; the actual `/api/chat` call is
  a TODO wiring step, not run in CI.
- **Voice-in (M7)** is not started; the cantina owner takes typed text only. M7 adds
  push-to-talk with measured latency.
- **World streaming is still a load-cost model, not a rendered 3D walk** (M8).
- **Combat/movement are logic + traces, not rendered fights** (M8).
- **Take-cover-against-marked-surfaces (movement)** remains deferred.
- **Cloud LLM fallback** is an interface + stub only; no API key ever enters the
  client. A backend proxy design is documented, not wired.

**Known non-failing artifact:** GUT reports "1 orphan" at process exit (a detached
test bolt). It is a warning, not a test failure -- `ci.sh` exits 0 and "All tests
passed" shows. Tracked for M8 cleanup.

**Model risk (watch):** Qwen3 4B Q4 is the planned cantina owner model. If tool-calling
quality or speed on the dev machine is poor, the fallback is a 1-2B instruct model
that supports tool calls. Documented, not yet measured.

**Disk:** ~12 GB free at M0 start. A single 4B Q4 model is ~2.5 GB; M0 is fine; the
full windows export + model cache later will be watched.

**Headless proof limitation:** I can run the engine and capture logs/frames, but I
cannot open the GUI editor and "watch it on screen." The primary proof for each
milestone is the headless CI run + JUnit XML + a machine trace; a screen recording
(scripts/record.sh) is the secondary proof where the spec asks for one.

## After M5 (2026-10-25) -- superseded by the notes above.

**What is real and proven by tests:** movement + FPV/TPV toggle (M1), two blasters +
a covering trooper with health/death (M2), the energy blade with stamina, timed
deflection, and a duelist enemy (M3), chunk streaming with no >50ms frame-cost over
the port->desert walk plus a data-driven outpost (M4), and the full mission loop
(fixer -> contract -> fight -> crate -> payout) with a save/load round-trip of the
four named things plus the 4-trooper squad coordinator (M5). Each milestone ships a
headless trace or log plus GUT assertions.

**Stubbed / deferred, honestly:**
- **The mission loop is a headless simulation, not a rendered fight or a live AI
  agent.** The bot feeds the state machine a fixed event sequence; the cantina owner
  conversation is a deterministic stub, not real inference. Real LLM inference (the
  cantina owner, M6) is a manual + recorded check.
- **World streaming is still a load-cost model, not a rendered 3D walk.** M4 proved
  the per-frame work stays under the 50ms budget and a walk crosses the boundary; the
  3D greybox and a recorded real frame time are M8.
- **Combat/movement are logic + traces, not rendered fights.** No visible bolts, no
  blade-swing animation, no on-screen parry feedback yet. M8 is the polish pass that
  adds the GUI rendering and the 3-minute recording.
- **Take-cover-against-marked-surfaces (movement)** remains deferred; free walking
  with a pose change and the squad coordinator are what exist so far.
- **Cloud LLM fallback** is an interface + stub only; no API key ever enters the
  client. A backend proxy design is documented, not wired.
- **Voice-in (M7)** may start as a measured latency stub before being made good.

**Known non-failing artifact:** GUT reports "1 orphan" at process exit (a detached
test bolt). It is a warning, not a test failure -- `ci.sh` exits 0 and "All tests
passed" shows. Tracked for M8 cleanup.

**Model risk (watch):** Qwen3 4B Q4 is the planned cantina owner model. If tool-calling
quality or speed on the dev machine is poor, the fallback is a 1-2B instruct model
that supports tool calls. Documented, not yet measured.

**Disk:** ~12 GB free on the volume at M0 start. A single 4B Q4 model is ~2.5 GB, so
M0 is fine; the full windows export + model cache later will be watched.

**Headless proof limitation:** I can run the engine and capture logs/frames, but I
cannot open the GUI editor and "watch it on screen." The primary proof for each
milestone is the headless CI run + JUnit XML + a machine trace; a screen recording
(scripts/record.sh) is the secondary proof where the spec asks for one.

## After M4 (2026-10-25) -- superseded by the notes above.

**What is real and proven by tests:** movement + FPV/TPV toggle (M1), two blasters + a
covering trooper with health/death (M2), the energy blade with stamina, timed deflection,
and a duelist enemy (M3), and chunk streaming with no >50ms frame-cost over the
port->desert walk plus a data-driven outpost (M4). Each milestone ships a headless trace
or log plus GUT assertions.

**Stubbed / deferred, honestly:**
- **World streaming is a load-cost model + frame-time log, not yet a rendered 3D walk.**
  M4 proves the chunk streamer's per-frame work never exceeds the 50ms budget and that a
  walk crosses the port/desert boundary to the outpost -- via a generated per-frame log
  read by a test, not a recorded rendered frame time. The 3D greybox and a recorded
  real frame time are M8.
- **Combat/movement are logic + traces, not rendered fights.** No visible bolts, no
  blade-swing animation, no on-screen parry feedback yet. M8 is the polish pass that
  adds the GUI rendering and the 3-minute recording.
- **Take-cover-against-marked-surfaces (movement)** was deferred; the squad "not all in
  the open" coordinator is still outstanding (note: M4 delivered streaming + the outpost,
  and M5 will carry the 4-trooper squad with the mission loop).
- **Bot playthrough (M5)** talks to a deterministic stub for the cantina owner; real LLM
  inference remains a manual + recorded check.
- **Cloud LLM fallback** is an interface + stub only; no API key ever enters the
  client. A backend proxy design is documented, not wired.
- **Voice-in (M7)** may start as a measured latency stub before being made good.

**Known non-failing artifact:** GUT reports "1 orphan" at process exit (a detached test
bolt). It is a warning, not a test failure -- `ci.sh` exits 0 and "All tests passed"
shows. Tracked for M8 cleanup.

**Model risk (watch):** Qwen3 4B Q4 is the planned cantina owner model. If tool-calling
quality or speed on the dev machine is poor, the fallback is a 1-2B instruct model that
supports tool calls. Documented, not yet measured.

**Disk:** ~12 GB free on the volume at M0 start. A single 4B Q4 model is ~2.5 GB, so
M0 is fine; the full windows export + model cache later will be watched.

**Headless proof limitation:** I can run the engine and capture logs/frames, but I
cannot open the GUI editor and "watch it on screen." The primary proof for each
milestone is the headless CI run + JUnit XML + a machine trace; a screen recording
(scripts/record.sh) is the secondary proof where the spec asks for one.

## After M0 (2026-10-25) -- superseded by the notes above.
