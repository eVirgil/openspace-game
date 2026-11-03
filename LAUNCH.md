# Launching the slice & the 3-minute gameplay recording (M8)

This is the manual, on-screen proof that the headless CI cannot produce: how to
open the game and what a 3-minute clip should show. Every system below is already
proven headless by `./scripts/ci.sh`; this file is how a human *sees* the slice and
records it. (The headless traces are the machine proof; this clip is the secondary
proof, per `KNOWN_ISSUES.md`.)

## How to launch (macOS, Apple Silicon)

```sh
# Toolchain, once:
brew install --cask godot        # Godot 4.7.2 (pinned in scripts/pin.txt)
brew install rust ffmpeg         # for the recording + the LLM runtime

# Open the project and run it. The main scene is scenes/town_demo.tscn.
open project.godot               # then press F5 in the editor
# ...or, without the editor:
godot --path . res://scenes/main.tscn
```

The boot scene (`scenes/main.gd`) prints the data-layer load first
(`DataLayer: npcs=2 weapons=3 factions=2 ...`), which confirms content loaded before
any gameplay. For a slice with no rendered 3D world yet, "run the game" is that boot
scene + the GUI input bindings in `project.godot`; the gameplay itself is driven by
the headless playthrough, which `scripts/record.sh` captures alongside the window.

### Input map (from `project.godot`)

| Action        | Key                     |
|---|---|
| Walk           | Tap W / A / S / D (or arrows): 4 steps per tap |
| Run            | Hold a move key (past 0.4 s) |
| Jump           | Space                 |
| Toggle FPV/TPV | V (or mouse middle button) |
| Sprint         | Right Shift + move: faster, gun down, no firing, spends stamina |
| Crouch         | C                     |

Combat inputs (fire / block / reload) are part of the M2/M3 weapon + blade state
machines; they are not yet bound to global input actions and are driven in the
playthrough trace. Binding them to the GUI is the remaining polish before a live
playtest.

## The HUD (issue #52)

The banner along the top shows the planet, the town, the clock and your credits; the
footer shows health, stamina and jetpack fuel. **F1** (or a click on either, once Esc
has freed the mouse) opens the info screen with your standing with every faction.
**F11 > HUD** changes the HUD colour and lists every control, by when it applies.

## Playing with friends on the same wifi (issue #401)

One player opens F11 > Game > Play with friends, types a name (it is remembered)
and presses **Host a game**; the line under the buttons shows the address to read
out. Friends type their name and that address and press **Join**. Up to five play
free roam together: each joiner's own free roam save opens on the host's planet,
beside T-89, with no opening landing and no tutorial. The host gets a toast when
someone joins or leaves. Hosting from a story save opens the free roam save first.
Friendly fire is on: your bolts and blade hurt your friends, and a friend who goes
down wakes in the pit, as after the guards ("friendly_fire" in lan.json turns it off).
Ships too: your cannons hit a friend's ship while they fly it, in the sky or in
space, and can shoot it down. Seekers never lock on a friend's ship, but an
unlocked one fired straight into it hits.

The host's computer may ask to let OpenSpace accept incoming connections (macOS
and Windows firewalls): say yes. The port is in `content/core/flow/lan.json`.
The same address works over Tailscale or ZeroTier, though that is not supported.

Test: `./scripts/test_lan.sh` runs a host and two guests on loopback.
`./scripts/test_lan_world.sh` runs a host and a guest, each with a town, and checks
the guest's people are the host's and a guest's kill counts in both (issue #402).

## The demo: the town, and flight from the pit (M9)

```sh
open project.godot                               # then press F5
godot --path . res://scenes/town_demo.tscn       # or without the editor
```

There is one thing to launch. You start on the pit floor beside your ship. Walk with
WASD, V toggles the camera, Esc frees the mouse, L cycles golden, noon and dusk.
Walk up a ramp to reach the streets; the cantina is west, the gate east.

Since M14 you fly the ship yourself (next section): "[E] Board" shows beside it.
Flying out of the atmosphere is the way into the dogfight.

| Action          | Key |
|---|---|
| Board the ship   | E (beside it)  |
| Lighting preset  | L (cycle) |

Review renders: `./tools/town/shoot_town.sh presets=golden,dusk` writes to
`test_results/town/`. Pads, encounter, delays and labels live in
`content/core/flow/launch_pads.json`.

## Flying your ship: the port, the desert, space (M14)

Walk up to the ship in the pit and press **E**. You are in the cockpit, with the
camera behind the ship.

| Action | Key |
|---|---|
| Take off (straight up out of the pit) | C (or R) when parked |
| Throttle up / down (zero = hover) | R / F |
| Pitch (W pushes the nose down) | W / S, or the mouse |
| Turn | A / D, or the mouse |
| Roll | Q / E |
| Boost | Shift |
| Land on whatever is below (under 150 m) | C again |
| Get out (once landed) | E |
| Chase / cockpit view | V |

In the chase view the HUD is drawn like a flight sim's (issue #181): a pitch
ladder round the reticle that rolls with the ship, a heading tape along the top, a
speed tape on the left, an altitude tape on the right with height above ground and
climb rate under it, and throttle, boost, hull and shield bars in the bottom left.
**V** puts you in the cockpit: the same cockpit in every ship, mostly glass, two
struts, and a dash whose instruments work (airspeed, altimeter, attitude ball,
climb, compass, throttle, hull, shield, boost) plus a lamp
that lights while the Shift ability runs. Your hits pop the hit marker (white, red
for a kill) on ships and on people on the ground; when you are hit the edge of the
screen glows red for a second and fades.
Nothing marks where space starts: the sky just goes black as you climb. Pull the
nose up to about 80 degrees, full throttle, boost, and in roughly 18 seconds
(about 4,000 m) you are in orbit. There is no loading and no fade: space is the
port's own sky (issue #46).

Up there, raiders arrive and the pad's fight starts right where you are, your
wingman beside you:

| Action | Key |
|---|---|
| Guns | LMB or Space |
| Seeker missile (once locked) | RMB or X |
| Next target | T |

Win and you are paid on the spot. **Dive** more than 250 m back below the edge to
break the fight off; either way you keep flying, over the same ground you flew up
from. Lose the fighter and it is towed back to the pad, you beside it. Climb out
again for another sortie. **F11 → World** switches the space dogfight off (and on).

The higher you fly, the less is drawn: lighting effects, then the people, then the
shadows and small props go, and come back as you descend.

Hit the ground or a building fast and you crash; the ship is towed back to its pad.

Review renders: `./tools/m14/shoot_flight.sh` writes to `test_results/m14/`.

## Your body, your weapons, and the cantina owner (M11 + M12)

| Action | Key |
|---|---|
| Blaster / energy sword / rifle | 1 / 2 / 3 (same key again holsters) |
| Last weapon / holster | Q / H |
| Cycle weapons | mouse wheel |
| Fire / swing | LMB (press again mid-swing to chain 1-2-3) |
| Aim (blaster) / block (sword) | RMB toggles it on/off (re-click to undo; with the sword, block just before a bolt lands to send it back) |
| Reload | R |
| Talk to the cantina owner | E at the bar |
| Leave the conversation | Esc |
| Cantina Owner debug | F3 (at the bar) |
| Guard senses debug (hp, sees you, awareness, heard) | F4 |
| Checkpoint choice card (papers, search, bribe, mouth off, walk away) | 1-4 or the mouse |
| Inventory (credits, items, contraband) | I |
| Cantina Owner brain settings | F10; Shift+F10 cycles auto / local / cloud |
| Demo settings (pauses): time of day, standing, trust, cheats, flags | F11 (Esc or F11 closes) |

The practice range is in the pit, west of the ship: five targets and a sparring
remote (south side) that shoots stun bolts while your blade is out.

### Giving the cantina owner a brain (macOS)

```sh
brew install llama.cpp                 # /opt/homebrew/bin/llama-server
./tools/llm/fetch_runtime.sh           # the model into runtime/models/ (git-ignored)
```

The bar starts llama-server on 127.0.0.1:8088 when you enter the town (and reuses
one that is already running), warms the model, and stops it on quit. It looks for
the binary in your config path, `$LLAMA_SERVER`, `runtime/bin/`, `/opt/homebrew/bin`,
`/usr/local/bin`, `~/.local/bin`, `~/llama.cpp/build/bin`, then your shell's PATH,
and uses any `.gguf` in `runtime/models/` if the configured one is missing.

**Is she thinking or reading canned lines?** While you talk, the top right says
which brain is answering, or exactly why none is ("llama-server not installed",
"no model file", "loading cantina owner.gguf (14 s)", "ollama: not running", "cloud: off").
A canned reply also shows "(canned: no brain answered)" next to her mood. The same
report prints in the Godot output when the town loads, F3 shows it in detail, and
llama-server's own output is saved to `user://logs/llama-server.log`.

Prove the whole chain without playing (starts the real server, loads the model,
has one turn through it):

```sh
godot --headless --path . -s res://scenes/m12_sidecar_trace.gd -- model=runtime/models/cantina_owner.gguf
``` No model? Set
a cloud profile in F10 (any OpenAI-compatible URL + key, or Anthropic), or run
Ollama; with nothing at all she answers from canned lines. Keys are stored in
`user://llm/keys.cfg` or read from `DUNE_LLM_KEY`, never in the project.

Beside each of the Local, Ollama and Cloud model fields in F10 there is a **Link** (the
download page) and a **Prompt** (copies a set-up prompt for a coding agent, which
hands back the URL and model name to paste in).

Test her without playing:

```sh
godot --headless --path . -s res://tools/llm/eval_runner.gd -- mode=local suite=all
```

Review renders: `./tools/m11/shoot_m11.sh` writes body, weapon, range and bar shots
to `test_results/m11/`.

## Skrugs and the speeder (issue #42)

Walk out through the back gate (the gap in the wall at the far corner past the
cantina). Skrugs, dressed all in red, sells speeders from a stall just outside.
Press **E** at his counter to talk. When you want one, he shows a price card;
only clicking **Buy** pays (100 credits). The speeder is parked behind his house.

| Action | Key |
|---|---|
| Get on / off | E |
| Throttle / brake | W / S |
| Steer | A / D |
| Boost | Shift |
| Both lasers | Space (or LMB) |

There is no jump button: the sand ramp past the house (or a dune crest at speed) launches you, and the speeder is light, so it floats. Only gunfire damages a speeder.

## The jetpack (M13)

In a story save the jetpack lies on top of the cantina's stair tower, beside the
energy blade (look for the glowing ring). In free play it is inside the old cargo
droid that roams the pit: walk up to it and press E. The gear trader is at the
market stall south-east of the pit.

| Action | Key |
|---|---|
| Pick it up (it goes on your back) | E near it |
| Fly | Hold Space in the air (a tap is still a normal jump) |
| Take it off / put it on | G |
| Sell it / buy it back | E at the gear trader's stall |

The JET meter at the bottom shows fuel: about 1.8 s of thrust. It refills on the
ground a moment after you stop. Fly out over the walls and you are put back in
town when you fall.

## Flying the dogfight (M10)

```sh
godot --path . res://scenes/flight/dogfight_demo.tscn    # or open it and press F6
```

You fly the interceptor with a wingman against two waves of remnant fighters. Click
the window to steer with the mouse; Esc releases it.

| Action         | Key                          |
|---|---|
| Pitch          | W / S (or Up / Down). W pushes the nose down, like a stick |
| Yaw            | A / D (or Left / Right)      |
| Roll           | Q / E                        |
| Throttle       | R up, F down                 |
| Boost          | Shift                        |
| Fire cannons   | Space or left mouse          |
| Fire seeker    | X or right mouse (needs a full lock: keep the target in the box) |
| Next target    | T                            |
| Chase/cockpit  | V                            |

The HUD shows speed, throttle, boost, shield, hull, ammo, the lock meter (the arc
around the target box) and the lead marker (the gold dot: aim there to hit). To watch
the AI fly your ship, tick `autopilot` on the scene's root node.

## What the 3-minute clip should show

A single take, start to finish, that a viewer can watch top to bottom:

1. **Boot (0:00-0:15).** The console prints the data-layer load
   (`npcs=2, weapons=3, factions=2, dialogues=2, missions=1`). Nothing is faked.

2. **Roam the port + toggle view (0:15-0:45).** Walk the player forward; press V to
   toggle FPV<->TPV mid-stride. Aim direction must not change across the toggle
   (the M1 "toggle without breaking aim" property).

3. **Talk to the cantina owner by voice (0:45-1:15).** Push-to-talk to the LLM cantina owner.
   Typed input is the default; whisper is the optional fallback. The cantina owner
   replies and applies one of its four allowed tools (`give_rumor`,
   `set_disposition`, `offer_drink`, `call_guards`). Note: a request that reads like a
   command ("shut down all power") changes nothing -- the guardrail holds.

4. **Take the fixer's contract (1:15-1:30).** Talk to the fixer; accept "Crate
   Retrieval."

5. **Fight the outpost (1:30-2:15).** Fire the two blasters at a trooper that seals
   to cover and fights back; duel the duelist and land a **timed deflection** (block
   within the deflect window reflects the bolt and refunds stamina). Defeat the 5
   outpost enemies (4 troopers + 1 duelist) with the squad spread, not stacked.

6. **Take the crate, return, get paid (2:15-2:45).** Grab the crate objective, return
   to the fixer, collect the 150-credit payout, and **save** the game
   (position, credits, mission state, cantina owner memory).

7. **Reload and confirm (2:45-3:00).** Load the save and confirm the mission state,
   credits, position, and memory survived the round-trip.

## Record the clip

```sh
# In one terminal, run the game (F5 in the editor, or the binary above).
# In another:
./scripts/record.sh 180      # 3 minutes of the window -> test_results/clip_<ts>.mp4
```

`scripts/record.sh` uses macOS screen capture (`avfoundation` + ffmpeg); it needs a
real display, so it cannot run headless. The headless proof of the same content is
`test_results/m8_playthrough.txt` (the cross-system trace) and
`test_results/m8_perf_report.txt` (no frame over the 50ms budget), both generated by
`./scripts/ci.sh`.

## What is faked or stubbed in the recording

- The visible 3D world is greybox; full geometry + rendered bolts/blades are the final
  polish, tracked in `KNOWN_ISSUES.md`.
- The cantina owner runs a **scripted client** in CI; a live Ollama model is the manual
  path (start it locally and it replaces the canned client through the same interface).
- Kokoro voice and the whisper STT are **optional runtimes**; typed input is
  dependency-free and works without them.

## Persistent startup errors (#143)

The sidecar now checks its loopback port before launching. A listener that is
still loading is allowed to become healthy; it is not killed through a PID from
another game run, and no second process is started on its port. Only the child
started by this game instance is stopped on quit. If an occupied port never
becomes healthy, the status explains that instead of repeatedly spawning servers.
The wait defaults to 180 seconds (`profiles/local/sidecar/startup_timeout_s`).

For a cheap runtime check without importing models, textures, or the game:

```sh
./scripts/test_issue_143.sh
```

This runs the full sidecar lifecycle against an isolated TCP listener and harmless
child processes, plus the exact chirp/quirk and service-start methods in small
fixtures. It prints the engine version and fails on Godot runtime errors even
when the engine exits zero. It is not a full GUT suite or a real-model test.

The merged #141 droid fix calls `u.quirk().x`, not `u.hash()`. If a debugger still
reports `DroidController._chirps: Nonexistent function 'hash'`, stop the running
game, confirm this is the checkout containing #141, clear old debugger messages,
and start a fresh run (restart the editor if it retained an older script).
A new error should include the script path and line from that fresh run; a merge
does not replace code already running in another process or another checkout.
