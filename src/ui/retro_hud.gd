class_name RetroHud
extends CanvasLayer
## Issue #52: the 80s HUD frame. A banner across the top (planet, town, clock,
## credits) and a footer along the bottom (health, stamina, jetpack fuel, what you
## are doing). Click either, or press F1, for the info screen: where you are, the
## time, money, speeders, standing with every faction and the latest news.
##
## It only reads: WorldState, the player and the town's look. Styled by RetroSkin.

const REFRESH := 0.25                 ## seconds between redraws of the numbers

var demo                              ## town_demo.gd
var banner: PanelContainer
var footer: PanelContainer
var info: PanelContainer
var _place: Label
var _clock: Label
var _money: Label
var _vitals: Label
var _mode: Label
var _info_text: Label
var _left := 0.0


func _ready() -> void:
	layer = 4
	process_mode = Node.PROCESS_MODE_ALWAYS
	banner = _strip(Control.PRESET_TOP_WIDE)
	_place = _cell(banner, HORIZONTAL_ALIGNMENT_LEFT)
	_clock = _cell(banner, HORIZONTAL_ALIGNMENT_CENTER)
	_money = _cell(banner, HORIZONTAL_ALIGNMENT_RIGHT)
	footer = _strip(Control.PRESET_BOTTOM_WIDE)
	_vitals = _cell(footer, HORIZONTAL_ALIGNMENT_LEFT)
	_mode = _cell(footer, HORIZONTAL_ALIGNMENT_RIGHT)
	info = PanelContainer.new()
	info.set_anchors_preset(Control.PRESET_CENTER)
	info.offset_left = -330
	info.offset_right = 330
	info.offset_top = -250
	info.offset_bottom = 250
	info.grow_horizontal = Control.GROW_DIRECTION_BOTH   # longer text grows it both ways: it stays centred
	info.grow_vertical = Control.GROW_DIRECTION_BOTH
	info.visible = false
	info.gui_input.connect(_on_click)
	add_child(info)
	_info_text = Label.new()
	_info_text.add_theme_font_size_override("font_size", 20)
	info.add_child(_info_text)
	refresh()


## A full-width strip at the top or bottom edge.
func _strip(preset: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(preset)
	if preset == Control.PRESET_TOP_WIDE:
		p.offset_bottom = 40
	else:
		p.offset_top = -40
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.85)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.gui_input.connect(_on_click)
	p.tooltip_text = "Info (F1)"
	add_child(p)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	return p


func _cell(strip: PanelContainer, align: int) -> Label:
	var l := Label.new()
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 19)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.get_child(0).add_child(l)
	return l


func _on_click(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		toggle_info()
		get_viewport().set_input_as_handled()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F1:
		toggle_info()
		get_viewport().set_input_as_handled()


func toggle_info() -> void:
	info.visible = not info.visible
	refresh()


static var _last_place := ""        ## the banner's last place, across scenes
static var _last_vitals := ""       ## the footer's last readings, across scenes


func _process(dt: float) -> void:
	_left -= dt
	if _left <= 0.0:
		_left = REFRESH
		refresh()


func refresh() -> void:
	if banner == null:
		return
	var talking: bool = demo != null and demo.bar != null and demo.bar.is_talking()
	footer.visible = not talking          # the chat box sits there
	var planet := str(demo.planet_name) if demo != null else ""
	var town := str(demo.town_name) if demo != null else ""
	if planet == "" and town == "" and _last_place != "":
		_place.text = _last_place     # a handoff's scene names its places a moment later: keep the old ones till then
	else:
		_place.text = "> %s // %s" % [(planet if planet != "" else "UNCHARTED").to_upper(),
			(town if town != "" else "OUTPOST").to_upper()]
		_last_place = _place.text
	_clock.text = "%s  %s" % [clock_text(), str(WorldState.time_of_day).to_upper()]
	_money.text = "CR %d   [F1] INFO" % WorldState.credits
	var v := vitals_text()
	if _readings(_last_vitals) > _readings(v) and demo != null and demo.get("staging") == true \
			and demo.get("staged") != null and not demo.staged.done:
		v = _last_vitals              # a handoff's scene builds the body and gear a moment later: keep the old readings till then
	_vitals.text = v
	_last_vitals = v
	_mode.text = mode_text() + "   [F11] SETTINGS"
	if info.visible:
		_info_text.text = info_text()


## "18:40", from the look's hour (F11 slider) when it has one.
func clock_text() -> String:
	var h := -1.0
	if demo != null and demo.look != null:
		h = float(demo.look.hour)
	if h < 0.0:
		h = { "dawn": 6.5, "golden": 17.5, "noon": 12.0, "dusk": 19.5, "night": 23.0 }.get(str(WorldState.time_of_day), 12.0)
	return "%02d:%02d" % [int(h) % 24, int(fposmod(h, 1.0) * 60.0)]


func _player():
	return demo._player if demo != null else null


func vitals_text() -> String:
	var parts := PackedStringArray()
	var p = _player()
	if p != null and p.health != null:
		var hp := float(p.health.hp)
		var top := maxf(1.0, float(p.health.max_hp))
		parts.append("HP %s %03d" % [RetroUI.bar(hp / top), int(hp)])
	var kit = demo.player_kit if demo != null else null
	if kit != null and kit.weapons != null and kit.weapons.combo != null:
		var b = kit.weapons.combo.blade
		parts.append("STA %s" % RetroUI.bar(b.stamina / maxf(1.0, b.max_stamina), 8))
	if p != null and p.jetpack != null:
		parts.append("FUEL %s" % RetroUI.bar(p.jetpack.fuel / maxf(0.01, p.jetpack.fuel_max()), 8))
	return "   ".join(parts)


static func _readings(t: String) -> int:
	return int(t.contains("HP ")) + int(t.contains("STA ")) + int(t.contains("FUEL "))


func mode_text() -> String:
	var p = _player()
	if p != null and p.get("piloting") == true:
		return "MODE: PILOT"
	return "MODE: ON FOOT"


static func standing_word(v: int) -> String:
	if v <= -40:
		return "HOSTILE"
	if v < -5:
		return "UNFRIENDLY"
	if v <= 10:
		return "NEUTRAL"
	if v < 40:
		return "FRIENDLY"
	return "ALLIED"


func info_text() -> String:
	var t := PackedStringArray()
	t.append("==[ STATUS ]===================")
	t.append("PLANET    %s" % (str(demo.planet_name) if demo != null else "?"))
	t.append("TOWN      %s" % (str(demo.town_name) if demo != null else "?"))
	t.append("TIME      %s  %s" % [clock_text(), str(WorldState.time_of_day).to_upper()])
	t.append("CREDITS   %d" % WorldState.credits)
	t.append("SPEEDERS  %d" % WorldState.count("speeders_owned"))
	for s in ShipUpgrades.owned_lines():                # issue #207: your ships and their upgrades
		t.append("SHIP      " + str(s).left(52))
	if GearUpgrades.owned_line() != "":                 # issue #208: the fence's upgrades
		t.append("GEAR      " + GearUpgrades.owned_line().left(52))
	t.append("")
	t.append("==[ STANDING ]=================")
	for f in WorldState.FACTIONS:
		var v := int(WorldState.standing.get(f, 0))
		t.append("%-17s %s %+4d %s" % [str(f).capitalize(), RetroUI.bar((v + 100) / 200.0, 10), v, standing_word(v)])
	if Objective.home():
		t.append("")
		t.append("==[ CONTROL ]==================")    # issue #187: who holds each place
		for s in Territory.summary():
			t.append("  " + str(s))
	t.append("")
	t.append("==[ LATEST ]===================")
	var ev: Array = WorldState.events.slice(-4)
	if ev.is_empty():
		t.append("  quiet so far")
	for e in ev:
		t.append("  " + str(e.get("text", "")).left(52))
	t.append("")
	t.append("[F1] or click to close")
	return "\n".join(t)
