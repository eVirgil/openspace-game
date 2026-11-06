class_name ShipPilot
extends Node
## Your ship in the port (M14). The thin node over the pure AtmoFlight:
##   - the ship parked on the pit pad is the one you fly (it adopts the parked model
##     the decor built, so nothing on screen changes until you take off),
##   - E beside it boards; Space lifts off; W/S/A/D/Q/E and R/F fly it; Shift
##     boosts; C lands on whatever is below; E gets out once landed,
##   - a chase camera takes over the player's camera rig while seated,
##   - the sky darkens with altitude (AltitudeSky); the town's desert (DesertTerrain,
##     DesertLandforms) is the ground it flies over and lands on, plus the outpost
##     and the planet's curve beyond the sand (WorldScenery),
##   - while seated the desert's walkable collider stops following the player
##     (a ship at 300 m/s would rebuild it every frame); coming in to land it is
##     built under the ship in the background (DesertTerrain.prefetch), so getting
##     out finds ground there,
##   - issue #46: space is this scene's own sky, over the same ground, and nothing
##     marks where it starts (no read-out, toast or change of music: the sky just
##     darkens as you climb). With GameFlow.space_dogfight() on, climbing past the
##     world's space_altitude starts the pad's encounter right there (SpaceFight),
##     which flies your ship until it is won, lost, or you dive `space_exit_margin`
##     back below it; then normal flight takes over where the fight left you. A
##     lost fighter is towed home like a crash. Climbing out again starts another
##     sortie.
##   - (an arrival "reentry" from the stand-alone flight scene still starts you in
##     the sky above the port, still flying),
##   - a crash tows the ship back to its pad and puts you beside it,
##   - issue #55: the ship's guns fire from the moment you sit down (LMB / Space),
##     in the air as in space; the hull (and shield) from its data takes bolts
##     wherever it is, and the garrison shoots it once it lifts off inside town.
##     A hull shot to nothing goes down like a crash and is towed home.
##     Its seekers (X / right mouse) launch in the air too: locked on the Remnant
##     interceptor they home, unlocked they fly straight off the nose, and either
##     way they go up like a vehicle where they land. One rack for air and space.
##   - issue #43: every ship parked in the pit is flyable. Each is a berth (its ship
##     data, model, hull and home bay); E beside any parked one boards it, and that
##     ship's own stats, guns and Shift ability fly from then on. The one you left
##     stays where you landed it.
##   - issue #193: Z within reach of the Remnant cruiser in orbit (any altitude, a
##     fight running or not) flies her round its hull, in through its bay's shield,
##     turns her round and sets her down on its empty pad (dock()), in one smooth
##     curve from where she was; Space lifts off again, out through the bay. The Z
##     prompt and toast name where she will land (the cruiser's bay before your own,
##     which goes by its town: "Quartzspring bay").
##     While Oda has you on the cruiser, the climb out meets its escort instead of
##     the pad's fight. Its hull is solid in a fight too, and flying in through the
##     bay's mouth or landing on it (C) breaks the fight off.
##   - issue #181: the guns' hits pop the hit marker (ships, NPCs, anything that
##     takes damage; in space the fight's own hits and kills), being hit flashes the
##     screen's edge red, and the HUD is a flight-sim HUD in the chase view and a
##     cockpit with working instruments in the cockpit view (FlightHud).
##   - issue #275: hold B in the air (not in space, a fight or the opening landing)
##     to eject: you are thrown clear with the ship's speed and fall on foot (falls
##     hurt, issue #274). Issue #276: the empty ship goes ADRIFT (AtmoFlight): zero
##     throttle, her momentum and gravity bring her down. Damaged by the fall she
##     crashes and is towed home like any crash; slow enough, she rests where she
##     came down and you can walk back to her.
##   - issue #291: J while seated steps the radio (Sound.radio_next) through the
##     club mixes and off; it plays on across a handoff, in space and in a fight,
##     and goes off when you leave the seat.
##   - issue #368: your own ships (Fleet) are berths with a key. The primary stands
##     on the pit pad when the town is built and whenever you wake in the pit
##     (woke_in_pit), patched up for T-89's fee if it was shot to pieces; the others
##     stand where you last left them (place_fleet). call_ship() flies the primary
##     to clear ground by where you called it from, with nobody at the controls
##     and nobody chasing it.
##   - issue #401: a LAN guest's own ship (Fleet.LAN) stands on the landing pad the
##     host gave it, in their livery, "Your ship" over it; the pit pad's ship is
##     the host's in their game, so it is stowed in the guest's (lan_pad, _stow).
##   - LAN: a guest who climbs out while the host's fight is on flies a copy of it
##     (NetFight, SpaceFight.net_copy) instead of the pad's own, and joins it from
##     up there when it starts (join_net_fight).
##   - LAN friendly fire: your cannons hit the other players' ships while they fly
##     (RemoteShip's hull; NetFight out in space) and theirs hit yours
##     (lan_ship_hit). Seekers never lock on them (the lock is on the Remnant
##     interceptor only), but one flying straight that runs into one hits it.
##   - Hijacking (Hijack): another player on foot by the ship you sit in can take
##     it: thrown_out puts you on the ground beside her and stows her until they
##     let go (hijack_returned); theirs taken by you is a borrowed berth
##     (seat_taken), theirs again when you get out, eject or crash (hijack_let_go).
##
## The headless trace drives it with board(), takeoff(), land(), exit_ship(), eject() and
## set_external_command(): the same code paths the keys use.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const ChaseCamera := preload("res://src/systems/camera/chase_camera.gd")
const ShipDefense := preload("res://src/systems/flight/ship_defense.gd")
const ShipLoadout := preload("res://src/systems/flight/ship_loadout.gd")
const MissileLock := preload("res://src/systems/flight/missile_lock.gd")
const Dogfight := preload("res://src/systems/flight/dogfight.gd")
const SeekerWarning := preload("res://src/systems/flight/seeker_warning.gd")
const BoltScene := preload("res://scenes/entities/bolt.tscn")
const TownDecor := preload("res://src/systems/world/town_decor.gd")
const RemoteShip := preload("res://src/systems/net/remote_ship.gd")
const SCENE_PATH := "res://scenes/town_demo.tscn"
const CRASH_TOW_TIME := 2.5

signal boarded
signal exited
signal ejected                   ## issue #275: out of the seat in the air
signal left_atmosphere
signal fight_started
signal fight_ended(outcome: String)
signal cannon_fired(origin: Vector3, dir: Vector3, reach: float, bolt: Node)   ## LAN shows it to the others (unlocked seekers too)
signal woke                        ## the player respawned (woke_in_pit): SpeederPost lines their speeder up
signal hijack_let_go(peer: int, xf: Transform3D, wrecked: bool)   ## a ship you took from player `peer` is theirs again (Hijack)

var demo                         ## the town scene (town_demo.gd)
var content
var world: Dictionary = {}
var ground: WorldGround
var scenery: WorldScenery
var sky: AltitudeSky
var atmo: AtmoFlight
var ship_id := ""
var ship_cfg: Dictionary = {}
var pad: Dictionary = {}         ## the resolved home pad
var berths: Array = []           ## issue #43: { ship_id, cfg, visual, hull, home, home_yaw, clearance } per parked ship
var berth := 0                   ## the berth you fly (or last flew)
var home := Vector3.ZERO
var home_yaw := 0.0
var visual: Node3D
var hud: FlightHud
var chase = ChaseCamera.new()
var piloting := false
var ascending := false
var crash_left := -1.0
var log_events: Array = []      ## every AtmoFlight event, for traces and tests
var flight_time := 0.0          ## seconds since liftoff (for "how long to space")
var space_time := -1.0

var _throttle := 0.0
var _stick := Vector2.ZERO
var _external: Dictionary = {}   ## a bot's command; empty = read the keys
var _cam_near := 0.05
var _cam_far := 4000.0
var _rig_was_view := 0            ## the on-foot view (CameraRig.Mode) to give back on getting out
var _boost := false
var _motion_basis := Basis.IDENTITY
var _motion_basis_valid := false
var _foot_prompt: Label          ## "[E] Board" while standing at the ship
var jolt := BoardJolt.new(1.6, 1.4)   ## issue #87: the ship settles and lifts on its gear as you board
var _jolt_xf := Transform3D.IDENTITY
var hull: ShipHull               ## the ship's own collision: solid parked and flying (bolts hit it)
var defense                      ## issue #55: ShipDefense, the flown ship's shield and hull
var guns                         ## issue #55: ShipLoadout, its guns in the air
var _gun_reach := 300.0          ## where the guns cross with nothing nearer under the nose
var shots := 0                   ## bolts the guns fired in the air (traces, tests)
var seeker_lock                  ## MissileLock: the seekers' lock on the interceptor in the air
var seekers := 0                 ## seekers launched in the air (traces, tests)
var vessel_name := ""            ## issue #15: the ship's own name (same key as in space)
var planet_name := ""
var fight: SpaceFight            ## issue #46: the space encounter in progress, or null
var kit: ShipKit                 ## built once at load (on the town's materials) for every fight
var fight_log: Array = []        ## { outcome, payout, at } per sortie, for traces and tests
var space_exit_margin := 250.0   ## metres below the edge that break off a running fight
var travel: SpaceTravel          ## issue #45: the other planets in this sky, and flying to them
var _engine: AudioStreamPlayer   ## issue #16: the engine drone while the ship flies
var seeker_warning := SeekerWarning.new()   ## an enemy lock or seeker on her: alarm, text and dash lamp
var _alarm: AudioStreamPlayer    ## the seeker warning's alarm, made when it first sounds
var bay_landing := false          ## issue #75: Z near the bay: she is flying herself in
var bay_landings := 0             ## times that brought her down (traces, tests)
var docking := false              ## issue #193: Z by the cruiser: she is flying herself into its bay
var dockings := 0                 ## times that brought her down there (traces, tests)
var _dock_target = null           ## what she is docking in: the cruiser or a SpaceStation
var _dock_curve: Curve3D          ## the docking flight, one smooth curve from her to over the pad
var _dock_s := 0.0                ## metres along it so far
var _dock_v := 0.0                ## her speed along it
var _dock_bay := 0.0              ## its length from off the bay's mouth to the end (the gentle part)
var _dock_spin := -1.0            ## over the pad: seconds into turning round (-1: still flying in)
var _dock_yaw0 := 0.0             ## her heading when the turn round began
var _dock_drop := 0.0             ## how far the turn round lowers her (to just over the deck)
var _dock_y0 := 0.0
var _dock_to := ""                ## where Z is taking her ("<name> bay"), for the HUD
var _dock_head := 0.0             ## the curve's heading last frame (its turn rate banks her)
var steals := 0                   ## issue #76: outpost ships taken (traces, tests)
var opening := false              ## issue #202: the story's first landing (the autopilot; V and E only)
var opening_t := 0.0              ## seconds into it: the cinematic view has the first few to itself
var ejections := 0                ## issue #275: times the pilot ejected (traces, tests)
var pit_key := ""                 ## issue #368: whose ship stood on the pit pad when the town was built (Fleet key)
var fleet_placed := false         ## issue #368: place_fleet ran
var calling := false              ## issue #368: the primary is flying itself to you (call_ship)
var call_to := Vector3.ZERO       ## the ground she sets down on
var call_yaw := 0.0               ## her heading there (towards where you called from)
var calls := 0                    ## times a call brought her down (traces, tests)
var _eject_hold := 0.0            ## seconds B has been held
var _prefetch_speed := 45.0       ## issue #574: the walkable ground is built under her only slower than this (flow data)


func setup(town_scene) -> void:
	demo = town_scene


func _ready() -> void:
	name = "ShipPilot"
	_engine = Sound.carried_loop("ship_engine")   # one drone for every scene: a handoff never restarts it
	content = CoreContent.new()
	content.load_from()
	world = demo.world if "world" in demo and not demo.world.is_empty() else content.world_for_town("port_town")
	ground = WorldGround.new()
	var desert: DesertTerrain = demo.terrain
	if desert != null:
		ground.setup(world, demo.town, content, desert.height_at, desert.extent)
		# The mesas and hoodoos on screen are solid to the ship too.
		if demo.landforms != null:
			_late_landforms = true
			ground.add_landforms(demo.landforms.data, demo.desert_site().floor)
			ground.add_boulders(demo.landforms.boulders)      # issue #93: solid rocks, speeder ramps
		scenery = WorldScenery.new()
		scenery.setup(ground)
		demo.add_child(scenery)
		if demo.use_look:
			scenery.build_visuals(demo._flat_mats(), desert.material)
	else:
		ground.setup(world, demo.town, content)
	# Issue #45: a platform town's glass (and an asteroid's rock) are solid to ships.
	if "platform" in demo and demo.platform != null:
		demo.platform.add_to_ground(ground)
	if demo.use_look and demo.look != null:
		sky = AltitudeSky.new()
		sky.setup(demo.look, ground.atmosphere())
		demo.add_child(sky)
	var pads: Array = GameFlow.pads_for_scene(SCENE_PATH)
	pad = demo.resolve_pad(pads[0]) if not pads.is_empty() else {}
	var enc: Dictionary = content.get_encounter(str(pad.get("encounter", "")))
	# Issue #45: the ship you flew in on is on the pad; issue #368: else your primary.
	ship_id = Fleet.pit_ship(str(enc.get("player", {}).get("ship", "interceptor")), content.ships)
	pit_key = Fleet.pit_key()
	ship_cfg = content.get_ship(ship_id)
	atmo = AtmoFlight.new()
	atmo.setup(ship_cfg, ground)
	space_exit_margin = GameFlow.setting("space_exit_margin", space_exit_margin)
	_prefetch_speed = GameFlow.setting("prefetch_speed", _prefetch_speed)
	seeker_warning.configure(GameFlow.setting("seeker_alarm_secs", seeker_warning.alarm_secs),
		GameFlow.setting("seeker_alarm_rest", seeker_warning.rest_secs),
		GameFlow.setting("seeker_lamp_hz", seeker_warning.flash_hz))
	hud = FlightHud.new()
	add_child(hud)
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	_foot_prompt = Label.new()
	_foot_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_foot_prompt.position = Vector2(-300, -170)
	_foot_prompt.size = Vector2(600, 28)
	_foot_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_foot_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_foot_prompt.add_theme_constant_override("outline_size", 4)
	planet_name = NameHooks.planet(world)
	_foot_prompt.visible = false
	RetroUI.prompt(_foot_prompt)
	layer.add_child(_foot_prompt)
	kit = ShipKit.new(demo._flat_mats())
	chase.cine.blocked = _cine_clear
	_gather_berths()
	_use_berth(0)
	refresh_wreck_look()
	if "planet" in demo and not demo.planet.is_empty():
		travel = SpaceTravel.new()
		travel.staged = "staging" in demo and bool(demo.staging)    # issue #121: a handoff's first frame
		travel.setup(self, demo.planet.get("neighbours", []), demo.use_look)
		demo.add_child(travel)
	if str(demo._arrival.get("mode", "")) == "" and WorldState.opening_due():
		opening_landing.call_deferred()      # issue #202: the story (and a new free roam game) opens with the landing
	elif str(demo._arrival.get("mode", "")) == "reentry":
		reenter()
	elif str(demo._arrival.get("mode", "")) == "travel":
		arrive_from_space(demo._arrival)
	elif str(demo._arrival.get("mode", "")) == "handoff":
		arrive_handoff(demo._arrival)
	if not piloting:
		Sound.lib().set_radio("")            # issue #291: on foot (a lost fight, a new game), no radio


## Every parked ship the decor built becomes a berth: the pit pad's own ship first
## (berth 0, the pad's encounter ship), then each bay's. In the greybox there are no
## models, so a bare node stands in for the pit ship (the trace does not need to see
## it). Each berth's greybox box stops being solid: the ship carries its own hull, and
## the static box would stay behind as an invisible wall when the ship leaves.
func _gather_berths() -> void:
	if not berths.is_empty() and (demo.decor == null or demo.decor.parked_ships.is_empty()):
		return
	var parked: Array = demo.decor.parked_ships if demo.decor != null else []
	var c: Vector3 = pad.get("center", Vector3.ZERO)
	if parked.is_empty():
		var v := Node3D.new()
		v.name = "ShipStandIn"
		demo.add_child(v)
		v.position = c
		v.rotation.y = deg_to_rad(float(pad.get("parked_yaw_deg", 0.0)))
		parked = [v]
	for i in parked.size():
		var v: Node3D = parked[i]
		if berths.any(func(b): return b.visual == v):
			continue                         # issue #574: a handoff parks the bays' ships after the pad's: gathered again then
		var id := ship_id if i == 0 else str(v.get_meta("ship_id", ship_id))
		var box_id := str(pad.get("town_box", "ship")) if i == 0 else str(v.get_meta("box_id", ""))
		var bi := add_berth(v, id, box_id, pit_key if i == 0 else "")
		if i > 0 and bool(demo.town.get_box(box_id).get("free", false)):
			berths[bi]["free"] = true        # issue #316: the station's frigate, anyone's to fly


## Issue #574: a handoff builds the bays' ships and the landforms after its
## first frame; they join the ground and the berths here.
func town_built_late() -> void:
	_gather_berths()
	if demo.landforms != null and not _late_landforms:
		_late_landforms = true
		ground.add_landforms(demo.landforms.data, demo.desert_site().floor)
		ground.add_boulders(demo.landforms.boulders)
var _late_landforms := false


## A parked ship becomes one you can board: its data, model, hull and home bay.
## Issue #58: also how a ship bought from T-89 joins once it is on the spare pad.
## Issue #368: `key` is the Fleet key of one of your own (yours to fly; never lost
## for good to ships_destroyed). Returns its berth index.
func add_berth(v: Node3D, id: String, box_id: String, key: String = "") -> int:
	var i := berths.size()
	var b := {
		"ship_id": id, "cfg": ship_cfg if i == 0 else content.get_ship(id), "visual": v,
		"home": v.global_position, "home_yaw": v.rotation.y, "clearance": atmo.clearance,
	}
	var acc := [null]
	TownDecor._merge_aabb(v, Transform3D.IDENTITY, acc)
	if acc[0] != null:
		b.clearance = maxf(0.3, -(acc[0] as AABB).position.y)
	_disable_box(box_id)
	b.hull = _build_hull(v, acc[0], box_id, b.clearance)
	b.hull.on_damage = _on_hull_hit.bind(i)
	b.box_id = box_id
	b.destroyed = false
	b.key = key
	if key != "":
		b.owned = true
	berths.append(b)
	if key == "" and WorldState.ships_destroyed.has(box_id):
		_wreck_berth(i, false)          # issue #64: shot to pieces in an earlier session
	return i


## Issue #76: a Remnant ship parked at a desert outpost. Flyable, but boarding it
## the first time sets off that outpost's alarm (and scrambles the barracks
## interceptor, AtmoFighter). Lost (shot down or crashed), it is gone and you wake
## in the pit. Not saved: a new session finds it back at its outpost. The barracks
## pad's interceptor is one too while it stands there (AtmoFighter._offer_berth).
func add_outpost_berth(v: Node3D, id: String, outpost_id: String) -> int:
	var i := add_berth(v, id, "outpost_ship_" + outpost_id)
	berths[i]["outpost"] = outpost_id
	berths[i]["stolen"] = false
	return i


## Berth `b`'s ship name: an outpost's ship goes by its "locals_label" while the
## locals hold that outpost ("(Local)", not "(Remnant)").
static func berth_label(b: Dictionary) -> String:
	var cfg: Dictionary = b.get("cfg", {})
	if b.has("outpost") and Territory.owner(str(b.outpost)) == Territory.LOCALS:
		return str(cfg.get("locals_label", cfg.get("label", "")))
	return str(cfg.get("label", ""))


## Issue #206: the pit pad's ship looks wrecked (WreckLook) while a story save's
## ship waits for T-89, and like new once he has rebuilt it.
func refresh_wreck_look() -> void:
	if berths.is_empty() or not is_instance_valid(berths[0].visual):
		return
	if ShipSalesman.needs_rebuild() and GameFlow.flown_ship == "":
		WreckLook.apply(berths[0].visual)
	else:
		WreckLook.remove(berths[0].visual)


## May the player board berth `i`? (berth_open: the rule.)
func berth_flies(i: int) -> bool:
	return berth_open(berths[i], i)


## Issue #64: the port's ships fly once Oda tells you about the fleet. Issue #206:
## a story save has no free keys in the pit: only a ship you own flies (berth 0,
## the pit pad's, once T-89 rebuilt your wreck or when you flew in on it; one he
## sold you, "owned"). An outpost's ship is still there to steal once ships fly.
static func berth_open(b: Dictionary, i: int) -> bool:
	if bool(b.get("owned", false)) or bool(b.get("free", false)):
		return true
	if not WorldState.story_mode() or b.has("outpost"):
		return Story.ships_unlocked()
	return i == 0 and (WorldState.has_flag(WorldState.SHIP_REBUILT) or GameFlow.flown_ship != "")


## Why berth `i` will not fly, as a Story line key.
func locked_line(i: int) -> String:
	if not WorldState.story_mode() or berths[i].has("outpost"):
		return "ship_locked"
	return "ship_wreck" if i == 0 else "ship_not_yours"


## Flying a ship taken from an outpost (the barracks interceptor hunts it).
func flying_stolen() -> bool:
	return piloting and bool(berths[berth].get("stolen", false))


## Issue #58: the last berth leaves (sold back to T-89): its model goes, and you
## fly the pit pad's ship again if it was the one you last flew. Not while you sit
## in it. Returns true when it went.
func remove_last_berth() -> bool:
	var i := berths.size() - 1
	if i <= 0 or (piloting and berth == i):
		return false
	if berth == i:
		_use_berth(0)
	var v: Node3D = berths[i].visual
	berths.remove_at(i)
	if demo.decor != null:
		demo.decor.parked_ships.erase(v)
	v.queue_free()
	return true


## Issue #295: berth `i` sold to Skrugs. It goes for good the way a lost stolen
## ship does (_lose_stolen), but you stay where you are: a stolen one's chase ends
## with it, and the one T-89 sold you frees his pad. Never the pit pad's own ship
## (berth 0 when it is nobody's; issue #368: one of yours there may go), never the
## one you sit in. True when it went.
func sell_berth(i: int) -> bool:
	if i < 0 or i >= berths.size() or bool(berths[i].get("destroyed", false)) or (piloting and berth == i):
		return false
	if i == 0 and berth_key(0) == "":
		return false
	if calling and i == berth:
		return false
	berths[i]["stolen"] = false
	_wreck_berth(i, false, true)
	return true


## Issue #207: T-89 fitted an upgrade: the parked ship you fly takes it now
## (in the air it waits for the next landing), and an upgrade with a paint job
## repaints its ship (ShipUpgrades.look). Every owned ship shows its parts at once.
func refit() -> void:
	for b in berths:
		if not bool(b.get("destroyed", false)) and is_instance_valid(b.visual):
			var base := str(content.get_ship(str(b.ship_id)).get("look", ""))
			kit.repaint(b.visual, ShipUpgrades.look(str(b.ship_id), base))
			if b.visual.has_meta("look_id"):
				kit.dress(b.visual, ShipUpgrades.fitted(str(b.ship_id)))
	if not piloting and not berths.is_empty():
		_use_berth(berth)


## Fly berth `i` from now on: its data, model, hull and home bay. It is parked
## wherever its model stands.
func _use_berth(i: int) -> void:
	var b: Dictionary = berths[i]
	berth = i
	ship_id = b.ship_id
	ship_cfg = ShipUpgrades.apply(b.cfg, ship_id)      # issue #207: what T-89 fitted
	visual = b.visual
	hull = b.hull
	home = b.home
	home_yaw = b.home_yaw
	atmo.setup(ship_cfg, ground)
	atmo.clearance = b.clearance
	atmo.park(visual.global_position, _yaw_of(visual.global_transform))
	_sync_visual()
	defense = ShipDefense.new(ship_cfg)
	guns = ShipLoadout.new(ship_cfg, content)
	_gun_reach = guns.convergence
	seeker_lock = MissileLock.new()
	seeker_lock.configure(guns.group_config("secondary"))
	vessel_name = NameHooks.vessel(ship_cfg, "vessel:player/" + ship_id)
	hud.vessel_name = vessel_name
	var look: Dictionary = kit.looks.get(str(ship_cfg.get("look", "")), {})
	chase.fit_to(float(look.get("length", 9.0)))


## The ship's own shape, in its own frame, travelling with it: you can walk up to
## (not through) a parked ship wherever it landed, and under its wings. Fitted to
## the model (ShipHull.fit); a box from the pad in the greybox.
func _build_hull(v: Node3D, model_box, box_id: String, clear: float) -> ShipHull:
	var body := ShipHull.new()
	body.name = "ShipHull"
	if model_box != null and body.fit(v):
		v.add_child(body)
		return body
	var size := Vector3(9.0, 2.5, 8.0)
	var center := Vector3.ZERO
	if model_box != null:
		size = (model_box as AABB).size
		center = (model_box as AABB).get_center()
	else:
		var box: Dictionary = demo.town.get_box(box_id)
		if not box.is_empty():
			var w := WorldGround._v3(box.max) - WorldGround._v3(box.min)
			var c := absf(cos(v.rotation.y))
			var sn := absf(sin(v.rotation.y))
			size = Vector3(c * w.x + sn * w.z, w.y, sn * w.x + c * w.z)
			center = Vector3(0, w.y * 0.5 - clear, 0)
	body.fit_box(size, center)
	v.add_child(body)
	return body


func _set_hull(solid: bool) -> void:
	if hull != null:
		for ch in hull.get_children():
			if ch is CollisionShape3D:
				ch.set_deferred("disabled", not solid)


func _disable_box(box_id: String) -> void:
	var body: Node = demo.get_node_or_null("Town/" + box_id)
	if body == null:
		return
	for ch in body.get_children():
		if ch is CollisionShape3D:
			ch.disabled = true


# ------------------------------------------------------------------ queries

func player() -> CharacterBody3D:
	return demo._player


func is_parked_home() -> bool:
	return atmo.state == AtmoFlight.State.PARKED and Vector2(atmo.position().x - home.x, atmo.position().z - home.z).length() < 3.0


## On foot, close enough to a parked ship to climb in.
func can_board() -> bool:
	return nearest_berth() >= 0


## The berth you are close enough to board (the nearest), or -1. Every ship but the
## one you fly is always parked; that one only while it is on the ground.
func nearest_berth() -> int:
	var p := player()
	if piloting or p == null:
		return -1
	var reach := float(pad.get("board_reach", 9.0))
	var best := -1
	var best_d := INF
	if calling:
		return -1                 # issue #368: not while your primary flies itself in
	# Issue #276: while the ship you ejected from is still coming down (or waiting
	# for her tow) she is the berth flown: no switching to another until she is down.
	var settling := atmo.state == AtmoFlight.State.ADRIFT or crash_left >= 0.0
	for i in berths.size():
		if i == berth and atmo.state != AtmoFlight.State.PARKED:
			continue
		if i != berth and settling:
			continue
		if bool(berths[i].get("destroyed", false)):
			continue
		var v: Node3D = berths[i].visual
		var s := v.global_position
		var d := Vector2(p.global_position.x - s.x, p.global_position.z - s.z).length()
		if d <= reach and d < best_d and absf(p.global_position.y - (s.y - float(berths[i].clearance))) <= 4.0:
			best = i
			best_d = d
	return best


# ------------------------------------------------------------------ actions

func board() -> bool:
	var i := nearest_berth()
	if i < 0 or not berth_flies(i):
		return false
	return board_berth(i)


## Into the seat of berth `i`, wherever it is (board() checks you stand at it and
## may fly it; a hijack has already put you on top of it).
func board_berth(i: int) -> bool:
	if piloting or i < 0 or i >= berths.size() or player() == null:
		return false
	if i != berth:
		_use_berth(i)
	if berths[i].has("outpost") and not bool(berths[i].stolen) and not bool(berths[i].get("borrowed", false)):
		_steal(i)
	if hud.cockpit != null:
		hud.cockpit.hull_material = ShipKit.skin(visual)
	var p := player()
	piloting = true
	_motion_basis = atmo.flight.basis
	_motion_basis_valid = true
	_foot_prompt.visible = false
	p.piloting = true
	p.vehicle = self
	p.locked = true
	p.velocity = Vector3.ZERO
	p.visible = false
	p.process_mode = Node.PROCESS_MODE_DISABLED
	_set_player_collision(false)
	_ground_follow(null)
	_throttle = 0.0
	_stick = Vector2.ZERO
	var rig = demo._rig
	if rig != null:
		_rig_was_view = rig.rig.mode
		var cam: Camera3D = rig.camera()
		_cam_near = cam.near
		_cam_far = cam.far
		cam.near = 0.3
		cam.far = 160000.0
	chase._primed = false
	hud.visible = true
	if atmo.state == AtmoFlight.State.PARKED:
		jolt.start()
	boarded.emit()
	return true


func exit_ship() -> bool:
	if not piloting or atmo.state != AtmoFlight.State.PARKED:
		return false
	var spot := _exit_spot()
	_leave_seat(spot)
	_remember(berth)                   # issue #368: one of yours stays where you left it
	if opening:
		opening = false
		chase.fit_to(_look_length())
		if chase.is_cinematic():
			chase.set_mode(chase.Mode.CHASE)    # the opening's view, not one the player picked
		Story.event("landed")          # issue #202: out of the ship; the general is waiting
		WorldState.set_flag(WorldState.FREE_OPENING, false)    # free roam: no general, and the landing played once
	exited.emit()
	_drop_hijacked(false)              # one you took from another player is theirs again
	return true


## Issue #275: B held in the air. Not on the ground (E gets you out), in space or a
## fight, or while an autopilot the story needs has her.
func can_eject() -> bool:
	return piloting and not opening and not docking and not _fight_flying() \
		and (atmo.state == AtmoFlight.State.FLYING or atmo.state == AtmoFlight.State.LANDING) \
		and atmo.altitude() < atmo.space_altitude


## Your own ship flies itself home when you eject; a stolen (or borrowed) one, or one
## that is nobody's, has nobody to take it and comes down ADRIFT.
func ejecting_flies_home() -> bool:
	var b: Dictionary = berths[berth]
	return berth_key() != "" and not bool(b.get("stolen", false)) and not bool(b.get("borrowed", false))


## Out of the seat in mid air: thrown clear (above and behind) with the ship's own
## speed and a kick up, falling on foot from there. The empty ship flies on ADRIFT,
## unless she is yours: then she flies home (_fly_home) and waits on her pad.
func eject() -> bool:
	if not can_eject():
		return false
	var u := atmo.up()
	var v: Vector3 = atmo.flight.velocity()
	var b: Basis = atmo.flight.basis
	var spot := atmo.position() + u * (atmo.clearance + GameFlow.setting("eject_clear_up", 4.0)) \
		+ b.z * GameFlow.setting("eject_clear_back", 6.0)
	bay_landing = false
	_eject_hold = 0.0
	if atmo.state == AtmoFlight.State.LANDING:
		v -= u * atmo.p("land_descent", 12.0)
	var flies_home := ejecting_flies_home()
	if not flies_home:
		atmo.abandon()
	_leave_seat(spot)
	if flies_home:
		_fly_home()
	var p := player()
	var climb := v.dot(u)
	var flat := (v - u * climb).limit_length(GameFlow.setting("eject_push_max", 60.0))
	var rise := u * (climb + GameFlow.setting("eject_kick", 12.0))
	if p.has_method("launch"):
		p.call("launch", rise, flat, GameFlow.setting("eject_push_fade", 14.0))   # her way on, fading in the air
	else:
		p.velocity = rise
	if demo.terrain != null:
		demo.terrain.prefetch(spot)
	ejections += 1
	var e := { "type": "ejected", "at": spot, "speed": v.length(), "altitude": atmo.altitude() }
	e["t"] = flight_time
	log_events.append(e)
	ejected.emit()
	_drop_hijacked(false)              # one you took from another player: theirs, on the ground below
	return true


## Issue #276 follow-up: an ejected ship of yours is not simulated down. She is on her
## pad at once (no fall, no crash, nothing for the garrison to shoot) and the ledger's
## Call brings her back.
func _fly_home() -> void:
	atmo.park(home, home_yaw)
	_set_hull(true)
	if visual != null:
		visual.visible = true
	_sync_visual()
	_remember(berth)
	var line := "eject_home_call" if berth_key() == Fleet.primary() else "eject_home"
	_foot_toast(GameFlow.label(line))


## Out of the seat at `spot`: the player is back on foot (seen, solid, moving), the
## camera theirs again, the flight HUD gone. Motion is cleared: an ejection
## gives them the ship's afterwards.
func _leave_seat(spot: Vector3) -> void:
	var p := player()
	piloting = false
	Sound.lib().set_radio("")        # issue #291: the radio is the ship's
	_motion_basis_valid = false
	if demo.detail != null:
		demo.detail.update_motion(0.0, atmo.altitude(), 0.0, 0.0, false)
	_set_flight_terrain_quality(false)
	p.piloting = false
	p.vehicle = null
	p.locked = false
	p.process_mode = Node.PROCESS_MODE_INHERIT
	p.visible = true
	_set_player_collision(true)
	p.global_position = spot
	var rig = demo._rig
	if rig != null:
		rig.clear_override()
		# The ship's heading, read in the ground's own frame (issue #77: on the ball).
		rig.rig.yaw = (PlanetSphere.tilt_to(atmo.up()).inverse() * atmo.flight.basis).get_euler().y
		p.rotation.y = rig.rig.yaw
		if "player_kit" in demo and demo.player_kit != null and demo.player_kit.avatar != null:
			demo.player_kit.avatar.facing_yaw = rig.rig.yaw
		rig.set_view(_rig_was_view)
		var cam: Camera3D = rig.camera()
		cam.near = _cam_near
		cam.far = _cam_far
	if p.has_method("align_to_ground"):
		p.call("align_to_ground", true)
	else:
		p.velocity = Vector3.ZERO
		p.controller.velocity = Vector3.ZERO
		p.controller.body_pos = spot
	_ground_follow(p)
	hud.visible = false
	if sky != null:
		sky.update_for(ground.altitude(spot), spot)


func takeoff() -> bool:
	if not piloting or not atmo.takeoff():
		return false
	flight_time = 0.0
	return true


## In space the only ground to land on is the cruiser's: a fight running there goes
## on without her while she is down (_out_of_fight), as Z's docking does.
func land() -> bool:
	if not piloting or not atmo.can_land():
		return false
	return atmo.land()


# ------------------------------------------------------------------ Z: land in the bay (issue #75)

## Close enough to your bay (across the ground, below space) for Z to bring you in.
func near_bay() -> bool:
	if not piloting or _fight_flying() or atmo.state != AtmoFlight.State.FLYING:
		return false
	var p := atmo.position()
	return Vector2(p.x - home.x, p.z - home.z).length() <= GameFlow.setting("bay_land_radius", 4000.0) \
		and atmo.altitude() < atmo.space_altitude


## Z: fly her over the bay and set her down on her own pad, on any planet. False
## when not near enough (or not flying).
func bay_land() -> bool:
	if bay_landing or not near_bay():
		return false
	bay_landing = true
	_throttle = 0.0
	hud.toast(GameFlow.label("bay_landing") % bay_place(), 3.0)
	return true


## One frame of the autopilot: across to a point high over the pad (higher than
## anything in the town), turning to the pad's heading on the way in, then
## straight down with the normal landing.
func _bay_step(dt: float) -> void:
	var f = atmo.flight
	var pos: Vector3 = f.position
	var flat := Vector2(home.x - pos.x, home.z - pos.z)
	var d := flat.length()
	var hold := home.y + atmo.clearance + 60.0
	if d < 0.5:
		f.position = Vector3(home.x, pos.y, home.z)
		f.speed = 0.0
		f.basis = Basis(Vector3.UP, home_yaw)
		if pos.y > hold + 2.0:
			f.position.y = move_toward(pos.y, hold, maxf(10.0, (pos.y - hold) * 0.9) * dt)
			return
		bay_landing = false
		if atmo.land():
			bay_landings += 1
		return
	var v := clampf(d * 0.7, 3.0, 90.0)
	var step := flat.normalized() * minf(v * dt, d)
	var ty := hold if d < 250.0 else maxf(pos.y, hold)
	f.position = Vector3(pos.x + step.x, move_toward(pos.y, ty, maxf(8.0, absf(pos.y - ty) * 0.8) * dt), pos.z + step.y)
	var yaw := atan2(-flat.x, -flat.y) if d > 30.0 else home_yaw
	f.basis = f.basis.slerp(Basis(Vector3.UP, yaw), minf(1.0, dt * 2.0)).orthonormalized()
	f.speed = v


# ------------------------------------------------------------------ Z: dock in the cruiser (issue #193)

## The Remnant cruiser in this sky (RemnantCruiser), or null. Untyped on purpose:
## the cruiser's crew are NpcBodies, which need the autoloads, and the headless
## traces compile this script before those exist.
func cruiser():
	var c = demo.get("cruiser") if demo != null else null
	return c if c != null and is_instance_valid(c) else null


## Close enough to the cruiser for Z to take her into its bay.
func near_cruiser() -> bool:
	var c = cruiser()
	return piloting and c != null and atmo.state == AtmoFlight.State.FLYING and c.can_dock(atmo.position())


## The space stations in this sky (SpaceStation), untyped for the same reason.
func stations() -> Array:
	var list = demo.get("stations") if demo != null else null
	return (list as Array).filter(func(s): return is_instance_valid(s)) if list is Array else []


## The station `p` is aboard, or null.
func station_aboard(p: Vector3):
	for s in stations():
		if s.aboard(p):
			return s
	return null


## What Z flies her into from here: the cruiser in reach, else a space station in
## reach (both answer can_dock, dock_path, dock_yaw, dock_cfg and line), else null.
func dock_target():
	if not piloting or atmo.state != AtmoFlight.State.FLYING:
		return null
	var p := atmo.position()
	var c = cruiser()
	if c != null and c.can_dock(p):
		return c
	for s in stations():
		if s.can_dock(p):
			return s
	return null


func near_dock() -> bool:
	return dock_target() != null


## Z by the cruiser: she flies herself round the hull and in. A fight running is not
## broken off: it goes on without her while she docks and is down in the bay
## (_out_of_fight), and she is back in it when she flies out. False when not near
## enough.
func dock() -> bool:
	if docking or not near_dock():
		return false
	var c = dock_target()
	_dock_target = c
	var f = atmo.flight
	var pts: Array = c.dock_path(atmo.position())
	bay_landing = false
	docking = true
	_dock_curve = dock_curve(atmo.position(), f.forward(), pts)
	_dock_s = 0.0
	_dock_v = maxf(float(f.speed), 20.0)
	_dock_spin = -1.0
	_dock_head = f.basis.get_euler().y
	var mouth: Vector3 = pts[maxi(pts.size() - 3, 0)]
	_dock_bay = _dock_curve.get_baked_length() - _dock_curve.get_closest_offset(mouth)
	_throttle = 0.0
	_dock_to = dock_place()
	hud.toast(c.line("docking") % _dock_to, 3.0)
	return true


## The docking flight as one curve: from `from`, leaving along `heading` (so taking
## over does not snap her round), through each point of `pts`, the last three (off
## the bay's mouth, the apron, over the pad) on one straight line in through the
## shield. Each point's handles run along the way through it, a third of the
## shorter leg long, so the curve stays close to the path round the hull.
static func dock_curve(from: Vector3, heading: Vector3, pts: Array) -> Curve3D:
	var all: Array = [from]
	for p in pts:
		if (p as Vector3).distance_to(all[all.size() - 1]) > 1.0:
			all.append(p)
	var curve := Curve3D.new()
	curve.bake_interval = 1.0
	var n := all.size()
	var into: Vector3 = ((all[n - 1] as Vector3) - (all[maxi(n - 3, 0)] as Vector3)).normalized()
	for i in n:
		var p: Vector3 = all[i]
		var prev: Vector3 = all[maxi(i - 1, 0)]
		var next: Vector3 = all[mini(i + 1, n - 1)]
		var dir: Vector3 = (next - prev).normalized()
		if i == 0:
			dir = heading.normalized()
		elif i >= n - 3:
			dir = into
		var reach := 300.0
		if i > 0:
			reach = minf(reach, p.distance_to(prev) * 0.35)
		if i < n - 1:
			reach = minf(reach, p.distance_to(next) * 0.35)
		curve.add_point(p, -dir * reach, dir * reach)
	return curve


## Where Z takes her from here: the cruiser's bay by its name when it is in reach
## (Z docks first), else your own bay on this planet by its town's ("Quartzspring
## bay"); "" when neither.
func dock_place() -> String:
	if near_dock():
		var c = dock_target()
		return GameFlow.label("bay_place") % (c.vessel_name if c.vessel_name != "" else c.label())
	if near_bay():
		return bay_place()
	return ""


## Your bay on this planet, by its town's name (else the planet's).
func bay_place() -> String:
	var town := NameHooks.town(world)
	var place := town if town != "" else planet_name
	return GameFlow.label("bay_place") % place if place != "" else GameFlow.label("bay_place_none")


## One frame of the docking autopilot: along the curve, quick out in space and
## braking gently from off the bay's mouth, nose along the way and banked into
## the turns, through the shield to a stop over the pad; then she turns round on
## the spot to the pad's heading (nose out to space) as she sinks to just over
## the deck, and the normal landing sets her down.
func _dock_step(dt: float) -> void:
	var c = _dock_target if _dock_target != null and is_instance_valid(_dock_target) else null
	if c == null or _dock_curve == null:
		docking = false
		return
	var f = atmo.flight
	var dc: Dictionary = c.dock_cfg()
	if _dock_spin >= 0.0:
		_dock_turn(dt, c, dc)
		return
	var length := _dock_curve.get_baked_length()
	var left := length - _dock_s
	# The fastest she can go and still stop over the pad: gently inside the bay's
	# stretch, hard out in space, never past the cruise speed.
	var b_in := float(dc.get("brake_in", 22.0))
	var cap := sqrt(2.0 * b_in * minf(left, _dock_bay))
	if left > _dock_bay:
		cap = sqrt(cap * cap + 2.0 * float(dc.get("brake", 160.0)) * (left - _dock_bay))
	cap = minf(cap, float(dc.get("speed", 500.0)))
	_dock_v = maxf(minf(move_toward(_dock_v, cap, float(dc.get("accel", 220.0)) * dt), cap), 2.0)
	_dock_s = minf(_dock_s + _dock_v * dt, length)
	var at := _dock_curve.sample_baked(_dock_s, true)
	var ahead := _dock_curve.sample_baked(minf(_dock_s + maxf(6.0, _dock_v * 0.3), length), true)
	f.position = at
	f.speed = _dock_v
	var to := ahead - at
	if to.length() > 0.5 and Vector2(to.x, to.z).length() > 0.05 * to.length():
		var look := Basis.looking_at(to, Vector3.UP)
		var head: float = look.get_euler().y
		var turn := wrapf(head - _dock_head, -PI, PI) / maxf(dt, 0.0001)
		_dock_head = head
		var bank := clampf(turn * 0.35, -0.7, 0.7)
		f.basis = f.basis.slerp(look * Basis(Vector3.BACK, bank), minf(1.0, dt * 5.0)).orthonormalized()
	if left <= 0.01:
		_dock_spin = 0.0
		_dock_yaw0 = f.basis.get_euler().y
		_dock_y0 = f.position.y
		_dock_drop = maxf(atmo.agl() - float(dc.get("settle", 3.0)), 0.0)
		f.speed = 0.0


## Over the pad: turn round to its heading, easing in and out, and sink to just
## over the deck; then the normal landing.
func _dock_turn(dt: float, c, dc: Dictionary) -> void:
	var f = atmo.flight
	var secs := maxf(float(dc.get("spin_secs", 1.3)), 0.01)
	_dock_spin += dt
	var k := smoothstep(0.0, 1.0, minf(_dock_spin / secs, 1.0))
	var yaw := _dock_yaw0 + wrapf(float(c.dock_yaw()) - _dock_yaw0, -PI, PI) * k
	f.basis = Basis(Vector3.UP, yaw)
	f.position.y = _dock_y0 - _dock_drop * k
	f.speed = 0.0
	if k < 1.0:
		return
	docking = false
	_dock_curve = null
	if atmo.land():
		dockings += 1
		hud.toast(c.line("docked"), 3.0)


## A bot's command for this frame and on: { pitch, yaw, roll, throttle, boost }.
## Pass {} to give control back to the keys.
func set_external_command(c: Dictionary) -> void:
	_external = c


## Back from space: start in the sky above the port, flying toward it.
## The space encounter over this planet: the planet's own ("" = quiet sky), else
## the pad's (issue #45).
func encounter_id() -> String:
	if cruiser() != null and atmo != null and cruiser().wants_escort(atmo.position(), atmo.flight.forward()):
		return cruiser().escort_id()      # issue #193: Oda said you'd have company on the way up (#327: or you fly for the belt cruiser)
	var e = demo.planet.get("encounter", null) if "planet" in demo else null
	return str(e) if e != null else str(pad.get("encounter", ""))


## Issue #45: in from another planet. Seated in the ship you flew (it is parked on
## this bay's pad, berth 0), flying, high over the bay on the side you came from,
## nose down at the town.
func arrive_from_space(a: Dictionary) -> void:
	var tcfg: Dictionary = demo.planet.get("type_cfg", {})
	var arr: Dictionary = tcfg.get("arrival", {})
	var c: Vector3 = pad.get("center", Vector3.ZERO)
	var from := Vector2(0, 1)
	for n in demo.planet.get("neighbours", []):
		if str(n.id) == str(a.get("from", "")):
			var at: Vector3 = n.at
			from = Vector2(at.x - c.x, at.z - c.z).normalized()
	var dist := float(arr.get("distance", pad.get("reentry_distance", 3250.0)))
	var alt := float(arr.get("altitude", pad.get("reentry_altitude", 2600.0)))
	_seat_arriving()
	var at := Vector3(c.x + from.x * dist, alt, c.z + from.y * dist)
	var to := Vector3(c.x - at.x, 0.0, c.z - at.z).normalized()
	var pitch := deg_to_rad(float(pad.get("reentry_pitch_deg", -18.0)))
	var facing := (to * cos(pitch) + Vector3(0, sin(pitch), 0)).normalized()
	atmo.place_flying(at, facing, 0.0, 0.6)
	atmo.flight.speed = atmo.flight.cruise_speed(0.6) * atmo.air_scale()
	_throttle = 0.6
	_set_hull(true)
	chase._primed = false
	hud.visible = true
	hud.toast(GameFlow.arrival_text(a), 5.0)
	_sync_visual()


## Issue #99: in from another planet with no fade. The ship carries on exactly
## where it was (the travel worked out where that is in this planet's own
## coordinates), same heading, speed and throttle, still flying.
func arrive_handoff(a: Dictionary) -> void:
	var h: Dictionary = a.get("handoff", {})
	_seat_arriving()
	var at: Vector3 = h.get("position", Vector3(0, 3000, 0))
	var b: Basis = h.get("basis", Basis.IDENTITY)
	var thr := float(h.get("throttle", 0.6))
	atmo.place_flying(at, -b.z, float(h.get("speed", 0.0)), thr)
	atmo.flight.basis = b
	_throttle = thr
	# Already up there when the scene began: not a climb out (no sortie, no fight).
	atmo.reached_space = atmo.altitude() >= atmo.space_altitude
	ascending = atmo.reached_space
	_set_hull(true)
	# The camera where it was behind the ship, in the same view, still lagging.
	chase.mode = int(h.get("camera_mode", chase.mode))
	if h.has("camera"):
		chase.xform = atmo.transform() * (h.camera as Transform3D)
		chase._primed = true
	else:
		chase._primed = false
	# Straight onto that view: no blend in from the on-foot camera, which stands on
	# the town's ground (a dark, turned frame at the switch).
	if demo._rig != null:
		demo._rig.snap_override(chase.update(0.0, atmo.transform()), 72.0)
	hud.visible = true
	_update_hud(atmo.agl())       # its numbers on the first frame too, not one later
	_sync_visual()
	if demo.terrain != null and atmo.agl() < 60.0:
		demo.terrain.prefetch(at)       # issue #574: only when there is ground near to step out on
	if sky != null:
		sky.update_for(atmo.altitude(), at)


## Put the player in the cockpit without the walk up to the ship.
func _seat_arriving() -> void:
	var p := player()
	if p == null or piloting:
		return
	piloting = true
	p.piloting = true
	p.vehicle = self
	_ground_follow(null)
	p.locked = true
	p.visible = false
	p.process_mode = Node.PROCESS_MODE_DISABLED
	_set_player_collision(false)
	var rig = demo._rig
	if rig != null:
		_rig_was_view = rig.rig.mode
		var cam: Camera3D = rig.camera()
		_cam_near = cam.near
		_cam_far = cam.far
		cam.near = 0.3
		cam.far = 160000.0


## Issue #202: a story save opens with your ship coming down into the pit as if
## the autopilot were bringing it in, the camera far back. Nothing but V (change
## view) does anything until she is down; then E gets you out (exit_ship), and
## the story moves on ("landed"). The pad's "opening" sets where she starts.
## It is filmed in the cinematic view; the story's "opening_cinematic_secs" in, the
## prompt says V changes it and J the radio, which comes on to the story's
## "opening_radio" station (the desert cantina mix).
func opening_landing() -> void:
	_seat_arriving()
	Sound.lib().set_radio(str(Story.data().get("opening_radio", "")))
	var o: Dictionary = pad.get("opening", {})
	var bearing := deg_to_rad(float(o.get("bearing_deg", pad.get("reentry_bearing_deg", 200.0))))
	var dist := float(o.get("distance", 700.0))
	var at := Vector3(home.x + sin(bearing) * dist, home.y + float(o.get("altitude", 220.0)), home.z + cos(bearing) * dist)
	var to := Vector3(home.x - at.x, 0.0, home.z - at.z).normalized()
	atmo.place_flying(at, to, 0.0, 0.4)
	_throttle = 0.0
	opening = true
	opening_t = 0.0
	bay_landing = true
	chase._primed = false
	chase.fit_to(_look_length() * float(o.get("camera_scale", 3.5)))
	chase.set_mode(chase.Mode.CINE)
	hud.visible = true
	_sync_visual()


## The cinematic view's ray (ChaseCamera.cine): how far from the ship toward a
## shot is clear, so a shot never sits inside the pit's walls or under the ground.
## Her own hull is not in the way.
func _cine_clear(from: Vector3, to: Vector3) -> Vector3:
	var space: PhysicsDirectSpaceState3D = demo.get_world_3d().direct_space_state if demo.is_inside_tree() else null
	if space == null:
		return to
	var q := PhysicsRayQueryParameters3D.create(from, to)
	if hull != null and is_instance_valid(hull):
		q.exclude = [hull.get_rid()]
	q.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(q)
	return to if hit.is_empty() else hit.position - (to - from).normalized()


func _look_length() -> float:
	return float(kit.looks.get(str(ship_cfg.get("look", "")), {}).get("length", 9.0)) if kit != null else 9.0


## Wingtip to wingtip, from the ship's look (content/look/ships.json "span").
func _look_span() -> float:
	return float(kit.looks.get(str(ship_cfg.get("look", "")), {}).get("span", 8.0)) if kit != null else 8.0


func reenter() -> void:
	_seat_arriving()
	var c: Vector3 = pad.get("center", Vector3.ZERO)
	var bearing := deg_to_rad(float(pad.get("reentry_bearing_deg", 200.0)))
	var dist := float(pad.get("reentry_distance", 6500.0))
	var alt := float(pad.get("reentry_altitude", 5200.0))
	var at := Vector3(c.x + sin(bearing) * dist, alt, c.z + cos(bearing) * dist)
	var to := Vector3(c.x - at.x, 0.0, c.z - at.z).normalized()
	var pitch := deg_to_rad(float(pad.get("reentry_pitch_deg", -18.0)))
	var facing := (to * cos(pitch) + Vector3(0, sin(pitch), 0)).normalized()
	atmo.place_flying(at, facing, 0.0, 0.6)
	atmo.flight.speed = atmo.flight.cruise_speed(0.6) * atmo.air_scale()
	_throttle = 0.6
	chase._primed = false
	hud.visible = true
	hud.toast(GameFlow.arrival_text(demo._arrival), 5.0)
	_sync_visual()


# ------------------------------------------------------------------ frame

func _unhandled_input(event: InputEvent) -> void:
	if not piloting:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_stick.x = clampf(_stick.x + event.relative.x * 0.004, -1.0, 1.0)
		_stick.y = clampf(_stick.y - event.relative.y * 0.004, -1.0, 1.0)
	if InputMap.has_action("toggle_view") and event.is_action_pressed("toggle_view"):
		chase.toggle_mode()
	if fight != null and InputMap.has_action("flight_next_target") and event.is_action_pressed("flight_next_target"):
		fight.next_target()
	if InputMap.has_action("flight_radio") and event.is_action_pressed("flight_radio"):
		hud.toast(radio_line(Sound.radio_next()), 3.0)


## Issue #291: what the HUD says when the radio changes station.
static func radio_line(playlist: String) -> String:
	return GameFlow.label("radio_" + playlist if playlist != "" else "radio_off")


func _physics_process(dt: float) -> void:
	if atmo == null:
		return
	if fight != null and not piloting:
		_shelter()                     # out of the seat: out of the fight, which goes on
	if not piloting:
		_on_foot()
		if atmo.state == AtmoFlight.State.ADRIFT:
			_adrift_step(dt)
		elif calling:
			_call_step(dt)
	else:
		_seated(dt)
	if fight != null and fight.sheltered:
		_sheltered_step(dt)
	_engine_step()
	_seeker_step(dt)
	if crash_left >= 0.0:
		crash_left -= dt
		if crash_left < 0.0:
			_tow_home()


func _exit_tree() -> void:
	if demo != null and is_instance_valid(demo) and demo.detail != null and atmo != null:
		demo.detail.update_motion(0.0, atmo.altitude(), 0.0, 0.0, false)
	_set_flight_terrain_quality(false)
	_motion_basis_valid = false
	if handing_off():
		return                     # the next planet's ship carries on: the drone and the music too
	if _engine != null:
		_engine.stop()
	Sound.set_space(false)


## Leaving for another planet's scene with no fade (SpaceTravel.handoff).
func handing_off() -> bool:
	return travel != null and is_instance_valid(travel) and travel.traveling != "" and travel.handoffs > 0


func _set_flight_terrain_quality(active: bool) -> void:
	if demo == null or not is_instance_valid(demo) or demo.terrain == null:
		return
	if demo.terrain is PlanetTerrain:
		(demo.terrain as PlanetTerrain).set_fast_flight_quality(active)


## Issue #16: the engine drones while the ship is in the air; pitch follows the throttle.
func _engine_step() -> void:
	if _engine == null or not _engine.is_inside_tree():
		return        # Sound (its parent) joins the tree a frame after the first call
	var st := atmo.state
	var on := piloting and (st == AtmoFlight.State.LIFTOFF or st == AtmoFlight.State.FLYING \
		or st == AtmoFlight.State.LANDING)
	if on != _engine.playing:
		if on:
			_engine.play()
		else:
			_engine.stop()
	if on:
		_engine.pitch_scale = 0.75 + _throttle * 0.5 + (0.15 if _boost else 0.0)


## The seeker warning: while an enemy has a lock on her or a seeker in flight at her
## (in a space fight, or down on the planet from the Remnant interceptor, whether or
## not the space dogfight is on), the alarm sounds for a few seconds, the text shows, and (in the cockpit
## view) the dash lamp flashes. SeekerWarning decides when; this plays it.
func _seeker_step(dt: float) -> void:
	var threat := false
	if _fight_flying() and fight.running():
		var on_her: Dictionary = fight.df.seekers_on_player()
		threat = int(on_her.locks) + int(on_her.missiles) > 0
	# Down on the planet too, fight or no fight (the dogfight toggle does not matter):
	# the Remnant interceptor's lock and its seekers in the air.
	var foe = _air_foe()
	if not threat and piloting and foe != null and foe.has_method("seekers_on_player"):
		var on_her: Dictionary = foe.seekers_on_player()
		threat = int(on_her.locks) + int(on_her.missiles) > 0
	var was := seeker_warning.sounding
	seeker_warning.update(dt, threat)
	if seeker_warning.sounding != was:
		_sound_alarm(seeker_warning.sounding)
	hud.set_seeker_warning(seeker_warning.sounding, seeker_warning.lamp_on())


func _sound_alarm(on: bool) -> void:
	if _alarm == null and on:
		_alarm = Sound.loop("seeker_alarm", self, false) as AudioStreamPlayer
	if _alarm == null or not _alarm.is_inside_tree():
		return
	if on:
		_alarm.play()
	else:
		_alarm.stop()


func _on_foot() -> void:
	var p := player()
	if p == null:
		return
	if sky != null:
		sky.update_for(ground.altitude(p.global_position), p.global_position)
	if demo.detail != null:
		var alt := ground.altitude(p.global_position)
		var c = cruiser()
		if c != null and c.aboard(p.global_position):
			# Issue #193: aboard the cruiser you are in space, but up close: its shadows
			# and props stay on (the town's people, far below, stay off).
			alt = minf(alt, float(c.cfg.get("detail_altitude", 600.0)))
		var st = station_aboard(p.global_position)
		if st != null:
			alt = minf(alt, float(st.cfg.get("detail_altitude", 600.0)))     # the same, aboard a station
		demo.detail.update_for(alt)
	var i := nearest_berth() if not p.locked and not _hijack_claims() else -1
	var near := i >= 0
	if near:
		var cfg: Dictionary = berths[i].cfg
		var vname := NameHooks.vessel(cfg, "vessel:player/" + str(berths[i].ship_id))
		_foot_prompt.text = "%s  %s" % [GameFlow.label("board"), "  ·  ".join(
			[vname, berth_label(berths[i]), ShipUpgrades.short(str(berths[i].ship_id))].filter(func(x): return x != ""))]
		if not berth_flies(i):
			_foot_prompt.text = "%s  ·  %s" % [vname, Story.line(locked_line(i))]
	_foot_prompt.visible = near
	if near and _just("interact"):
		board()


## Issue #276: the empty ship after an ejection, coming down on her own. Her
## crash (or her touchdown) goes through the same events as a flown ship's.
func _adrift_step(dt: float) -> void:
	for e in atmo.step(dt):
		_on_event(e)
	_sync_visual()


func _seated(dt: float) -> void:
	var st := atmo.state
	if _external.is_empty():
		_read_keys(dt)
		# E just got you out: stop here, or the rest of this frame puts the chase
		# camera override back on and snaps you into the ship again.
		if not piloting:
			return
	else:
		_throttle = float(_external.get("throttle", _throttle))
		_boost = bool(_external.get("boost", false))
		atmo.set_command(float(_external.get("pitch", 0.0)), float(_external.get("yaw", 0.0)),
			float(_external.get("roll", 0.0)), _throttle, _boost)
	if st == AtmoFlight.State.LIFTOFF or st == AtmoFlight.State.FLYING or st == AtmoFlight.State.LANDING:
		flight_time += dt
	if opening:
		opening_t += dt
	_jolt_xf = jolt.step(dt)
	if fight != null:
		_shelter()
	if _fight_flying():
		_fight_step(dt)
	elif docking:
		_dock_step(dt)
	elif bay_landing:
		_bay_step(dt)
	else:
		atmo.air_cap = _cruiser_air_cap()
		for e in atmo.step(dt):
			_on_event(e)
		_rearm_space()
		if _external.is_empty():
			_fire_guns(dt, _held("flight_fire"), _held("flight_missile"))
		else:
			_fire_guns(dt, bool(_external.get("fire", false)), bool(_external.get("missile", false)))
		defense.step(dt)
	_sync_visual()
	var s := atmo.position()
	var agl_now := atmo.agl()
	player().global_position = s
	if demo.terrain != null and atmo.state != AtmoFlight.State.CRASHED \
			and (atmo.state == AtmoFlight.State.LANDING or (agl_now < 60.0 and atmo.speed() <= _prefetch_speed)):
		demo.terrain.prefetch(s)           # ground to step out onto, built in the background (issue #574: not at speed)
	if sky != null:
		sky.update_for(atmo.altitude(), s)
	if demo.detail != null:
		var turn_rate := 0.0
		var basis_now: Basis = atmo.flight.basis
		if _motion_basis_valid and dt > 0.0:
			var turn_radians := _motion_basis.get_rotation_quaternion().angle_to(basis_now.get_rotation_quaternion())
			turn_rate = rad_to_deg(turn_radians / dt)
		_motion_basis = basis_now
		_motion_basis_valid = true
		var in_flight := atmo.state in [AtmoFlight.State.LIFTOFF, AtmoFlight.State.FLYING, AtmoFlight.State.LANDING]
		demo.detail.update_motion(dt, atmo.altitude(), atmo.speed(), turn_rate, in_flight)
		_set_flight_terrain_quality(demo.detail.motion_active or demo.detail.fast_ground)
	if demo._rig != null:
		chase.up = atmo.up()
		demo._rig.set_override(chase.update(dt, atmo.transform()), 72.0)
	_update_hud(agl_now)


func _read_keys(dt: float) -> void:
	var st := atmo.state
	if opening:
		# Issue #202: the autopilot has her; only E, once she is down.
		if st == AtmoFlight.State.PARKED and _just("interact"):
			exit_ship()
		return
	if st == AtmoFlight.State.PARKED:
		_throttle = 0.0          # parked is zero throttle (AtmoFlight.park), not what she landed with
		if _just("interact"):
			exit_ship()
			return
		# C takes off, as it lands; Space is the guns (flight_fire) and must not lift her.
		if _just("crouch_act") or _axis("flight_throttle_down", "flight_throttle_up") > 0.5:
			takeoff()
		return
	if _held("flight_eject") and can_eject():
		if _eject_hold == 0.0:
			hud.toast(GameFlow.label("eject_hold"), 1.0)
		_eject_hold += dt
		if _eject_hold >= GameFlow.setting("eject_hold", 0.5) and eject():
			return
	else:
		_eject_hold = 0.0
	# C lands from where she is; with Z's autopilot flying her in it does nothing (it
	# used to drop the autopilot, and from any height land() refuses: dead stop, free).
	if st == AtmoFlight.State.FLYING and _just("crouch_act") and not bay_landing and not docking:
		land()
	elif st == AtmoFlight.State.LANDING and _just("crouch_act") and atmo.abort_landing():
		_throttle = 0.0          # C again: flying on, coasting to a stop
		hud.toast(GameFlow.label("landing_off"), 2.0)
	if st == AtmoFlight.State.FLYING and _just("bay_land"):
		if bay_landing or docking:
			bay_landing = false          # Z again: take her back
			docking = false
		elif not dock():
			bay_land()
	if bay_landing or docking:
		return
	if st == AtmoFlight.State.LIFTOFF:
		_throttle = 0.0          # she comes up hovering: the throttle key that lifted her does not wind it up
	else:
		_throttle = clampf(_throttle + _axis("flight_throttle_down", "flight_throttle_up") * dt * 0.6, 0.0, 1.0)
	var pitch := clampf(_axis("flight_pitch_down", "flight_pitch_up") + _stick.y, -1.0, 1.0)
	var yaw := clampf(_axis("flight_yaw_left", "flight_yaw_right") + _stick.x, -1.0, 1.0)
	var roll := _axis("flight_roll_left", "flight_roll_right")
	_stick = _stick.lerp(Vector2.ZERO, minf(1.0, dt * 3.0))
	_boost = _held("flight_boost")
	atmo.set_command(pitch, yaw, roll, _throttle, _boost)


func _on_event(e: Dictionary) -> void:
	e["t"] = flight_time
	log_events.append(e)
	match str(e.type):
		"airborne":
			hud.toast(GameFlow.label("airborne"), 6.0)
		"landing":
			hud.toast(GameFlow.label("landing"), 2.0)
		"landed":
			hud.toast(GameFlow.label("landed"), 4.0)
			_set_hull(true)
			if not piloting:
				_remember(berth)           # issue #368: came down on her own (an ejection)
		"crashed":
			hud.toast(GameFlow.label("crashed"), 3.0)
			crash_left = CRASH_TOW_TIME
			if demo.terrain != null:
				demo.terrain.prefetch(home) # ground at the pad, ready before the tow
			if visual != null:
				visual.visible = false
			_crash_fx(e.at)
			Sound.play("vehicle_boom", e.at)
		"reached_space":
			if space_time < 0.0:
				space_time = flight_time
			_leave_atmosphere()


## Issue #46: out of the atmosphere, still in this scene, over the same ground.
## No fade, no scene change and nothing said: the sky is already black up here.
## Only the pad's fight (when it starts) is news.
func _leave_atmosphere() -> void:
	ascending = true
	left_atmosphere.emit()
	if GameFlow.space_dogfight() and start_fight():
		hud.toast(GameFlow.label("contact"), 6.0)


## Start the pad's encounter around the ship as it flies now. False if there is
## none (or one is already running).
func start_fight() -> bool:
	if fight != null:
		return false
	var f := SpaceFight.new()
	# LAN: the host's fight over this planet is on: join it instead (NetFight).
	var net = NetSession.link.get_node_or_null("Fight") if NetSession.is_guest() else null
	var host_fight: Dictionary = net.joinable() if net != null else {}
	f.net_copy = not host_fight.is_empty()
	demo.add_child(f)
	if not f.begin(content, str(host_fight.get("encounter", encounter_id())), atmo.transform(), atmo.speed(), 1, kit, ship_id):
		f.queue_free()
		return false
	fight = f
	if cruiser() != null:
		f.df.arena_follow = true       # flying for the cruiser: both sides come along, not back to the start
	# One hull and shield in the air and in space: the fight's bolts land on the
	# ship's own defense, so you climb out as damaged as you are and come back
	# down as damaged as the fight left you.
	var me: Dictionary = f.df.get_ship(f.df.player_id)
	if not me.is_empty():
		me.defense = defense
		me.loadout.set_rack("secondary", guns.rack("secondary"))   # and one seeker rack
	Sound.set_space(true)          # the space track is the orbital fight's music
	fight_started.emit()
	return true


## One frame of the fight: the director flies the player's ship from the same
## command the keys (or a bot) give normal flight, and the town ship follows it.
func _fight_step(dt: float) -> void:
	var cmd: Dictionary = atmo._command.duplicate()
	if _external.is_empty():
		cmd["fire"] = _held("flight_fire")
		cmd["missile"] = _held("flight_missile")
	else:
		cmd["fire"] = bool(_external.get("fire", false))
		cmd["missile"] = bool(_external.get("missile", false))
	var before: Vector3 = atmo.flight.position
	var events: Array = fight.step(dt, cmd)
	var f = fight.player_flight()
	if f != null:
		atmo.flight.position = f.position
		atmo.flight.basis = f.basis
		atmo.flight.speed = f.speed
	if _fight_meets_ground(before, dt):
		return
	for e in events:
		match str(e.type):
			"hit":
				_fight_hit(e)
			"wave":
				hud.toast("Wave %d" % int(e.index), 2.5)
			"kill":
				if fight != null and e.by == fight.df.player_id:
					hud.confirm_hit(true)
					hud.toast("Kill  ·  " + str(e.who) if str(e.get("who", "")) != "" else "Kill", 2.0)
			"complete":
				end_fight("complete")
				return
			"failed":
				end_fight("failed")
				return
			"net_over":
				_net_fight_over()
				return
	if not _fight_held() and atmo.altitude() < atmo.space_altitude - space_exit_margin and not _bound_for_cruiser():
		end_fight("left")


## The fight is flying her now (running, and she is out in it).
func _fight_flying() -> bool:
	return fight != null and not fight.sheltered


## The cruiser's escort only ends with the general's death (RemnantCruiser), with
## every wave shot down, or with her shot down: diving away does not break it off.
func _fight_held() -> bool:
	var c = cruiser()
	return fight != null and c != null and fight.encounter_id == c.escort_id()


## Close by the cruiser: inside its approach's fight_off_radius the fight lets go of
## her and normal flight lines her up with the bay. Once out, she stays out until
## past fight_back_radius, so the edge does not flick her back and forth.
func _by_cruiser(c) -> bool:
	var ap: Dictionary = c.cfg.get("approach", {})
	var r := float(ap.get("fight_back_radius", 1300.0)) if fight != null and fight.sheltered \
		else float(ap.get("fight_off_radius", 1000.0))
	return c.distance(atmo.position()) <= r


## Not out in the fight: docking, landing or down in the cruiser's bay, close by the
## cruiser, parked, on foot, crashed, or (the escort) dived away under the edge of space.
## The fight goes on without her (Dogfight.player_sheltered) until she is out in it again.
## Diving home lets go of her space_exit_margin under the edge, as a fight that ends does,
## so normal flight (and the air's speeds) has her for the way down, not the fight's
## 480+ m/s; she is back in it half that far under the edge, so the line does not flicker.
func _out_of_fight() -> bool:
	if not piloting or docking or bay_landing or atmo.state != AtmoFlight.State.FLYING:
		return true
	var c = cruiser()
	if c != null and (c.aboard(atmo.position()) or _by_cruiser(c)):
		return true
	var under := space_exit_margin * (0.5 if fight.sheltered else 1.0)
	return _fight_held() and atmo.altitude() < atmo.space_altitude - under and not _bound_for_cruiser()


## Into the fight or out of it as she comes and goes. Back in, the director's ship
## takes over from the one normal flight was flying.
func _shelter() -> void:
	var out := _out_of_fight()
	if out == fight.sheltered:
		return
	fight.set_sheltered(out)
	if not out:
		_hand_to_fight()


## The director's ship where normal flight has her: place, heading and speed.
func _hand_to_fight() -> void:
	var f = fight.player_flight() if fight != null else null
	if f == null:
		return
	f.position = atmo.position()
	f.basis = atmo.flight.basis
	f.speed = minf(atmo.speed(), f.max_speed())


## The fight going on without her: everyone else flies and shoots, round where her
## ship is. Shot down to the last wave, it is won all the same.
func _sheltered_step(dt: float) -> void:
	var f = fight.player_flight()
	if f != null:
		f.position = atmo.position()
		f.basis = atmo.flight.basis
		f.speed = atmo.speed()
	for e in fight.step(dt, {}):
		if str(e.type) == "complete":
			end_fight("complete")
			return
		if str(e.type) == "net_over":
			_net_fight_over()
			return


## LAN: a guest up in space with no fight of their own joins the host's when it
## starts (NetFight asks while it is on). False when not up there flying.
func join_net_fight() -> bool:
	if fight != null or not piloting or atmo == null or atmo.state != AtmoFlight.State.FLYING \
			or not atmo.reached_space or atmo.altitude() < atmo.space_altitude or not GameFlow.space_dogfight():
		return false
	if not start_fight():
		return false
	hud.toast(GameFlow.label("contact"), 6.0)
	return true


## LAN: the host's fight this guest was flying a copy of is over (or the host went
## quiet): it is over here too, nothing paid.
func _net_fight_over() -> void:
	end_fight("left", true)
	Sound.set_space(false)
	hud.toast(NetSession.label("fight_over"), 4.0)


## Flying at the cruiser keeps the fight on: the ball curves away under the straight
## line to it, so that line dips below the edge of space on the way. Only a real
## dive (nose away from it, or below the approach's floor) breaks the fight off.
func _bound_for_cruiser() -> bool:
	var c = cruiser()
	if c == null:
		return false
	var ap: Dictionary = c.cfg.get("approach", {})
	if atmo.altitude() < atmo.space_altitude - float(ap.get("floor", 1500.0)):
		return false
	var to: Vector3 = c.frame.origin - atmo.position()
	return atmo.flight.forward().dot(to.normalized()) >= cos(deg_to_rad(float(ap.get("cone_deg", 40.0))))


## How fast normal flight may go by the cruiser: her space-fight speed (the ship's
## "flight" block times the fight's speed_scale, about her edge-of-space speed)
## within the approach's calm_radius, back to the full edge-of-space speed by
## calm_out, so a fight broken off up here hands her on at the speed she had.
func _cruiser_air_cap() -> float:
	var c = cruiser()
	if c == null:
		return INF
	var ap: Dictionary = c.cfg.get("approach", {})
	var inner := float(ap.get("calm_radius", 1500.0))
	var k := clampf((c.distance(atmo.position()) - inner) / maxf(float(ap.get("calm_out", 5000.0)) - inner, 1.0), 0.0, 1.0)
	if k >= 1.0:
		return INF
	var fight_top := float(ship_cfg.get("flight", {}).get("max_speed", 48.0)) * float(Dogfight.load_tune().get("speed_scale", 1.0))
	var calm := fight_top / maxf(atmo.p("max_speed", 170.0), 1.0)
	var edge := atmo.p("edge_speed_mult", 4.0)
	return lerpf(minf(calm, edge), edge, k)


## Issue #181: a hit in the fight. Theirs on you flashes the screen's edge; yours on
## them pops the hit marker (a kill's marker comes with its own event), and a seeker's
## also pins one where it struck.
func _fight_hit(e: Dictionary) -> void:
	if fight == null:
		return
	if int(e.get("id", -1)) == fight.df.player_id:
		hud.flash_damage()
	elif int(e.get("by", -1)) == fight.df.player_id:
		hud.confirm_hit(false)
		if str(e.get("kind", "")) == "missile":
			# A seeker lands far off the nose: mark where (red if it was the kill).
			var victim: Dictionary = fight.df.get_ship(int(e.get("id", -1)))
			hud.mark_hit_at(e.point, not victim.is_empty() and not victim.alive)


## Finish the sortie. "complete" pays out, "failed" tows the ship home (as a crash
## does), "left" (dived out early) just ends it, and "general" (the cruiser's
## general is dead: RemnantCruiser) ends it with the cruiser's own reward. Normal
## flight picks up where the fight left the ship, if it was flying her.
func end_fight(outcome: String, quiet := false) -> void:
	if fight == null:
		return
	var pay := fight.payout() if outcome == "complete" else 0
	var at := atmo.position()
	var flown := not fight.sheltered and atmo.state == AtmoFlight.State.FLYING
	var me: Dictionary = fight.df.get_ship(fight.df.player_id) if fight.df != null else {}
	if not me.is_empty() and guns != null:
		guns.set_rack("secondary", me.loadout.rack("secondary"))   # the seekers you came down with
	fight.finish(outcome)
	fight.queue_free()
	fight = null
	if not quiet:
		Sound.set_space(false)
	fight_log.append({ "outcome": outcome, "payout": pay, "at": at })
	if outcome != "left" and outcome != "general":
		WorldState.on_flight_returned({ "pad": str(pad.get("id", "")), "encounter": str(pad.get("encounter", "")),
			"outcome": outcome, "payout": pay, "mode": "orbit" })
	match outcome:
		"complete":
			var t := GameFlow.label("orbit_complete")
			hud.toast(t % pay if t.contains("%d") else t, 6.0)
		"left":
			if not quiet:
				hud.toast(GameFlow.label("orbit_broke_off"), 3.0)
	if outcome == "failed":
		atmo._crash(at, "space")
		_on_event({ "type": "crashed", "at": at, "what": "space" })
		hud.toast(GameFlow.label("orbit_failed"), 4.0)
	elif flown:
		var throttle := clampf(float(atmo._command.get("throttle", 0.6)), 0.0, 1.0)
		atmo.place_flying(at, atmo.flight.forward(), atmo.flight.speed, throttle)
	fight_ended.emit(outcome)


## The fight's director flies her through empty space: it knows nothing of the
## world. Up there the world is the cruiser (issue #193): in through its bay's mouth
## she is out of the fight (_out_of_fight) and normal flight has her from the next
## frame, and its hull is as solid as in normal flight: the normal collision bumps
## her (and she fights on from where it stopped her) or crashes her, which ends it.
func _fight_meets_ground(before: Vector3, dt: float) -> bool:
	var pos := atmo.position()
	if ground.hit(pos, atmo.body_radius) == "" and ground.height_above(pos - atmo.up() * atmo.clearance) > 0.0:
		return false
	atmo.events = []
	atmo._collide(before, dt)
	for e in atmo.events:
		_on_event(e)
	if atmo.state == AtmoFlight.State.CRASHED:
		end_fight("left", true)        # the crash says so
		Sound.set_space(false)
	else:
		_hand_to_fight()
	return true


## Back under the edge of space (and no fight running): the next climb out is a
## new sortie.
func _rearm_space() -> void:
	if atmo.reached_space and atmo.altitude() < atmo.space_altitude - space_exit_margin:
		atmo.reached_space = false
		ascending = false
		Sound.set_space(false)     # a fight's music carried over a handoff ends coming down


func _tow_home() -> void:
	if berths[berth].has("hijacked_from"):
		# Taken from another player and crashed: wrecked in their game too (borrowed: lost here).
		hijack_let_go.emit(int(berths[berth].hijacked_from), atmo.transform(), true)
		berths[berth].erase("hijacked_from")
	if visual != null:
		visual.visible = true
	atmo.reached_space = false
	ascending = false
	atmo.park(home, home_yaw)
	_set_hull(true)
	_sync_visual()
	defense = ShipDefense.new(ship_cfg)       # patched up at the pad
	var seated := piloting
	if piloting:
		exit_ship()
	if bool(berths[berth].get("stolen", false)) or bool(berths[berth].get("borrowed", false)):
		_lose_stolen(seated)
		return
	_remember(berth)
	hud.toast(GameFlow.label("towed"), 4.0)
	if demo.pads.size() > 0:
		demo.pads[0].toast(GameFlow.label("towed"), 4.0)


func _sync_visual() -> void:
	if visual != null and is_instance_valid(visual):
		visual.global_transform = atmo.transform() * _jolt_xf
		# The engines light with the throttle while you fly her; out the moment you're not.
		var up := piloting and atmo.state == AtmoFlight.State.FLYING
		ShipKit.throttle_flames(visual, _throttle if up else 0.0, _boost and up,
			get_physics_process_delta_time() if piloting else 0.0)


func _update_hud(agl_now: float) -> void:
	var f = atmo.flight
	var v: Vector3 = f.velocity()
	# Issue #181: in a fight the director's model and defense are the live ones (its
	# boost meter, its Shift ability, the shield and hull its bolts hit).
	var live = f
	var d = defense
	if _fight_flying() and fight.df != null:
		var me: Dictionary = fight.df.get_ship(fight.df.player_id)
		if not me.is_empty():
			live = me.flight
			d = me.defense
	var up := atmo.up()
	var att := FlightHud.attitude(PlanetSphere.tilt_to(up).inverse() * f.basis)
	# The stick as last commanded, for the cockpit's yoke (centred while the bay
	# landing flies her in, which commands nothing).
	var cmd: Dictionary = {} if bay_landing else atmo._command
	hud.set_cockpit(chase.is_cockpit(), chase.is_cinematic())
	hud.show_values({
		"speed": f.speed, "throttle": _throttle, "max_speed": live.max_speed(),
		"boost": live.boost_left / maxf(live.boost_time(), 0.001),
		"agl": agl_now if is_finite(agl_now) else atmo.altitude(), "altitude": atmo.altitude(), "climb": v.dot(up),   # issue #573: no ground in open space
		"state": atmo.state_label(),
		"hull": d.hull_hp(), "hull_max": d.hull_max(), "shield": int(d.shield), "shield_max": d.shield_max,
		"pitch": att.pitch, "roll": att.roll, "heading": att.heading,
		"ability": live.ability(), "ability_on": live.boosting,
		"stick_pitch": float(cmd.get("pitch", 0.0)), "stick_yaw": float(cmd.get("yaw", 0.0)),
		"stick_roll": float(cmd.get("roll", 0.0)),
	})
	var tip := ""
	if opening:
		var hint := "opening_exit" if atmo.state == AtmoFlight.State.PARKED else ""
		if hint == "" and opening_t >= float(Story.data().get("opening_cinematic_secs", 8.0)):
			hint = "opening_view"
		hud.set_prompt(Story.line(hint) if hint != "" else "")
		return
	match atmo.state:
		AtmoFlight.State.PARKED:
			tip = GameFlow.label("seated")
		AtmoFlight.State.FLYING:
			tip = GameFlow.label("can_land") if atmo.can_land(agl_now) else ""
			# Z says where it takes her: the cruiser's bay before your own.
			if bay_landing:
				tip = GameFlow.label("bay_heading") % bay_place()
			elif docking:
				tip = GameFlow.label("bay_heading") % _dock_to
			elif near_dock() or near_bay():
				tip = (tip + "    " if tip != "" else "") + GameFlow.label("bay_land") % dock_place()
		AtmoFlight.State.LANDING:
			tip = GameFlow.label("landing")
	hud.set_prompt(tip)
	# Issue #76: the Remnant interceptor, boxed and led like a space target (and the
	# seekers' lock on it drawn round the box).
	var foe = _air_foe()
	hud.target = foe.hud_target() if foe != null else {}
	if not hud.target.is_empty() and seeker_lock != null:
		hud.target["lock"] = seeker_lock.fraction()
	# LAN: the other players' ships, boxed the same way while your guns can hit them
	# (no lock ring: seekers never lock on a friend).
	hud.friends = _friend_targets()


# ------------------------------------------------------------------ guns and hull (issue #55)

## Issue #55: in town the garrison treats your ship as hostile from the moment it
## lifts off until it is back on the ground (or gone to space). Issue #200: not in
## a story save, where flying out of port raises no alarm.
func hostile_in_town() -> bool:
	return piloting and not _fight_flying() and not WorldState.story_mode() and atmo.state != AtmoFlight.State.PARKED \
		and atmo.state != AtmoFlight.State.CRASHED and TownNav.in_town(demo.town, atmo.position())


## Flown or sat in on the ground, and not wrecked: an outpost's troopers fight it
## as they would you on foot (out there it is no offence by itself).
func targetable() -> bool:
	return piloting and not _fight_flying() and atmo.state != AtmoFlight.State.CRASHED


## What the troopers' eyes and bolts hit while you fly.
func hull_body() -> CollisionObject3D:
	return hull


func threat_velocity() -> Vector3:
	return atmo.flight.velocity()


## The guns, in the air or still on the pad: the primary group (cannons) as real
## bolts, the same ones the troopers and the speeder fire. The seekers fire too,
## locked or not: a lock (the interceptor held in the cone, as in space) makes one
## home on it; without one it flies straight off the nose. The rack refills by the
## same rule as in space (ShipLoadout's reload_each), and it is the same rack.
func _fire_guns(dt: float, trigger: bool, missile := false) -> void:
	if guns == null or atmo.state == AtmoFlight.State.CRASHED:
		return
	var v: Vector3 = atmo.flight.velocity() if atmo.state != AtmoFlight.State.PARKED else Vector3.ZERO
	if trigger:
		guns.convergence = _gun_cross()
	var foe = _air_foe()
	var foe_id := -1
	if seeker_lock != null:
		var to_foe := Vector3.ZERO
		if foe != null and atmo.state == AtmoFlight.State.FLYING and not foe.hud_target().is_empty():
			foe_id = foe.get_instance_id()
			to_foe = foe.position() - atmo.position()
		seeker_lock.update(dt, foe_id, atmo.flight.forward(), to_foe)
	var locked: bool = seeker_lock != null and seeker_lock.is_locked()
	var volley := false
	for s in guns.fire(dt, atmo.transform(), v, trigger, missile, foe_id if locked else -1):
		if str(s.kind) == "missile":
			_launch_seeker(s, foe.hull if locked else null)
			continue
		if str(s.kind) != "bolt":
			continue
		var b := ship_bolt(s, hull, content, ground, Color("#ff6a3a"))
		b.connect("on_hit", hud.on_gun_hit)          # issue #181: hit markers
		b.connect("on_splash", hud.on_gun_hit)
		demo.add_child(b)
		b.global_position = s.origin
		shots += 1
		volley = true
		cannon_fired.emit(s.origin, b.direction, minf(guns.convergence + 2.0, b.range_m), b)
	if volley:
		Sound.play("ship_cannon", atmo.position())


## One seeker in the air: a ship bolt in the seeker's look (ships.json "bolts"
## "missile") that turns after `seek` (the interceptor's hull, or null: straight)
## and goes up like a vehicle where it lands, splash and all.
func _launch_seeker(s: Dictionary, seek: Node3D) -> void:
	var look: Dictionary = kit.bolts.get("missile", {}) if kit != null else {}
	var b := ship_bolt(s, hull, content, ground, Color(str(look.get("color", "#ffd28a"))))
	b.streak_length = float(look.get("length", 1.6))
	b.streak_radius = float(look.get("width", 0.3)) * 0.5
	b.seek = seek
	b.turn_rate = float(s.get("turn_rate", 0.0))
	b.blast_size = float(s.get("blast_size", 0.0))
	b.connect("on_hit", hud.on_gun_hit)
	b.connect("on_splash", hud.on_gun_hit)
	demo.add_child(b)
	b.global_position = s.origin
	seekers += 1
	Sound.play("ship_missile", s.origin)
	if seek == null:
		# LAN: a straight one shows to the others, out to whatever is under the nose.
		var cross := _gun_cross()
		cannon_fired.emit(s.origin, b.direction, cross + 2.0 if cross < _gun_reach else b.range_m, b)


## LAN: whether the others' cannons can hit the ship you fly (RemoteShip): off the
## ground, or out in a space fight.
func lan_flying() -> bool:
	return piloting and (_fight_flying() or atmo.state in [AtmoFlight.State.LIFTOFF,
		AtmoFlight.State.FLYING, AtmoFlight.State.LANDING])


## LAN: the hull left on the ship you fly, 0..1 (the fight's while in one), for the
## bar under the box the others' flight HUDs draw on it.
func lan_hull() -> float:
	var d = defense
	if _fight_flying() and fight.df != null:
		var me: Dictionary = fight.df.get_ship(fight.df.player_id)
		if not me.is_empty():
			d = me.defense
	return float(d.hull_hp()) / maxf(1.0, float(d.hull_max())) if d != null else 1.0


## LAN friendly fire: the other players' ships your guns can hit now (their
## RemoteShip.hittable: they fly, friendly fire is on), boxed on your HUD as an
## enemy is, in the town's sky and out in space.
func _friend_targets() -> Array:
	var out: Array = []
	if not NetSession.active() or NetSession.link == null:
		return out
	var pc: Dictionary = guns.group_config("primary") if guns != null else {}
	var speed := float(pc.get("bolt_speed", 300.0))
	var from := atmo.position()
	var v: Vector3 = atmo.flight.velocity() if atmo.state != AtmoFlight.State.PARKED else Vector3.ZERO
	for rs in NetSession.link.ship_bodies.values():
		if rs != null and is_instance_valid(rs) and rs.has_method("hud_target"):
			var t: Dictionary = rs.hud_target(from, v, speed)
			if not t.is_empty():
				out.append(t)
	return out


## LAN friendly fire: another player's ship cannon hit the ship you fly
## (NetLink.ship_hit). In the air it is a hit on your hull, as anyone's bolt is;
## out in a space fight it lands on your ship in the fight's director. Returns 0 if
## it did nothing (not flying, already down), 1 if it hurt, 2 if it shot you down.
func lan_ship_hit(amount: float) -> int:
	if not lan_flying():
		return 0
	if _fight_flying():
		return int(fight.df.friendly_damage(amount))
	if berth < 0 or berth >= berths.size():
		return 0
	var was: float = defense.shield + float(defense.hull_hp())
	_on_hull_hit(amount, null, berth)
	if atmo.state == AtmoFlight.State.CRASHED:
		return 2
	return 1 if defense.shield + float(defense.hull_hp()) < was else 0


## The Remnant interceptor (issue #76), when this town has one: what the seekers
## lock on in the air and the HUD boxes.
func _air_foe():
	var foe = demo.interceptor if "interceptor" in demo else null
	return foe if foe != null and is_instance_valid(foe) else null


## Where the guns cross: on whatever is under the nose, out to their own reach.
## Crossing 300 m ahead, the wing guns' bolts pass a man 50 m off a metre or two
## either side (a trooper in the cruiser's bay, issue #193); now they meet on him.
func _gun_cross() -> float:
	var xf := atmo.transform()
	var from := xf.origin
	var q := PhysicsRayQueryParameters3D.create(from, from - xf.basis.z * _gun_reach)
	var skip: Array[RID] = []
	for n in [hull, player()]:
		if n is CollisionObject3D:
			skip.append((n as CollisionObject3D).get_rid())
	q.exclude = skip
	var space: PhysicsDirectSpaceState3D = demo.get_world_3d().direct_space_state
	var hit := space.intersect_ray(q)
	while not hit.is_empty() and (hit.collider as Object).has_meta("bolts_pass"):
		skip.append(hit.rid)
		q.exclude = skip
		hit = space.intersect_ray(q)
	if hit.is_empty():
		return _gun_reach
	return clampf(from.distance_to(hit.position), 8.0, _gun_reach)


## One cannon shot from ShipLoadout.fire() as a real bolt in the air (sweeping, so
## it cannot tunnel; bursting where it lands). Issue #76: the Remnant interceptor's
## guns use it too. The caller adds it to the scene and sets its position.
static func ship_bolt(s: Dictionary, shooter: Node, content, ground: WorldGround, color: Color) -> Node3D:
	var b = BoltScene.instantiate()
	var vel: Vector3 = s.velocity
	b.direction = vel.normalized()
	b.speed = vel.length()
	b.damage = float(s.damage)
	b.soft_damage = float(s.get("personnel_damage", 0.0))
	b.range_m = float(s.range)
	b.shooter = shooter
	b.sweep = true
	b.stylize = true
	b.streak_length = 2.4
	b.streak_radius = 0.07
	b.color = color
	var wc: Dictionary = content.weapons.get(str(s.get("weapon_id", "")), {})
	b.splash_radius = float(wc.get("splash_radius", 0.0))
	b.splash_damage = float(wc.get("splash_damage", 0.0))
	if ground.sphere() != null:
		# Issue #93: round the ball the ground is what is under the bolt along "up", not
		# the flat (x, z) line (which is only the port's half of the planet).
		b.over_ground = func(p: Vector3) -> float: return ground.height_above(p)
		b.ground_up = func(p: Vector3) -> Vector3: return ground.up_at(p)
	else:
		b.ground_at = func(x: float, z: float) -> float: return ground.terrain.height_at(x, z)
	return b


## A bolt hit berth `i`'s hull. Only the ship you are flying keeps score; a hull
## shot to nothing goes down like a crash (and is towed home).
func _on_hull_hit(amount: float, shooter: Node, i: int) -> void:
	if i < berths.size() and _parked_target(i, shooter):
		_hit_parked(i, amount)
		return
	var adrift := atmo.state == AtmoFlight.State.ADRIFT    # issue #276: the empty ship still takes hits
	if i != berth or not (piloting or adrift) or _fight_flying() or atmo.state == AtmoFlight.State.CRASHED:
		return
	defense.apply_damage(amount)
	if piloting:
		hud.flash_damage()                        # issue #181
	if defense.is_alive():
		return
	var at := atmo.position()
	atmo._crash(at, "shot_down")
	_on_event({ "type": "crashed", "at": at, "what": "shot_down" })


# ------------------------------------------------------------------ parked ships (issue #64)

## A parked ship shot by another ship (its guns: the shooter is a ship's hull)
## takes the damage. Not the one you sit in. A "foot_target" berth (the barracks
## pad's interceptor) takes your hand weapons too: your bolts, and a blade (no shooter).
func _parked_target(i: int, shooter: Node) -> bool:
	var b: Dictionary = berths[i]
	if bool(b.get("destroyed", false)) or shooter == b.hull:
		return false
	var by_hand: bool = bool(b.get("foot_target", false)) and (shooter == null or shooter == player())
	if not (shooter is ShipHull) and not by_hand:
		return false
	return not (i == berth and (piloting or atmo.state != AtmoFlight.State.PARKED))


func _hit_parked(i: int, amount: float) -> void:
	var b: Dictionary = berths[i]
	if not b.has("defense"):
		b.defense = ShipDefense.new(b.cfg)
	(b.defense as ShipDefense).apply_damage(amount)
	if b.hull != null and is_instance_valid(b.hull):
		b.hull.took_damage()                      # issue #181: a hit marker for the shooter
	if not (b.defense as ShipDefense).is_alive():
		_wreck_berth(i, true)


## Berth `i` is gone for good: it blows up (when `boom`), its model and hull go,
## nobody can board it, and the save remembers (WorldState.ships_destroyed), so it
## never comes back. A ship bought from T-89 frees his pad. Issue #368: one of
## yours (`sold` or not the primary) leaves your fleet; the primary only waits for
## T-89's patch-up (Fleet.WRECKED, back on the pad when you next wake).
func _wreck_berth(i: int, boom: bool, sold: bool = false) -> void:
	var b: Dictionary = berths[i]
	if bool(b.get("destroyed", false)):
		return
	b.destroyed = true
	var v: Node3D = b.visual
	if boom and is_instance_valid(v):
		var at := v.global_position + Vector3(0, 1.5, 0)
		_crash_fx(at)
		Sound.play("vehicle_boom", at)
		WorldState.log_event("A parked ship in the pit was shot to pieces.", "pit")
	if is_instance_valid(v):
		v.visible = false
	if b.hull != null and is_instance_valid(b.hull):
		b.hull.dead = true
		if b.hull.collision_layer != 0:
			b.hull_layer = b.hull.collision_layer
			b.hull_mask = b.hull.collision_mask
		b.hull.collision_layer = 0
		b.hull.collision_mask = 0
	var key := str(b.get("box_id", ""))
	var owner := str(b.get("key", ""))
	var pad_id := ""
	if demo.salesman != null:
		pad_id = str(demo.salesman.cfg.get("pad", "spare_pad"))
	if owner != "" and owner == Fleet.primary() and not sold:
		WorldState.set_flag(Fleet.WRECKED)
	elif owner != "":
		Fleet.lose(owner)
		if owner == Fleet.T89 and demo.salesman != null:
			demo.salesman.bought_ship = null
	elif key != "" and key == pad_id:
		WorldState.hangar = ""             # T-89's pad is free again
		demo.salesman.bought_ship = null
	elif key != "" and not b.has("outpost") and not WorldState.ships_destroyed.has(key):
		WorldState.ships_destroyed.append(key)
	if i == berth and not piloting:
		for j in berths.size():
			if not bool(berths[j].get("destroyed", false)):
				_use_berth(j)
				break


# ------------------------------------------------------------------ your ships (issue #368)

## Berth `i`'s owner (a Fleet key), "" = nobody's. -1: the berth you fly.
func berth_key(i: int = -1) -> String:
	if i < 0:
		i = berth
	return str(berths[i].get("key", "")) if i < berths.size() else ""


## The berth holding your ship `key`, or -1. Shot to pieces counts only with `wrecked`.
func berth_of(key: String, wrecked: bool = false) -> int:
	if key == "":
		return -1
	for i in berths.size():
		if str(berths[i].get("key", "")) == key and (wrecked or not bool(berths[i].get("destroyed", false))):
			return i
	return -1


## Issue #368: a stolen ship becomes yours (Skrugs cleaned it up): no longer stolen
## or any outpost's, so nobody hunts it and a crash tows it back here, where it
## stands now. False when berth `i` is not a stolen ship standing on the ground.
func keep_berth(i: int) -> bool:
	if i < 0 or i >= berths.size() or not bool(berths[i].get("stolen", false)) or bool(berths[i].get("destroyed", false)):
		return false
	if i == berth and (piloting or atmo.state != AtmoFlight.State.PARKED):
		return false
	var b: Dictionary = berths[i]
	for k in ["stolen", "borrowed", "outpost", "town_alarm", "foot_target", "where"]:
		b.erase(k)
	b.key = Fleet.keep(str(b.ship_id))
	b.owned = true
	var v: Node3D = b.visual
	b.home = atmo.position() if i == berth else v.global_position
	b.home_yaw = _yaw_of(atmo.transform() if i == berth else v.global_transform)
	if i == berth:
		home = b.home
		home_yaw = b.home_yaw
	_remember(i)
	return true


## Make `key` the primary. The old one stays where it stands.
func set_primary(key: String) -> bool:
	var old := Fleet.primary()
	if not Fleet.set_primary(key):
		return false
	var j := berth_of(old)
	if j >= 0:
		_remember(j)
	return true


## Once the town is built (after T-89 parked his sale): each of your ships not here
## yet stands where you last left it on this planet. One with no spot yet (a save
## from before) stands on clear ground by the pit, on the home planet. A spot on the
## pit pad that another ship holds now moves aside. A primary shot to pieces is back,
## patched up for T-89's fee.
func place_fleet() -> void:
	if fleet_placed or berths.is_empty():
		return
	fleet_placed = true
	# Issue #401: a LAN guest's pit pad is the host's (their ship shows there), unless
	# the guest flew in on their own (Fleet.LAN, the moon handoff): that one is theirs.
	if Fleet.lan() and not berths.is_empty() and str(berths[0].get("key", "")) != Fleet.LAN:
		_stow(0)
	var here := GameFlow.current_planet_id()
	for e in Fleet.owned():
		var key := str(e.key)
		if berth_of(key, true) >= 0:
			continue
		var s := Fleet.spot(key)
		if not s.is_empty() and str(s.get("planet", "")) == here:
			var i := _spawn_owned(key, Fleet.spot_xf(s))
			if i > 0 and _on_pad(i):
				_move_aside(i)
		elif s.is_empty() and (here == PlanetGen.home_id() or key == Fleet.LAN):
			var at := lan_pad() if key == Fleet.LAN else []      # issue #401: on the pad the host gave it
			var foot: Vector3 = at[0] if not at.is_empty() else clear_spot(_pad_foot(), GameFlow.setting("call_aside_min", 16.0))
			var i := _spawn_owned(key, Transform3D(Basis.IDENTITY, foot)) if foot != Vector3.INF else -1
			if i >= 0:
				_stand(i, foot, float(at[1]) if not at.is_empty() else float(berths[0].home_yaw))
				_remember(i)
	var p := berth_of(Fleet.primary(), true)
	if p >= 0 and WorldState.has_flag(Fleet.WRECKED):
		_patch_up(p)


## Issue #401: the landing pad the host gave this LAN guest's ship: [foot, yaw], or
## [] when there is none (no pad was free, or this town has no such box).
func lan_pad() -> Array:
	var box: Dictionary = demo.town.get_box(str(NetSession.ship.get("pad", ""))) if Fleet.lan() else {}
	if box.is_empty():
		return []
	var c := Vector3((float(box.min[0]) + float(box.max[0])) * 0.5, float(box.min[1]), (float(box.min[2]) + float(box.max[2])) * 0.5)
	return [c, deg_to_rad(float(box.get("parked_yaw_deg", 0.0)))]


## Berth `i` is not here for you (a LAN guest's pit ship: the host's): out of sight,
## nothing to hit or board. Not saved as lost.
func _stow(i: int) -> void:
	var b: Dictionary = berths[i]
	b.destroyed = true
	b.stowed = true
	if is_instance_valid(b.visual):
		(b.visual as Node3D).visible = false
	if b.hull != null and is_instance_valid(b.hull):
		b.hull.collision_layer = 0
		b.hull.collision_mask = 0


## You woke in the pit (downed, killed, a fall, a lost stolen ship): your primary is
## on its pad, wherever it was, patched up if it was shot to pieces.
func woke_in_pit() -> void:
	woke.emit()
	if piloting or berths.is_empty() or not Fleet.goes_to_pit():
		return
	calling = false
	bring_primary_to_pit()


## The primary on the pit pad: moved there (or brought from wherever it is, another
## planet too), and whatever stood on the pad moved aside onto clear ground.
func bring_primary_to_pit() -> void:
	var key := Fleet.primary()
	if key == "" or berths.is_empty():
		return
	var foot := _pad_foot()
	var yaw := float(berths[0].home_yaw)
	var i := berth_of(key, true)
	if i < 0:
		i = _spawn_owned(key, Transform3D(Basis.IDENTITY, foot))
		if i < 0:
			return
	if bool(berths[i].get("destroyed", false)) or WorldState.has_flag(Fleet.WRECKED):
		_patch_up(i)
	if i == berth and atmo.state != AtmoFlight.State.PARKED:
		crash_left = -1.0
		atmo.park(foot, yaw)
	for j in berths.size():
		if j != i and _on_pad(j):
			_move_aside(j)
	var u := ground.up_at(foot)
	berths[i].home = foot + u * float(berths[i].clearance)
	berths[i].home_yaw = yaw
	if i == berth:
		home = berths[i].home
		home_yaw = yaw
	_stand(i, foot, yaw)
	(berths[i].visual as Node3D).visible = true
	_remember(i)


## Call: your primary flies itself to clear ground by where you are now (that spot,
## even if you walk on). "" = on its way; otherwise a label key for why not.
func call_ship() -> String:
	var key := Fleet.primary()
	var p := player()
	if key == "" or p == null:
		return "call_none"
	if calling:
		return "call_busy"
	if piloting:
		return "call_seated"
	var i := berth_of(key, true)
	if atmo.state == AtmoFlight.State.ADRIFT or crash_left >= 0.0:
		return "call_busy"            # a ship still coming down (or waiting for her tow) first
	if i >= 0 and berths[i].has("hijacked_by"):
		return "call_hijacked"        # another player flies her: back when they get out
	var at := p.global_position
	var foot := clear_spot(at, 0.0, -1.0, i)
	if foot == Vector3.INF:
		return "call_nowhere"
	if i >= 0 and (bool(berths[i].get("destroyed", false)) or WorldState.has_flag(Fleet.WRECKED)):
		_patch_up(i)
	var u := ground.up_at(foot)
	var from := Vector3.INF
	if i < 0:
		# Not on this planet (or nowhere yet): she comes down out of the sky.
		from = foot + u * GameFlow.setting("call_from_height", 900.0) \
			+ _tangent(u) * GameFlow.setting("call_from_far", 1500.0)
		i = _spawn_owned(key, Transform3D(PlanetSphere.tilt_to(ground.up_at(from)), from))
		if i < 0:
			return "call_none"
	if i != berth:
		_use_berth(i)
	if from == Vector3.INF:
		var d := _flat(foot - atmo.position(), u).length()
		if atmo.state == AtmoFlight.State.PARKED and d < GameFlow.setting("call_near", 15.0):
			return "call_here"
		atmo.takeoff()
	else:
		atmo.place_flying(from, _flat(foot - from, u), 0.0, 0.0)
	call_to = foot
	var to_you := PlanetSphere.tilt_to(u).inverse() * (at - foot)
	call_yaw = atan2(-to_you.x, -to_you.z) if Vector2(to_you.x, to_you.z).length() > 0.5 else _yaw_of(atmo.transform())
	calling = true
	_set_hull(true)
	visual.visible = true
	_foot_toast(GameFlow.label("call_inbound") % vessel_name)
	return ""


## What Call can do right now, for the ledger: { ok, text }.
func call_state() -> Dictionary:
	if Fleet.primary() == "":
		return { "ok": false, "text": GameFlow.label("call_none") }
	if calling:
		return { "ok": false, "text": GameFlow.label("call_busy") }
	if piloting:
		return { "ok": false, "text": GameFlow.label("call_seated") }
	return { "ok": true, "text": GameFlow.label("call") }


## One frame of a call: up off the ground, across at cruise height over whatever is
## under her, then straight down over the spot with the normal landing. The same
## flight model's state, moved the way the bay landing moves it (_bay_step).
func _call_step(dt: float) -> void:
	match atmo.state:
		AtmoFlight.State.LIFTOFF:
			atmo.step(dt)              # its events (the seated toasts) are not for you
		AtmoFlight.State.FLYING:
			_call_fly(dt)
		AtmoFlight.State.LANDING:
			for e in atmo.step(dt):
				if str(e.type) == "landed":
					_call_done()
				elif str(e.type) == "crashed":
					calling = false
					_on_event(e)
		AtmoFlight.State.PARKED:
			_call_done()
		_:
			calling = false
	_sync_visual()


func _call_fly(dt: float) -> void:
	var f = atmo.flight
	var u := ground.up_at(call_to)
	var pos: Vector3 = f.position
	var flat := _flat(call_to - pos, u)
	var d := flat.length()
	var h := (pos - call_to).dot(u)
	var climb := GameFlow.setting("call_climb", 40.0)
	var v := clampf(d * 0.6, 3.0, GameFlow.setting("call_speed", 140.0))
	var rise := 0.0
	if d > GameFlow.setting("call_descend_at", 60.0):
		var agl := atmo.agl()
		var cruise := GameFlow.setting("call_cruise_agl", 120.0)
		rise = clampf((cruise - agl) * 0.8, -climb, climb)
		if agl < minf(cruise * 0.5, 40.0):
			v = 0.0                    # clear of the roofs first
	else:
		rise = clampf((atmo.clearance + GameFlow.setting("call_hold", 25.0) - h) * 0.8, -climb, climb)
	if d < 1.0:
		f.position = call_to + u * h
		f.speed = 0.0
		f.basis = f.basis.slerp(PlanetSphere.tilt_to(u) * Basis(Vector3.UP, call_yaw), minf(1.0, dt * 3.0)).orthonormalized()
		if absf(rise) < 2.0:
			f.basis = PlanetSphere.tilt_to(u) * Basis(Vector3.UP, call_yaw)
			if not atmo.land():
				atmo.state = AtmoFlight.State.LANDING
			return
		f.position += u * rise * dt
		return
	f.position = pos + flat.normalized() * minf(v * dt, d) + u * rise * dt
	var local := PlanetSphere.tilt_to(u).inverse() * flat
	var yaw := atan2(-local.x, -local.z) if d > 20.0 else call_yaw
	f.basis = f.basis.slerp(PlanetSphere.tilt_to(u) * Basis(Vector3.UP, yaw), minf(1.0, dt * 2.0)).orthonormalized()
	f.speed = v


func _call_done() -> void:
	calling = false
	calls += 1
	_set_hull(true)
	_remember(berth)
	_foot_toast(GameFlow.label("call_landed") % vessel_name)


## Clear, landable, flat-enough ground for a ship nearest `near` (rings out to
## `max_r`, from `min_r`), counting a climb up onto a roof as three times its
## height in distance. Not on another ship (berth `skip` aside). INF = none.
func clear_spot(near: Vector3, min_r: float = 0.0, max_r: float = -1.0, skip: int = -1) -> Vector3:
	if max_r < 0.0:
		max_r = GameFlow.setting("call_land_radius", 150.0)
	var u := ground.up_at(near)
	var t1 := _tangent(u)
	var t2 := u.cross(t1)
	var room := GameFlow.setting("call_room", 9.0)
	var best := Vector3.INF
	var best_score := INF
	var r := min_r
	while r <= max_r and r < best_score:
		var n := 1 if r < 0.5 else clampi(int(TAU * r / 6.0), 6, 48)
		for k in n:
			var a := TAU * float(k) / float(n)
			var foot := ground.surface_below(near + (t1 * cos(a) + t2 * sin(a)) * r + u * 200.0)
			var score := r + absf((foot - near).dot(u)) * 3.0
			if score < best_score and _clear_at(foot, room, skip):
				best = foot
				best_score = score
		r += 6.0
	return best


func _clear_at(foot: Vector3, room: float, skip: int) -> bool:
	if not ground.landable(foot.x, foot.z):
		return false
	var u := ground.up_at(foot)
	var half := room * 0.5
	if ground.hit(foot + u * (half + 0.6), half) != "" or ground.hit(foot + u * (room + 1.5), half) != "":
		return false
	var t1 := _tangent(u)
	var t2 := u.cross(t1)
	var flat := GameFlow.setting("call_flat", 1.5)
	for off in [t1 * room * 0.6, -t1 * room * 0.6, t2 * room * 0.6, -t2 * room * 0.6]:
		if absf((ground.surface_below(foot + off + u * 5.0) - foot).dot(u)) > flat:
			return false
	for j in berths.size():
		if j == skip or bool(berths[j].get("destroyed", false)) or not is_instance_valid(berths[j].visual):
			continue
		if _flat((berths[j].visual as Node3D).global_position - foot, u).length() < room + 4.0:
			return false
	return true


## Berth `i`'s ship stands on the pit pad (berth 0's home), on the ground.
func _on_pad(i: int) -> bool:
	if bool(berths[i].get("destroyed", false)) or not is_instance_valid(berths[i].visual):
		return false
	if i == berth and (piloting or atmo.state != AtmoFlight.State.PARKED):
		return false
	var foot := _pad_foot()
	return _flat((berths[i].visual as Node3D).global_position - foot, ground.up_at(foot)).length() < GameFlow.setting("call_pad_room", 8.0)


## Berth `i` off the pit pad, onto clear ground beside it.
func _move_aside(i: int) -> void:
	var foot := clear_spot(_pad_foot(), GameFlow.setting("call_aside_min", 16.0), -1.0, i)
	if foot == Vector3.INF:
		return
	_stand(i, foot, float(berths[i].home_yaw))
	_remember(i)


## The pit pad's deck: under berth 0's home.
func _pad_foot() -> Vector3:
	var h: Vector3 = berths[0].home
	return h - ground.up_at(h) * float(berths[0].clearance)


## Berth `i` stood on the ground at `foot`, facing `yaw` (in the ground's own frame).
func _stand(i: int, foot: Vector3, yaw: float) -> void:
	var b: Dictionary = berths[i]
	var u := ground.up_at(foot)
	var xf := Transform3D(PlanetSphere.tilt_to(u) * Basis(Vector3.UP, yaw), foot + u * float(b.clearance))
	(b.visual as Node3D).global_transform = xf
	if i == berth and not piloting:
		atmo.park(xf.origin, yaw)
		_sync_visual()


## One of your ships stood at `xf` as a berth (a model, or a bare node in the
## greybox). Returns its berth index, -1 when it has no ship data.
func _spawn_owned(key: String, xf: Transform3D) -> int:
	var sid := Fleet.ship_of(key)
	if sid == "" or not content.ships.has(sid):
		return -1
	var v: Node3D
	var look_id := str(content.get_ship(sid).get("look", ""))
	var livery := Fleet.look_of(key)          # issue #401: a LAN guest's ship in their colours
	if demo.use_look and look_id != "":
		v = kit.build(livery if livery != "" else ShipUpgrades.look(sid, look_id))
		kit.dress(v, ShipUpgrades.fitted(sid))
	else:
		v = Node3D.new()
	v.name = "Owned_" + key
	v.set_meta("ship_id", sid)
	if key == Fleet.LAN:
		v.add_child(RemoteShip.make_tag(NetSession.label("ship_tag_yours")))
	demo.add_child(v)
	v.global_transform = xf
	return add_berth(v, sid, "", key)


## Shot to pieces and back: whole again, its fee paid (a toast says how much).
func _patch_up(i: int) -> void:
	var b: Dictionary = berths[i]
	b.destroyed = false
	b.erase("defense")
	b.erase("hijacked_by")            # back from T-89: the one another player took is theirs to lose
	b.erase("stowed")
	if is_instance_valid(b.visual):
		(b.visual as Node3D).visible = true
	if b.hull != null and is_instance_valid(b.hull):
		b.hull.dead = false
		b.hull.collision_layer = int(b.get("hull_layer", 1))
		b.hull.collision_mask = int(b.get("hull_mask", 1))
	if i == berth:
		defense = ShipDefense.new(ship_cfg)
	var fee := Fleet.repair()
	if fee >= 0:
		_foot_toast(GameFlow.label("repaired") % [ShipUpgrades.ship_label(str(b.ship_id)), fee])


## Where berth `i` stands now is where it stays (one of yours; Fleet.remember).
func _remember(i: int) -> void:
	if i < 0 or i >= berths.size() or berth_key(i) == "" or bool(berths[i].get("destroyed", false)):
		return
	if i == berth and not piloting:
		Fleet.remember(berth_key(i), atmo.transform())
	elif i != berth and is_instance_valid(berths[i].visual):
		Fleet.remember(berth_key(i), (berths[i].visual as Node3D).global_transform)


## A heading in the ground's own frame (issue #77: on the ball "up" leans).
func _yaw_of(xf: Transform3D) -> float:
	return (PlanetSphere.tilt_to(ground.up_at(xf.origin)).inverse() * xf.basis).get_euler().y


static func _flat(v: Vector3, u: Vector3) -> Vector3:
	return v - u * v.dot(u)


static func _tangent(u: Vector3) -> Vector3:
	var t := _flat(Vector3.RIGHT, u)
	return (t if t.length() > 0.1 else _flat(Vector3.FORWARD, u)).normalized()


## A line for you on foot (the gear HUD's toast; the flight HUD's in a test without one).
func _foot_toast(text: String) -> void:
	var gear = demo.get("gear") if demo != null else null
	if gear != null and gear.hud != null:
		gear.hud.toast(text, 4.0)
	else:
		hud.toast(text, 4.0)


# ------------------------------------------------------------------ stolen ships (issue #76)

## Taking an outpost's ship: its garrison sounds the alarm. Issue #303: a friend of
## the Remnant in free play borrows it instead: no alarm, no chase, a little
## standing, and (not stolen) nothing for Skrugs to buy.
func _steal(i: int) -> void:
	if DarkPact.borrow_ok():
		berths[i]["borrowed"] = true
		WorldState.change_standing("imperial_remnant", DarkPact.borrow_cost(),
			"Someone borrowed a Remnant ship from %s." % str(berths[i].get("where", Story.outpost_label(str(berths[i].outpost)))))
		return
	berths[i].stolen = true
	steals += 1
	var outposts = demo.outposts if "outposts" in demo else null
	var g = outposts.garrisons.get(str(berths[i].outpost)) if outposts != null else null
	if bool(berths[i].get("town_alarm", false)):
		g = demo.garrison if "garrison" in demo else null     # the barracks pad's (AtmoFighter)
	if g != null and is_instance_valid(g):
		g._raise("ship_stolen")
	var where := str(berths[i].get("where", Story.outpost_label(str(berths[i].outpost))))
	WorldState.log_event("A Remnant ship was stolen from %s." % where)


## A stolen ship that went down is gone; you wake in the pit, flying your own again.
## Issue #276: one you ejected from just goes (you are wherever you came down).
func _lose_stolen(wake_in_pit: bool = true) -> void:
	var p := player()
	var i := berth
	_wreck_berth(i, false)
	if not wake_in_pit:
		return
	if p != null and demo.town != null:
		p.global_position = demo.town.spawn_pos() + Vector3(0, 0.05, 0)
		if p.has_method("align_to_ground"):
			p.call("align_to_ground", true)
	hud.toast(GameFlow.label("stolen_lost"), 4.0)
	woke_in_pit()


# ------------------------------------------------------------------ hijacking (Hijack)

## E is the town's Hijack's this frame (someone else's ship or speeder in reach).
func _hijack_claims() -> bool:
	var h = demo.get("hijack") if demo != null else null
	return h != null and is_instance_valid(h) and h.claims_e()


## Someone on foot may take the ship you sit in now: seated, down here (on the
## ground or in the air under the edge of space), not in a fight, a docking, a bay
## landing or the story's opening.
func can_be_hijacked() -> bool:
	return piloting and not opening and not docking and not bay_landing and not calling \
		and not _fight_flying() and atmo.altitude() < atmo.space_altitude \
		and atmo.state in [AtmoFlight.State.PARKED, AtmoFlight.State.LIFTOFF,
			AtmoFlight.State.FLYING, AtmoFlight.State.LANDING]


## Thrown out of your seat by player `by` (Hijack.on_take): on your feet on the
## ground beside her, and she is not here for you while they fly her (stowed,
## "hijacked_by"; not lost in the save: hijack_returned brings her back). Returns
## what another game needs to fly her on ({} when she can not be taken now).
func thrown_out(by: int) -> Dictionary:
	if not can_be_hijacked():
		return {}
	var flying := atmo.state != AtmoFlight.State.PARKED
	var st := { "ship_id": ship_id, "look": str(visual.get_meta("look_id", "")) if visual != null else "",
		"xf": atmo.transform(), "flying": flying, "speed": atmo.flight.speed if flying else 0.0,
		"throttle": _throttle if flying else 0.0, "hull": lan_hull() }
	var i := berth
	_eject_hold = 0.0
	_leave_seat(_exit_spot())
	atmo.park(atmo.position(), _yaw_of(atmo.transform()))
	_stow(i)
	berths[i]["hijacked_by"] = by
	exited.emit()
	for j in berths.size():
		if not bool(berths[j].get("destroyed", false)):
			_use_berth(j)                  # you fly another of these from now (none: she waits)
			break
	return st


## Player `by` let go of the ship they took from you (Hijack.on_back): she stands
## on the ground under `xf` (INF there: where they took her), yours again; or,
## `wrecked`, she is shot to pieces (the primary waits for T-89's patch-up). False
## when no ship of yours is theirs (she came back another way).
func hijack_returned(by: int, xf: Transform3D, wrecked: bool) -> bool:
	for i in berths.size():
		var b: Dictionary = berths[i]
		if int(b.get("hijacked_by", 0)) != by or not is_instance_valid(b.visual):
			continue
		b.erase("hijacked_by")
		b.erase("stowed")
		b.destroyed = false
		if wrecked:
			_wreck_berth(i, false)
			return true
		if b.hull != null and is_instance_valid(b.hull):
			b.hull.dead = false
			b.hull.collision_layer = 1
			b.hull.collision_mask = 1
		var v: Node3D = b.visual
		var at := v.global_transform if xf.origin == Vector3.INF else xf
		var u := ground.up_at(at.origin)
		_stand(i, ground.surface_below(at.origin + u * 2.0), _yaw_of(at))
		v.visible = true
		_remember(i)
		return true
	return false


## Player `from` threw their pilot out for you (Hijack.on_answer): their ship, as
## `st` (thrown_out's), here as a ship nobody owns (borrowed: lost if you crash
## her, adrift if you eject) and you in her seat, where she was, flying on if she
## was. Returns her berth, -1 when she could not be put here.
func seat_taken(st: Dictionary, from: int) -> int:
	var sid := str(st.get("ship_id", ""))
	if piloting or player() == null or not content.ships.has(sid):
		return -1
	var xf: Transform3D = st.get("xf", Transform3D.IDENTITY)
	var look := str(st.get("look", ""))
	if look == "" or not kit.has_look(look):
		look = str(content.get_ship(sid).get("look", ""))
	var v: Node3D = kit.build(look) if demo.use_look and kit.has_look(look) else Node3D.new()
	v.name = "Hijacked_%d" % from
	v.set_meta("ship_id", sid)
	demo.add_child(v)
	v.global_transform = xf.orthonormalized()
	var i := add_berth(v, sid, "", "")
	berths[i]["borrowed"] = true
	berths[i]["hijacked_from"] = from
	if not board_berth(i):
		_wreck_berth(i, false)
		return -1
	if bool(st.get("flying", false)):
		var thr := clampf(float(st.get("throttle", 0.5)), 0.0, 1.0)
		atmo.place_flying(xf.origin, -xf.basis.z, float(st.get("speed", 0.0)), thr)
		atmo.flight.basis = xf.basis.orthonormalized()
		_throttle = thr
	var hf := clampf(float(st.get("hull", 1.0)), 0.0, 1.0)
	if hf < 1.0 and hf > 0.0:
		defense.shield = 0.0
		defense.apply_damage((1.0 - hf) * float(defense.hull_max()))
	_set_hull(true)
	_sync_visual()
	return i


## Out of a ship you took from another player (got out, ejected): gone from here,
## and theirs again where she is (hijack_let_go: Hijack tells their game).
func _drop_hijacked(wrecked: bool) -> void:
	if berth < 0 or berth >= berths.size() or not berths[berth].has("hijacked_from"):
		return
	var i := berth
	var from := int(berths[i].hijacked_from)
	berths[i].erase("hijacked_from")
	var xf := atmo.transform()
	crash_left = -1.0
	atmo.park(atmo.position(), _yaw_of(xf))
	_stow(i)
	for j in berths.size():
		if not bool(berths[j].get("destroyed", false)):
			_use_berth(j)
			break
	hijack_let_go.emit(from, xf, wrecked)


# ------------------------------------------------------------------ helpers

## Beside the ship (left, then right, then behind), on whatever ground is there.
## Clear of her wings: 5.5 m out, or half her look's span and a bit more for a big
## one (the station's frigate is 16 m across, so 5.5 m put you inside her hull).
func _exit_spot() -> Vector3:
	var b: Basis = atmo.flight.basis
	var s := atmo.position()
	var u := atmo.up()
	var side := maxf(5.5, _look_span() * 0.5 + 1.5)
	var back := maxf(side + 3.0, _look_length() * 0.5 + 1.5)
	for off in [-b.x * side, b.x * side, b.z * back, -b.z * back]:
		var flat: Vector3 = off - u * off.dot(u)
		var at := ground.surface_below(s + flat) + u * 0.05
		if ground.hit(at + u, 0.6) == "":
			return at
	return ground.surface_below(s + u * 5.0) + u * 0.05


func _set_player_collision(on: bool) -> void:
	var p := player()
	for ch in p.get_children():
		if ch is CollisionShape3D:
			ch.set_deferred("disabled", not on)


func _crash_fx(at: Vector3) -> void:
	ExplosionFx.big(demo, at)


func _just(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


func _held(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_pressed(action)


func _axis(neg: String, pos: String) -> float:
	if not InputMap.has_action(neg) or not InputMap.has_action(pos):
		return 0.0
	return Input.get_axis(neg, pos)


## The desert's walkable collider follows whoever is on foot: null while seated,
## the player again once out (it snaps under them if a prefetch has not got there).
func _ground_follow(who: Node3D) -> void:
	if demo.terrain != null:
		demo.terrain.follow(who)
