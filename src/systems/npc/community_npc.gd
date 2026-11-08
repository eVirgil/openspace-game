class_name CommunityNpc
extends RefCounted
## Issue #147: player-made stall keepers. Each is one small file in
## content/community/npcs/<id>.json, made in the NPC builder (CommunityNpcPanel)
## and sent in as a pull request, so two of them never touch the same file.
##
## A file holds only what the player picks (see `blank`). At load it is built
## into a full NpcBrain card from content/core/npcs/community_card_template.json
## (`card`): the template owns the rules, the tools (talk only: no jobs, items or
## drinks), what they hear (the market) and the canned lines, so a file can never
## loosen them. The town briefing tells them where they are, like the fence.
##
## Where they stand: a marker with the merchant profile (local_merchant) and no
## vendor of its own is a free stall (`free_stalls`). Each NPC asks for one; two
## asking for the same stall are settled by id, and the later goes to the first
## stall left (`assign`). The same answer on every machine.
##
## Settings: content/core/flow/community.json. Checked by
## tests/test_community_npc.gut.gd on every file in the folder.

const CONFIG_PATH := "res://content/core/flow/community.json"
const TEMPLATE_PATH := "res://content/core/npcs/community_card_template.json"
const VOICES_PATH := "res://content/core/npcs/voice_library.json"
const BLOCKLIST_PATH := "res://content/core/llm/ip_blocklist.json"
const CORE := "res://content/core/"
const CARD_PREFIX := "community_"
const DRAFT_PREFIX := "community_draft_"
const KEYS := ["schema", "id", "author", "town", "stall", "wares", "name", "label", "look", "voice", "temperament",
	"sentences", "side", "identity", "backstory", "speech", "knows", "secret", "greetings", "lines"]

static var _cfg: Dictionary = {}
static var _tpl: Dictionary = {}
static var _block: Dictionary = {}
static var _voices: Array = []
static var _known: Dictionary = {}      ## knowable id -> their name ("Oda Vell")
static var _core_names: Array = []


# ------------------------------------------------------------------ data

static func config() -> Dictionary:
	if _cfg.is_empty():
		_cfg = _read(CONFIG_PATH)
	return _cfg


static func template() -> Dictionary:
	if _tpl.is_empty():
		_tpl = _read(TEMPLATE_PATH)
	return _tpl


static func limit(key: String) -> Dictionary:
	return config().get("limits", {}).get(key, {})


## The voices a stall keeper can have (voice_library.json).
static func voices() -> Array:
	if _voices.is_empty():
		_voices = (_read(VOICES_PATH).get("voices", {}) as Dictionary).keys()
		_voices.sort()
	return _voices


## Who they can say they know: { id: name }, the names from those characters' own cards.
static func knowable() -> Dictionary:
	if _known.is_empty():
		var k: Dictionary = template().get("knowable", {})
		for id in k:
			var c := _read(CORE + str(k[id]))
			_known[id] = str(c.get("name", c.get("label", id)))
	return _known


## Every authored character's name, which no stall keeper may take.
static func core_names() -> Array:
	if _core_names.is_empty():
		for f in DirAccess.get_files_at(CORE + "npcs"):
			if f.ends_with("_card.json"):
				var c := _read(CORE + "npcs/" + f)
				if str(c.get("name", "")) != "":
					_core_names.append(str(c.name))
	return _core_names


## A new file for the stall `stall` in `town`, filled with defaults the player edits.
static func blank(town: String, stall: String, author: String = "") -> Dictionary:
	var look: Dictionary = config().get("look", {})
	return {
		"schema": int(config().get("schema", 1)),
		"id": "",
		"author": author,
		"town": town,
		"stall": stall,
		"wares": "pottery",
		"name": "",
		"label": "",
		"look": { "head": "local", "torso": "local", "legs": "local",
			"height": float(look.get("height", {}).get("default", 1.72)),
			"build": float(look.get("build", {}).get("default", 1.0)) },
		"voice": str(config().get("default_voice", "man_casual")),
		"temperament": "friendly",
		"sentences": 2,
		"side": "neutral",
		"identity": "",
		"backstory": "",
		"speech": [],
		"knows": {},
		"secret": "",
		"greetings": { "stranger": [], "regular": [] },
		"lines": { "small_talk": [], "bye": [] },
	}


## The file's id from a name (or label): lower case, letters, digits and _.
static func slug(text: String) -> String:
	var out := ""
	for ch in text.to_lower().strip_edges():
		var c := ch.unicode_at(0)
		if (c >= 97 and c <= 122) or (c >= 48 and c <= 57):
			out += ch
		elif not out.ends_with("_") and out != "":
			out += "_"
	return out.trim_suffix("_").left(int(limit("id").get("max", 40)))


## Every file in the folder, sorted by id: [{ file, data }]. A file that does not
## parse comes back with data {} (the test names it).
static func load_files(folder: String = "") -> Array:
	var dir := folder if folder != "" else str(config().get("folder", "res://content/community/npcs"))
	var out: Array = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json"):
			out.append({ "file": f, "data": _read(dir.path_join(f)) })
	out.sort_custom(func(a, b): return str(a.data.get("id", a.file)) < str(b.data.get("id", b.file)))
	return out


## The valid NPCs whose town is `location` (a broken file is skipped, with a warning).
static func in_town(location: String, folder: String = "") -> Array:
	var out: Array = []
	var seen: Array = []
	for e in load_files(folder):
		var d: Dictionary = e.data
		if str(d.get("town", "")) != location:
			continue
		var errs := validate(d, seen)
		if not errs.is_empty():
			push_warning("CommunityNpc: %s skipped: %s" % [e.file, errs[0].text])
			continue
		seen.append(d)
		out.append(d)
	return out


# ------------------------------------------------------------------ stalls

## The town's free stalls, in the town's own marker order: markers with the
## merchant profile that no vendor of `location` (or the droid merchant) uses.
## None in a town not in community.json "towns".
static func free_stalls(town, location: String, content = null) -> Array:
	if not (config().get("towns", []) as Array).has(location):
		return []
	var profile := str(config().get("merchant_profile", "local_merchant"))
	var used := {}
	if content != null:
		for v in content.vendors_in(location):
			used[str(v.get("marker", ""))] = true
	for key in ["vendor", "club_vendor"]:
		var dv: Dictionary = DroidRoster.config().get(key, {})
		if not dv.is_empty():
			used[str(dv.get("marker", ""))] = true
	var out: Array = []
	for m in town.markers():
		if str(m.get("soldier", "")) == profile and not used.has(str(m.id)):
			out.append(str(m.id))
	return out


## Who keeps which stall: { marker: npc }. Each in id order takes the stall it asks
## for if it is still free; the rest then take the first free stalls in order. More
## NPCs than stalls: the last ones (by id) wait for a stall.
static func assign(npcs: Array, stalls: Array) -> Dictionary:
	var list := npcs.duplicate()
	list.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
	var out := {}
	var waiting: Array = []
	for n in list:
		var want := str(n.get("stall", ""))
		if stalls.has(want) and not out.has(want):
			out[want] = n
		else:
			waiting.append(n)
	for n in waiting:
		for s in stalls:
			if not out.has(s):
				out[s] = n
				break
	return out


# ------------------------------------------------------------------ the card

## The id their brain, memory and transcripts go by.
static func card_id(npc: Dictionary, draft: bool = false) -> String:
	return (DRAFT_PREFIX if draft else CARD_PREFIX) + str(npc.get("id", ""))


## What the prompt and the chat box call them: their name, or "The <label>".
static func display_name(npc: Dictionary) -> String:
	var n := str(npc.get("name", "")).strip_edges()
	return n if n != "" else "The " + str(npc.get("label", "stall keeper")).strip_edges()


## The full NpcBrain card. `draft`: a try-out in the builder (its own id).
static func card(npc: Dictionary, draft: bool = false) -> Dictionary:
	var t := template()
	var name := display_name(npc)
	var label := str(npc.get("label", "")).strip_edges()
	var wares := str(t.get("wares", {}).get(str(npc.get("wares", "")), "goods"))
	var sentences := str(t.get("sentences", {}).get(str(clampi(int(npc.get("sentences", 2)), 1, 3)), "two sentences"))
	var ctx := { "name": name, "label": label, "wares": wares, "sentences": sentences }
	var temper: Dictionary = t.get("temperaments", {}).get(str(npc.get("temperament", "")), {})
	var voice: Array = []
	for l in npc.get("speech", []):
		voice.append(str(l))
	for l in temper.get("voice", []):
		voice.append(str(l))
	if str(npc.get("name", "")).strip_edges() == "":
		voice.append("You never give your name. People call you by your trade.")
	voice.append(fill("Keep 'say' to {sentences} at most.", ctx))
	var rules: Array = []
	for r in t.get("rules", []):
		rules.append(fill(str(r), ctx))
	rules.insert(rules.size() - 1, fill(str(t.get("stall_rule", "")), ctx))
	var people: PackedStringArray = []
	var known := knowable()
	var knows: Dictionary = npc.get("knows", {})
	for id in known:
		if knows.has(id) and str(knows[id]).strip_edges() != "":
			people.append("%s: %s" % [known[id], str(knows[id]).strip_edges()])
	var actions: Array = (t.get("actions", []) as Array).duplicate()
	var secrets: Array = []
	if str(npc.get("secret", "")).strip_edges() != "":
		secrets.append({ "id": "s_" + card_id(npc, draft), "tier": "trusted", "text": str(npc.secret).strip_edges() })
		actions.insert(1, str(t.get("secret_action", "hint_secret")))
	var g: Dictionary = npc.get("greetings", {})
	var stranger: Array = _lines(g.get("stranger", []))
	if stranger.is_empty():
		stranger = (t.get("greetings_fallback", ["Yes?"]) as Array).duplicate()
	var regular: Array = _lines(g.get("regular", []))
	if regular.is_empty():
		regular = stranger
	var lines: Dictionary = npc.get("lines", {})
	var canned: Dictionary = (t.get("canned", {}) as Dictionary).duplicate(true)
	var fallback: Dictionary = t.get("lines_fallback", {})
	for k in [["default", "small_talk"], ["bye", "bye"]]:
		var got := _lines(lines.get(k[1], []))
		canned[k[0]] = got if not got.is_empty() else (fallback.get(k[1], ["Mm."]) as Array).duplicate()
	var identity := fill(str(t.get("identity", "")), ctx) + " " + str(npc.get("identity", "")).strip_edges()
	var c := {
		"id": card_id(npc, draft),
		"name": name,
		"label": label if label != "" else name,
		"note": "Community NPC (issue #147) by %s: content/community/npcs/%s.json, built by src/systems/npc/community_npc.gd from community_card_template.json." % [str(npc.get("author", "")), str(npc.get("id", ""))],
		"community": true,
		"temperature": float(temper.get("temperature", 0.7)),
		"hears": (t.get("hears", ["market"]) as Array).duplicate(),
		"voice_profile": str(npc.get("voice", config().get("default_voice", "man_casual"))),
		"actions": actions,
		"place": str(t.get("place", "")),
		"identity": identity.strip_edges(),
		"backstory": str(npc.get("backstory", "")).strip_edges(),
		"voice": voice,
		"neutrality": str(t.get("sides", {}).get(str(npc.get("side", "")), {}).get("text", "")),
		"rules": rules,
		"secrets": secrets,
		"greetings": { "stranger": stranger, "regular": regular, "trusted": regular, "confidant": regular },
		"canned": canned,
		"meta_deflections": (t.get("meta_deflections", []) as Array).duplicate(),
		"hostile_words": (t.get("hostile_words", []) as Array).duplicate(),
		"topic_words": (t.get("topic_words", {}) as Dictionary).duplicate(true),
		"mood_rules": (t.get("mood_rules", []) as Array).duplicate(true),
	}
	if not people.is_empty():
		c["people"] = ". ".join(people) + "."
	return c


static func fill(text: String, ctx: Dictionary) -> String:
	var out := text
	for k in ctx:
		out = out.replace("{%s}" % k, str(ctx[k]))
	return out


static func _lines(a) -> Array:
	var out: Array = []
	if a is Array:
		for l in a:
			if str(l).strip_edges() != "":
				out.append(str(l).strip_edges())
	return out


# ------------------------------------------------------------------ the body

## The kit pieces a stall keeper may wear: the player's builder's catalog, only
## the pieces community.json allows. { part: { piece: [colour, ...] } }
static func look_catalog() -> Dictionary:
	var allow: Array = config().get("look", {}).get("pieces", [])
	var out := {}
	var cat := PlayerOutfit.catalog()
	for part in PlayerOutfit.PARTS:
		var pieces := {}
		for piece in cat.get(part, {}):
			if allow.has(piece):
				pieces[piece] = cat[part][piece]
		out[part] = pieces
	return out


## The outfit for CharacterKit: { head, torso, legs } as "<piece>[:<colour>]".
static func outfit(npc: Dictionary) -> Dictionary:
	var look: Dictionary = npc.get("look", {})
	var o := {}
	for part in PlayerOutfit.PARTS:
		if str(look.get(part, "")) != "":
			o[part] = str(look[part])
	return o


## Their soldier profile: the merchant's, in their outfit (their size is set once
## the body stands: NpcBody.set_look_scale(scale_of)).
static func soldier(base: Dictionary, npc: Dictionary) -> Dictionary:
	var s := base.duplicate(true)
	s["archetype"] = str(config().get("look", {}).get("archetype", "local"))
	s["outfit"] = outfit(npc)
	return s


static func height(npc: Dictionary) -> float:
	var h: Dictionary = config().get("look", {}).get("height", {})
	return clampf(float(npc.get("look", {}).get("height", h.get("default", 1.72))), float(h.get("min", 1.6)), float(h.get("max", 1.9)))


static func build(npc: Dictionary) -> float:
	var b: Dictionary = config().get("look", {}).get("build", {})
	return clampf(float(npc.get("look", {}).get("build", b.get("default", 1.0))), float(b.get("min", 0.9)), float(b.get("max", 1.15)))


## Their look's size: height over the local body's, widened or slimmed by build.
static func scale_of(npc: Dictionary) -> Vector3:
	var y := height(npc) / float(config().get("base_height", 1.72))
	var k := build(npc)
	return Vector3(y * k, y, y * k)


# ------------------------------------------------------------------ checks

## Everything wrong with a file, in the builder's order: [{ field, text }]. []
## is good to send. `others`: the NPCs already in (their names and ids are taken).
static func validate(npc: Dictionary, others: Array = []) -> Array:
	var errs: Array = []
	var add := func(field: String, text: String) -> void:
		errs.append({ "field": field, "text": text })
	var t := template()
	if int(npc.get("schema", 0)) != int(config().get("schema", 1)):
		add.call("schema", "Made by a different version of the builder.")
	var id := str(npc.get("id", ""))
	var lid := limit("id")
	if id.length() < int(lid.get("min", 3)) or id.length() > int(lid.get("max", 40)) or slug(id) != id:
		add.call("id", "Needs a name or label of at least 3 letters.")
	for o in others:
		if str(o.get("id", "")) == id and o != npc:
			add.call("id", "Another stall keeper already has the id '%s'. Change the name." % id)
	_text(add, npc, "author", "Your handle", true)
	if not RegEx.create_from_string("^[A-Za-z0-9-]*$").search(str(npc.get("author", ""))):
		add.call("author", "Your handle: letters, digits and - only (your GitHub name).")
	if str(npc.get("town", "")) == "":
		add.call("town", "No town.")
	if str(npc.get("stall", "")) == "":
		add.call("stall", "No stall.")
	if not t.get("wares", {}).has(str(npc.get("wares", ""))):
		add.call("wares", "Pick what is on the counter.")
	var name := str(npc.get("name", "")).strip_edges()
	if name != "":
		_text(add, npc, "name", "The name", true)
		if not RegEx.create_from_string("^[A-Za-z][A-Za-z '\\-]*$").search(name):
			add.call("name", "The name: letters, spaces, ' and - only.")
		if not name_ok(name):
			add.call("name", "That name is not allowed here. Try another.")
		for n in core_names():
			if NameEngine.normalize(n) == NameEngine.normalize(name):
				add.call("name", "%s is already someone in the game." % n)
		for o in others:
			if o != npc and NameEngine.normalize(str(o.get("name", ""))) == NameEngine.normalize(name):
				add.call("name", "Another stall keeper is already called %s." % name)
	_text(add, npc, "label", "What people call them", true)
	if str(npc.get("label", "")) != "" and not name_ok(str(npc.label)):
		add.call("label", "That label is not allowed here. Try another.")
	var look: Dictionary = npc.get("look", {})
	var cat := look_catalog()
	for part in PlayerOutfit.PARTS:
		var pc := PlayerOutfit.split(str(look.get(part, "")))
		var pieces: Dictionary = cat.get(part, {})
		if not pieces.has(pc[0]) or (pc[1] != "" and not (pieces[pc[0]] as Array).has(pc[1])):
			add.call("look", "Pick a %s." % ("head" if part == "head" else "upper body" if part == "torso" else "lower body"))
	if not voices().has(str(npc.get("voice", ""))):
		add.call("voice", "Pick a voice.")
	if not t.get("temperaments", {}).has(str(npc.get("temperament", ""))):
		add.call("temperament", "Pick a temperament.")
	if int(npc.get("sentences", 0)) < 1 or int(npc.get("sentences", 0)) > 3:
		add.call("sentences", "They say 1, 2 or 3 sentences at a time.")
	if not t.get("sides", {}).has(str(npc.get("side", ""))):
		add.call("side", "Pick their side in the war.")
	_text(add, npc, "identity", "Who they are", true)
	_text(add, npc, "backstory", "Their backstory", false)
	_list(add, npc.get("speech", []), "speech", "How they speak")
	var knows = npc.get("knows", {})
	if not knows is Dictionary:
		add.call("knows", "Who they know is broken.")
	else:
		for k in knows:
			if not knowable().has(k):
				add.call("knows", "They can not know '%s'." % k)
			elif str(knows[k]).length() > int(limit("knows").get("max", 140)):
				add.call("knows", "What they think of %s is too long." % knowable()[k])
	if str(npc.get("secret", "")).length() > int(limit("secret").get("max", 240)):
		add.call("secret", "The secret is too long.")
	var g: Dictionary = npc.get("greetings", {}) if npc.get("greetings", {}) is Dictionary else {}
	_list(add, g.get("stranger", []), "greetings_stranger", "Greetings for a stranger")
	_list(add, g.get("regular", []), "greetings_regular", "Greetings for a regular")
	var l: Dictionary = npc.get("lines", {}) if npc.get("lines", {}) is Dictionary else {}
	_list(add, l.get("small_talk", []), "small_talk", "Small talk")
	_list(add, l.get("bye", []), "bye", "Goodbyes")
	for k in npc:
		if not KEYS.has(k):
			add.call("schema", "Unknown field '%s'." % k)
	var hits := ip_hits(all_text(npc))
	if not hits.is_empty():
		add.call("text", "Words from another franchise are not allowed: %s." % ", ".join(PackedStringArray(hits)))
	return errs


## A text field's length (limits[field]); `need`: it may not be empty.
static func _text(add: Callable, npc: Dictionary, field: String, what: String, need: bool) -> void:
	var s := str(npc.get(field, "")).strip_edges()
	var lim := limit(field)
	var lo := int(lim.get("min", 1 if need else 0))
	if s.length() < lo:
		add.call(field, "%s: at least %d characters." % [what, lo] if lo > 1 else "%s: fill it in." % what)
	elif s.length() > int(lim.get("max", 300)):
		add.call(field, "%s: at most %d characters (now %d)." % [what, int(lim.max), s.length()])


static func _list(add: Callable, a, field: String, what: String) -> void:
	var lim := limit(field)
	var lines := _lines(a)
	if not a is Array:
		add.call(field, "%s is broken." % what)
		return
	if lines.size() < int(lim.get("min_lines", 0)):
		add.call(field, "%s: at least %d." % [what, int(lim.min_lines)])
	elif lines.size() > int(lim.get("max_lines", 5)):
		add.call(field, "%s: at most %d." % [what, int(lim.max_lines)])
	for l in lines:
		if str(l).length() > int(lim.get("max", 140)):
			add.call(field, "%s: each line at most %d characters." % [what, int(lim.max)])
			return


## A name or label passes the name book's own checks (its deny lists and the
## franchise names, as whole words).
static func name_ok(text: String) -> bool:
	var b := _blocklist()
	var low := text.to_lower()
	var squashed := NameEngine.normalize(text)
	var words := low.replace("-", " ").replace("'", " ").split(" ", false)
	for w in b.get("name_terms", []):
		if words.has(str(w)) or squashed == NameEngine.normalize(str(w)):
			return false
	if WorldState.names != null and WorldState.names.engine != null:
		return WorldState.names.engine.acceptable(text, { "min_len": 2, "max_len": 40 })
	return true


## The franchise terms in `text` (the shared IP blocklist, as test_ip_neutral reads it).
static func ip_hits(text: String) -> Array:
	var low := text.to_lower()
	var out: Array = []
	for term in _blocklist().get("terms", []):
		if low.contains(str(term).to_lower()):
			out.append(str(term))
	return out


static func all_text(npc: Dictionary) -> String:
	return JSON.stringify(npc)


static func _blocklist() -> Dictionary:
	if _block.is_empty():
		_block = _read(BLOCKLIST_PATH)
	return _block


# ------------------------------------------------------------------ send

## The file as it goes in the repo: the fields in KEYS order, two-space indents.
static func to_json(npc: Dictionary) -> String:
	var ordered := {}
	for k in KEYS:
		if npc.has(k):
			ordered[k] = npc[k]
	for k in ["schema", "sentences"]:            # whole numbers, not 1.0 (JSON reads every number as a float)
		if ordered.has(k):
			ordered[k] = int(ordered[k])
	if ordered.get("look") is Dictionary:
		var look: Dictionary = (ordered.look as Dictionary).duplicate()
		for k in ["height", "build"]:
			if look.has(k):
				look[k] = snappedf(float(look[k]), 0.01)
		ordered["look"] = look
	return JSON.stringify(ordered, "  ", false) + "\n"


static func repo_path(npc: Dictionary) -> String:
	return "%s/%s.json" % [str(config().get("repo_folder", "content/community/npcs")), str(npc.get("id", ""))]


## GitHub's new-file page with the path and the file filled in: { url, full }.
## Too long for a link: the page with the path only (full false), and the
## caller puts the file on the clipboard to paste.
static func pr_url(npc: Dictionary) -> Dictionary:
	var c := config()
	var repo := str(c.get("repo", ""))
	var branch := str(c.get("branch", "main"))
	var path := repo_path(npc)
	var url := str(c.get("new_file_url", "")) % [repo, branch, path.uri_encode(), to_json(npc).uri_encode()]
	if url.length() <= int(c.get("max_url_chars", 7500)):
		return { "url": url, "full": true }
	return { "url": str(c.get("blank_file_url", "")) % [repo, branch, path.uri_encode()], "full": false }


## Write the file where the player can find it: the Desktop (or community.json's
## export_dir). Returns the path written, "" if it could not be.
static func export_file(npc: Dictionary) -> String:
	var where := str(config().get("export_dir", "desktop"))
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP) if where == "desktop" else ProjectSettings.globalize_path(where)
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		dir = ProjectSettings.globalize_path("user://community_npcs")
		DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(str(npc.get("id", "npc")) + ".json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(to_json(npc))
	f.close()
	return path


# ------------------------------------------------------------------ drafts

static func drafts_dir() -> String:
	return str(config().get("drafts", "user://community_npcs/drafts"))


## The draft kept for a stall: "<town>__<stall>.json", so coming back to the same
## stall carries on where you left off.
static func draft_path(town: String, stall: String) -> String:
	return drafts_dir().path_join("%s__%s.json" % [town, stall])


static func save_draft(npc: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(drafts_dir())
	var f := FileAccess.open(draft_path(str(npc.get("town", "")), str(npc.get("stall", ""))), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(npc, "  ", false))


static func load_draft(town: String, stall: String) -> Dictionary:
	return _read(draft_path(town, stall))


## The handle the player last typed, so the next stall keeper starts with it.
static func saved_author() -> String:
	return str(_read(drafts_dir().get_base_dir().path_join("me.json")).get("author", ""))


static func save_author(author: String) -> void:
	DirAccess.make_dir_recursive_absolute(drafts_dir().get_base_dir())
	var f := FileAccess.open(drafts_dir().get_base_dir().path_join("me.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({ "author": author }))


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}
