class_name DevSettingsPanel
extends CanvasLayer
## F11 in the town: the game's settings. Opening it pauses the game and frees
## the mouse; closing it resumes and saves (when the bar saves). Six pages:
##   Map       a globe of the planet with every place that stays put, you and the
##             waypoint, click one for a waypoint; the places off planet beside it
##             (GlobeMap; M opens it)
##   Ledger    what you own on the left, the story and your jobs on the right, each
##             with a waypoint button (InventoryPanel; I opens it)
##   Game      the main story's chapter (issue #64), time of day, game speed,
##             credits, the space fight switch, the home town's layout, new game
##   Player    the outfit from the kit pieces (CharacterBuilder, issue #48), then
##             god mode, heal, jetpack, teleport and guard debug
##   Standing  faction standing, each individual's trust / mood / tab, and every
##             world flag the content reads
##   Options   the HUD's colour (issue #52) and text size (issue #71), volume
##             (issue #16), indirect light, the AI characters' brain (issue #80)
##             and every key
##
## Everything writes to the same places the game does (WorldState, the npc's
## Relationship, the look), so the cantina owner, rumors and checkpoint react as if
## it had happened in play.
##
## A story save earns what free roam hands out: there the controls that would give
## it (credits, the space fight switch, standing and trust, god mode, heal, the
## jetpack, endless fuel, teleport, guard senses, flags) are greyed out, each page
## saying why. Game speed, the look, HUD, sound, the AI brain and the smuggler's
## own outfit stay the player's. A stuck player may still skip ahead a chapter,
## after a warning that points them at the characters first.

const MOODS := ["wary", "warm", "amused", "irritated"]
const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0]

var demo                              ## town_demo.gd
var _panel: PanelContainer
var tabs: TabContainer               ## issue #80: open_tab() picks one by title
var _was_mouse := Input.MOUSE_MODE_VISIBLE
var _refreshers: Array[Callable] = []  ## each puts the live value back into its control
var _hour: HSlider
var _hour_label: Label
var _flags_box: VBoxContainer
var _flag_new: LineEdit
var builder: CharacterBuilder
var _god := false
var _endless_fuel := false
var _cheats: Array[Control] = []       ## greyed out in a story save (_lock_for_story)
var _story_notes: Array[Control] = []  ## shown only in a story save
var skip_confirm: ConfirmationDialog   ## a story save asks before skipping a chapter
var _skip_to := ""
var _anchors: Dictionary = {}          ## a name open_tab knows -> the section label it scrolls to
var globe: GlobeView                   ## the Map page's globe
var cruiser_view: CruiserMapView       ## the Map page's side view of the cruiser
var system_view: SystemView            ## the Map page's chart of the star system
var _map_view := ""                    ## what the Map page shows: "" here, a planet id, "cruiser" or "system"
var _map_title: Label
var _map_back: Button
var _map_you: Button
var _map_home: Button
var _off_planet: Array = []            ## GlobeMap.off_planet, last refresh
var _off_box: VBoxContainer
var _map_note: Label
var _no_globe: Label
var inventory: InventoryPanel          ## the Ledger page

const STUCK_WARNING := "If you are stuck, ask the interactive NPCs for advice, they may have a hint.\n\nAre you sure?"


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_fit()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.06, 0.06, 0.96)
	sb.border_color = Color("#b08e50")
	sb.set_border_width_all(1)
	for side in ["left", "right", "top", "bottom"]:
		sb.set("content_margin_" + side, 14)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)
	var title := Label.new()
	title.text = "Settings  (F11)"
	title.add_theme_font_size_override("font_size", 18)
	v.add_child(title)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	var h := HBoxContainer.new()
	v.add_child(h)
	for b in [["Save now", _save], ["Close", close]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.pressed.connect(b[1])
		h.add_child(btn)
	visible = false


## The pages themselves, made the first time the panel opens (issue #121: they cost
## about a second to build, on every arrival, for a panel most visits never open).
var tabs_built := false


func _build_tabs() -> void:
	if tabs_built:
		return
	tabs_built = true
	tabs.add_child(_map_tab())
	tabs.add_child(_inventory_tab())
	var game := _tab("Game")
	_lan_page(game)
	_saves_page(game)
	_story_page(game)
	_world_page(game)
	_new_game_page(game)
	tabs.add_child(game.get_parent())
	var player := _tab("Player")
	_character_page(player)
	_player_page(player)
	tabs.add_child(player.get_parent())
	var standing := _tab("Standing")
	_standing_page(standing)
	_flags_page(standing)
	tabs.add_child(standing.get_parent())
	var options := _tab("Options")
	_hud_page(options)
	_sound_page(options)
	_graphics_page(options)
	_llm_page(options)
	_keys_page(options)
	tabs.add_child(options.get_parent())


## _input, not _unhandled_input: a focused slider or text field must not swallow F11.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			toggle()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and visible:
			close()
			get_viewport().set_input_as_handled()


## M opens the Map page, I (the inventory action) the Ledger page; the same key
## again shuts the panel, the other one swaps pages. Unhandled: typing an M or an I
## in a text box is not this.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var page := ""
	if event.keycode == KEY_M:
		page = "Map"
	elif event.is_action_pressed("inventory"):
		page = "Ledger"
	if page == "":
		return
	if visible and tabs.get_tab_title(tabs.current_tab) == page:
		close()
	else:
		open_tab(page)
	get_viewport().set_input_as_handled()


## Issue #80: the cursor shows on every page while the settings are open, whatever
## else (a click in the world, a tab's own controls) tried to capture it.
func _process(_dt: float) -> void:
	if visible and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if visible and _lan_refresh.is_valid():
		_lan_refresh.call()          # players come and go while the panel is open


func _physics_process(_dt: float) -> void:
	var p = _player()
	if p == null:
		return
	if WorldState.story_mode():
		return
	if _god:
		p.invulnerable_left = maxf(p.invulnerable_left, 1.0)
	if _endless_fuel and p.jetpack != null:
		p.jetpack.fuel = p.jetpack.fuel_max()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## Issue #80: open on a page by its title, or on the page holding a section
## anchored by that name ("LLM": F10 lands on Options, scrolled to the AI brain).
func open_tab(title: String) -> void:
	open()
	var at: Control = _anchors.get(title, null)
	for i in tabs.get_tab_count():
		var page := tabs.get_tab_control(i)
		if tabs.get_tab_title(i) == title or (at != null and page.is_ancestor_of(at)):
			tabs.current_tab = i
			if at != null and page is ScrollContainer:
				var scroll := page as ScrollContainer
				(func():
					if is_instance_valid(scroll) and is_instance_valid(at):
						scroll.ensure_control_visible(at)).call_deferred()
			return


func open() -> void:
	if visible:
		return
	_build_tabs()
	_fit()
	visible = true
	_was_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	Input.mouse_mode = _was_mouse
	_save()


## The panel's size: SIZE, or the window less a margin when that is smaller (a
## big text size on a small window), so the tabs and the buttons stay on screen.
const SIZE := Vector2(760, 620)


func _fit() -> void:
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else SIZE
	var half := Vector2(minf(SIZE.x, vp.x - 24.0), minf(SIZE.y, vp.y - 24.0)) * 0.5
	_panel.offset_left = -half.x
	_panel.offset_right = half.x
	_panel.offset_top = -half.y
	_panel.offset_bottom = half.y


## Pull every control back from the live game (it changes while the panel is shut).
func refresh() -> void:
	if not tabs_built:
		return                      # nothing to refresh until the pages exist
	for r in _refreshers:
		r.call()
	_rebuild_flags()
	_lock_for_story()


## Grey out every control a story save has to earn in play, and show each page's
## note saying so; free roam gets them all back.
func _lock_for_story() -> void:
	var locked := WorldState.story_mode()
	for c in _cheats:
		if c is BaseButton:
			c.disabled = locked
		else:
			c.set("editable", not locked)   # sliders, spin boxes, line edits
	for n in _story_notes:
		n.visible = locked


## Register a control _lock_for_story greys out in a story save. Returns it.
func _cheat(c: Control) -> Control:
	_cheats.append(c)
	return c


## A page's line on what a story save keeps for play, hidden in free roam.
func _story_note(v: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = "Story save: " + text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	l.visible = false
	v.add_child(l)
	_story_notes.append(l)


# ------------------------------------------------------------------ inventory

## The Ledger, wired to the town's gear (its item names and wear toggle). Rebuilt
## on open and whenever the page is picked (a cheat on the Player page may have
## just handed you the jetpack); a waypoint picked there moves the HUD's pointer.
func _inventory_tab() -> Control:
	var gear = demo.get("gear") if demo != null else null
	inventory = gear.inventory_page() if gear != null else InventoryPanel.new()
	inventory.on_waypoint = _hud_refresh
	var pilot = demo.get("pilot") if demo != null else null
	if pilot != null:
		# Issue #368: your ships: pick the primary, call her (the panel closes to watch).
		inventory.set_primary = pilot.set_primary
		inventory.call_ship = pilot.call_ship
		inventory.call_state = pilot.call_state
		inventory.on_called = close
	_refreshers.append(inventory.refresh)
	tabs.tab_changed.connect(func(i):
		if tabs.get_tab_control(i) == inventory:
			inventory.refresh())
	return inventory


func _hud_refresh() -> void:
	if demo != null and demo.get("objective_hud") != null:
		demo.objective_hud.refresh()


# ------------------------------------------------------------------ map

## The globe (GlobeView) with the places that stay put, and beside it the star
## system and its planets, a legend, and the waypoint's own buttons. Not a scroll
## page: the wheel zooms the globe. Clicking a planet opens its own map in the same
## spot (another planet's globe, the system's chart: SystemView, or the cruiser's
## side view: CruiserMapView), with a button back to the page's own view; a
## waypoint set there stays on that planet. The page opens on the planet you are
## on, or on the system's chart when you are out in space (_map_home_view).
func _map_tab() -> Control:
	var page := VBoxContainer.new()
	page.name = "Map"
	page.add_theme_constant_override("separation", 6)
	var h := HBoxContainer.new()
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 12)
	page.add_child(h)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(left)
	var head := HBoxContainer.new()
	left.add_child(head)
	_map_title = Label.new()
	_map_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_title.add_theme_font_size_override("font_size", 18)
	head.add_child(_map_title)
	_map_back = Button.new()
	_map_back.pressed.connect(func(): open_map(_map_home_view()))
	head.add_child(_map_back)
	globe = GlobeView.new()
	globe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	globe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	globe.town_zoom = float(GlobeMap.cfg().get("town_zoom", 14.0))
	globe.pin_clicked.connect(map_pick)
	globe.spot_clicked.connect(func(m): map_pick(GlobeMap.spot_pin(m)))
	left.add_child(globe)
	cruiser_view = CruiserMapView.new()
	cruiser_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cruiser_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cruiser_view.visible = false
	cruiser_view.place_clicked.connect(map_pick)
	left.add_child(cruiser_view)
	system_view = SystemView.new()
	system_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	system_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	system_view.visible = false
	system_view.body_clicked.connect(func(id: String):
		open_map("" if id == GameFlow.current_planet_id() else id))
	left.add_child(system_view)
	_no_globe = Label.new()
	_no_globe.text = GlobeMap.line("no_globe")
	_no_globe.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_no_globe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_no_globe.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_no_globe.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(_no_globe)
	_map_note = Label.new()
	_map_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_map_note.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	page.add_child(_map_note)

	var side_scroll := ScrollContainer.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_scroll.custom_minimum_size = Vector2(200, 0)
	h.add_child(side_scroll)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 6)
	side_scroll.add_child(side)
	_section(side, GlobeMap.line("off_planet"))
	_off_box = VBoxContainer.new()
	side.add_child(_off_box)
	_section(side, GlobeMap.line("legend"))
	side.add_child(_legend_row(GlobeMap.look().get("player", {}), GlobeMap.line("you"), Color(str(GlobeMap.look().get("player", {}).get("color", "#4dff88")))))
	side.add_child(_legend_row(GlobeMap.look().get("goal", {}), GlobeMap.line("goal"), Color(str(GlobeMap.look().get("goal", {}).get("color", "#ffd84a")))))
	var pins_look: Dictionary = GlobeMap.look().get("pins", {})
	for kind in ["port", "remnant_outpost", "village", "droid_merchant_outpost", "post", "camp", "wreck", "outpost", "spot"]:
		var legend := str(GlobeMap.kind_cfg(kind).get("legend", GlobeMap.kind_cfg(kind).get("label", kind)))
		side.add_child(_legend_row(pins_look.get(kind, {}), legend))
	var owners: Dictionary = GlobeMap.look().get("owners", {})
	for held in [["locals", "legend_held"], ["short", "legend_short"]]:
		side.add_child(_legend_row(pins_look.get("remnant_outpost", {}), GlobeMap.line(held[1]), Color(str(owners.get(held[0], "#5fd35f")))))
	side.add_child(_legend_row({ "shape": "ring" }, GlobeMap.line("legend_hold"), Color(str(owners.get("locals", "#5fd35f")))))
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(gap)
	_map_you = Button.new()
	_map_you.text = GlobeMap.line("centre_you")
	_map_you.pressed.connect(func():
		if _map_view == "system":
			if system_view.player != Vector3.INF:
				system_view.focus(system_view.player)
		elif globe.player != Vector2.INF:
			globe.focus(globe.player))
	side.add_child(_map_you)
	_map_home = Button.new()
	_map_home.text = GlobeMap.line("home")
	_map_home.pressed.connect(func():
		if _map_view == "system":
			system_view.reset()
			return
		globe.zoom = 1.0
		globe.focus(Vector2.ZERO))
	side.add_child(_map_home)
	var clear := Button.new()
	clear.text = GlobeMap.line("clear")
	clear.pressed.connect(func():
		GlobeMap.clear_waypoint()
		_refresh_map())
	side.add_child(clear)
	_refreshers.append(_refresh_map.bind(true))
	tabs.tab_changed.connect(func(i):
		if tabs.get_tab_control(i) == page:
			_refresh_map())          # a waypoint picked in the Ledger since
	return page


## One legend line: the pin's shape, drawn the way the globe draws it, and its name.
## `col` overrides the look's colour (you and the waypoint keep theirs off the pins).
func _legend_row(look: Dictionary, text: String, col := Color(0, 0, 0, 0)) -> HBoxContainer:
	var row := HBoxContainer.new()
	if col.a > 0.0:
		look = look.duplicate()
		look["color"] = col.to_html()
	row.add_child(_pin_icon(look))
	var l := Label.new()
	l.text = text
	row.add_child(l)
	return row


## A pin's shape (content/look/map.json) as a small control, for the legend and
## the off-planet list.
func _pin_icon(look: Dictionary, r := 5.0) -> Control:
	var icon := Control.new()
	icon.custom_minimum_size = Vector2.ONE * ceilf(r * 3.6)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.draw.connect(func(): GlobeView.draw_shape(icon, icon.size * 0.5, str(look.get("shape", "circle")),
		Color(str(look.get("color", "#f2e2b0"))), r))
	return icon


## Show `view` on the Map page: "" where you are, a planet's id, "cruiser", or
## "system" (the star system's chart, as a whole).
func open_map(view: String) -> void:
	_map_view = view
	globe.zoom = 1.0
	_refresh_map()
	if view == "system":
		system_view.reset()
	elif view != "":
		globe.focus(Vector2.ZERO)


## What the Map page opens on: the planet you are on, or the system's chart when
## you are out in space (flying above this planet's space_altitude).
func _map_home_view() -> String:
	var pilot = demo.get("pilot") if demo != null else null
	if pilot != null and bool(pilot.get("piloting")) and pilot.get("atmo") != null:
		if pilot.atmo.altitude() >= pilot.atmo.space_altitude:
			return "system"
	return ""


## The planet a waypoint picked on the Map page now goes on: the one shown (the
## cruiser hangs over this one).
func _map_planet() -> String:
	return _map_view if not _map_view in ["", "cruiser", "system"] else GameFlow.current_planet_id()


## Rebuild the map's pins and off-planet list from the scene (the town's stops
## and the planets in the sky only exist once it is built), you and the waypoint.
## `centre`: back to where you are, the globe turned to you (on opening the panel).
## Another planet is drawn from its data (GlobeMap.other_planet): its ball, its
## ground, its places, no town stops and no you.
func _refresh_map(centre := false) -> void:
	if centre:
		_map_view = _map_home_view()
	var here := GameFlow.current_planet_id()
	var live := _map_view == ""
	var on_cruiser := _map_view == "cruiser"
	var on_system := _map_view == "system"
	var other: Dictionary = {} if live or on_cruiser or on_system else GlobeMap.other_planet(_map_view)
	var sphere: PlanetSphere = PlanetSphere.current if live else other.get("sphere", null)
	var world: Dictionary = (demo.world if demo != null else {}) if live else other.get("planet", {}).get("world", {})
	var planet: Dictionary = (demo.planet if demo != null else {}) if live else other.get("planet", {})
	var shown := _map_planet()
	globe.visible = sphere != null and not on_cruiser and not on_system
	_no_globe.visible = sphere == null and not on_cruiser and not on_system
	cruiser_view.visible = on_cruiser
	system_view.visible = on_system
	var home_view := _map_home_view()
	_map_back.visible = _map_view != home_view
	_map_back.text = GlobeMap.line("back") % (GlobeMap.line("system") if home_view == "system" else GlobeMap.planet_name(here))
	_map_you.visible = live or on_system
	_map_home.visible = not on_cruiser
	_map_home.text = GlobeMap.line("system_reset" if on_system else "home")
	var w := WorldState.map_waypoint
	var w_here := str(w.get("planet", "")) == shown
	if on_cruiser:
		_refresh_cruiser(w_here)
	elif on_system:
		_map_title.text = GlobeMap.line("system_title")
		_refresh_system(centre)
	else:
		_map_title.text = GlobeMap.planet_name(shown)
	if sphere != null and not on_cruiser and not on_system:
		globe.radius_m = sphere.radius
		globe.town_zoom = float(GlobeMap.cfg().get("town_zoom", 14.0)) if live else INF
		var town: Array = GlobeMap.town_pins(demo.town, WorldState.current_town_id(), sphere.world_to_map) if demo != null and live else []
		globe.pins = GlobeMap.pins(world, planet, town)
		globe.shapes = GlobeMap.station_shapes(planet)
		var mesas: Array = DesertLandforms.mesa_spots if DesertLandforms.mesa_planet == shown else []
		globe.ground = GlobeTerrain.for_sphere("%s/%d" % [shown, mesas.size()], sphere, mesas)
		globe.terrain = GlobeMap.terrain_look(planet)
	globe.selected = GlobeMap.waypoint_id() if w_here and not str(w.get("target", "")).begins_with("cruiser") else ""
	var t := str(w.get("target", ""))
	globe.spot = Vector2(float(t.get_slice(":", 1).get_slice(",", 0)), float(t.get_slice(",", 1))) \
		if globe.selected == "spot" and t.begins_with("map:") else Vector2.INF
	_map_marks(sphere if live else null)
	if centre and globe.player != Vector2.INF:
		globe.focus(globe.player)
	globe.queue_redraw()
	# The star system's chart, then every planet in it (this one too: its own
	# map, where you are), then the cruiser when this world has one.
	var bodies: Array = []
	for b in GlobeMap.system():
		bodies.append({ "id": b.id, "name": GlobeMap.line("system_here") % b.label if str(b.id) == here else b.label })
	_off_planet = [{ "id": "system", "kind": "system", "label": GlobeMap.line("system"), "target": "system:" }] \
		+ GlobeMap.off_planet(bodies, demo.world if demo != null else {})
	for c in _off_box.get_children():
		c.queue_free()
	var pins_look: Dictionary = GlobeMap.look().get("pins", {})
	for o in _off_planet:
		var row := HBoxContainer.new()
		row.add_child(_pin_icon(pins_look.get(str(o.kind), {}), 7.0))
		var b := Button.new()
		b.text = str(o.label)
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var view := "cruiser" if str(o.kind) == "cruiser" else ("system" if str(o.kind) == "system" else str(o.target).get_slice(":", 1))
		if view == here:
			view = ""
		b.set_pressed_no_signal(view == _map_view)
		b.pressed.connect(func(): open_map(view))
		row.add_child(b)
		_off_box.add_child(row)
	if _off_planet.is_empty():
		var l := Label.new()
		l.text = "-"
		_off_box.add_child(l)
	var now := Objective.current()
	_map_note.text = (GlobeMap.line("waypoint") % str(now.text) if now.get("key", "") != "map" else str(now.text)) \
		if not now.is_empty() else GlobeMap.line("system_hint" if on_system else "none")


## The star system's chart: its planets, the cruiser, you and the other LAN
## players wherever you are (this scene's points carried into the system's frame),
## and the planet the pointer leads to. `centre`: the whole system, nothing moved.
func _refresh_system(centre: bool) -> void:
	var here := GameFlow.current_planet_id()
	system_view.bodies = GlobeMap.system()
	system_view.here = here
	system_view.cruiser = GlobeMap.system_cruiser()
	system_view.cruiser_label = str(GlobeMap.kind_cfg("cruiser").get("label", ""))
	system_view.player = Vector3.INF
	system_view.heading = Vector2.ZERO
	system_view.others = []
	var p = demo.get("_player") if demo != null else null
	if p is Node3D and is_instance_valid(p):
		var at: Vector3 = (p as Node3D).global_position
		system_view.player = GlobeMap.to_system(at, here)
		var cam := get_viewport().get_camera_3d()
		var fwd: Vector3 = -cam.global_basis.z if cam != null else -(p as Node3D).global_basis.z
		system_view.heading = Vector2(fwd.x, fwd.z)
		for o in NetSession.others():
			system_view.others.append({ "id": o.id, "pos": GlobeMap.to_system(o.pos, here), "name": o.name })
	var goal := ""
	var now := Objective.current()
	var t := str(now.get("target", ""))
	if t.begins_with("planet:"):
		goal = t.get_slice(":", 1)
	elif t.begins_with("cruiser"):
		goal = "cruiser"
	elif now.get("key", "") == "map":
		goal = str(WorldState.map_waypoint.get("planet", ""))
	elif not now.is_empty():
		goal = here
	system_view.goal = goal
	if centre or system_view.pan == Vector2.ZERO:
		system_view.reset()
	system_view.queue_redraw()


## Where you are and which way you look, the other LAN players (on foot or in a
## ship, wherever it is over this planet), and
## where the pointer is (the globe flashes the pin there, or marks the spot).
## Off-planet targets (another planet, the cruiser up there) are not on the globe.
func _map_marks(sphere: PlanetSphere) -> void:
	globe.player = Vector2.INF
	globe.heading = Vector2.ZERO
	globe.others = []
	globe.goal_pin = ""
	globe.goal = Vector2.INF
	if sphere == null or demo == null:
		return
	var p = demo.get("_player")
	if p is Node3D and is_instance_valid(p):
		var at: Vector3 = (p as Node3D).global_position
		globe.player = sphere.world_to_map(at)
		var cam := get_viewport().get_camera_3d()
		var fwd: Vector3 = -cam.global_basis.z if cam != null else -(p as Node3D).global_basis.z
		globe.heading = sphere.world_to_map(at + fwd * 25.0) - globe.player
		for o in NetSession.others():
			globe.others.append({ "id": o.id, "map": sphere.world_to_map(o.pos), "name": o.name })
	var now := Objective.current()
	if now.is_empty():
		return
	if now.get("key", "") == "map":
		globe.goal_pin = globe.selected if globe.selected != "spot" else ""
		return
	var target := str(now.get("target", ""))
	var hud = demo.get("objective_hud")
	if target == "" or target.begins_with("planet:") or target.begins_with("cruiser") or hud == null:
		return
	var pos: Vector3 = hud.where(target)
	if pos == Vector3.INF:
		return
	globe.goal = sphere.world_to_map(pos)


## The cruiser's side view: its places, the waypoint's, and you when aboard.
func _refresh_cruiser(w_here: bool) -> void:
	var c = demo.get("cruiser") if demo != null else null
	_map_title.text = GlobeMap.line("cruiser_title") % (c.label() if c != null else str(GlobeMap.kind_cfg("cruiser").get("label", "")))
	cruiser_view.pins = GlobeMap.cruiser_pins()
	cruiser_view.selected = GlobeMap.waypoint_id() if w_here else ""
	cruiser_view.player = Vector3.INF
	var p = demo.get("_player") if demo != null else null
	if c != null and p is Node3D and is_instance_valid(p) and c.aboard((p as Node3D).global_position):
		cruiser_view.player = c.to_local_point((p as Node3D).global_position)
	cruiser_view.queue_redraw()


## Set the waypoint on a pin (on the planet shown, or a place on the cruiser); the
## one already set clears.
func map_pick(pin: Dictionary) -> void:
	var planet := _map_planet()
	if GlobeMap.waypoint_id() == str(pin.id) and str(pin.id) != "spot" and str(WorldState.map_waypoint.get("planet", "")) == planet:
		GlobeMap.clear_waypoint()
	else:
		GlobeMap.set_waypoint(pin, planet)
	_refresh_map()
	_hud_refresh()


# ------------------------------------------------------------------ world

func _world_page(v: VBoxContainer) -> void:
	_section(v, "Time of day")
	# LAN: the host sets the time of day for everyone; a guest sees a line instead.
	var tod := VBoxContainer.new()
	v.add_child(tod)
	var hosts := Label.new()
	hosts.text = NetSession.label("lighting_host")
	v.add_child(hosts)
	_refreshers.append(func():
		tod.visible = not NetSession.is_guest()
		hosts.visible = NetSession.is_guest())
	_hour = HSlider.new()
	_hour.min_value = 0.0
	_hour.max_value = 24.0
	_hour.step = 0.25
	_hour.custom_minimum_size = Vector2(380, 0)
	_hour_label = Label.new()
	_hour_label.custom_minimum_size = Vector2(110, 0)
	# Issue #381: Auto moves the day on by itself (DayClock); a preset fixes it.
	# Moving the slider or pressing a preset sets the picker to where it lands.
	var day := OptionButton.new()
	for id in DayClock.PICKS:
		day.add_item(str(id).capitalize())
	day.item_selected.connect(func(i):
		var p := DayClock.pick(str(DayClock.PICKS[i]))
		if p != "":
			demo.set_preset(p)
		refresh())
	_row(tod, "Time of day", day)
	_hour.value_changed.connect(func(h):
		if DayClock.locked():
			return
		demo.set_hour(h)
		DayClock.set_by_hand(str(demo.preset))
		_show_hour())
	var hr := _row(tod, "Hour", _hour)
	hr.add_child(_hour_label)
	var presets := HBoxContainer.new()
	var buttons: Array[Button] = []
	for id in ["golden", "noon", "dusk"]:
		var btn := Button.new()
		btn.text = id.capitalize()
		btn.pressed.connect(func():
			if DayClock.locked():
				return
			demo.set_preset(id)
			DayClock.set_by_hand(id)
			_hour.set_value_no_signal(maxf(0.0, demo.look.hour_of(id)) if demo.look != null else 0.0)
			refresh())
		presets.add_child(btn)
		buttons.append(btn)
	_row(tod, "Preset", presets)
	var day_note := Label.new()
	day_note.text = "Story save: the chapters set the time of day; it is yours to pick once the cruiser is won."
	day_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	day_note.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	tod.add_child(day_note)
	_refreshers.append(func():
		var h: float = demo.look.hour if demo.look != null and demo.look.hour >= 0.0 else \
			(demo.look.hour_of(demo.preset) if demo.look != null else 0.0)
		_hour.set_value_no_signal(maxf(0.0, h))
		_show_hour()
		var locked := DayClock.locked()
		day.select(maxi(0, DayClock.PICKS.find(WorldState.day_pick)))
		day.disabled = locked
		_hour.editable = not locked
		for b in buttons:
			b.disabled = locked
		day_note.visible = locked)

	_section(v, "Game")
	_story_note(v, "credits are earned and the Remnant fleet always meets you in orbit.")
	var speed := OptionButton.new()
	for s in SPEEDS:
		speed.add_item("%sx" % str(s))
	speed.item_selected.connect(func(i): Engine.time_scale = SPEEDS[i])
	_row(v, "Game speed", speed)
	_refreshers.append(func(): speed.select(maxi(0, SPEEDS.find(Engine.time_scale))))
	var credits: SpinBox = _cheat(_spin(0, 99999, 10))
	credits.value_changed.connect(func(x): WorldState.credits = int(x))
	_row(v, "Credits", credits)
	_refreshers.append(func(): credits.set_value_no_signal(WorldState.credits))
	# Issue #46: whether flying out of the atmosphere starts the pad's space fight.
	var dogfight: CheckBox = _cheat(CheckBox.new())
	dogfight.text = "Flying to space starts a dogfight"
	dogfight.toggled.connect(func(on): GameFlow.set_space_dogfight(on))
	_row(v, "", dogfight)
	_refreshers.append(func(): dogfight.set_pressed_no_signal(GameFlow.space_dogfight()))
	# Issue #237: which saved layout the home town is built to (this run only).
	_section(v, "Town")
	var layout := OptionButton.new()
	var ids: Array = PlanetGen.layouts()
	ids.sort()
	for id in ids:
		layout.add_item(str(id))
	layout.item_selected.connect(func(i): set_town_layout(str(ids[i])))
	_row(v, "Home town layout", layout)
	_refreshers.append(func():
		var here := str(demo.planet.get("town", {}).get("layout", "")) if demo != null and "planet" in demo else ""
		layout.select(ids.find(here))
		layout.disabled = demo == null or str(demo.planet.get("id", "")) != PlanetGen.home_id())


## Issue #237: build the home town to `layout` (content/core/towns/) and reload it.
func set_town_layout(layout: String, reload := true) -> void:
	PlanetGen.set_layout(PlanetGen.home_id(), layout)
	if not reload or not is_inside_tree():
		return
	_save()
	visible = false
	get_tree().paused = false
	get_tree().reload_current_scene()


func _show_hour() -> void:
	var h := _hour.value
	var preset: String = demo.preset if demo != null else ""
	_hour_label.text = "%02d:%02d  %s" % [int(h) % 24, int(round(fmod(h, 1.0) * 60.0)) % 60, preset]


# ------------------------------------------------------------------ standing

func _standing_page(v: VBoxContainer) -> void:
	_section(v, "Factions  (-100 hostile .. 100 allied)")
	_story_note(v, "where you stand with each faction and person is earned in play. Shown here, not set.")
	for fac in WorldState.FACTIONS:
		var s: HSlider = _cheat(_slider(-100, 100))
		var lab := Label.new()
		lab.custom_minimum_size = Vector2(120, 0)
		var paint := func(x): lab.text = "%d  %s" % [int(x), WorldState.standing_label(int(x))]
		s.value_changed.connect(func(x):
			WorldState.standing[fac] = int(x)
			paint.call(x))
		_row(v, _faction_label(fac), s).add_child(lab)
		_refreshers.append(func():
			var x := int(WorldState.standing.get(fac, 0))
			s.set_value_no_signal(x)
			paint.call(x))
	var reset: Button = _cheat(Button.new())
	reset.text = "Reset to defaults"
	reset.pressed.connect(func():
		WorldState.standing = WorldState.DEFAULT_STANDING.duplicate()
		refresh())
	_row(v, "", reset)

	for who in _individuals():
		_individual(v, who.label, who.rel)


## Named people the player has a Relationship with. Only the cantina owner so far;
## add the next one here when an npc gets a Relationship.
func _individuals() -> Array:
	var out: Array = []
	if demo != null and demo.bar != null and demo.bar.brain != null:
		out.append({ "label": str(demo.bar.brain.card.get("name", "Cantina Owner")), "rel": demo.bar.brain.rel })
	return out


func _individual(v: VBoxContainer, label: String, rel: Relationship) -> void:
	_section(v, label + "  (trust 0 .. 100)")
	var trust: HSlider = _cheat(_slider(0, 100))
	var lab := Label.new()
	lab.custom_minimum_size = Vector2(120, 0)
	var paint := func(x): lab.text = "%d  %s" % [int(x), Relationship.tier_for(int(x))]
	trust.value_changed.connect(func(x):
		rel.trust = int(x)
		paint.call(x))
	_row(v, "Trust", trust).add_child(lab)
	var mood: OptionButton = _cheat(OptionButton.new())
	for m in MOODS:
		mood.add_item(m)
	mood.item_selected.connect(func(i): rel.mood = MOODS[i])
	_row(v, "Mood", mood)
	var tab: SpinBox = _cheat(_spin(0, 9999, 1))
	tab.value_changed.connect(func(x): rel.tab = int(x))
	var h := _row(v, "Tab owed", tab)
	var unban := Button.new()
	unban.text = "Clear ban"
	unban.pressed.connect(func():
		rel.banned_until = -1.0
		unban.disabled = true)
	h.add_child(unban)
	_refreshers.append(func():
		trust.set_value_no_signal(rel.trust)
		paint.call(rel.trust)
		mood.select(maxi(0, MOODS.find(rel.mood)))
		tab.set_value_no_signal(rel.tab)
		unban.disabled = WorldState.story_mode() or rel.banned_until <= WorldState.clock)


func _faction_label(id: String) -> String:
	var f := FileAccess.open("res://content/core/factions/%s.json" % id, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return str(d.get("label", id)) if d is Dictionary else id


# ------------------------------------------------------------------ player

func _player_page(v: VBoxContainer) -> void:
	_section(v, "Body")
	_story_note(v, "no god mode, free gear, teleports or guard x-ray; you live by your wits.")
	var god: CheckBox = _cheat(CheckBox.new())
	god.text = "God mode (no damage)"
	god.toggled.connect(func(on):
		_god = on
		var p = _player()
		if p != null and not on:
			p.invulnerable_left = 0.0)
	v.add_child(god)
	var heal: Button = _cheat(Button.new())
	heal.text = "Heal / revive"
	heal.pressed.connect(func():
		var p = _player()
		if p != null:
			p.revive(0.0))
	_row(v, "", heal)

	_section(v, "Jetpack")
	var give: Button = _cheat(Button.new())
	give.text = "Give and wear jetpack"
	give.pressed.connect(_give_jetpack)
	_row(v, "", give)
	var fuel: CheckBox = _cheat(CheckBox.new())
	fuel.text = "Endless fuel"
	fuel.toggled.connect(func(on): _endless_fuel = on)
	v.add_child(fuel)

	_section(v, "Teleport")
	var where: OptionButton = _cheat(OptionButton.new())
	var ids: Array = []
	if demo != null:
		for m in demo.town.markers():
			if str(m.role) in ["spawn", "waypoint", "interact"]:
				ids.append(str(m.id))
				where.add_item(str(m.id).replace("_", " "))
	var go: Button = _cheat(Button.new())
	go.text = "Go"
	go.pressed.connect(func():
		if where.selected >= 0:
			teleport(ids[where.selected]))
	_row(v, "Marker", where).add_child(go)

	_section(v, "Debug")
	var npc_dbg: CheckBox = _cheat(CheckBox.new())
	npc_dbg.text = "Guard senses (F4)"
	npc_dbg.toggled.connect(func(on): NpcBody.show_debug = on)
	v.add_child(npc_dbg)
	_refreshers.append(func():
		god.set_pressed_no_signal(_god)
		fuel.set_pressed_no_signal(_endless_fuel)
		npc_dbg.set_pressed_no_signal(NpcBody.show_debug))


func _player():
	return demo._player if demo != null else null


# ------------------------------------------------------------------ character

## The builder saves each pick itself; the player's body wears it at once.
func _character_page(v: VBoxContainer) -> void:
	_section(v, "Outfit")
	_story_note(v, "you play the smuggler; every piece and colour of their own kit is yours to pick.")
	builder = CharacterBuilder.new()
	builder.outfit_changed.connect(func(o):
		var a = _avatar()
		if a != null:
			a.set_outfit(o))
	v.add_child(builder)
	_refreshers.append(func():
		var a = _avatar()
		builder.show_outfit(a.worn_outfit() if a != null else PlayerOutfit.load_outfit()))


func _avatar() -> PlayerAvatar:
	return demo.player_kit.avatar if demo != null and demo.player_kit != null else null


func _give_jetpack() -> void:
	if demo == null or demo.gear == null:
		return
	var item: Dictionary = demo.gear.content.get_item("jetpack")
	var inv := WorldState.inventory
	if not inv.has("jetpack"):
		inv.add("jetpack")
	var on := inv.in_slot(str(item.get("slot", "")))
	if on != "" and on != "jetpack":
		inv.detach(on)
	inv.attach("jetpack", item)
	demo.gear.sync_gear()


## Stand on a town marker (not while flying, nor in a story save).
func teleport(marker_id: String) -> bool:
	var p = _player()
	if p == null or p.piloting or WorldState.story_mode() or demo.town.get_marker(marker_id).is_empty():
		return false
	p.global_position = demo.town.marker_pos(marker_id) + Vector3(0, 0.05, 0)
	if p.has_method("align_to_ground"):
		p.call("align_to_ground", true)
	else:
		p.velocity = Vector3.ZERO
	return true


# ------------------------------------------------------------------ flags

func _flags_page(v: VBoxContainer) -> void:
	_section(v, "World flags")
	var note := Label.new()
	note.text = "World flags the content reads (rumors, jobs, moods). Changes apply at once."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	_story_note(v, "the story sets these as you play. Shown here, not set.")
	_flags_box = VBoxContainer.new()
	v.add_child(_flags_box)
	_flag_new = _cheat(LineEdit.new())
	_flag_new.placeholder_text = "custom_flag"
	_flag_new.custom_minimum_size = Vector2(260, 0)
	var add: Button = _cheat(Button.new())
	add.text = "Set"
	add.pressed.connect(func():
		var n := _flag_new.text.strip_edges()
		if n != "":
			WorldState.set_flag(n)
			_flag_new.text = ""
			_rebuild_flags())
	_row(v, "Add", _flag_new).add_child(add)


func _rebuild_flags() -> void:
	for c in _flags_box.get_children():
		c.queue_free()
	for flag in known_flags():
		var cb := CheckBox.new()
		cb.text = flag
		cb.button_pressed = WorldState.has_flag(flag)
		cb.disabled = WorldState.story_mode()   # made fresh each refresh, so not a _cheat
		cb.toggled.connect(func(on): WorldState.set_flag(flag, on))
		_flags_box.add_child(cb)


## Flags set now, plus every flag a rumor, job or mood rule asks about. Sorted.
func known_flags() -> Array:
	var seen := {}
	for f in WorldState.flags:
		seen[str(f)] = true
	var reqs: Array = []
	for r in WorldState.all_rumors():
		reqs.append(r.get("requires", {}))
	for j in WorldState.board():
		reqs.append(j.get("requires", {}))
	for req in reqs:
		for f in req.get("flags", []) + req.get("not_flags", []):
			seen[str(f)] = true
	if demo != null and demo.bar != null and demo.bar.brain != null:
		for r in demo.bar.brain.card.get("mood_rules", []):
			for f in r.get("if_flags", []):
				seen[str(f)] = true
	var out := seen.keys()
	out.sort()
	return out


# ------------------------------------------------------------------ story (issue #64)

func _story_page(v: VBoxContainer) -> void:
	_section(v, "Main story")
	var now := Label.new()
	now.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(now)
	var pick := OptionButton.new()
	for id in Story.chapter_ids():
		pick.add_item(str(id).replace("_", " "))
	var go := Button.new()
	go.pressed.connect(func():
		if pick.selected >= 0:
			skip_chapter(str(Story.chapter_ids()[pick.selected])))
	_row(v, "Chapter", pick).add_child(go)
	_story_note(v, "chapters are there to be played, but if you are truly stuck you can skip ahead (never back).")
	skip_confirm = ConfirmationDialog.new()
	skip_confirm.title = "Skip ahead?"
	skip_confirm.dialog_text = STUCK_WARNING
	skip_confirm.dialog_autowrap = true
	skip_confirm.min_size = Vector2i(420, 0)
	skip_confirm.ok_button_text = "Yes"
	skip_confirm.cancel_button_text = "No"
	skip_confirm.confirmed.connect(func():
		Story.skip_to(_skip_to)
		var t := DayClock.story_due()     # issue #381: open on the chapter's time
		if t != "":
			demo.set_preset(t)
		refresh())
	v.add_child(skip_confirm)
	_refreshers.append(func():
		var b := WorldState.bounty
		now.text = "Now: %s save, %s%s" % ["story" if WorldState.story_mode() else "free roam", Story.chapter().replace("_", " "),
			("   ·   bounty on %s (%s)" % [b.name, b.state]) if str(b.get("state", "")) in ["out", "dead"] else ""]
		var at := Story.index(Story.chapter())
		pick.select(maxi(0, at))
		for i in pick.item_count:
			pick.set_item_disabled(i, WorldState.story_mode() and (i <= at or not Story.applies(Story.chapters()[i])))
		go.text = "Skip ahead" if WorldState.story_mode() else "Skip to it")


## The story save and the free roam save, side by side (SaveSlots): the one being
## played, and Play on the other (from where it was left, or a new game when it
## has none).
func _saves_page(v: VBoxContainer) -> void:
	_section(v, "Saves")
	for m in [[WorldState.STORY, "Story"], [WorldState.FREEPLAY, "Free roam"]]:
		var row := HBoxContainer.new()
		var about := Label.new()
		about.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var play := Button.new()
		play.pressed.connect(func(): switch_save(m[0]))
		row.add_child(about)
		row.add_child(play)
		_row(v, m[1], row)
		_refreshers.append(func():
			var here: bool = SaveSlots.playing() == m[0]
			var s := SaveSlots.summary(m[0])
			if here:
				about.text = "Playing now: %s, %d credits" % [Story.chapter().replace("_", " "), WorldState.credits]
			elif bool(s.exists):
				about.text = "%s, %d credits" % [str(s.chapter).replace("_", " "), int(s.credits)]
			else:
				about.text = "None yet: Play starts one"
			play.text = "Playing" if here else "Play"
			play.disabled = here)
	var note := Label.new()
	note.text = "Each save keeps its own world, gear, ships, standing, names and outfit. This one is saved before the other opens; the town reloads."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)


# ------------------------------------------------------------------ LAN (issue #401)

var _lan_refresh: Callable = Callable()


## Play with friends on the same wifi: your name (remembered), Host, or the host's
## address and Join, Leave, and who is here. Free roam only: hosting from a story
## save opens the free roam save first.
func _lan_page(v: VBoxContainer) -> void:
	_anchors["LAN"] = _section(v, "Play with friends (LAN)")
	var name_box := LineEdit.new()
	name_box.text = NetSession.saved_name()
	name_box.placeholder_text = "Your name over your head"
	name_box.max_length = int(NetSession.n("name_max", 16))
	name_box.custom_minimum_size = Vector2(260, 0)
	name_box.text_changed.connect(func(t): NetSession.save_name(t))
	_row(v, "Your name", name_box)
	var host := Button.new()
	host.text = "Host a game"
	_row(v, "", host)
	var addr := LineEdit.new()
	addr.text = NetSession.saved_address()
	addr.placeholder_text = "Host's address, e.g. 192.168.1.20"
	addr.custom_minimum_size = Vector2(260, 0)
	var join := Button.new()
	join.text = "Join"
	var join_row := HBoxContainer.new()
	join_row.add_child(addr)
	join_row.add_child(join)
	_row(v, "Join a friend", join_row)
	var leave := Button.new()
	leave.text = "Leave"
	_row(v, "", leave)
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(status)
	var said := [""]                 # a refusal or a "type your name" stays until the next click
	host.pressed.connect(func():
		said[0] = lan_host(name_box.text)
		_lan_refresh.call())
	var go_join := func():
		said[0] = lan_join(addr.text, name_box.text)
		_lan_refresh.call()
	join.pressed.connect(go_join)
	addr.text_submitted.connect(func(_t): go_join.call())
	leave.pressed.connect(func():
		said[0] = ""
		NetSession.leave()
		_lan_refresh.call())
	_lan_refresh = func():
		var on := NetSession.active()
		host.disabled = on
		join.disabled = on
		addr.editable = not on
		name_box.editable = not on
		leave.disabled = not on
		status.text = NetSession.status_line() if on or said[0] == "" else said[0]
	_refreshers.append(_lan_refresh)


## Host a LAN game as `who`. Returns "" or why not. From a story save the free roam
## save opens first (the town reloads; the session carries on).
func lan_host(who: String) -> String:
	if NetSession.clean_name(who) == "":
		return NetSession.label("need_name")
	NetSession.save_name(who)
	if NetSession.host(get_tree(), who, _worn()) != OK:
		var line := NetSession.label("cannot_host")
		return line % NetSession.port() if line.contains("%d") else line
	if SaveSlots.playing() != WorldState.FREEPLAY:
		switch_save(WorldState.FREEPLAY)
	return ""


## Join the LAN game at `address` as `who`. Returns "" or why not; the host's answer
## comes later (lan_arrive, or a toast saying no).
func lan_join(address: String, who: String) -> String:
	if NetSession.clean_name(who) == "":
		return NetSession.label("need_name")
	if address.strip_edges() == "":
		return NetSession.label("need_address")
	NetSession.save_name(who)
	NetSession.save_address(address)
	if NetSession.join(get_tree(), address, who, _worn()) != OK:
		var line := NetSession.label("no_answer")
		return line % address if line.contains("%s") else line
	return ""


## The outfit the others see you in.
func _worn() -> Dictionary:
	var a := _avatar()
	return a.worn_outfit() if a != null else PlayerOutfit.load_outfit()


## Issue #401: the host let you in. This game is saved, then your free roam save
## opens on the host's planet with you beside T-89: no opening landing, no hello
## and tutorial from him. `reload` false: just the state (tests).
func lan_arrive(planet_id: String, reload := true) -> void:
	var persist := _persists()
	_save_left()
	_leave()
	SaveSlots.enter(WorldState.FREEPLAY, persist)
	GameFlow.resumed = true                 # the host's planet, not where the save was left
	GameFlow.planet_id = "" if planet_id == PlanetGen.home_id() or PlanetGen.build(planet_id).is_empty() else planet_id
	WorldState.set_flag(WorldState.FREE_OPENING, false)
	ShipSalesman.greeted = true
	NetSession.guest_spawn = true
	_reload(reload)


## Issue #64: start again, as a story or as free roam.
func _new_game_page(v: VBoxContainer) -> void:
	_section(v, "New game")
	var note := Label.new()
	note.text = "Starts that save again as on a first play: credits, gear, droids, ships, every flag, faction standing and what each character thinks of you. Its names are kept. The other save is not touched. The town reloads.\nStory: the story from the start, every faction neutral, the pistol only, locked to the smuggler.\nFree roam: drops and bounties on repeat, any character."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	var row := HBoxContainer.new()
	for m in [[WorldState.STORY, "New story game"], [WorldState.FREEPLAY, "New free roam game"]]:
		var b := Button.new()
		b.text = m[1]
		b.pressed.connect(func(): new_game(m[0]))
		row.add_child(b)
	_row(v, "", row)


## Move the main story to chapter `id`. Free roam: at once, any chapter. A story
## save: only ahead, and only after the player says yes to STUCK_WARNING (the
## characters may have a hint first). Returns false when it will not skip.
func skip_chapter(id: String) -> bool:
	if Story.index(id) < 0:
		return false
	if not WorldState.story_mode():
		Story.skip_to(id)
		refresh()
		return true
	if Story.index(id) <= Story.index(Story.chapter()) or not Story.applies(Story.chapter_cfg(id)):
		return false
	_skip_to = id
	skip_confirm.popup_centered()
	return true


## Issue #64: back to the start, as on a first play. Everything the player has or
## has done goes (WorldState: credits, gear, droids, the bought ship, flags,
## standing, the story), every character's opinion of them goes back to a
## stranger's, T-89 says hello again; that save's names stay. Issue #200: in
## `mode` (WorldState.STORY or FREEPLAY), in that mode's own save (SaveSlots): a
## new story game never touches the free roam save, nor the other way round. The
## game being left is saved first, then the town is built again from scratch, as
## on a launch (SaveSlots.fresh_launch). `reload` false: just the state (tests).
func new_game(mode: String, reload := true) -> void:
	var persist := _persists()
	if persist and mode != SaveSlots.current():
		_save_left()
	var kept := WorldState.names if mode == WorldState.mode else (SaveSlots.names_in(mode) if persist else NameBook.new())
	_leave()
	SaveSlots.start(mode, kept, persist)
	if demo != null and demo.bar != null:
		for s in demo.bar.spots:
			s.brain.rel = Relationship.new()
	_reload(reload)


## Play `mode`'s save instead of this one: this one is saved, then the other opens
## from where it was left (a new game there when it has none). `reload` false:
## just the state (tests).
func switch_save(mode: String, reload := true) -> void:
	var persist := _persists()
	if persist and mode == SaveSlots.current():
		return
	_save_left()
	_leave()
	SaveSlots.enter(mode, persist)
	_reload(reload)


## This town saves to disk (not a test's or a trace's).
func _persists() -> bool:
	return demo != null and demo.bar != null and demo.bar.autosave


## Save the game being left in its slot, unless it never started (a first launch's
## menu is still up: there is nothing to keep).
func _save_left() -> void:
	if demo != null and demo.bar != null and not demo.bar.fresh:
		_save()


## The town being left must not save again on its way out: by then WorldState is
## the next game's.
func _leave() -> void:
	if demo != null and demo.bar != null:
		demo.bar.autosave = false


func _reload(reload: bool) -> void:
	if not reload or not is_inside_tree():
		return
	visible = false
	get_tree().paused = false
	get_tree().reload_current_scene()


# ------------------------------------------------------------------ save

func _save() -> void:
	if demo != null and demo.bar != null:
		demo.bar._save_memory()


# ------------------------------------------------------------------ LLM (issue #80)

## The AI brain settings (they were a separate F10 panel): where the cantina
## owner's brain runs, its URLs, models and key, Test and Save.
func _llm_page(v: VBoxContainer) -> void:
	_anchors["LLM"] = _section(v, "AI characters' brain  (F10 jumps here)")
	var bar = demo.bar if demo != null and "bar" in demo else null
	if bar != null and bar.settings != null:
		bar.settings.embed_into(v, self)
		_refreshers.append(func(): bar.settings._load())
	else:
		var l := Label.new()
		l.text = "No AI characters in this scene."
		v.add_child(l)


# ------------------------------------------------------------------ HUD (issue #52)

## Every bound control (project.godot), by when it applies. Keep it in step with the input map.
const KEYS := [
	["On foot", [
		["W A S D", "Walk (tap for steps, hold to run); arrows too"],
		["Space", "Jump (hold for the jetpack)"],
		["Right Shift", "Sprint: faster, gun down, spends stamina"],
		["C", "Crouch"],
		["V", "First / third person (mouse middle button too)"],
		["E", "Interact: talk, board, ride, pick up"],
		["G", "Put on / take off your gear"],
		["Z", "Rest, at a tent"],
		["I", "What you carry, the job log, and Call (your ship flies to you)"],
	]],
	["Weapons", [
		["1 / 2 / 3 / 4", "Blaster / rifle / energy sword / sniper rifle (same key again holsters)"],
		["Q / H", "Last weapon / holster"],
		["Tab or wheel", "Next weapon"],
		["Left mouse", "Fire or swing"],
		["Right mouse", "Aim (blaster) or block (sword), toggles; with the sniper a second click zooms in twice as far"],
		["R", "Reload"],
	]],
	["Flying", [
		["W / S", "Pitch (W pushes the nose down); the mouse steers too"],
		["A / D", "Turn"],
		["Q / E", "Roll"],
		["R / F", "Throttle up / down"],
		["Shift", "Boost"],
		["C", "Take off, and land on what is below"],
		["Z", "Land in the bay when near it (again to take her back)"],
		["Space or left mouse", "Guns"],
		["X or right mouse", "Seeker missile, once locked"],
		["T", "Next target"],
		["J", "Radio: next station, then off"],
		["V", "Chase / cockpit view"],
		["Hold B", "Eject, in the air"],
		["E", "Get out, once landed"],
	]],
	["Everywhere", [
		["F1", "Info: planet, town, time, credits, standing"],
		["F3", "AI debug overlay"],
		["F4", "Guard debug (what each guard sees and hears; free roam only)"],
		["F10", "AI model settings: the AI brain under Options here (Shift+F10: next model)"],
		["F11", "These settings"],
		["M", "The map: click a place for a waypoint"],
		["L", "Cycle the lighting"],
		["Esc", "Free the mouse, close a panel"],
	]],
]


func _hud_page(v: VBoxContainer) -> void:
	_section(v, "HUD colour")
	var grid := GridContainer.new()
	grid.columns = 3
	for name in RetroUI.PRESETS:
		var b := Button.new()
		b.text = name
		b.custom_minimum_size = Vector2(190, 0)
		b.pressed.connect(func(): _set_hud_color(RetroUI.PRESETS[name]))
		grid.add_child(b)
	v.add_child(grid)
	var pick := ColorPickerButton.new()
	pick.custom_minimum_size = Vector2(120, 30)
	pick.edit_alpha = false
	pick.color = RetroUI.accent
	pick.color_changed.connect(_set_hud_color)
	_row(v, "Your own", pick)
	_refreshers.append(func(): pick.color = RetroUI.accent)
	# Issue #71: one number sizes every UI element; saved per machine.
	_section(v, "Text size")
	RetroUI.load_settings()
	var ui := RetroUI.ui()
	var size := _slider(int(round(float(ui.get("min", 0.75)) * 100.0)), int(round(float(ui.get("max", 2.0)) * 100.0)))
	size.step = float(ui.get("step", 0.05)) * 100.0
	size.value = roundf(RetroUI.text_scale * 100.0)
	var shown := Label.new()
	shown.text = "%d%%" % int(size.value)
	size.drag_ended.connect(func(_changed): RetroUI.set_text_scale(get_tree(), size.value / 100.0))
	size.value_changed.connect(func(x):
		shown.text = "%d%%" % int(x)
		if not size.has_focus():
			RetroUI.set_text_scale(get_tree(), x / 100.0))
	var row := _row(v, "Size", size)
	row.add_child(shown)
	var reset := Button.new()
	reset.text = "Default"
	reset.pressed.connect(func(): size.value = roundf(float(ui.get("text_scale", 1.75)) * 100.0); RetroUI.set_text_scale(get_tree(), size.value / 100.0))
	row.add_child(reset)
	_refreshers.append(func(): size.set_value_no_signal(roundf(RetroUI.text_scale * 100.0)); shown.text = "%d%%" % int(size.value))


func _keys_page(v: VBoxContainer) -> void:
	_section(v, "Controls")
	for group in KEYS:
		var head := Label.new()
		head.text = group[0]
		head.add_theme_color_override("font_color", Color("#d8b878"))
		v.add_child(head)
		for k in group[1]:
			var l := Label.new()
			l.text = "[%s]" % k[0]
			l.custom_minimum_size = Vector2(150, 0)
			var h := _row(v, "", l)
			h.get_child(0).custom_minimum_size = Vector2(0, 0)
			var what := Label.new()
			what.text = k[1]
			h.add_child(what)


## Issue #16: the music and the effects each get a volume, saved per machine.
func _sound_page(v: VBoxContainer) -> void:
	_section(v, "Volume  (0 .. 100)")
	for bus in [[Sound.MUSIC_BUS, "Music"], [Sound.SFX_BUS, "Effects"]]:
		var s := _slider(0, 100)
		s.value = roundf(Sound.volume(bus[0]) * 100.0)
		s.value_changed.connect(func(x): Sound.set_volume(bus[0], x / 100.0))
		_row(v, bus[1], s)
		_refreshers.append(func(): s.set_value_no_signal(roundf(Sound.volume(bus[0]) * 100.0)))


## Lower it if near things (the hands in first person, a ship's interior) look far
## too bright: some Windows GPUs overdo the bounce light (LookEnvironment.indirect_level).
func _graphics_page(v: VBoxContainer) -> void:
	_section(v, "Graphics")
	var s := _slider(0, 100)
	s.value = roundf(LookEnvironment.indirect_level() * 100.0)
	s.value_changed.connect(func(x):
		if demo != null and demo.look != null:
			demo.look.set_indirect(x / 100.0)
		else:
			LookEnvironment.save_indirect_level(x / 100.0))
	_row(v, "Indirect light", s)
	var note := Label.new()
	note.text = "How strong the bounce light and the sky's fill are."
	note.add_theme_font_size_override("font_size", 12)
	v.add_child(note)
	_refreshers.append(func(): s.set_value_no_signal(roundf(LookEnvironment.indirect_level() * 100.0)))
	# Issue #534: the temporal upscaler is the anti-aliasing; off falls back to FXAA
	# at full size, for a machine where it smears fast things.
	var taa := CheckBox.new()
	taa.set_pressed_no_signal(LookEnvironment.taa())
	taa.toggled.connect(func(on):
		if demo != null and demo.look != null:
			demo.look.set_taa(on)
		else:
			LookEnvironment.save_taa(on))
	_row(v, "Temporal anti-aliasing", taa)
	var taa_note := Label.new()
	taa_note.text = "Smooth edges and a faster frame. Turn off if bolts or the sword leave trails."
	taa_note.add_theme_font_size_override("font_size", 12)
	v.add_child(taa_note)
	_refreshers.append(func(): taa.set_pressed_no_signal(LookEnvironment.taa()))
	# For slower PCs (LookEnvironment.low_graphics): what it turns off is in time_of_day.json.
	# Its pieces have a checkbox each below it, to try one at a time.
	var low := CheckBox.new()
	var boxes := {}
	var sync := func():
		low.set_pressed_no_signal(LookEnvironment.low_graphics())
		for id in boxes:
			boxes[id].set_pressed_no_signal(LookEnvironment.cut(id))
	var show_now := func():
		if demo != null and demo.look != null:
			demo.look.apply_low()
			if demo.draw_distance != null:
				demo.draw_distance.apply_low_graphics()
	low.toggled.connect(func(on):
		LookEnvironment.save_low_graphics(on)
		show_now.call()
		sync.call())
	_row(v, "Low graphics", low)
	var low_note := Label.new()
	low_note.text = "Faster on slower PCs. The same, one piece at a time (to find what causes a glare):"
	low_note.add_theme_font_size_override("font_size", 12)
	v.add_child(low_note)
	for p in LookEnvironment.pieces():
		var id := str(p.id)
		var b := CheckBox.new()
		b.toggled.connect(func(on):
			LookEnvironment.save_cut(id, on)
			show_now.call()
			sync.call())
		boxes[id] = b
		_row(v, "    " + str(p.get("label", id)), b)
	sync.call()
	_refreshers.append(sync)


func _set_hud_color(c: Color) -> void:
	if RetroSkin.current != null:
		RetroSkin.current.set_color(c)
	else:
		RetroUI.accent = c
		RetroUI.save_settings()


# ------------------------------------------------------------------ layout

## A scrolling page in the tab container; returns the column to fill.
func _tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	scroll.add_child(v)
	return v


## A section's heading (upper case, gold). Returns it (open_tab can scroll to it).
func _section(v: VBoxContainer, text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_color_override("font_color", Color("#d8b878"))
	v.add_child(l)
	return l


func _row(v: VBoxContainer, label: String, c: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(160, 0)
	h.add_child(l)
	h.add_child(c)
	v.add_child(h)
	return h


func _slider(lo: float, hi: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1
	s.custom_minimum_size = Vector2(300, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return s


func _spin(lo: float, hi: float, step: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	return s
