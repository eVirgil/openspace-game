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
##             (issue #16), the AI characters' brain (issue #80) and every key
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

## The globe (GlobeView) with the places that stay put, and beside it the places
## off planet, a legend, and the waypoint's own buttons. Not a scroll page: the
## wheel zooms the globe.
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
	globe = GlobeView.new()
	globe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	globe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	globe.town_zoom = float(GlobeMap.cfg().get("town_zoom", 14.0))
	globe.pin_clicked.connect(map_pick)
	globe.spot_clicked.connect(func(m): map_pick(GlobeMap.spot_pin(m)))
	left.add_child(globe)
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
	for kind in ["port", "remnant_outpost", "droid_merchant_outpost", "post", "camp", "wreck", "outpost", "spot"]:
		var legend := str(GlobeMap.kind_cfg(kind).get("legend", GlobeMap.kind_cfg(kind).get("label", kind)))
		side.add_child(_legend_row(pins_look.get(kind, {}), legend))
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(gap)
	var you := Button.new()
	you.text = GlobeMap.line("centre_you")
	you.pressed.connect(func():
		if globe.player != Vector2.INF:
			globe.focus(globe.player))
	side.add_child(you)
	var home := Button.new()
	home.text = GlobeMap.line("home")
	home.pressed.connect(func():
		globe.zoom = 1.0
		globe.focus(Vector2.ZERO))
	side.add_child(home)
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


## Rebuild the map's pins and off-planet list from the scene (the town's stops
## and the planets in the sky only exist once it is built), you and the waypoint.
## `centre`: turn the globe to you (on opening the panel).
func _refresh_map(centre := false) -> void:
	var sphere := PlanetSphere.current
	var world: Dictionary = demo.world if demo != null else {}
	var planet: Dictionary = demo.planet if demo != null else {}
	globe.visible = sphere != null
	_no_globe.visible = sphere == null
	if sphere != null:
		globe.radius_m = sphere.radius
		var town: Array = GlobeMap.town_pins(demo.town, WorldState.current_town_id(), sphere.world_to_map) if demo != null else []
		globe.pins = GlobeMap.pins(world, planet, town)
	var w := WorldState.map_waypoint
	globe.selected = GlobeMap.waypoint_id() if str(w.get("planet", "")) == GameFlow.current_planet_id() else ""
	var t := str(w.get("target", ""))
	globe.spot = Vector2(float(t.get_slice(":", 1).get_slice(",", 0)), float(t.get_slice(",", 1))) \
		if globe.selected == "spot" and t.begins_with("map:") else Vector2.INF
	_map_marks(sphere)
	if centre and globe.player != Vector2.INF:
		globe.focus(globe.player)
	globe.queue_redraw()
	var travel = demo.pilot.travel if demo != null and demo.get("pilot") != null and demo.pilot.travel != null else null
	_off_planet = GlobeMap.off_planet(travel.bodies if travel != null else [], world)
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
		b.set_pressed_no_signal(GlobeMap.waypoint_id() == str(o.id))
		b.pressed.connect(func(): map_pick(o))
		row.add_child(b)
		_off_box.add_child(row)
	if _off_planet.is_empty():
		var l := Label.new()
		l.text = "-"
		_off_box.add_child(l)
	var now := Objective.current()
	_map_note.text = (GlobeMap.line("waypoint") % str(now.text) if now.get("key", "") != "map" else str(now.text)) \
		if not now.is_empty() else GlobeMap.line("none")


## Where you are and which way you look, and where the pointer is (the globe
## flashes the pin there, or marks the spot). Off-planet targets (another planet,
## the cruiser up there) are not on the globe.
func _map_marks(sphere: PlanetSphere) -> void:
	globe.player = Vector2.INF
	globe.heading = Vector2.ZERO
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


## Set the waypoint on a pin or an off-planet place; the one already set clears.
func map_pick(pin: Dictionary) -> void:
	if GlobeMap.waypoint_id() == str(pin.id) and str(pin.id) != "spot":
		GlobeMap.clear_waypoint()
	else:
		GlobeMap.set_waypoint(pin, GameFlow.current_planet_id())
	_refresh_map()
	_hud_refresh()


# ------------------------------------------------------------------ world

func _world_page(v: VBoxContainer) -> void:
	_section(v, "Time of day")
	_hour = HSlider.new()
	_hour.min_value = 0.0
	_hour.max_value = 24.0
	_hour.step = 0.25
	_hour.custom_minimum_size = Vector2(380, 0)
	_hour_label = Label.new()
	_hour_label.custom_minimum_size = Vector2(110, 0)
	_hour.value_changed.connect(func(h):
		demo.set_hour(h)
		_show_hour())
	var hr := _row(v, "Hour", _hour)
	hr.add_child(_hour_label)
	var presets := HBoxContainer.new()
	for id in ["golden", "noon", "dusk"]:
		var btn := Button.new()
		btn.text = id.capitalize()
		btn.pressed.connect(func():
			demo.set_preset(id)
			_hour.set_value_no_signal(maxf(0.0, demo.look.hour_of(id)) if demo.look != null else 0.0)
			_show_hour())
		presets.add_child(btn)
	_row(v, "Preset", presets)
	_refreshers.append(func():
		var h: float = demo.look.hour if demo.look != null and demo.look.hour >= 0.0 else \
			(demo.look.hour_of(demo.preset) if demo.look != null else 0.0)
		_hour.set_value_no_signal(maxf(0.0, h))
		_show_hour())

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

const KEYS := [
	["F1", "Info: planet, town, time, credits, standing"],
	["F3", "AI debug overlay"],
	["F4", "Guard debug (what each guard sees and hears; free roam only)"],
	["F10", "AI model settings: the AI brain under Options here (Shift+F10: next model)"],
	["F11", "These settings"],
	["M", "The map: click a place for a waypoint"],
	["I", "What you carry and the job log"],
	["E", "Interact: talk, board, ride, pick up"],
	["L", "Cycle the lighting"],
	["V", "First / third person"],
	["Esc", "Free the mouse, close a panel"],
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
	_section(v, "Keys")
	for k in KEYS:
		var l := Label.new()
		l.text = "[%s]" % k[0]
		l.custom_minimum_size = Vector2(70, 0)
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
