class_name CharacterBuilder
extends HBoxContainer
## Issue #48: mix and match the player's outfit from the kit pieces (F11,
## Character). A head, upper body and lower body piece, each in one of its colours
## (PlayerOutfit.catalog), shown on a turning model. Every change is saved at once
## (PlayerOutfit) and sent out as outfit_changed, so the player wears it live.
## In free roam the guard's pieces show once the player has had its armour
## (PlayerOutfit.unlocked); the lists are filled again each time it is shown.

signal outfit_changed(outfit: Dictionary)

const LABELS := { "head": "Head", "torso": "Upper body", "legs": "Lower body" }
const TURN_SPEED := 0.6        ## rad/s
const BG := Color(0.11, 0.09, 0.08)

var outfit: Dictionary = {}    ## every part filled in: { part: "<piece>[:<colour>]" }
var preview: Node3D            ## the model on the turntable
var _kit: CharacterKit
var _turntable: Node3D
var _pieces: Dictionary = {}   ## part -> OptionButton
var _colours: Dictionary = {}  ## part -> OptionButton
var _locked_note: Label        ## which item opens the pieces still locked


func _init() -> void:
	add_theme_constant_override("separation", 14)
	_kit = CharacterKit.new(LookMaterials.new(), -1000.0)
	add_child(_viewport())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(v)
	for part in PlayerOutfit.PARTS:
		var title := Label.new()
		title.text = LABELS[part]
		title.add_theme_color_override("font_color", Color("#d8b878"))
		v.add_child(title)
		var h := HBoxContainer.new()
		var piece := OptionButton.new()
		piece.custom_minimum_size = Vector2(150, 0)
		piece.item_selected.connect(func(_i): _pick(part, true))
		h.add_child(piece)
		var colour := OptionButton.new()
		colour.custom_minimum_size = Vector2(150, 0)
		colour.item_selected.connect(func(_i): _pick(part, false))
		h.add_child(colour)
		v.add_child(h)
		_pieces[part] = piece
		_colours[part] = colour
	var buttons := HBoxContainer.new()
	for b in [["Random", randomize_outfit], ["Default", func(): _commit({})]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.pressed.connect(b[1])
		buttons.add_child(btn)
	v.add_child(buttons)
	var note := Label.new()
	note.text = "Saved as you pick; worn at once."
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	v.add_child(note)
	_locked_note = Label.new()
	_locked_note.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_locked_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_locked_note)
	show_outfit(PlayerOutfit.load_outfit())


func _process(dt: float) -> void:
	if _turntable != null and is_visible_in_tree():
		_turntable.rotation.y = wrapf(_turntable.rotation.y + TURN_SPEED * dt, -PI, PI)


## Put an outfit in the controls and on the preview (without saving it).
func show_outfit(o: Dictionary) -> void:
	_rebuild(PlayerOutfit.sanitize(o))
	_fill_pieces()
	for part in PlayerOutfit.PARTS:
		var pc := PlayerOutfit.split(str(outfit.get(part, "")))
		var piece: OptionButton = _pieces[part]
		for i in piece.item_count:
			if piece.get_item_metadata(i) == pc[0]:
				piece.select(i)
		_fill_colours(part, pc[0])
		var colour: OptionButton = _colours[part]
		for i in colour.item_count:
			if colour.get_item_metadata(i) == pc[1]:
				colour.select(i)


func randomize_outfit() -> void:
	var o := {}
	for part in PlayerOutfit.PARTS:
		var pieces: Dictionary = PlayerOutfit.pickable().get(part, {})
		if pieces.is_empty():
			continue
		var piece: String = pieces.keys().pick_random()
		o[part] = PlayerOutfit.choice(piece, ([""] + pieces[piece]).pick_random())
	_commit(o)


## A control changed: the part's choice from its two buttons. A new piece starts on
## its own colour (the old piece's colours may not exist on it).
func _pick(part: String, new_piece: bool) -> void:
	var piece := str(_pieces[part].get_selected_metadata())
	if new_piece:
		_fill_colours(part, piece)
	var colour: OptionButton = _colours[part]
	var o := outfit.duplicate()
	o[part] = PlayerOutfit.choice(piece, str(colour.get_selected_metadata()) if colour.selected >= 0 else "")
	_commit(o)


func _commit(o: Dictionary) -> void:
	PlayerOutfit.save_outfit(o)
	show_outfit(o)
	outfit_changed.emit(outfit)


## Each part's pieces from what can be picked now (a locked piece may have opened),
## and a line naming the item that opens any still locked.
func _fill_pieces() -> void:
	var cat := PlayerOutfit.pickable()
	for part in PlayerOutfit.PARTS:
		var piece: OptionButton = _pieces[part]
		piece.clear()
		for p in cat.get(part, {}):
			piece.add_item(str(p).capitalize())
			piece.set_item_metadata(piece.item_count - 1, p)
	var needs: Array = []
	for item in PlayerOutfit.locked_items():
		needs.append(str(WorldState._item(item).get("label", item)))
	_locked_note.text = "More pieces open once you have: %s." % ", ".join(needs) if not needs.is_empty() else ""
	_locked_note.visible = not needs.is_empty()


func _fill_colours(part: String, piece: String) -> void:
	var colour: OptionButton = _colours[part]
	colour.clear()
	colour.add_item("Original")
	colour.set_item_metadata(0, "")
	for c in PlayerOutfit.pickable().get(part, {}).get(piece, []):
		colour.add_item(str(c).capitalize())
		colour.set_item_metadata(colour.item_count - 1, c)
	colour.select(0)


func _rebuild(o: Dictionary) -> void:
	if preview != null:
		preview.free()
	preview = _kit.build(PlayerOutfit.ARCHETYPE, "idle", o)
	_turntable.add_child(preview)
	outfit = preview.get_meta("outfit", {})


# ------------------------------------------------------------------ preview

func _viewport() -> Control:
	var box := SubViewportContainer.new()
	box.custom_minimum_size = Vector2(240, 360)
	box.stretch = true
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	box.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.45)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.4
	key.light_color = Color(1.0, 0.92, 0.8)
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 0.7
	rim.light_color = Color(0.7, 0.8, 1.0)
	vp.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 1.05, 4.2)
	cam.rotation_degrees = Vector3(-4, 0, 0)
	vp.add_child(cam)
	_turntable = Node3D.new()
	_turntable.name = "Turntable"
	vp.add_child(_turntable)
	return box
