extends GutTest
## Issue #547: the docs AGENTS.md sends every builder to first stay true.
## PLAN.md lists each milestone once, KNOWN_ISSUES.md holds only current notes
## (replaced ones go to docs/KNOWN_ISSUES_ARCHIVE.md), and the render rules
## page exists and is linked where builders start.

const PLAN := "res://PLAN.md"
const KNOWN := "res://KNOWN_ISSUES.md"
const ARCHIVE := "res://docs/KNOWN_ISSUES_ARCHIVE.md"
const RENDER_RULES := "res://docs/RENDER_RULES.md"


func _read(path: String) -> String:
	assert_true(FileAccess.file_exists(path), "exists: " + path)
	return FileAccess.get_file_as_string(path)


## The id in the first cell of each table row ("| M15 | ..."), header rows out.
func _plan_ids(text: String) -> PackedStringArray:
	var ids := PackedStringArray()
	for line in text.split("\n"):
		if not line.begins_with("|"):
			continue
		var cells := line.split("|")
		if cells.size() < 3:
			continue
		var id := cells[1].strip_edges()
		if id == "" or id == "#" or id.begins_with("-"):
			continue
		ids.append(id)
	return ids


func test_plan_lists_each_milestone_once() -> void:
	var ids := _plan_ids(_read(PLAN))
	assert_gt(ids.size(), 10, "PLAN.md's table was read")
	var seen := {}
	var twice := PackedStringArray()
	for id in ids:
		if seen.has(id):
			twice.append(id)
		seen[id] = true
	assert_eq(twice.size(), 0, "PLAN.md lists these ids more than once: " + str(twice))


func test_plan_row_check_catches_a_duplicate() -> void:
	var ids := _plan_ids("| # | M | D | S |\n|---|---|---|---|\n| M1 | a | b | DONE |\n| M1 | a | b | WIP |\n")
	assert_eq(ids, PackedStringArray(["M1", "M1"]))


func test_known_issues_holds_only_current_notes() -> void:
	var text := _read(KNOWN).to_lower()
	assert_false(text.contains("superseded"),
		"a replaced section in KNOWN_ISSUES.md belongs in docs/KNOWN_ISSUES_ARCHIVE.md")
	assert_true(FileAccess.file_exists(ARCHIVE), "the archive exists")


func test_render_rules_are_linked_where_builders_start() -> void:
	assert_true(FileAccess.file_exists(RENDER_RULES), "docs/RENDER_RULES.md exists")
	assert_true(_read("res://AGENTS.md").contains("docs/RENDER_RULES.md"), "AGENTS.md links it")
	assert_true(_read("res://.claude/skills/write-issue/SKILL.md").contains("docs/RENDER_RULES.md"),
		"the write-issue skill links it")
