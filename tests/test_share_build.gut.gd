extends GutTest
## Issue #533: the share builds carry only what the game loads. Raw Hyper3D
## exports live in `source/` folders (tool input for tools/look/prep_*.gd) and
## review stills live in docs/; neither ships. A `.gdignore` keeps each source
## folder out of the import and the export, and both presets exclude docs/ and
## any source folder as a second guard. The game must never load from either.

const PRESETS := "res://export_presets.cfg"
const MUST_EXCLUDE := ["docs/*", "assets/*/source/*"]

## Keys whose path is tool input (read by the prep tools from a checkout), so
## it may point into a source/ folder. Any other path in the data may not.
const TOOL_KEYS := ["source"]
const TOOL_PARENTS := ["emission"]

## Game code and data: what runs in a share build.
const GAME_DIRS := ["res://src/", "res://scenes/", "res://content/"]


func _walk(dir: String, out: PackedStringArray, dirs_only := false) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if not name.begins_with("."):
			var full := dir + name
			if da.current_is_dir():
				if dirs_only:
					out.append(full)
				_walk(full + "/", out, dirs_only)
			elif not dirs_only:
				out.append(full)
		name = da.get_next()
	da.list_dir_end()


func test_every_source_folder_is_ignored_by_godot() -> void:
	var dirs := PackedStringArray()
	_walk("res://assets/", dirs, true)
	var sources := 0
	for d in dirs:
		if d.get_file() != "source":
			continue
		sources += 1
		assert_true(FileAccess.file_exists(d + "/.gdignore"),
			d + " needs a .gdignore, or its raw models are imported and shipped")
	assert_gt(sources, 0, "the source folders were found")


func test_both_presets_exclude_docs_and_sources() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(PRESETS), OK)
	var presets := 0
	for section in cfg.get_sections():
		if not cfg.has_section_key(section, "exclude_filter"):
			continue
		presets += 1
		var filters := PackedStringArray()
		for f in str(cfg.get_value(section, "exclude_filter")).split(","):
			filters.append(f.strip_edges())
		for want in MUST_EXCLUDE:
			assert_true(filters.has(want), "%s excludes %s" % [cfg.get_value(section, "name"), want])
	assert_eq(presets, 2, "the Windows and macOS share presets")


## The other way round: a data file Godot does not pack by itself (not a
## resource, nothing imported from it, e.g. Oda's persona .txt) is only in a
## build when the preset's include_filter names it. V1.6.3 left the persona out,
## and the cantina owner's AI talked without it.
func test_both_presets_ship_every_plain_content_file() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(PRESETS), OK)
	var files := PackedStringArray()
	_walk("res://content/", files)
	var plain := PackedStringArray()
	for path in files:
		# A resource (the .json data too) or an imported file ships on its own.
		if path.get_extension() in ["import", "uid"] or ResourceLoader.exists(path) or FileAccess.file_exists(path + ".import"):
			continue
		plain.append(path.trim_prefix("res://"))
	assert_true(plain.has("content/core/dialogue/cantina_owner_persona.txt"), "the persona text was found")
	var presets := 0
	for section in cfg.get_sections():
		if not cfg.has_section_key(section, "include_filter"):
			continue
		presets += 1
		var filters := PackedStringArray()
		for f in str(cfg.get_value(section, "include_filter")).split(","):
			if f.strip_edges() != "":
				filters.append(f.strip_edges())
		for path in plain:
			var shipped := false
			for f in filters:
				shipped = shipped or path.matchn(f)
			assert_true(shipped, "%s ships %s (include_filter)" % [cfg.get_value(section, "name"), path])
	assert_eq(presets, 2, "the Windows and macOS share presets")


## Every "res://..." string in a JSON value, with its key and its parent's key.
func _paths(v, key: String, parent: String, out: Array) -> void:
	if v is Dictionary:
		for k in v:
			_paths(v[k], str(k), key, out)
	elif v is Array:
		for item in v:
			_paths(item, key, parent, out)
	elif v is String and v.begins_with("res://"):
		out.append([v, key, parent])


func test_the_game_loads_nothing_from_a_source_folder_or_docs() -> void:
	var files := PackedStringArray()
	for root in GAME_DIRS:
		_walk(root, files)
	var offenders := PackedStringArray()
	var checked := 0
	for path in files:
		var ext := path.get_extension()
		if ext == "json":
			var data = JSON.parse_string(FileAccess.get_file_as_string(path))
			var found := []
			_paths(data, "", "", found)
			for p in found:
				checked += 1
				var res: String = p[0]
				var tool_input: bool = TOOL_KEYS.has(p[1]) or TOOL_PARENTS.has(p[2])
				if res.contains("/source/") and not tool_input:
					offenders.append("%s: \"%s\" = %s" % [path, p[1], res])
				if res.begins_with("res://docs/"):
					offenders.append("%s: \"%s\" = %s" % [path, p[1], res])
		elif ext in ["gd", "tscn", "tres"]:
			var text := FileAccess.get_file_as_string(path)
			for line in text.split("\n"):
				if (line.contains("res://assets/") and line.contains("/source/")) \
						or line.contains("res://docs/"):
					offenders.append(path + ": " + line.strip_edges())
	assert_gt(checked, 100, "the content's paths were read")
	assert_eq(offenders.size(), 0,
		"loaded from a folder the share builds leave out: " + str(offenders))
