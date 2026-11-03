extends SceneTree
## Turns a raw rigged character from Hyper3D into the game asset. Raw downloads live
## in assets/characters/<id>/source/ (ignored by the importer); this writes
## assets/characters/<id>/<id>.glb.
##
##   godot --headless --path . -s res://tools/look/prep_character.gd -- id=smuggler
##
## Steps, all from content/look/character_models.json:
## - flatten: press the vertices inside a box onto a plane (z = plane_z) and give them
##   the UV of the vertex nearest `uv_from`. Used for gear the game draws itself (the
##   jetpack is an inventory item): there is no coat modelled under it, so deleting
##   it leaves a hole, while flattening it leaves a closed patch of coat leather.
## - reweight: auto-rigging weights some of the long coat to the arms, so raising an
##   arm drags a plank of coat up with it. Any arm-chain influence on a vertex farther
##   than `radius` from that bone's segment moves to `to` (the hips).
## - cut: drop every triangle whose centroid falls in a box (mesh space, metres).
## - drop the small loose islands a cut leaves behind.
## - emission: attach the separate glow texture (goggles, wrist lights).
## - attach: weld a separately generated prop (Oda's gas mask) onto one bone. The prop
##   is scaled by `scale` and moved to `at` (mesh space, metres), every vertex goes
##   100% to `bone`, and `cut` boxes (prop space) drop triangles, only light-coloured
##   ones when `light` is set (the mannequin bust the generator put inside the mask).
##   `tint` multiplies its albedo; `discs` add flat glowing lenses (prop space centre
##   and radius, facing +Z); `spheres` add see-through balls on the same bone (mesh
##   space centre and radius, metres), drawn in order: the barge duke's tank of glowing
##   liquid and its glass, around the squid (the generator can only paint a squid on
##   an opaque ball). Each has a `color` with alpha, and optional `energy` (glow) and
##   `rough`.
## - decimate: cut a surface (or an attached prop) down to about this many triangles.
## - split: cut the body into parts that are swapped and recoloured on their own (the
##   locals: head, torso, legs). A triangle goes to the first part whose `bones` (name
##   prefixes) carry 80% of its weight, else to the first part
##   whose `above` / `below` (mesh-space y, metres) holds its centroid, else to the
##   `rest` part. Height cuts give straight seams (belt, collar); `bones` keep a hand
##   that hangs below the belt on the torso; a claimed patch smaller than
##   `min_claim_tris` (connected triangles) is cloth the fingers touch, and goes back
##   to the height rule. `within` { bone, radius, below } limits a height rule, under `below`, to a vertical
##   cylinder around that bone: the neck above the collar line, but not the tops of
##   the shoulders (above `below` the whole head counts, ears and all). Every part is its own MeshInstance3D,
##   named after the part (lower case: "Head" is taken by the bone), on the same
##   skeleton and skin.

const CFG_PATH := "res://content/look/character_models.json"


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var id := str(args.get("id", "smuggler"))
	var all: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CFG_PATH))
	var cfg: Dictionary = all.get(id, {})
	if cfg.is_empty():
		push_error("prep: no config for '%s' in %s" % [id, CFG_PATH])
		quit(1)
		return
	var src := ProjectSettings.globalize_path(str(cfg.source))
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(src, state) != OK:
		push_error("prep: cannot read " + src)
		quit(1)
		return
	var scene := doc.generate_scene(state)
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		_prep_mesh(mi as MeshInstance3D, cfg)
		if cfg.has("split") and (mi as MeshInstance3D).skin != null:
			_split(mi as MeshInstance3D, cfg.split, int(cfg.get("min_claim_tris", 0)), scene)
	var out_doc := GLTFDocument.new()
	var out_state := GLTFState.new()
	out_doc.append_from_scene(scene, out_state)
	var out := ProjectSettings.globalize_path(str(cfg.out))
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	if out_doc.write_to_filesystem(out_state, out) != OK:
		push_error("prep: cannot write " + out)
		quit(1)
		return
	print("prep: wrote ", out)
	scene.free()
	quit()


func _prep_mesh(mi: MeshInstance3D, cfg: Dictionary) -> void:
	var src_mesh := mi.mesh as ArrayMesh
	var out := ArrayMesh.new()
	for s in src_mesh.get_surface_count():
		var arr := src_mesh.surface_get_arrays(s)
		var mat := src_mesh.surface_get_material(s)
		var albedo: Image = null
		if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null:
			albedo = (mat as BaseMaterial3D).albedo_texture.get_image()
			albedo.decompress()
		for f in cfg.get("flatten", []):
			_flatten(arr, f, albedo)
		if cfg.has("reweight") and mi.skin != null:
			_reweight(arr, mi, cfg.reweight)
		var before := (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		arr[Mesh.ARRAY_INDEX] = _cut(arr, cfg.get("cut", []), int(cfg.get("min_island_tris", 0)))
		if cfg.has("decimate"):
			arr = _decimate(arr, int(cfg.decimate))
		var after := (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		print("prep: surface %d  %d -> %d triangles" % [s, before, after])
		var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if (arr[Mesh.ARRAY_BONES] as PackedInt32Array).size() == (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() * 8 else 0
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
		if mat is BaseMaterial3D and cfg.has("emission"):
			var e: Dictionary = cfg.emission
			var m := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
			var img := Image.load_from_file(ProjectSettings.globalize_path(str(e.texture)))
			m.emission_enabled = true
			m.emission_texture = ImageTexture.create_from_image(img)
			m.emission = Color.WHITE
			m.emission_energy_multiplier = float(e.get("energy", 1.0))
			mat = m
		out.surface_set_material(s, mat)
	if mi.skin != null:
		for a in cfg.get("attach", []):
			_attach(out, mi, a)
	mi.mesh = out


func _attach(out: ArrayMesh, mi: MeshInstance3D, a: Dictionary) -> void:
	var bone := _bind_index(mi, str(a.bone))
	if bone < 0:
		push_warning("prep: attach bone '%s' missing" % a.bone)
		return
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(str(a.source)), state) != OK:
		push_error("prep: cannot read " + str(a.source))
		return
	var prop := doc.generate_scene(state)
	var k := float(a.scale)
	var at := Vector3(a.at[0], a.at[1], a.at[2])
	var per := (out.surface_get_arrays(0)[Mesh.ARRAY_BONES] as PackedInt32Array).size() / (out.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
	for pm in prop.find_children("*", "MeshInstance3D", true, false):
		var src := (pm as MeshInstance3D).mesh
		for s in src.get_surface_count():
			var arr := src.surface_get_arrays(s)
			var mat := src.surface_get_material(s)
			var albedo: Image = null
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null:
				albedo = (mat as BaseMaterial3D).albedo_texture.get_image()
				albedo.decompress()
			var before := (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			arr[Mesh.ARRAY_INDEX] = _cut_prop(arr, a.get("cut", []), albedo)
			if a.has("decimate"):
				arr = _decimate(arr, int(a.decimate))
			print("prep: attach %s  %d -> %d triangles" % [a.get("what", ""), before, (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3])
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for i in v.size():
				v[i] = at + v[i] * k
			arr[Mesh.ARRAY_VERTEX] = v
			_skin_to(arr, v.size(), bone, per)
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
			if mat is BaseMaterial3D and a.has("tint"):
				mat = (mat as BaseMaterial3D).duplicate()
				(mat as BaseMaterial3D).albedo_color = Color(str(a.tint))
			out.surface_set_material(out.get_surface_count() - 1, mat)
	prop.free()
	for d in a.get("discs", []):
		var c := at + Vector3(d.center[0], d.center[1], d.center[2]) * k
		var r := float(d.radius) * k
		var verts := PackedVector3Array([c])
		var idx := PackedInt32Array()
		var n := 24
		for i in n:
			var t := TAU * i / n
			verts.append(c + Vector3(cos(t) * r, sin(t) * r, 0.0))
			idx.append_array([0, 1 + (i + 1) % n, 1 + i])   # clockwise from the front (Godot culls CCW)
		var norms := PackedVector3Array()
		norms.resize(verts.size())
		norms.fill(Vector3(0, 0, 1))
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_INDEX] = idx
		_skin_to(arr, verts.size(), bone, per)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color(str(d.color))
		glow.emission_enabled = true
		glow.emission = Color(str(d.color))
		glow.emission_energy_multiplier = float(d.get("energy", 2.0))
		out.surface_set_material(out.get_surface_count() - 1, glow)
	for i in a.get("spheres", []).size():
		var sp: Dictionary = a.spheres[i]
		var ball := SphereMesh.new()
		ball.radius = float(sp.radius)
		ball.height = float(sp.radius) * 2.0
		ball.radial_segments = 48
		ball.rings = 24
		var arr := ball.get_mesh_arrays()
		var c := Vector3(sp.center[0], sp.center[1], sp.center[2])
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for j in v.size():
			v[j] += c
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_TANGENT] = null
		_skin_to(arr, v.size(), bone, per)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(str(sp.color))
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.metallic = 0.0
		m.roughness = float(sp.get("rough", 0.1))
		m.render_priority = i
		if sp.has("energy"):
			m.emission_enabled = true
			m.emission = Color(str(sp.color))
			m.emission_energy_multiplier = float(sp.energy)
		out.surface_set_material(out.get_surface_count() - 1, m)
	print("prep: attached %s to %s" % [a.get("what", ""), a.bone])


## The coarsest LOD meshoptimizer makes that still has `target` triangles or more,
## with the unused vertices dropped. Rodin's high tier is ~500k triangles; the game
## wants tens of thousands.
static func _decimate(arr: Array, target: int) -> Array:
	var tris := (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	if tris <= target:
		return arr
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr)
	im.generate_lods(25.0, 60.0, [])
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for lod in im.get_surface_lod_count(0):
		var li := im.get_surface_lod_indices(0, lod)
		if li.size() / 3 < target:
			if lod == 0:
				idx = li                   ## even the first level is under: take it
			break
		idx = li
	return _compact(arr, idx)


## A copy of `arr` with only the vertices `idx` uses, and `idx` renumbered.
static func _compact(arr: Array, idx: PackedInt32Array) -> Array:
	var remap := PackedInt32Array()
	remap.resize((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	remap.fill(-1)
	var keep := PackedInt32Array()
	var out_idx := PackedInt32Array()
	out_idx.resize(idx.size())
	for i in idx.size():
		var vi := idx[i]
		if remap[vi] < 0:
			remap[vi] = keep.size()
			keep.append(vi)
		out_idx[i] = remap[vi]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for k in Mesh.ARRAY_MAX:
		var src = arr[k]
		if src == null or k == Mesh.ARRAY_INDEX:
			continue
		var per: int = src.size() / remap.size()
		var dst = src.duplicate()
		dst.resize(keep.size() * per)
		for i in keep.size():
			for j in per:
				dst[i * per + j] = src[keep[i] * per + j]
		out[k] = dst
	out[Mesh.ARRAY_INDEX] = out_idx
	return out


func _split(mi: MeshInstance3D, parts: Array, min_claim: int, scene: Node) -> void:
	var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D
	var claim := {}                    ## bind -> part index, from `bones`
	var rest := -1
	for pi in parts.size():
		if parts[pi].get("rest", false):
			rest = pi
	for b in mi.skin.get_bind_count():
		var n := String(mi.skin.get_bind_name(b))
		if n == "" and skel != null and mi.skin.get_bind_bone(b) >= 0:
			n = skel.get_bone_name(mi.skin.get_bind_bone(b))
		for pi in range(parts.size() - 1, -1, -1):
			for prefix in parts[pi].get("bones", []):
				if n.begins_with(str(prefix)):
					claim[b] = pi
	for pi in parts.size():
		if parts[pi].has("within") and skel != null:
			var o := skel.get_bone_global_rest(skel.find_bone(str(parts[pi].within.bone))).origin
			parts[pi]["axis_xz"] = Vector2(o.x, o.z)
	var src := mi.mesh as ArrayMesh
	var meshes: Array = []
	for pi in parts.size():
		meshes.append(ArrayMesh.new())
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / v.size()
		var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
		var part_tri := PackedInt32Array()   ## triangle -> part
		var claimed := PackedInt32Array()    ## triangle -> part its bones claim, or -1
		for t in range(0, idx.size(), 3):
			var total := 0.0
			var share := {}                ## claiming part -> weight
			for j in 3:
				for k in per:
					var bw := weights[idx[t + j] * per + k]
					total += bw
					var cp := int(claim.get(bones[idx[t + j] * per + k], -1))
					if bw > 0.0 and cp >= 0:
						share[cp] = float(share.get(cp, 0.0)) + bw
			var pick := -1
			for cp in share:
				if share[cp] >= 0.8 * total:
					pick = cp
			claimed.append(pick)
			part_tri.append(pick if pick >= 0 else _by_height(parts, v, idx, t, rest))
		_drop_small_claims(part_tri, claimed, v, idx, parts, rest, min_claim)
		for pi in parts.size():
			var mine := PackedInt32Array()
			for t in part_tri.size():
				if part_tri[t] == pi:
					mine.append_array([idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2]])
			if mine.is_empty():
				continue
			var m: ArrayMesh = meshes[pi]
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _compact(arr, mine), [], {}, flags)
			m.surface_set_material(m.get_surface_count() - 1, src.surface_get_material(s))
	for pi in parts.size():
		var part := MeshInstance3D.new()
		part.name = str(parts[pi].name)
		part.mesh = meshes[pi]
		part.skin = mi.skin
		part.transform = mi.transform
		mi.get_parent().add_child(part)
		part.owner = scene
		part.skeleton = mi.skeleton
		var tris := 0
		for s in (meshes[pi] as ArrayMesh).get_surface_count():
			tris += ((meshes[pi] as ArrayMesh).surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		print("prep: split %s  %d triangles" % [part.name, tris])
	mi.get_parent().remove_child(mi)
	mi.free()


static func _by_height(parts: Array, v: PackedVector3Array, idx: PackedInt32Array, t: int, rest: int) -> int:
	var y := (v[idx[t]].y + v[idx[t + 1]].y + v[idx[t + 2]].y) / 3.0
	for pi in parts.size():
		if (parts[pi].has("above") and y > float(parts[pi].above)) or (parts[pi].has("below") and y < float(parts[pi].below)):
			if parts[pi].has("axis_xz"):
				var c := (v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0
				if c.y < float(parts[pi].within.get("below", INF)) and Vector2(c.x, c.z).distance_to(parts[pi].axis_xz) > float(parts[pi].within.radius):
					continue
			return pi
	return rest


## Claimed triangles in connected patches (by shared position) under `min_claim`
## triangles fall back to the height rule.
static func _drop_small_claims(part_tri: PackedInt32Array, claimed: PackedInt32Array, v: PackedVector3Array,
		idx: PackedInt32Array, parts: Array, rest: int, min_claim: int) -> void:
	if min_claim <= 0:
		return
	var parent := PackedInt32Array()
	parent.resize(v.size())
	for i in v.size():
		parent[i] = i
	var weld := {}
	for i in v.size():
		var k := Vector3i((v[i] * 10000.0).round())
		if weld.has(k):
			_union(parent, i, weld[k])
		else:
			weld[k] = i
	for t in claimed.size():
		if claimed[t] >= 0:
			_union(parent, idx[t * 3], idx[t * 3 + 1])
			_union(parent, idx[t * 3 + 1], idx[t * 3 + 2])
	var count := {}
	for t in claimed.size():
		if claimed[t] >= 0:
			var r := _find(parent, idx[t * 3])
			count[r] = int(count.get(r, 0)) + 1
	var dropped := 0
	for t in claimed.size():
		if claimed[t] >= 0 and int(count[_find(parent, idx[t * 3])]) < min_claim:
			part_tri[t] = _by_height(parts, v, idx, t * 3, rest)
			dropped += 1
	print("prep: split  %d triangles in small claimed patches back to the height rule" % dropped)


static func _skin_to(arr: Array, count: int, bone: int, per: int) -> void:
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	bones.resize(count * per)
	weights.resize(count * per)
	for i in count:
		bones[i * per] = bone
		weights[i * per] = 1.0
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = weights


## Triangles of a prop that survive its cut boxes. With `light` [min_value, max_sat]
## only triangles whose three texels are that light and grey go.
func _cut_prop(arr: Array, boxes: Array, albedo: Image) -> PackedInt32Array:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var kept := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		var c := (v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0
		var drop := false
		for b in boxes:
			var box := AABB(Vector3(b.min[0], b.min[1], b.min[2]), Vector3(b.max[0], b.max[1], b.max[2]) - Vector3(b.min[0], b.min[1], b.min[2]))
			if not box.has_point(c):
				continue
			if not b.has("light") or albedo == null:
				drop = true
			else:
				drop = true
				for j in 3:
					var px := Vector2i((uv[idx[t + j]] * Vector2(albedo.get_size())).clamp(Vector2.ZERO, Vector2(albedo.get_size() - Vector2i.ONE)))
					var col := albedo.get_pixelv(px)
					if col.v < float(b.light[0]) or col.s > float(b.light[1]):
						drop = false
			if drop:
				break
		if not drop:
			kept.append_array([idx[t], idx[t + 1], idx[t + 2]])
	return kept


static func _bind_index(mi: MeshInstance3D, bone_name: String) -> int:
	var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D
	for b in mi.skin.get_bind_count():
		var n := String(mi.skin.get_bind_name(b))
		if n == "" and skel != null and mi.skin.get_bind_bone(b) >= 0:
			n = skel.get_bone_name(mi.skin.get_bind_bone(b))
		if n == bone_name:
			return b
	return -1


## `skip_hue` [lo, hi] (optional): leave vertices whose texel has that hue and some
## saturation, e.g. the brown hat brim that shares the jetpack's height.
func _flatten(arr: Array, f: Dictionary, albedo: Image) -> void:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var lo := Vector3(f.min[0], f.min[1], f.min[2])
	var hi := Vector3(f.max[0], f.max[1], f.max[2])
	var box := AABB(lo, hi - lo)
	var src := Vector3(f.uv_from[0], f.uv_from[1], f.uv_from[2])
	var best := 0
	for i in v.size():
		if v[i].distance_squared_to(src) < v[best].distance_squared_to(src):
			best = i
	var patch_uv := uv[best]
	var skip: Array = f.get("skip_hue", [])
	var moved := 0
	for i in v.size():
		if box.has_point(v[i]):
			if skip.size() == 2 and albedo != null:
				var px := Vector2i((uv[i] * Vector2(albedo.get_size())).clamp(Vector2.ZERO, Vector2(albedo.get_size() - Vector2i.ONE)))
				var c := albedo.get_pixelv(px)
				if c.s > 0.25 and c.h >= float(skip[0]) and c.h <= float(skip[1]):
					continue
			v[i].z = float(f.plane_z)
			uv[i] = patch_uv
			n[i] = Vector3(0, 0, -1)
			moved += 1
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_NORMAL] = n
	# Tangents were computed for the old shape; drop them so the importer rebuilds them.
	arr[Mesh.ARRAY_TANGENT] = null
	print("prep: flattened %d vertices (%s)" % [moved, f.get("what", "")])


func _reweight(arr: Array, mi: MeshInstance3D, r: Dictionary) -> void:
	var skin := mi.skin
	var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D
	var bind_name := func(b: int) -> String:
		var n := String(skin.get_bind_name(b))
		if n == "" and skel != null and skin.get_bind_bone(b) >= 0:
			n = skel.get_bone_name(skin.get_bind_bone(b))
		return n
	var head := {}                     ## bind -> head position in mesh space
	var by_name := {}
	for b in skin.get_bind_count():
		head[b] = skin.get_bind_pose(b).affine_inverse().origin
		by_name[bind_name.call(b)] = b
	var to := int(by_name.get(str(r.get("to", "Hips")), -1))
	if to < 0:
		push_warning("prep: reweight target bone missing")
		return
	# One segment per arm-chain bind: arm -> forearm -> hand -> mean of the fingertips.
	var seg := {}
	for side in ["Left", "Right"]:
		var arm: int = by_name.get(side + "Arm", -1)
		var fore: int = by_name.get(side + "ForeArm", -1)
		var hand: int = by_name.get(side + "Hand", -1)
		if arm < 0 or fore < 0 or hand < 0:
			continue
		var tips := Vector3.ZERO
		var nt := 0
		for nm in by_name:
			if str(nm).begins_with(side + "Hand") and str(nm).ends_with("3"):
				tips += head[by_name[nm]]
				nt += 1
		var tip: Vector3 = tips / nt if nt > 0 else head[hand] + (head[hand] - head[fore]) * 0.4
		seg[arm] = [head[arm], head[fore]]
		seg[fore] = [head[fore], head[hand]]
		for nm in by_name:
			if str(nm).begins_with(side + "Hand"):
				seg[by_name[nm]] = [head[hand], tip]
	var radius := float(r.get("radius", 0.11))
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / v.size()
	var moved := 0
	for i in v.size():
		var hit := false
		for k in per:
			var j := i * per + k
			if weights[j] <= 0.0 or not seg.has(bones[j]):
				continue
			var s: Array = seg[bones[j]]
			var p := Geometry3D.get_closest_point_to_segment(v[i], s[0], s[1])
			if p.distance_to(v[i]) > radius:
				bones[j] = to
				hit = true
		if hit:
			moved += 1
	arr[Mesh.ARRAY_BONES] = bones
	print("prep: reweighted %d vertices off the arms" % moved)


## Indices that survive the cut boxes and the island clean-up.
func _cut(arr: Array, boxes: Array, min_island: int) -> PackedInt32Array:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var aabbs: Array = []
	for b in boxes:
		var lo := Vector3(b.min[0], b.min[1], b.min[2])
		var hi := Vector3(b.max[0], b.max[1], b.max[2])
		aabbs.append(AABB(lo, hi - lo))
	var kept := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		var c := (v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0
		var inside := false
		for box in aabbs:
			if (box as AABB).has_point(c):
				inside = true
				break
		if not inside:
			kept.append_array([idx[t], idx[t + 1], idx[t + 2]])
	if min_island <= 0:
		return kept
	# Islands by shared position (vertices are split at UV seams, so weld first).
	var parent := PackedInt32Array()
	parent.resize(v.size())
	for i in v.size():
		parent[i] = i
	var weld := {}
	for i in v.size():
		var k := Vector3i((v[i] * 10000.0).round())
		if weld.has(k):
			_union(parent, i, weld[k])
		else:
			weld[k] = i
	for t in range(0, kept.size(), 3):
		_union(parent, kept[t], kept[t + 1])
		_union(parent, kept[t + 1], kept[t + 2])
	var count := {}
	for t in range(0, kept.size(), 3):
		var r := _find(parent, kept[t])
		count[r] = int(count.get(r, 0)) + 1
	var out := PackedInt32Array()
	for t in range(0, kept.size(), 3):
		if int(count[_find(parent, kept[t])]) >= min_island:
			out.append_array([kept[t], kept[t + 1], kept[t + 2]])
	return out


static func _find(p: PackedInt32Array, i: int) -> int:
	while p[i] != i:
		p[i] = p[p[i]]
		i = p[i]
	return i


static func _union(p: PackedInt32Array, a: int, b: int) -> void:
	p[_find(p, a)] = _find(p, b)
