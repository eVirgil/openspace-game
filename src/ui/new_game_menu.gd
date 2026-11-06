class_name NewGameMenu
extends CanvasLayer
## Issue #200: New Game asks Story or Free Roam. Shown once, on a first launch
## (no save yet), after the AI notice (DisclaimerOverlay) is accepted; never in a
## headless run. Picking one starts that game in its own save slot
## (DevSettingsPanel.new_game) and the town reloads. Later new games, and playing
## the other save, are in F11 > Game.
##
## It starts on Story: Enter (or Space) picks the lit choice, Up/W and Down/S
## move it, a click picks one. The menu reads the keys itself, like DroidMenu.

const CHOICES := [
	[WorldState.STORY, "Story",
		"You land broke in a wreck, in a port the Remnant runs. Pistol only, nobody's friend yet, and you play the smuggler."],
	[WorldState.FREEPLAY, "Free Roam",
		"The town as it is: drops and bounties on repeat, the port's ships, any character you like. The rifle and the blade are in your pack."],
]

var settings: DevSettingsPanel
var selected := 0                 ## the choice Enter picks: Story to start
var _buttons: Array[Button] = []
var _lit: StyleBoxFlat


## Show it if the town found no save. Returns the menu, or null.
static func show_if_fresh(demo: Node, panel: DevSettingsPanel) -> NewGameMenu:
	if DisplayServer.get_name() == "headless" or demo.get("bar") == null or not demo.bar.fresh:
		return null
	var m := NewGameMenu.new()
	m.settings = panel
	demo.add_child(m)
	return m


func _ready() -> void:
	name = "NewGameMenu"
	layer = 29
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var notice := get_parent().get_node_or_null("DisclaimerOverlay")
	if notice != null and not notice.is_queued_for_deletion():
		notice.accepted.connect(_open)
	else:
		_open()


func _open() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.015, 0.01, 0.9)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -380
	panel.offset_right = 380
	panel.offset_top = -200
	panel.offset_bottom = 200
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.05, 0.98)
	sb.border_color = Color("#c9a35e")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		sb.set_content_margin(side, 28)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	panel.add_child(v)
	var title := Label.new()
	title.text = "New game"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("#e0a050"))
	v.add_child(title)
	for c in CHOICES:
		var b := Button.new()
		b.text = c[1]
		b.add_theme_font_size_override("font_size", 22)
		b.custom_minimum_size = Vector2(200, 48)
		b.focus_mode = Control.FOCUS_NONE        # the keys are this menu's, not the focus system's
		b.pressed.connect(pick.bind(c[0]))
		b.mouse_entered.connect(_select.bind(_buttons.size()))
		var about := Label.new()
		about.text = c[2]
		about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		about.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		about.add_theme_font_size_override("font_size", 18)
		about.add_theme_color_override("font_color", Color(0.95, 0.92, 0.86))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		row.add_child(b)
		row.add_child(about)
		v.add_child(row)
		_buttons.append(b)
	_lit = sb.duplicate()
	_lit.bg_color = Color("#c9a35e", 0.3)
	_lit.set_content_margin_all(8)
	_select(0)
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## _input, not _unhandled_input: the menu is modal, and nothing behind it may
## take Enter or the arrow keys first.
##
## The key is marked handled before it acts: picking reloads the town, which
## takes the scene (this menu with it) out of the tree at once, and then
## get_viewport() is null. A debug build only logged that; the exported game
## (a release build) crashed on it, on a first launch, as Enter picked a game.
func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed:
		return
	var k := (event as InputEventKey).keycode
	if k in [KEY_UP, KEY_W, KEY_DOWN, KEY_S]:
		get_viewport().set_input_as_handled()
		_select(posmod(selected + (-1 if k in [KEY_UP, KEY_W] else 1), CHOICES.size()))
	elif k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and not event.echo:
		get_viewport().set_input_as_handled()
		pick(CHOICES[selected][0])


## Light choice `i`: the one Enter picks.
func _select(i: int) -> void:
	selected = i
	for j in _buttons.size():
		if j == i:
			for st in ["normal", "hover", "pressed"]:
				_buttons[j].add_theme_stylebox_override(st, _lit)
		else:
			for st in ["normal", "hover", "pressed"]:
				_buttons[j].remove_theme_stylebox_override(st)


## Start a new game in `mode` (the town reloads).
func pick(mode: String) -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	settings.new_game(mode)
	queue_free()
