class_name DroidMenu
extends CanvasLayer
## A pick list (issue #51): the droid merchant, a cargo droid's hold, and "you
## already run three droids: sell one?". No game logic: the caller hands it the
## options and a callback. Issue #58: an optional body (what T-89 is saying) sits
## between the title and the options.
##
## Keys: W/S or the arrows move the cursor, Enter picks the row under it, Esc
## walks away. A shop that reopens the menu from its pick
## callback (open with keep_cursor) stays where it was, so you can buy or sell
## again without starting over. Long lists scroll.
##
## A row marked "job" (what you are delivering for a job you have open) is green,
## and a fresh menu opens with the cursor on the first one.

const INK := Color(0.95, 0.92, 0.85, 0.95)
const AMBER := Color("#e0a050")
const JOB_GREEN := Color("#6ee07a")   ## coloured, so RetroSkin leaves it be
const PANEL_W := 600.0             ## narrower on a small screen (or a big text size)
const LIST_MAX_H := 330.0          ## rows past this scroll (less on a short screen)
const MARK_W := 20.0               ## the cursor mark's column (not KEY_W: in here that would hide the W key)

var panel: PanelContainer
var title_label: Label
var body_label: Label
var scroll: ScrollContainer
var list: VBoxContainer
var hint: Label
var options: Array = []           ## [{ id, text }]
var on_pick: Callable             ## (id: String) -> void; "" = walked away
var rows: Array = []              ## the text of each row, for tests
var selected := 0                 ## the row under the cursor
var _rows: Array = []             ## [{ box: PanelContainer, key: Label, text: Label }]
var _cursor_box: StyleBoxFlat
var _row_box: StyleBoxEmpty
signal option_selected(id: String)


func _init() -> void:
	name = "DroidMenu"
	layer = 8


func _ready() -> void:
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	title_label = Label.new()
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.add_theme_color_override("font_color", AMBER)
	box.add_child(title_label)
	body_label = Label.new()
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.add_theme_font_size_override("font_size", 17)
	body_label.add_theme_color_override("font_color", INK)
	box.add_child(body_label)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	hint = Label.new()
	hint.text = "[W/S]  Move    [Enter]  Choose    [Esc]  Walk away"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(INK, 0.6))
	box.add_child(hint)
	_cursor_box = StyleBoxFlat.new()
	_cursor_box.border_width_left = 3
	_cursor_box.set_content_margin_all(2)
	_row_box = StyleBoxEmpty.new()
	_row_box.set_content_margin_all(2)
	panel.visible = false


func is_open() -> bool:
	return panel != null and panel.visible


## Show the menu. keep_cursor: the same menu again (after a buy or a sale), so the
## cursor stays on the row it was on, or the row that took its place.
func open(title: String, opts: Array, pick: Callable, body: String = "", keep_cursor: bool = false) -> void:
	var was := str(options[selected].id) if keep_cursor and selected < options.size() else ""
	options = opts.duplicate()
	on_pick = pick
	rows.clear()
	var at := -1
	if was != "":
		for i in options.size():
			if str(options[i].id) == was:
				at = i
				break
	selected = at if at >= 0 else (clampi(selected, 0, maxi(options.size() - 1, 0)) if keep_cursor else first_job())
	for i in options.size():
		rows.append(str(options[i].text))
	if panel == null:
		return
	title_label.text = title
	body_label.text = body
	body_label.visible = body != ""
	for c in list.get_children():
		c.free()
	_rows.clear()
	for i in options.size():
		var box := PanelContainer.new()
		box.set_meta("retro_off", true)     # the cursor bar is ours, not RetroSkin's glass
		var line := HBoxContainer.new()
		box.add_child(line)
		var key := _row_label("")
		key.custom_minimum_size.x = MARK_W
		key.size_flags_vertical = Control.SIZE_SHRINK_BEGIN     # level with the first line
		line.add_child(key)
		var text := _row_label(str(options[i].text))
		if bool(options[i].get("job", false)):
			text.add_theme_color_override("font_color", JOB_GREEN)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART     # long offers wrap under the text, not the cursor
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		list.add_child(box)
		_rows.append({ "box": box, "key": key, "text": text })
	_fit()
	_show_cursor()
	panel.visible = true
	_fit.call_deferred()     # again once RetroSkin has swapped the font in


## The first row marked "job", or 0 when there is none.
func first_job() -> int:
	for i in options.size():
		if bool(options[i].get("job", false)):
			return i
	return 0


func _row_label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", INK)
	return l


## Size the box to the screen: at a big text size the screen is small in UI units,
## so the box narrows, rows wrap, and the list scrolls rather than run off it.
func _fit() -> void:
	if panel == null:
		return
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1920, 1080)
	var w := minf(PANEL_W, vp.x - 32.0)
	panel.offset_left = -w * 0.5
	panel.offset_right = w * 0.5
	var inner := w - 28.0
	var wraps := [title_label, body_label, hint]
	var widths := [inner, inner, inner]
	for r in _rows:
		wraps.append(r.text)
		widths.append(inner - 16.0 - MARK_W - 12.0)     # less the scroll bar, the cursor mark, the gaps
	for i in wraps.size():
		var l: Label = wraps[i]
		l.custom_minimum_size.x = widths[i]
		l.size.x = widths[i]     # wrap at this width now, not after the next layout pass
	var h := 0.0
	for r in _rows:
		h += r.box.get_combined_minimum_size().y + 2.0
	var rest := title_label.get_combined_minimum_size().y + hint.get_combined_minimum_size().y + 60.0
	if body_label.visible:
		rest += body_label.get_combined_minimum_size().y
	var room := clampf(vp.y * 0.92 - rest, 60.0, LIST_MAX_H)
	scroll.custom_minimum_size = Vector2(inner, minf(h, room))
	var ph := panel.get_combined_minimum_size().y
	panel.offset_top = -ph * 0.5
	panel.offset_bottom = ph * 0.5


## Move the cursor by `step` rows (wraps round).
func move(step: int) -> void:
	if options.is_empty():
		return
	selected = posmod(selected + step, options.size())
	_show_cursor()


## The row under the cursor: a lit bar behind it in the HUD colour (RetroSkin
## owns the text colours) and a ">" in front of it.
func _show_cursor() -> void:
	_cursor_box.bg_color = Color(RetroUI.accent, 0.28)
	_cursor_box.border_color = RetroUI.accent
	for i in _rows.size():
		var on := i == selected
		_rows[i].box.add_theme_stylebox_override("panel", _cursor_box if on else _row_box)
		_rows[i].key.text = ">" if on else ""
	_scroll_to_cursor()


## Once the list has been laid out (the rows' places are known), bring the cursor
## row into view.
func _scroll_to_cursor() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if scroll != null and selected < _rows.size() and is_instance_valid(_rows[selected].box):
		scroll.ensure_control_visible(_rows[selected].box)


## Pick an option by id ("" = walk away). The same path the keys use.
func choose(id: String) -> void:
	for i in options.size():
		if str(options[i].id) == id:
			selected = i
			break
	if panel != null:
		panel.visible = false
	var cb := on_pick
	on_pick = Callable()
	option_selected.emit(id)
	if cb.is_valid():
		cb.call(id)


## _input, not _unhandled_input: the menu is modal, and a focused Control would
## otherwise take the arrow keys for focus moves first.
func _input(event: InputEvent) -> void:
	if not is_open() or not (event is InputEventKey) or not event.pressed:
		return
	var k := (event as InputEventKey).keycode
	if k in [KEY_UP, KEY_W, KEY_DOWN, KEY_S]:     # held: keeps moving
		move(-1 if k in [KEY_UP, KEY_W] else 1)
		get_viewport().set_input_as_handled()
		return
	if event.echo:
		return
	if k == KEY_ESCAPE:
		choose("")
		get_viewport().set_input_as_handled()
	elif k in [KEY_ENTER, KEY_KP_ENTER] and selected < options.size():
		choose(str(options[selected].id))
		get_viewport().set_input_as_handled()
