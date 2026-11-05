extends GutTest
## M0: IP-neutrality guard. Scans every file in the repo for franchise names.
## None may appear in code, class names, file names, docs or the data layer
## (README's rule). Generic terms only. This test failing is a hard block on
## the merge. Commit messages are checked by scripts/check_commit_messages.sh.

## M12: the list lives in data so the cantina owner's runtime output filter and this
## scan share one source of truth. That file is the list itself, so it is exempt.
const BLOCKLIST := "res://content/core/llm/ip_blocklist.json"
var BANNED: Array = []

## Files that quote the list on purpose. Nothing else is exempt.
const SELF := "res://tests/test_ip_neutral.gut.gd"
const ALLOW := [SELF, BLOCKLIST]

## Folders that are not the repo's own words: the engine's cache, git, the GUT
## addon, ignored build and test output, and other checkouts of this repo
## (agent worktrees live under .claude/ in the main checkout).
const SKIP_DIRS := [
	"res://.git/",
	"res://.godot/",
	"res://addons/",
	"res://test_results/",
	"res://builds/",
	"res://rec/",
	"res://models/",
	"res://runtime/",
	"res://.claude/worktrees/",
]

## Text files whose contents are read. Every other file (models, sounds,
## textures) is checked by name only.
const TEXT_EXTS := [
	"gd", "gdshader", "gdshaderinc", "json", "txt", "tscn", "tres", "cfg",
	"godot", "md", "html", "py", "sh", "svg",
]

var _files := PackedStringArray()


func before_all() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(BLOCKLIST))
	BANNED = d.get("terms", []) if d is Dictionary else []
	_files.clear()
	_walk("res://", _files)


func _walk(dir: String, out: PackedStringArray) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.include_hidden = true
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if name != "." and name != "..":
			var full := dir + name
			if da.current_is_dir():
				if not SKIP_DIRS.has(full + "/"):
					_walk(full + "/", out)
			else:
				out.append(full)
		name = da.get_next()
	da.list_dir_end()


func _hits(text: String) -> PackedStringArray:
	var found := PackedStringArray()
	var low := text.to_lower()
	for banned in BANNED:
		if low.contains(banned):
			found.append(banned)
	return found


func test_scan_covers_the_whole_repo() -> void:
	# The folders the old scan missed are in: the docs, the root markdown, the
	# skills, the tools, shaders and the project file.
	for want in ["res://README.md", "res://CHANGELOG.md", "res://project.godot",
			"res://export_presets.cfg", "res://.claude/skills/write-issue/SKILL.md"]:
		assert_true(_files.has(want), "scanned: " + want)
	var shaders := 0
	var docs := 0
	var tools := 0
	for path in _files:
		if path.get_extension() == "gdshader":
			shaders += 1
		if path.begins_with("res://docs/"):
			docs += 1
		if path.begins_with("res://tools/"):
			tools += 1
	assert_gt(shaders, 0, "shaders are scanned")
	assert_gt(docs, 0, "docs are scanned")
	assert_gt(tools, 0, "tools are scanned")
	for path in _files:
		for skip in SKIP_DIRS:
			assert_false(path.begins_with(skip), "skipped folder walked: " + path)


func test_no_franchise_names_in_any_file() -> void:
	var offenders := PackedStringArray()
	for path in _files:
		if ALLOW.has(path) or not TEXT_EXTS.has(path.get_extension()):
			continue
		for banned in _hits(FileAccess.get_file_as_string(path)):
			offenders.append(path + " :: " + banned)
	assert_eq(offenders.size(), 0, "franchise names found: " + str(offenders))


func test_no_franchise_names_in_file_names() -> void:
	var offenders := PackedStringArray()
	for path in _files:
		for banned in _hits(path.trim_prefix("res://")):
			offenders.append(path + " :: " + banned)
	assert_eq(offenders.size(), 0, "franchise names in file names: " + str(offenders))


func test_the_scan_catches_a_planted_name() -> void:
	# The check itself works: a term from the list, in any case, is found.
	assert_gt(BANNED.size(), 0)
	var term: String = BANNED[0]
	assert_eq(_hits("a line with " + term.to_upper() + " in it").size(), 1)
	assert_eq(_hits("a clean line").size(), 0)


func test_blocklist_loaded() -> void:
	assert_gt(BANNED.size(), 10, "the IP blocklist must load from data")


func test_content_files_match_manifest() -> void:
	# Every id in the manifest must resolve to a file on disk.
	var content = preload("res://src/systems/dataload/core_content.gd").new()
	content.load_from()
	for id in content.weapons:
		var f := FileAccess.file_exists("res://content/core/weapons/" + str(id) + ".json")
		assert_true(f, "weapon file exists: " + str(id))
