# Known issues archive

Notes from `KNOWN_ISSUES.md` that later milestones replaced, kept for the
history. Nothing here is current; read `KNOWN_ISSUES.md` for that. Newest on top,
as they were.

## After the seamless desert (2026-10-26)

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

## After M13 (2026-10-26)

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

## After M11 + M12 (2026-10-26)

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

## After M8 (2026-10-25)

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

## After M7 (2026-10-25)

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

## After M6 (2026-10-25)

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

## After M5 (2026-10-25)

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

## After M4 (2026-10-25)

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

## After M0 (2026-10-25)
