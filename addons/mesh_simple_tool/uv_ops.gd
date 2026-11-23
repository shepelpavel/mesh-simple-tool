@tool
extends RefCounted

const UV1 := Mesh.ARRAY_TEX_UV
const UV2 := Mesh.ARRAY_TEX_UV2


static func ensure_array_mesh(mi: MeshInstance3D) -> ArrayMesh:
	var mesh: Mesh = mi.mesh
	if mesh is ArrayMesh:
		return mesh
	if mesh is PrimitiveMesh:
		var arrays: Array = (mesh as PrimitiveMesh).get_mesh_arrays()
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			return null
		var converted := ArrayMesh.new()
		converted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if mesh.material != null:
			converted.surface_set_material(0, mesh.material)
		mi.mesh = converted
		return converted
	return null


static func snapshot(mesh: ArrayMesh) -> Array:
	var out: Array = []
	for i in mesh.get_surface_count():
		out.append(_entry(
			mesh.surface_get_arrays(i),
			mesh.surface_get_primitive_type(i),
			mesh.surface_get_format(i),
			mesh.surface_get_material(i),
			mesh.surface_get_name(i)
		))
	return out


static func _entry(arrays: Array, primitive: int, format: int, material: Material, sname: String) -> Dictionary:
	return {
		"arrays": arrays,
		"primitive": primitive,
		"format": format,
		"material": material,
		"name": sname,
	}


static func apply(mesh: ArrayMesh, surfaces: Array) -> void:
	mesh.clear_surfaces()
	for s in surfaces:
		var arrays: Array = s["arrays"]
		if arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		mesh.add_surface_from_arrays(s["primitive"], arrays)
		var idx: int = mesh.get_surface_count() - 1
		var material: Material = s["material"]
		if material != null:
			mesh.surface_set_material(idx, material)
		var sname: String = s["name"]
		if sname != "":
			mesh.surface_set_name(idx, sname)
	mesh.emit_changed()


static func has_channel(snap: Array, channel: int) -> bool:
	for s in snap:
		var arrays: Array = s["arrays"]
		var uvs: Variant = arrays[channel]
		if uvs is PackedVector2Array and not uvs.is_empty():
			return true
	return false


static func scaled(snap: Array, channel: int, factor: float) -> Array:
	var out: Array = []
	for s in snap:
		var arrays: Array = (s["arrays"] as Array).duplicate(true)
		var uvs: Variant = arrays[channel]
		if uvs is PackedVector2Array and not uvs.is_empty():
			var pivot := _uv_center(uvs)
			var moved := PackedVector2Array()
			moved.resize(uvs.size())
			for i in uvs.size():
				moved[i] = pivot + (uvs[i] - pivot) * factor
			arrays[channel] = moved
		out.append(_entry(arrays, s["primitive"], s["format"], s["material"], s["name"]))
	return out


static func _uv_center(uvs: PackedVector2Array) -> Vector2:
	var mn := uvs[0]
	var mx := uvs[0]
	for i in range(1, uvs.size()):
		mn = Vector2(minf(mn.x, uvs[i].x), minf(mn.y, uvs[i].y))
		mx = Vector2(maxf(mx.x, uvs[i].x), maxf(mx.y, uvs[i].y))
	return (mn + mx) * 0.5


static func box_unwrapped(snap: Array, padding: float) -> Array:
	var out: Array = []
	for s in snap:
		var arrays: Array = (s["arrays"] as Array).duplicate(true)
		var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
		if not (verts is PackedVector3Array) or verts.is_empty():
			out.append(_entry(arrays, s["primitive"], s["format"], s["material"], s["name"]))
			continue
		var normals: Variant = arrays[Mesh.ARRAY_NORMAL]
		var uvs := PackedVector2Array()
		uvs.resize(verts.size())
		for i in verts.size():
			var n := Vector3.UP
			if normals is PackedVector3Array and normals.size() == verts.size():
				n = normals[i]
			uvs[i] = _project_axis(verts[i], n)
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		out.append(_entry(arrays, s["primitive"], s["format"], s["material"], s["name"]))
	_normalize(out, padding)
	return out


static func _project_axis(v: Vector3, n: Vector3) -> Vector2:
	var ax := absf(n.x)
	var ay := absf(n.y)
	var az := absf(n.z)
	if ax >= ay and ax >= az:
		return Vector2(v.z if n.x >= 0.0 else -v.z, v.y)
	if ay >= az:
		return Vector2(v.x, -v.z if n.y >= 0.0 else v.z)
	return Vector2(v.x if n.z >= 0.0 else -v.x, v.y)


static func cylindrical_unwrapped(snap: Array, padding: float) -> Array:
	var out: Array = []
	for s in snap:
		var arrays: Array = (s["arrays"] as Array).duplicate(true)
		var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
		if not (verts is PackedVector3Array) or verts.is_empty():
			out.append(_entry(arrays, s["primitive"], s["format"], s["material"], s["name"]))
			continue
		var mn_y := INF
		var mx_y := -INF
		for v in verts:
			mn_y = minf(mn_y, v.y)
			mx_y = maxf(mx_y, v.y)
		var span := mx_y - mn_y
		var uvs := PackedVector2Array()
		uvs.resize(verts.size())
		for i in verts.size():
			var v: Vector3 = verts[i]
			var u: float = atan2(-v.z, v.x) / TAU + 0.5
			var t: float = 0.0 if span <= 0.000001 else (v.y - mn_y) / span
			uvs[i] = Vector2(u, t)
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		out.append(_entry(arrays, s["primitive"], s["format"], s["material"], s["name"]))
	_normalize(out, padding)
	return out


static func lightmap_unwrapped(snap: Array, padding: float) -> Dictionary:
	var tmp := ArrayMesh.new()
	var kept: Array = []
	for i in snap.size():
		var s: Dictionary = snap[i]
		var arrays: Array = (s["arrays"] as Array).duplicate(true)
		var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
		if not (verts is PackedVector3Array) or verts.is_empty():
			continue
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		if not (idx is PackedInt32Array) or idx.is_empty():
			var generated := PackedInt32Array()
			generated.resize(verts.size())
			for k in verts.size():
				generated[k] = k
			arrays[Mesh.ARRAY_INDEX] = generated
		tmp.add_surface_from_arrays(s["primitive"], arrays)
		kept.append(i)
	if tmp.get_surface_count() == 0:
		return {"ok": false, "error": "Нет данных вершин в меше"}
	var err: int = tmp.lightmap_unwrap(Transform3D.IDENTITY, 1.0)
	if err != OK:
		return {"ok": false, "error": "lightmap_unwrap: %s" % error_string(err)}
	var out: Array = []
	for gi in tmp.get_surface_count():
		var got: Array = tmp.surface_get_arrays(gi)
		var uv2: Variant = got[Mesh.ARRAY_TEX_UV2]
		if not (uv2 is PackedVector2Array) or uv2.is_empty():
			return {"ok": false, "error": "lightmap_unwrap не вернул UV2"}
		var s: Dictionary = snap[kept[gi]]
		var src: Array = s["arrays"]
		var src_verts: Variant = src[Mesh.ARRAY_VERTEX]
		var new_verts: Variant = got[Mesh.ARRAY_VERTEX]
		if new_verts is PackedVector3Array and src_verts is PackedVector3Array:
			if _same_vertices(new_verts, src_verts):
				got[Mesh.ARRAY_TEX_UV2] = src[Mesh.ARRAY_TEX_UV2]
		got[Mesh.ARRAY_TEX_UV] = uv2
		out.append(_entry(got, s["primitive"], s["format"], s["material"], s["name"]))
	_normalize(out, padding)
	return {"ok": true, "error": "", "surfaces": out}


static func _same_vertices(a: PackedVector3Array, b: PackedVector3Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not a[i].is_equal_approx(b[i]):
			return false
	return true


static func _normalize(surfaces: Array, padding: float) -> void:
	var found := false
	var mn := Vector2.ZERO
	var mx := Vector2.ZERO
	for s in surfaces:
		var arrays: Array = s["arrays"]
		var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
		if not (uvs is PackedVector2Array) or uvs.is_empty():
			continue
		for i in uvs.size():
			if not found:
				mn = uvs[i]
				mx = uvs[i]
				found = true
			else:
				mn = Vector2(minf(mn.x, uvs[i].x), minf(mn.y, uvs[i].y))
				mx = Vector2(maxf(mx.x, uvs[i].x), maxf(mx.y, uvs[i].y))
	if not found:
		return
	var ext := mx - mn
	var longest := maxf(ext.x, ext.y)
	if longest <= 0.000001:
		return
	var target := 1.0 - padding * 2.0
	var k := target / longest
	var offset := Vector2(
		padding + (target - ext.x * k) * 0.5,
		padding + (target - ext.y * k) * 0.5
	)
	for s in surfaces:
		var arrays: Array = s["arrays"]
		var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
		if not (uvs is PackedVector2Array) or uvs.is_empty():
			continue
		var fixed := PackedVector2Array()
		fixed.resize(uvs.size())
		for i in uvs.size():
			fixed[i] = (uvs[i] - mn) * k + offset
		arrays[Mesh.ARRAY_TEX_UV] = fixed
