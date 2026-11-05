# Render rules

The rules for anything that is drawn or ticked, so the game stays fast while it
grows. Read this before dressing a place, adding props or people, or writing
per-frame code. They apply as much as "What can not change" in the
[write-issue skill](../.claude/skills/write-issue/SKILL.md): a PR that breaks one
says why in its body.

Lifted from four places, which keep the detail and the history:
[`docs/station/STATION_FILL.md`](station/STATION_FILL.md) (the station's eleven
rules and the crowd's five), DECISIONS "Draw distance" (2026-11-02),
[`docs/ART_DIRECTION.md`](ART_DIRECTION.md) (the budget) and
[`docs/performance-traces.md`](performance-traces.md) (how to measure).

**The budget:** 60 fps at 1440p on an Apple Silicon laptop, about 11 ms of GPU
a frame, with headroom left for the local LLM.

## Drawing

1. **Batch.** Props go through the building kit (`TownBuildings.part` and
   `solid_part`, `src/systems/world/town_buildings.gd`); a place ends as one
   mesh per material, and anything repeated is a MultiMesh. A new node per prop
   is a review comment.
2. **Share materials.** A new material is a new draw call. Colours come from
   short lists in `content/look/`, never random per piece. Glows are cached
   (`StationFill._glow`; `LookMaterials.glow` makes a new one each call).
3. **Boxes before models.** A prop is a few boxes (a shack is about ten, about
   120 triangles). A model is for what the player looks at up close.
4. **No new shaders in a dressing.** A shader compiles on first use, 60 to
   70 ms on the Mac. Reuse one from `src/systems/look/shaders/` through
   `LookMaterials`. A new surface is a new finish in a shader already
   compiled (the station's rooms: `cruiser_metal` 14 to 32, `StationFill._t`).
5. **Never read a mesh back** from the renderer (`append_from`,
   `surface_get_arrays`, `PrimitiveMesh.get_mesh_arrays`): about 8 ms a mesh
   waiting on the GPU. Build triangles from your own numbers
   (`StationFill._flat`, `LookMeshKit.ring_segment` with a transform).
6. **Draw by distance, from data.** `DrawDistance` gives every mesh under 6 m
   and every light a range from the `draw_distance` block of
   `content/look/world.json` (outdoor, interior, person, orbit). Register a new
   system's root with the town once; do not set ranges by hand. There is no
   occlusion culling, so an interior shows only the floor you are on and the
   ones next to it.
7. **One shadow caster, the sun.** Lamps are glowing materials, or lights with
   `shadow_enabled = false` and a fade distance.

## Building and ticking

8. **Build over ticks** under a ms budget: `StagedBuild`
   (`src/systems/flow/staged_build.gd`) or a `begin` / `step` queue like
   `StationFill`, a couple of ms a physics tick, so a big place loads over
   frames instead of in one hitch.
9. **Few colliders.** Only what you would walk into gets a box, all in one body
   per place. Colliders and people are built before the `use_look` branch; the
   branch only dresses them ("What can not change" 5). The station fill does
   not do this yet (#543).
10. **Tick by distance.** People sleep past the draw distance and think less
    often further out (puppets, not NPCs, until a fight); at most a set number
    of bodies are posed a frame, nearest first. Per-tick code allocates nothing
    and scans no tree: find things once and keep the list.

## Data and proof

11. **Look numbers in `content/look/`, gameplay numbers in `content/core/`.**
    A literal colour or distance in a script is a review comment.
12. **Measure.** Draw calls and primitives from a probe, before and after, in
    the PR. Frame time only as a median over several runs; GPU ms on this Mac
    is noisy, and headless timing is not a render measurement
    ([`performance-traces.md`](performance-traces.md)).
