class_name SkinnedBody
extends RefCounted
## Dresses a CharacterKit body in a rigged model (a .glb with a Skeleton3D). The kit's
## joints stay the source of truth: BodyAnimator and the two-bone IK keep driving
## them, and every frame `sync()` copies their rotations onto the mapped bones. The
## kit's primitive meshes are hidden; the joints, the holster grip and the weapon
## mounts stay, so gameplay never sees the difference.
##
## Rest poses differ (the kit's arms hang straight down, a rigged model usually
## stands in an A- or T-pose), so `bind()` turns each mapped limb bone onto its
## kit joint's limb axis once, and stores the offset. After that a joint at rest
## puts its bone at rest along the kit's limb, and a joint rotation turns the bone
## by the same amount.
##
## Config (content/look/characters.json, "model" on an archetype):
##   scene:   res:// path to the rigged .glb
##   height:  metres from the soles to the top of the hat, used to fit the model
##   fit:     "height" fits `height` even with a pelvis bone (a body whose hips sit
##            far lower than a person's, like the barge duke's stubby legs)
##   yaw_deg: extra turn if the model does not face +Z
##   bones:   { kit joint name: bone name }

## Joints whose limb hangs along the joint's local -Y (the rest point up +Y).
const LIMBS := ["l_shoulder", "r_shoulder", "l_elbow", "r_elbow", "l_wrist", "r_wrist",
	"l_hip", "r_hip", "l_knee", "r_knee"]
## Joints that are not re-aimed at bind (feet point forward, not down the limb).
const NO_AIM := ["l_ankle", "r_ankle", "head"]

var model: Node3D
var skeleton: Skeleton3D
var joints: Dictionary = {}
var bone_of: Dictionary = {}       ## joint -> bone index
var joint_of: Dictionary = {}      ## bone index -> joint
var _offset: Dictionary = {}       ## bone index -> Basis (joint-space rotation of the bone)
var _root_bone := -1
var _root_rest_origin := Vector3.ZERO
var _pelvis_rest := Vector3.ZERO
var _skel_in_body := Transform3D()
var _order: Array = []             ## bone indices, parents first


## Load and attach. Returns null (and changes nothing) if the model or its skeleton
## is missing, so a checkout without the asset keeps the primitive body.
static func dress(body: Node3D, cfg: Dictionary) -> SkinnedBody:
	var path := str(cfg.get("scene", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var packed = ModelCache.scene(path)
	if not packed is PackedScene:
		return null
	var inst := (packed as PackedScene).instantiate() as Node3D
	var skel := _find_skeleton(inst)
	if skel == null:
		inst.free()
		return null
	var sb := SkinnedBody.new()
	sb.model = inst
	sb.skeleton = skel
	sb.joints = body.get_meta("joints")
	inst.name = "Skin"
	body.add_child(inst)
	sb._fit(cfg)
	sb._bind(body, cfg.get("bones", {}))
	if not body.has_meta("skin"):
		sb._hide_primitives(body)
	if cfg.has("tint"):
		sb.tint(cfg.tint)
	return sb


## Issue #45: a variant of a model without a new model: every surface's colour
## multiplied by "albedo", and anything that glows (goggles, a prosthetic) glowing
## "emission" instead. Materials are copied, so the original keeps its look.
func tint(t: Dictionary) -> void:
	var alb := Color(str(t.get("albedo", "#ffffff")))
	var has_em := t.has("emission")
	var em := Color(str(t.get("emission", "#ffffff")))
	for mi in _meshes(model):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var src = m.get_surface_override_material(i)
			if src == null:
				src = m.mesh.surface_get_material(i)
			if not src is BaseMaterial3D:
				continue
			var c := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
			c.albedo_color = c.albedo_color * alb
			if has_em and c.emission_enabled:
				c.emission = em
			m.set_surface_override_material(i, c)


static func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s != null:
			return s
	return null


## Stand the model on y = 0 facing +Z, scaled so its hips sit at the kit's pelvis
## height: the legs then match the kit's legs, which keeps the feet on the ground
## whatever the hat adds on top. Without a pelvis bone (or with fit "height"), fit
## `height` instead.
func _fit(cfg: Dictionary) -> void:
	model.rotation_degrees.y = float(cfg.get("yaw_deg", 0.0))
	var aabb := _aabb(model, Transform3D())
	var s := float(cfg.get("height", 1.8)) / maxf(aabb.size.y, 0.001)
	var hips := skeleton.find_bone(str(cfg.get("bones", {}).get("pelvis", "")))
	if hips >= 0 and joints.has("pelvis") and str(cfg.get("fit", "")) != "height":
		var hy := (_rel(model, skeleton) * skeleton.get_bone_global_rest(hips).origin).y - aabb.position.y
		if hy > 0.001:
			s = (joints.pelvis as Node3D).position.y / hy
	model.scale = Vector3.ONE * s
	model.position = Vector3(0, -aabb.position.y * s, 0)


static func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var here := xf * ((n as Node3D).transform if n is Node3D else Transform3D())
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out = here * (n as MeshInstance3D).mesh.get_aabb()
		first = false
	for c in n.get_children():
		var a := _aabb(c, here)
		if a.size != Vector3.ZERO:
			out = a if first else out.merge(a)
			first = false
	return out


func _bind(body: Node3D, bones: Dictionary) -> void:
	for jn in bones:
		var bi := skeleton.find_bone(str(bones[jn]))
		if bi >= 0 and joints.has(jn):
			bone_of[jn] = bi
			joint_of[bi] = jn
	_skel_in_body = _rel(body, skeleton)
	# The kit at rest: every joint rotation zero. Measure it, then put the pose back.
	var saved := {}
	for jn in joints:
		saved[jn] = (joints[jn] as Node3D).transform.basis
		(joints[jn] as Node3D).transform.basis = Basis()
	var inv := _skel_in_body.affine_inverse()
	for bi in skeleton.get_bone_count():
		_order.append(bi)
	_order.sort_custom(func(a, b): return _depth(a) < _depth(b))
	for bi in joint_of:
		var jn: String = joint_of[bi]
		var jb := _rot(inv * _rel(body, joints[jn]))
		var bb := skeleton.get_bone_global_rest(bi).basis.orthonormalized()
		if not NO_AIM.has(jn):
			var kit_dir := jb * (Vector3.DOWN if LIMBS.has(jn) else Vector3.UP)
			var bone_dir := _bone_dir(bi)
			if bone_dir != Vector3.ZERO:
				bb = _turn(bone_dir, kit_dir.normalized()) * bb
		_offset[bi] = jb.inverse() * bb
	if bone_of.has("pelvis"):
		_root_bone = bone_of.pelvis
		_root_rest_origin = skeleton.get_bone_global_rest(_root_bone).origin
		_pelvis_rest = (inv * _rel(body, joints.pelvis)).origin
	for jn in saved:
		(joints[jn] as Node3D).transform.basis = saved[jn]


func _depth(bi: int) -> int:
	var d := 0
	var p := skeleton.get_bone_parent(bi)
	while p >= 0:
		d += 1
		p = skeleton.get_bone_parent(p)
	return d


## Rest direction from a bone to its first mapped (or any) child, in skeleton space.
func _bone_dir(bi: int) -> Vector3:
	var kids := skeleton.get_bone_children(bi)
	if kids.is_empty():
		return Vector3.ZERO
	var pick: int = kids[0]
	for k in kids:
		if joint_of.has(k):
			pick = k
			break
	var d := skeleton.get_bone_global_rest(pick).origin - skeleton.get_bone_global_rest(bi).origin
	return d.normalized() if d.length() > 0.0001 else Vector3.ZERO


static func _turn(from: Vector3, to: Vector3) -> Basis:
	var axis := from.cross(to)
	var s := axis.length()
	if s < 0.00001:
		return Basis() if from.dot(to) > 0.0 else Basis(Vector3.RIGHT if absf(from.x) < 0.9 else Vector3.UP, PI)
	return Basis(axis / s, atan2(s, from.dot(to)))


static func _rot(t: Transform3D) -> Basis:
	return t.basis.orthonormalized()


static func _rel(root: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D()
	var n: Node = node
	while n != null and n != root:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


func _hide_primitives(body: Node3D) -> void:
	# A held prop (the kit's rifle, body meta "weapon") stays: the hands are posed on it.
	var prop: Node = body.get_meta("weapon") if body.has_meta("weapon") else null
	for m in _meshes(body):
		if model.is_ancestor_of(m) or (prop != null and (prop == m or prop.is_ancestor_of(m))):
			continue
		(m as GeometryInstance3D).visible = false


func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is GeometryInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


## Every mesh of the skin (for first-person shadow-only switching).
func skin_meshes() -> Array:
	return _meshes(model)


## Where joint `jn`'s bone is now, as the joint's own frame (its bind offset taken
## back out), in body space. The skin's limbs are not the kit's lengths, so a skin
## hand is not quite where the kit's IK put the kit's. Call after sync().
func joint_xf(jn: String) -> Transform3D:
	var bi: int = bone_of[jn]
	var g := skeleton.get_bone_global_pose(bi)
	var t := _skel_in_body * Transform3D(g.basis.orthonormalized() * (_offset[bi] as Basis).inverse(), g.origin)
	t.basis = t.basis.orthonormalized()
	return t


## Copy the kit joints onto the bones. Call after the animator and IK have run.
func sync(body: Node3D) -> void:
	var skins = body.get_meta("skins", [])
	if skins is Array and not skins.is_empty():
		for layer in skins:
			if layer is SkinnedBody:
				(layer as SkinnedBody)._sync_one(body)
		return
	_sync_one(body)


func _sync_one(body: Node3D) -> void:
	var inv := _skel_in_body.affine_inverse()
	var want := {}                 ## bone -> skeleton-space basis this frame
	for bi in _order:
		var parent := skeleton.get_bone_parent(bi)
		var pg: Basis = want.get(parent, Basis()) if parent >= 0 else Basis()
		var g: Basis
		if joint_of.has(bi):
			g = _rot(inv * _rel(body, joints[joint_of[bi]])) * _offset[bi]
		else:
			g = pg * skeleton.get_bone_rest(bi).basis.orthonormalized()
		want[bi] = g
		skeleton.set_bone_pose_rotation(bi, (pg.inverse() * g).get_rotation_quaternion())
	if _root_bone >= 0:
		var now := (inv * _rel(body, joints.pelvis)).origin
		var origin := _root_rest_origin + (now - _pelvis_rest)
		var parent := skeleton.get_bone_parent(_root_bone)
		if parent >= 0:
			origin = skeleton.get_bone_global_pose(parent).affine_inverse() * origin
		skeleton.set_bone_pose_position(_root_bone, origin)
