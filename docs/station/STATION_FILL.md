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
| `engines` | `engines` | Its 8 rooms by turn: reactors, cargo holds (one has the drop hatch in its floor, sealed until the wrecks below exist, #317), pump rooms, workshops. Pipes run round the walkway's ceiling. |

The top floor and the second tower's outpost floor are empty here (#314).

## Render rules

The station is drawn from anywhere in the giant's scene, and a floor of
furniture is thousands of parts. These are the rules that keep it cheap. Follow
them for anything else put in the station (and for any other interior built at
runtime).

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

## Measuring

`test_results/probe/station_probe.gd` (not in the repo) boots the giant with the
look layer and stands the camera at fixed spots: the bay, both market floors,
the homes, the engine deck, the top floor, the second tower and outside. It
reads the GPU and CPU render time, draw calls and primitives at each spot, and
can save stills (`shots`). Run main and the branch back to back.
