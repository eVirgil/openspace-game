# Plot plan: the story line and owning your gear

Issues #196 (plot improvements) and #186 (own and upgrade your ship and gear),
planned together because upgrading your gear is part of the plot. The work is
split into the **Plot:** issues listed at the bottom.

The rule from #196: build the story out of what the game already has (the town,
the pit, Oda, T-89, Skrugs, the fence, the garrison, the droids, the wreck, the
natives, the fleet) and add as little new code as possible. Most of it is data
in `content/core/story/main.json`, vendor files and NPC cards.

## Two modes, one per save slot

Every save is a **story** save or a **freeplay** save, picked on New Game and
kept in the save.

| | Story | Freeplay |
|---|---|---|
| Start | Landing sequence in the pit, pistol only, everyone neutral | As today |
| Chapters | The list below | The `free` chapter: drops and bounties on repeat |
| Character | Locked to the smuggler; F11 changes the outfit only | Any character, freely |
| Quantonium armour | Swaps your whole body to the desert guard | HP only, outfit unchanged |
| Upgrades, ship ownership | Yes | Yes |

Freeplay stays about as it is today. It only gains the shops from #186.

## Feel

**A tense occupation thriller.** The Remnant runs the port and is always
watching: searches at the gate, guards on the roofs, an alarm that is one
mistake away. You arrive broke in a wreck and have to work out whose side to
stand on.

### The characters

* **The general** (new LLM NPC, own card and brain). A combative Remnant
  officer who walks around near the barracks with a guard and an assassin
  droid. He bullies newcomers, but he loves the Hegemony and being part of
  something so grand. He gets nostalgic about the crashed cruiser: even in the
  sand it's magnificent, and he sometimes walks around in it to remember being
  a private. He is a patron or a target depending on your standing.
* **T-89** (the pit droid). He's been here longer than the war. He still
  pushes the tutorial at first and points you at Oda. He rebuilds your ship,
  and he quietly hates the Remnant: tell him you do too and the repair costs 1
  credit, a *comrade discount*.
* **Oda Vell** (cantina). She still tells most chapters. Dry, careful,
  connected. She tips you about the jetpack, the rifle and the energy blade,
  and she gives the bounty.
* **Skrugs** (speeders, back gate). Loud. He sells you your first wheels and
  tells you about the nomad packs and the rifle.
* **The fence** (market). Buys your contraband, pays bounties, sells the gun
  and jetpack upgrades, and sells quantonium armour after the bounty.

## Remnant standing

Remnant standing and local standing are **separate tracks**. Working for the
general does not cost you with Oda or the locals, and the other way round.

* Standing **> -50**: the general offers droid-hunting jobs. -49 still gets
  jobs; -50 and below is the existing hostile band.
* Each droid job you complete **raises** Remnant standing.
* Mouthing off at the general in the opening **lowers** standing and can get
  you searched on the spot.
* In good standing the general tips you about the crash site.
* When Oda gives the bounty, standing **<= -15** makes **the general** the
  target, your first assassination. Above -15 the target is the outpost
  officer as today, and the general survives the Remnant's retreat: he stays
  in the desert armour and still buys droids.

## Chapters (story mode)

| # | Chapter | Teller | What happens | Ends on |
|---|---|---|---|---|
| 0 | `land` | none | Your ship lands in the pit, seen from far away as if the autopilot brought it in. Only **V: change view** shows. **E** to get out. | Out of the ship |
| 1 | `general` | general | *Halt! You are trespassing on the Hegemony. State your business.* A minute of bullying: your ship is trash, T-89 can fix it. You type replies. Insults cost standing and can get you searched. Then a waypoint to T-89. | Talk ends |
| 2 | `t89` | T-89 | Pushes the tutorial, quotes the 500 credit repair (1 credit with the comrade discount), sends you to Oda. Until you own a ship you get around by speeder. | `met_oda` |
| 3 | `range` | Oda | As today. | `range_visited` |
| 4 | `remote` | Oda | As today. | `range_visited` |
| 5 | `smuggle_1` | Oda | The fence's drop, as today. Oda tells you about the jetpack hidden on top of the cantina tower (by the energy blade) instead of lending hers. | `smuggle_sold` |
| 6 | `droid_merchant` | Oda | *A friend of mine in need of three cargo droids. You could buy them, or fix some up in the desert. Get that done and I'll tell you about an incredible weapon.* Then she tells you about the energy blade on the cantina tower. | Three droids delivered |
| 7 | `heist` | Oda | Issue #413. She keeps her promise (the energy blade on the cantina tower) and sends you to rob the control room at the broken ridge outpost (`remnant_outpost_mid`) with one of her people and an assassin droid: hack the console, bring the 15 flasks to the fence. Never flips the outpost: kill every trooper there and the locals take it as usual. | `heist_paid` |
| 8 | `bounty` | Oda | The general (standing <= -15) or the outpost officer at the nearest outpost. Paid by the fence. Unlocks quantonium armour. | `bounty_paid` |
| 9 | `fleet` | Oda | Take **your own** ship (rebuilt or bought) up to the Remnant fleet. No free keys in story mode. | `fleet_beaten` |
| 10 | `end` | none | End card: the Remnant leave the moon. Its text depends on whether the general lived. | Card closed |
| 11 | `free` | Oda | *Go find one of the native tribes and trade, upgrade your gear, and explore the moon base.* Then open play on the same save: drops, heists and bounties on repeat. | never |

**Running alongside the chapters:** the general's droid-hunting jobs (from
chapter 1 on), at 3x the droid merchant's pay.

## Optional quests

Each one shows a toast in the top right for 5 seconds (**Press "I" to see new
quest**) and goes in the job log. There is no automatic waypoint: each quest
has a toggle in the log.

| Quest | Unlocked by | Prize |
|---|---|---|
| Rebuild your ship | T-89, chapter 2 | Your own ship |
| Steal the rifle from the barracks roof | Ask Oda or Skrugs about the Remnant (*the guards keep guns lying around on top of the barracks*) | Rifle |
| Trade with the nomad packs | Skrugs | Anything any vendor sells, for sand pig only (single digits: blaster 5, armour 12). Packs turn friendly after 1 minute (was 5) |
| The blade on the cantina tower | Oda, telling the `heist` chapter (after `droid_merchant`) | Energy blade |
| The crashed cruiser | The general, in good standing | Red saber (the only prize there) |

The jetpack is not an optional quest. Oda points you at the top of the
cantina tower during `smuggle_1`; it lies on the lookout floor beside the
energy blade. In free play it is still inside the pit cargo droid.

## Shops and upgrades (#186)

Every price is data and tunable. The repair and the armour prices are fixed
by the issue; the rest are starting values set against today's pay (bounty
900-1600, ships from 1500, fleet 5000). A first ship should come after a few
runs and a bounty or two; the top upgrades take the endgame.

| Where | What | Price |
|---|---|---|
| T-89 | Rebuild your wreck | **500** (1 with the comrade discount) |
| T-89 | Boosted shields, reinforced hull, booster speed: any ship you own, each one-time | 1200 / 1200 / 1500 |
| Fence | Pistol: recoil, damage, fire rate (separate, one-time each) | 150 each |
| Fence | Rifle: recoil, damage, fire rate (separate, one-time each) | 300 each |
| Fence | Jetpack fuel | 250 |
| Fence | Quantonium armour (after the bounty, one purchase): toggled like the jetpack, triples HP | **500** |
| General | Pays for assassin droids brought back | 3x the droid merchant |

Owned ships, upgrades and armour are saved and shown in the job log and the
F1 screen.

## Built from what we have

| Need | Existing piece |
|---|---|
| Mode, flags, standing, save | `WorldState` (`standing`, `hangar`, flags, save v2) |
| Chapters, tellers, objectives, job log | `story.gd`, `objective.gd`, `objective_hud.gd`, `content/core/story/main.json` |
| The general | `NpcBrain` + a new card like `skrugs_card.json`; guard bodies from the garrison; assassin droid from `droid_kit` |
| Opening search | The gate checkpoint's search and contraband rules |
| Ship rebuild and upgrades | `ship_salesman.gd`, T-89's AI card, ship data |
| Gun, jetpack and armour shop | `fence.json`, `merchant_npc.gd`, the weapon and item data, `GearController` |
| Armour look | The Remnant guard kit's desert variation |
| Droid merchant chapter | `droid_merchant_outposts.gd`, `droid_roster` |
| Crash site saber | `starcruiser_wreck.gd`, `red_energy_saber.json` |
| Nomads | `natives_director.gd`, `dune_nomads.json` (`hostile.survive_s` 300 → 60) |
| Early travel | `speeder_post.gd` (Skrugs) |
| Fleet | The M10/M14 orbital encounter |

## Issues, in build order

Each depends only on those above it in the same group. Groups A and B can be
built in parallel.

**A. Foundation**
1. #200 Plot: story or freeplay per save slot
2. #201 Plot: optional quests, toasts and waypoint toggles

**B. Ship and gear (#186)**
3. #206 Plot: T-89 rebuilds your wrecked ship
4. #207 Plot: T-89 ship upgrades (shields, hull, boost)
5. #208 Plot: fence gun and jetpack upgrades

**C. Opening and the general** (needs A)
6. #202 Plot: opening landing sequence
7. #203 Plot: the Remnant general meets you in the pit
8. #204 Plot: the general's droid-hunting jobs and Remnant standing
9. #205 Plot: crash site tip and the red saber

**D. The middle** (needs A)
10. #210 Plot: hidden jetpack, rifle and energy blade
11. #211 Plot: nomad packs quest and the 1 minute timer
12. #212 Plot: droid merchant chapter replaces the second drop

**E. The end** (needs B, C and D)
13. #213 Plot: the general as the first assassination
14. #209 Plot: quantonium armour after the bounty
15. #214 Plot: fleet needs your own ship, end card, after the story
16. #215 Plot: chapter rewrite and end-to-end traces
