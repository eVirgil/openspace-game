# Art Direction: "Sun on Ruin"

The visual bible for the desert spaceport. Every visual decision is checked against
this file. If a change makes a screenshot look worse against these rules, it is
reverted, however clever it is.

## The one-line pitch

**A frontier port living in the shadow of a fallen empire's corpse.** The empire
fell days ago. One of its ships fell with it, and it is still smoking on the horizon.

## Why stylized grandeur, not 4K realism

We are one person plus agents. A AAA studio wins every fight about texture count,
mocap and facial animation. We do not take those fights. Halo, Dishonored, Journey and
Destiny look great because of **composition, scale, light and restraint**, which are
cheap for us and expensive for nobody. Our edge is taste, not polygons.

## Six pillars

1. **Scale is the spectacle.** Every key view has a near layer, a middle layer, a far
   layer, and one thing that is *too big*: the wreck, the ringed giant in the sky, the
   mesas. Put something human-sized in the foreground so the big thing reads as big.
2. **Light is the main material.** Golden hour is the default. A low sun, long
   shadows, warm key light and cool sky fill. Haze turns distance into layers of
   value, like stage flats. If a shot looks flat, fix the light before adding detail.
3. **Shapes over surfaces.** Silhouettes must read at 200 m in a single flat color.
   Big simple forms, a few sharp details. No noisy, high-frequency detail everywhere.
4. **Restrained palette (60 / 30 / 10).** 60% sun-bleached sand, bone and plaster.
   30% cool shadow (dusty violet-blue). 10% accent: dyed cloth in madder red, teal
   and saffron, and the empire's oxblood and gunmetal. Saturation is earned, not
   default.
5. **The world tells the story.** Torn-down Remnant banners, fresh scorch marks,
   scavenger rigs crawling over the wreck, cables strung between salvaged hull
   plates. The port is built *out of* the empire's leftovers.
6. **Original, always.** No franchise silhouettes: no wedge-shaped capital ships, no
   white-armor helmets, no twin suns, no iconic vaporator shapes. The wreck is a long
   ribbed hull with a broken ring, closer to a beached whale skeleton. This is a legal
   rule (see the IP scan) and a taste rule. Copies look cheap.

## Reference games (what to steal: ideas, never assets)

| Game | Take this | Leave this |
|---|---|---|
| Halo CE / Halo 3 | Megastructures on the horizon, sky as a set piece | Sci-fi chrome |
| Dishonored | Exaggerated proportions, painterly texture, strong value groups | Grime on every surface |
| Journey | Sand that glitters and ripples, cloth as the color accent | Empty world |
| Destiny | Skyboxes with planets, mythic scale ruins | Loot-UI clutter |
| RDR2 | Golden-hour light, atmosphere, weather | Photoreal faces |

## Palette

| Role | Hex | Use |
|---|---|---|
| Sand light | `#E8C48F` | Lit dunes, plaster tops |
| Sand mid | `#C9955A` | Most of the ground |
| Sand shadow | `#7A5A4A` | Dune shadow sides (warm, not grey) |
| Sky shadow fill | `#6E7FA6` | Ambient in shadow; never pure grey |
| Haze | `#E9B98A` | Far distance at golden hour |
| Plaster | `#D8C2A0` | Port buildings |
| Hull metal | `#4A4E54` | Salvaged plate, the wreck |
| Remnant oxblood | `#6B1E1E` | Empire banners, markings |
| Cloth teal | `#1F7A78` | Awnings, scarves |
| Cloth madder | `#A8322A` | Awnings, flags |
| Cloth saffron | `#D99A2B` | Market accents |
| Lamp | `#FFB46A` | Practical lights at dusk |

## Lighting presets (data, not code)

Presets live in `content/look/time_of_day.json`. The look-dev scene and any level read
them by id. Tuning a preset means editing JSON and re-shooting, never editing code.

| Preset | Sun elevation | Mood |
|---|---|---|
| `golden` (hero) | about 9 degrees | Warm, long shadows, thick haze, god rays |
| `noon` | about 65 degrees | Bleached, harsh, short shadows, heat |
| `dusk` | about 2 degrees | Violet sky, lamps on, silhouettes |

## Materials

- **Sand:** ripples in the normal map, a soft glitter sparkle, darker and redder in
  shadow. No grass.
- **Rock:** horizontal strata bands, wind-polished tops, darker at the base.
- **Plaster:** pale, slightly rough, dirt darkening up from the ground (a height
  gradient, not a texture), sun-bleached tops.
- **Hull metal:** panel lines, scorch gradients, sand piled against it.
- **Cloth:** saturated dyes, translucent when backlit. It is the only thing allowed
  to move in the wind besides dust.

## Characters

### What the reference games teach (research notes)

- **Silhouette first.** Lock the big shapes before any detail; every faction must
  read as a flat black shape at 50 m. (Shape-language practice, see sources.)
- **Detail hierarchy.** "Having detail everywhere is as good as having no detail at
  all." One busy focal zone (head and chest) and quiet rest areas (legs, coat backs).
- **Grounded function (Halo).** The Chief's armour was designed around carrying
  "800 pounds of tank and jet fighter", using real military kit as reference. Our
  Remnant armour is heavy, plated and practical: power pack, vents, belts.
- **Costume is identity, and it remembers (RDR2).** Layered clothing, wear,
  dust and damage that persists. Ours: the gear shader fades cloth, scuffs metal,
  and dusts boots and hems.
- **Exaggerate with intent (Dishonored).** Striking, slightly exaggerated forms
  and distinctive props (Dishonored's crank-loaded crossbow). Ours: heroic
  proportions (broad shoulders, narrow waist, small heads, big hands and boots),
  and props with a twist: the coil pistol, the forged-spine energy sword.
- **Grounded attitude (GTA V, Battlefront).** Characters are sold by pose and
  material contrast: matte cloth vs. worn metal vs. emissive light.

### The cast

| Archetype | Silhouette | Palette | Signature |
|---|---|---|---|
| Remnant trooper | Tall, plated slab; one huge left pauldron; back power pack | Gunmetal, oxblood, brass | Swept helmet with a single amber visor slit under a brow |
| Remnant commander (player option) | Trooper plus long open greatcoat and shoulder cape | Darker plate, oxblood coat, brass rank | Cloth crest on the helmet, brass epaulettes |
| Smuggler (player option) | Wide hat, long flared duster, low gun belt | Sand leather, dark trousers, teal scarf | Goggles over a dark face wrap, coil pistol, bandolier |
| Duelist | Lean, wide stance; asymmetric rust mantle | Charcoal wraps, rust, madder sash | Sculpted pale mask with one slit; **yellow energy sword** |
| Local | Loose and draped: head scarf, linen shirt, linen trousers | Sand, or a dye per part (darker, lighter, blue, red, yellow) | Scarf and goggles with black lenses, no face; parts mix and match |
| Local guard (issue #393) | The trooper's plated slab, recoloured | Bone-white plate (never pure white), green trim and visor, sand cloth | Reads as the locals' at a glance next to a gunmetal trooper; the places they hold turn green where the Remnant painted red |

- **Faces are covered.** Helmets, goggles, wraps and masks. It avoids the uncanny
  valley and saves months.
- **The energy sword is yellow by default** (`content/core/weapons/energy_blade.json`,
  `blade_color`). It is a forged sword spine sheathed in energy, with a brass
  crossguard: a sword, not a glowing tube.
- **Avoid:** white armour, skull faceplates, T-visors, pointed brown hoods, tube
  hilts. They read as someone else's franchise.
- **Animation priority:** root motion, foot IK on sand, head look-at, idle weight
  shift. The look-dev kit already has two-bone IK for hands on weapons.

### How the characters are built now

`src/systems/look/character_kit.gd` builds each character from primitives on a real
joint hierarchy, with poses as joint rotations and IK for hands. It is a design
tool and a stand-in: when real rigged models arrive (Mixamo animation on
commissioned or kitbashed meshes), they keep the same palettes, silhouettes and
props. Palettes and heights live in `content/look/characters.json`.

Sources: [80.lv on shape language and readability](https://80.lv/articles/character-design-shape-language-and-readability/),
[Kotaku on Halo 4's Master Chief redesign](https://kotaku.com/here-s-why-master-chief-s-going-to-look-different-in-ha-5885765),
[DigiPen on RDR2's clothing system](https://www.digipen.edu/showcase/news/digipen-grad-andy-kibler-puts-clothes-on-the-cowboy-in-red-dead-redemption-2),
[GamesBeat on Dishonored's art](https://gamesbeat.com/how-dishonoreds-artists-created-an-oppressive-world-from-scratch/).

## Ships

The two sides read apart as black shapes against the sky, the same way the cast does
on the ground:

- **Smuggler side (the player's interceptor):** a long forward arrow. Pale worn hull,
  saffron trim, teal glass, blue-white engines. Swept wings with tip guns.
- **Remnant side:** dark plate, oxblood trim, amber glass, orange engines, the
  trooper's colours. The fighter is a hunched pod with forward-swept, drooping blade
  wings and a tall spine. The heavy is a wide armoured block with a wedge prow and
  two nacelles.
- **Bolts:** cyan for the player's side, red-orange for the remnant, warm white for
  seekers. Colour says whose fire it is before shape does.
- **Backdrop:** high orbit over the desert world, near-black space, a warm sun low on
  one side. Values in `content/look/space.json`.

- **The port's fleet (issue #43):** the interceptor (silver and cobalt, wingtip
  guns), a disc freighter in bone and rust, a white and saffron racing courier, and
  a sky-blue gunship. All are Hyper3D models with big clean shapes. The speeder is a
  sand and madder sled on red pontoons. Stills: `docs/lookdev/vehicles/`.

`src/systems/look/ship_kit.gd` builds stand-ins from primitives; colours and sizes are
in `content/look/ships.json`. A real model replaces a stand-in by setting the look's
`scene` path, with no code change (see `docs/ADDING_SHIPS.md`). Review stills:
`./tools/lookdev/shoot_dogfight.sh`; the current ones are in `docs/lookdev/flight/`.

## The world beyond the walls (M14)

- **The seamless desert is what you fly over** (`DesertTerrain`, `DesertLandforms`): its dunes,
  mesas and hoodoos. M14 adds the remnant outpost's plaster buildings with oxblood
  bands 3 km out (placeholder boxes), and past the desert's 6 km edge a plain sand
  skirt that curves away with the planet.
- **Altitude is the time of day's last stop.** The sky darkens from the preset's
  colours to `space` in `content/look/world.json` between 600 m and 7 km; at the top
  it is black with stars, the ringed planet sharp, and the desert curving away.
- Review stills: `./tools/m14/shoot_flight.sh`; the current ones are in `docs/m14/`.

## Camera and post

- Default field of view: 70 (TPV), 80 (FPV). Keep the horizon low, so the sky does
  the work.
- Tonemap: AgX. Glow: subtle, only on the sun, the lamps and blaster bolts.
- Fog: depth fog with aerial perspective for distance layers, plus light volumetric
  fog for god rays. Fog is the main depth tool. Use it before adding geometry.
- Grading: warm highlights, cool shadows, a slight lift in the blacks. Small vignette.

## Performance budget (Apple Silicon laptop, 64 GB unified memory)

- 60 fps target at 1440p output, rendered at about 70% resolution and upscaled
  (MetalFX or FSR2).
- GPU frame: about 11 ms rendering, leaving headroom for the local LLM's spikes.
- Memory: about 6 GB for the game and about 8 GB reserved for the LLM plus voice.
- Shadow distance 600 m with 4 cascades. Far terrain is low-poly; the fog hides the seam.

## The beauty corner (built)

`scenes/lookdev/beauty_corner.tscn` is the current visual target. Open it and press
F6 to walk it (keys 1, 2, 3 switch golden, noon and dusk), or shoot it:

```sh
./tools/lookdev/shoot.sh                                  # all presets x all shots
./tools/lookdev/shoot.sh presets=golden shots=hero_vista  # one image
```

What is in it:
- The port on a rock plinth above a sunken basin, its wall breached at the hero view.
- A crashed capital ship stabbed nose-first into the basin, smoking; a broken orbital
  ring standing on edge; a ringed giant planet in the sky. Mesas and hoodoos layer
  the distance through height fog.
- A market lane of battered (inward-leaning) walls, cloth awnings, cables and
  pennants, ending at a comm spire with torn Remnant banners.
- The cast: a lineup, a smuggler-vs-duelist standoff at the breach, and a Remnant
  patrol in the lane.

Review shots (content/look/shots.json): `hero_vista`, `street`, `dune_return`,
`wreck_close`, `lineup`.

Known next steps:
- Replace primitive characters with rigged models that keep these designs.
- The trooper cuirass reads a little flat from the front; give it a sculpted chest.
- Add moving dust, cloth wind and heat shimmer (the stills hide that they are static).
- Measure frame time on the Mac at 1440p with all presets.

## How we work (the look-dev loop)

1. **Build one "beauty corner" first** (`scenes/lookdev/beauty_corner.tscn`). Make it
   look finished before scaling up.
2. **Shoot fixed cameras:** `tools/lookdev/shoot.sh` renders the same shots for each
   preset to `test_results/lookdev/`. Same cameras every time, so changes are
   comparable.
3. **Review, change one thing, re-shoot.** A change that does not improve the
   screenshots is reverted.
4. **Then promote:** materials, presets and the building kit move into the real levels.

### Rules for the local coding agent

- Visual numbers live in `content/look/`, not in code.
- Never add a franchise-recognizable shape, name or logo.
- Every visual change ships with before and after screenshots from `shoot.sh`.
- Do not raise texture or polygon counts to fix a shot that a light, fog or
  composition change would fix.
- Keep `scripts/ci.sh` green. Look-dev code must not break headless runs.
