class_name GrenadeArcView
extends Node3D
## Issue #372: the dotted arc while the throw key is held: a dot every few of the
## arc's steps (GrenadeArc.trace, the same steps the grenade flies) and a ring
## where it first lands. Unshaded and glowing a little so it reads on sand and in
## the dark. Hidden when there is nothing to show.

const MAX_DOTS := 96

var dot_radius := 0.045
var color := Color("#ffd27a")
var _dots: MultiMeshInstance3D
var _ring: MeshInstance3D


func _ready() -> void:
	top_level = true
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.6
	mat.no_depth_test = false
	var sphere := SphereMesh.new()
	sphere.radius = dot_radius
	sphere.height = dot_radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sphere
	mm.instance_count = MAX_DOTS
	mm.visible_instance_count = 0
	_dots = MultiMeshInstance3D.new()
	_dots.multimesh = mm
	_dots.material_override = mat
	_dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dots)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.32
	torus.outer_radius = 0.4
	torus.rings = 24
	torus.ring_segments = 6
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.material_override = mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	hide_arc()


## Show `path` (GrenadeArc.trace's result), a dot every `every` points, from
## `near` metres out (closer ones sit in front of the eye and fill the screen).
func show_arc(path: Dictionary, every := 3, near := 2.5) -> void:
	if _dots == null:
		return
	var pts: Array = path.get("points", [])
	var mm := _dots.multimesh
	var n := 0
	var i := 0
	var start: Vector3 = pts[0] if not pts.is_empty() else Vector3.ZERO
	while i < pts.size() and (pts[i] as Vector3).distance_to(start) < near:
		i += 1
	while i < pts.size() and n < MAX_DOTS:
		mm.set_instance_transform(n, Transform3D(Basis.IDENTITY, pts[i]))
		n += 1
		i += maxi(1, every)
	mm.visible_instance_count = n
	_dots.visible = n > 0
	_ring.visible = bool(path.get("landed", false))
	if _ring.visible:
		var up: Vector3 = (path.get("normal", Vector3.UP) as Vector3).normalized()
		var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		_ring.global_transform = Transform3D(Basis(side, up, side.cross(up)), (path.at as Vector3) + up * 0.03)
	visible = true


func hide_arc() -> void:
	visible = false
	if _dots != null:
		_dots.multimesh.visible_instance_count = 0
