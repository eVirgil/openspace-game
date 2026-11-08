class_name CommunityNpcPanel
extends CanvasLayer
## Issue #147: the NPC builder. Opened at a free market stall ([E] Make this
## stall keeper yours, CommunityStalls). Four pages:
##
##   Look            the kit pieces (the player's CharacterBuilder, NPC mode),
##                   height, build, voice and what is on the counter
##   Who             your handle, their name and label, temperament, how much
##                   they say, their side in the war, who they are, their past,
##                   how they speak, who they know, a secret
##   Lines           what they say with no AI model: greetings, small talk, goodbyes
##   Check & send    every check (CommunityNpc.validate), the file as it will go
##                   in, and Open pull request / Export file / Copy file
##
## Every change is kept as a draft for this stall (CommunityNpc.save_draft), so
## coming back carries on. "Try them out" closes the panel and puts them behind
## the counter to talk to (tried); nothing of them goes in the save. The game
## is paused while it is open.

signal tried(npc: Dictionary)
signal closed

const SIZE := Vector2(820, 660)
const INK_DIM := Color(1, 1, 1, 0.55)
const RED := Color("#e07060")
const GREEN := Color("#6ee07a")
const GOLD := Color("#d8b878")
const LINE_FIELDS := ["speech", "greetings_stranger", "greetings_regular", "small_talk", "bye"]

var npc: Dictionary = {}
var others: Array = []               ## the stall keepers already in (their names and ids are taken)
var errors: Array = []               ## CommunityNpc.validate, as of the last change
var tabs: TabContainer
var look: CharacterBuilder
var status: Label
var pr_button: Button
var _panel: PanelContainer
var _title: Label
var _f: Dictionary = {}              ## field -> its control
var _counts: Dictionary = {}         ## field -> Label "12 / 300"
var _knows: Dictionary = {}          ## knowable id -> [CheckBox, LineEdit]
var _checks: VBoxContainer
var _file: TextEdit
var _where: Label
var _loading := false
var _was_mouse := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	name = "CommunityNpcPanel"
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.06, 0.06, 0.97)
	sb.border_color = Color("#b08e50")
	sb.set_border_width_all(1)
	for side in ["left", "right", "top", "bottom"]:
		sb.set("content_margin_" + side, 14)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	v.add_child(_title)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.tab_changed.connect(func(_i): _refresh_checks())
	v.add_child(tabs)
	tabs.add_child(_look_page())
	tabs.add_child(_who_page())
	tabs.add_child(_lines_page())
	tabs.add_child(_send_page())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	var try_b := Button.new()
	try_b.text = "Try them out"
	try_b.tooltip_text = "Close the builder and talk to them at the stall. Nothing of them goes in your save."
	try_b.pressed.connect(_try)
	h.add_child(try_b)
	var close_b := Button.new()
	close_b.text = "Close"
	close_b.pressed.connect(close)
	h.add_child(close_b)
	status = Label.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", INK_DIM)
	h.add_child(status)
	visible = false


## Open on `data` (a draft, or CommunityNpc.blank). `taken`: the stall keepers
## already in this town.
func open(data: Dictionary, taken: Array = []) -> void:
	npc = data.duplicate(true)
	others = taken
	_fit()
	_fill()
	_title.text = "Your stall keeper  ·  %s" % _stall_name()
	tabs.current_tab = 0
	status.text = ""
	visible = true
	_was_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	_refresh_checks()


func close() -> void:
	if not visible:
		return
	_pull()
	visible = false
	get_tree().paused = false
	Input.mouse_mode = _was_mouse
	closed.emit()


func _process(_dt: float) -> void:
	if visible and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _try() -> void:
	_pull()
	var data := npc.duplicate(true)
	close()
	tried.emit(data)


func _stall_name() -> String:
	var n := str(npc.get("stall", "")).get_slice("_", 1)
	return "stall %s in the market" % n if n != "" else "a market stall"


func _fit() -> void:
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else SIZE
	var s := Vector2(minf(SIZE.x, vp.x - 40.0), minf(SIZE.y, vp.y - 40.0))
	_panel.custom_minimum_size = s
	_panel.size = s
	_panel.position = (vp - s) * 0.5


# ------------------------------------------------------------------ pages

func _look_page() -> Control:
	var scroll := _scroll("Look")
	look = CharacterBuilder.new(true)
	look.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	look.outfit_changed.connect(func(_o): _changed())
	scroll.get_child(0).add_child(look)
	var col := look.controls
	var cfg: Dictionary = CommunityNpc.config().get("look", {})
	for k in ["height", "build"]:
		var r: Dictionary = cfg.get(k, {})
		col.add_child(_heading("Height" if k == "height" else "Build"))
		var s := HSlider.new()
		s.min_value = float(r.get("min", 0.9))
		s.max_value = float(r.get("max", 1.1))
		s.step = 0.01
		s.custom_minimum_size = Vector2(300, 0)
		s.value_changed.connect(func(_x): _changed())
		col.add_child(s)
		_f[k] = s
	col.add_child(_heading("Voice"))
	col.add_child(_options("voice", CommunityNpc.voices().map(func(id): return [id, str(id).capitalize()])))
	col.add_child(_heading("On the counter"))
	var wares: Dictionary = CommunityNpc.template().get("wares", {})
	col.add_child(_options("wares", wares.keys().map(func(id): return [id, str(wares[id]).capitalize()])))
	return scroll


## A page that scrolls: the ScrollContainer, its VBox the page's first child.
func _scroll(title: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	scroll.add_child(v)
	return scroll


func _who_page() -> Control:
	var scroll := _scroll("Who")
	var v: VBoxContainer = scroll.get_child(0)
	_line(v, "author", "Your handle", "Your GitHub name: the pull request and the file say who made them.")
	_line(v, "name", "Their name", "Leave it empty and they never give a name: people call them by their label.")
	_line(v, "label", "What people call them", "Their trade, in a word or two: Potter, Water seller.")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	v.add_child(grid)
	var t := CommunityNpc.template()
	var temps: Dictionary = t.get("temperaments", {})
	grid.add_child(_label("Temperament"))
	grid.add_child(_options("temperament", temps.keys().map(func(id): return [id, str(temps[id].get("label", id))])))
	grid.add_child(_label("Says at a time"))
	grid.add_child(_options("sentences", [[1, "One sentence"], [2, "Two sentences"], [3, "Three sentences"]]))
	var sides: Dictionary = t.get("sides", {})
	grid.add_child(_label("In the war"))
	grid.add_child(_options("side", sides.keys().map(func(id): return [id, str(sides[id].get("label", id))])))
	_text(v, "identity", "Who they are", "One or two sentences: \"A retired miner who sells pots to pay off his debts.\"", 60)
	_text(v, "backstory", "Their past", "What happened to them, what they want, what they fear.", 90)
	_text(v, "speech", "How they speak (one per line)", "\"Calls everyone 'dear'.\"  \"Laughs at their own jokes.\"", 70)
	v.add_child(_heading("Who they know (tick, then say what they think of them)"))
	var known := CommunityNpc.knowable()
	for id in known:
		var h := HBoxContainer.new()
		var cb := CheckBox.new()
		cb.text = str(known[id])
		cb.custom_minimum_size = Vector2(170, 0)
		cb.toggled.connect(func(_on): _changed())
		h.add_child(cb)
		var le := LineEdit.new()
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.placeholder_text = "What they think of %s" % known[id]
		le.max_length = int(CommunityNpc.limit("knows").get("max", 140))
		le.text_changed.connect(func(_s): _changed())
		h.add_child(le)
		v.add_child(h)
		_knows[id] = [cb, le]
	_line(v, "secret", "A secret (optional)", "Only told to a player they trust.")
	return scroll


func _lines_page() -> Control:
	var scroll := _scroll("Lines")
	var v: VBoxContainer = scroll.get_child(0)
	var note := _label("What they say when no AI model is set up, and how they open a talk. One line each.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", INK_DIM)
	v.add_child(note)
	_text(v, "greetings_stranger", "Greeting a stranger", "\"New face. Looking or buying?\"", 70)
	_text(v, "greetings_regular", "Greeting a regular (optional)", "\"You again! Sit, sit.\"", 70)
	_text(v, "small_talk", "Small talk", "\"Sand in everything this week.\"", 90)
	_text(v, "bye", "Goodbye", "\"Mind the gate.\"", 60)
	return scroll


func _send_page() -> Control:
	var scroll := _scroll("Check & send")
	var page: VBoxContainer = scroll.get_child(0)
	_where = _label("")
	_where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_where)
	_checks = VBoxContainer.new()
	page.add_child(_checks)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	page.add_child(h)
	pr_button = Button.new()
	pr_button.text = "Open pull request on GitHub"
	pr_button.tooltip_text = "Opens GitHub with the file filled in. Sign in, then Propose new file and Create pull request."
	pr_button.pressed.connect(_open_pr)
	h.add_child(pr_button)
	var export_b := Button.new()
	export_b.text = "Export file"
	export_b.pressed.connect(_export)
	h.add_child(export_b)
	var copy := Button.new()
	copy.text = "Copy file"
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(CommunityNpc.to_json(npc))
		status.text = "The file is on your clipboard.")
	h.add_child(copy)
	page.add_child(_heading("The file"))
	_file = TextEdit.new()
	_file.editable = false
	_file.custom_minimum_size = Vector2(0, 260)
	page.add_child(_file)
	return scroll


# ------------------------------------------------------------------ controls

func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _heading(text: String) -> Label:
	var l := _label(text)
	l.add_theme_color_override("font_color", GOLD)
	return l


func _line(parent: Control, field: String, title: String, hint: String) -> void:
	parent.add_child(_heading(title))
	var le := LineEdit.new()
	le.placeholder_text = hint
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lim := CommunityNpc.limit(field)
	if lim.has("max"):
		le.max_length = int(lim.max)
	le.text_changed.connect(func(_s): _changed())
	parent.add_child(le)
	_f[field] = le


func _text(parent: Control, field: String, title: String, hint: String, height: float) -> void:
	var h := HBoxContainer.new()
	var t := _heading(title)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	var n := _label("")
	n.add_theme_color_override("font_color", INK_DIM)
	h.add_child(n)
	parent.add_child(h)
	_counts[field] = n
	var te := TextEdit.new()
	te.placeholder_text = hint
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.custom_minimum_size = Vector2(0, height)
	te.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	te.text_changed.connect(_changed)
	parent.add_child(te)
	_f[field] = te


func _options(field: String, items: Array) -> OptionButton:
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(260, 0)
	for it in items:
		ob.add_item(str(it[1]))
		ob.set_item_metadata(ob.item_count - 1, it[0])
	ob.item_selected.connect(func(_i): _changed())
	_f[field] = ob
	return ob


func _select(ob: OptionButton, value) -> void:
	for i in ob.item_count:
		if str(ob.get_item_metadata(i)) == str(value) or (value is float and str(ob.get_item_metadata(i)) == str(int(value))):
			ob.select(i)
			return


# ------------------------------------------------------------------ data <-> controls

## Put the file in the controls.
func _fill() -> void:
	_loading = true
	var l: Dictionary = npc.get("look", {})
	look.show_outfit(CommunityNpc.outfit(npc))
	(_f.height as HSlider).value = CommunityNpc.height(npc)
	(_f.build as HSlider).value = CommunityNpc.build(npc)
	_apply_scale()
	for k in ["author", "name", "label", "secret"]:
		(_f[k] as LineEdit).text = str(npc.get(k, ""))
	for k in ["voice", "wares", "temperament", "sentences", "side"]:
		_select(_f[k], npc.get(k, ""))
	for k in ["identity", "backstory"]:
		(_f[k] as TextEdit).text = str(npc.get(k, ""))
	var g: Dictionary = npc.get("greetings", {})
	var lines: Dictionary = npc.get("lines", {})
	var lists := { "speech": npc.get("speech", []), "greetings_stranger": g.get("stranger", []),
		"greetings_regular": g.get("regular", []), "small_talk": lines.get("small_talk", []), "bye": lines.get("bye", []) }
	for k in lists:
		(_f[k] as TextEdit).text = "\n".join(PackedStringArray((lists[k] as Array).map(func(x): return str(x))))
	var knows: Dictionary = npc.get("knows", {})
	for id in _knows:
		(_knows[id][0] as CheckBox).button_pressed = knows.has(id)
		(_knows[id][1] as LineEdit).text = str(knows.get(id, ""))
	_loading = false
	_counts_update()
	if l.is_empty():
		_pull()


## Read the controls into the file. The id follows the name (or the label).
func _pull() -> void:
	var o := look.outfit
	npc["look"] = { "head": str(o.get("head", "local")), "torso": str(o.get("torso", "local")), "legs": str(o.get("legs", "local")),
		"height": snappedf((_f.height as HSlider).value, 0.01), "build": snappedf((_f.build as HSlider).value, 0.01) }
	for k in ["author", "name", "label", "secret"]:
		npc[k] = (_f[k] as LineEdit).text.strip_edges()
	for k in ["voice", "wares", "temperament", "side"]:
		npc[k] = str((_f[k] as OptionButton).get_selected_metadata())
	npc["sentences"] = int((_f.sentences as OptionButton).get_selected_metadata())
	for k in ["identity", "backstory"]:
		npc[k] = (_f[k] as TextEdit).text.strip_edges()
	npc["speech"] = _lines_of("speech")
	npc["greetings"] = { "stranger": _lines_of("greetings_stranger"), "regular": _lines_of("greetings_regular") }
	npc["lines"] = { "small_talk": _lines_of("small_talk"), "bye": _lines_of("bye") }
	var knows := {}
	for id in _knows:
		if (_knows[id][0] as CheckBox).button_pressed:
			knows[id] = (_knows[id][1] as LineEdit).text.strip_edges()
	npc["knows"] = knows
	npc["id"] = CommunityNpc.slug(str(npc.name) if str(npc.name) != "" else str(npc.label))
	CommunityNpc.save_draft(npc)
	if str(npc.author) != "":
		CommunityNpc.save_author(str(npc.author))


func _lines_of(field: String) -> Array:
	var out: Array = []
	for l in (_f[field] as TextEdit).text.split("\n", false):
		if l.strip_edges() != "":
			out.append(l.strip_edges())
	return out


func _changed() -> void:
	if _loading:
		return
	_apply_scale()
	_pull()
	_counts_update()
	_refresh_checks()


func _apply_scale() -> void:
	look.set_body_scale(CommunityNpc.scale_of({ "look": { "height": (_f.height as HSlider).value, "build": (_f.build as HSlider).value } }))


func _counts_update() -> void:
	for k in _counts:
		var lim := CommunityNpc.limit(k)
		var lbl: Label = _counts[k]
		if LINE_FIELDS.has(k):
			var n := _lines_of(k).size()
			lbl.text = "%d of %d–%d lines" % [n, int(lim.get("min_lines", 0)), int(lim.get("max_lines", 5))]
		else:
			lbl.text = "%d / %d" % [(_f[k] as TextEdit).text.strip_edges().length(), int(lim.get("max", 300))]


func _refresh_checks() -> void:
	if _checks == null or npc.is_empty():
		return
	errors = CommunityNpc.validate(npc, others)
	for c in _checks.get_children():
		c.queue_free()
	if errors.is_empty():
		var ok := _label("✓  Ready to send.")
		ok.add_theme_color_override("font_color", GREEN)
		_checks.add_child(ok)
	for e in errors:
		var l := _label("✗  " + str(e.text))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", RED)
		_checks.add_child(l)
	_where.text = "%s keeps %s. Once the pull request is merged, everyone meets them there in the next build. The file: %s" % [
		CommunityNpc.display_name(npc), _stall_name(), CommunityNpc.repo_path(npc)]
	_file.text = CommunityNpc.to_json(npc)
	pr_button.disabled = not errors.is_empty()


# ------------------------------------------------------------------ send

func _open_pr() -> void:
	_pull()
	if not CommunityNpc.validate(npc, others).is_empty():
		_refresh_checks()
		return
	var link := CommunityNpc.pr_url(npc)
	var err := OS.shell_open(str(link.url))
	if not bool(link.full):
		DisplayServer.clipboard_set(CommunityNpc.to_json(npc))
		status.text = "The file is too long for a link: it is on your clipboard. Paste it into the page GitHub opened."
	else:
		status.text = "GitHub is open in your browser: sign in, then Propose new file and Create pull request."
	if err != OK:
		DisplayServer.clipboard_set(str(link.url))
		status.text = "Could not open the browser. The link is on your clipboard: paste it into one."


func _export() -> void:
	_pull()
	var path := CommunityNpc.export_file(npc)
	if path == "":
		status.text = "Could not write the file."
		return
	DisplayServer.clipboard_set(CommunityNpc.to_json(npc))
	status.text = "Saved to %s (and copied)." % path
