class_name DrawDistance
extends Node
## Less to draw the further it is from the camera: the ground-level partner of
## AltitudeDetail. Small things stop being drawn first: a goggle strap at 120 m,
## a crate at 220 m, a 5 m awning at 1500 m; buildings and hulls always draw.
## Lights fade out the same way. The scene hands it the roots of the systems it
## builds (watch()), each with a rule; anything built under a root later (a pack
## that walks in, a camp rebuilt, a body woken) gets its range when it enters the
## tree. Anything that walks under a root (a CharacterBody3D: NPCs, droids,
## animals) takes the "person" rule, so a crowd is drawn as far as it is awake.
##
## Rules are data: the "draw_distance" block of content/look/world.json. A mesh or
## light that already set its own range (the barge, the wreck field, the camps'
## canisters) keeps it. Pure maths in end_for() and light_begin_for(), for tests.

const LOOK_PATH := "res://content/look/world.json"
const PERSON := "person"

var rules := {}                      ## name -> { sizes: [[under_m, end_m], ...], light_m }
var fade_margin := 0.1               ## of the end distance, faded rather than cut
var light_fade_m := 20.0
var reach_x := 4.0                   ## a light reaching far fades from reach_x times its reach
var applied := 0                     ## meshes and lights given a range so far (tests, traces)
var _roots := {}                     ## instance id -> rule name
var _queue: Array = []


func _init() -> void:
	name = "DrawDistance"


func setup(cfg: Dictionary = {}) -> void:
	if cfg.is_empty():
		cfg = ItemKit._read_json(LOOK_PATH).get("draw_distance", {})
	fade_margin = float(cfg.get("fade_margin", fade_margin))
	light_fade_m = float(cfg.get("light_fade_m", light_fade_m))
	reach_x = float(cfg.get("reach_x", reach_x))
	rules = cfg.get("rules", {})


func _ready() -> void:
	get_tree().node_added.connect(_on_added)
	set_process(false)


## Give every mesh and light under `nodes` its range by `rule`, now and as more
## is built under them. Nulls and roots already watched are skipped.
func watch(rule: String, nodes: Array) -> void:
	if not rules.has(rule):
		return
	for n in nodes:
		if n == null or not is_instance_valid(n) or _roots.has(n.get_instance_id()):
			continue
		_roots[n.get_instance_id()] = rule
		var stack: Array = [n]
		while not stack.is_empty():
			var c: Node = stack.pop_back()
			stack.append_array(c.get_children())
			_apply(c)


## Where a mesh `size` metres corner to corner stops being drawn under `rule`
## (0 = always drawn).
static func end_for(rule: Dictionary, size: float) -> float:
	for s in rule.get("sizes", []):
		if size < float(s[0]):
			return float(s[1])
	return 0.0


## Where a light reaching `reach` metres starts to fade under `rule`.
func light_begin_for(rule: Dictionary, reach: float) -> float:
	return maxf(float(rule.get("light_m", 90.0)), reach * reach_x)


# Meshes are often given their mesh just after add_child, so wait a frame.
func _on_added(n: Node) -> void:
	if n is GeometryInstance3D or (n is Light3D and not n is DirectionalLight3D):
		_queue.append(n)
		set_process(true)


func _process(_dt: float) -> void:
	var q := _queue
	_queue = []
	for n in q:
		if is_instance_valid(n) and n.is_inside_tree():
			_apply(n)
	set_process(not _queue.is_empty())


## The rule of the nearest watched root above `n` ("" = none), or "person" when
## something that walks stands between them.
func rule_of(n: Node) -> String:
	var walks := false
	var p := n
	while p != null:
		var r: String = _roots.get(p.get_instance_id(), "")
		if r != "":
			return PERSON if walks and rules.has(PERSON) else r
		if p is CharacterBody3D:
			walks = true
		p = p.get_parent()
	return ""


func _apply(n: Node) -> void:
	if not (n is GeometryInstance3D or n is Light3D) or n is DirectionalLight3D:
		return
	var name_ := rule_of(n)
	if name_ == "":
		return
	var rule: Dictionary = rules[name_]
	if n is Light3D:
		var l := n as Light3D
		if l.distance_fade_enabled:
			return
		var reach := (l as OmniLight3D).omni_range if l is OmniLight3D else ((l as SpotLight3D).spot_range if l is SpotLight3D else 0.0)
		l.distance_fade_enabled = true
		l.distance_fade_begin = light_begin_for(rule, reach)
		l.distance_fade_length = light_fade_m
		applied += 1
		return
	var gi := n as GeometryInstance3D
	if gi.visibility_range_end > 0.0 or gi.visibility_range_begin > 0.0:
		return
	var box := gi.get_aabb()
	if box.size == Vector3.ZERO:
		return                       # no mesh yet: nothing to measure
	var end := end_for(rule, (gi.global_transform * box).size.length() if gi.is_inside_tree() else box.size.length())
	if end <= 0.0:
		return
	gi.visibility_range_end = end
	gi.visibility_range_end_margin = end * fade_margin
	gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	applied += 1
