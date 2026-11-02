class_name ObjectiveHud
extends CanvasLayer
## The objective pointer: what to do next (Objective.current) on a line under
## the banner's left end, with how far it is, an arrow before it turning towards
## it, and a diamond over the place itself while it is on screen. Left, not
## centred: the middle of the top is where arrival titles and toasts go.
##
## It only reads. `demo` (town_demo.gd) turns the objective's target word into a
## place: live bodies, town markers, the smuggling drop (near it, issue #251),
## the range, the pit, the desert outposts, the crashed cruiser ("wreck", issue #205),
## and a waypoint set on the F11 map (a ground spot, or another planet's port).
##
## Quest news (QuestNews: a quest or job started, cargo found, a target killed)
## goes up big in the upper middle, with a sound: the QuestBanner it carries.

const REFRESH := 0.25                 ## seconds between re-reading the objective
const AMBER := Color("#e0a050")
const INK := Color(0.95, 0.92, 0.85, 0.95)
const TOP := 48.0                     ## below RetroHud's 40 px banner
const EDGE := 36.0                    ## the diamond stays this far inside the screen
const LEFT := 26.0                    ## the arrow's centre from the left edge; the text starts after it

var demo                              ## town_demo.gd
var label: Label
var marks: Control                    ## draws the arrow and the diamond
var objective: Dictionary = {}        ## the last Objective.current()
var target_pos := Vector3.INF         ## where it points, INF = nowhere (text only)
var banner: QuestBanner               ## quest news, big, one at a time
var _left := 0.0


func _init() -> void:
	name = "ObjectiveHud"
	layer = 4


func _ready() -> void:
	marks = Control.new()
	marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marks.draw.connect(_draw_marks)
	add_child(marks)
	label = Label.new()
	label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	label.offset_left = LEFT + 20.0
	label.offset_right = LEFT + 760.0
	label.offset_top = TOP
	label.offset_bottom = TOP + 28
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", INK)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	banner = QuestBanner.new()
	add_child(banner)
	refresh()


func _process(dt: float) -> void:
	_left -= dt
	if _left <= 0.0:
		_left = REFRESH
		refresh()
	elif target_pos != Vector3.INF:
		label.text = text_line()       # the distance changes every frame
	marks.queue_redraw()


## Re-read the objective and find its place. A waypoint set on the F11 map
## clears itself once the player is there.
func refresh() -> void:
	objective = Objective.current()
	target_pos = where(str(objective.get("target", "")))
	if objective.get("map", false) and target_pos != Vector3.INF:
		var d := distance()
		if d >= 0.0 and d < float(objective.get("arrive", 30.0)):
			GlobeMap.clear_waypoint()
			objective = Objective.current()
			target_pos = where(str(objective.get("target", "")))
	label.text = text_line()
	label.visible = not objective.is_empty()


## "Find Oda Vell at the cantina   84 m"
func text_line() -> String:
	if objective.is_empty():
		return ""
	var t := str(objective.text)
	var d := distance()
	if d >= 0.0:
		t += "   %s" % (("%.1f km" % (d / 1000.0)) if d >= 1000.0 else ("%d m" % int(d)))
	return t


## Metres from the player to the target, or -1.
func distance() -> float:
	var p := _player_pos()
	if target_pos == Vector3.INF or p == Vector3.INF:
		return -1.0
	return p.distance_to(target_pos)


func _player_pos() -> Vector3:
	var p = demo._player if demo != null else null
	return (p as Node3D).global_position if p is Node3D and is_instance_valid(p) else Vector3.INF


## The world position a target word names, or INF.
func where(target: String) -> Vector3:
	if demo == null or target == "":
		return Vector3.INF
	var kind := target.get_slice(":", 0)
	var id := target.get_slice(":", 1) if target.contains(":") else ""
	match kind:
		"npc":
			if id == "cantina_owner" and demo.cantina_owner != null and is_instance_valid(demo.cantina_owner):
				return demo.cantina_owner.global_position
			var g = demo.get("general_post")
			if id == "general" and g != null and is_instance_valid(g) and g.body != null and g.body.visible:
				return g.body.global_position          # issue #203: wherever he stands now
			return _marker(id)
		"wreck":
			# Issue #205: the crashed cruiser on the horizon.
			var pl = demo.get("pilot")
			if pl != null and pl.ground != null and StarcruiserWreck.has_wreck(pl.ground):
				return StarcruiserWreck.frame(pl.ground).origin
		"marker":
			return _marker(id)
		"drop":
			# Issue #251: near the drop itself (its "near" offset, within
			# WorldState.DROP_NEAR), once it is placed; till then its area's marker.
			var g = demo.get("gear")
			if g != null and g.drop != null and is_instance_valid(g.drop):
				var near: Array = WorldState.smuggle.get("near", [0.0, 0.0])
				return g.drop.global_position + Vector3(float(near[0]), 0.0, float(near[1]))
			return _marker(id)
		"range":
			var r = demo.training_range
			if r != null and not r.targets.is_empty() and is_instance_valid(r.targets[0]):
				return r.targets[0].global_position
		"remote":
			var r = demo.training_range
			if r != null and r.remote != null and is_instance_valid(r.remote):
				return r.remote.global_position
		"pad":
			if not demo.pads.is_empty() and is_instance_valid(demo.pads[0]):
				return demo.pads[0].global_position
		"cruiser":
			# Issue #193: its bay from outside, its general (or the bridge) once aboard;
			# or one part of it by name: the bay, the stairs, the general.
			if demo.get("cruiser") != null:
				return demo.cruiser.objective_point(_player_pos(), id)
		"droid_post":
			# Issue #212: the nearest desert droid merchant's post.
			var posts = demo.get("droid_merchant_outposts")
			var best := Vector3.INF
			if posts != null and is_instance_valid(posts):
				var p := _player_pos()
				for site in posts.sites:
					if best == Vector3.INF or p.distance_to(site.pos) < p.distance_to(best):
						best = site.pos
			return best
		"map":
			# The F11 map: a place on the ground, in map coordinates (PlanetSphere).
			var x := float(id.get_slice(",", 0))
			var z := float(id.get_slice(",", 1))
			if PlanetSphere.current != null:
				return PlanetSphere.current.surface_at(x, z)
			return Vector3(x, 0.0, z)
		"planet":
			# The F11 map's off-planet list: that planet's port, in this sky.
			var tr = demo.pilot.travel if demo.get("pilot") != null and demo.pilot.travel != null else null
			if tr != null:
				for b in tr.bodies:
					if str(b.id) == id:
						return b.offset
		"outpost":
			if demo.outposts != null:
				for o in demo.outposts.outposts:
					if str(o.id) == id:
						return o.origin
	return Vector3.INF


func _marker(id: String) -> Vector3:
	if demo.town == null or demo.town.get_marker(id).is_empty():
		return Vector3.INF
	return demo.town.marker_pos(id)


# ------------------------------------------------------------------ drawing

## The arrow before the line (the target's bearing from where the camera looks),
## and the diamond over the target while it is in front of the camera.
func _draw_marks() -> void:
	if objective.is_empty() or target_pos == Vector3.INF or not label.visible:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var size := marks.size
	var to := target_pos - cam.global_position
	# Bearing in the camera's frame (works round a ball planet too): 0 = straight
	# ahead, + = to the right, PI = behind.
	var bearing := atan2(to.dot(cam.global_basis.x), to.dot(-cam.global_basis.z))
	var c := Vector2(LEFT, TOP + 14.0)
	var tip := Vector2(sin(bearing), -cos(bearing))
	var side := Vector2(-tip.y, tip.x)
	var pts := PackedVector2Array([c + tip * 11.0, c - tip * 7.0 + side * 8.0, c - tip * 3.0, c - tip * 7.0 - side * 8.0])
	marks.draw_colored_polygon(pts, AMBER)
	marks.draw_polyline(pts + PackedVector2Array([pts[0]]), Color.BLACK, 1.5)
	if cam.is_position_behind(target_pos + Vector3.UP * 2.0):
		return
	var at := cam.unproject_position(target_pos + Vector3.UP * 2.0)
	at = at.clamp(Vector2(EDGE, TOP + 50.0), size - Vector2(EDGE, EDGE + 40.0))
	var r := 9.0
	var dia := PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)])
	marks.draw_colored_polygon(dia, Color(AMBER, 0.85))
	marks.draw_polyline(dia + PackedVector2Array([dia[0]]), Color.BLACK, 1.5)
