extends Node3D
## The demo. Builds port_town from content/core at runtime, dresses it with the
## look-dev lighting and materials, places placeholder capsules at the npc /
## trooper / ambient markers, and spawns the player beside the ship in the pit.
## The ship's pad launches the dogfight (GameFlow); after the fight the player
## lands back here. No coordinates live in this file.
##
## Layers: the gameplay layer (boxes + collision, from TownLayout) is built first
## and never changes; TownDecor only adds visuals on top. `use_look = false` gives
## the plain greybox the CI walk trace uses.
##
## The desert: the town sits on the same DesertTerrain as the beauty corner, seated
## at its floor level, so walking out of the gate (or flying over a wall) lands on
## sand that runs on into the dunes. Its collider follows the player. The greybox
## builds the collider only; the look adds the mesh, sand on the aprons and the
## landforms on the horizon. `with_desert = false` is the old town in the void.

const TownLayout := preload("res://src/systems/world/town_layout.gd")
const Greybox := preload("res://src/systems/world/greybox.gd")
const TownDecor := preload("res://src/systems/world/town_decor.gd")
const StairTower := preload("res://src/systems/world/stair_tower.gd")
const PitBowl := preload("res://src/systems/world/pit_bowl.gd")
const RingWall := preload("res://src/systems/world/ring_wall.gd")
const LaunchPad := preload("res://src/systems/flow/launch_pad.gd")
const CharacterBody := preload("res://src/systems/player/character_body.gd")
const CameraRigNode := preload("res://src/systems/camera/camera_rig_node.gd")
const CantinaOwnerNPC := preload("res://src/systems/npc/cantina_owner_npc.gd")
const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const FENCE_CARD := "res://content/core/npcs/fence_card.json"   ## issue #188
const SCENE_PATH := "res://scenes/town_demo.tscn"
const SHOTS_PATH := "res://content/look/town_shots.json"

## Placeholder colors per marker role (greybox).
const ROLE_COLORS := {
	"npc":          Color(0.20, 0.70, 0.60),
	"trooper_post": Color(0.90, 0.90, 0.90),
	"ambient":      Color(0.70, 0.55, 0.80),
}

@export var use_look := true          ## false: plain sun + sky, no decor (CI trace)
@export var lookdev_mode := false     ## true: fixed review cameras, no player
@export var preset := ""              ## "" = default preset in time_of_day.json
@export var with_body := true         ## M11: animated body + hand weapons (needs use_look)
@export var with_bar := true          ## M12: the live cantina owner (needs use_look)
@export var with_gear := true         ## M13: pickups, the gear trader, the jetpack (works in greybox too)
@export var with_desert := true       ## the terrain around the town (collider in greybox too)
@export var terrain_resolution := 320 ## mesh vertices per side (look only; issue #46: was 400)
@export var with_landforms := true    ## mesas, hoodoos, boulders (look only)
@export var with_ship := true         ## M14: the pit's ship is flyable (E boards it instead of quick-launching)
@export var with_npcs := true         ## NPCs on foot: trooper posts with a "soldier" profile get a body, pathing and senses
@export var nav_async := true         ## bake the navmesh on a worker thread (traces may bake in place)
@export var npc_brains := true        ## M15: guards and locals think (patrol, challenge, fight). Off = bodies hold their posts

var town := TownLayout.new()
var look: LookEnvironment
var decor
var camera: Camera3D
var shots: Dictionary = {}
var pads: Array = []
var _player: Node
var _rig: Node
var _arrival: Dictionary = {}
var player_kit: PlayerKit             ## M11 body + weapons (null in the CI greybox)
var training_range: TrainingRange
var cantina_owner: Node3D                 ## M12 (null in the CI greybox)
var bar: Node
var gear: GearController              ## M13
var pilot: ShipPilot                  ## M14
var interceptor: AtmoFighter          ## issue #76: the Remnant's dark interceptor on the barracks pad
var characters: Dictionary = {}       ## marker id -> built character
var terrain: DesertTerrain            ## null when with_desert is off
var dust: DustWind                    ## issue #93: blowing sand round the camera (look only)
var landforms: DesertLandforms
var built_boxes := 0          # read by the trace and tests
var built_markers := 0
var nav: TownNav                      ## the walkable surface NPCs path on
var npcs: Array = []                  ## NpcBody, one per Remnant soldier marker (the garrison)
var stage_performers: Array = []      ## ambient NPCs (dance, do not join a combat group)
var club_look: ClubDressing           ## issue #261: the club's room and the band's instruments (null without one)
var garrison: Garrison                ## M15: runs every trooper in town (null with npc_brains off)
var locals: Array = []                ## NpcBody, one per marker whose profile is in the "locals" faction
var townsfolk: Townsfolk              ## runs every local (null with npc_brains off)
var town_name := ""                   ## issue #15: this town's generated name ("" when its world names none)
var planet_name := ""                 ## and the planet it is on
var place_card: Label                 ## "<town>  ·  <planet>", shown for a few seconds on arrival
var retro_hud: RetroHud               ## issue #52: banner, footer and the F1 info screen (null in the CI greybox)
var objective_hud: ObjectiveHud       ## what to do next and an arrow to it (null in the CI greybox)
var dev_settings: DevSettingsPanel    ## F11: time of day, standing, trust, player cheats
var detail: AltitudeDetail            ## issue #46: less to draw and run the higher you fly
var speeder_post: SpeederPost         ## issue #42: Skrugs's stall outside the back gate, and the speeders
var mechanic: MechanicYard            ## issue #95: Dorrin's speeder yard out in the desert
var harmful_surface: HarmfulSurface    ## issue #298: no air outside without armour (the asteroid)
var barge: PartyBarge                 ## issue #269: the planet's party barge, if it has one
var beast: PlanetBeast                ## issue #220: the planet's beast (a deadly purple blob), if it has one
var natives: NativesDirector          ## issue #96: the planet's native packs and wild animals
var gate_speeders: Array = []         ## issue #82: the Remnant's Sand-boxers parked outside the front gate
var planet: Dictionary = {}           ## issue #45: the planet this scene is (PlanetGen.build), from GameFlow
var world: Dictionary = {}            ## its world (terrain, atmosphere, detail): authored or generated
var style: TownStyle                  ## its town style (metallic, snowy, pastel, words...)
var platform: PlatformWorld           ## the deck, glass, shield and what lies below (platform planets; AsteroidWorld on an asteroid)
@export var with_speeders := true     ## issue #42: Skrugs's post (needs with_ship: it shares the ship's ground)
@export var with_droids := true       ## issue #51: companion droids, the droid merchant, desert wrecks, the Remnant's patrol droids (needs use_look + with_gear)
var droids: DroidController
var droid_merchant_outposts: DroidMerchantOutposts
@export var with_salesman := true     ## issue #58: T-89 in the pit (hello + tutorial, sells ships onto the spare pad)
var salesman: ShipSalesman
@export var resume_saved := true       ## issue #113: open on the save's planet and spot (the real game only, not headless)
@export var with_barge := true        ## issue #269: the planet's party barge (band, boss, steerage), if it has one
@export var with_beast := true        ## issue #220: the planet's beast that rolls about the desert (touch = death)
var general_post: GeneralPost         ## issue #203: the Remnant general (story saves)
var dark_master: DarkMasterPost       ## issue #303: the dark master (cruiser bay, barracks roof)
var barracks_locals: Dictionary = {}  ## issue #303: barracks post id -> the locals' guard on it (NpcBody)
@export var with_natives := true      ## issue #96: native packs and wild animals (when the planet has any)
@export var with_outposts := true     ## issue #64: the Remnant's three desert outposts (needs with_ship: they share the ship's ground)
var outposts: RemnantOutposts
@export var with_cruiser := true      ## issue #193: the Remnant's star cruiser in orbit (needs with_ship and the home ball)
var cruiser: RemnantCruiser
var _town_withdrawn := false          ## issue #64: the garrison left town after the fleet was beaten
var _town_synced := false             ## the barracks' side was set once (at load); later swaps wait until you can't see it
var _respawned := 0


func _ready() -> void:
	var t0 := Time.get_ticks_usec()
	# Issue #113: the first town of a run opened from a save is the save's planet.
	if resume_saved and not lookdev_mode and DisplayServer.get_name() != "headless" \
			and GameFlow.arrival.is_empty() and GameFlow.planet_id == "":
		GameFlow.resume_from_save(SaveSlots.current_path())
	# Issue #45: the planet decides the town, the world, the ground and the look.
	planet = GameFlow.planet()
	PlanetSphere.current = null       # issue #77: only a ball planet sets it again (_build_desert)
	if planet.is_empty():
		push_error("TownDemo: no planet " + GameFlow.current_planet_id())
		return
	world = planet.world
	style = TownStyle.parse(str(planet.get("style", "")))
	PlanetGen.reserve_names(planet)
	town.load_from_dict(planet.town)
	if town.data.is_empty():
		push_error("TownDemo: planet %s has no town" % str(planet.id))
		return
	var errs := TownCheck.errors(str(planet.id), town.data)   # issue #121: once per town per session
	if not errs.is_empty():
		for e in errs:
			push_error("TownDemo: " + str(e))
		return                  # never build a broken town
	# Issue #121: the build is a plan of named steps. A normal arrival runs them all
	# now, in order. A no-fade handoff (the ship flying straight in from another
	# planet) runs only the flight shell now and the rest over the next frames.
	staging = staged_handoff and not lookdev_mode and str(GameFlow.arrival.get("mode", "")) == "handoff"
	staged = StagedBuild.new()
	staged.budget_ms = stage_budget_ms
	for s in build_plan(staging):
		if staging and s.tier == SHELL:
			staged.run_now(s.name, s.fn)
		elif s.poll:
			staged.add_poll(s.name, s.fn)
		else:
			staged.add(s.name, s.fn)
	if staging:
		staged.step_done.connect(func(_n, _ms): _register_detail())
		add_child(staged)
		staged.start()
	else:
		staged.run_all()
		add_child(staged)
	ready_ms = (Time.get_ticks_usec() - t0) / 1000.0


# ---------------------------------------------------------------- the build plan (issue #121)

const SHELL := "shell"    ## built on the scene's first frame, even on a handoff
const LATER := "later"    ## on a handoff: built over the frames after, under the budget

@export var staged_handoff := true    ## issue #121: a no-fade handoff builds a flight shell now and the rest over the next frames
@export var stage_budget_ms := 5.0    ## issue #121: main-thread ms a frame the staged part may spend
var staged: StagedBuild               ## issue #121: this scene's build plan and what each step took
var staging := false                  ## issue #121: this build is a handoff's, spread over frames
var ready_ms := 0.0                   ## issue #121: wall ms _ready took (the scene's first frame)


## Every build step, in the order a normal arrival runs them, from the same planet,
## feature and export flags as always. The shell is what a ship flying in needs to
## carry on with nothing on screen changing: the planet's ball (a coarse far mesh
## at first) and its sky at the carried hour, the town's boxes and pads, the
## player and camera, the ship with its pilot, travel and HUD, and the altitude
## detail. Everything else is LATER. A LATER step may rely on any earlier step
## and on the whole shell; a SHELL step only on earlier SHELL steps.
## `staged_build` adds the steps that only exist on a handoff (the terrain's
## worker-thread jobs, waited on as polls).
func build_plan(staged_build: bool) -> Array:
	var plan: Array = []
	var ground_kind := str(planet.get("ground", "terrain"))
	var add := func(n: String, tier: String, fn: Callable, poll := false) -> void:
		plan.append({ "name": n, "tier": tier, "fn": fn, "poll": poll })
	if use_look:
		# Issue #162: the outfit textures load on worker threads from here, so the
		# people built over the next frames (or after the next handoff) never wait on disk.
		add.call("warm_outfits", SHELL, func(): ModelCache.prefetch(CharacterKit.outfit_textures()); return true)
	add.call("boxes", SHELL, func(): _build_boxes(); return true)
	# One step per character: each is a whole procedural body (tens to hundreds of ms).
	add.call("markers", LATER, func(): _markers_root(); return true)
	for m in town.markers():
		if _shows_marker(m):
			add.call("marker:" + str(m.id), LATER, func(): _build_marker(m); return true)
	if with_npcs and not lookdev_mode:
		add.call("nav", LATER, func(): _build_nav(); return true)
	var ball_terrain := with_desert and ground_kind in ["terrain", "ball"]
	if ball_terrain:
		add.call("desert", SHELL, func(): _build_desert(staged_build); return true)   # issue #99: "ball" (the asteroid) is a real ball too
	add.call("platform", SHELL, func(): _build_platform(ground_kind); return true)
	if use_look:
		add.call("look", SHELL, func(): _build_look(); return true)
		add.call("decor", SHELL, func(): _build_decor(); return true)
		add.call("club_look", LATER, func(): _build_club_look(); return true)    # issue #261: the club's room and instruments
		add.call("dress_desert", SHELL, func():
			if terrain != null:
				_dress_desert()
			return true)
		add.call("dress_platform", SHELL, func():
			if platform is AsteroidWorld:
				(platform as AsteroidWorld).dress_outside(look, decor.mats)   # what shows from space
			elif platform != null:
				platform.dress(look, decor.mats)
			return true)
		add.call("dress_platform_inside", LATER, func():
			if platform is AsteroidWorld:
				(platform as AsteroidWorld).dress_inside()
			return true)
	else:
		add.call("light_and_sky", SHELL, func(): _add_light_and_sky(); return true)
	if not lookdev_mode:
		add.call("ui_scale", SHELL, func(): RetroUI.apply_scale(get_tree()); return true)   # issue #71: text size (F11 > HUD), greybox too
	if use_look and not lookdev_mode:
		add.call("retro_skin", SHELL, func(): add_child(RetroSkin.new()); return true)   # issue #52: the 80s HUD look, on everything from here on
	if lookdev_mode:
		add.call("shots", SHELL, func(): _build_shot_camera(); return true)
		return plan
	add.call("music", SHELL, func(): Sound.start_music(); return true)      # issue #16: carries on across launches and landings
	add.call("player", SHELL, func(): _spawn_player(); return true)
	add.call("club", SHELL, func(): _add_club_music(); return true)    # issue #104: the cantina's club mix
	add.call("pads", SHELL, func(): _build_launch_pads(); return true)
	add.call("world_flags", SHELL, func(): _world_from_scene(); return true)
	if use_look and with_body:
		add.call("body", LATER, func(): _attach_body(has_feature("training_range")); return true)
	if use_look and with_bar:
		add.call("bar", LATER, func(): _build_bar(); return true)
	if with_gear:
		add.call("gear", LATER, func(): _build_gear(); return true)      # after the bar: the save (and the inventory in it) is loaded
	if with_ship:
		add.call("ship", SHELL, func(): _build_ship(); return true)
	if staged_build and ball_terrain:
		# Ground round the town for the people about to stand on it.
		add.call("terrain_town_ground", LATER, func(_left): return _terrain_town_ground(), true)
	if with_npcs:
		add.call("npcs", LATER, func(): _npcs_root(); return true)
		for m in town.markers():
			if _is_live_npc(m):
				add.call("npc:" + str(m.id), LATER, func(): _build_npc(m); return true)
		add.call("outposts", LATER, func(): _build_outposts(not staged_build); return true)
		if staged_build:
			# One piece of an outpost a frame: its ground, nav, look, ship or a trooper.
			add.call("outpost_sites", LATER, func(_left): return outposts == null or outposts.build_step(), true)
		add.call("npc_brains", LATER, func(): _npc_brains(); return true)
		add.call("interceptor", LATER, func(): _build_interceptor(); return true)
	add.call("speeders", LATER, func():
		if with_speeders and pilot != null and has_feature("speeders"):
			_build_speeder_post()
			_park_gate_speeders()
		return true)
	add.call("droids", LATER, func():
		if use_look and with_droids and gear != null:
			_build_droids()
		return true)
	add.call("cruiser", LATER, func(): _build_cruiser(); return true)
	add.call("salesman", LATER, func():
		if with_salesman and gear != null:
			_build_salesman()
		return true)
	add.call("fleet", LATER, func():
		if pilot != null:
			pilot.place_fleet()          # issue #368: your other ships where you left them
		return true)
	add.call("end_card", LATER, func():
		add_child(EndCard.new())          # issue #214: shows itself when the story ends
		return true)
	add.call("general", LATER, func():
		if gear != null and str(planet.get("id", PlanetGen.home_id())) == PlanetGen.home_id():
			_build_general()
		return true)
	add.call("dark_master", LATER, func():
		if gear != null and str(planet.get("id", PlanetGen.home_id())) == PlanetGen.home_id():
			_build_dark_master()
		return true)
	add.call("fence", LATER, func():
		if bar != null and gear != null and townsfolk != null:
			_build_fence()
		return true)
	add.call("mechanic", LATER, func():
		if speeder_post != null and gear != null:
			_build_mechanic()
		return true)
	add.call("barge", LATER, func():
		if with_barge and pilot != null and terrain != null and PartyBarge.lives_on(planet):
			barge = PartyBarge.new()
			barge.setup(self, pilot.ground, planet)
			add_child(barge)
			if player_kit != null:
				player_kit.weapons.off_record_zone = barge.off_record
		return true)
	add.call("surface", LATER, func():
		if not HarmfulSurface.config(planet).is_empty() and _player != null:
			harmful_surface = HarmfulSurface.new().setup(self, HarmfulSurface.config(planet))
			add_child(harmful_surface)
		return true)
	add.call("beast", LATER, func():
		if with_beast and pilot != null and terrain != null and PlanetBeast.lives_on(planet):
			beast = PlanetBeast.new()
			beast.setup(self, pilot.ground, planet)
			add_child(beast)
		return true)
	add.call("natives", LATER, func():
		if with_natives and pilot != null and gear != null and terrain != null:
			_build_natives()
		return true)
	if staged_build:
		# One pack member or animal at a time: each is a whole procedural body.
		add.call("native_bodies", LATER, func(left): return _native_bodies(left), true)
	add.call("detail", SHELL, func(): _build_detail(); return true)
	add.call("names", LATER, func(): _name_places(); return true)          # after the bar: a loaded save keeps the names it had
	add.call("dev_settings", LATER, func():
		dev_settings = DevSettingsPanel.new()
		dev_settings.name = "DevSettings"
		dev_settings.demo = self
		add_child(dev_settings)
		NewGameMenu.show_if_fresh(self, dev_settings)   # issue #200: a first launch picks Story or Free Roam
		return true)
	if use_look:
		# On the first frame: the HUD's frame must not blink out over a handoff.
		add.call("retro_hud", SHELL, func():
			retro_hud = RetroHud.new()
			retro_hud.demo = self
			add_child(retro_hud)
			var notice := DisclaimerOverlay.show_once(self)   # issue #29: AI characters are not real people
			if notice != null:
				notice.ai_chosen.connect(_on_first_run_ai)   # issue #328: the first launch asks
			return true)
		add.call("objective_hud", LATER, func():
			objective_hud = ObjectiveHud.new()
			objective_hud.demo = self
			add_child(objective_hud)
			return true)
	if staged_build and ball_terrain:
		add.call("terrain_far", LATER, func(left): return _terrain_far(left), true)
	return plan


## Issue #121: the town's own collider, from its worker thread (a poll step).
func _terrain_town_ground() -> bool:
	return (terrain as PlanetTerrain).finish_town_collider() if terrain is PlanetTerrain else true


## Issue #121: the ball's full-detail far mesh, a few chunks a frame (a poll step).
func _terrain_far(budget_left: float) -> bool:
	return (terrain as PlanetTerrain).refine_far_step(budget_left) if terrain is PlanetTerrain else true


func _build_platform(ground_kind: String) -> void:
	if ground_kind == "platform":
		platform = PlatformWorld.new()
	elif ground_kind == "ball" and bool(planet.get("type_cfg", {}).get("enclosed", false)) and terrain != null:
		# Issue #99: the sealed station on the asteroid's ball (dome, hallway, pit liner).
		platform = AsteroidWorld.new()
	if platform != null:
		platform.setup(self, planet)
		add_child(platform)


func _build_look() -> void:
	look = LookEnvironment.new()
	_lay_sky(look, planet.get("sky", {}))
	add_child(look)
	set_preset(preset)
	# Issue #99: flown in from another planet with no fade: the same time of day,
	# so the sun is where it was.
	var arr: Dictionary = GameFlow.arrival
	if str(arr.get("mode", "")) == "handoff":
		if float(arr.get("hour", -1.0)) >= 0.0:
			set_hour(float(arr.hour))
		elif str(arr.get("preset", "")) != "":
			set_preset(str(arr.preset))


func _build_decor() -> void:
	decor = TownDecor.new()
	decor.style = style
	decor.location_id = str(planet.get("town_id", "port_town"))
	add_child(decor)
	decor.dress(town, look)


## Issue #261: the cantina dressed as its club (the town's "club" block), and the
## band's instruments in front of them.
func _build_club_look() -> void:
	if town.data.get("club", {}).is_empty():
		return
	club_look = ClubDressing.new()
	add_child(club_look)
	club_look.dress(town, self)


func _build_shot_camera() -> void:
	shots = _load_shots()
	camera = Camera3D.new()
	camera.name = "ShotCamera"
	camera.far = view_far()
	add_child(camera)
	camera.current = true
	show_shot("gate_approach")


# ---------------------------------------------------------------- names (issue #15)

## The town and its planet get their names from the world's "naming" block
## (NameHooks); a card shows them when you arrive, like entering a region.
func _name_places() -> void:
	town_name = NameHooks.town(world)
	planet_name = NameHooks.planet(world)
	DarkPact.town_label = town_name
	if town_name == "":
		return
	var layer := CanvasLayer.new()
	layer.name = "PlaceCard"
	layer.layer = 6
	add_child(layer)
	place_card = Label.new()
	place_card.text = town_name + ("  ·  " + planet_name if planet_name != "" else "")
	place_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	place_card.position = Vector2(-360, 64)
	place_card.size = Vector2(720, 40)
	place_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	place_card.add_theme_font_size_override("font_size", 28)
	place_card.add_theme_color_override("font_color", Color(0.97, 0.92, 0.82))
	place_card.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	place_card.add_theme_constant_override("outline_size", 6)
	place_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(place_card)
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(place_card, "modulate:a", 0.0, 1.5)


# ---------------------------------------------------------------- gameplay layer

func _build_boxes() -> void:
	var root := Node3D.new()
	root.name = "Town"
	add_child(root)
	for b in town.boxes():
		var color: Color = Greybox.KIND_COLORS.get(b.kind, Color.MAGENTA)
		var node: StaticBody3D
		if b.kind == "ramp":
			var rt := TownLayout.ramp_transform(b)
			node = Greybox.make_box(b.id, rt.center, rt.size, color, rt.basis)
		elif b.kind == "spiral":
			node = Greybox.make_trimesh(b.id, StairTower.merged(StairTower.tower_parts(b)), color)
		elif b.kind == "bowl":
			node = Greybox.make_trimesh(b.id, StairTower.merged(PitBowl.parts(b, town)), color)
		elif b.kind == "ring":
			node = RingWall.make_body(b, color)       # issue #237: a round wall
		elif b.kind == "lookout":
			var tower: Dictionary = town.get_box(str(b.get("stair", "")))
			node = Greybox.make_trimesh(b.id, StairTower.merged(StairTower.lookout_parts(b, tower)), color)
		else:
			var cs := Greybox.center_size(b)
			node = Greybox.make_box(b.id, cs[0], cs[1], color, Basis.IDENTITY, str(b.get("shape", "")) == "round")
		if b.kind == "pad":
			for ch in node.get_children():       # issue #58: a painted plate, nothing to trip on
				if ch is CollisionShape3D:
					ch.disabled = true
		root.add_child(node)
		built_boxes += 1


func _build_markers() -> void:
	## Static capsules: no AI, no collision (so they never block the bot).
	_markers_root()
	for m in town.markers():
		_build_marker(m)


## The markers' parent (issue #121: the build plan makes them one at a time).
func _markers_root() -> Node3D:
	var root := get_node_or_null("Markers") as Node3D
	if root == null:
		root = Node3D.new()
		root.name = "Markers"
		add_child(root)
	return root


func _shows_marker(m: Dictionary) -> bool:
	if not ROLE_COLORS.has(m.role):
		return false           # spawn/waypoint/interact are invisible
	return not _is_live_npc(m) # a live NPC gets a real body in _build_npcs instead


func _build_marker(m: Dictionary) -> void:
	if not _shows_marker(m):
		return
	var v := _make_marker_visual(m)
	v.name = m.id
	# Capsules are centered; built characters stand on their feet.
	v.position = town.marker_pos(m.id) + (Vector3.ZERO if v.has_meta("feet") else Vector3(0, 0.9, 0))
	_markers_root().add_child(v)
	built_markers += 1


## The one seam the character art pass replaces. M11: with the look on, markers
## get CharacterKit characters (the cantina owner is built separately by the bar);
## the CI greybox keeps the capsules.
const MARKER_ARCHETYPES := { "npc": "smuggler", "trooper_post": "remnant_trooper", "ambient": "local" }

func _make_marker_visual(m: Dictionary) -> Node3D:
	if use_look and not lookdev_mode:
		if str(m.get("npc", "")) == "cantina_owner" and with_bar:
			var holder := Node3D.new()      # the bar puts her here
			holder.set_meta("feet", true)
			return holder
		var c := _kit().build(MARKER_ARCHETYPES.get(m.role, "local"), str(m.get("pose", "")))
		c.set_meta("feet", true)
		var face := town.marker_pos("gate") if m.role == "trooper_post" else town.marker_pos("cantina_door")
		if m.has("face"):
			face = Vector3(float(m.face[0]), float(m.face[1]), float(m.face[2]))   # e.g. bar patrons look at the cantina owner
		var here := town.marker_pos(str(m.id))
		c.rotation.y = atan2(face.x - here.x, face.z - here.z)
		characters[str(m.id)] = c
		return c
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.35
	mesh.height = 1.8
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if use_look:
		var role_look := {
			"npc": LookMaterials.CLOTH_TEAL,
			"trooper_post": LookMaterials.REMNANT_OXBLOOD,
			"ambient": LookMaterials.CLOTH_SAND,
		}
		mi.material_override = _flat_mats().flat(role_look[m.role])
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = ROLE_COLORS[m.role]
		mesh.material = mat
	return mi


var _kit_inst: CharacterKit
func _kit() -> CharacterKit:
	if _kit_inst == null:
		_kit_inst = CharacterKit.new(_flat_mats(), 0.0)
	return _kit_inst


## Issue #328: the first launch's answer: AI characters on or off, saved, never asked again.
func _on_first_run_ai(on: bool) -> void:
	if bar != null and bar.has_method("answer_first_run"):
		bar.answer_first_run(on)
		return
	var cfg := LLMConfig.new().load_all()
	cfg.set_first_run_asked()
	cfg.set_ai_enabled(on)
	cfg.save_user()


var _mats: LookMaterials
func _flat_mats() -> LookMaterials:
	if _mats == null:
		_mats = LookMaterials.new()
	return _mats


## Issue #104: the club mix of this planet's cantina, heard by distance from it.
func _add_club_music() -> void:
	for z in town.zones():
		if str(z.get("id", "")) == "cantina":
			var id := str(planet.get("cfg", {}).get("club", Sound.lib().cfg.get("club", {}).get("default", "")))
			add_child(ClubMusic.new().setup(id, z, _player))
			return


func _spawn_player() -> void:
	_player = CharacterBody.new()
	_player.fall_damage = CharacterBody.FallDamage.cfg()      # issue #274: the player's falls hurt
	_player.position = town.spawn_pos() + Vector3(0, 0.05, 0)  # origin is at the feet
	var yaw := 0.0
	# Back from a flight: stand at the pad's arrive marker, facing the ship.
	_arrival = GameFlow.take_arrival()
	var from_pad := resolve_pad(GameFlow.pad(str(_arrival.get("pad", ""))))
	if not from_pad.is_empty():
		_player.position = from_pad.arrive
		var c: Vector3 = from_pad.center
		yaw = atan2(c.x - from_pad.arrive.x, c.z - from_pad.arrive.z)
	elif _arrival.is_empty():
		var at := GameFlow.take_resume_pos()        # issue #113: where the save left you
		if at != Vector3.INF:
			_player.position = at + Vector3(0, 0.05, 0)
	add_child(_player)
	_player.call("align_to_ground", true)
	_rig = CameraRigNode.new()
	add_child(_rig)
	_rig.set_player(_player as Node3D)
	_rig.rig.yaw = yaw
	if _rig._camera is Camera3D:
		_rig._camera.far = view_far()
	if terrain != null:
		terrain.follow(_player)
		if terrain is PlanetTerrain:
			# The mid ring follows whichever camera is drawing (on foot, a ship, a speeder).
			(terrain as PlanetTerrain).follow_camera(func():
				var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
				return cam.global_position if cam != null else _player.global_position)
	if not lookdev_mode and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _add_light_and_sky() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.85, 0.75, 0.60)   # dusty sky placeholder
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.55, 0.5)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


# ---------------------------------------------------------------- NPCs on foot

func _is_live_npc(m: Dictionary) -> bool:
	return with_npcs and not lookdev_mode and m.has("soldier")


## Issue #64: a Remnant trooper post. After the fleet is beaten the garrison has
## left town and these stay empty.
func _is_remnant_post(m: Dictionary) -> bool:
	return str(m.get("role", "")) == "trooper_post"


func _build_nav() -> void:
	nav = TownNav.new()
	nav.name = "TownNav"
	add_child(nav)
	nav.build(town, nav_async)


## One NpcBody per marker that names a soldier profile. Placed facing the marker's
## "face" point if it has one (a merchant faces the aisle), else the way the statue
## used to (the gate for a trooper post); senses watch the player. Profiles in the
## Local combatants go to Townsfolk, ambient performers stay out of combat groups,
## and the remaining combatants go to the Garrison.
func _build_npcs() -> void:
	_npcs_root()
	for m in town.markers():
		_build_npc(m)
	_build_outposts()
	_npc_brains()


## The NPCs' parent (issue #121: the build plan makes them one at a time).
func _npcs_root() -> Node3D:
	var root := get_node_or_null("Npcs") as Node3D
	if root == null:
		root = Node3D.new()
		root.name = "Npcs"
		add_child(root)
	return root


func _build_npc(m: Dictionary) -> void:
	if not _is_live_npc(m):
		return
	var soldier := str(m.soldier)
	var key := "npc:%s/%s" % [str(town.data.get("id", "town")), str(m.id)]
	var barracks_post := ""
	if _is_remnant_post(m) and not Story.town_garrison():
		# Issue #187: the locals hold the barracks; their guard on this post, if any.
		soldier = Territory.locals_post("barracks", str(m.id))
		key += "/locals"
		if soldier == "":
			return
		# Issue #303: one guard a post, and a dead one stays dead (the Remnant take
		# the town back when the last of them dies).
		barracks_post = str(m.id)
		var had = barracks_locals.get(barracks_post)
		if (had != null and is_instance_valid(had)) or Territory.barracks_dead().has(barracks_post):
			return
	elif _is_remnant_post(m) and Story.remnant_gone() and Territory.remnant_dead().has(str(m.id)):
		return                        # the fleet is beaten: a dead trooper stays dead
	var here := town.marker_pos(str(m.id))
	var face := town.marker_pos("gate") if m.role == "trooper_post" else town.marker_pos("cantina_door")
	if m.has("face"):
		face = Vector3(float(m.face[0]), float(m.face[1]), float(m.face[2]))
	var npc := make_soldier(soldier, here, atan2(face.x - here.x, face.z - here.z), str(m.id), key)
	if npc == null:
		return
	characters[str(m.id)] = npc.look_body if npc.look_body != null else npc
	built_markers += 1
	if barracks_post != "":
		barracks_locals[barracks_post] = npc
		npc.set_meta("barracks_locals", barracks_post)
		npc.died.connect(Territory.barracks_guard_died.bind(barracks_post))
	elif _is_remnant_post(m):
		npc.died.connect(Territory.remnant_guard_died.bind(str(m.id), _remnant_posts()))


## The town's Remnant trooper posts (the ones with a soldier): every one of them
## dead, once the fleet is beaten, hands the barracks to the locals.
func _remnant_posts() -> Array:
	return town.markers().filter(func(m): return _is_live_npc(m) and _is_remnant_post(m)).map(func(m): return str(m.id))


## Once every town NPC stands: the desert outposts and their guards.
## `now` false (issue #121, a staged handoff): the outpost_sites step builds them.
func _build_outposts(now: bool = true) -> void:
	# The Remnant's outposts are the port's desert's (issue #75: not on other planets).
	if with_outposts and pilot != null and str(planet.get("id", "")) == PlanetGen.home_id():
		outposts = RemnantOutposts.new()
		outposts.setup(self, pilot.ground)
		add_child(outposts)
		if now:
			outposts.build()


## Then the brains that run them all.
func _npc_brains() -> void:
	if npc_brains:
		# The town's garrison, and (issue #64) one per desert outpost: each has its
		# own alarm, so a fight out there never puts the town on alert. The town's
		# handles the player being knocked out; with no town garrison, the first
		# outpost's does.
		var town_troops: Array = npcs if outposts == null else npcs.filter(func(n): return not n.has_meta("outpost"))
		if not town_troops.is_empty():
			garrison = _make_garrison("Garrison", town_troops, true, Vector3.INF, false, _town_zones())
		if outposts != null:
			for o in outposts.outposts:
				var mine: Array = outposts.guards.filter(func(g): return str(g.get_meta("outpost", "")) == str(o.id))
				if mine.is_empty():
					continue
				var first := garrison == null and outposts.garrisons.is_empty()
				outposts.garrisons[str(o.id)] = _make_garrison("Garrison_" + str(o.id), mine, first, o.origin, true, [outpost_zone(o)])
		# Issue #187: someone always counts the player out when they are downed, even
		# with no Remnant left in town or at the outposts (a garrison of nobody).
		if garrison == null and (outposts == null or outposts.garrisons.is_empty()):
			garrison = _make_garrison("Garrison", [], true)
	if npc_brains and not locals.is_empty():
		townsfolk = make_townsfolk("Townsfolk", locals)
		if gear != null:
			gear.vendor_open = townsfolk.vendor_open
			gear.closed_line = townsfolk.closed_line
	if npc_brains and outposts != null:
		# Issue #187: the locals at each outpost they hold have their own alarm.
		for o in outposts.outposts:
			var mine: Array = outposts.held_by.filter(func(g): return str(g.get_meta("outpost", "")) == str(o.id))
			if not mine.is_empty():
				outposts.folks[str(o.id)] = make_townsfolk("Locals_" + str(o.id), mine)


## Issue #187: a director for some of the port's locals (the town's, or one outpost's).
func make_townsfolk(node_name: String, members: Array) -> Townsfolk:
	var t := Townsfolk.new()
	t.name = node_name
	add_child(t)
	t.setup(self, members)
	return t


## Issue #187: a garrison for an outpost the Remnant have just taken back.
func make_outpost_garrison(o: Dictionary, members: Array) -> Garrison:
	return _make_garrison("Garrison_" + str(o.id), members, false, o.origin, true, [outpost_zone(o)])


## Issue #308: the town's checkpoint zones (its "garrison" "checkpoints", e.g. the
## barracks yard). Each is the ground under the boxes it lists ("around": the
## yard walls and the hall, so it follows the barracks in either layout), else
## all of the town "zone" it names.
func _town_zones() -> Array:
	var out: Array = []
	for c in town.data.get("garrison", {}).get("checkpoints", []):
		var spec: Dictionary = (c as Dictionary).duplicate(true)
		for id in spec.get("around", []):
			var bx: Dictionary = town.get_box(str(id))
			if bx.is_empty():
				continue
			var lo: Array = spec.get("min", [INF, INF])
			var hi: Array = spec.get("max", [-INF, -INF])
			spec["min"] = [minf(float(lo[0]), float(bx.min[0])), minf(float(lo[1]), float(bx.min[2]))]
			spec["max"] = [maxf(float(hi[0]), float(bx.max[0])), maxf(float(hi[1]), float(bx.max[2]))]
		if not spec.has("min"):
			for z in town.zones():
				if str(z.get("id", "")) == str(spec.get("zone", "")):
					spec["min"] = z.min
					spec["max"] = z.max
		if spec.has("min"):
			out.append(spec)
	return out


## Issue #308: the ring round outpost `o` (its location file's "zone").
func outpost_zone(o: Dictionary) -> Dictionary:
	var spec: Dictionary = (o.cfg.get("zone", {}) as Dictionary).duplicate(true)
	spec["id"] = str(o.id)
	spec["place"] = str(o.label)
	spec["center"] = o.origin
	if not spec.has("radius"):
		spec["radius"] = 18.0
	if not spec.has("roles"):
		spec["roles"] = ["sentry"]
	return spec


## The Townsfolk running the locals at outpost `id` ("" = the town's own).
func townsfolk_for(id: String) -> Townsfolk:
	if id != "" and outposts != null and outposts.folks.has(id):
		return outposts.folks[id]
	return townsfolk


## `outpost`: a desert outpost's, which fights the player in a speeder or ship too.
## `zones`: issue #308's checkpoint zones (Garrison.zone_specs).
func _make_garrison(node_name: String, members: Array, handles_player: bool, klaxon_at := Vector3.INF,
		outpost := false, zones: Array = []) -> Garrison:
	var g := Garrison.new()
	g.name = node_name
	g.handles_player = handles_player
	g.klaxon_at = klaxon_at
	g.vehicles_anywhere = outpost
	g.zone_specs = zones
	add_child(g)
	g.setup(self, members)
	g.player_armed = func(): return player_kit != null and player_kit.weapons.holder.current != ""
	g.respawn_rule = respawn_rule
	g.spawner = respawn
	return g


## The garrison a Remnant body answers to: its outpost's, else the town's.
func garrison_for(n: Node) -> Garrison:
	if n != null and n.has_meta("cruiser") and cruiser != null and cruiser.garrison != null:
		return cruiser.garrison
	if n != null and n.has_meta("outpost") and outposts != null:
		var g = outposts.garrisons.get(str(n.get_meta("outpost")), null)
		if g != null:
			return g
	return garrison


## One NpcBody from a soldier profile, standing at `here` facing `yaw`, its senses
## on the player, named by `name_key`. It joins `npcs` (the Remnant) or `locals`
## by its faction; the caller hands a Remnant body to the Garrison if it is up.
func make_soldier(soldier_id: String, here: Vector3, yaw: float, post_id: String, name_key: String,
		parent: Node = null) -> NpcBody:
	var cc := _content()
	var soldier: Dictionary = cc.get_soldier(soldier_id)
	if soldier.is_empty():
		push_error("TownDemo: unknown soldier profile " + soldier_id)
		return null
	var npc := make_npc(soldier, here, yaw, post_id, name_key, parent)
	if bool(soldier.get("ambient", false)):
		stage_performers.append(npc)
		if bool(soldier.get("band", false)):
			npc.died.connect(func(): Sound.set_club_live(false))   # issue #261: kill the band, the music stops
	elif npc.faction == "locals":
		locals.append(npc)
	else:
		npcs.append(npc)
	return npc


## The body alone, from a profile already read (make_soldier, or the party
## barge's crowd with its own look): in no list, run by whoever asked for it.
func make_npc(soldier: Dictionary, here: Vector3, yaw: float, post_id: String, name_key: String,
		parent: Node = null) -> NpcBody:
	var npc := NpcBody.new()
	npc.post_id = post_id
	npc.setup(soldier, here, yaw, _flat_mats() if use_look else null)
	npc.nav = nav
	npc.bolt_parent = self
	npc.target = _player
	npc.assign_name(name_key)
	npc.target_crouched = func(): return _player != null and _player.controller.pose == CharacterBody.CharacterController.Pose.CROUCH
	npc.target_armed = func(): return player_kit != null and player_kit.weapons.holder.current != ""
	var root := get_node_or_null("Npcs") if parent == null else parent
	(root if root != null else self).add_child(npc)
	return npc


var _cc: CoreContent
func _content() -> CoreContent:
	if _cc == null:
		_cc = CoreContent.new()
		_cc.load_from()
	return _cc


# ---------------------------------------------------------------- the Remnant (issue #64)

## When a dead trooper comes back, and where (Garrison asks as each one dies).
## Town troopers: behind the barracks a minute later, while the garrison holds
## the town; they walk back to their post. A sentry up on a roof or the tower
## (profile combat.hold_ground) has no way up from there, so it comes back at its
## post on the same clock. Outpost troopers: at their post after a few minutes.
## The bounty target and the general's barracks squad never come back. {} = stays dead.
func respawn_rule(g: NpcBody) -> Dictionary:
	if g.has_meta("bounty") or g.has_meta("cruiser") or g.has_meta("general_squad"):
		return {}
	var rc := Story.remnant_cfg()
	var r := { "soldier": g.soldier_id, "post": g.post_id, "home": g.post_pos, "yaw": g.post_facing }
	if g.has_meta("outpost"):
		r.merge({ "delay": float(rc.get("outpost_respawn_s", 180.0)), "at": g.post_pos, "outpost": str(g.get_meta("outpost")) })
		return r
	var mk := str(rc.get("town_respawn_marker", "remnant_respawn"))
	if not Story.town_garrison() or Story.remnant_gone() or town.get_marker(mk).is_empty():
		return {}                     # the fleet beaten, the town's troopers stay dead (Territory.remnant_dead)
	var aloft := bool(g.profile.get("combat", {}).get("hold_ground", false))
	r.merge({ "delay": float(rc.get("town_respawn_s", 60.0)), "at": g.post_pos if aloft else town.marker_pos(mk) })
	return r


## Bring one back (Garrison calls this when its time is up). Null = not now.
func respawn(r: Dictionary) -> NpcBody:
	var is_outpost := r.has("outpost")
	if not is_outpost and (not Story.town_garrison() or Story.remnant_gone()):
		return null
	if is_outpost and Territory.owner(str(r.outpost)) != Territory.REMNANT:
		return null                   # issue #187: the locals hold it now
	_respawned += 1
	var npc := make_soldier(str(r.soldier), r.at, float(r.yaw), str(r.post),
		"npc:%s/%s#%d" % [str(town.data.get("id", "town")), str(r.post), _respawned])
	if npc == null:
		return null
	npc.post_pos = r.home
	npc.post_facing = float(r.yaw)
	if is_outpost and outposts != null:
		outposts.adopt(npc, str(r.outpost))
		outposts.guards.append(npc)
	elif str(npc.profile.get("role", "")) == "gate":
		WorldState.set_flag("gate_checkpoint_up")
		WorldState.set_flag("gate_guards_down", false)
	return npc


## The fleet is beaten: once the player is back on foot, the town's troopers and
## droids are gone (the outposts keep theirs).
func _withdraw_town_remnant() -> void:
	if _town_withdrawn or Story.town_garrison() or (_player != null and _player.piloting):
		return
	_town_withdrawn = true
	for n in npcs.duplicate():
		if n.has_meta("outpost") or n.has_meta("bounty") or n.has_meta("cruiser") or n.has_meta("dark_master"):
			continue
		if garrison != null:
			garrison.remove_member(n)
		npcs.erase(n)
		n.queue_free()
	if droids != null:
		droids.withdraw_town_remnant()
	WorldState.set_flag("gate_checkpoint_up", false)
	_locals_take_barracks()


## Issue #303: the Remnant take the town back (its barracks guards all dead): the
## locals left on the posts go, the troopers and their droids come back on their
## posts, and the gate checkpoint is up again. Hostile, or (on the dark master's
## oath) on your side: the garrison reads your standing as usual.
func _return_town_remnant() -> void:
	if (_player != null and _player.piloting):
		return
	_town_withdrawn = false
	_repaint_town(Territory.REMNANT)
	for post in barracks_locals:
		var n = barracks_locals[post]
		if n == null or not is_instance_valid(n):
			continue                  # out of sight: the fallen go too
		if townsfolk != null:
			townsfolk.remove_member(n)
		locals.erase(n)
		n.queue_free()
	barracks_locals.clear()
	for m in town.markers():
		if not _is_live_npc(m) or not _is_remnant_post(m):
			continue
		var before := npcs.size()
		_build_npc(m)
		if garrison != null and npcs.size() > before:
			garrison.add_member(npcs.back())
	if droids != null:
		droids.return_town_remnant()
	WorldState.set_flag("gate_checkpoint_up", not town.markers_with_role("trooper_post").is_empty())
	if gear != null and gear.hud != null:
		gear.hud.toast(Territory.line("barracks_remnant"), 5.0)


## Issue #187: the locals move into the barracks: their guards on the posts the
## Remnant left (territory.json "barracks").
func _locals_take_barracks() -> void:
	_repaint_town(Territory.LOCALS)
	if not npc_brains or not with_npcs:
		return
	for m in town.markers():
		if not _is_live_npc(m) or not _is_remnant_post(m):
			continue
		var before := locals.size()
		_build_npc(m)
		if townsfolk != null and locals.size() > before:
			townsfolk.add_member(locals.back())
	if gear != null and gear.hud != null:
		gear.hud.toast(Territory.line("barracks"), 5.0)


## Issue #393: the Remnant's red marks on the barracks, the gate, the wall and the
## towers (and the watchtower banners) are painted for whoever holds the barracks.
## Called with the guard swap, so it happens out of sight like the people. Look only:
## the greybox has no decor and nothing to repaint.
func _repaint_town(owner: String) -> void:
	if decor != null and decor.mats != null:
		decor.mats.repaint(owner)


## Issue #42: Skrugs's speeder stall outside the back gate. Skrugs joins the bar's
## conversation host when there is one (a test that builds the bar later calls
## speeder_post.attach_host itself).
func _build_speeder_post() -> void:
	speeder_post = SpeederPost.new()
	speeder_post.setup(self, pilot.ground)
	add_child(speeder_post)
	if bar != null:
		speeder_post.attach_host(bar)


## Issue #82: the Remnant's black and red Sand-boxers (the town's "vehicle"
## markers), parked outside the front gate while the garrison holds it. Not
## rideable: they are the Remnant's.
func _park_gate_speeders() -> void:
	if not Story.town_garrison():
		return
	for m in town.markers_with_role("vehicle"):
		var s := SpeederNode.new()
		s.setup(self, pilot.ground, {}, false, str(m.get("paint", "")))
		add_child(s)
		s.name = str(m.id).to_pascal_case()
		s.place(town.marker_pos(str(m.id)), deg_to_rad(float(m.get("yaw_deg", 0.0))))
		gate_speeders.append(s)


## Issue #76: the barracks pad's interceptor (the town box with a "remnant_ship").
## After the garrison: it reads its alarm. It stays when the garrison leaves (the
## Remnant then shoot on sight, so it hunts you whenever you fly out of town).
func _build_interceptor() -> void:
	if pilot == null:
		return
	for b in town.boxes():
		if b.has("remnant_ship"):
			interceptor = AtmoFighter.new()
			interceptor.setup(self, b, pilot)
			add_child(interceptor)
			return


## Issue #193: the Remnant's star cruiser, in orbit far east of the port. Part of the
## home planet's map (its world's "cruiser" landmark put its boxes in the ship's
## ground already); after the droids, whose Remnant units its crew includes.
func _build_cruiser() -> void:
	if not with_cruiser or pilot == null or not CruiserHull.has_cruiser(pilot.ground):
		return
	cruiser = RemnantCruiser.new()
	cruiser.setup(self, pilot.ground)
	add_child(cruiser)


## Issue #51: companion droids. After the gear (its HUD and E prompt are shared)
## and the NPCs (the Remnant's droids answer to the garrison's alarm).
func _build_droids() -> void:
	if pilot != null and str(planet.get("id", "")) == PlanetGen.home_id():
		droid_merchant_outposts = DroidMerchantOutposts.new()
		droid_merchant_outposts.setup(self, pilot.ground)
		add_child(droid_merchant_outposts)
	droids = DroidController.new()
	droids.setup(self, _player, gear)
	add_child(droids)


## Issue #95: Dorrin's speeder yard, out in the desert. After the speeders (he
## works on the ones SpeederPost parks) and the gear (its HUD and E are shared).
func _build_mechanic() -> void:
	mechanic = MechanicYard.new()
	mechanic.setup(self, pilot.ground, gear)
	add_child(mechanic)


## Issue #96: the planet's native packs and wild animals (PlanetGen gave the
## planet its "natives"). After the gear (its HUD, its E) and the ship (the ground).
func _build_natives() -> void:
	var n: Dictionary = planet.get("natives", {})
	if n.is_empty():
		return
	natives = NativesDirector.new()
	natives.setup(self, n, pilot.ground, gear)
	natives.staged = staging          # issue #121: a handoff makes the bodies in native_bodies
	add_child(natives)


## Issue #121: the natives' bodies, at least one a frame and more while the frame's
## budget lasts (a poll step). Nothing to do without natives.
func _native_bodies(budget_left: float) -> bool:
	if natives == null or not is_instance_valid(natives):
		return true
	var t0 := Time.get_ticks_usec()
	while not natives.build_step():
		if (Time.get_ticks_usec() - t0) / 1000.0 >= budget_left:
			return false
	return true


## Issue #58: T-89 in the pit. After the ship (a bought ship becomes a berth) and
## the bar (the save says which ship is on the spare pad, and whether he has met
## the player). He joins the bar's host as an AI character when there is one.
func _build_salesman() -> void:
	salesman = ShipSalesman.new()
	salesman.setup(self, _player, gear)
	add_child(salesman)
	if bar != null:
		salesman.attach_host(bar)


## Issue #203: the Remnant general (story saves; GeneralPost stands him wherever
## the story has him). He joins the bar's host as an AI character.
func _build_general() -> void:
	general_post = GeneralPost.new()
	general_post.setup(self, _player, gear)
	add_child(general_post)
	if bar != null:
		general_post.attach_host(bar)


## Issue #303: the dark master: in the cruiser's bay after the general dies, on the
## barracks roof while the Remnant hold the planet. He joins the bar's host as an
## AI character (his offer is a talk).
func _build_dark_master() -> void:
	dark_master = DarkMasterPost.new()
	dark_master.setup(self, _player, gear)
	add_child(dark_master)
	if bar != null:
		dark_master.attach_host(bar)


## Issue #188: the fence talks: an AI character on the bar's host from his own card
## (content/core/npcs/fence_card.json), in the body of the local who keeps his
## stall. "Talk" leads the stall's [E] menu (GearController.vendor_talk), so he
## only talks while his stall trades (alive, and the locals not fighting).
func _build_fence() -> void:
	for v in gear.vendors:
		if str(v.cfg.get("id", "")) != "fence":
			continue
		for g in townsfolk.members:
			if g.post_id == str(v.cfg.get("marker", "")):
				var spot := TalkSpot.new(NpcBrain.new(null, FENCE_CARD), g, v.pos)
				spot.manual = true
				spot.radius = float(v.cfg.get("reach", 3.5))
				bar.add_spot(spot)
				gear.vendor_talk["fence"] = func(): bar.start_talk(spot)
				return


## Issue #46: the world's "detail" tiers, and what they may switch off: the
## people (bodies, the cantina owner, and the brains that run them) and the small
## props (lamps, banners, boulders). ShipPilot feeds it the viewer's altitude.
func _build_detail() -> void:
	detail = AltitudeDetail.new()
	detail.setup(world.get("detail", {}), look)
	_register_detail()
	add_child(detail)


## Hand AltitudeDetail every group built so far. Safe to call again: a node is
## only added once, and (issue #121) one built after the tier was set (a staged
## handoff builds the people while the ship is still high up) takes that tier's
## state at once, so nothing pops in.
func _register_detail() -> void:
	if detail == null:
		return
	detail.add_group("people", [get_node_or_null("Markers"), get_node_or_null("Npcs"), cantina_owner, garrison, townsfolk,
		speeder_post.skrugs if speeder_post != null else null, mechanic.mechanic if mechanic != null else null, natives,
		droid_merchant_outposts])
	if decor != null:
		var small_props := [decor.get_node_or_null("Lamps"), decor.get_node_or_null("Banners")]
		detail.add_group("props", small_props)
		detail.add_group("small_props", small_props)
	if landforms != null:
		detail.add_group("props", [landforms.get_node_or_null("Boulders")])
	if dust != null:
		detail.add_group("weather", [dust])


func npc(post_id: String) -> NpcBody:
	for n in npcs + locals:
		if n.post_id == post_id:
			return n
	return null


# ---------------------------------------------------------------- M11 / M12

## Facts the scene itself makes true, plus whatever the flight we just came back
## from did. The cantina owner reads these (WorldState), so her talk matches the town.
func _world_from_scene() -> void:
	WorldState.set_flag("gate_checkpoint_up", not town.markers_with_role("trooper_post").is_empty() and Story.town_garrison())
	WorldState.time_of_day = preset if preset != "" else WorldState.time_of_day
	WorldState.on_flight_returned(_arrival)


func _attach_body(with_range: bool = true) -> void:
	player_kit = PlayerKit.attach(_player, _rig, self, _flat_mats())
	if not with_range:
		return                       # issue #45: the practice range is the port's
	training_range = TrainingRange.new()
	add_child(training_range)
	training_range.player = _player
	training_range.blade_out = func(): return player_kit.weapons.holder.current == "energy_blade" and player_kit.weapons.blade_extent > 0.5
	player_kit.weapons.in_range_zone = training_range.contains


## `scripted` = CI providers (no network); `save_path` "" = do not persist, null =
## the save being played (SaveSlots: story or free roam).
func _build_bar(scripted = null, save_path = null) -> void:
	bar = ConversationHost.new()
	bar.name = "Bar"
	bar.autosave = save_path != ""
	if save_path != null and save_path != "":
		bar.save_path = save_path
	add_child(bar)
	bar.setup(self, scripted)
	cantina_owner = bar.npc


## M13: gear in the town. Pickups and vendors come from content/core; the gear
## node puts a jetpack on the player while one is attached.
func _build_gear() -> void:
	gear = GearController.new()
	gear.setup(null, town, _player, _rig, str(planet.get("town_id", "port_town")))
	if terrain != null:
		gear.ground_at = terrain.ground_at
	elif platform != null:
		gear.ground_at = platform.ground_at      # the void: the deck's own fall handles it
	if pilot != null:
		gear.ground = pilot.ground      # issue #121: a staged handoff builds the ship first
	gear.on_refit = func():             # issue #208: the fence's gun upgrades
		if player_kit != null and player_kit.weapons != null:
			player_kit.weapons.refit()
	add_child(gear)


## M14: the pit's ship becomes the one you fly, and the world opens up around the
## town. The pad stops quick-launching: E boards the ship, and flying out of the
## atmosphere is the way to space.
func _build_ship() -> void:
	for pd in pads:
		pd.quick_launch = false
	pilot = ShipPilot.new()
	pilot.setup(self)
	add_child(pilot)
	if gear != null:
		gear.ground = pilot.ground      # issue #93: the fall guard, round the ball


func _physics_process(dt: float) -> void:
	WorldState.tick(dt)
	# The barracks change hands out of sight (the first look, at load, is free).
	var swap_now := not _town_synced or _barracks_unseen()
	if not _town_withdrawn and not Story.town_garrison():
		if swap_now:
			_withdraw_town_remnant()
	elif _town_withdrawn and Story.town_garrison():
		if swap_now:
			_return_town_remnant()
	_town_synced = true


## No barracks post on screen and you at least barracks_unseen_dist from each,
## or every one further than swap_dist (territory.json).
func _barracks_unseen() -> bool:
	if _player == null or not is_instance_valid(_player) or not (_player is Node3D):
		return true
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var near := Territory.n("barracks_unseen_dist", 40.0)
	var far := Territory.n("swap_dist", 110.0)
	var me: Vector3 = (_player as Node3D).global_position
	for m in town.markers_with_role("trooper_post"):
		var at := town.marker_pos(str(m.id))
		var d := me.distance_to(at)
		if d > far:
			continue
		if d < near or cam == null or cam.is_position_in_frustum(at + Vector3.UP * 1.5):
			return false
	return true


# ---------------------------------------------------------------- desert

## The far plane: out to the horizon landforms when the desert is on.
func view_far() -> float:
	if terrain is PlanetTerrain:
		return 4.0 * (terrain as PlanetTerrain).sphere.radius   # the whole ball, from orbit too
	return 12000.0 if terrain != null or platform != null else 4000.0


# ---------------------------------------------------------------- planets (issue #45)

## True when the planet's config lists this feature (the port's practice range,
## Skrugs's speeders, the desert landforms, the jetpack pickups).
func has_feature(f: String) -> bool:
	return (planet.get("features", []) as Array).has(f)


## The planet type's sky: its values laid over every time-of-day preset, so the
## clock and F11 still work (an asteroid's grey, a snow world's pale blue).
func _lay_sky(env: LookEnvironment, sky: Dictionary) -> void:
	if sky.is_empty():
		return
	for id in env.presets:
		env.presets[id] = deep_merge(env.presets[id], sky)


static func deep_merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in over:
		if out.get(k) is Dictionary and over[k] is Dictionary:
			out[k] = deep_merge(out[k], over[k])
		else:
			out[k] = over[k]
	return out


## Footprints from the town data (no coordinates in this file): every floor box
## at floor level, the walled area, and the floors sunk below it (the pit).
func desert_site() -> Dictionary:
	var floor_rect := Rect2()
	var sunken := []
	var first := true
	for b in town.boxes():
		if str(b.kind) != "floor":
			continue
		var r := Rect2(float(b.min[0]), float(b.min[2]), float(b.max[0]) - float(b.min[0]), float(b.max[2]) - float(b.min[2]))
		if float(b.max[1]) < -0.1:
			sunken.append({ "rect": r, "y": float(b.min[1]) })
			continue
		floor_rect = r if first else floor_rect.merge(r)
		first = false
	var bounds: Dictionary = town.data.get("bounds", {})
	var walls := floor_rect
	if not bounds.is_empty():
		walls = Rect2(float(bounds.min[0]), float(bounds.min[1]),
			float(bounds.max[0]) - float(bounds.min[0]), float(bounds.max[1]) - float(bounds.min[1]))
	return { "floor": floor_rect, "walls": walls, "sunken": sunken }


## `staged_build` (issue #121, a handoff): a ball's terrain builds only what the
## first frame needs (a coarse far mesh) and the rest on worker threads.
func _build_desert(staged_build := false) -> void:
	var site := desert_site()
	# Issue #77: a world with a sphere_radius is a whole ball (the home planet,
	# seated on its town: PlanetTerrain.for_planet); the rest are still a square
	# of desert.
	terrain = PlanetTerrain.for_planet(planet)
	if terrain == null:
		terrain = DesertTerrain.new()
		terrain.resolution = terrain_resolution
		terrain.collider_size = 512.0
		terrain.configure_site(site.floor, site.walls, site.sunken, 0.0)
	add_child(terrain)
	if staged_build and terrain is PlanetTerrain:
		(terrain as PlanetTerrain).build_staged(use_look)
	else:
		terrain.build(use_look)          # greybox: collider only
	if terrain is PlanetTerrain:
		PlanetSphere.current = (terrain as PlanetTerrain).sphere
		tree_exiting.connect(func():
			if PlanetSphere.current == (terrain as PlanetTerrain).sphere:
				PlanetSphere.current = null)


## Look only: the aprons outside the walls are hidden (still solid) so the terrain's
## sand, which lies exactly at their top, is what you see: paving runs straight
## into sand. The sun drives the sand's glitter, and the horizon gets landforms.
func _dress_desert() -> void:
	look.track_material(terrain.material)
	if terrain is PlanetTerrain and not (terrain as PlanetTerrain).rock_look.is_empty():
		return          # issue #99: the asteroid's rock: no sand, dust or desert landforms
	var walls: Rect2 = desert_site().walls
	for b in town.boxes():
		if str(b.kind) != "floor" or float(b.max[1]) < -0.1:
			continue
		var r := Rect2(float(b.min[0]), float(b.min[2]), float(b.max[0]) - float(b.min[0]), float(b.max[2]) - float(b.min[2]))
		if walls.encloses(r):
			continue
		var mi := get_node_or_null("Town/%s/Mesh" % str(b.id)) as MeshInstance3D
		if mi != null:
			mi.visible = false
	_tint_sand(terrain.material, planet.get("type_cfg", {}).get("sand", {}))
	# Issue #93: wind you can see over the sand (not on a snow world).
	if str(planet.get("type", "sand")) != "snow":
		dust = DustWind.new()
		add_child(dust)
		var wd = terrain.material.get_shader_parameter("wind_dir")
		dust.set_wind(wd if wd is Vector2 else Vector2(0.8, 0.6))   # unset: the shader's default
	if with_landforms:
		landforms = DesertLandforms.new()
		landforms.clear_circles = _landmark_clearings()
		add_child(landforms)
		landforms.build(terrain, _flat_mats(), desert_site().floor)
		if terrain is PlanetTerrain:
			for m in landforms.rock_materials():
				look.track_material(m)       # the sun, for the dusk side (issue #77)
		_tint_rock(landforms, planet.get("type_cfg", {}).get("rock", {}))


## Issue #45: a snow world's white drifts, a red desert's red sand. Shader values
## from the planet type ("sand"); the port's own (empty) changes nothing.
func _tint_sand(m: ShaderMaterial, sand: Dictionary) -> void:
	if m == null:
		return
	for k in sand:
		var v = sand[k]
		m.set_shader_parameter(k, Color(str(v)) if v is String else v)


func _tint_rock(root: Node, rock: Dictionary) -> void:
	if rock.is_empty():
		return
	var done := {}
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var mat = (n as GeometryInstance3D).material_override
		if mat is ShaderMaterial and not done.has(mat):
			done[mat] = true
			for k in rock:
				mat.set_shader_parameter(k, Color(str(rock[k])))


## Issue #64: the world's landmarks that want open sand round them (the outposts).
func _landmark_clearings() -> Array:
	var cc := CoreContent.new()
	cc.load_from()
	var out: Array = []
	for lm in cc.world_for_town(str(town.data.get("id", "")), str(town.data.get("layout", ""))).get("landmarks", []):
		if lm.has("clear"):
			out.append([Vector2(float(lm.at[0]), float(lm.at[2])), float(lm.clear)])
	return out


# ---------------------------------------------------------------- launch pads

## A pad anchored to a town box sits on that box's footprint center at its base,
## and returns the player to its arrive marker. Coordinates come from town data.
func resolve_pad(p: Dictionary) -> Dictionary:
	if p.is_empty() or str(p.get("scene", "")) != SCENE_PATH:
		return {}
	var out := p.duplicate(true)
	var box: Dictionary = town.get_box(str(p.get("town_box", "")))
	if box.is_empty():
		return {}
	var cs := Greybox.center_size(box)
	var c: Vector3 = cs[0]
	out.center = Vector3(c.x, float(box.min[1]), c.z)
	var am := str(p.get("arrive_marker", ""))
	out.arrive = (town.marker_pos(am) if not town.get_marker(am).is_empty() else town.spawn_pos()) + Vector3(0, 0.05, 0)
	return out


func _build_launch_pads() -> void:
	for p in GameFlow.pads_for_scene(SCENE_PATH):
		var r := resolve_pad(p)
		if r.is_empty():
			push_warning("TownDemo: launch pad %s has no town_box" % str(p.get("id", "")))
			continue
		var c: Vector3 = r.center
		r.center = [c.x, c.y, c.z]
		var pad := LaunchPad.new()
		pad.configure(r, _player)
		add_child(pad)
		pads.append(pad)
	# A no-fade handoff says nothing: the player should not notice the switch.
	if not _arrival.is_empty() and not pads.is_empty() and str(_arrival.get("mode", "")) != "handoff":
		pads[0].toast(GameFlow.arrival_text(_arrival), 5.0)


# ---------------------------------------------------------------- look + review

func set_preset(id: String) -> void:
	if look == null:
		return
	look.apply(id)
	preset = look.current
	WorldState.time_of_day = preset


## A time of day in hours, blended between presets (F11). `preset` and the
## world's time_of_day follow the nearer preset, so rumors still key on it.
func set_hour(h: float) -> void:
	if look == null:
		return
	look.apply_hour(h)
	preset = look.current
	WorldState.time_of_day = preset


func _load_shots() -> Dictionary:
	var f := FileAccess.open(SHOTS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	if not data is Dictionary:
		return {}
	var out: Dictionary = data.get("shots", {}).duplicate(true)
	# Issue #237: a layout's own cameras ("layouts": { <layout>: { shot: ... } }) replace or add to these.
	var layout := str(town.data.get("layout", "")) if town != null else ""
	var own: Dictionary = data.get("layouts", {}).get(layout, {})
	for id in own:
		if own[id] is Dictionary:
			out[id] = own[id]
	return out


func shot_ids() -> Array:
	return shots.keys()


func show_shot(id: String) -> bool:
	if camera == null or not shots.has(id):
		return false
	var s: Dictionary = shots[id]
	var pos := Vector3(s["pos"][0], s["pos"][1], s["pos"][2])
	if s.has("height_above_ground") and terrain != null:
		pos.y = terrain.height_at(pos.x, pos.z) + float(s["height_above_ground"])
	var target := Vector3(s["target"][0], s["target"][1], s["target"][2])
	var up := Vector3.UP
	# Issue #77: "map" = [x, z, metres up, target x, z, metres up] on the ball.
	if s.has("map") and terrain is PlanetTerrain:
		var sp: PlanetSphere = (terrain as PlanetTerrain).sphere
		var m: Array = s["map"]
		var g := sp.surface_at(float(m[0]), float(m[1]))
		up = sp.up_at(g)
		pos = g + up * float(m[2])
		var gt := sp.surface_at(float(m[3]), float(m[4]))
		target = gt + sp.up_at(gt) * float(m[5])
	camera.fov = float(s.get("fov", 65.0))
	camera.global_position = pos
	camera.look_at(target, up)
	if terrain is PlanetTerrain:
		terrain.snap_to(pos)         # the fine sand under this shot
		(terrain as PlanetTerrain).follow_camera(func(): return camera.global_position)
		# The sky a ship would see at this height (fog clears, stars come out).
		if look != null:
			if _shot_sky == null:
				_shot_sky = AltitudeSky.new()
				_shot_sky.setup(look, world.get("atmosphere", {}))
				add_child(_shot_sky)
			_shot_sky._applied = -1.0
			_shot_sky.update_for((terrain as PlanetTerrain).sphere.altitude(pos), pos)
	return true


var _shot_sky: AltitudeSky


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if bar != null and bar.is_talking():
			return                      # the dialogue panel owns Esc while talking
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and not lookdev_mode \
			and not (bar != null and bar.is_talking()):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F4 and not WorldState.story_mode():
		NpcBody.show_debug = not NpcBody.show_debug   # what each guard sees and hears (free roam only)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_L:
		# L cycles the lighting (1/2/3 are weapons since M11).
		var ids := ["golden", "noon", "dusk"]
		set_preset(ids[(ids.find(preset) + 1) % ids.size()])
