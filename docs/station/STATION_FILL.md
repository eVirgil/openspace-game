# What is in the station's floors (issue #315, part 1)

The station's shell is `StationHull` (`content/core/stations/orbital_station.json`).
What stands in its floors is `StationFill` (`src/systems/world/station_fill.gd`),
from the config's `"fill"` block: one entry per floor id, by `use`.

| use | Floors | What is in it |
|---|---|---|
| `favela` | `homes` (main tower, the lower homes) | Open from the walkway to the glass and packed like a favela: nine rings of shacks, booths and the town's huts back to back in pairs with an alley between each pair, 8 radial alleys out from the walkway and a lane to the tunnel door. A third of the shacks have a second one built on top, with a ladder. Cables strung with bulbs and washing lines cross the alleys. About 355 shacks, 120 booths and 20 huts. |
| `suites` | `homes_2` (second tower's top floor, the upper homes) | 8 big suites (10 rooms; the two by the tunnel's corridor have no door), all open, dressed like the cantina's club and the party barge: dark wood floors and panelling with a gold rail, neon lines, a bar with lit bottles, an aquarium, two velvet booths under chandeliers, a light-up dance floor ringed by cocktail tables, a long sofa, a grand piano in every other suite, a round bed under a gold canopy by the window. |
| `homes` | (none today) | Long studios in a floor's open rooms (lounge, kitchen, partition, bedroom by the window), the rest locked with a shut door and an amber lock light. |
| `market` | `markets`, `markets_2` | Rings of the town's market stalls (`TownMarket`: tables, canopies, wares), and an outer ring packed with shacks and booths like the favela's (`pack`). A lane is kept clear to every tunnel door. |
| `remnant` | `outpost` (second tower's middle floor) | The Remnant's deck (issue #314): its rooms by turn are the cruiser's control room (`OutpostRoom.inside`, the planet map over its holo table, built near), bunk rooms, armouries, the commander's office and a mess; red stripes, banners and lamps down the walkway, and a staggered barricade with a lit checkpoint at the tunnel from the favela. Its reds are faction materials (`faction_mats`): taken, the deck is repainted in the locals' colours in place. The people are `StationRemnant`. |
| `engines` | `engines` | Its 8 rooms by turn: reactors, cargo holds (one has the drop hatch in its floor, sealed until the wrecks below exist, #317), pump rooms, workshops. Pipes run round the walkway's ceiling. |

The top floor is still empty (the cantina comes with #314's rest).

## Render rules

The station is drawn from anywhere in the giant's scene, and a floor of
furniture is thousands of parts. These are the rules that keep it cheap. Follow
them for anything else put in the station (and for any other interior built at
runtime).
The general version, for anything drawn or ticked anywhere in the game, is
[`docs/RENDER_RULES.md`](../RENDER_RULES.md).

1. **Batch everything.** Every part goes through the town's building kit
   (`TownBuildings.part`), never as its own node. At the end of a floor every
   box, cylinder and sphere is merged into **one mesh per material**. The kit's
   own ArrayMeshes (hut domes, arches) are drawn as one MultiMesh per mesh and
   material. The stalls' cloth is one MultiMesh per canopy size and colour
   (`TownMarket` shares a cloth mesh between canopies of a size). A floor is
   16 to 90 meshes.
2. **Share materials.** A new material is a new draw call. Glows are cached in
   `StationFill._glow` (`LookMaterials.glow` is not). Paints, fabrics, velvets
   and neons come from short lists. The town's huts take two fixed sizes, and
   shack sizes are snapped to 25 cm. Nothing gets a random colour per piece.
3. **Build your own props from boxes.** A favela shack is about ten boxes
   (about 120 triangles); a town hut is 2,000 to 3,000. The town's huts are
   only a few in every ring.
4. **No new shaders aboard.** The first use of a shader compiles it (60 to 70 ms
   on the Mac). The huts use the station's own `cruiser_metal` finishes, not
   the town's plaster, and their door clutter (plaster jars) is off
   (`TownBuildings.clutter`).
5. **Never read a mesh back.** Reading a mesh's arrays from the renderer
   (`append_from`, `surface_get_arrays`, even `PrimitiveMesh.get_mesh_arrays`)
   waits on the GPU, about 8 ms a mesh however small. `StationFill._flat`
   builds a primitive's triangles from its own numbers instead.
   `LookMeshKit.ring_segment` takes a transform, so `TownBuildings.arch` no
   longer builds a mesh and reads it back to turn it.
6. **Build a little each tick.** `StationFill.begin` / `step` queue the work.
   `SpaceStation` gives it `budget_ms` (2 ms) each physics tick, one floor at a
   time. The slowest tick is about 14 ms, once (the first stalls make their
   wood and canvas). The whole station is about 100 ms of work over about a
   second.
7. **Draw only the floors near you.** No occlusion culling in the project, so a
   floor's fill is shown only while the camera is within `show_dy` (30 m) of
   its height band and `show_m` (60 m) of its glass: the floor you are on and
   the ones just above and below. Checked every 6 physics ticks, not every
   frame.
8. **No lights, no shadows.** Lamps and panels are glowing materials. The
   station's own interior lights stay as they were. Nothing in the fill casts
   a shadow.
9. **Few colliders.** Only what you would walk into (couches, counters, beds,
   tables, stall tables, huts, machines, crates) gets a box, all in one `Props`
   body a floor. Wares, canopies and trim are only drawn.
10. **Look layer only.** With `use_look = false` there is no fill, and the
   station plays as before.

## The crowd (`StationCrowd`, `src/systems/world/station_crowd.gd`)

About 80 people (the config's `"crowd"`), each with a home floor. They walk the
walkways, go down the alleys and aisles to stand at a stall, a booth or a shack
door (the fill's walking net, `StationFill.nets`), look into open rooms, ride
the elevators (they board only when the car has stopped at their floor with its
doors open) and cross the tunnels to the other tower. Hurt one and the nearest
armed people on your floor (no more than `rouse_max`) become real locals where
they stand, run by a Townsfolk of the station's own; they walk again once the
alarm has been down a while. The dead fall as ragdolls and are back later.

Render rules for people, on top of the ones above:

1. **Puppets, not NPCs.** A kit body moved by script along paths in the
   station's frame, with a hit capsule. No physics body, navmesh or brain until
   a fight, and then only `rouse_max` of them.
2. **One walk cycle for everyone.** `BodyAnimator` is stepped once at load into
   a 24-frame table; a walker reads its frame from it. Nobody runs the animator
   per frame.
3. **A posing budget.** At most `anim_budget` (12) bodies are posed and skinned
   a frame, nearest first: every frame within 25 m, every fourth out to 60 m,
   frozen past that.
4. **Drawn near the camera only.** Within `people_m` (70 m) and `show_dy` (30 m)
   of its height, like the fill. Shadows only within `shadow_m` (20 m).
5. **Built one a frame,** once the camera is within `build_within` (900 m).

Measured on the Mac: the crowd's own time is 0.2 ms a frame from outside or a
quiet floor and about 0.8 ms on a busy one (12 posed). A kit body is about 20k
triangles, so a busy floor draws 0.3 to 0.7M more triangles and 50 to 100 more
draw calls; the GPU's frame stayed in the same range.

## Measuring

`test_results/probe/station_probe.gd` (not in the repo) boots the giant with the
look layer and stands the camera at fixed spots: the bay, both market floors,
the homes, the engine deck, the top floor, the second tower and outside. It
reads the GPU and CPU render time, draw calls and primitives at each spot, and
can save stills (`shots`). Run main and the branch back to back.
