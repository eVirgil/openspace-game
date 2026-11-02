extends SceneTree
## Issue #410: the weapon wheel's icons. Renders each hand weapon's own model flat
## white from the side (muzzle to the right) on a clear background, so the wheel
## shows silhouettes of the guns you hold. No new art: the same models the
## player carries.
##
## Needs a real renderer:
##   godot --path . --resolution 640x320 -s res://tools/lookdev/weapon_icons.gd
## Writes res://assets/ui/weapon_icons/<weapon id>.png. Run again if a model changes.

const OUT := "res://assets/ui/weapon_icons/"
const IDS := ["pistol_blaster", "rifle_blaster", "energy_blade"]
const W := 512
const H := 256
const MARGIN := 1.12

var avatar            # a PlayerAvatar, loaded lazily so the autoloads exist first
var vp: SubViewport
var cam: Camera3D
var stage: Node3D


func _initialize() -> void:
	avatar = load("res://src/systems/player/player_avatar.gd").new()
	root.add_child(avatar)
	avatar.build_weapons(IDS)
	avatar.set_blade_extent(1.0)
	vp = SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	stage = Node3D.new()
	vp.add_child(stage)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	_run()


func _run() -> void:
	for id in IDS:
		var w: Node3D = avatar.weapon_node(id)
		w.get_parent().remove_child(w)
		stage.add_child(w)
		w.visible = true
		_flatten(w)
		await process_frame
		var box := _bounds(w)
		var along := Vector3.BACK              # guns point +Z; the sword stands up its Y
		if id == "energy_blade":
			along = Vector3.UP
		# Camera on -X looking +X: screen right is +Z. A sword is tipped so the blade
		# runs up and to the right at 45 degrees, hilt bottom left.
		var centre := box.get_center()
		cam.global_position = centre + Vector3(-5, 0, 0)
		cam.look_at(centre, Vector3.UP)
		if id == "energy_blade":
			cam.rotate_object_local(Vector3.BACK, deg_to_rad(45))
		var span := _extent(w, box, id)
		var aspect := float(W) / H
		cam.size = maxf(span.y, span.x / aspect) * MARGIN
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img = img.get_region(img.get_used_rect().grow(4).intersection(Rect2i(0, 0, W, H)))   # trimmed; the wheel fits it to a slot
		img.save_png(OUT + id + ".png")
		print("ICON ", id, " ", img.get_size(), " span ", span)
		stage.remove_child(w)
		w.queue_free()
	quit()


## Everything white and unlit, so only the outline reads. The sword's blade and
## hilt are fattened: at true size they are a hair-line that vanishes on the wheel.
func _flatten(n: Node) -> void:
	var sword = n.get_meta("sword") if n.has_meta("sword") else null
	if sword != null:
		(sword.get_node("Blade") as Node3D).scale *= Vector3(1.8, 1.0, 1.8)
		for c in sword.get_children():
			if c.name != "Blade" and c is Node3D:
				(c as Node3D).scale *= Vector3(3.0, 1.2, 3.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color.WHITE
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.find_children("*", "Light3D", true, false):
		c.visible = false
	for c in n.find_children("*", "Sprite3D", true, false):
		c.visible = false


func _bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if not mi.is_visible_in_tree():
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


## The box's size as the camera will see it: depth (Z) across, height (Y) up; the
## sword's 45 degree tilt swaps in its diagonal.
func _extent(_n: Node3D, box: AABB, id: String) -> Vector2:
	if id == "energy_blade":
		var d := Vector2(box.size.z, box.size.y).length()
		return Vector2(d, d)
	return Vector2(box.size.z, box.size.y)
