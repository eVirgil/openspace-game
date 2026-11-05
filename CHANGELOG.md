# Changelog

Plain English, newest on top. One entry per milestone.

## Sniper rifle balance, and the weapon keys move (2026-11-04)

- **The sniper rifle fires half as fast.** 0.24 s between shots instead of
  0.12, so it is now slower than the rifle blaster.
- **Scope it to snipe.** Scoped in, it still lands dead on the crosshair.
  Not scoped in, each shot can wander up to 3 degrees, enough to miss a
  trooper at range.
- **New weapon keys.** 1 pistol, 2 rifle, **3 sniper rifle**, **8 energy
  sword**. Keys 4 to 7 are empty, kept free for guns to come. The weapon wheel
  matches: the sniper is at slot 3 and the sword at slot 8 (up and to the left).
  The mouse wheel and Tab skip the empty slots.

## New version is 1.6.3 (2026-11-04)

- Share builds are now **OpenSpace V1.6.3**. Everything below, down to "New
  version is 1.6.2", is in it.

## Grenades: hold F to aim, let go to throw (issue #372, 2026-11-04)

- **Hold F to aim a grenade.** The view zooms in a little and a dotted arc runs
  from your hand to where it will first land, with a ring on the spot. Look
  around and the arc follows. Let go to throw it along the arc. With no
  grenades, F does nothing.
- **It bounces and bursts.** It falls under the planet's own gravity, bounces
  off the ground and walls (slower each time) and goes off after about 3
  seconds, or at once if it hits a person, a droid or a vehicle.
- **A big blast.** Everyone within 6 m is killed (troopers, locals, natives,
  beasts) and thrown away from the burst. Droids, speeders and the party barge
  are destroyed. It hurts you and your droids too. Hurting locals raises the
  town alarm, as any attack does.
- **Where to get them.** Every gear trader and fence sells them, 40 cr each,
  from day 1 in story and free play, and never runs out. Remnant troopers
  sometimes drop one. The count shows on the HUD under the ammo and is saved.
- **An overarm throw.** Holding F, your right hand winds back behind your
  shoulder with the grenade in it and your left points ahead; your gun is
  tucked away. Letting go swings the arm over the top, and the grenade leaves
  your hand partway through.
- **Your own droids don't set it off.** A grenade that hits one of your droids
  bounces off it instead of going off in your face.
- **Grenades on LAN.** Everyone sees your grenade fly, bounce and go off where
  it went off in your game, and sees your arm wind back and throw. Your game
  says what it hit, as with your bolts. Guards and the town's droids take it
  through the host's game, and the guards hear the bang. Another player in the
  blast takes what you would (60), if friendly fire is on.

## The station's bay: six pads, a frigate and T-99 (issue #316, 2026-11-04)

- **A bigger bay.** It is now 104 m across (it was 76) with a wider mouth, and
  has six landing pads in two rows of three. Your ship comes down on the front
  right one, as before.
- **The station's frigate** stands on the front middle pad: the port's disc
  freighter built twice the size, heavier and slower, with more hull and shield
  and two seeker racks. Walk up and board it like any other ship. It is anyone's
  to fly, story save or not, and is not for sale.
- **T-99, the station's ship salesman,** stands by the tunnel door at the back
  of the bay. He is T-89's brother off the same line, in grey: the same shop
  (buy, sell back, upgrades) at the same prices, with his own hello and his own
  AI card, and no tutorial. A ship you buy from him lands on the back left pad.
- **The frame rate holds.** The frigate and T-99 add no draw calls you can
  measure and at most 85k triangles in view. Two more parked ships would cost
  about 100 draw calls, so the other pads wait for ships that fly in.

## A whole floor of the station is the Remnant's (issue #314, 2026-11-04)

- **The second tower's middle floor is a Remnant deck.** The cruiser's control
  room with the planet map spinning over its holo table, two bunk rooms, two
  armouries with rifle racks, the commander's office and a mess hall. Red
  banners, a stripe and red lamps run down the walkway.
- **A barricade at the tunnel from the favela.** Staggered barriers and a lit
  checkpoint arch, with two troopers on it.
- **About fifteen troopers hold it,** at their posts in the rooms and two
  walking the walkway, and fight like an outpost's.
- **Kill them all and the station is the locals'.** The red is painted over in
  the locals' green, their guards move in, and it stays theirs: it is saved
  with the world, and the locals think better of you for it.

## New version is 1.6.2 (2026-11-04)

- Share builds are now **OpenSpace V1.6.2**. Everything below, down to "New
  version is 1.6.1", is in it.

## The station is full of people (issue #315, part 2, 2026-11-04)

- **About 80 people live aboard.** They walk the walkways, go down the
  favela's alleys and the market aisles to stand at a stall, a booth or a shack
  door, look into the suites and the engine rooms, ride the elevators between
  floors and cross the tunnels to the other tower.
- **They ride the elevators properly.** They wait by the shaft, step on when the
  car stops at their floor with its doors open, ride it, and step off on the
  floor they wanted.
- **Hurt one and the station fights back.** The nearest armed people on your
  floor pull their pistols, up to ten at once, and the station's locals
  remember it like the port's do. Once it is over they go back to walking. The
  dead fall and are back a few minutes later.
- **The frame rate holds.** They are cheap stand-ins until a fight: one walk cycle
  shared by everyone, only the nearest dozen animated each frame, and only those
  on your floor and the ones next to it drawn.

## A second Remnant cruiser by the station (issue #327, 2026-11-04)

- **The belt cruiser.** A second Remnant star cruiser, the same ship as the
  one over the home planet, holds station about 4 km out from the ringed
  giant's space station. You see it through the bay's mouth and from the
  station's windows, and its name is in the sky while you fly.
- **Same visit:** fly toward it and its escort meets you past the edge of
  space, Z docks you on its empty pad, its crew, droids, honour guard and
  general are all aboard, and taking one of its interceptors sounds its alarm.
- **Its bridge's holo table shows the station,** not the home planet: both
  towers floor by floor, the shafts, the tunnels and the bay, the belt of rocks
  round it, and the cruiser where it really is.
- **The pointer:** at the station the objective points at its bay, then at its
  general once you are aboard (also on the F1 screen, which now shows what the
  pointer is on).
- **Taken on its own.** Killing its general pays 15,000 cr and empties it for
  good (saved with the world). The home cruiser, Oda's story, the port's love
  and the dark master are untouched. The dark master only ever waits in the
  home cruiser's bay.

## The gear trader is the market's legit shop (2026-11-04)

- **The gear trader now sells the gun upgrades, the jetpack's long-range tank
  and the sniper rifle,** next to his jetpacks: everything legal, on one stall.
  Same prices, and upgrades already bought stay on.
- **The fence keeps the shady side:** contraband at twice its value, buying
  anything else you carry, the bounties, his jobs and his quantonium armour.
  Ask him for an upgrade and he sends you to the gear trader.
- Same at the ranches, which have both stalls.

## Walk into the barracks: a corridor, the Remnant's office and a bunk room (2026-11-04)

- **The barracks hall has a real front door** off the yard (the middle door; the
  others are locked, with a red light). Inside, a corridor runs the length of
  the hall with locked doors down both sides.
- **The office is the cruiser's control room:** rows of consoles and screens,
  red and blue light, and a holo table with the planet map spinning over it
  (the port marked "here", the outposts in their owners' colours, the cruiser
  in orbit, the moons).
- **A bunk room** beside the way in: two rows of two-high bunks, footlockers and
  lockers.
- **Two Remnant troopers** walk a loop from the corridor into the office and
  round the holo table. They are the town garrison's: they fight back and come
  back like the rest.
- **The rifle moved inside:** in a story save it is hidden in the office's
  middle console. "[E] Search the console" takes it and finishes "Steal a
  rifle". Oda, Skrugs and the quest point you there; the general warns you off,
  and the fence and T-89 know the hall can be walked into.
- **Alarm lights:** red lamps in the corridor, the office, the bunk room and over
  the door pulse while the town alarm sounds and go dark on calm.
- **Every barracks:** the square port, the round port and any generated town big
  enough to have one. The roof riflemen and the bridge to the bunk tower are as
  before.

## The station's floors are furnished (issue #315, part 1, 2026-11-04)

- **Two market floors.** Rings of market stalls round the walkway, with
  canopies and wares, and an outer ring packed with shacks and booths. Lanes
  stay clear to every tunnel door.
- **The lower homes are a favela.** The main tower's homes floor is packed from
  the walkway to the glass with shacks, booths and huts, back to back along
  narrow alleys. A third of the shacks have another built on top, with a
  ladder up. Cables with bulbs and washing lines cross the alleys.
- **The upper homes are luxury suites.** The second tower's top floor has 8 big
  suites dressed like the cantina's club and the party barge: wood panelling
  with gold, neon, a bar with lit bottles, an aquarium, velvet booths under
  chandeliers, a light-up dance floor, a piano, and a round bed under a gold
  canopy by the window.
- **The engine deck.** Two reactors glowing blue, two cargo holds stacked with
  containers and crates (one has a sealed drop hatch in its floor), two pump
  rooms and two workshops, with pipes round the walkway's ceiling.
- **The frame rate holds.** A floor is drawn as a few dozen meshes, only while
  you are on it or the floor just above or below. It is built a little each
  frame while you arrive, so nothing stutters. No new lights or shadows.
- Nobody lives there yet: the crowd, the shopkeepers and the workers come next.
  The top floor and the outpost floor are still empty. The station's homes
  studios (a lounge, kitchen and bedroom in a long room) are still in the code
  for any floor's config to use.

## Heists: hold the control room for a minute (2026-11-04)

- **Hacking a console takes a minute now.** Hold [E] for 5 seconds to start
  it, then stay within 25 m of the console for 60 seconds. You can leave the
  console and fight from the room or the doorway. Go further than 25 m and
  the hack drops, so you have to start it again. The stash drops when the
  minute is up.
- **The outpost sends a wave at you** when the hack starts: four soldiers
  50 m out on the door's side, running in to kill you, and the outpost's
  alarm goes up. Remnant outposts send barracks troopers, and the locals'
  outposts send their guards. One wave per heist. They don't come back
  when killed.
- The prompt and the bar show the time left.

## A laser droid of your own (2026-11-04)

- **A droid merchant in the moon rave,** at a stall of their own by the stage.
  They sell floating droids and the **laser rig** (300 cr) for any floating
  droid you own. The rig is sold only there.
- **A floating droid with the rig wears the rave droid's colours,** black with
  magenta trim and eye and a neon ring round its belly, and carries a fan of
  lasers under it, the same fan as the stage's laser droid.
- **E next to it turns the lasers on or off,** anywhere: the moon, the desert,
  the port cantina, the barge. The prompt says which, and on or off is saved
  with the droid. A new rig starts off.
- **It fights like any floating droid.** The lasers keep sweeping while it
  shoots, go dark when it is knocked out and come back when it reboots.
- The price, the beams and the colours are in `content/core/droids/droids.json`
  ("upgrades" "lasers", "club_vendor").

## The moon rave: a long bar, a lounge and stalls (2026-11-04)

- **The bar is across the dance floor from the stage** now, a 12 m counter
  under a lit canopy with lamps that cycle through the colours, a back bar of
  bottles behind Oda and stools all along it.
- **Armed patrons stand round the bar**, scattered along it, bottle in hand,
  and fight back with the whole rave if you hurt one.
- **A lounge round the bar:** the port club's leather booths in black and purple
  with a neon line along the back, and high cocktail tables with a neon ring and
  a glow under each top. Patrons stand round them in twos and threes.
- **They talk as you pass:** walk close by a patron and one says a short line
  about the party, the DJ or the drinks, one line every so often for the room.
- **The fence's stall is on the way from the hallway to the bar.** He still buys
  contraband, and now sells jetpacks at the gear trader's price; his counter
  shows gear.
- **Four rave stalls round the edge of the room,** a merchant at each and
  nothing to buy: bead strands, glow sticks, band shirts on a rail, jars and
  vials, snack bowls and little neon signs, two kinds a stall, each different
  from the last, under a neon frame.
- **The rave mix plays everywhere on the station:** the dome, the hallway and
  the landing pit, and never the ambient or battle music. Kill the DJ and the
  station goes quiet until your next visit.
- The lava moon's station is the same rave and gets all of it too.
- Positions, sizes and counts are in `content/core/planets/town_kit.json`
  ("club_dome"); the lines in `content/core/dialogue/locals_lines.json`
  ("club_talk").

## Hijacking ships and speeders (2026-11-04)

- **E by a ship or speeder someone else is in takes it.** Walk up (or ride up on
  your own speeder) to one being flown or ridden and the prompt says
  "[E] Hijack". You hop up onto it for about a second, the pilot is thrown out
  onto the ground beside it, a little hurt, and you are at the controls.
- **Works between players over LAN,** host or guest either way: their game
  throws them out, yours puts you in their ship (on the pad, or flying on where
  it was), and everyone else sees it change hands. A jetpack gets you onto a
  ship hovering low.
- **It is still theirs.** Get out, eject or get off and it is back in their game
  where you left it, on the ground below. Crash it and it is wrecked for them
  too (their own ship waits for T-89's patch-up). Their Call says someone else
  is flying her until then.
- **Other players' speeders now show over LAN** while they ride them, with
  their name over them (before, a rider just vanished).
- **The Remnant interceptor can be taken in the air** when it comes low enough
  to reach (setting down on its pad): its pilot is thrown clear and it is a
  stolen ship, alarm and all.
- Numbers (reach, hop time, the pilot's knock) are in
  `content/core/flow/hijack.json`.

## Take the lava moon: the same domes, barracks and outposts (2026-11-04)

- **The lava moon gets the moon's expansion:** two more tunnels out of its
  landing bay, to a barracks dome and a homes dome, and five Remnant outposts out
  among the lava, 500 to 560 m from the station.
- **Taken on its own,** on the moon's rules: kill the troopers at an outpost and
  the locals move in; hold all five and the Remnant are driven off the lava
  moon, barracks and all. The port and the moon are not touched by it, and the
  other way round. F1 and the lava moon's map show it.
- **The outposts stand on raised basalt pads,** 1.5 m over the lava and wide
  enough for the ship and the patrol, so nobody is standing in it.
- **No lava within 180 m of the port** (was 130), so the new domes and tunnels
  sit on dry rock.
- Fronts past the port's are a list in `territory.json` ("fronts"): the next
  planet to take is a block of data.

## Take the moon: two more domes, a barracks and five outposts (2026-11-04)

- **Two more tunnels out of the moon's landing bay,** north and south, each down
  its own ramp and through its own shields to a dome as big as the first.
- **The barracks dome:** the Remnant's metal barracks (the gray homes' metal,
  its band turns green for the locals), crates in the yard and five troopers.
  It changes hands like the port's barracks: the locals take it when the fleet
  is beaten or when the Remnant are driven off the moon; kill every local guard
  there and the Remnant take it back; once the fleet is beaten, kill every
  trooper there and it is the locals' again. Dead troopers come back behind the
  hall until then.
- **The homes dome:** eight of the station's gray homes either side of a street,
  locals walking it.
- **Five Remnant outposts out on the moon's rock.** Kill every trooper at one and
  the locals move in, like the port's. No quest and no supply runs: they keep it
  until their guards there are all dead. Hold all five at once and the Remnant
  are driven off the moon, barracks and all. Once the cruiser has fallen the
  moon's Remnant outposts run short and give up one at a time, like the port's.
  F1 lists the moon's places too.
- **The landing bay's rim is 3 m lower** (10 m, was 13).
- **No more breathing on the roof.** Out of air now means outside the glass,
  not just outside its circle: standing on a dome, on a tunnel's roof or above
  the bay's shield hurts without armour.
- **The moon's map** shows the station's shape (the domes, the bay and the
  tunnels), a pin for the bay, the barracks (who holds it) and the homes, and
  the five outposts, green when the locals hold them.
## Ranch villages: three walled outposts with houses and stands, far out (2026-11-04)

- **Three ranch villages out in the desert,** each a Remnant outpost with a
  few houses round it (one of them a tall tower house), a walled yard and a
  gate facing the port. Two are far out on the side away from the wreck field
  (Saltpan and Windbreak, 3.5 to 3.8 km); the third, Hullside, sits out east
  between the second and third wrecks.
- **Four stands at each:** the gear trader, the food stall, the fence and a
  droid merchant. They are the port's own merchants, with the same stock and
  prices. No speeders. A stand shuts while its keeper is dead or the village
  is fighting you.
- **Armed locals hang about** the fire and the gate. They have their own
  alarm, so a fight out there never reaches the port.
- **They count toward driving the Remnant off.** The Remnant only hand a
  village over once the cruiser has fallen. Before that, killing every trooper
  there just brings more ("they answer to the cruiser"). The same rule as the
  barracks: the cruiser first, then its guards.
- **The map says "Village"** for each, in the outposts' colours (green once the
  locals hold it).
- **Nothing of them is drawn from the port.** Everything at a village is drawn
  only within 1500 m, and they are 3.5 km and more out, below the horizon.
## Armour at the moon stalls from day 1 (2026-11-04)

- **The merchant in front of the moon's cantina sells quantonium armour** from the
  start, in a story save and in free play, for 500 (the port's fence price) and
  never runs out. It is what lets you breathe out on the rock.
- **The lava moon's merchant too:** it had no stall at all; now it is the moon's,
  armour included.

## The ringed giant: gas you can see, fog under the station, air you can breathe (2026-11-04)

- **The giant looks like gas from far off:** a soft glowing edge of haze all
  round it, bands that bend and drift, and heaps of cloud as you get closer. The
  far side is dusky purple, not black.
- **Up close the ground is fog.** From the station you look down into a sea of
  haze with no hard horizon; dive toward the clouds and you fly into thick fog
  (the deadly line is inside it).
- **Go outside the station without armour:** the air is breathable. Walk out of
  the bay's mouth through its shield and roam outside on the jetpack. Drop too
  far toward the clouds and the station pulls you back into the bay.

## Jetpacks at the gear trader, and stash one or all in a cargo droid (2026-11-04)

- **The gear trader sells jetpacks** and never runs out, at the jetpack's value
  (120 cr). It still buys them back at half that.
- **A cargo droid's hold stashes one at a time:** Enter stashes one of a stack,
  **Shift+Enter** stashes the whole stack, and each row has **Stash one** and
  **Stash all** buttons you can click. The hold stays open after each stash.

## Step out of the station between its floors (2026-11-04)

- **The glass round each elevator gap between floors is a shield now.** It keeps
  the air in and lets you through. Jump the railing onto the gap's glass,
  jetpack up through the hole in the ceiling, step out through the shield, and
  you are outside on the roof of the floor below, under the next floor, out in
  space.
- **You stay out there.** The station only pulls you back in if you go off the
  roof's edge, as on the tunnels' roof walks.

## New version is 1.6.1 (2026-11-04)

- Share builds are now **OpenSpace V1.6.1**. Everything below, down to "New
  version is 1.5", is in it.

## The ringed giant: a real gas planet with the station as its town (2026-11-03)

- **The ringed giant in the port's sky is real now,** in the same spot and about
  the same size as the old painting, which is gone. It is smaller than it looked,
  so the flight out is a couple of minutes.
- **A real ball of gas you fly all the way round,** handed over to its own
  scene with no fade, like Grit Station. Its ring is drawn too (a look, not solid).
- **The clouds kill you.** Nothing holds a ship up in them: go down into them
  and the ship is lost, at any speed.
- **The space station is its town.** The station from the moon now hangs over
  the top of the giant; Z docks you in its round bay, and a save loaded on the
  giant starts you there, by your ship on the dock pad. No deck, no cantina yet.
- **A new planet type, `gas_ball`,** so the next gas giant is a config file.

## LAN: friends' ships boxed like enemies, and players in ships on the map (2026-11-03)

- **Another player's ship in flight gets the enemy box on your flight HUD:** the
  red box, their hull under it, the range, the lead pip, and the arrow at the
  edge of the screen when they are off it. In the town's sky and out in space.
  No lock ring, since seekers never lock on a friend. Only while friendly fire
  is on and they are off the ground.
- **The F11 map shows the other players in their ships too,** not only on foot:
  the blue dot sits on the ground straight under their ship, in the air or up
  in space, and it works whoever is flying. Click it and the waypoint follows
  their ship.
## A space station behind the moon (2026-11-03)

- **A station hangs over the moon's far side,** out of sight of the port. Fly
  to the moon, round it, and its name shows in the sky; Z flies you into its
  bay, the same way Z docks you on the cruiser.
- **Two towers of tall round floors,** the top floor the biggest, with open
  space between floors. Each floor has a walkway round a glass-floored middle
  (you look down the glass tube through every floor below), rooms with big
  windows round the outside, and markets on the open floors.
- **An elevator up the middle of each tower** in a glass tube. Stand on it and
  it carries you floor to floor; stand by its shaft and it comes to you. Its
  doors open only where it has stopped.
- **Glass tunnels join the towers** on the three floors they share. Each has a
  shield hatch in its roof: jetpack up through it and walk the roof outside,
  like a bridge.
- **A round landing bay** at the end of its own tunnel, its mouth closed by a
  curved shield you fly through.
- **The floors are empty for now.** The cantina, homes, markets, garrison and
  crowd come with #314 to #316.
- It is a component: one config file and one landmark block. Move the block to
  another planet and the station goes with it.

## Story: a heist before the bounty (2026-11-03)

- **After the cargo droids, Oda sends you on a heist** before she gives you the
  bounty: the control room at the broken ridge outpost, with one of her people
  and an assassin droid. Bring the flasks to the fence and the bounty comes next.
- **She keeps her promise straight away:** the energy blade on the cantina tower
  is in the heist's telling now, not the bounty's.
- **Nothing forces the outpost to change hands.** Kill every trooper there and
  the locals take it as usual; sneak in and it stays the Remnant's. Either way
  the story goes on.
- Skipping past the chapter counts a heist as paid and gives its pay. Saves
  already at the bounty or later carry on as they were.

## Heists on the board (2026-11-03)

- **Oda, the fence, Skrugs and T-89 offer a heist** on a Remnant outpost's
  control room: the job names the outpost, who goes with you and the pay.
  Hack the console, carry the 15 flasks home and the fence pays, less your
  crew's cut (20%). The quest log and the waypoint follow each step.
- **In free roam the general stands in the barracks yard** and offers his own
  heist on an outpost the locals hold, as long as the Remnant don't hate you.
  He pays half as much again as the fence, and the Remnant like it.
- **A crew member and an assassin droid go with you.** They follow, keep quiet
  while you sneak, and only shoot whoever is fighting you. You can talk to the
  crew member. If they go down the heist goes on without them; when it ends
  they walk off and the droid goes home.
- **One heist at a time, for ever.** It ends when you are paid, when you are
  downed, when you call it off (the fence's or the general's menu), or when the
  flasks are gone. A heist never decides who holds the outpost.

## Walk into the outposts' control rooms (2026-11-03)

- **Every Remnant outpost has an open doorway on the town side,** into a small
  control room like the star cruiser's bridge: rows of consoles under screens,
  a holo table with its map glowing over it, red and blue light. Ships and
  speeders still hit the building; the footprint is the same.
- **One trooper now stands inside,** at the consoles with his back to the door
  (the locals post one there too when they hold it). Troopers walk in and out
  after you.
- **The console at the back can be hacked:** hold [E] for 5 seconds, a bar
  fills, and a stash of 15 flasks of refined quantonium drops at your feet.
  Let go or step away and it starts over. Being seen raises the alarm as usual;
  the hack keeps going. For now it is locked: heists (coming next) open it.
- **The sand under each outpost is levelled,** so the floor is flat and nothing
  pokes through it.
- **The inside only draws within 50 m,** so the rooms cost nothing from afar.

## Your speeder waits outside the back gate when you respawn (2026-11-03)

- **Wake up after being downed and your speeder is in a row outside the back
  gate,** on the sand by the wall, nose to the desert, wherever you left it.
  Loading a save puts it there too. Nothing else brings it back: left out in
  the desert, it stays there until you respawn.
- **Every LAN player has their own spot in the row** (five, one each): the host
  or a lone player the first, each guest the next by when they joined.
- **A new speeder still waits in Skrugs's garage.**
- **A destroyed speeder is gone for good,** respawn or not, and Skrugs sells
  you another at full price (checked).

## LAN: friendly fire for ships, no seeker lock on friends (2026-11-03)

- **Your ship's cannons hit your friends' ships.** Before, another player's
  ship was a picture: bolts flew through it. Now, while they fly it, a hit
  lands on their ship in their game (shield first, then hull) and enough of
  them shoot it down, as any gun would, in the town's sky and out in space.
  You get the usual hit marker, red for the one that brings it down.
- **Seekers never lock on a friend's ship.** An unlocked seeker fired
  straight into one still hits it, blast and all.
- **A parked ship is still a picture.** Nobody can wreck a friend's ship on
  its pad.
- **You see your friends' cannon fire and unlocked seekers in the sky.**
  Before, their shots only showed in a space fight.
- Off with the same switch as friendly fire on foot (`friendly_fire` in
  `content/core/flow/lan.json`), scaled by `friendly_fire_scale`.

## New version is 1.5 (2026-11-03)

- Share builds are now **OpenSpace V1.5**. Everything below, down to "New
  version is 1.4", is in it.

## LAN: you can find each other (2026-11-03)

- **The other players were there, just hard to find.** A guest arrives by a
  pad down in the pit, often 80 m or more from the host, and the name over
  their head was a few centimetres of text the colour of an NPC's speech: past
  a few metres you could not tell a player from a townsperson.
- **Their name is the same size on screen at any distance.**
- **On the F11 map** each other player on foot is a blue dot with their name.
  Click one and they are your waypoint: the HUD's pointer follows them with a
  blue diamond (the line stays white), and clears when you reach them or they
  leave the game.
- Tunable in `content/core/flow/lan.json` (`name_px`, `mark_color`,
  `waypoint_arrive_m`).

## LAN: falls, wake-ups and the red sword show to the others (2026-11-03)

- **A downed player falls as a ragdoll on every screen,** pushed away from the
  hit that put them down, as their own body does in their game. Before, the
  others saw them standing still.
- **When they wake, the body on the ground goes.** It is gone from where it
  fell and they stand up where they woke (the pit, wherever).
- **The red saber is red to the others too,** on its black hilt. Before, every
  other player's sword showed blue.

## The wreck field is cheaper to look at (2026-11-03)

- **The four crashed cruisers look the same and cost far less to draw.** Their
  2,561 hull plates were drawn one by one, from anywhere the field can be seen;
  they are now 56 meshes, one per wreck and finish. Looking east from the port
  that is about 2,700 fewer draw calls a frame (about 5 ms on a Mac).

## One speeder each: the town is smooth again (2026-11-03)

- **Skrugs sells one speeder to a customer.** Once you own one he says so, and
  points you to his bench for parts instead. A save with more keeps its first
  speeder, paint and parts and all; the rest are gone.
- **Why:** every parked speeder ran its hover each physics tick, standing still
  or not. A free roam save with seven of them parked at his yard took the town
  down to 7.5 fps (each tick took 22 ms, over its 16 ms budget, so the game ran
  several a frame). With one a tick takes 10 ms: 61-88 fps in most directions
  with full graphics.

## Blaster pops are sparks, not grit (2026-11-03)

- **A blaster bolt landing is a clean pop now:** the flash and the spray of
  sparks as before, a smaller lick of fire, and no bits of casing flying out.
  Droids going pop still throw bits and a wisp of smoke.

## Maps of the moon and the Remnant cruiser (2026-11-03)

- **Click the moon or the cruiser on the Map page (M) to open its own map.**
  A button takes you back to your planet's map.
- **The moon's map is its real ball,** craters and all, the same as the ground
  you land on. Click anywhere on it to set a waypoint there: until you land,
  the pointer leads you to the moon, then to the spot.
- **The cruiser's map is a cutaway of the real ship** seen from the side: the
  landing bay, the armoury, the crew room, the stairs up and the bridge on top.
  Click a room to set a waypoint to it.

## Half the barge crowd is unarmed; the guards wear navy (2026-11-02)

- **Only half the party barge's dancers carry a pistol.** Hurt anyone on
  board and every other dancer draws and fights, as before; the rest have no
  gun and keep dancing through the fight. They can still be shot and cut
  down (`armed_share` in `content/core/barges/party_barge.json`).
- **The barge's two guards wear the navy guard armour.** Gunmetal plate with
  blue trim, a navy cloth and a pale blue visor (`barge_guard` in
  `content/look/characters.json`), so they read as the boss's own men, not
  the locals' guards. Still killable, rifles up as before.

## The barge boss is a squid in a tank (2026-11-02)

- **The party barge's boss is the barge duke now.** A fat squid-cyborg: a
  potbelly-stove robot body in dark metal with very small hands, and a glass
  tank of glowing yellow liquid for a head, a little squid wired up inside.
  He is the player's height (the old boss was a stretched, warty Oda), and
  bolts find him in a capsule his size. One Hyper3D model, rigged, worn like
  the smuggler's (`barge_duke` in `content/look/characters.json`).
- **You can see the squid from every side.** The generated tank was a solid
  ball with the squid painted on, so it looked empty side-on. It is cut off
  and rebuilt: a separate squid model floats in clear, faintly glowing yellow
  liquid inside a glass shell, all moving with his head.
- **He stands in front of his lounger, not in it.** The seat moved back
  against its backrest.

## The map shows the real desert (2026-11-02)

- **The globe on the Map page (M) shows the ground faintly under its lines.**
  The dune fields, the mesas and (on the asteroid) the craters are drawn where
  they really are, from the same heights you walk on, lit softly from the top
  left. Zoomed right in, only a faint tint of high and low ground is left.

## The locals at Oda's bar are real people (2026-11-02)

- **The three locals on the bar stools are solid and fight back.** You can no
  longer walk through them, they can be shot and cut down, and hurting one
  turns the whole cantina (and the town) on you, like the club crowd. They are
  live `local_patron`s now, with a drink in hand. Both port layouts, and every
  other planet's cantina (`src/systems/planets/town_gen.gd`).

## Rifle held properly (2026-11-02)

- **The rifle's hands sit where they should.** The right hand wraps the outside
  of the pistol grip instead of sinking into it, and the left hand holds further
  forward, off the magazine and onto the front of the gun. Same for the player in
  first and third person and for the Remnant troopers.

## Skrugs's yard: real lamps on the clock, and a workbench (2026-11-02)

- **Skrugs's garage has a work light, his house door a lamp,** a lamp over his bench, and with the
  lamp over his counter all four are real lights on the look's lamp clock: on by day,
  full at dusk and night. The string bulbs and a new teal sign over the garage
  mouth brighten with them (issue #458, `src/systems/world/speeder_post.gd`).
- **His bench is a workbench** like Dorrin's: a vise, a pegboard of tools behind
  it, his toolbox and coil still on top. Both town layouts.
- **Dorrin's counter hangs the same lamp**, a real light now, and his bulbs and
  garage sign follow the clock too. The lamp is `HangingLamp`
  (`src/systems/look/hanging_lamp.gd`), for any outpost dressing.
## No freeze on the first blaster shot (2026-11-02)

- **The first shot no longer stops the game for a few seconds.** The bolt, the
  muzzle flash, the explosions and their sounds now load in small pieces over
  the first frames of the game, before anyone fires.

## Chill 80s synth score, and a second battle track for long fights (2026-11-02)

- **The background music is laid-back 80s synth now.** Eleven new tracks, picked
  to sound like the owner's two favourites (slow, soft beat, long pads, no
  vocals), replace the five that were too cinematic. Fourteen in the shuffle.
- **Long fights get a second battle track.** When the battle music runs out and
  people are still shooting at you, a second track takes over and lasts the whole
  fight, which suits the climb up the cruiser.
- **The cruiser's music ends at the top** when the general dies, and **starts
  again when the dark master attacks you**. His sword fight has battle music now.

## New version is 1.4 (2026-11-02)

- Share builds are now **OpenSpace V1.4**. Everything below, down to "New
  version is 1.3", is in it.

## Scripted lines are voiced without an ElevenLabs key (2026-11-01)

- **Non-AI lines now play recorded voices from the repo.** Every fixed line
  (card greetings and canned replies, story beats, T-89, the general, the dark
  master, guard and locals barks, the speeder shops) has a slot in
  `assets/audio/voice/`, one clip per voice that can say it. `NpcVoice` plays the
  bundled clip first, with or without a key; lines with a runtime fill (prices,
  names) still go through the API.
- **All 808 clips are in** (22 MB): 125 copied free from the game's play cache,
  683 recorded on ElevenLabs' quick Flash model. A new fixed line gets its voice
  from `python3 tools/audio/make_voice_lines.py`, which records only what is missing.
- **T-89 speaks as the retro robot**, every line of him re-recorded in it.

## Bug fix: T-89's tutorial card shows its text again (2026-11-01)

- **Saying yes to T-89's tutorial now shows the page.** The card measured its
  height before its text had wrapped to the card's width, so it came out almost
  3,000 px tall with the text above the top of the screen: an empty dark panel
  down the left side. It now re-fits whenever its content's size changes, and
  settles at the page's own height a frame after it opens (`src/ui/tutorial_card.gd`).

## The locals run checkpoints like the Remnant did (2026-11-01)

- **Wherever the locals hold, their guards stop you like the Remnant's did.** That
  means the front gate and the barracks yard when they hold the barracks, and the
  ring round any outpost they hold. Same places, same rules: waved through at 40 and
  up, papers below that, papers and a search in poor standing, bribes, contraband
  and warnings. It reads and moves your standing with the locals, not the Remnant.
  In poor enough standing (-40 and below) they warn you by day and then open fire.
- A fight at the barracks brings the town's locals in, and shooting a local in town
  brings the barracks guards in. Each outpost's fight is its own, as with the Remnant.
- The gate barks no longer name the Remnant ("Remnant property now" is gone), so
  both sides use the same lines.
- New profile `content/core/soldiers/local_gate_guard.json`; the locals' guards take
  the Remnant gate guard's checkpoint block (`checkpoint_of`). Tests in
  `tests/test_locals_gate.gut.gd`.

## New version is 1.3 (2026-11-01)

- Share builds are now **OpenSpace V1.3** (`OpenSpace V1.3.app`, `OpenSpace V1.3.exe`).
  Everything below is in it. The version is `config/version` in `project.godot`;
  `.claude/skills/build-share-files` says how to build and name the next one.

## Settings: the controls list shows every control (2026-11-01)

- **F11 > Options > Controls now lists all the controls**, in four groups: on foot,
  weapons, flying, and the keys that work everywhere. It used to show eleven; the
  walking, jetpack, gear, rest, weapon, flight, radio, missile, target, land and
  eject keys were missing.
## G wears the armour too, and new gear tells you the key (2026-11-01)

- **[G] now puts on and takes off the quantonium armour as well as the jetpack.**
  With only one of them it just toggles it. With both it opens a small menu:
  "Put on" or "Take off" for each, Enter to pick, Esc to walk away.
- **New equipment says how to wear it.** Buying the armour from the fence (or taking
  any jetpack or armour that does not go on by itself) toasts "New equipment: ...
  Press [G] to put it on".
- **A new weapon says how to change weapons.** Picking up or buying a gun or a
  sword follows its toast with "Press [Tab] to change weapons - press & hold to see
  all weapons".
- Words are in `content/core/flow/gear.json`; tests in `tests/test_gear_g.gut.gd`.

## Bug fix: the lookout's jetpack and blade sit on the floor, not in the middle (2026-11-01)

- **In a story save the jetpack and the energy blade now lie on the cantina
  lookout's floor on the pit side**: the jetpack 2 m from the middle toward the pit,
  the blade a metre beside it. The blade used to sit in the middle, where the
  stairwell and its column are. Same ids, flags and rings as before
  (`content/core/pickups/port_town.json`).
## T-89's tutorial: walk the pit while it runs (2026-11-01)

- **The tutorial no longer freezes you.** Each page is a small card on the left of
  the screen instead of a big menu in the middle, so you can walk, jump, aim and
  try what it says while you read. Enter turns the page (the last one finishes it),
  Backspace skips the rest.
- **Leaving the pit ends it.** Up a ramp or over the rim and T-89 calls "off you
  go": the card goes away. Opening his menu (E), a talk, a ship or the general's
  meeting also ends it. The pit is the sunken floor under his marker; a town
  without one lets go 32 m from him (`tutorial_leash` in `content/core/npcs/t89.json`).
- **W works in the pick lists again.** In every menu (T-89, the fence, droid
  merchants) only the Up arrow went up: a layout constant named `KEY_W` hid the W
  key inside the menu. W and S now both move the cursor.

## Standing toast: every change in faction standing shows (2026-11-01)

- **When your standing with a faction moves, a small panel comes up high on the
  screen, under the top banner**: "Remnant standing +10", the change green for up and red for
  down, over a gauge from -100 to +100 with a tick every 25. A finer tick, in the
  change's colour, is drawn for every point it moved as the marker sweeps from
  where you were to where you are. A fight that moves both the Remnant and the
  locals shows two panels side by side, and a second change to one that is still up adds to it.
- Only the Remnant and the locals: the smugglers' standing never shows.
  Only faction standing. What one character thinks of you (Oda's trust) is not
  shown. Setting standing in the dev panel or loading a save is not news either.

## The Remnant love you when you clear the locals for the dark master (2026-11-01)

- **On the dark master's oath, clearing the barracks' local guards now takes your
  Remnant standing to 100.** It was 25 from joining, and an armed player who had
  just fired still read as hostile, so the troopers coming back to their posts shot
  on sight. At 100 they wave you through. Number: `standing.retaken` in
  `content/core/npcs/dark_master.json`.

## The dark master: blade on his hip until he fights, and his talk works with AI on (2026-11-01)

- **His red blade hangs dark on his left hip while he is at ease**, in story and
  free roam alike: in the cruiser's bay while he makes his offer, and on the
  barracks roof while you are sworn to him. The moment he is hostile and the fight
  is on he draws it, the hilt swinging to his fist and the blade igniting as his
  guard comes up (0.4 s), and he hangs it up again if he gives up on you (you are
  down, or gone past his give-up distance). Built mid-fight (free roam, or back
  after you refused him) it is already out.
- **His offer talk no longer locks the box with AI characters on.** His talk spot
  joined the host's list by hand instead of through `add_spot`, so his brain never
  got the AI service (every answer was a written line) and the host never heard his
  reply: after your first typed line the box stayed locked, and Esc only repeated
  "is not finished with you". He now registers as the general does.
## Map: places the locals hold turn green (2026-11-01)

- **On the F11 Map, an outpost the locals have taken is green**, and the port goes
  green once the locals hold the barracks (the fleet beaten, or the Remnant driven
  off). It turns back to its Remnant colour when they take it back.
- **A ring round each outpost the locals hold drains as their hold runs down.**
  Once their supplies run short the pin turns yellow-green and "Resupply needed"
  shows under it.
- **The Remnant take outposts back five times slower**: the locals hold one for
  about 100 minutes of play (was 20), and run short with about 40 left. A lazy
  round of the desert still saves most of them.
- **The cruiser's holo table shows who holds what (issue #325).** The port's pin
  is coloured by who holds the barracks, and each of the seven outposts has a
  pin: Remnant red, locals green, yellow-green when the locals run short. They
  change colour while you watch, and an outpost that changes hands flashes.
- **Resupplying is an optional quest.** When an outpost runs short, "Resupply the
  ... outpost" turns up in the Ledger, pointed at the outpost. It is done when Oda's
  supplies get there, fails if the Remnant take it back first, and comes round
  again the next time that outpost runs short. With a quest's waypoint on, Oda's
  supply job goes to that outpost instead of the one shortest on time.
- **Hover (or a waypoint on) a held place** and its tag says who holds it and how
  long the hold has left. The legend has two new lines for the colours.
- Colours are in `content/look/map.json` (`owners`), the lines in
  `content/core/flow/map.json`. The pins read Territory each time the page opens.

## Settings: set up an AI brain with a link or a prompt (2026-11-01)

- **Ollama, the local server (llama.cpp) and the cloud each get two buttons** beside
  their model in the AI settings (F10): **Link** opens the download page
  (ollama.com, the llama.cpp project, platform.claude.com), and **Prompt** copies a
  detailed set-up prompt for a coding agent. The button says "Copied" and the
  settings say "Prompt copied; give it to your agent", with a reminder to run the
  agent with access to the internet and your computer, in a trusted folder.
- Each prompt asks the agent only to get the server running (or, for the cloud,
  to walk you through making a key yourself) and to hand back the URL and model
  name to paste in, with examples of what is allowed. It picks a model by this
  machine's memory, and tests the server with the same kind of streamed JSON
  request the game sends, against the game's first-word time limit. Text is in
  `content/core/llm/setup_help.json`.
- **A Local or Ollama URL on another port now works.** Its health check and the
  local server's port follow the URL you type, so a server on, say, port 8080 is
  no longer reported down.
## Story mode: the jetpack is on top of the cantina tower (2026-11-01)

- **In a story save the jetpack lies on the cantina tower's lookout floor**,
  beside the energy blade, with the usual glowing ring. Take the stairs up.
  Oda's tip in the first smuggling run, her reminder and her briefing now send
  you there, and a new rumor does too.
- **The pit's old cargo droid roams empty in story mode.** In free play the
  jetpack is still inside it, and its rumor only plays there.
- A story save that already took the jetpack from the droid keeps it: it is
  the same pickup, moved (`modes` in `content/core/pickups/port_town.json`).

## The general's pit meeting opens as you climb out (2026-11-01)

- **Story mode: General Vask's talk opens the moment you step out of your
  ship**, wherever you stand. Before, it only opened within 9 m of him, and
  the ship's exit spot is about 14 m away, so nothing happened until you
  walked over.
- **The meeting lasts at most four of his lines.** If he gives no verdict (the
  model calls neither let_go nor search), or no model answers (AI characters
  off), his guards search you after the fourth. It was three lines with the AI
  on and two with it off.
- **Then he leaves.** He, his guard and his droid walk out of the pit to the
  barracks on the town's navmesh in single file, instead of vanishing on the
  spot. There's no cut: you stay where you stood and the time of day doesn't
  change. Settings are under `meeting.leave` in content/core/npcs/general.json.
- Test: tests/test_plot_buildout.gut.gd (opens from 16 m, four lines then
  the search, the walk out with you and the time of day unchanged).
## Ships and speeders share an explosion sound (2026-11-01)

- **Every ship and speeder that blows up now makes the same boom**, picked
  at random from four real explosion recordings ("explosions 4" by
  EZduzziteh, CC0 from OpenGameArt.org, nothing to license or credit). The
  speeder used to go up in silence, and so did your own ship when it
  crashed or was shot down; the Remnant fighters, dogfight kills, parked
  ships, the party barge and seekers swap the old synthesized boom for the
  new set. One key, `vehicle_boom` in `content/look/sound.json`; the old
  `ship_boom.wav` is kept for the droid pop.
- Test: tests/test_sound.gut.gd (vehicles share an explosion).
## A story save and a free roam save, side by side (2026-11-01)

- **Both games are kept.** F11 > Game > Saves lists the story save and the
  free roam save; Play on the other one saves this game and opens that one where
  you left it (or starts it, if you have none yet). The last one played opens
  next launch.
- **Nothing leaks between them.** Each has its own world, gear, ships, standing,
  names and outfit. Starting a new game resets only its own save. Switching
  clears the free roam tweaks, the planet you were on and T-89's hello, as a
  fresh launch would.
- **Your old save moves over by itself.** The first launch copies `save.json`
  into the slot its mode says, and leaves the original where it was.
- Test: tests/test_save_slots.gut.gd.

## More ambient music (2026-11-01)

- **The ambient score has eight tracks now, not three.** Five calm, spacey
  pieces join the shuffle: Galactic Temple, Starfield Romance, The Budding of
  Consciousness, Calm Ambient 1 (Synthwave 4k) and Contemplation. All are CC0
  from OpenGameArt.org, so there is nothing to license or credit. Each
  file's source page is listed in `content/look/sound.json`
  (`music.ambient_sources`).

## The music fades back in after a fight (2026-11-01)

- **When a fight ends, the next ambient track fades in** over the usual 4 s,
  blending with the battle track as it fades out. Before, it cut over in a
  quarter of a second, the same as going into a fight. The battle music
  still cuts in at once when the shooting starts (issue #80).
- Test: tests/test_sound.gut.gd (battle cuts in, ambient fades back).

## Every ship has a seeker rack (2026-11-01)

- **Every spaceship now carries a secondary weapon**, and for now that is
  the seeker rack (four seekers, one back every 1.5 s). The Lanner courier,
  the Frigatebird freighter, the Remnant's dark Frigatebird and the Remnant
  fighter get one under the nose; the Kestrel, the Albatross and the
  Remnant's Kestrel and heavy fighter already had one. T-89's stats for the
  courier and the freighter now read "... and a seeker rack".
- AI pilots still only fire seekers when their pilot profile says so
  (`missile_use`), so rookie Remnant fighters carry the rack without using it.
- Test: tests/test_ship_combat.gut.gd (every ship has a secondary, the seeker).

## T-89's menu, tidied (2026-11-01)

- **[E] by T-89 is a short menu now**: Talk, "Buy or sell a ship", "Upgrade
  your ships" and "Run me through the basics again". Each shop is its own
  submenu, so the ships and the ship-by-ship upgrades are no longer one long
  list. Buying, selling or fitting keeps you in that submenu with the new
  prices; Back returns to his menu, Esc walks away. Upgrades show up once you
  own a ship, with what each one already carries. While your wreck waits, the
  rebuild and the Remnant talk stay on his top menu.
- **"Tell him what you think of the Remnant" is a real conversation**, with
  AI characters off too. T-89 tells his story (the green planet he remembers,
  the bombing, a hundred years of the Hegemony) a page at a time ("Get to the
  point" skips it), says he has always hated the Remnant, and asks what you
  think. "Down with the Tyrants!" makes you his comrade: the 1-credit rebuild.
  Side with the Remnant and there's no discount; he tells you to buy a ship
  or leave him be. The row stays on his menu, so you can try again.
- Tests: tests/test_ship_salesman.gut.gd (the menu and both submenus),
  tests/test_ship_rebuild.gut.gd (both answers, and asking again).

## The Ledger, a live map, and text you can read (2026-11-01)

- **Inventory is now the Ledger** (F11, still on I). Left: what you own:
  credits, the backpack slots, the gear you have on with its Take off button
  on the same row, your droids, your ships and their upgrades, your gear
  upgrades. Right: the story and your jobs, then the optional quests, each
  on its own card.
- **Pick your waypoint.** Every story, job or quest card with somewhere to
  go has a waypoint button. The one you pick is what the HUD arrow points at
  (saved as `objective_pin`). The card the arrow is on now is lit; unpicked,
  it is the most urgent one, marked "Waypoint (auto)". Picking one turns off
  a map waypoint, and a map waypoint turns off your pick: one pointer at a
  time. Board jobs can name a place with `target` (and a short HUD line
  with `objective`) in bar_board.json.
- **The Map shows you and the waypoint.** You are a pulsing green triangle
  pointing the way the camera looks; the map opens centred on you, and a
  "Centre on you" button brings you back. The waypoint's place flashes; out
  where no place is on the map (a drop in the desert, a marked spot) it
  shows as its own pin marker. Both are in the legend.
- **Text is easier to read everywhere.** Same font and phosphor look, but the
  bold cut, a crisp dark edge round each letter and a tight glow in the
  text's own colour, in place of a wide pale glow that fogged the letters
  (`RetroUI.legible`).
- Tests: tests/test_objective.gut.gd (picking and lighting the waypoint).

## Oda's recap when you come back (issue #185, 2026-10-31)

- **She opens with the news.** Come back to Oda after time away and she starts
  with a short recap of what has happened since you last talked: a bounty
  done, a ship bought, the beast killed. Up to three things, newest first.
- **With AI on**, her usual greeting comes first, then the model's turn. It
  recaps in her own voice, briefed with only those events and told not to
  invent anything. **With AI off** (or no provider), her greeting is an
  authored recap built from the same events.
- **No recap** on a first visit, in a fresh game, when nothing new has
  happened, or when the story or an opener has something to say first.
- The save remembers when you last talked (`heard_until` on her relationship).
  "Story:" bookkeeping lines are never news.
- Any AI character can do this with a `recap` block on their card (open,
  close, max, cue, instruction); Oda's is in cantina_owner_card.json.
- Test: tests/test_oda_recap.gut.gd.
## Textured stalls, and traders show what they sell (2026-10-31, issue #355)

- **Market stalls are made of something now:** sawn planks with grain, seams
  and nails; canopies and drapes of striped canvas; painted, chipped metal
  posts. Drawn in code (`StallTextures`), three textures for the whole market.
- **Each trader's stall shows its trade.** Food stall: fruit, flatbread, jars
  and a quartz case. Gear trader: the jetpack, an armour case and a cell case.
  Fence: the contraband he pays for. Droid merchant: droid heads, arms and a
  cell case. The items are the game's own item looks, listed in
  `content/look/items.json` under `stalls`.
- **The droid relays** get painted metal, and their merchant tables get a droid
  head, an arm, lit cells and a cell case.
- **Skrugs's stall** gets planks, a canvas canopy, and speeder parts on the
  counter: a thruster nozzle, fuel cans, a toolbox and a coil.
- **Crates:** the pit's crate stacks, the crates by hut doors and the stock
  crates behind each stall are plank crates with iron bands. The stall crates
  now collide (the others already did).

## No air on the asteroid without armour (issue #298, 2026-10-31)

- **The asteroid's rock has no air.** Step outside the station (past the dome,
  the hallway and the landing pit) without armour on and you lose 5 health a
  second, a straight line to death. A message says "Put on armour to roam this
  planet's surface." every few seconds. Die out there and you wake as from any
  other death.
- **Armour keeps you breathing** (anything worn in the armour slot, e.g. the
  Quantonium armour). Flying a ship is safe too.
- **Any planet can be harmful**: a `harmful_surface` block on its type
  (types.json; the asteroid has one) or on its own file, which wins. PlanetGen
  passes it through and the town adds the hazard (HarmfulSurface). Shelter is
  AsteroidWorld.sheltered(): the dome's ring, the hallway or the pit.
- Test: tests/test_harmful_surface.gut.gd.
## Saves remember where you were (issue #113, 2026-10-31)

- **Quit on the station, load on the station.** The save now remembers which
  planet you were on and where you stood on it (that planet's own coordinates).
  Opening the game from that save builds that planet first and puts you back
  on that spot.
- The spot is only taken when you're standing on your own feet (not flying,
  riding, falling or down). Otherwise the last good spot on that planet is
  kept, or you get the planet's spawn.
- Older saves, saves on a planet that no longer exists, a flight back from a
  pad, and headless runs all start as before (the home planet's spawn).
- Save: a `where` block ({ planet, pos }) via SaveSystem.set_where/get_where;
  resume: GameFlow.resume_from_save / take_resume_pos (once per run).
- Test: tests/test_save_where.gut.gd.

## Silent sword kills (issue #307, 2026-10-31)

- **Cut someone down before they notice you and nobody knows.** An energy sword
  kill on a trooper or a local who had not noticed you raises no alarm, plays no
  "man down" and wakes nobody else. This applies to the gate, the barracks,
  outposts, the cruiser and the town's locals.
- **Seen is still loud.** If the victim had noticed you, or another of them has
  noticed you, can see you, or has the victim in their sight cone close by
  (16 m), it is a fight as before. A cut that doesn't kill is a fight too.
- **Bodies get found.** A trooper or local who later walks within sight of the
  body shouts a new "found_body" line and raises the alarm.
- Shots are still loud. Standing changes and kill rewards are unchanged.
- Code: src/systems/npc/silent_kill.gd, used by Garrison and Townsfolk; NpcBody
  remembers whether the last cut landed unseen (`cut_unaware`).

## The beast's rock shell, glowing eyes, and no more spinning (2026-11-01)

- **Its shell is desert rock now.** Old Murk's plates, body, legs and jaws are
  weathered stone, not shiny plastic: sandstone strata across each segment,
  cracks and pits, lumps in the surface, a darker belly, and sand settled on
  its back and in the cracks. The stone sticks to the body as it walks.
- **Its eyes glow.** Each eye is a glowing orb with a white-hot core and a dark
  slit pupil. They throw a little light on the jaws and sand in front of them,
  pulse slowly, flare brighter when it chases you, and go out when it dies.
- **It no longer spins on the spot.** Its heading used to take a fresh random
  kick every frame, so the head twitched and its path looped back on itself in
  a space smaller than its 50 m body, which then coiled through itself. Now it
  crawls in long curves, never tighter than a 14 m radius (6 m in a chase).
  Bunched-up segments keep their facing instead of snapping round with the head.
- **If it does end up milling about, it walks out.** It checks every second: if
  over the last 20 s it got less than a third of the way it walked from where
  it started, it heads away from where it has been for 15 to 25 s, then
  wanders again.
- Numbers are in content/core/hazards/beast.json: `turn_radius_m`,
  `min_turn_radius_m`, `chase_turn_radius_m`, `stuck_window_s`,
  `stuck_net_frac`, `unstick_s`, and the `look.stone` and `look.eyes` blocks.
## Barracks and outposts stop you like the gate (2026-10-31, issue #308)

- **Walk into the barracks yard or up to a Remnant outpost below 40 standing**
  and the nearest trooper there walks over, asks for your papers, and the
  gate's card opens: papers, a search (pockets and contraband), a bribe, mouth
  off or walk away. The gate's rules all apply: a warning then shots when
  you're wanted by day, one band softer at night, and bribes that go up as the
  Remnant lose outposts.
- **40 and up you just walk in.** A "move along" at most.
- **Walk out before you answer and the card closes,** like walking away from
  the gate. Once you're cleared, that place leaves you alone for a few minutes.
- **Tunable in the data:** the yard is the town's `garrison` `checkpoints`
  (the ground from the yard walls to the hall), and each outpost's ring is the
  `zone` block in its location file (radius, who asks, how long a clearance
  lasts).

## Outposts shoot back at speeders and ships (2026-10-31)

- **A speeder or ship no longer hides you at an outpost.** Its troopers and
  droids fight you in one as they would on foot: shoot at them from the saddle
  or the cockpit and they shoot back at the hull, and once the Remnant shoot on
  sight they do it to your speeder too.
- **Riding past is still fine.** Out in the desert a vehicle is no offence by
  itself: no alarm unless you start something (or they already want you).

## The party barge fights back (2026-11-01)

- **Everyone on the barge falls like everyone else.** Kill a dancer, a band
  member, a guard or the old boss and they drop as a ragdoll, pushed away from
  the shot or flung along a sword's cut, and land on the deck (riding along if
  the barge is under way).
- **Hurt anyone and the party fights back.** The guards bring their rifles up
  and the crowd pulls holdout pistols, nearest you first. The band plays on and
  the boss only yells for his guards. They keep to the barge; once you get away
  (or are downed) they walk back to their spots and start dancing again.
- **None of it touches your standing.** Not the fight, the kills, getting
  away, or shots fired on board or on the sand round it.
## The dark master's red blade (2026-11-01)

- **He waits where the corridor opens into the cruiser's bay.** Walking back
  from the bridge to your ship you pass him, and his offer opens.
- **His blade falls where he does.** Kill him and his red energy sword lies on
  the floor, glowing like the one on the wreck's cargo droid. Walk up and press
  E to pick it up.
- **A red saber no longer takes over your blue sword.** Picking one up (his, or
  the wreck's) just puts it in your backpack. Open the inventory (I) and press
  Activate to fight with the red blade; Put away and your sword is blue again.
  An activated red saber can be drawn in a story save even without the blue
  one. A save that already had the wreck's saber starts with it put away.

## Sword fighting the dark master (2026-10-31)

- **Parries throw sparks.** When your blade blocks one of his blows, or his
  guard turns one of your cuts, a small burst of sparks goes off where the
  blades cross and you both get shoved back about a metre and a half. The
  camera jolts and the game pauses for a split second.
- **He no longer charges you the whole time.** He comes at you, strikes one to
  three times, then steps back out of reach and circles you for a second or so
  before he comes again. He runs in from far away and walks in from close up.
  Step into his reach while he circles and he cuts at you once, then backs off
  again. After you parry him he staggers, then backs off.
## Map zoom buttons and off-planet icons (2026-11-01)

- **Zoom buttons.** The F11 map's globe has + and - buttons in its top-left
  corner. Each press zooms twice as far in or out, alongside the mouse wheel.
- **Off-planet icons.** Each place in the sky has an icon beside it: a ringed
  planet for a planet you can fly to, a red wedge for the Remnant cruiser.
  Looks: content/look/map.json.

## The barracks change hands back and forth (2026-11-01)

- **Kill every Remnant trooper at the barracks and the locals take the town
  back.** Once the fleet is beaten (after the general's death, in story or free
  roam), a trooper you kill at the barracks stays dead, through a reload too.
  When the last one is down, the locals move in and like you a little more.
  Before the fleet is beaten nothing changes: they come back after a minute.
- **It goes on as long as you like.** Kill the locals' guards there and the
  Remnant come back; kill the Remnant and the locals come back.
- **Nobody moves in while you watch.** The new side takes the barracks once no
  post is on screen and you are 40 m away, or once you are 110 m away. Until
  then the barracks stand empty.
- **Driving the Remnant off is no longer for ever.** Holding all seven outposts
  still hands the locals the town, and the outposts still never fall on their
  own. But kill every local guard at the barracks and the Remnant retake the
  town; the outposts the locals hold start running down again from a full
  hold, and fall one by one unless Oda's supply runs keep them.

## A globe map in F11, and five settings pages (2026-10-31)

- **Map page.** F11 (or M) opens on a small globe of the home planet with an
  icon at every place that stays put: the port, the Remnant outposts, the
  droid relays, the traders (speeder stall, mechanic's yard), the cruiser
  wrecks, the old outpost and the two native camps. Zoomed in on the port it
  opens into its own stops (cantina, ship dealer, droid merchant, the stalls).
  Nothing that moves is on it. Drag to turn, wheel to zoom.
- **Click to set a waypoint.** A click on an icon points the HUD's objective
  arrow at it ("Waypoint: Drywash Droid Relay 1.3 km"); a click on bare sand
  marks that spot. It clears itself when you get there, is kept in the save,
  and is the only pointer on: switching on a quest's waypoint turns it off and
  the other way round.
- **Off planet.** Beside the globe: the station you can fly to and the Remnant
  cruiser, each a waypoint too (the station's clears when you land there).
- **Five pages instead of nine:** Map, Game (story chapter, time of day, speed,
  credits, space fights, town layout, new game), Player (outfit, then the
  cheats), Standing (factions, people, world flags) and Options (HUD colour,
  text size, volume, the AI brain, keys). F10 still jumps to the AI brain.
- The panel now shrinks to fit the window, so at a big text size the tabs and
  the Save/Close buttons stay on screen.
- Data: content/core/flow/map.json (what is on the map, labels, lines),
  content/look/map.json (icons and colours).

## The fence buys anything, a droid post by the gate, Skrugs's stall (2026-10-31)

- **The fence buys anything you carry**, not just contraband: guns, blades,
  gear, armour, quartz, food. Contraband still pays twice its value; everything
  else half, the gear trader's rate, so nothing bought in town sells there at a
  profit. Same for the station's fence. (`"*"` in a vendor's `buys`, paid at its
  `any_rate`.)
- **The fence never runs out of quantonium armour.** Once your first bounty
  unlocks it, it stays on his stall: buy it, sell it back to him (250), buy it
  again (500), as often as you like. (An offer can be `"endless"` in fence.json;
  the gun and jetpack upgrades are still once each.)
- **A droid merchant you can see from town.** The Drywash Droid Relay moved a
  kilometre closer, to about 310 m straight out from the front gate. Its hut and
  tall mast show through the gate from the street, and its counter faces the town.
- **Skrugs's stall is at the gate end of his yard**, right in front of the
  display speeder and beside his garage, facing the back gate: the first thing
  you see walking in from the desert. It used to be tucked behind his house.
- **Skrugs buys a stolen ship within 100 m of his stall** (it was 30 m from a
  spot outside the gate). Land it outside the back gate, or on the port's two
  nearest pads, and talk to him: he opens with his price and the chat box offers
  the sale at once, no asking needed. Click Sell and the ship is gone.
## The party barge stops eating the frame rate (2026-10-31)

- **Its cost was everywhere, not just near it.** Measured rendered with the look
  on, the barge was about half of every frame's work: 12 to 14 ms of physics and
  3 to 5 ms of scripts, even standing in town 660 m away. Now its physics cost is
  about 1 to 3 ms when you are near it or on deck, and close to nothing from town.
- **Parked until it is yours.** Nobody's barge no longer drifts about its home;
  it sits still, so its 40-odd colliders and 33 hit boxes never move. It only
  moves on autopilot once you own it (the drift numbers are gone from
  party_barge.json).
- **Its people are built late.** The crowd, band, DJ, guards and boss are built
  the first time you come within `party_m` (220 m), one a physics tick (about half
  a second), instead of at load.
- **The club only animates near.** Its pulsing lights and props stop past
  `anim_m` (160 m), and the barge's whole look is only moved between physics ticks
  while the barge is actually moving.
- **Fixed:** each dancer's skin was synced once per skin layer, times every layer.

## The Albatross is a black Lanner gunship (2026-10-31)

- **New look for the pit's gunship.** The Ashford Albatross Mk VI in bay 4 was
  the last ship still on the first, pale blue textured model, which didn't
  match the game's style. It is now built on the Lanner's body: a little
  bigger (9 m), painted black with glowing teal bands and canopy. Same name,
  same numbers, still not yours until T-89 sells it to you.
- **It looks like a gunship.** Long cannons out front of the wingtip pods, a
  twin chin cannon under the nose and a small twin-gun turret on its back, all
  with teal muzzles. They are always on: a ship look can now carry `parts`
  (content/look/ships.json), the same kind of part T-89's upgrades bolt on.
- **T-89's upgrades show on it too:** shield rings, hull armour and the flared
  boost nozzle, sized up from the Lanner's.
- Bay 4's box is resized to the new model (port_square.json, regenerated
  port_round.json, town_kit `ship_boxes`). The old model is kept in
  assets/vehicles/source/gunship.glb. Stills: docs/lookdev/vehicles/06_albatross.jpg.

## Divergent endings: the dark master (issue #303, 2026-10-31)

- **The general's death is locked in.** Killing him on the cruiser still pays
  the 20,000 credits on the spot, and now the game saves right there too. The
  end card no longer pops up on the bridge: the story says "go back to Oda", and
  her telling brings the end card.
- **A dark master waits in the cruiser's bay.** After the general dies, a figure
  in all-black armour with a red energy sword stands where the corridor opens
  into the bay. Walk past him on the way back to your ship and
  he talks to you (an AI character): "There is a dark energy emerging. Join me,
  and realize more power than you could know." You can't walk away; answer him,
  and if the talk drags on the game asks you outright: Join or Refuse.
- **Refuse,** and he says "Then I must destroy you." and fights you with the
  sword: he runs you down, slashes and swings, bounds across the deck, and turns
  most shots from the front aside with his blade. Block his blows with your own
  blade and he reels. Kill him and his red blade is yours.
- **Join,** and your Remnant standing jumps to friendly: their fighters,
  outposts and the cruiser's crew stop shooting. Your new quest is to clear the
  local guards from the town's barracks. They still think you're on their side.
  Kill all five and the Remnant take the town back, and the end card says the
  Remnant hold the moon. Go back to Oda before that and the oath is broken: the
  normal ending, and the Remnant and the dark master are your enemies.
- **The town can change hands.** Whenever every local guard at the barracks
  dies, the Remnant move back in (troopers, droids and the gate checkpoint).
  Holding all seven outposts gives it back to the locals.
- **On the barracks roof.** While the Remnant hold the whole planet, the dark
  master stands on top of the barracks facing the gate (on his oath in a story
  game; always in free roam). He fights back if you attack him, and killing him
  while sworn to him turns the Remnant against you.
- **Free roam diverges too.** Killing the general breaks the fleet there as
  well (the garrison leaves town). The dark master is just an enemy: in the
  cruiser's bay after the general dies, and on the roof whenever the Remnant
  hold the planet.
- **The generals wear bright blood red.** The cruiser's general and General
  Vask in the barracks now wear a new `guard:blood` armour (bright red plates,
  black stripes) instead of the dark oxblood, which stays for the bounty officer
  and the honour guards. Blood red and the dark master's all-black `guard:void`
  are in the character builder's guard colours too.
- **Friends of the Remnant.** Friendly with them in free play, you can take
  their ships without an alarm (borrowed, not stolen: no chase, a little
  standing, and Skrugs won't buy one). The desert droid posts sell droids
  cheaper to friends of the Remnant, and the port's market to friends of the
  locals, never below what the merchant pays back.

## Skrugs's yard, garages and stolen ships (2026-10-31)

- **Skrugs moved in.** In the round port his stall is inside the wall now,
  right behind the cantina on the back lane: his house, his stall, the display
  speeder and a new garage. In the square port (F11 > World > Town) he is back
  outside its own back gate, where he stood before the round port. His sand
  ramp stays out in the desert past the back gate.
- **The back gate fits a speeder.** It is just wide enough (about 3.9 m) to
  drive one through. Buy a speeder, drive it out of his garage, turn down the
  lane and out into the desert. Take the gate at a careful speed.
- **No more price board** at his stall.
- **Garages you can drive into.** Skrugs's new garage and Dorrin's garage out
  in the desert are walls and a roof now, open on one side, so a speeder drives
  straight in. Dorrin's lift is inside his garage.
- **Skrugs fits parts too (free roam).** [E] at his garage bench opens the same
  menu as Dorrin's, same parts, same prices, for the speeder parked in his
  garage. In a story game Dorrin is still the only mechanic.
- **Skrugs buys ships, and asks no questions.** Land a ship you stole from a
  Remnant outpost by his post (in the round port, just outside the back gate)
  and talk to him: he pays a quarter more than its list price. He also buys back
  the ship T-89 sold you, at T-89's price. Only your click sells. A stolen ship
  you sell is gone, and the Remnant interceptor stops chasing it. He never buys
  the ship in the pit or the port's free ones.
- **Bought speeders wait in his garage** (and beside it once it is full).
## The party barge, cleaned up (issue #269 follow-up, 2026-10-31)

- **No more shaking.** The drifting barge used to get a fresh random turn every
  physics tick (about 3° at a time), so the whole hull jittered. It now picks a
  new heading every 12 to 25 seconds and turns onto it gently. It is also drawn
  between physics ticks like the player (render smoothing), so it glides
  instead of stepping against a smooth camera. Its parts are merged into one
  mesh a finish (a few draw calls, not hundreds), small props and their lights
  fade out far off, and the crowd animates at a quarter rate past 50 m.
- **A new look.** Rusted iron hull plates in a skin that flares to the gunwale
  and runs into a raked prow, lit portholes down both sides, blue repulsor pods
  underneath. Wood plank decks. The sails are now **solar panels**: navy cells
  with glowing blue lines between them, pulsing slowly with the music.
- **A franchise of the cantina club.** The top deck has the cantina's band (the
  hologram drums and the laser upright bass) on a stage at the bow, the club's
  neon sign (the cocktail glass and the moon) over them, a checker dance floor,
  velvet and panelling, warm and blue spots, a piano and a sax, candlelit tables
  and a bar with bottles. **A DJ on the lower deck** runs a small rave: a light-up
  floor, a hologram wall, speaker stacks with strobes, moving heads, a mirror
  ball and neon strips, with a lounge of leather booths aft.
- **Everyone on board can be killed**, and nobody fights back. It never touches
  your standing with anyone. They are back on their feet after 3 minutes of play,
  or the next time the town is built. Kill the whole band and the DJ and the
  music stops until they are back. The old boss, once he has handed the barge
  over, is just another partygoer.
- **The control panel.** The wheel is gone. Yours, [E] at the panel by the stern:
  [A/D] turns the course (a needle on its compass screen and a hologram arrow
  over it show where), [W] engages the **autopilot**, [S] is all stop, [E] steps
  away. On autopilot it swings round onto the course and cruises (4.5 m/s) while
  you walk the decks; the gangplank comes up while it is under way.
- **It stops dead if it runs into anything** (rocks, buildings, anything in the
  world's data). Set a new course and go again. **Run it into the beast and it
  blows up**: fire along the hull, anyone aboard hurt and thrown clear. It is
  built again at its home 4 minutes of play later, still yours.
- Numbers are in content/core/barges/party_barge.json (`drive`, `person_hp`,
  `respawn_s`, `rebuild_s`, `blast_damage`). The look is
  src/systems/world/barge_look.gd; new surfaces `ClubTextures.rust`, `solar`
  and `local` (textures mapped in the mesh's own space, for things that move).
- Trace: scenes/barge_trace.gd, tests/test_barge_trace.gut.gd. Stills:
  docs/lookdev/barge/.

## The Lanner is a rocket with wings (2026-10-31)

- **New Lanner model.** The Valcourt Kinetics Lanner, the fastest small ship
  in port, is now a wide silver and blue rocket with short swept wings: a long
  needle nose, a teal canopy, one big engine at the back with booster pods on
  each side, and blue pods on the wingtips. Made in Hyper3D from a concept sheet.
- **Brushed silver, not white.** The prep step repaints its light panels
  silver and gives them a metal finish, so it reads as metal in the desert
  light too. The blue bands stay blue.
- **Its engine flames** come out of the big main nozzle and the four booster
  pods beside it.
- **T-89's upgrades show on the ship.** Each upgrade bolts parts onto the
  Lanner, and they stack:
  - **Boosted shields:** glowing cyan emitter rings on the wingtip pods and a
    shield dish on its back.
  - **Reinforced hull:** gunmetal armour on the nose cheeks, the wings' leading
    edges, the booster pods and the belly.
  - **Booster speed:** a longer, flared main nozzle with a hot orange glow, lit
    side boosters and orange heat stripes.
  The parts appear on the parked ship as soon as T-89 fits them, and on your
  ship in a dogfight. The frigate shows its upgrades as paint jobs instead (see
  below); any look can add parts under `upgrades` in `content/look/ships.json`.
## The wreck field (2026-10-31)

- **Three more crashed starcruisers** lie out east, under the Remnant's cruiser and
  most of the way round to the far side of the ball (map 3.5 km, 5.6 km and 7.7 km
  east). Each is about 2.2 km from the last, so from one you can see the next
  one's stern over the sand.
- **Each one is barely different**: its own heading, a fallen deck and drop ramp
  (port on one, starboard on another), a missing stair on the last, other ramp
  widths, other railings knocked out, a radiator or two gone, the torn plating
  twisted another way, no speeder kicker on the last. A landmark's `variant`
  (`StarcruiserWreck.VARIANT_KEYS`) says what changes.
- **Every wreck has the same Remnant crew** (less the droids for a deck it lost).
  The red saber's hauler stays on the first wreck.
- **Wreck droids come back** three minutes after they fall, or as soon as you are
  500 ft (152 m) from where one fell. Droids more than 900 m from you stand still,
  so four crews cost little.
- **A supply crate on every wreck's bridge platform**, the first wreck's too,
  under a beacon. `[E]` opens it for one random prize: 300 or 600 credits, 10 sand
  pig, 5 refined quantonium or 3 holocrystals. An opened crate stays open (saved).
- Small wreck parts (railings, vents, braces) are not drawn past 1.5 km.
## The round port (issue #237, 2026-10-31)
## Brighter star cruiser (2026-10-31)

- **Every area aboard the Remnant cruiser is lit properly.** The bay, the
  corridor, the armoury and crew room, the ramp shaft and the bridge were all
  too dark to see in; the corridor, shaft and crew room were close to black.
  There are more lamps now and they are brighter: floods and a low fill over
  the bay's pads, a lamp every 15 m down the corridor, two per side room, one
  on every landing of the shaft plus side fills, and extra lamps over the
  bridge. The colours are the same as before.
## Tab cycles weapons (2026-10-31)

- **Tab steps through your weapons**: pistol, blade, rifle, then empty hands,
  then back to the pistol. It skips any weapon you don't have yet. T-89's
  tutorial now mentions it.

## The new frigate (2026-10-31)

- **The Frigatebird has a new model.** It is the strongest ship and the big
  cargo hauler: a thick, boxy disc with a forked front, three engines on the
  back and no wings. It is a new Hyper3D model built from a concept sheet. The
  Remnant's dark frigates (the one in the cruiser hangar and the ones at the
  outposts) use the same airframe in their dark paint.
- **Upgrades repaint it.** Each upgrade T-89 fits to a Frigatebird has its own
  paint: blue for boosted shields, steel grey for a reinforced hull, red for
  booster speed. With more than one fitted, the last one shows. The parked ship
  changes colour as soon as he fits it, and it keeps that paint in the air and
  in space. Other ships keep their stock paint.

## Space fights at real speed, and a seeker rack (2026-10-31)

- **No more slowing to a crawl when a fight starts.** Space fights used to run
  at the ships' old dogfight speeds (48 m/s for an interceptor), so your speed
  dropped from about 680 to 48 the moment the enemy showed up. Now a fight runs
  at your edge-of-space speed, about 480 m/s, and nothing jumps as it starts or
  ends.
- **Top speed at the edge of space is down to 70%**: 2.8x the ship's speed near
  the ground instead of 4x (an interceptor tops out at about 476 m/s instead of
  680). Grit Station is still under half a minute away.
- **Everything in a fight scales with the speed**, from one file,
  `content/core/flow/space_fight.json`: speeds x10, distances x2 (the arena, where
  waves arrive, how far pilots engage and break, gun and seeker range), bolts x3
  faster, turning x1.3, and ships' hit spheres x1.5. The values come from
  headless runs of both fights over 28 seeds: the player wins about as often as
  before and lands about as many gun hits. Fights run longer (about 90 s
  instead of 30-60).
- **Seekers are a rack of four.** Hold the seeker key with a lock and all four
  go, one every 0.3 s, and the lock holds through the salvo. The rack gets one
  back every 1.5 s. Each seeker hits harder (85, was 55) and turns a little
  tighter. AI pilots still lock afresh for each seeker.

## The round port (issue #237, parts 1 to 4, 2026-10-31)
## The round port (issue #237, parts 1 to 3, 2026-10-31)
## Eject from the ship in flight (issue #271: #274, #275, #276, 2026-10-31)

- **Falls hurt (#274).** Landing faster than 16 m/s (a drop of about 6 m) costs
  health, rising in a straight line to 100 (your base health) at 40 m/s (about
  40 m). Nobody falls faster than 45 m/s. A jetpack burn before you land takes
  about 29 m/s off, enough to walk away from a high fall. Armour's extra health
  helps a little. Only the player takes fall damage; guards share the body but
  never do. The numbers are in `content/core/flow/falls.json`.
- **Hold B to eject (#275).** In the air (below space, outside a fight, not
  during the opening landing), hold B for half a second. You're thrown clear
  above and behind the ship, kicked upward, and carried on by her speed (up to
  60 m/s, fading in the air). Then you fall on foot. Without a jetpack, a high
  ejection is fatal. The tuning is in `launch_pads.json` (`eject_*`).
- **The empty ship comes down on her own (#276).** With nobody at the controls
  she goes **adrift** at zero throttle. She keeps her momentum, air drag slows
  her, gravity pulls her down, and her nose drops the way she's going. If she
  hits faster than `crash_speed`, she crashes and is towed back to her pad like
  any crash. If she comes down slower, she rests where she lands and you can
  walk back and board her. She can still be shot on the way down. You can't
  board another ship until she's down or towed.

## Ejecting from your own ship sends her home (2026-11-01)

- **Your ship flies home; a stolen one crashes.** Eject from a ship you own and she
  is on her pad at once, with "Your ship flies home. Press [I] to call it back."
  (the ledger's Call button). No fall, no crash, no tow. A stolen or borrowed ship,
  or a pad's own ship that is nobody's, still goes adrift and crashes as before.

## The party barge (issue #269, 2026-10-31)

- **A sail barge that is one long party.** Out in the home planet's desert,
  about 650 m from town, the Gilded Wallow floats over the sand. It has two
  striped sails, string lights, an awning over the dance floor and a bar.
- **A band on the top deck** (horn, lute, drums, pipes) plays the same club
  music as the cantina (the planet's `club` playlist). You hear it by distance
  from the barge, and on board on every deck. A crowd dances on every deck: the
  top deck, the lounge below and steerage at the bottom. They do the cantina's
  dance loop.
- **The boss, Grubba Vosk**, is big, wide and ugly, warts and all, on his dais
  with two guards. [E] by him to talk. With enough credits, [E] buys the barge
  (1500). Or shoot or cut him down (400 health). Either way he goes below to
  the lounge and keeps partying, and the barge is yours (saved).
- **Drive it.** Yours, [E] at the wheel by the stern takes the helm:
  [W/S] throttle, [A/D] steer, like a speeder but slow and heavy (4.5 m/s
  top). You stand at the wheel and ride along. **The party never stops**: the
  band plays and everyone dances while it moves. [E] lets go.
- **Walk inside.** A gangplank runs from the stern to the sand. A ramp on the
  port side goes down to the lounge, and another on the starboard side down to
  steerage (crates, hammocks, lamps). Everyone down there is partying too, and
  the top deck is still going when you come back up.
- **Any planet can have one.** Add a `"barge"` block to the planet's file (name,
  boss, home; any number in content/core/barges/party_barge.json can be
  overridden). PlanetGen passes it through and the town builds it (`with_barge`).
- With more than one club in a scene (the cantina and the barge), the loudest
  one plays (ClubMusic).
- Trace: scenes/barge_trace.gd (in CI), tests/test_barge_trace.gut.gd. Stills:
  docs/lookdev/barge/.

## The round port (issue #237, parts 1 and 2, 2026-10-31)

- **Towns are saved layouts.** Today's port is kept as `port_square` (size 50)
  in `content/core/towns/`, and a planet picks its layout with `town_layout`.
  The town is still `port_town` whichever layout it has, so saves carry over.
- **A second layout: the round port** (`port_round`, size 67). A round wall,
  about twice the floor space (61,600 m² inside), two manned gate towers, a
  76 m bowl with eight surface pads round it, and huts and towers that wrap
  round the back until they nearly meet behind the cantina, with only the back
  lane to the back gate between them.
- **The round port's market is three times today's** (part 3): 48 stalls along
  three curved aisles, with two aisles cutting across them and six shops on the
  far side. Every stall is taller (a 3.4 m back panel, its canopy 0.9 m higher,
  from the stall's `canopy_lift`). Twelve merchants (the four traders as before)
  and six shoppers walking the aisles.
- **Its barracks are about twice the size**: a bigger hall with the riflemen on
  its roof, the bunk tower and upper block bridged as before, a second block,
  an armoury, and a yard with the Remnant's pad and a drill ground.
- **Its cantina is a round club** (part 4): a round body with the same floor
  as the square room, a round roof with a parapet, and the arched door facing
  the square. The jazz club inside is as before, its band, bar, tables and
  patrons in their places: a round plank floor, panels and drapes following the
  curve, booths against it. The stair tower is a turret outside the wall,
  entered through a side door.
- **The stair tower is lit all the way up**, in both ports: a warm light in
  every turn of the ramp and in the lookout, brighter lamps on the core, and a
  glowing band under every ledge outside, so the climb reads at night and from
  the square.
- **You can jump out of the lookout's windows**, in both ports. The sill is
  0.45 m (was 1.1 m), so a walk stops at it but a jump clears it, and the roof
  is 3 m up (was 2.5 m), so you fit through standing.
- The overlap check (V5) now treats round boxes (round huts, the stair tower,
  the lookout, the round roof) as circles, not squares. A stair tower's door can
  face any way (`door_deg`).
- **The home planet is the round port now** (part 5). F11 > World > Town builds
  it to the square one for the rest of the run.
- **Skrugs moved out** to about 90 m past the back gate, straight out from it,
  so a speeder starts to make sense. The near outpost is off the barracks side
  (0, 250) and the far outpost moved to (700, 300): straight out of the front
  gate you see only the crashed cruiser and the desert.
- Oda's town briefing and Skrugs's card tell it the round way.
- **The round port is fuller**: crates, barrels and water tanks against a share
  of the houses (never walling a door in), a cargo yard with a container and
  crate stacks in every gap between the landing pads with a dock hand by each,
  more towers on the barracks side, and three more locals walking the lanes.
- New stills of the round port in `docs/town/look/port_round/`, and the frame
  time against the square port in `docs/town/round_port_perf.md`.
- **New box kind `ring`**: a round wall cut open at gates, which any layout can
  use. The validators check it (V9).
- `tools/town/gen_port_round.py` makes the round port from the numbers in
  `town_kit.json` (`round`). Don't edit the layout file by hand.

## The beast is a giant beetle-centipede (issue #266, 2026-10-31)

- **No more purple ball.** The planet's beast (Old Murk on the home planet) is
  now a giant armoured beetle-centipede. It has a beetle's head with a horn,
  curved mandibles that open and close, swaying antennae and glowing eyes. Its
  long body is 14 armoured segments, about 50 m from head to tail.
- **It walks.** Each segment has a pair of legs that step in a wave as it
  crawls. The body follows the exact path the head took over the dunes.
- **Same behaviour as before.** It wanders with no pull toward or away from the
  town, kills on touch, has 1000 health, chases you if you hurt it, stays dead
  once killed, and still farts (now from its tail end).
- **The whole body is deadly and can be hit.** Touching the head or any segment
  kills you, on foot or on a speeder. Bolts and blades hit any segment.
- **Dead, it slumps** and its legs curl up.
- The locals' lore, the AI briefing and the beast's lines now describe the new
  creature. Numbers and colours are in content/core/hazards/beast.json
  (`segments`, `segment_gap`, `tail_scale`, `stride_m`, `look`).
- Stills: docs/lookdev/hazards/desert_beast.jpg and desert_beast_head.jpg.

## The moon's dome rave (issue #261, part 2, 2026-10-31)

- **Grit Station's whole dome is the club now.** The cantina building and the
  four grey homes are gone. The bar (Oda's counter under a lit canopy, with a
  freestanding back bar) and the merchant's table stay where they were.
- **The stage is on your right as you walk in from the pad.** It's round with
  a diamond-plate deck and a lit rim that cycles through the colours. Above it
  stands a truss with moving heads, strobes and a fan of sweeping lasers, and an
  LED video wall rolls colours behind the DJ. Rave speaker stacks stand either
  side.
- **Only a DJ** plays, at a black rave desk with glowing buttons and two glowing
  decks. Kill them and the music stops. The station's **dancer** has moved off
  the stage to dance on the floor beside it.
- **An LED dance floor** in front of the stage ripples on the beat. Ravers stand
  on it and dance, a hand thrown up for a few bars now and then, with drinks.
  More walk loops round the room. They're locals: they fight back, and the town
  talks.
- **It's dark in there.** The dome is smoked glass that keeps the sun off, and
  its floods are turned down (`"club_dome": { "dim" }`). Neon rings run round the
  wall and a mirror ball hangs over the floor.
- A planet's `"club_dome"` turns this on for a sealed station. The layout is in
  content/core/planets/town_kit.json (`club_dome`).

## The clubs' people, and the desert's jazz club (issue #261, part 1, 2026-10-31)

- **The desert port's cantina is a chill jazz club.** A dark plank floor with a
  checker floor round the stage, panelled walls under velvet drapes, leather
  booths with candlelit tables, round tables in place of the old boxes, warm
  and blue stage spots through the haze, a mirror ball, a neon sign over the
  bar, an upright piano and a saxophone on its stand. The house lights are
  turned down (`"club": { "dim" }`).
- **A band of three plays on the centre stage**, back to back, facing out. They
  are full black versions of the player with the guard's white helmet:
  - the **DJ**, at a desk with glowing buttons and two glowing decks that spin;
  - the **drummer**, standing at a **hologram drum kit**: a floor projector
    throws up see-through hex pads, cymbal discs and a kick panel that flare and
    swell on each hit;
  - the **bassist**, on a gloss black upright bass **strung with lasers** that
    cycle through the colours, both hands up on the neck.
  Each plays a 20 s loop (ClubMoves): looking round the room, moving their arms,
  bobbing on the beat and shifting their weight, with their hands kept on the
  instrument by the arm IK.
- **Kill a band member and the music stops** until the next visit.
- **A crowd with drinks.** Eight patrons stand at the tables or walk the room,
  bottle in hand, nodding along and taking a sip now and then. They are locals:
  hurt one and the whole club draws holdout pistols and fights back, and the town
  talks about it. Gunfire scatters them but does not stop the music.
- **Ask Oda for a vibe.** "Something harder", "slow it down": she has the band
  change the song (`club_vibe`, checked against the club's moods). Free, and she
  never refuses.
- **Shared with the moon's club (part 2):** the textures (ClubTextures), the
  instruments and lights (ClubProps), the play loops (ClubMoves), the band and
  patron profiles, and Oda's action.

## The club mix (issue #104, part 1: the music, 2026-10-31)

- **Every cantina is a club now.** Walk toward one and its music fades in from
  about 40 m out, muffled through the walls; the town's own music fades down
  under it. Step through the door and it opens up to full volume and is the only
  music playing.
- **Two playlists, one per planet.** The desert port's **Dust Lounge** is afro
  and organic house (12 tracks, about 48 min). Grit Station's **Salvage Rave** is
  UK garage, breaks and rave (11 tracks, about 37 min). Other planets play Dust
  Lounge. A planet's file picks its playlist with `"club"`.
- **Songs shuffle and blend.** Never the same song twice in a row; each blends
  into the next over 10 s. Walk away and back and a new song starts.
- **Gunfire does not cut the club.** Battle music only plays outside it.
- **If the band is killed the music stops**, until the next visit's new band.
  (The band itself comes in part 2; the hook is `Sound.set_club_live(false)`.)
- **Oda can change the vibe** (`Sound.club_vibe("hard")`): every track has mood
  tags. Her dialogue action for it comes in part 2.
- **The tracks are free**: 22 from Pixabay (Pixabay Content License) and one CC0
  from Free Music Archive, in the taste of the artists in the issue, not their
  releases. Each entry in content/look/sound.json links its source page.
  `tools/audio/rip_club.py` brings downloads in at the music's one loudness.
## Flying to the star cruiser (2026-10-30)

- **The cruiser holds orbit higher**, 7 km up (was 4.6), so the fight on the
  way up runs most of the way there.
- **Flying at the cruiser no longer breaks the fight off.** The planet curves
  away under the straight line to it, which used to dip you under the edge of
  space and end the fight. With your nose on the cruiser the fight carries on;
  a real dive still breaks it off.
- **The fight comes with you.** Both sides used to turn back to where the fight
  started; now they stay with you all the way to the cruiser.
- **No more zooming off near the cruiser.** Within a few km of it normal flight
  slows to the ship's space-fight speed (48 m/s for an interceptor, not 680), so
  a fight broken off by the hull leaves you a ship you can line up with the bay.
  Z within reach still flies you in and onto the pad, fight or no fight.

## Nomads trade for sand pig (2026-10-30)

- **Food is now called sand pig.** The item, the nomads' trade menu, their
  prompts and the log all say sand pig. Saves still work (the item's id is
  still `food`).
- **The nomads' goods cost single digits.** Jetpack 3, rifle blaster 5, energy
  blade 6, red energy saber 8, quantonium armour 12 (were 30 to 125).
  Skrugs and the quest text now quote a blaster for 5 and armour for 12.

## The beast (issue #220, 2026-10-30)

- **Every planet can have a beast.** A planet's file
  (content/core/planets/<id>.json) may have a `beast` block: its name, its home
  spot, and what the locals say of it. The home planet's is **Old Murk**, a
  glossy purple blob about 7 m across that rolls about the desert about 900 m
  from town. The numbers every beast shares are content/core/hazards/beast.json;
  a planet's block can override any of them.
- **It has nowhere to be.** Its heading drifts at random. It is not drawn toward
  the town and does not avoid it. A loose leash, about 1.4 km round its own home
  spot, turns it back only if it strays very far.
- **Touch it and you die.** On foot, or riding a speeder into it, you die on the
  spot, whatever your health. You wake as from any other death (the garrison's
  pit). If nothing else wakes you within a few seconds, the beast does it.
- **Hurt it and it comes for you.** It has 1000 health and takes bolts, speeder
  lasers and blades. Once the player hurts it, it rolls after them at 5.5 m/s
  (faster than a run, a little slower than a sprint) until they are 1 km away or
  dead, then goes back to wandering. Stray bolts from anyone else only hurt it.
- **Kill it and it stays dead.** It sinks into a purple puddle. The flag
  `beast_slain_<planet id>` keeps it from being built again, it goes in the event
  log, and the locals' talk changes.
- **The locals know it.** Walk close by a calm local and now and then they say
  something about it by name (the planet's `lore` lines, at most once every 30 s).
  Every AI character (the cantina owner, Skrugs, T-89...) is briefed on it by
  name each turn, so they can talk about it if asked.
- **It farts.** Every 9 to 26 seconds: a wet noise
  (assets/audio/npc/blob_fart.wav, made by tools/audio/make_npc_sfx.py), a
  yellowish puff behind it, and a squash.
- **Code:** src/systems/world/planet_beast.gd (`PlanetBeast`). The town scene
  adds it as a late build stage (`with_beast`) on planets that have one.
- **Trace:** scenes/beast_trace.gd (in CI), read by tests/test_beast_trace.gut.gd.
  Still: docs/lookdev/hazards/desert_blob.jpg.

## The locals forget you when you die, like the guards (2026-10-30)

- **Waking in the pit wipes the locals' grudge.** After you get away from a
  fight with the port's locals they still remember your face for 4 minutes and
  start again on sight. Getting knocked out was meant to clear that, but if
  anything hit a local while you were out (your droid's last bolt, say) their
  alarm went back up and you woke to 4 more minutes of it. Now, as with the
  Remnant's garrison, the town's locals and every outpost's forget the fight
  and your face the moment you wake in the pit.

## Assassin droids stand up straight to shoot (2026-10-30)

- **No more frozen half step.** An assassin droid that stopped walking or
  running to shoot at you stayed stuck halfway between a stride and its ready
  stance for the whole fight. Now it settles into the upright stance within a
  fifth of a second and holds it while it fires. This applies to the
  Remnant's, the locals' and your own.
## Shop menus: keys, and they stay open (2026-10-30)

- **Every NPC menu takes W/S or the arrows and Enter.** T-89, Dorrin, the droid
  merchant, the general, the market stalls, the fence and the nomads' trade all
  show a lit cursor bar; W/S or Up/Down moves it, Enter picks the row, 1-9 still
  pick straight off and Esc walks away. Long menus scroll and wrap to fit the
  screen at any text size.
- **Buying or selling no longer closes the menu.** It reopens with the new
  prices, your credits and what the keeper said, the cursor on the same row, so
  you can sell three power cells in a row.
- **The market stalls have a real trade menu.** [E] used to sell the first thing
  the stall would take (your worn jetpack included) in one press. Now it opens a
  list: everything they buy from you, with counts and prices, what they have for
  sale, and at the fence its upgrades and Talk, all in one menu.
- **Text size starts at 175%** (was 125%). A size you already set in F11 > HUD
  is kept.

## Ship guns hit people hard; one hull in the air and in space (2026-10-30)

- **A ship's cannon kills a man in one hit.** A direct hit from a ship's guns
  now does 130 damage to anything that is not a ship (times the ship's blaster
  power): every trooper, sentry and guard, the cruiser's troopers and assassin
  droids included, goes down to one bolt, in the atmosphere or aboard the
  cruiser. Honour guards, bounty targets and the general take two or more.
  Before, a direct hit did 9 (less than the 22 of a near miss's burst).
- **Ship against ship is unchanged** and the same everywhere: 9 a bolt on a
  hull, through the shield first, in the air as in space.
- **Your ship keeps its damage between the air and space.** Climbing into an
  orbital fight used to give you a fresh hull and shield, and coming back down
  forgot what the fight did to you. Now it is the same hull and shield all the
  way up and back.

## Who holds the desert: the Remnant or the locals (2026-10-30, issue #187)

- **Seven Remnant outposts now.** Besides the three out the front gate, four new
  ones sit round the other sides of the town, 500-650 m out: the salt pan
  outpost (north), the old well outpost (south), the glass flats outpost (west)
  and the dust gap outpost (southwest). Each has its own building, ship,
  troopers, droids and cover, and can be the bounty contract's outpost.
- **The outposts change hands.** Kill every trooper at a Remnant outpost and the
  locals take it: two of their guards in desert armour and a white assassin
  droid move in once you are out of sight (or after half a minute). The
  Remnant's troopers and droids stop coming back there.
- **The Remnant take it back** after 20 minutes of play, or straight away if the
  locals' guards there are all killed. They return once you are 110 m away.
- **Supply runs from Oda.** When an outpost the locals hold is running short
  (8 minutes left), Oda offers "Supplies for the locals". Walk up to that
  outpost with the job on: the hold is full again and the locals pay 120 cr.
  The objective pointer points at it.
- **Hold all seven at once and the Remnant are driven off** the planet: nothing is
  retaken after that, and the locals take the barracks too.
- **When the story ends the locals own the barracks.** Once the fleet is beaten
  and the Remnant leave town, desert guards stand at the gate, the tower and the
  yard, and two white assassin droids walk the main street. They leave you alone
  until you hurt a local, then fight like the Remnant did.
- **What it changes:** with three outposts lost, the Remnant's gate checkpoint is a
  band stricter, and every lost outpost makes bribes 25% dearer. The fence pays
  8% more for contraband per outpost the locals hold. Oda has new rumors about
  it. F1 shows a CONTROL section: who holds each place and how long the locals'
  hold lasts.
- Numbers and lines: `content/core/story/territory.json`. Not in yet: Remnant
  raids or an interceptor hunting you after big losses, and the Remnant
  retaking the gate.

## T-89 talks: returning hello, ship advice, and he is solid (2026-10-29)

- **A returning line instead of the tutorial.** The first game, T-89 says hello
  and offers the tutorial as before. Every game after that (the save remembers
  he has met you) he just calls out one line across the pit, like "I have
  multiple ships for sale, ready for all kinds of things!". The lines are under
  "returning" in content/core/npcs/t89.json. The tutorial is still in his shop.
- **He is an AI character now**, like Oda and Skrugs. [E] still opens his shop;
  its first option, **Talk**, opens the chat box. His prompt holds every ship he
  sells with its price and its real numbers (hull, shields, top and boost speed,
  guns, what Shift does), what is on your pad, and your credits. Ask what to buy
  and he recommends one ship and says why; the price card comes up and **Buy**
  puts it on the pad. The price is always the game's, never the model's.
- **With no model he still recommends a real ship.** He matches what you asked
  for (speed, a fight, hauling) and says so when you cannot afford it, offering
  the best one you can.
- **Solid all round.** His collider is a cylinder his full height (2.3 m) and wide
  enough for his shoulders and hanging arm, so you cannot clip into him from any
  side.
## The Remnant cruiser in orbit, and Oda's last job (2026-10-30, issue #193)

- **A Remnant star cruiser holds orbit far to the east**, 4.6 km up and round the
  curve of the planet: you cannot see it from the port, and you cannot miss it
  from space. It is the wreck in the desert remade whole and clean: 690 m of grey
  armour with rows of lit windows, a stepped superstructure, a tower with sensor
  globes, and twin engine nacelles with a small fifth engine between them, all
  burning long blue flames. Its name is generated.
- **Land in its bay.** The bay opens along its flank behind an energy shield you
  can fly through but not walk out of. Two Remnant interceptors and a frigate
  stand on the bay's pads; the fourth pad is empty. Press **Z** anywhere within
  3 km and your ship flies itself round the hull, in through the bay's mouth and
  down onto the empty pad (Z again takes the stick back). The interceptors are
  flyable, and taking one sounds the alarm.
- **Walk it.** From the bay a long corridor (an armoury and a crew room off it)
  runs aft to a tall shaft by the engines, where six ramps switch back up past
  the reactor's glow to the bridge: a long room with a window wall over the bow,
  crew pits with rows of consoles, a holo table, and the general at the glass.
- **It is held.** Twenty Remnant aboard (troopers walking the bay and the
  corridor, sentries on the gantry and the landings, an honour guard on the
  bridge) and their droids. They shoot on sight, and come aboard as your ship
  closes in.
- **Oda's last job.** After the fleet she sends you up: "Fly a ship to the
  cruiser and kill the general there. You'll have some company on the way up."
  Climbing out, the cruiser's interceptors and fighters meet you (two of the
  port's pilots fly with you); Z by the cruiser breaks the fight off and runs
  for the bay. Kill the general on the bridge: **20,000 cr**, the locals love you
  for it (+60), and Oda's story is done.
- **Then it is yours to visit.** Whoever is left aboard is gone the next time
  you come back, and from then on the cruiser is empty, still there to fly to,
  land in and walk round. Fall out of it and you are pulled back aboard.

## Desert packs: camps, tents, chests, rest, clubs and rocks (2026-10-29, issue #96)

- **Every pack has a camp.** Three hide tents round a firepit that is always lit.
  Each tent is a room you can walk into: a rug, a rock table and rock seats, a
  bedroll and a chest. A pack starts at its camp, stops there on every loop of
  its route, and comes back for the night. Three of each pack never leave it.
- **Chests to loot.** Each holds food, quartz, or what the town's traders and
  fences buy (quantonium, holocrystals, power cells, whale teeth). Get seen
  taking it and a friendly pack turns on you. Chests fill again a few in-game
  hours later.
- **Wreck a camp** by shooting its tents down. It is back a few in-game hours
  later.
- **Rest until morning** in a friendly pack's tent with **Z**: the screen goes
  dark, you heal, it is morning and the game is saved.
- **Real moves instead of text.** Club swings, rock throws (a small, short,
  dark rock), and hand gestures for greeting, trading, thanks, "no food" and a
  truce. The chief only fights hand to hand.
- **No more voices for the packs.** Their yells and gestures show as text, never
  through ElevenLabs, and their entry in the voice profiles is gone ("man_fierce"
  stays in the library as a spare).
- **They walk round boulders and mesas** instead of through them, and round the
  tents and the camp's clutter.
- **Camps sit on level ground.** The sand under each camp is levelled (a pad the
  sand you see, the ground you stand on and the camp all share), so the fire,
  the tents and the people round it no longer sit at odds with a dune's slope.
- **No more falling through the sand.** Walking up to a pack, its people used to
  drop through the ground: they switched on their physics before the sand's
  collider had reached them. They now wait for it.
- **Textures and clutter.** Stitched hide with patches, woven rugs, rough rock,
  wood grain and clay, all drawn in code. Tents have wall posts, roof ribs, a
  painted band, guy ropes and streamers; inside, cushions, pots, a hanging
  lantern and an iron-bound chest. Round the camp: stacks of painted scavenged
  canisters, a woodpile, a drying rack hung with hides, water jars, spears, a
  spit and pot over the fire, logs to sit on, and a ring of stones.
- **Follow-ups filed:** planet-wide sandstorms (#175) and packs stealing
  vehicles (#176).


## Villagers draw pistols; your droids fight beside you (2026-10-29)

- **Villagers carry pistols.** The port's locals (walkers, stall merchants and the
  fence) now hold the same blaster pistol the player uses when they fight back. It
  stays out of sight while the port is calm, comes out the moment their alarm goes
  up, and is put away once they calm down. They used to shoot from empty hands.
- **Your droids help in any fight.** Your assassin droid and now your floating
  droid (a smaller, slower gun) shoot whoever you are fighting: the Remnant as
  before, the port's locals once their alarm is up, and a native pack on the
  attack. A Remnant droid is a target once you shot one, it shot at you, or its
  alarm is up. They never start a fight: nobody calm is shot. Cargo droids still
  carry no gun.
- **What your droids hit counts as yours.** A native your droid kills locks that
  pack hostile, and a local your droid kills costs you standing, as if you had
  fired.
## Remnant interceptor stands down after the fleet, flies wider loops (2026-10-30, issue #180)

- **No chase once the Remnant is beaten.** After the fleet in orbit falls, the
  barracks pad's dark interceptor stays on its pad, even for a stolen outpost ship.
  One already in the air gives up and flies home.
- **Bigger loops at the same speed.** Its pilot (`remnant_hunter.json`) breaks off
  at 140 m instead of 70 m and extends to 650 m instead of 300 m before turning
  back in, so it swings much wider around you. The ship's speeds are unchanged.
## Objective pointer and job log (2026-10-29)

- **Always know what to do next.** A line under the banner says the next thing
  to do ("Find Oda Vell at the cantina, far end of town   84 m"), with an arrow
  turning towards it and a diamond over the place while it is on screen. It
  follows the story chapter by chapter, then whatever job is on: a bounty to
  collect or hunt (the outpost), goods to sell (the fence), a drop to find (the
  drop's area, not the exact spot, so the search is still yours). Lines and
  targets are data (`content/core/story/main.json` "objectives"); the logic is
  `src/systems/flow/objective.gd`, the HUD `src/ui/objective_hud.gd`.
- **A job log on I.** The inventory screen has a JOBS column beside the items:
  the story's current chapter, the smuggling run (what the goods are, where they
  were left), the bounty (who, where, the pay, their crime) and any job taken
  from Oda's board, with runs sold and bounties paid at the bottom.

## Ship fights feel like a shooter (2026-10-30, issue #181)

- **Hit markers for the ship's guns.** The same white X as on foot pops when your
  cannons hurt something: another ship, a trooper or local on the ground (a bolt's
  burst counts too), a parked ship. It turns red and bigger for a kill. In space the
  fight's own hits and kills drive it. Shots a target shrugs off (a parked
  interceptor, a wall) show nothing.
- **A red flash when you are hit.** The edge of the screen glows red, holds for a
  second and fades slowly, in the air and in space. Each new hit lights it again.
- **A flight-sim HUD in the chase view.** The block of numbers in the top left is
  gone. In its place: a pitch ladder round the reticle that rolls with the ship, a
  heading tape, speed and altitude tapes either side, and bars for throttle, the
  Shift ability, hull and shield. It uses your HUD colour.
- **A cockpit in the cockpit view.** V now puts you behind a canopy (two struts,
  the rest faint glass) with a dashboard whose instruments move: airspeed,
  altimeter, an attitude ball, climb, compass, throttle, hull, shield and boost.
  The Shift ability is one lamp, lit while it runs. Every ship
  shares the one cockpit.

## Flying to the moon without a seam (2026-10-29)

- **The switch to the moon's scene is ~4x shorter.** The frame it happened on
  took ~680 ms; it is now ~130 ms, then 55-75 ms for two frames. The port's scene
  is freed a little each frame after it leaves (`SceneReaper`) instead of all at
  once (330 ms). The moon's coarse ball and the home planet's ball in its sky are
  built on worker threads ~1.5 km before the switch (`PlanetTerrain.prewarm_far`,
  `SpaceTravel.prewarm_bodies`). The station's walls and dome are built first and
  its floors, inner panels and lamps a few frames later.
- **The last frame before and the first after look the same.** In space the sky
  takes the parent planet's up in every scene (it had turned to the moon's, which
  put a dark brown "ground" behind it), and every planet's ambient light eases to
  the plain time of day (the station's 1.6x fill had made the moon brighter). The
  moon drawn in the port's sky uses the same noise as its own scene. The HUD's top
  and bottom bars are there on the first frame and keep the old place names until
  the new ones are known; no "Approaching..." toast and no stamina bar in the
  cockpit. The chase camera keeps its view and lag.
- **Nothing you hear stops.** The engine drone is one player that outlives the
  scene, the music plays on (a fight broken off by the switch ends quietly, its
  space track playing until you come down), and arriving above the moon's edge of
  space no longer counts as climbing out (no new orbital fight on arrival).
- `scenes/handoff_trace.gd`: a rendered trace of the switch (frame times, the
  pictures either side and how different they are, the music and the engine).
- **No black, turned frame at the switch.** The new scene's camera blended in
  over ~0.4 s from the on-foot camera, which stands on the town's ground: one
  frame of the town at a tilt, then a few of black sky. A handoff now puts the
  camera straight onto the chase view it carried (`CameraRigNode.snap_override`),
  with the flight read-out filled in on that same frame and the footer's HP,
  stamina and fuel kept until the new scene's body and gear are built.
- **The way home is ~40% shorter.** The port's first frame on arrival went from
  ~335 ms to ~205 ms: its rocks (mesas, hoodoos, boulders and their colliders),
  the moon's ball in its sky and the town's cover spots are made once a session
  and reused, since the port was already built before you left. Four garrisons
  each working out the same 56 ms of cover spots in one frame (a 240 ms spike a
  second after arrival) now share one list.
- The trace flies there and back, and keeps every frame drawn around each switch.

## Smooth orbit over the port; no "edge of space" (2026-10-29)

- **No more stutter flying high.** Climbing past ~2 km and on toward the moon
  ran at ~150 ms a frame whenever the Remnant's interceptor was up hunting you.
  Its ground checks (and your ship's) scanned every box, mesa and boulder in the
  desert from that high, and 60 Hz physics fell behind. The ground lookup now
  also skips anything not under the line it measures along, with the same
  answers as before. Orbit runs at ~10 ms a frame, none over 25 ms.
- **Space is just the sky.** The HUD's "EDGE OF SPACE" bar, the "In orbit"
  toast and the music switching to the space track at 4,000 m are gone; the sky
  darkens as you climb and that is all. The space track now plays during a fight
  in orbit. Climbing out still starts the pad's orbital fight.
- `scenes/orbit_trace.gd`: a rendered trace from the pad to the moon handoff,
  frame times by altitude.

## Sand nomad heads for the native packs (2026-10-29)

- **The dune nomads wear a new sand head.** It is the same freaky beaked goggle mask
  as before, remade with Hyper3D: a sand cloth hood and a matte bone mask instead
  of the teal hood and brass. Every pack uses it; leaders still wear the helmet.
- **Three variations for later NPCs:** `nomad_crest`, `nomad_maw` and `nomad_horn`,
  each in its own sand and bone tones. No pack uses them yet.
- **All four are in the character builder** (F11, Character, Head).
- The snow planets' frost folk keep the goggle head in their cold colours.

## Cantina owner's hood tufts go with her helmet (2026-10-29)

- **A clean hood under any head.** Two small dark tufts on the rim of the cantina
  owner's hood, once hidden behind her breathing hoses, stuck out in front of her
  shoulders whenever she wore another head. They now belong to her helmet piece, where
  the hoses still cover them, so her own look is unchanged.

## Voices cleanup: a voice library, Skrugs and T-89 recast (2026-10-29, issue #164)

- **Voice library.** `content/core/npcs/voice_library.json` lists every ElevenLabs
  voice the game can use, keyed by how it sounds ("Man (goofy)", "Robot (male)",
  "Woman (sultry)"), with its voice ID, ElevenLabs name and stability. Spare
  voices are in it too, ready for new NPCs. `voice_profiles.json` now names
  library voices instead of holding raw IDs.
- **Skrugs is a goofy man** (Dr. Quibble), not the woman's voice he had.
  **T-89 has a real robot voice** (Sigma Centauri). Its old ID had been quietly
  remapped by ElevenLabs to the same voice as the mechanic.
- **The Odas on other planets sound like women again.** They had fallen through
  to the male default. Each one picks from four women's voices by planet.
- **Recast where the old fallback voice was used:** the mechanic sounds southern
  and warm (Wade). Troopers on outposts, towers and the yard use the gate guards'
  two voices. Desert natives sound fierce (Harry), the fence and the bounty
  officer shady (Callum), and stall merchants laid-back (Roger). Villagers draw
  from a wider mix of five men's and women's voices.
- **Oda and the gate guards are unchanged.**
- **Canned lines are generated once.** Villager barks, the mechanic's menus and
  T-89's tutorial always render at normal speed, so their cached clips no longer
  depend on the speech-speed slider. Moving the slider no longer regenerates
  them. The slider now changes only live conversation lines.

## The energy saber, redrawn (2026-10-29)

- **A glowing staff on a metal hilt.** The energy sword's forged spine and brass
  crossguard are gone: the blade is a straight, round staff of light (a white-hot
  core, a coloured shell, a soft halo) out of a Hyper3D hilt. The blade is still
  drawn in code, so it ignites, recolours, lights the room and hits as before.
- **Blue on light metal by default.** The player's and the duelist's blade is blue
  now (was yellow), on a brushed-silver hilt.
- **The red saber is red on black metal.** Owning the saber from the wreck turns
  the blade red and swaps in a blackened gunmetal hilt with a red stud. The pickup
  in the wreck uses the same hilt, and now lies flat with its blade in the emitter
  (its parts were turned in radians read as degrees).

## Dogfights in the port's sky (2026-10-29, issue #76 part 3)

- **The outposts' ships are the Remnant's, and you can fly them.** The near
  outpost keeps a dark interceptor, the other two a dark freighter (the port's
  models painted dark: textured ones through the dark-gun shader, the flat-colour
  interceptor by hand, accents in oxblood). Each is a berth like the pit's ships.
  Climbing into one sets off that outpost's alarm. If it goes down (shot or
  crashed) it is gone and you wake in the pit.
- **The barracks has a landing pad with a dark interceptor on it.** It takes off
  after you when you fly a stolen ship, or when the Remnant wants you (the
  garrison's alarm, a hostile standing, or the fleet is beaten) and you are
  300 m out past the town.
- **It fights like the space fighters.** Same AI pilot (pursue, attack, break,
  extend), guns, shield and hull as the space dogfights, flying with your ship's
  atmosphere flight. It pulls up near the ground and stays under the edge of
  space. Nothing to chase for 10 s and it flies home and lands on its pad.
- **Shot down, a new one is on the pad two minutes later.** If it shoots you
  down, you both start again in town: you in the pit, it on its pad.
- **Your flight HUD boxes it** like a space target: a box, its hull, the range,
  the lead dot to aim at, and an arrow when it is off screen.
## Villagers join the character kit; collar and hoses on the right pieces (2026-10-29)

- **Villagers are kit pieces now.** The villager outfit (scarf head, linen shirt,
  trousers) is fitted onto the shared base body and cut at the same seams as the
  player, guard and cantina owner, from its existing rigged model, with no new
  Hyper3D generation. Its head, upper and lower body show in the character builder
  (F11, Character) and mix with any other piece. Villagers still get a random
  colour per part from the same six colourways.
- **The player's jacket keeps its collar.** The stand-up collar ring had been cut
  onto the head piece; it now belongs to the upper body. The bandana's chin stays
  on the head.
- **The cantina owner's breathing hoses are on her helmet**, not her upper body,
  so her tunic goes cleanly under any head and the hoses come with her mask.
- `fit_parts.gd` dress `move` can now pick triangles by region (`below`, `box`) or
  by a saturation/value ceiling (`max_sv`), and can `copy` instead of move; `hue`
  is optional.

## Fewer hitches after a planet handoff (2026-10-29, issue #162)

- **Troopers no longer reload their rifle from disk.** Each trooper loaded
  `rifle.glb` twice with nothing keeping it, about 78 ms per trooper. The rifle
  and a droid's carried weapon now come from `ModelCache`.
- **Outfit textures are shared and loaded ahead of time.** Every NPC has its own
  `CharacterKit`, so the "shared" outfit materials were really per body, and each
  new colour read a 2048² texture on the main thread (35-110 ms). The materials
  are now shared by every kit. A first-frame step, `warm_outfits`, starts all 25
  colour textures loading on worker threads (`ModelCache.prefetch`).
- **Outposts build one piece a frame:** the ground, the nav, the look, the ship
  and each trooper, instead of a whole outpost (about 55 ms) at once.
- Worst staged frame after a handoff, look on, headless: to the station 129.5 →
  14.7 ms, home 100.1 → 26.5 ms. Staged total: 517 → 81 ms and 1078 → 444 ms.

## Smoother terrain uploads in flight (2026-10-29, issue #123)

- **Ground meshes no longer pile up on one frame.** When the sand under the
  player and the wider ring around the camera finish building at the same time,
  they now go onto the graphics card one per frame (near first) instead of
  together. A small per-frame budget (`mesh_upload_budget_ms`, 2 ms) lets both
  through at once when they are cheap.
- **No wasted rebuilds.** A finished mesh waiting for its turn counts as the
  current one, so the terrain never starts a second build of the same ring.
- The trace snapshot gains `ready_terrain_meshes` and
  `main_thread_mesh_upload_worst_frame_ms`.

## Station smuggling (2026-10-29)

- **The asteroid has its own smuggling loop.** The station's Oda offers a run
  that belongs to `grit_station_town`: the drop lands on the open rock outside
  the sealed station, and the merchant in front of the cantina buys it. The
  port's run stays at the port, gated by the port's story.
- **Smuggling jobs are per town.** The board filters a `kind: "smuggle"` job by
  its `location`, so home and station cannot offer each other's drops. The drop
  data lives in `content/core/pickups/<town_id>.json`.
- **Rock drops sit on the rock.** Drop areas can set `surface: true` to use the
  terrain height exactly instead of the old "never below the marker" floor.
- **A station merchant with a fence's rates.** The existing merchant by the
  cantina buys contraband; bounty payouts stay at the port's fence. The station
  drops are marked with a beacon because they are far out on the rock.

## Walk, run and sprint (2026-10-29, issue #133)

- **Walk:** tap a move key and you take 4 natural steps, then stop. Tap again to
  keep walking. The walk has a longer, calmer stride (heel first, loose arms).
- **Run:** hold a move key past 0.4 s to run at 7 m/s (the old Shift sprint
  speed), with a light jogging bounce.
- **Sprint:** Shift + move sprints at 10 m/s with a hard lean and pumping arms.
  The gun drops, nothing fires or swings, and it spends the same STA stamina as
  the blade (5 s from full). Run dry and you fall back to the run until the bar
  is back to 25.
- Slides still start from the run or the sprint. Guards and NPCs use the same
  three gait animations at their own speeds.
## The crash site: speeder jumps, an interior to fight through (2026-10-29, issue #148)

- **Speeder jump.** A bent hull plate stands on a brace beside the boarding plate.
  Ride up it toward the stern and you fly off the end. A speeder can also ride up
  the boarding plate into the hold and up the hold's sloping deck.
- **A level interior.** The hold climbs to a large interior deck high in the
  stern. Its floor is level with the horizon, not tilted with the hull. To reach
  it, walk up the starboard side of the hold and step onto the deck at its
  stern end.
- **The bridge.** A ramp climbs from the interior deck through torn dorsal
  plating to a level bridge platform on struts, with the bridge house at its bow
  end. It stands about 150 m over the dunes. The old solid bridge block and one
  radiator fin are gone to make room for it.
- **Ramps and broken railings.** A second ramp joins the interior deck to the
  stern end of the upper gallery. Railings line the open edges, with some panels
  missing and some sagging.
- **All of it is the ship's metal.** Every new plate wears the wreck's metal
  shader.
- **The Remnant aboard.** An assassin droid patrols the bridge. An assassin
  droid and a floating droid patrol the interior, and a floating droid patrols
  the hold. They shoot on sight. Nothing out there sets off the town's alarm.
  A destroyed one comes back after 3 minutes.
- **A red energy saber.** An old cargo droid in the deep hold carries it on its
  back. Press E beside it to take the saber. Owning it turns your energy sword
  red.
- The droids, their routes and the hauler are data: `content/core/droids/droids.json`
  ("wreck"). The geometry is in `src/systems/world/starcruiser_wreck.gd`.
- The plates you ride or walk on are ground, not obstacles. A speeder no longer
  catches the plate it is riding on as it climbs.
- Tests: `tests/test_crash_site.gut.gd`. `tools/review/wreck_probe.gd` still
  passes. The full CI suite was not run.
## Smooth on foot again (2026-10-29)

- **Walking near the dune packs no longer drops the game to a crawl.** Every
  sand pig and every far-off pack member asked the ground "how high am I?" each
  physics tick, and each answer checked all 1164 town boxes and 386 boulders.
  Near a pack a physics tick took longer than its 16 ms budget, so the game ran
  several ticks a frame and fell to 5 to 28 fps. The ground now only checks
  what is near (same answers, about 100 times faster), and far-off packs and
  pigs move every fourth tick (same speed). A tick by a pack went from 14-22 ms
  to about 4 ms.
- **Characters move as smoothly as the screen draws.** The game now draws at
  120 fps on a 120 Hz screen but physics ticks at 60, so you, the camera and the
  people moved in steps, and turning the mouse swung your body for a frame and
  snapped it back. The camera, your body and nearby people are now drawn
  between ticks.

## Staged planet handoffs (2026-10-29, issue #121)

- **Flying from the port to the station (and back) no longer freezes for the
  whole build.** The other planet's scene now shows up with just what the ship
  needs on its first frame: the planet, its sky, the town's boxes, the player,
  the camera and the ship, flying on exactly where it was. Everything else (the
  people, the bar, the gear, the HUD, the full-detail ground) is built over the
  next frames, a little each frame.
- In the headless trace the first frame of a handoff went from 1.6 s (to the
  station) and 2.3 s (home) to under 0.1 s. With the look on, it went from 6.3 s
  to 0.34 s (station) and from 12.8 s to 1.0 s (port).
- The ship keeps its place, heading, speed and throttle, and stays under your
  control while the rest is built.
- The planet's far ground starts coarse and sharpens over about a second, with
  no holes. People built while you are still high up stay hidden until you come
  down.
- Works the same for any generated planet: nothing in it is about the port or
  the station.
- `staged_handoff = false` on the town scene builds it all at once, as before.

## Desert packs and sand pigs, first milestone (2026-10-28, issue #96)

- **The dune people** now live on the home planet: one primitive people,
  travelling on foot in packs.
  - **The two packs:** the friendly Red Wind (12) and the hostile Bone Teeth
    (10), each with two children (the same bodies at 60%, who fight too).
  - **Their look:** they wear the existing kit pieces (Goggles head, Cantina
    Owner upper body, Player legs) in each pack's own sun-faded colours. The
    leader wears the helmet and carries a tall pole with a rag on it, so you can
    see a pack coming.
  - **Weapons:** clubs, spears and knives up close; throwing sticks and light
    spears from 5 to 18 m. No rifles.
  - They yell; they do not speak the port's language.
- **Food for quartz:**
  - Buy food at the new food stall in the market. It never runs out.
  - A friendly pack's leader comes over and gestures. Press E to gesture back:
    one food for one quartz, or two from an adults-only pack.
  - The stall buys quartz back for 22 cr.
  - Reputation is per pack, and the Remnant has nothing to do with it.
- **Hostile packs:**
  - They blow a battle horn and come at you on sight, and fight to the last.
    They will chase your speeder on foot.
  - Survive 5 minutes without killing any of them (and without being downed)
    and they stop, offer trade, and stay friendly.
  - Kill one and that pack is hostile for good.
- **Sand pigs:** eight roam the desert alone and bolt when shot or run at. Kill
  one, then press E at the carcass for 2 food.
- **Every planet can have its own:** the planet generator gives each planet its
  native people and animals, like everything else.
  - Sand, red-desert and snow types each make a people of their own, with its
    own name and pack colours, plus the type's animals.
  - Water, lava, gas and the asteroid have none.
  - Data lives in `content/core/species/`, `content/core/fauna/`, and the
    `natives` blocks in the planet and type files. See
    `docs/natives/NATIVES.md`.
- **Not yet:** camps, tents, resting, stealing, packs fighting each other or the
  Remnant, sandstorms, and stealing vehicles.
## Speeder merchant improvements (2026-10-28, issue #100)

- **Dorrin's yard is dressed up:**
  - a striped awning with a string of bulbs over his counter, with parts and a
    lamp on it;
  - a tool bench with a vise and a pegboard of tools;
  - crates by the garage door, and fuel and coolant canisters lying about, some
    knocked over.
- **Droids at the yard:** three cargo droids drive loops round it, and an
  assassin droid with no weapon stands by the garage door.
- **The Grav Lifter keeps your momentum.** For 2 s after Space, gravity and
  any downward speed are off, so whatever is going up keeps going up. Lift into
  a ramp or a dune face and the slope's climb is added: you ride up it and
  launch off the top. Lift while already climbing and you keep that climb.
  Horizontal speed carries through the air as before.
- **Boosters and the soft-top stay on.**
  - The soft-top now folds back behind the seat while you ride, still in
    sight; before, it folded into the body and vanished.
  - The boosters sit out past the tail.
     - Getting in rebuilds any looks part that has gone missing.

## Mesa shapes (issue #93)

- Kept the mesas' existing size and rock material, but replaced the regular
  cylinder profile with broad, uneven plateaus, stepped cliff shelves and
  restrained erosion gullies. The mesh remains inside the existing world-ground
  collision envelope; hoodoos are unchanged.
- Added a focused geometry check for the plateau-to-base ratio, collision bounds
  and silhouette detail. The full CI suite was not run.

## The asteroid, done properly: a real ball, a sealed station, no cutaway (2026-10-28, issue #99)

- **One map.** Flying from the home planet to the asteroid has no fade and no
  cut. The asteroid hangs in the port's sky as its real ball, in its own rock,
  with its station on top. Come within 2.6 km of its surface and its scene takes
  over in mid-flight: same spot, heading, speed, sun and stars, with more detail
  coming in. Fly straight down to the town, or press Z. Leaving works the same
  way back. Every planet's scene is now the same space shifted to its own port,
  so the planets sit exactly where each other's skies show them.
- **The asteroid is a real ball** (3 km across), built like the home planet. Its
  grey, blocky moon rock is cratered all the way round (three sizes of crater),
  gravity points to its centre, and you can fly and walk all the way round it.
  Blocky boulders lie on the rock near the station.
- **The station is sealed** (the locals cannot breathe outside):
  - a round wall round the town, with the glass dome rising from its top;
  - a transparent energy shield in the gate;
  - a covered hallway with wide windows, a roof, and lights along its ceiling. It
    runs from the gate through a door in the landing pit's tall round liner, then
    down over the pit's ramp to a round energy shield onto the pit floor;
  - an energy shield over the top of the pit, which ships fly through.
- The pit has one way in now: the far ramp is gone.
- `./tools/planets/shoot_planets.sh` has new stills: the station, the hallway,
  the pit, the rock, the ball, and each planet seen from the other.
## Walkable starcruiser wreck (issue #93, wreck only)

- A 600 m ribbed transport lies nose-down far beyond the starting town's front
  gate (map 1350, -120). Its bow is buried; the raised stern, radiator
  comb and four dead engines form a landmark above the dunes.
- A huge tear in the town-facing flank exposes the hold. A fallen hull plate
  leads from the sand onto a continuous lower deck; small salvage boxes and
  door frames give it human scale. No NPCs, loot or missions are added.
- Plates, decks and ribs share their visible geometry with player collision
  and the ship/speeder ground model. The breach is genuinely open, not a painted
  hole on a solid box.
- `tools/review/wreck_probe.gd` is a standalone, wreck-only collision/landing
  check with optional screenshots. The CI suite was not run for this change.
- Visual refinement: wreck-only scorched/chipped metal, irregular pointed
  fracture plates around the breach, and layered engine collars, vents, braces
  and recessed dark throats. Engines remain unpowered (no emission or exhaust).
  Hull dimensions, placement, boarding plate and lower deck are unchanged.

## Speeder upgrades at the mechanic's yard (2026-10-28, issue #95)

- **Dorrin Vask's yard** is out in the desert, about a 30 second drive from the
  back gate: a garage, a workbench, a scrap heap and a lift. Park your speeder
  on the lift and press E beside Dorrin.
- **Paint:** steel, tide blue, crimson, or the Remnant's black and red.
- **Looks:** turbo boosters on the back that flare when you boost, and a
  convertible soft-top that is up when parked and folds back when you ride.
- **Performance, two tiers each:** engine (top speed), thrusters (acceleration)
  and cannons (laser damage). Tier 2 needs tier 1.
- **Grav Lifter** (900 cr, the most expensive part): press Space while riding
  to hop off the ground, then hang in the air for about a second; drive off a
  hill and you float. It recharges in 4 seconds. With it fitted, Space lifts and
  the left mouse button fires.
- **Sell for scrap:** Dorrin pays 35 cr plus a quarter of what you spent on
  its parts.
- Each speeder keeps its own paint and parts, saved with the world.

## Character animations (2026-10-28, issue #87)

- **Walking has some swagger.** The hips roll and shift over the planted foot,
  the shoulders twist against them and the arms swing looser, so nobody marches
  like a robot. Standing still, people shift their weight and glance around.
- **Sprinting looks like sprinting:** leaned forward, longer and slower strides,
  a high back kick and arms pumping with bent elbows.
- **Jumps** tuck the knees on the way up, reach for the ground with arms out on
  the way down, and split into a leap when you jump at a run.
- **Crouching** drops to one knee when still and duck-walks low on bent knees
  when moving.
- **Guns rest when nobody is shooting.** Guards carry the rifle low across the
  body, muzzle down, and raise it to the shoulder before they fire (they cannot
  shoot until it is up). They lower it a few seconds after the fight goes quiet.
  In third person the player does the same: a rifle across the body, a pistol
  pointed down by the right thigh in one hand. Pressing fire or aim raises it in
  a fraction of a second, and you can walk while aiming. Hands stay on the grips
  the whole way. First person is unchanged.
- **Speeders and ships react when you get in:** they sink under your weight,
  then lift with a short engine shudder and settle.
- `./tools/anim/shoot_poses.sh` renders a sheet of every pose
  (`archetype=player` for the player's guns) to `test_results/anim/poses.png`.
## Planet generation cleanup: the asteroid, and what every planet has (2026-10-27, issue #75)

- **The asteroid is a whole rock ball**, 900 m across, grey like the moon, with
  big and small craters, rough ground and blocky boulders. The station sits on
  top of it, under a **glass dome** with a shielded door over the gate, and the
  port's own **round landing pit** is outside the gate. You can walk out onto the
  rock and keep going until it is too steep; slide off the side and you wake by
  the bay.
- **Z lands you in the bay.** Flying near your bay on any planet (home too),
  press Z and the ship flies itself over the pad and sets down on it. Z again
  takes control back.
- **Every generated planet now has:**
  - its merchants' stalls in front of the cantina;
  - at least three locals walking the street, who fight back like every local;
  - a stage in the cantina;
  - its own Oda: a new iteration with a generated last name, the planet's name in
    her prompt, and her own brain, memory and save entry;
  - smuggling runs and contracts on Remnant officers, always on her board.
- **The port's Remnant outposts** no longer appear on other planets.
- Ilka Vell, the station's old hand-written owner, is gone; the station has its
  own Oda now.
## Bug fixes: droids, sounds, one settings panel, one health bar (2026-10-27, issue #80)

- **Droids bought from the merchant** now come out from behind the stall and
  walk round it to you, instead of appearing at your feet.
- **The practice droid in the pit** is built from the same model as the
  floating droid you can take on, so taking it is seamless: it keeps its look,
  height and facing instead of being swapped for another one.
- **Floating droids fall when they die**, dropping to the ground and tipping
  over, instead of appearing on the floor.
- **Floating droids' hitboxes are bigger** (0.55 m, from droids.json) and bob
  with the droid.
- **The alarm** is quieter and a saw-wave "beep beep beep, pause".
- **Music** cuts into and out of battle music straight away (0.25 s).
- **Droids chirp more often** (floating droids every 2 to 5 s).
- **The AI settings are a tab ("LLM") in the F11 settings panel**; F10 opens
  that tab. The cursor now shows on every settings tab.
- **One health bar**: the red bar that sat over the HUD's own is gone (it only
  shows in the greybox, where there is no HUD).

## Atlantium Sand-boxer speeders (2026-10-27, issue #82)

- **A new speeder, the Atlantium Sand-boxer**, replaces the Curlew: a wide,
  flat, wedge-shaped hover car (DeLorean meets Cybertruck) with hover pads in
  the wheel wells, a plasma-core engine deck with twin exhausts, and twin
  blasters under the headlights, where the lasers now fire from. Same handling
  and specs; it is 5 m long and 2.7 m wide.
- **Four paint jobs** on the one Hyper3D model: bare steel, green and blue,
  crimson and white, and the Remnant's black and red (with a red core).
  Skrugs's display model is crimson; each speeder you buy comes in the next
  colour (steel, green and blue, crimson).
- **The Remnant park a black and red one outside the front gate**, off the gate
  lane, while they hold the town. It is theirs: you cannot ride it.
- **Its hitbox is its shape**: bolts hit the body (cabin included) and miss
  over the roof, instead of a flat 1 m box.
- Buying one no longer loads a model on the spot: the paints load in the
  background when the stall is built.
- **Guards carry the rendered rifle**, the same dark, scoped Hyper3D rifle the
  player uses, instead of the boxy one.
- Review sheet: `docs/lookdev/vehicles/03_sandboxer.png`. Paint jobs are
  `paint` in `content/look/vehicle_models.json` (prepped by
  `tools/look/prep_vehicle.gd`).

## New character art: player, guards, cantina owner (2026-10-27, issue #79)

- **Three new outfits from the concept art**, made the way the locals are: one
  model each, cut into head, upper body and lower body at the same seams, so any
  piece goes with any other. Faces are fully covered.
- **Player:** dark leather jacket, cream undershirt, khaki cargo trousers, masked
  face with glowing cyan goggles and a hat with a cyan band.
- **Guards:** slim gunmetal armour with red shoulders and chest, a red eye slit and
  a ragged red half-cape. Troopers wear it grey, commanders in oxblood.
- **Cantina owner:** pilot helmet, breathing mask and yellow visor, a yellow
  hooded tunic over a leather jacket, tight leather trousers and boots. She now
  wears kit pieces too, and stands at the player's height (1.94 m, was 1.74).
- **Jetpacks are grey and black,** no orange bands or lamp.
- **Colours:** player rust (red cargo pants, rust hat band), sand, olive, dusk; guard gunmetal, oxblood, desert,
  navy, black; owner teal, madder, slate, sand. All show up in the character
  builder (F11 > Character).
- Review sheets in `docs/kit/`; prompts and picks in `docs/kit/HYPER3D_PROMPTS.md`.

## Shooter feel (2026-10-27, issue #65)

- **Aim down the sights.** Right-click in first person brings the gun's own
  sights onto the crosshair, worked out from the camera so it holds at any
  angle. Pistol: iron sights (front post, rear notch), 1.25x. Rifle: a scope with
  clear glass and a lit reticle, 2.5x (twice the pistol). The crosshair hides
  while aimed in. Third person keeps the shoulder view with the same zoom.
- **Dark guns.** Both blasters render dark, keeping their texture detail and
  glow panels (`dark` in `content/look/hand_weapons.json`).
- **Slide.** Crouch while sprinting slides (1.35x sprint, 0.75 s), then you
  stand back up even with crouch held, so sprint, slide, sprint flows. The eye
  drops and tilts a little. Guards never slide.
- **Hit markers.** Any damage you deal flashes four ticks round the crosshair
  with a thud; a kill is red, bigger and heavier.
- **Health bars, not names.** Enemies (fighting you, or hurt) show a health bar
  over their head within 40 m. Floating names are gone.
- **First person arms.** Black sleeves and black gloves with fingers that curl
  round the grip, for every outfit.

## Bigger, adjustable text (2026-10-27, issue #71)

- **One number sizes every UI element.** `text_scale` (default 1.25, from
  `content/look/ui.json`) is the window's UI scale. Every panel, label, prompt,
  box and HUD read-out grows with it, and layouts keep their shape.
- **F11 > HUD > Text size:** a slider from 75% to 200%, plus a Default button. It
  applies live and is saved per machine with the HUD colour.
- **The worst offenders start bigger:** the dialogue box (her lines, history, your
  field), the job box, the ship's flight read-out, toasts and edge-of-space gauge,
  the space-fight read-out and the speeder read-out. Their base sizes are in
  `content/look/ui.json` too.
- Headless traces and tests keep the UI at 1.0, so their measurements are
  unchanged.

## P1 — Planet generator, the town style kit, and a second planet (2026-10-27, issue #45)

What works now:
- **A planet is one config file.** `content/core/planets/<id>.json` gives a
  name, a type, a town size from 1 to 100, a style, and where it hangs in another
  planet's sky. The generator builds the rest. `docs/planets/PLANETS.md` is the
  whole how-to: a contributor (or an agent) adds a planet with no code.
- **Towns of any size.** Size 50 is the port's scale, 100 is 5x its area, and size
  1 is a cantina, one Remnant guard at its door, a merchant out back, and a landing
  bay. Bigger towns add a market, barracks, a watchtower, more bays, guards, houses,
  towers and residents strolling the lanes. Every size from 1 to 100 passes the
  town validator, and the decor, bar, guards, locals and ship work unchanged.
- **Seven planet types.**
  - Biome planets: sand (the port), snow (white dunes, grey-blue rocks), red
    desert.
  - Element planets (water, lava, gas) and the asteroid station: the town floats
    on a deck closed underneath.
  - On a deck, a glass enclosure rises from the walls, solid to people and ships
    and open above. An energy shield fills the open gate; you walk straight
    through it. Below is a sea, a lava lake, cloud decks, or the asteroid's own
    rock with debris drifting round it. Go over the edge and you wake up by the
    landing bay.
  - Each type has its own sky over every time of day; the asteroid's is grey.
- **The town style kit.** `desert` (the port, unchanged), `metallic`, `snowy`,
  `pastel`, or plain words like `red matte metal` or
  `pale blue glossy ceramic with gold trim`. One line restyles every wall, slab,
  trim, prop and awning. The words are in `content/look/town_styles.json`.
- **Grit Station, a second planet you can fly to.** An asteroid with a size-1
  town in `metallic`, hanging in the port's sky 12 km away and 5 km up:
  - Climb out of the atmosphere and fly into it. A marker in space names it and
    gives its distance.
  - You arrive in its grey sky, still flying the same ship, above its bay. Land,
    get out, and visit its cantina.
  - Fly into the port's planet in its sky to go home.
- **Ilka Vell runs the station's cantina.** She is Oda's younger sister, on her
  own AI card with her own drinks, secrets and voice. She wears Oda's model
  re-tinted steel-blue with cyan goggles, and her briefing names the station.
- Town names fit the place. Stations are named like "Grit Hold" and floating towns
  like "Brine Quay"; new name grammars were added to the name engine.

How to see it:
- Run the town, take off (Space, R), climb past 4 km and fly at the grey rock
  marked "◇ <name>".
- `./tools/planets/shoot_planets.sh` renders the station, the styles, every type
  and sizes 10, 50 and 100 to `test_results/planets/`. The current ones are in
  `docs/planets/`.
- `./scripts/ci.sh` adds two things:
  - `test_planets`: every size, every type, the style parser, the station, a new
    planet from a config.
  - `test_planets_trace`, backed by `scenes/planets_trace.gd`: the whole trip.
## Droids that act like droids, the pit hauler, ship guns on the ground (2026-10-27, issue #64)

- **Assassin droids keep the shuffle for quiet moments.** The idle's little dance plays when one wakes up or stands about. In a fight it holds its ready stance and shoots.
- **Followers are not puppets.** Two droids of the same kind no longer share a spot. Each takes its own place in a fan behind you, drifts a little, reacts a beat later or sooner, walks at its own pace and keeps a body's width from the others. Floating droids hover at different heights.
- **Bigger cargo droids** (1.3 times the size; `scale` in `droids.json`).
- **The pit hauler.** An old cargo droid roams the landing pit, like T-89, with the jetpack strapped to its back. Walk up and take it with [E]. Oda knows about it as a rumor until someone does.
- **Ship guns hit people on the ground.** In the atmosphere a cannon bolt bursts where it lands (on the sand too), hurting everyone within 3.5 m.
- **Parked ships can be shot to pieces** by another ship's guns. A destroyed ship blows up, can't be boarded and never comes back (the save remembers). A ship bought from T-89 that gets destroyed frees his pad.
- Remnant standing stays permanent: killing them has lasting consequences.

## Story fixes: the pit droid step, one drop at a time, speeder lasers, calmer alarms (2026-10-27, issue #64)

- **The game launches again.** A bolt whose shooter had already been removed (a droid that respawned, a trooper who left town) stopped the game when it tested the shooter. Bolts now forget a shooter that is gone.
- **Oda's practice is just practice.** She sends you to the range; going down to the pit is enough (honour system). When you come back she pays 40 cr for the practice and tells you about the sparring droid: block five of its shots in a row and it follows you. That step is optional: go to the pit and come back, and she gives you the first smuggling run.
- **One loot box at a time.** A run only counts if Oda gave it to you in that chapter, so contraband picked up early no longer skips a run. The loose contraband cache outside the gate only appears in free play, while no drop of Oda's is out and you carry none. A save from before the story drops its old smuggling drop.
- **Drops in town are marked.** A drop in the alleys or on a roof has a tall orange beam of light and a glowing ring. Drops out in the sand are still hidden.
- **Speeder lasers kill.** The two barrels fired straight ahead, either side of the nose, so the bolts passed either side of anyone in front of you. Both now converge on whatever the nose points at.
- **Your droid never shoots you.** Its bolts fly through you.
- **Wrecked droids turn up more often** in the desert: a check every 2 minutes at 60%, about one every 3 to 4 minutes (was every 5 minutes at 40%).
- **Calmer alarms.** Each desert outpost has its own garrison and alarm, so a fight out there (every bounty) no longer puts the whole town on alert, turns the town's droids hostile, or sends the barracks troopers running. A dead trooper comes back only once the alarm is over, as a new face that does not remember you.

## The main story line and three Remnant outposts (2026-10-27, issue #64)

- **A main quest.** T-89 in the pit sends you to Oda. Oda sends you to the practice range (knock all five targets down), then gives you two smuggling runs. On the first one she lends you her old jetpack if she is amused or warm. Then she tells you about Skrugs's speeders and a bounty on a Remnant officer at a desert outpost. Kill the officer and the fence in the market pays the bounty.
- **The Remnant fleet.** After the bounty, Oda tells you about a Remnant fleet in orbit, and the port's ships unlock ("the pilots leave their keys in them"). Until then, boarding a ship says it is locked. Win the space fight and you get 5000 credits.
- **After the fleet.** The garrison leaves town. What is left of the Remnant holds the desert outposts and shoots on sight. Oda keeps offering smuggling runs and bounty contracts on repeat. Each contract names a red Remnant officer and their crime and puts them at one of the outposts. Kill them, then collect a big payout from the fence.
- **Three Remnant outposts** out the front gate, near (about 150 m), mid (about 360 m) and far (about 620 m). Each has one dark grey, black and red building, a parked cargo ship, two troopers and an assassin droid. Each is a little different: the building's size, the ship, a comms mast, a lookout tower. Dead troopers and droids come back after 3 minutes.
- **Respawns in town.** Until the fleet is beaten, a Remnant trooper or droid killed in town comes back behind the barracks a minute later and walks back to its post.
- **Reset story** (F11, Story tab). Starts again from the beginning: credits, gear, droids, the bought ship, flags, standing and what every character thinks of you. Names are kept. The Story tab also shows the current chapter and can skip to any chapter.
- Story text lives in `content/core/story/main.json`; the code is `src/systems/flow/story.gd` and `src/systems/world/remnant_outposts.gd`. New tests are in `tests/test_story.gut.gd`.

## Gear and droid models, ragdoll deaths (2026-10-27, issue #25)

- **New Hyper3D models** (prompts written against `docs/ART_DIRECTION.md`, kept in `docs/items/HYPER3D_PROMPTS.md`):
  - **Pistol:** a chunky gunmetal blaster with copper and orange trim, in place of the Kenney blaster.
  - **Rifle:** a chunky gunmetal energy rifle with red panels, in place of the Kenney repeater. First and third person.
  - **Jetpack:** a heavy yellow pack with twin tanks. The flames still burn from under its nozzles.
  - **Cargo cases (the smuggling loot):** one strapped trunk model, stretched to each cargo's size and tinted to its colour, with its glowing status strip.
  - **Floating droid:** a white dome with one big lens on four little legs.
  - **Cargo droid:** a boxy hauler on two tank treads, with goggle eyes.
  - **Assassin droid:** a tall plated humanoid with a visor and a pistol in its right hand.
  - **The assassin droid carries a real pistol.** The gun the generator fused into its hand is cut away in prep, and it holds the new blaster pistol model on its hand bone. **T-89** in the pit now uses the same model, with empty hands and a relaxed idle.
  - **The assassin droid walks.** Hyper3D rigged it with walk, run, idle and death clips: it walks or runs to keep up, stands ready when still, and falls backward when destroyed.
  - Every droid variant tints its model (rust, black, tan, olive, blue, bone, gunmetal, copper) and keeps its glowing eyes, which still go dark when it breaks.
- **Droids follow more calmly.** A droid holds its ground until you are a few metres away (`follow.leash`: floating 4 m, cargo 5 m, assassin 6 m), then walks to its spot beside or behind you and stops. It no longer shuffles every time you move.
- **The energy sword stays code-built.** It is already the laser sword (an igniting yellow blade over a forged spine with a brass guard). Four Hyper3D attempts could not hold a long, thin sword together.
- **Ragdoll deaths.** Troopers and locals no longer tip over like a plank. They crumple: knees buckle, the body falls away from whoever landed the killing shot, rolls to a stop on the sand and rests. The rifle flies out of their hands and clatters to the ground. The player does the same when knocked out at the gate, and stands back up in the pit.
- Tuning in `content/look/ragdoll.json`; model placement in `content/look/gear_models.json` (prep: `tools/look/prep_gear.gd`) and each droid kind's `look` in `content/core/droids/droids.json`.
- Review stills: `docs/lookdev/gear/` (`05_droids.png`, `06_ragdoll.png`, `08_items.png`). Tests: test_ragdoll.

## T-89, the ship salesman, and the empty pad (2026-10-27, issue #58)

- **An empty landing pad in the pit.** The courier's bay is now a bare round pad inside its painted ring. The round freighter and the gunship stay parked; the courier is still for sale.
- **T-89** stands in the pit near where you start: a droid on the assassin droid's frame, but with no gun, and nothing hurts him. Every time the game starts he says a quick hello and offers the tutorial.
- **The tutorial** is nine short pages: walking, your weapons (you already carry them; he explains them), blocking bolts with the blade, holstering at the gate, E and the gear keys, flying the ship, space, F1 and F11, and his ship shop. Say no and he leaves you alone. Press E beside him to run it again.
- **Buying a ship:** press E beside T-89. He sells every ship that flies in the atmosphere, cheapest first: the Lanner courier (900 cr), the Kestrel (1200 cr), the Albatross (1800 cr) and the Frigatebird (2400 cr). The ship you buy lands on the empty pad, and you can board and fly it like any other parked ship. The pad holds one ship at a time. He buys it back for 60% of the price, but not while you are flying it.
- Data: `content/core/npcs/t89.json` (his lines, tutorial pages, prices, look). The bought ship is saved with the world (`WorldState.hangar`).
- Tests: test_ship_salesman. test_town_layout, test_town_decor and test_ship_fleet are updated for the empty pad. Review shots: `tools/review/t89_shot.gd`.

## Companion droids (2026-10-27, issue #51)

- **Three kinds, each with several looks:** the floating droid (the range remote's shape), a tall, skeletal assassin droid with a pistol and deadly aim, and a cargo droid: a small box on wheels. All are placeholder shapes for now (`src/systems/droids/droid_kit.gd`). None of them talk; they beep, each kind in its own voice (new sounds from `tools/audio/make_game_sfx.py`).
- **Up to three at a time.** They follow you on foot. They vanish while you fly the ship and come back beside you when you climb out. They show as droids in the inventory (I), but nothing a cargo droid carries is listed there.
- **The droid merchant** in the market (stall `vendor_4`) sells floating and cargo droids for 50 cr and assassin droids for 100 cr. They buy them back for 40 cr and 90 cr. A sold droid leaves.
- **Cargo droid:** press E beside it to stash items or unload them. The gate searches your pockets, never the droid, so it is a smuggler's best friend. Oda still waits until the goods are sold before she lines up another drop.
- **Taming the range remote:** block or deflect five of its bolts in a row and it follows you home. Oda passes this on as a rumour.
- **Wrecks in the desert:** now and then a broken droid turns up far out in the sand, one of each kind at most, never close to another one. The assassin lies flat like it is dead. Press E and stay beside it for 10 seconds to fix it; it resets and follows you.
- **At the cap:** a fourth droid (a wreck or the range remote) asks which droid to sell at the merchant's price to make room.
- **The Remnant's droids:** a black, red-eyed assassin droid and a floating droid patrol the main street. They turn on you whenever the garrison would, sound the alarm, and fight. Shooting them provokes them; destroying one costs Remnant standing. Your own assassin droid shoots back at them, and at troopers while the alarm is up.
- Data: `content/core/droids/droids.json` (kinds, variants, prices, tuning, words). Saved with the world (`WorldState.droids`).
- Tests: test_droids.

## Bug fixes and hardening (2026-10-27, issue #55)

- **Vehicles in town are hostile.** Ride a speeder into town, or lift a ship off inside it, and the garrison treats it as a threat. The first trooper to notice it sounds the alarm, and the troopers shoot its hull. Out in the desert nobody minds it. Speeder or ship lasers that hit a trooper count as the player's shots.
- **The ship has a hull in the air.** Its hull and shield come from its data and show on the flight HUD. A hull shot to nothing goes down like a crash and is towed home. The hull box stays solid in flight so bolts can hit it.
- **Ship guns in the atmosphere.** LMB fires the cannons as soon as you sit down, whether you are on the pad or in the air. Seekers stay a space weapon.
- **Solid props.** Lamp posts, bay light posts, fuel pods, pit clutter, door-side barrels and crates, rooftop antennas, parapets and roof blocks now collide. Each one has a box in a single `Props` body. You bump into them and can stand on them. The town's own boxes and the nav are unchanged.
- **Brighter cantina.** The hanging lamps reach further, and four warm fill lights hang under the roof. They are on by day too.
- Tests: test_vehicle_threat. test_town_decor and the m14 flight trace are updated (the hull is now solid in flight).

## The port's fleet (2026-10-27, issue #43)

- Four flyable ships from Hyper3D replace the placeholder colour variants in the pit. Each has its own stats, guns and Shift ability:
  - **Kaldor VX-88 Kestrel:** the interceptor, rebuilt from the old stand-in. Silver and cobalt, with wingtip guns. Balanced, and Shift boosts.
  - **Marchbank GR-75 Frigatebird:** a disc freighter. Tough and slow with four guns. Shift drifts: it keeps sliding while the nose swings round.
  - **Valcourt Kinetics Lanner:** a racing courier. The fastest and lightest ship, with the longest boost.
  - **Ashford Albatross Mk VI:** a gunship. Armoured, with double-strength guns. Shift is an air brake that snaps it round.
- Walk up to any parked ship and press E to fly it. Its stats, its guns and its name go with it into space. The ship you left stays where you landed it.
- The speeder (Hartwell MK-84 Curlew) is a Hyper3D model of the original sled.
- Make-and-model names come from the name generator.
- New data fields:
  - `blaster_power`, `flight.ability`, and `ship` on a bay box;
  - `content/look/vehicle_models.json`, with the runner-up generations kept as options.
- New tools: `tools/look/prep_vehicle.gd` (raw model to game model) and `tools/look/shoot_vehicles.gd` (review stills). The stills are in `docs/lookdev/vehicles/`.
- Tests: test_ship_fleet. test_ship_kit, the town layout and decor tests, and the m14 flight trace are updated.
## Character builder (2026-10-27, issue #48)

What works now:
- **Dress the player yourself.** F11, Character: pick the head, upper body and
  lower body from the kit pieces (player, guard, and the goggle head), each in
  its original colour or one of its variants. A model turns beside the choices.
- **Live and kept.** Every pick is worn at once (weapons and the jetpack stay on)
  and saved to `user://player_outfit.json`, so it is still on after a restart.
  Random and Default buttons.
- **No hand-kept list.** The builder reads the pieces from the kit model and the
  colours from the texture files, so a new piece or colour shows up by itself.
- **Review shots:** `tools/review/builder_shot.gd` screenshots the builder.

Known gaps:
- No mouse turning or zoom on the preview; it turns by itself.

## Player and guard outfits from kit pieces (2026-10-27, issue #48)

What works now:
- **The player and the guards are built from pieces.** Each wears a head, an upper
  body and a lower body from one shared kit (`assets/characters/kit/parts.glb`), the
  same way the locals mix their parts. Every piece sits on one skeleton and is cut
  at the same neck and waist seams, so any head goes with any body.
- **New looks in the game's style.** The player: wide hat, teal bandana mask, a
  leather vest over a shirt, cargo pants and boots. The guard: an enclosed helmet
  with an amber visor and plated armour, now gunmetal for troopers and oxblood for
  commanders. No packs or weapons are modelled on the bodies.
- **Colour variants.** Rust, sand and dusk for the player's pieces; gunmetal,
  oxblood and desert for the guard; an outfit picks one per part
  (`"guard:gunmetal"` in `characters.json`).
- **A spare head for later NPCs:** a brass goggle mask on a teal hood
  (`goggles`), with oxblood, sand and violet variants. Nobody wears it yet.
- **Tools.** `tools/look/fit_parts.gd` fits a whole generated costume onto the
  base body and cuts it into pieces; `recolor_fitted.gd` writes the variants;
  `shoot_sheet.sh` renders review sheets (`tools/look/sheets/`).

Known gaps:
- The player's head is about 34k triangles and the spare head 75k: the simplifier
  cannot reduce these meshes further. Future generations should ask Hyper3D for
  fewer polygons.
- Seams are cut, not capped, so a ragged edge can show at the guard's waist.
- No character builder in settings yet (added since: see Character builder).
## Sound FX library and music (2026-10-27, issue #16)

- **Music, all the time.** Three ambient tracks cycle with slow cross-fades. When an NPC opens fire on you, the battle track cuts in (from 30 s into the recording) and holds for 15 s after the last shot. Cross the edge of space and the space track takes over; dive back under and the ambient comes back. The music carries on across launches and landings.
- **New sounds:** the jetpack roars while it burns; your ship's engine drones in flight (pitch follows the throttle and boost), in the port's sky and in space; ship guns, missiles, hits and explosions in every dogfight; the speeder's engine and lasers; coins whenever your credits go up or down (paid, bribed, bought, sold, robbed); the sparring remote hums and chirps like a little droid.
- **The energy blade is quieter** (its one-shots down 7 dB, the hum down 8 dB).
- **F11 > Sound:** music and effects volume (saved per machine).
- One small library, `Sound` (`src/systems/audio/sound.gd`, data in `content/look/sound.json`): systems ask for a sound by key. New effects are synthesized by `tools/audio/make_game_sfx.py`; the music is free Pixabay tracks, re-encoded by `tools/audio/rip_music.sh`.
- Tests: test_sound.

## The 80s HUD (2026-10-27, issue #52)

- A glowing retro HUD over everything: one phosphor colour, a monospaced font (Anonymous Pro, SIL OFL), dark glass panels with a lit rim. RetroSkin restyles every panel, label and button as it appears, so no screen had to be rebuilt; text that means something (her lines, warnings) keeps its colour.
- A banner (planet, town, clock, credits) and a footer (health, stamina, jetpack fuel, on foot or piloting). Click either, or press F1, for the info screen: where you are, the time, credits, speeders, standing with every faction, the latest news.
- Bigger interaction prompts ("[E] Talk to ...", board, ride; they pulse) and a bigger chat box.
- F11 > HUD: pick the HUD colour (six presets or your own; saved), and a list of every function key.
- Pilot and speeder readouts moved below the banner; the weapon readout sits above the footer.
- Tests: test_retro_hud.

## AI disclaimers, the Cantina Owner, Skrugs and speeders (2026-10-27, issues #29, #42, #47)

- **#29:** a notice at game launch, one pinned in every AI conversation, and a reminder whenever the player types a trigger word (content/core/llm/disclaimers.json).
- **#47:** the bartender is the Cantina Owner everywhere (old saves carry over). Bigger, readable chat box; directions by landmark (front gate, back gate), never compass; every paid drink puts a new-coloured bottle on the counter.
- **#42:** Skrugs's stall outside the back gate, run by the same AI brain from his own card (sells speeders, no jobs, knows Oda). Click-to-buy speeders (100 credits), parked behind his house and saved. Speeders hover, jump off ramps, have lasers and a hull only gunfire can hurt.
- Tests: test_disclaimers, test_cantina_owner, test_speeders, and the end-to-end scenes/speeder_trace.gd.

## Seamless flight to space (2026-10-27, issue #46)

What works now:
- **No more pause and restart.** Flying out of the atmosphere used to fade to black,
  unload the town and load a separate space scene, then load the town again on the
  way down. Now the town scene stays loaded the whole time: space is just the sky
  above the port, already black with stars at 4 km.
- **The fight comes to you.** Reaching the edge of space starts the pad's encounter
  right where your ship is (`SpaceFight`): your wingman beside you, the raiders
  arriving from ahead of your heading. Your parked ship is the one in the fight;
  guns on LMB / Space, seekers on RMB / X, next target on T.
- **Three ways out, all in place.** Win and you are paid on the spot and fly on.
  Dive more than 250 m back below the edge and you break the fight off. Lose your
  fighter and it is towed home like a crash. Climb out again for a new sortie.
- **The same part of the planet.** No more arriving 3 km off at a fixed bearing:
  you come down exactly where you were.
- **The dogfight is a toggle.** On by default (`space_dogfight` in
  `content/core/flow/launch_pads.json`); F11 (World tab) switches it at runtime.
  Off, space is quiet sky.
- **Less detail the higher you fly** (`AltitudeDetail`, tiers in the world's
  `detail` block). Above 60 m: real-time GI (SDFGI) and SSIL off. SDFGI rebuilds
  whenever a fast camera moves, the likely cause of the lag. Above 500 m: SSAO and
  volumetric fog off, and the people (and their brains) are hidden and paused.
  Above 1.5 km: shadows off, lamps, banners and boulders hidden. All of it comes
  back on the way down, 40 m lower so it never flickers.
- **A smaller planet.** Planet radius 120 km to 60 km, the sand skirt stops at the
  horizon instead of running out to 100 km, and the desert mesh is 320 vertices a
  side instead of 400.
- **Shared dogfight drawing.** The ships, bolts and flashes are one `DogfightView`
  used by both the stand-alone space scene and the fight in the port's sky.

Measured (headless trace): the worst frame in the whole M14 loop is 16.6 ms (it was
28.1 ms, the town reload). Starting the fight costs 3.2 ms.

## Town art pass 2: neighbourhoods, barracks, market (2026-10-26)

What works now:
- **No more grid of boxes.** The two residential districts are laid out by
  `tools/town/gen_neighborhoods.py` (fixed seed) along crooked lanes, with a
  small square and a cistern in each. Beside the market: small huts packed
  close together. Beside the barracks: tall towers with bridges between the roofs
  (walkable, with rails and lit edges, and a door where each one lands).
- **A building kit** (`src/systems/world/town_buildings.gd`): round domed huts,
  block huts, stepped huts, barrel-vault huts, block towers and round towers.
  Every building has the same rounded sci-fi door (arched frame, recessed
  sliding panel, a glowing light bar and status light), a simple window (a
  porthole on round walls), and a short + tall antenna relay on the roof. A few
  variants are repeated to make the neighbourhoods. Round buildings collide as
  cylinders.
- **The barracks match:** the hall is buttressed with three big doors and
  windows between, a block stands on its roof, and a bunk tower is bridged to it.
  The watchtower and the market shops use the same doors, windows and relays.
- **Every market stall is different and shaded:** a slanted sheet, a peaked tent
  or two parasols over the vendor, a dressed table, and its own wares (pottery,
  produce, bolts of cloth, salvaged tech, water cans, spice sacks with a balance).
  Strings of bulbs cross the lane.
- **Street decor:** cables with pennants strung between the huts (and some
  towers), barrels, crates and jars by the doors, lamp posts down the main street.
  Lanterns, windows and string lights glow at dusk; no new omni lights.
- **The cantina is a proper hall:** the ceiling is 9 m (was 5), with beams, lit
  pilasters, an arched portal and a glowing lunette over the door. A round stage
  stands in the middle (lit rim, speakers, a mic, a lighting ring hung from the
  ceiling, nobody on it); tables and the walk routes go round it. Three locals
  sit on the bar stools facing the bartender.
- **A stair tower behind the bar:** go round the end of the bar and in at the
  tower door, then up a spiral ramp (5 turns, a real slope you walk) to a round
  lookout room 15 m up, open on all sides over the town, with a dome and an
  antenna relay. Built from one generator (`src/systems/world/stair_tower.gd`)
  for both collision and looks. The walk trace climbs it.
- **A bigger, round spaceport:** the pit is a 56 m circle (was 36 x 44 m) with
  straight ramps out east and west, a curb and wall lights. Four bays: your ship
  (you still spawn beside it), plus three parked colour variants of it: red
  accents, gold hull with blue accents, gold hull with red accents
  (`content/look/ships.json`). Painted bay rings, light posts, fuel pods, and
  crate stacks, barrels, cans and carts scattered at odd angles. The round wall
  is a `bowl` box (`src/systems/world/pit_bowl.gd`, "hollow": other boxes sit
  inside it).
- The alley and rooftop smuggling drops were moved to fit the new streets.
- Parts are batched as MultiMeshes (one per mesh + material).

## Locals on foot (2026-10-26)

What works now:
- **The locals are people, not statues.** Nine live locals, run by a new
  director (`Townsfolk`) the way the garrison runs the troopers, on the same body,
  senses, pathing and brain:
  - **Five walk loops:** three through the house lanes and alleys (two in the west
    houses, one in the east) and two shoppers up and down the market.
  - **Four keep a stall:** two merchants, the gear trader and the fence, each
    behind a counter facing the aisle. They look around but never leave it.
- **Hurt one and they all fight.** Shooting any local raises the locals' own alarm
  (not the Remnant's: the gate stays calm). Every local in town fights back with a
  holdout pistol: walkers take cover and close in on a leash, merchants duck behind
  the counter and shoot over it without leaving the stall. Locals standing drops
  (-10 for the fight, -8 per local killed). Get away and they calm down but
  remember your face for 4 minutes; get downed and they let the Remnant have you.
- **No trade mid-fight.** A stall will not deal while the locals are fighting, or
  ever again once its keeper is dead ("Not selling to you.").
- **The market is a street of stalls.** Two rows of six stalls face each other
  across an 8 m aisle; each is a waist-high counter on the aisle side and a back
  panel, the keeper standing between them.
- **Placeholder looks.** Every local uses the existing "local" CharacterKit figure;
  the profile's `archetype` is the one field the character art pass will change
  (`content/core/soldiers/local_resident.json`, `local_merchant.json`, `local_fence.json`).

## Mix-and-match locals (2026-10-26)

What works now:
- **Locals wear a rigged model in three parts.** A sand head scarf with goggles
  (black lenses, no face), a loose linen shirt and loose linen trousers, made with
  Hyper3D Rodin and split into head, torso and legs.
- **Every part has six colours:** sand, darker, lighter, blue, red and yellow.
  Each local picks one per part at random (216 combinations), or a caller passes
  an outfit: `kit.build("local", "", {"head": "blue"})`.
- To add a colour: add it under `local.recolor.colors` in
  `content/look/character_models.json`, run `tools/look/recolor_parts.gd`, and add
  its name to the part lists in `content/look/characters.json`.
## Oda's smuggling run (2026-10-26)

What works now:
- **Oda always has a drop lined up.** Ask her for work (or about smuggling, a
  drop, the fence) and she offers "A drop for the fence": what it is and roughly
  where it is. Take the job and the contraband appears there.
- **Three new contraband goods:** refined quantonium (45 cr), holocrystals
  (20 cr, 2-4 cases) and space whale teeth (70 cr). The fence buys all of them at
  full value; the gate confiscates them like the cells.
- **Four hiding areas, 17 spots:** the sand past the east gate, the dunes outside
  the back gap in the west wall, the alleys between the houses, and the low house
  roofs (bring the jetpack). She only names the area, never the same one twice
  running, and drops sit still with no glow ring, so you have to look.
- **It runs forever.** Once the drop is picked up and you carry no contraband
  (sold to the fence, or taken at the gate), she lines up the next one. The drop
  in the world, and whether you took it, is saved.
- Data only for new goods and spots: goods in `content/core/board/bar_board.json`
  (`j_smuggle_run`), spots in `content/core/pickups/port_town.json` ("drops").

## F11 demo settings (2026-10-26)

What works now:
- **F11 in the town opens demo settings.** The game pauses and the mouse frees;
  F11 or Esc closes it and saves. Tabs, so the full settings can move in later:
  - **World:** an hour slider (0-24) that blends the lighting between the
    golden / noon / dusk presets (keys in `content/look/time_of_day.json` "hours"),
    preset buttons, game speed (0.25x-4x) and credits.
  - **Standing:** a slider per faction (-100..100, with its label), reset to
    defaults, and each individual with a relationship (Oda for now): trust with
    its tier, mood, tab owed, and clear a ban.
  - **Player:** god mode, heal / revive, give and wear the jetpack, endless fuel,
    teleport to a town marker, and the guard-senses debug (F4).
  - **Flags:** every flag a rumor, job or mood rule reads, as checkboxes, plus a
    field to set a custom one.
- Everything writes where the game does (WorldState, the npc's Relationship, the
  look), so the bartender, rumors and the gate checkpoint react straight away.

## M15 part 3 — The garrison, sound, crouching, smuggling (2026-10-26)

What works now:
- **The whole garrison thinks.** The tower sentry and the two barracks troopers
  are live: the barracks pair walk loops round the yard, and the sentry watches
  the gate and the street from the watchtower with longer eyes (60 m). Wanted on
  sight (Remnant standing -40 or worse, by day), the tower or the barracks shout
  "Halt!" and raise the alarm themselves.
- **A town-wide alarm.** Start a fight anywhere (the gate, the yard, a sentry who
  spots you) and every trooper in town fights: a klaxon wails from the
  watchtower, the barracks troopers run to the trouble using the cover on the way,
  the sentry steps to the rim of the tower and shoots from up there, and everyone
  shares the last place anyone saw you. Troopers chase only so far (gate 30 m,
  barracks 55 m), so you can get away into the desert; they search, go home, and
  remember you for 5 minutes. Kill all five and the gate is yours.
- **They make noise.** Rifles (the Kenney blaster repeater), footsteps (quieter
  crouched), a grunt when hit, a lower one when they drop, helmet-radio chatter
  under every line they say (shouted lines are sharper), and the alarm klaxon. The
  chatter and the klaxon are synthesized (tools/audio/make_npc_sfx.py); there is no
  speech engine, the words stay on screen.
- **Your crouch is real.** Crouching shrinks your collision to 1.05 m and drops
  your eye to 1 m, so a waist-high barricade really hides you (and you cannot peek
  over it while hidden). You stay down where there is no room to stand.
- **Searches check your pockets.** A search that finds contraband stops you:
  hand it over (gone, small standing hit), pay to keep it (75% of its value, at
  least 30 cr), or run for it (the alarm). Bribe before the search and nobody
  looks. Even showing papers can turn into a spot search (1 in 4).
- **Something to smuggle.** A drop of three cases of unmarked power cells lies
  out past the east gate. The new fence in the market pays 30 cr a case, full
  value, no questions. Getting them past the checkpoint is the game.
- **I opens your inventory:** credits, every item you carry with its count and
  value, what you are wearing, and contraband marked in red.

How to see it:
- Run the town. Walk out of the gate, pick up the cells (E), and try to bring them
  back in. Press I. Fire a shot near the yard and listen.
- `./scripts/ci.sh` writes `test_results/garrison_trace.txt` and runs
  `test_garrison_trace`, `test_town_alarm`, and the updated checkpoint, combat and
  guard brain tests.
## Right-click toggles aim and block (2026-10-26)

What works now:
- **Aim and the sword's block are a right-click toggle, not a hold.** Right-click
  turns blaster aim (the zoom) on; right-click again turns it off and the camera
  zooms back out. With the energy sword out the same click arms the block and
  re-click disarms it.

## M15 part 2 — Combat NPCs at the gate (2026-10-26)

What works now:
- **The gate guards walk.** Each has a loop by its post (in the town data). They
  pause, glance around, turn toward footsteps or a shot, and come back.
- **The checkpoint reads your standing with the Remnant.** 40 and up: "Move
  along." 0 to 39: papers, or a 10 cr bribe. Below 0: papers and a search (you are
  held still for 3 s), or a 25 cr bribe. -40 and below: "Halt!", then they open
  fire. After dark, bribes work one band lower: a wanted face can buy its way
  through for 40 cr, and the search bribe drops to 10. A drawn weapon close by, or
  gunfire in the street, makes it one band worse.
- **A choice card** (keys 1-4 or the mouse): show papers, submit to a search,
  bribe (greyed out if you cannot pay), mouth off (papers becomes a search; twice is
  a fight), or walk away (fine, but walking through the gate anyway gets one
  warning, then shots). What the guard says shows over its head and as a subtitle.
- **They fight like soldiers.** When the warning runs out, they fire an opening
  burst, then each sprints to its own cover (the two new barricades inside the
  gate, the walls, the tower, the stalls), crouches, stands, fires 3 to 5 bolts,
  and ducks again. They only shoot what they can see, miss more at range and at a
  moving target, hide longer when hurt, and never hit each other. Shoot one, even
  after being waved through, and both are on you.
- **You can be hurt now.** 100 health, back on its own after 4 s without a hit, a
  bar bottom left while hurt. At zero you are knocked out and wake up in the pit,
  20% lighter in credits, and the guards stand down.
- **Three ways out of a fight.** Win (both down: standing drops 40, the checkpoint
  is gone, Oda talks about it). Run (out of sight and 70 m off: they search near the
  gate, give up, and remember your face for 5 minutes). Or lose (the pit).
- **The world remembers.** Bribes, fights, dead guards and flights all land in
  WorldState, with three new rumors for the bartender.

How to see it:
- Run the town and walk to the gate (default standing is -10: you get searched).
  F4 still shows each guard's senses. Pull a gun near them, or fire one off first.
- `./scripts/ci.sh` writes `test_results/combat_trace.txt` (15 scenarios, each in a
  fresh town) and runs `test_combat_trace`, `test_checkpoint` and `test_guard_brain`.
  Review stills: `docs/npc/look/`.
## N1 — Sci-fi naming system, issue #15 (2026-10-26)

What works now:
- **Everything that spawns gets a name.** The gate guards ("Corporal L. Raske"),
  the space fight's pilots with callsigns ('"Wasp" Lieutenant Selma Sakete'), your
  ship ("Woeful Refrain"), the jetpack's make and model ("Embry XR-76 Skylark"), the
  town ("Quartzspring") and its planet ("Namlunyn").
- **One engine, no LLM.** A library of about 2,300 original terms, four "tongues"
  that build new words syllable by syllable, and a small template grammar per kind
  of name (people by culture, callsigns, ships, equipment, makers, towns, planets,
  moons, stars). Same world seed, same names, every time.
- **Unique across the game.** Every new name is checked against all the names
  already given out, and the authored ones, before it is saved. The bartender's own
  name is reserved. The book is saved with the game.
- **You see them.** A guard's name floats over them when you walk up. A place card
  shows the town and planet when you arrive. The flight HUD and board prompt name
  your ship, and "Leaving Namlunyn..." shows at the edge of space. The space
  banner names the planet below, a kill calls out who you shot down, and the trade
  prompts show the jetpack's model.
- **The bartender knows them.** Her briefing names the town, the planet and the
  people in town, so she uses the same names.

How to see it:
- Run the town: the place card is the first thing on screen. Walk up to a gate
  guard, or press E at the ship.
- `./scripts/ci.sh` writes `test_results/names_trace.txt`. It covers:
  - names in the real scenes;
  - a save and reload keeping them;
  - a new game with the same seed giving the same names, and another seed
    different ones;
  - two sorties of named pilots;
  - 5,000 people named with no repeats.
- `docs/names/NAMING.md`: how it works and how to add words, cultures and kinds.
- 498 GUT tests (496 pass, 2 need a local model and skip, as before).

What is faked or outstanding:
- Only the gate guards, the pilots, your ship, the jetpack, the town and the
  planet are hooked in. The fixer has a naming block, but its scene has no place
  to show it yet. Weapons are not named.
- English-only library, three human cultures. No aliens yet.

## M15 part 1 — Guards on foot: body, pathing, senses (2026-10-26)

What works now:
- **The two gate guards are real bodies, not statues.** They stand on the same
  movement code as the player (the same controller, capsule and collision), so a
  guard can never walk faster, climb higher or clip through anything you cannot.
  They block you, bolts hit them, they flinch, and after 60 hp they drop (a fallen
  guard no longer blocks shots or sight). Every number is in
  `content/core/soldiers/gate_guard.json`.
- **They can walk anywhere in town.** The navmesh is baked when the town loads,
  from the same box data as the collision (move a wall in the data and the guards
  path around it), on a worker thread so it never costs a frame. Buildings and
  crates are cleared (no walkable floor inside a closed box), and the step height
  matches what the capsule can really climb. In the trace a guard runs a patrol,
  165 m to the cantina and back, and down into the pit and back up, with no stuck
  events.
- **They see and hear.** A 120 degree, 32 m view cone, a line-of-sight ray about
  five times a second (only while you are in the cone), and an awareness meter that
  fills faster up close and if you hold a weapon, slower if you crouch (crouched,
  you vanish past about 19 m). Right behind them inside 2.5 m they feel you. The
  watchtower and walls block their view. They hear a blaster shot within about
  45 m and know where it came from, but not who fired. They forget you 8 s after
  losing sight. Their heads turn to follow what they see.
- **F4** shows a line over each guard: hp, what it is doing, whether it sees you,
  its awareness and NOTICED / heard.

What they do not do yet: anything about it. No challenge, no hostility, no
shooting back. That is part 2 (the guard brain); see `docs/npc/GUARD_PLAN.md`.

How to see it:
- Run the town, walk to the gate, press F4. Stand in front of a guard, then step
  behind the watchtower, crouch, draw a gun, fire one off.
- `./scripts/ci.sh` writes `test_results/npc_trace.txt` (the whole run above with
  real physics) and runs `test_npc_trace`, `test_perception`, `test_npc_locomotion`
  and `test_town_nav`. Review stills: `docs/npc/look/`.

## M14 — Fly your ship from the port to space and back (2026-10-26)

What works now:
- **The ship in the pit is yours to fly.** Walk up to it and press **E** to climb
  in (the old "[E] Launch" straight to space is gone). **Space** lifts it straight up
  out of the pit; it hovers until you throttle up with **R**. Fly with the dogfight
  keys (W/S pitch, A/D turn, Q/E roll, R/F throttle, Shift boost, mouse to steer, V
  for the cockpit view).
- **The desert is the sky's floor.** The ship flies over the seamless desert (the
  same sand you walk on), and its mesas and hoodoos are solid: land on a mesa top or
  fly into one. The M5 outpost's buildings stand 3 km out as placeholders. Past the
  desert's 6 km edge the planet's surface carries on and curves away below you. Fly
  low over the dunes or high over the town, like a plane in an open-world game.
- **Land anywhere, get out anywhere.** Below 150 m, **C** lands on whatever is
  under you (street, roof, mesa top or dune) inside the desert. Once down, **E** gets
  you out beside the ship onto ground that was built under you while you came in. The parked ship is solid; walk up and **E** to get back in.
- **Crashes.** Hit the ground or a building fast and the ship crashes; it is towed
  back to its pad and you stand beside it.
- **Up through the atmosphere.** The air thins as you climb: the ship gets faster
  (up to 4x at the top), the sky darkens to black, the clouds and haze go, stars come
  out, and the planet curves away below. A bar on the right fills toward the
  **edge of space at 8,000 m**. Nose up at full throttle it takes **about 33 s with
  boost, 39 s without**, from lift-off.
- **Into the space battle.** Crossing the edge fades into the pad's encounter (the
  M10 orbital skirmish).
- **And back down.** In space, dive at the planet whenever you like and you come out
  in the port's sky at 5 km, still flying, pointed at the town. Win the fight and you
  get 25 s to dive yourself before re-entry happens anyway. Lose your fighter and
  you limp home to the pad on foot, as before.
- **A flight HUD:** speed (m/s and km/h), throttle, boost, altitude, height above
  ground, climb rate, state, and the space bar.

How to see it:
- Run the town, walk to the ship, E, Space, R, then pull back. Controls are in
  `LAUNCH.md`. Review stills are in `docs/m14/` (`./tools/m14/shoot_flight.sh`).
- `./scripts/ci.sh` writes `test_results/m14_flight_trace.txt`: the whole loop with
  real physics and the real scenes. Board, lift off (3.6 s), reach space in
  33.3 s, hand off to the space scene, dive back, arrive flying at 5.2 km, reach the
  port in 32 s, fly a 2.8 km circuit past the outpost and over the hoodoos, land in
  the dunes 840 m out, get out with no hitch (the walkable ground was ready), walk
  19 m on the sand, crash into a mesa, get towed home, land on the pad. Worst frame
  39 ms (one frame, the physics step as you step out; budget 50).
- 438 GUT tests (436 pass, 2 need a local model and skip, as before).

What is faked or outstanding:
- Built on the seamless desert (PR #17): its `DesertTerrain` gained `prefetch()`, so
  the walkable collider can be built ahead of a landing ship. Its collider stops
  following you while you fly. Main's desert-walk trace now lets you settle for a
  moment at the gate before checking you are on the floor (a collider re-centre can
  hop you a few cm; see KNOWN_ISSUES).
- The ship is still the stand-in model; no landing gear, no engine sound, no
  contrails or heat on the climb.
- Landmarks are placeholder shapes (cylinders and boxes); the outpost has no
  enemies or mission hooked up yet; no other ships or traffic in the sky.
- No ship weapons in the atmosphere (they fire in space only).
- Ships rest level wherever they land, even on a slope.
- The ship's position is not saved: a new session starts with it on the pad.
- The world is one desert around one port. Going to space and back always uses the
  same encounter and the same re-entry point.
## Seamless desert: the town sits on the dunes (2026-10-26)

What works now:
- **Walk out of the gate into the desert.** The town no longer floats in the sky.
  It sits on the same dune terrain as the beauty corner, at its own floor level:
  the paving runs straight into packed sand at the gate and the back gap, there is
  flat sand outside every wall, and about 30 m out the sand starts to swell into
  open dunes (fully dunes by about 300 m out).
- **The desert goes on.** The ground's collider follows you and rebuilds a little
  each frame (at most about 2 ms), so you can keep walking. The trace walks 700 m out
  and back with real physics, the collider re-centring under you on the way, with
  the worst frame well under the 50 ms budget. The visible terrain reaches about 6 km, with fog at
  the edge.
- **The pit is still a pit.** The ground dips under the landing pit, so the ship
  bay, its ramps and the launch pad work exactly as before.
- **Something to walk to.** Mesas on the horizon, hoodoos 300 m to 1 km out (solid,
  so you can walk up to them) and a few hundred boulders, all from
  `content/look/desert_landforms.json` (the same recipes as the beauty corner).
  The camera now sees 12 km.
- **The jetpack lands you on sand.** Flying out over a wall now sets you down on the
  sand outside. The fall guard still catches a fall through the world, measured
  from the ground under you (the old rule, "20 m under the town's lowest floor",
  would have yanked you home from any dune trough).
- **Review shots:** `gate_to_desert`, `desert_look_back`, `north_wall_outside`,
  `desert_aerial` in `content/look/town_shots.json`; golden-hour renders in
  `docs/town/look/desert/`.

How to see it: F5, walk up the ramp, head east through the gate and keep going.
`with_desert = false` on the town scene gives the old town in the void.

Proof: `scenes/desert_walk_trace.gd` (in `scripts/ci.sh`) +
`tests/test_desert_walk.gut.gd`, and `tests/test_desert_terrain.gut.gd` (the site
footprint from town data, nothing poking through the paving, the dip under the pit
for both mesh and collider, the follow-and-rebuild budget, teleports, landforms
clear of the town, the fall guard). The beauty corner's terrain is unchanged
(checked bit for bit against main over 20,000 points).

## M13 — Jetpack (issue #5) (2026-10-26)

What works now:
- **A jetpack you can find.** It sits glowing at the top of the pit's north-east
  ramp, on your way out of the pit. Walk up, press E: it is yours, and it goes
  straight onto your back.
- **Hold jump to fly.** A tap of Space is still the normal jump. Hold it and, after a
  fraction of a second in the air, the pack lights: flames out of both nozzles and a
  climb of about 17 m on a full tank (a normal jump is 0.6 m), with air control the
  whole way. Let go and you fall.
- **Fuel that recharges.** A JET meter at the bottom of the screen shows the tank:
  1.8 seconds of thrust. It refills on the ground, starting 0.8 s after you stop
  burning (about 3 s from empty). It does not refill in the air, so you cannot
  hover forever.
- **Attach, detach.** G takes the pack off (it stays in your inventory; you jump
  normally) and puts it back on.
- **Sell it, buy it back.** The gear trader at the market (the stall at `vendor_2`)
  buys gear at half its value: E sells the jetpack for 60 credits. The trader keeps
  it and sells it back for 120; if you are short, the prompt says what you have.
  Sales and purchases go into the world's event log, so the bartender's world knows.
- **Saved.** What you own, what you wear, which pickups you took and what the trader
  holds are saved with the world (inside the existing save, no version change). Come
  back from a dogfight or reload and the pack is still on your back, and the one in
  the street is still gone.
- **Flying out of town is caught.** The pack clears the 6 m walls, and there is no
  ground outside them. Fall 20 m below the lowest floor and you are put back where
  you last stood.
- **Any item, any design, from data.** Items, vendors and pickups are new data
  categories; the look is `content/look/items.json` (a stand-in today, or any
  `.glb`/`.tscn` through `scene`). `docs/ADDING_ITEMS.md` explains every field.

How to see it:
- Run the town (`scenes/town_demo.tscn`), walk up the ramp, E, then hold Space.
  Controls are in `LAUNCH.md`. Review stills are in `docs/m13/`
  (`./tools/m13/shoot_jetpack.sh` re-renders them).
- `./scripts/ci.sh` writes `test_results/m13_jetpack_trace.txt`: the bot walks out
  of the pit to the pack, picks it up, flies 17.3 m, runs the tank dry, recharges,
  detaches and reattaches, flies out over the north wall and is caught, sells for
  60, buys back for 120, and reloads with the pickup still taken. Worst frame 6.7 ms.
- 381 GUT tests pass (was 335), including a test that adds a new pack, vendor and
  pickup from JSON alone and trades with them.

What is faked or outstanding:
- The pack is a primitive stand-in (two tanks on a plate); the `scene` hook is
  ready for a real model.
- No thruster sound, no dust or heat haze, no flight pose (the body uses its
  airborne pose).
- No fall damage (the player has no health yet), so a 17 m drop costs nothing.
- One pack, one trader, one pickup. No drop key: gear leaves you only by selling.
## M12.1 — Oda's brain actually connects (2026-10-26)

Found by running a real llama-server (built from source) through the game's own
sidecar code, with a tiny random-weight model:
- **Fixed: every model turn failed with HTTP 400 and fell back to canned lines.**
  Godot reads `3` in the reply schema as `3.0`; llama-server's grammar builder rejects
  `"maxItems": 3.0`. Whole-number floats are turned back into integers before sending.
- **Fixed: llama-server could silently never start.** If a routine health check was
  in flight, the "start the sidecar" callback was dropped. Callbacks now queue.
- **Fixed: subtitles could not stream from llama-server.** It orders grammar keys
  alphabetically, so "say" came last. The reply keys are now `say`, `then` (actions),
  `tone` (mood), which sort with `say` first. Old names are still read.
- **The reply must say something** (`minLength: 1`); an empty line used to drop to canned.
- **She tells you why she is dumb.** While talking, the top right names the brain
  answering or the exact reason none is (not installed, no model file, loading,
  Ollama not running, cloud off). Canned replies are marked. The same report prints
  in the Godot output; F3 shows details and llama-server's last log line.
- **The sidecar looks harder:** configured path, `$LLAMA_SERVER`, `runtime/bin`, both
  Homebrew locations, `~/.local/bin`, `~/llama.cpp/build/bin`, and the login shell's
  PATH; any `.gguf` in `runtime/models/`. It logs the server's output to
  `user://logs/llama-server.log` and notices when the server dies.
- **New trace:** `scenes/m12_sidecar_trace.gd` starts a real server and has one turn;
  `ci.sh` runs it when `LLAMA_SERVER` and `TEST_GGUF` are set.
## M11.1 — The guns actually show up (2026-10-26)

- **Fixed: guns did not render on a fresh checkout.** The blaster models were never
  committed: the `models/` rule in `.gitignore` (meant for downloaded LLM models)
  matched `assets/.../models/` too. The rule is now `/models/`, the files are in,
  and `test_weapon_assets` fails CI if a weapon model or sound is ever missing.
- **Readable guns.** The retint is lighter worn gunmetal with tan or oxblood accents
  and catches light on its edges; it was near black because the material was too
  metallic with nothing to reflect.
- **Hands on the handles.** Grip points re-measured on the models: the right hand
  holds the rear handle, the left cups it (pistol) or takes the front band (rifle).
- **Held lower.** Chest height in third person (it used to cover the face); lower
  right and turned slightly inward in first person, so you see the barrel.
- **Muzzle.** A glowing emitter ring replaces the orange dot, plus a brief flash,
  a brighter muzzle light, and a small kick back and up on every shot.

## M11 + M12 — A body, hand weapons, and a bartender who actually talks (2026-10-26)

What works now:
- **You have a body.** Third person shows an animated smuggler (long coat, hat,
  teal scarf) who walks, jogs, sprints, strafes, jumps, lands and crouches, and
  faces where it moves. The camera sits over the shoulder and never goes through a
  wall. V still toggles views; the switch glides in 0.2 s and never moves your aim.
- **Weapons.** 1 blaster pistol, 2 energy sword, 3 rifle (same key again holsters;
  Q last weapon; mouse wheel cycles; H holsters). The weapon comes out of the
  holster (hip, left hip for the sword, back for the rifle) and your hands are on it.
  LMB fires or swings, RMB aims (blaster) or blocks (sword), R reloads. Bolts are
  glowing streaks with recoil, shake and muzzle flash. The sword ignites with a
  sound, hums, chains three swings (forehand, backhand, overhead), and a block timed
  just before a bolt lands sends it back. First person shows your forearms, hands
  and the weapon.
- **A practice range in the pit:** five targets that fall and stand back up, and a
  sparring remote that fires stun bolts while your blade is out.
- **The bartender is real.** Oda Vell stands behind the counter (apron, mechanical
  arm, goggles up), wipes a glass, looks at you, gestures while she talks, pours.
  Walk to the bar, press E, type anything. Her reply streams onto the screen from a
  local model (bundled llama-server), Ollama, or any cloud key (OpenAI-compatible or
  Anthropic), with canned lines that still use true rumors and real jobs when every
  model is down. She never hangs: no first word in time and she moves to the next
  brain with a "Mm." beat.
- **She knows the town.** Rumors are only shown to her when they are true (the
  checkpoint, the patrol you shot down, the shots you fired in the street, the
  range record). Trust (0 to 100, four tiers) unlocks secrets that are not even in
  her prompt before then. Jobs she offers complete on real events and pay. Drinks
  cost the menu price, from your credits or onto your tab. She remembers you between
  visits and between sessions (save v2).
- **Tools to tune her.** F3 shows provider, model, time to first token, tokens,
  fallbacks, dropped actions and why, the raw reply, and copies the prompt. F10 picks
  local / Ollama / cloud, sets URLs, models and a key, and has a Test button.
  Shift+F10 cycles modes. Every turn is logged to `user://logs/bartender/`.
- **Proven headless.** `scenes/m11_body_trace.gd` (real physics) and
  `scenes/m12_bar_trace.gd` (scripted providers, then real HTTP against a mock
  server) feed `test_m11_body_weapons` and `test_m12_bar`; plus unit suites for the
  animator, swap, sword chain, SSE, providers, config, parser, filter, validator,
  prompt, relationship, world state and save v2.
- **The live gauntlet:** `tools/llm/eval_runner.gd` runs 32 cases (jailbreak, meta,
  franchise names, neutrality, grounding, secrets, barometer, memory) against a real
  model and writes a readable report to `docs/bartender/evals/`.

## M9 — Port town, and one demo (2026-10-26)

What works now:
- **Press Play and you are in the town.** `scenes/town_demo.tscn` is the main scene:
  a walled desert port built at runtime from `content/core/locations/port_town.json`
  (112 boxes, 18 markers, 4 routes): gate, market, barracks with a watchtower, the
  sunken landing pit with your ship, the cantina (bartender + fixer spots) and two
  residential districts. You start on the pit floor beside the ship.
- **Your ship launches the dogfight.** Beside the ship, "[E] Launch" shows; E fades
  out into the dogfight. When it is won or lost you land back beside the ship with
  the result on screen. The dogfight scene opened on its own (F6) is unchanged.
- **It looks like the beauty corner.** A visual-only decor layer gives the town the
  look-dev sky, sun, fog and materials (plaster with dye bands, paving, hull metal),
  lamps that come on at dusk, and two torn banners on the watchtower. Keys 1, 2, 3
  switch golden, noon and dusk.
- **Proven headless.** The validator checks 8 rules, with a negative test for each.
  A bot walks every route with real collision: spawn to cantina 1495 frames, cantina
  to gate 2051, gate to cantina 2052, back gap to cantina 1243; worst frame about
  3 ms. New suites: `test_town_layout`, `test_town_walk`, `test_town_decor`,
  `test_flow`.
- **Review cameras.** `content/look/town_shots.json` and `tools/town/shoot_town.sh`;
  golden and dusk shots are in `docs/town/look/`.
- `scenes/m1_demo.gd` now builds its boxes with the shared greybox helper.
- **The ship in the pit is the ship you fly.** Same model, same colors, built from the
  same data as the dogfight. Its collision box now matches the model.

Faked or not yet done: see KNOWN_ISSUES.md "After M9" (capsule NPCs, bare stalls,
box ship, no railings, payout not saved).

## M10 — Starfighter flight and dogfights (2026-10-26)

What works now:
- **Ships are data.** Three starfighters in `content/core/ships/`: the player's
  interceptor (shielded, two cannons, a seeker rack), the remnant fighter (fast,
  unshielded) and the remnant heavy (slow, armoured, one seeker rack). Hull, shield,
  speeds, turn rates, boost and gun mounts are all JSON. Two ship guns join
  `content/core/weapons/`: the ship cannon and the seeker missile.
- **AI pilots are data.** `content/core/pilots/` holds three personalities (rookie,
  veteran, ace): how wide they shoot, when they break, whether they use seekers.
- **Fights are data.** `content/core/encounters/orbital_skirmish.json`: the player and
  a wingman hold off two raid waves above the port.
- **A flight model.** `src/systems/flight/flight_model.gd`: arcade flight along the
  nose, throttle between min and max speed, pitch/yaw/roll rates, a boost meter that
  trades turn rate for speed. Pure, so the AI, a human and the headless bot all fly it.
- **Guns and damage.** Each hardpoint runs the M2 weapon state machine, so ship guns
  share the blasters' ammo/fire-rate/reload rules (an empty cannon "cools", a seeker
  rack reloads). Bolts inherit the ship's speed and are swept against ship hit
  spheres so they cannot pass through a fighter between frames. Seekers need a lock
  (keep the target in the cone), then home with a limited turn rate. A regenerating
  shield sits in front of the M2 hull.
- **Fighter AI.** `src/systems/ai/fighter_brain.gd`: patrol, pursue, attack (fly the
  lead point, fire inside the aim cone), break (hard turn away when too close, when
  hit, or when a seeker is launched at it), extend, and return to the arena.
- **The dogfight director.** `src/systems/flight/dogfight.gd` runs an encounter:
  ships, targeting, projectiles, waves, hits, kills, and the COMPLETE/FAILED outcome.
- **Playable.** `scenes/flight/dogfight_demo.tscn` (F6): fly with the keyboard (or
  mouse), V toggles chase/cockpit view, T cycles targets, HUD with speed, shield,
  hull, ammo, lock meter, target box and lead marker. Set `autopilot` to watch the AI
  fly your ship.
- **Any design later.** Looks live in `content/look/ships.json`. Today they are
  stand-ins built by `src/systems/look/ship_kit.gd`; setting a look's `scene` to a
  `.glb`/`.tscn` swaps in a real model with no code change. `docs/ADDING_SHIPS.md`
  explains every field.
- **Review stills.** `tools/lookdev/shoot_dogfight.sh` renders a lineup of every look
  and chase-camera shots of the fight; current stills are in `docs/lookdev/flight/`.

How to see it:
- `./scripts/ci.sh` now writes `test_results/m10_dogfight_trace.txt`: the AI flies the
  player through orbital_skirmish to COMPLETE (both waves, 7 kills, seekers launched,
  some evaded, the player hit along the way) with every AI action used and no frame
  near the 50ms budget.
- 198 GUT tests pass (was 132), including a test that adds a brand-new ship, gun,
  pilot and fight from JSON alone and flies it.
- Play it: `godot --path . res://scenes/flight/dogfight_demo.tscn` (controls in
  `LAUNCH.md`).

Fixed along the way:
- **The IP-neutrality scan skipped every top-level file** in the folders it scans
  (`scenes/*.gd`, `content/core/manifest.json`, `scripts/*`, `tests/*`): it joined
  the folder and file names without a slash. Fixed; the guard file itself is the one
  exclusion. Added "x-wing", "tie fighter" and "millennium falcon" to the list.
- **CI on a fresh checkout ran no tests but still passed.** Without an import step GUT
  could not load, printed an error, and `ci.sh` exited 0. `ci.sh` now imports first.

What is faked or outstanding:
- Ships are primitive stand-ins until real models are made (the `scene` hook is ready).
- No ship-to-ship collisions; ships fly through each other.
- No flight on-ramp from the port yet: the dogfight is its own scene, not reached by
  walking to a ship.
- Untested on the Mac; review stills are from Linux software rendering.

## Look-dev: art direction, beauty corner, character kit (2026-10-26)

What works now:
- **Art bible.** `docs/ART_DIRECTION.md`: pillars, palette, lighting presets,
  materials, the cast, character research notes, and the screenshot review loop.
- **Beauty corner.** `scenes/lookdev/beauty_corner.tscn`: the port on a cliff above a
  basin, a crashed capital ship, a broken orbital ring, a ringed planet, a market lane,
  and staged characters. Walkable (F6), with presets on keys 1-3.
- **Lighting is data.** `content/look/time_of_day.json` (golden, noon, dusk) and
  `content/look/shots.json` (five fixed review cameras).
- **Screenshots, for real.** `tools/lookdev/shoot.sh` renders every shot per preset to
  `test_results/lookdev/` (Metal on the Mac; software Vulkan under xvfb on Linux).
  Review renders are in `docs/lookdev/`.
- **Character kit.** Five original archetypes on a jointed body with two-bone IK:
  Remnant trooper, Remnant commander, smuggler, duelist and local. The energy sword is
  yellow by default (`blade_color` in `content/core/weapons/energy_blade.json`).
- **Tests.** `tests/test_lookdev.gut.gd`: presets, wall normals, terrain, skeletons,
  IK hands on the rifle and the sword, the yellow default, and a headless scene build.

What is faked or outstanding:
- Characters are built from primitives (a design stand-in for rigged models).
- Everything in the stills is static: no wind, dust motes or cloth motion yet.
- Frame time on the Mac has not been measured for this scene.

## M8 — Polish pass: cleared bug list, performance report, cross-system playthrough (2026-10-25)

What works now:
- **The bug list was cleared.** The one standing artifact -- GUT's "1 orphan" at process
  exit -- was a detached node in a test that called `queue_free()` instead of `free()`.
  A detached node is freed by the engine only on the next idle frame, which never comes
  before GUT tears down, so it left one orphan. Changing it to `free()` clears it; the
  suite now reports zero orphans.
- **One playthrough, every system together.** A single headless run
  (`scenes/m8_playthrough.gd`) threads the whole slice: walk the port + toggle FPV/TPV,
  a trooper seals to cover, the squad spreads (4 troopers, none in the open), a
  timed-deflection duel with the duelist reflects a bolt, the mission loop runs to
  COMPLETE, a typed-default voice turn reaches the LLM bartender, and the game saves and
  reloads the four named things. This is the "the slice hangs together end to end" proof,
  beyond the per-milestone traces.
- **A performance report.** The same run writes `test_results/m8_perf_report.txt`:
  worst/average frame cost and how many frames exceeded the 50ms budget. Across the whole
  playthrough the worst frame is under the 50ms ceiling -- the "no hitch over 50ms"
  property, measured over a full session, not asserted in a vacuum.
- **How to run and record.** `LAUNCH.md` is the human-facing guide: how to open the
  game, the input map, what the 3-minute clip should show, and how to record it with
  `scripts/record.sh` (macOS screen capture; the manual path, not headless CI).

How to see it:
- `./scripts/ci.sh` generates both `test_results/m8_playthrough.txt` and
  `test_results/m8_perf_report.txt`; a GUT test reads them and proves every system ran
  and no frame exceeded the 50ms budget.
- 116 GUT tests pass (was 109); the merge gate is green with zero orphans.
- `LAUNCH.md` is how to watch the slice on screen and record the 3-minute clip.

What is faked or stubbed:
- The 3-minute clip is the manual/recorded path (`scripts/record.sh` needs a display);
  the headless cross-system trace is its machine equivalent. Same posture as M6/M7.
- The visible 3D world is greybox; full geometry + rendered bolts/blades and GUI-bound
  combat inputs are the remaining polish (tracked in KNOWN_ISSUES), and the bartender
  runs a scripted client in CI.

What broke / fixed:
- The GUT "1 orphan" was a real, if non-failing, artifact: a detached test node
  `queue_free`-d instead of `free`-d. Fixed by freeing it immediately. (Also: this build
  of GUT has no `assert_le`; the helper is `assert_lte`.)

What was needed from the user:
- Confirmation that the 3-minute clip may stay the manual/recorded path (headless CI
  cannot render) -- taken, so M8 ships the headless proof + the LAUNCH.md recording guide.
- The scope call: M8 = clear the bug list + performance report + a cross-system trace,
  with the rendered 3-min clip documented as the manual step.

## M7 — Voice input: push-to-talk, typed default, whisper fallback (2026-10-25)

What works now:
- The bartender now also takes voice input through a push-to-talk, and the design
  is the reverse of the M0 assumption: **typed is the default and the only path with
  no dependency; whisper is an optional, dependency-bearing upgrade.** A voice turn
  that cannot be served degrades to typed, so a request is never dropped and the slice
  ships voice input without shipping an STT model.
- A single door, the `push_to_talk`, routes every captured request to the **same
  `bartender.respond()` from M6**, so the guardrail "the player's text is read but
  never executed as a command" is unchanged: only a model tool proposal, validated
  against the npc's allowed set, may move the world.
- The voice path is wired end to end but optional: a `whisper_runtime` stands in for
  whisper.cpp + a model; it loads only when a model is present, exactly like M6's
  Ollama HTTP post. With the runtime loaded, a sample is transcribed and answers the
  bartender; without it, the controller falls back to typed.
- Every turn records a **latency** (ms from press to release), the M7 "latency
  measured" requirement, measured from an injected clock so it is deterministic.
- The headless voice trace (scenes/m7_voice_trace.gd) writes
  test_results/m7_voice_trace.txt with, in order: a typed default capture applying an
  allowed tool, a voice request that degrades to typed, a wired whisper capture that
  transcribes, a command-looking request that moves nothing, and a fallback; a GUT test
  reads it. ci.sh generates the trace before the suite.

How to see it:
- `./scripts/ci.sh` writes test_results/m7_voice_trace.txt and the GUT test reads it.
  The trace shows MODE=TYPE/SOURCE=typed, a FALLBACK=yes row (voice -> typed), a
  SOURCE=whisper row (the wired path), no TOOL=cut_power (a disallowed tool ignored),
  and a LAT on every row.
- 109 GUT tests pass (was 97); the merge gate is green.

What is faked or stubbed:
- whisper.cpp + the STT model are **not wired in CI**: the `whisper_runtime` is a
  stand-in that "loads" only when a model is set. Transcription in CI is a canned map.
  The real whisper run is the manual + recorded path (scripts/record.sh), not a
  headless CI step, per DECISIONS.
- Latency is measured from an injected clock, not the real mic->transcribe wall time;
  the wiring for real timing is the manual path.
- The push-to-talk `press()/release()` is the literal PTT over the same core; the mic
  capture that feeds it is a manual wiring step.

What broke / fixed:
- None at build level. Two GUT/GDScript-4.7 gotchas surfaced and were fixed: the test
  used Java-style asserts (`assertTrue`) and the trace's `Object.has("field")` does not
  exist in this engine -- switched to snake-case asserts and a presence guard via
  `has_method`.

What was needed from the user:
- None in this pass. Wiring the live whisper runtime + mic capture is the manual step
  (see M8 and KNOWN_ISSUES).

## M6 — LLM bartender (text + Kokoro voice) (2026-10-25)

What works now:
- The single LLM-driven NPC, the bartender, now takes the player's typed text and
  replies. It talks to the model through an interface (`llm_client`), so a live
  client (`ollama_client`) and a canned client (`scripted_client`) are the same shape.
  The canned client is what CI uses, so a conversation is deterministic and repeatable.
- Four tools, exactly the npc's allowed set taken from its data entry
  (`give_rumor`, `set_disposition`, `offer_drink`, `call_guards`). When the model
  proposes one, the brain validates it against the allowed set and applies only the
  effect it is allowed to.
- Two guardrails the spec asks for, both proven by tests:
  - **Text is read, never executed.** A request that reads like a command ("shut down
    all power") changes nothing in the world; only a model tool proposal may, and only
    an allowed one.
  - **A disallowed tool is ignored.** If the model proposes a tool the npc is not allowed
    to use, it is dropped, not acted on, and no effect leaks into memory.
- **Fallback.** When the model comes up dry (the client is exhausted), the bartender
  falls back to a canned line, so a conversation never dead-ends.
- **Memory survives.** The npc writes remembered facts to `memory`, which is the same
  thing the M5 save system already round-trips (`bartender_memory`).
- **Kokoro voice.** Each reply gets a deterministic voice signature from text+speaker,
  and the audio render fails gracefully (a null, not a crash) when the TTS model is not
  running -- as it is in headless CI.
- The headless conversation trace (scenes/m6_dialogue_trace.gd) drives three turns and
  writes test_results/m6_dialogue_trace.txt; a GUT test reads it and proves a reply, an
  applied tool, and a fallback all happened. ci.sh generates the trace before the suite.

How to see it:
- `./scripts/ci.sh` writes test_results/m6_dialogue_trace.txt and the GUT test reads it.
  The trace shows a model reply applying a rumor, a disallowed tool ignored, and an
  exhausted client routing to a fallback line, each with a voice signature.
- 97 GUT tests pass (was 86); the merge gate is green.

What is faked or stubbed:
- The bartender talks to a **scripted client in CI**, not a live model. Real Ollama
  inference is the manual + recorded path (scripts/record.sh); it is not run headless.
- Kokoro's audio render returns a **null offline** (no TTS model in CI); the voice
  *signature* is the deterministic, proven part. A real recorded voice is M8.
- The Ollama HTTP post is a documented stub; only the request-building and
  response-parsing are live code (and are tested on canned JSON).

What broke / fixed:
- None at build level. The first CI run surfaced the usual GDScript strictness: two
  client methods returned `null` against a `Dictionary` type (changed to `Variant`),
  and the Ollama parser had to always carry the `tool`/`args` keys so callers never hit
  a missing key.

What was needed from the user:
- None in this pass. Wiring the live Ollama server + Kokoro model is the manual step
  (see M7/M8 and KNOWN_ISSUES).

## M5 — Mission loop and save (2026-10-25)

What works now:
- The single slice mission "Crate Retrieval" runs end to end: talk to the fixer,
  accept the contract, travel to the desert outpost, defeat 4 troopers + 1 duelist,
  take the crate, return, and get paid. It is a pure state machine (IDLE -> ACCEPT
  -> TRAVEL -> FIGHT -> TAKE_CRATE -> RETURN -> COMPLETE) driven by world events, so
  the loop is the same spine a bot plays and a human plays.
- The mission is data in content/core/missions (crate_retrieval.json) and is now
  loaded through the same IP-neutral data layer as everything else. The data layer
  learned a new category, `missions`; the manifest lists it; the loader loads it the
  same generic way it loads locations. A new mission needs zero code change.
- A save system writes and reads the four things the spec names: player position,
  credits, mission state, and bartender memory. The trace proves all four survive a
  save/load round-trip.
- The 4-trooper squad coordinator (deferred from M4) now spreads the squad: each
  member is assigned a DISTINCT cover node, so 4 troopers do not all stand in the
  open. With 4 members and 4 nodes, none is left in the open.
- The headless bot playthrough (scenes/m5_mission_trace.gd) walks the whole loop and
  writes test_results/m5_mission_trace.txt; a GUT test reads it and proves the loop
  closed (COMPLETE, 5 kills, payout 150) and that save/load preserved the four named
  things. ci.sh generates the trace, then runs the suite.

How to see it:
- `./scripts/ci.sh` writes test_results/m5_mission_trace.txt and the GUT test reads
  it. The log ends in phase=COMPLETE, kills=5, credits=150, with RELOAD_* lines
  showing the save/load round-trip.
- 86 GUT tests pass (was 74); the merge gate is green.

What is faked or stubbed:
- The bot drives the loop by feeding the state machine a fixed event sequence; it is
  not an AI agent choosing actions. The bartender conversation is a deterministic
  stub, not real LLM inference (that is M6). Real inference stays a manual +
  recorded check.
- The fight is the same headless-simulation proof as M2/M3: a 1-D/numeric loop, not a
  rendered combat. The visible fight and the 3-minute recording are M8.
- The save writes to user://; a fresh save path or extra fields is a data-only change.

What broke / fixed:
- Two parse bugs in the pre-built mission state machine were found and fixed: a
  function returned null against a String type, and the enum was called as a
  function during save restore. Both were blocking the build; the loop now compiles
  and closes.

What was needed from the user:
- None.

## M4 — World streaming: port to desert, no hitch, outpost (2026-10-25)

What works now:
- A chunk streamer keeps a window of world chunks loaded around the player and
  AMORTIZES their load work across frames, so no single frame exceeds the frame-time
  budget. A naive "load the whole region now" loader would cost ~132ms at once and hitch;
  the streamer spreads that work so every frame stays under the 50ms ceiling from the spec.
- A headless frame-time log records the entire walk from the docking bay (x=0) through the
  port into the desert out to the outpost (x=1000). A GUT test reads that log and proves
  two properties from the actual numbers: (a) no frame's work exceeded 50ms, and (b) the
  walk travels the full distance, i.e. the port/desert boundary is crossed with no empty
  "loading" frame.
- The outpost is data in content/core (3 buildings, 1 crate objective, 4 troopers, 1
  duelist), loaded through the same IP-neutral data layer, and placed as a chunk at the far
  end of the desert.
- The data layer learned a new category, `locations`, so the outpost is swappable like
  everything else -- no code change to add a new location.

How to see it:
- `./scripts/ci.sh` writes test_results/m4_frame_time.txt and the GUT test reads it.
- The log's first line shows a ~36ms load spike at the bay (amortized under budget);
  the rest stay well under 18ms.

What is faked or stubbed:
- The world is a 1-D chunk strip in a simulation, not yet a 3D greybox you walk through
  on screen. The visible, streamed 3D desert with the outpost models rendered is part of
  the M8 polish pass. The streaming *behavior and its frame-cost* are the real thing,
  proven here in CI.
- The "no hitch over 50ms" is a load-work budget, not yet a measured GPU frame time of a
  real render. M8 will record real frame times with the model loaded.

What broke / fixed:
- A log parser that split on a single space produced empty fields (the log is space-
  padded); the parser now collapses whitespace runs.

What was needed from the user:
- None.

## M3 — Melee: energy blade, stamina, timed deflection, duelist enemy (2026-10-25)

What works now:
- The energy blade: light/heavy attacks and a block all draw from a stamina budget.
- Timed deflection is the core skill: a block pressed inside a tight window reflects
  an incoming bolt and refunds stamina; a block held too long only absorbs it, paying
  stamina. This is the "deflect when blocking with correct timing" from the spec.
- A duelist enemy presses the player, blocks, and parries using that same blade
  logic, so the duelist and the player fight on equal footing.
- A headless melee-duel trace shows a parry, a blow exchange, and the duelist brought
  DOWN; a GUT test asserts parries happened, blows landed, and a knockout occurred.

How to see it:
- `./scripts/ci.sh` generates the trace and runs the assertions.
- Read test_results/m3_melee_trace.txt for the duel log.

What is faked or stubbed:
- The trace is a simulated duel, not a rendered fight with animation. A visible
  blade-swing animation and on-screen parry feedback are part of the M8 polish pass.
- The duelist swing cadence in the trace is fixed.

What broke / fixed:
- A process-ordering bug in the blade: the recovery timer now runs before the frame's
  block drain, so reaching zero stamina correctly lands in BLOCKED_OUT (was: the same
  frame advanced the recovery to the point of missing the transition).
- Recovery action: M2 had been committed on its branch and not yet merged when M3 was
  branched, so M2 tests went missing on the active line. Fixed by merging M2 into main
  before building M3; the history now reads M0 -> M1 -> M2 -> M3 completely.

What was needed from the user:
- None.

## M2 — Ranged combat: two blasters + a covering trooper (2026-10-25)

What works now:
- Two ranged weapons from the data layer: a pistol blaster and a rifle blaster, with
  ammo drawdown, fire cooldown, recoil, and reload. The bolt travels as a visible
  projectile (in the GUI) that deals damage on contact.
- A trooper brain that seals to its nearest cover node and then suppresses the player,
  returning fire. A headless combat-integration trace records the whole arc: SEALING ->
  FIRING -> the trooper dying at 0 HP, while the player takes return fire and the
  return fire stops when the trooper dies.
- Health and death work for both sides.

How to see it:
- `./scripts/ci.sh` generates test_results/m2_combat_trace.txt and runs the assertions.

What is faked or stubbed:
- The combat trace is a simulation, not a rendered fight. On-screen hit feedback and
  bullet tracers are part of M8.
- The four-trooper squad coordinator (so they do not all stand in the open) is deferred
  to M5 with the mission loop; M2 brings a single covering trooper, as the spec asks.

What broke:
- Two blaster state-machine edge cases (idle recovery refunding an attack's cost; the
  deflect refund being capped at full stamina) were found and fixed so the numbers read
  correctly.

What was needed from the user:
- None.

## M1 — Movement + FPV/TPV camera toggle (2026-10-25)

What works now:
- Walk, sprint, crouch, and jump for the player, as pure, testable math.
- A camera rig that toggles between first-person and third-person on one key. The key
  requirement -- "toggle mid-combat without breaking aim" -- is that the toggle changes
  the camera position but not the look direction, which is proven by a test.
- A headless bot-driven trace proves the player moves and that the view toggles between
  FPV and TPV, without a rendered window.

How to see it:
- `./scripts/ci.sh` runs the trace and test_results/m1_trace.txt shows positions and
  view toggles.
- `scripts/record.sh` captures the live GUI (a rendered clip) for a human to watch;
  headless mode cannot render, so the trace is the machine proof.

What is faked or stubbed:
- No rendered clip was produced in CI because headless mode has no window. The human
  recording is available via record.sh; the machine trace stands in for it in CI.
- Take-cover-against-marked-surfaces (movement) is deferred to M4 with the world
  streaming; free walking with a pose change is what M1 proved.

What broke / fixed:
- A bare `godot --headless` run launches the project's main scene, which never quits, so
  the first CI run hung. Fixed by driving GUT through its CLI runner, which exits on its
  own.

What was needed from the user:
- None.

## M0 — Project setup (2026-10-25)

What works now:
- The repo exists on git from commit one, one feature per branch.
- Godot 4.7.2, Rust, and ffmpeg are installed locally; their versions are pinned
  and checked at the top of CI.
- A folder structure and a runtime-loaded data layer (`content/core`) are in place.
- The data-layer loader and the IP-neutrality guard are tested and passing.
- A headless CI script (`scripts/ci.sh`) runs the test suite and exits non-zero on
  failure, which is the merge gate.
- The README, this file, DECISIONS, and KNOWN_ISSUES live in the repo.

How to see it:
- Run `./scripts/ci.sh` -> it prints the GUT summary and exits 0.
- Open the editor and press F5 -> the console prints that the data layer loaded
  (npcs=2, weapons=3, factions=2).

What is faked or stubbed:
- Nothing gameplay-faked yet. There are no gameplay systems yet.

What broke:
- The first CI run hung because a bare `godot --headless` invocation runs the
  project's main scene, which never quits. Fixed by running GUT through its CLI
  runner, which quits on its own.

What was needed from the user:
- Approval to use NobodyWho's bundled TTS + STT instead of separate whisper.cpp.
- Approval to install the toolchain and download a small GGUF at M6.
- A neutral git identity.
- Confirmation the local CI script satisfies the headless-CI requirement.
