class_name PlayerOutfit
extends RefCounted
## Issue #48: the outfit the player picked in the character builder (F11,
## Character), kept per save (SaveSlots.outfit_path: a story and a free roam
## save each have their own) and worn by PlayerAvatar.
##
## An outfit is CharacterKit's: { part: "<piece>" or "<piece>:<colour>" }, e.g.
## { "head": "player", "torso": "guard:gunmetal", "legs": "player:rust" }.
##
## What can be picked comes from the player's kit model (characters.json,
## player_smuggler.model, "pieces": true): every mesh "<piece>_<part>" in its scene
## is a piece of that part, and every texture beside the "colors" pattern is a
## colour of it: "<piece>_<part>_<colour>" when the part has its own texture (the
## player's head), else "<piece>_<colour>". No colour is the piece's own texture.
##
## Issue #200: a story save is locked to the smuggler. Only the archetype's own
## pieces (its model's "parts") can be worn there; the colours stay free.
##
## In free roam a piece in the model's "locked" ({ piece: item id }) can not be
## worn until the player has had that item (the guard's armour: the quantonium
## armour). Then every part and colour of it is open, for good (a flag), even
## once the item is sold.

const ARCHETYPE := "player_smuggler"
const PARTS := ["head", "torso", "legs"]
const UNLOCK_FLAG := "outfit_unlocked_%s"   ## WorldState flag: a locked piece the player has opened
static var save_path := ""         ## "" = the save being played's (SaveSlots); tests point this elsewhere
static var _catalog: Dictionary = {}


## { part: { piece: [colour, ...] } }, the archetype's own pieces first.
static func catalog() -> Dictionary:
	if not _catalog.is_empty():
		return _catalog
	var model := _model()
	var scene_path := str(model.get("scene", ""))
	if not bool(model.get("pieces", false)) or not ResourceLoader.exists(scene_path):
		return {}
	var scene: Node = (load(scene_path) as PackedScene).instantiate()
	var pattern := str(model.get("colors", ""))
	var files := ResourceLoader.list_directory(pattern.get_base_dir()) if pattern.contains("%s") else PackedStringArray()
	for part in PARTS:
		var names: Array = []
		for choice in model.get("parts", {}).get(part, []):
			names.append(split(str(choice))[0])
		for mi in scene.find_children("*_" + part, "MeshInstance3D", true, false):
			var piece := String(mi.name).trim_suffix("_" + part)
			if not names.has(piece):
				names.append(piece)
		var pieces := {}
		for piece in names:
			if scene.find_child("%s_%s" % [piece, part], true, false) != null:
				pieces[piece] = _colors(files, pattern.get_file(), piece, part)
		_catalog[part] = pieces
	scene.free()
	return _catalog


## What can be picked in this save: the catalog without the pieces still locked,
## or in a story save only the archetype's own pieces. `locks` false leaves the
## locks out (another player's outfit, heard over the network: theirs to open).
static func pickable(locks := true) -> Dictionary:
	if not WorldState.story_mode() and not locks:
		return catalog()
	var model := _model()
	var own: Dictionary = model.get("parts", {})
	var out := {}
	for part in catalog():
		var names: Array = (own.get(part, []) as Array).map(func(c): return split(str(c))[0])
		var pieces := {}
		for piece in catalog()[part]:
			if (names.has(piece) if WorldState.story_mode() else unlocked(piece, model)):
				pieces[piece] = catalog()[part][piece]
		out[part] = pieces
	return out


## A piece can be worn in free roam: not locked, or its item had (now or before).
## Having the item opens it for good (UNLOCK_FLAG).
static func unlocked(piece: String, model: Dictionary = {}) -> bool:
	if model.is_empty():
		model = _model()
	var item := str(model.get("locked", {}).get(piece, ""))
	if item == "" or WorldState.has_flag(UNLOCK_FLAG % piece):
		return true
	if WorldState.inventory == null or not WorldState.inventory.has(item):
		return false
	WorldState.set_flag(UNLOCK_FLAG % piece)
	return true


## The items that would open the pieces still locked in this save (none in a
## story save: its own lock is the archetype's parts).
static func locked_items() -> Array:
	var out: Array = []
	if WorldState.story_mode():
		return out
	var model := _model()
	for piece in model.get("locked", {}):
		var item := str(model.locked[piece])
		if not unlocked(piece, model) and not out.has(item):
			out.append(item)
	return out


static func _model() -> Dictionary:
	return CharacterKit._read_json(CharacterKit.PALETTES_PATH).get("archetypes", {}).get(ARCHETYPE, {}).get("model", {})


## The colours of a piece's part, from the texture file names (as _wear_outfit
## looks them up: the part's own texture first, else the piece's).
static func _colors(files: PackedStringArray, file_pattern: String, piece: String, part: String) -> Array:
	var head := file_pattern.get_slice("%s", 0)
	var tail := file_pattern.get_slice("%s", 1)
	var own: Array = []
	var shared: Array = []
	for f in files:
		if not (f.begins_with(head) and f.ends_with(tail)):
			continue
		var stem := f.trim_prefix(head).trim_suffix(tail)
		if stem.begins_with("%s_%s_" % [piece, part]):
			own.append(stem.trim_prefix("%s_%s_" % [piece, part]))
		elif stem.begins_with(piece + "_") and not stem.trim_prefix(piece + "_").contains("_"):
			shared.append(stem.trim_prefix(piece + "_"))
	var out := own if not own.is_empty() else shared
	out.sort()
	return out


## "<piece>:<colour>" -> [piece, colour]; no colour is "".
static func split(choice: String) -> Array:
	var pc := choice.split(":", true, 1)
	return [pc[0], pc[1] if pc.size() == 2 else ""]


static func choice(piece: String, colour: String) -> String:
	return piece if colour == "" else "%s:%s" % [piece, colour]


## Only the parts whose piece and colour can be picked (pickable); the rest are
## left out, so the kit gives them the archetype's default.
static func sanitize(outfit: Dictionary, locks := true) -> Dictionary:
	var cat := pickable(locks)
	var out := {}
	for part in PARTS:
		if not outfit.has(part):
			continue
		var pc := split(str(outfit[part]))
		var pieces: Dictionary = cat.get(part, {})
		if pieces.has(pc[0]) and (pc[1] == "" or (pieces[pc[0]] as Array).has(pc[1])):
			out[part] = choice(pc[0], pc[1])
	return out


static func path() -> String:
	return save_path if save_path != "" else SaveSlots.outfit_path()


## The saved outfit, or {} (the archetype's default) when there is none.
static func load_outfit() -> Dictionary:
	if not FileAccess.file_exists(path()):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path()))
	return sanitize(d) if d is Dictionary else {}


static func save_outfit(outfit: Dictionary) -> bool:
	var f := FileAccess.open(path(), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(sanitize(outfit), "  "))
	return true
