class_name LookMeshKit
extends RefCounted
## Procedural mesh helpers for the look-dev kit. Everything here is pure geometry
## (no scene, no rendering), so it also runs headless in CI.
##
## Godot treats clockwise triangles as front-facing. add_quad() takes an outward
## direction and fixes the winding itself, so callers never think about it.


static func add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	# (b - a) x (c - a) is the counter-clockwise normal. If it already points out,
	# swap two vertices so the triangle is clockwise when seen from outside.
	if (b - a).cross(c - a).dot(outward) > 0.0:
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
	else:
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)


static func add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	add_tri(st, a, b, c, outward)
	add_tri(st, a, c, d, outward)


static func _finish(st: SurfaceTool) -> ArrayMesh:
	# Hard-surface builders set smooth group -1 first, so they get flat, faceted normals.
	st.generate_normals()
	return st.commit()


## A box-section arc around the Y axis: walls, parapets, landing bays, and (rotated)
## the wreck's broken ring and ribs. Angles are in radians. `xf` turns it as it is
## built (an arch stood up), so nobody has to read the mesh back to turn it: that
## waits on the GPU.
static func ring_segment(r_in: float, r_out: float, y0: float, y1: float,
		a0: float = 0.0, a1: float = TAU, seg: int = 64, xf := Transform3D.IDENTITY) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # hard edges: flat, faceted normals
	var quad := func(_st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3) -> void:
		LookMeshKit.add_quad(_st, xf * a, xf * b, xf * c, xf * d, xf.basis * out)
	for i in seg:
		var t0 := a0 + (a1 - a0) * float(i) / seg
		var t1 := a0 + (a1 - a0) * float(i + 1) / seg
		var d0 := Vector3(cos(t0), 0.0, sin(t0))
		var d1 := Vector3(cos(t1), 0.0, sin(t1))
		var mid := (d0 + d1).normalized()
		var o0b := d0 * r_out + Vector3(0, y0, 0)
		var o1b := d1 * r_out + Vector3(0, y0, 0)
		var o0t := d0 * r_out + Vector3(0, y1, 0)
		var o1t := d1 * r_out + Vector3(0, y1, 0)
		var i0b := d0 * r_in + Vector3(0, y0, 0)
		var i1b := d1 * r_in + Vector3(0, y0, 0)
		var i0t := d0 * r_in + Vector3(0, y1, 0)
		var i1t := d1 * r_in + Vector3(0, y1, 0)
		quad.call(st, o0b, o1b, o1t, o0t, mid)            # outer wall
		quad.call(st, i0b, i1b, i1t, i0t, -mid)           # inner wall
		quad.call(st, i0t, i1t, o1t, o0t, Vector3.UP)     # top
		quad.call(st, i0b, i1b, o1b, o0b, Vector3.DOWN)   # bottom
	if not is_equal_approx(a1 - a0, TAU):
		for end in [[a0, -1.0], [a1, 1.0]]:
			var t: float = end[0]
			var d := Vector3(cos(t), 0.0, sin(t))
			var tangent := Vector3(-sin(t), 0.0, cos(t)) * float(end[1])
			quad.call(st, d * r_in + Vector3(0, y0, 0), d * r_out + Vector3(0, y0, 0),
				d * r_out + Vector3(0, y1, 0), d * r_in + Vector3(0, y1, 0), tangent)
	return _finish(st)


## Points along a hanging cable between a and b.
static func catenary(a: Vector3, b: Vector3, sag: float, n: int = 16) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in n + 1:
		var t := float(i) / n
		var p := a.lerp(b, t)
		p.y -= sag * 4.0 * t * (1.0 - t)
		pts.append(p)
	return pts


## A thin tube following a polyline (cables, pipes, antenna stays).
static func tube(points: PackedVector3Array, radius: float, sides: int = 5) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var axis := (b - a).normalized()
		var side := axis.cross(Vector3.UP)
		if side.length() < 0.01:
			side = axis.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(axis).normalized()
		for s in sides:
			var t0 := TAU * s / sides
			var t1 := TAU * (s + 1) / sides
			var n0 := side * cos(t0) + up * sin(t0)
			var n1 := side * cos(t1) + up * sin(t1)
			add_quad(st, a + n0 * radius, a + n1 * radius, b + n1 * radius, b + n0 * radius,
				(n0 + n1).normalized())
	return _finish(st)


## Displace a primitive mesh's vertices with noise for wind-cut rock. strata > 0 adds
## horizontal steps (ledges) to the radius; y_squash < 1 gives vertical flutes.
## Output is faceted (flat normals).
static func rock(base: PrimitiveMesh, noise: FastNoiseLite, amount: float,
		strata: float = 0.0, seed_offset: float = 0.0, y_squash: float = 1.0) -> ArrayMesh:
	var arrays := base.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var moved := PackedVector3Array()
	moved.resize(verts.size())
	for i in verts.size():
		var v := verts[i]
		var dir := Vector3(v.x, 0.0, v.z)
		# y_squash < 1 stretches the noise vertically: fluted columns instead of blobs.
		var n := noise.get_noise_3d(v.x * 2.0 + seed_offset, v.y * 2.0 * y_squash, v.z * 2.0 + seed_offset)
		var k := 1.0 + n * amount
		if strata > 0.0:
			k += 0.06 * floor(sin(v.y * strata + seed_offset) * 2.0) / 2.0
		moved[i] = Vector3(dir.x * k, v.y + n * amount * 0.3, dir.z * k)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # hard edges: flat, faceted normals
	if idx.size() > 0:
		for i in idx.size():
			st.add_vertex(moved[idx[i]])
	else:
		for v in moved:
			st.add_vertex(v)
	return _finish(st)


## A slightly bowed cloth panel (awnings, banners), width along X, height along -Y.
static func cloth(width: float, height: float, bow: float, cols: int = 6, rows: int = 6) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := func(i: int, j: int) -> Vector3:
		var u := float(i) / cols
		var v := float(j) / rows
		return Vector3((u - 0.5) * width, -v * height, sin(u * PI) * sin(v * PI * 0.5) * bow)
	for i in cols:
		for j in rows:
			add_quad(st, p.call(i, j), p.call(i + 1, j), p.call(i + 1, j + 1), p.call(i, j + 1), Vector3.BACK)
	return _finish(st)


## A tapered cloth/armour shell around the Y axis (coats, robes, mantles, hoods).
## Radius goes from r_top at y_top to r_bot at y_bot; a0..a1 leaves an opening
## (for an open coat front, leave out the angles around +Z, i.e. PI/2).
static func shell(r_top: float, r_bot: float, y_top: float, y_bot: float,
		a0: float = 0.0, a1: float = TAU, thick: float = 0.03, seg: int = 20, rows: int = 4,
		flare: float = 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pt := func(i: int, j: int, inner: bool) -> Vector3:
		var a := a0 + (a1 - a0) * float(i) / seg
		var v := float(j) / rows
		var r := lerpf(r_top, r_bot, v) + flare * v * v
		if inner:
			r -= thick
		return Vector3(cos(a) * r, lerpf(y_top, y_bot, v), sin(a) * r)
	for i in seg:
		for j in rows:
			var am := a0 + (a1 - a0) * (float(i) + 0.5) / seg
			var out := Vector3(cos(am), 0.0, sin(am))
			add_quad(st, pt.call(i, j, false), pt.call(i + 1, j, false), pt.call(i + 1, j + 1, false), pt.call(i, j + 1, false), out)
			add_quad(st, pt.call(i, j, true), pt.call(i + 1, j, true), pt.call(i + 1, j + 1, true), pt.call(i, j + 1, true), -out)
		# hem
		var b0: Vector3 = pt.call(i, rows, false)
		var b1: Vector3 = pt.call(i + 1, rows, false)
		var c0: Vector3 = pt.call(i, rows, true)
		var c1: Vector3 = pt.call(i + 1, rows, true)
		add_quad(st, b0, b1, c1, c0, Vector3.DOWN)
	return _finish(st)


## Four-sided frustum (battered wall block, chest plate): footprint w x d at the base,
## each side leaning in by `lean` of its width at the top (negative = wider on top).
## Origin at the centre of its height.
static func frustum(w: float, d: float, h: float, lean: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # hard edges: flat, faceted normals
	var tw := w * (1.0 - lean)
	var td := d * (1.0 - lean)
	var b := [Vector3(-w, -h, -d) * 0.5, Vector3(w, -h, -d) * 0.5, Vector3(w, -h, d) * 0.5, Vector3(-w, -h, d) * 0.5]
	var t := [Vector3(-tw, h, -td) * 0.5, Vector3(tw, h, -td) * 0.5, Vector3(tw, h, td) * 0.5, Vector3(-tw, h, td) * 0.5]
	var outs := [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]
	for i in 4:
		var j := (i + 1) % 4
		add_quad(st, b[i], b[j], t[j], t[i], outs[i])
	add_quad(st, t[0], t[1], t[2], t[3], Vector3.UP)
	add_quad(st, b[0], b[1], b[2], b[3], Vector3.DOWN)
	return _finish(st)
