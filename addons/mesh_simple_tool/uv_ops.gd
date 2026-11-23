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


const KEEP_FORMAT_FLAGS := (Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
	| Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE
	| Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	| Mesh.ARRAY_FLAG_USES_EMPTY_VERTEX_ARRAY)


static func apply(mesh: ArrayMesh, surfaces: Array) -> void:
	mesh.clear_surfaces()
	for s in surfaces:
		var arrays: Array = s["arrays"]
		if arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		var flags: int = int(s["format"]) & KEEP_FORMAT_FLAGS
		mesh.add_surface_from_arrays(s["primitive"], arrays, [], {}, flags)
		var idx: int = mesh.get_surface_count() - 1
		var material: Material = s["material"]
		if material != null:
			mesh.surface_set_material(idx, material)
		var sname: String = s["name"]
		if sname != "":
			mesh.surface_set_name(idx, sname)
	mesh.emit_changed()


static func check_supported(mesh: ArrayMesh) -> String:
	if mesh.get_blend_shape_count() > 0:
		return "меш содержит blend shapes, операция удалила бы их — отменено"
	return ""


static func has_channel(snap: Array, channel: int) -> bool:
	for s in snap:
		var arrays: Array = s["arrays"]
		var uvs: Variant = arrays[channel]
		if uvs is PackedVector2Array and not uvs.is_empty():
			return true
	return false


static func scaled(snap: Array, channel: int, factor: float) -> Array:
	var pivot := Vector2.ZERO
	var found := false
	var mn := Vector2.ZERO
	var mx := Vector2.ZERO
	for s in snap:
		var uvs: Variant = (s["arrays"] as Array)[channel]
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
		return snap
	pivot = (mn + mx) * 0.5
	var out: Array = []
	for s in snap:
		var arrays: Array = (s["arrays"] as Array).duplicate(true)
		var uvs: Variant = arrays[channel]
		if uvs is PackedVector2Array and not uvs.is_empty():
			var moved := PackedVector2Array()
			moved.resize(uvs.size())
			for i in uvs.size():
				moved[i] = pivot + (uvs[i] - pivot) * factor
			arrays[channel] = moved
		out.append(_entry(arrays, s["primitive"], s["format"], s["material"], s["name"]))
	return out


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


static func merged(snap: Array, distance: float, keep_shading: bool = true) -> Dictionary:
	var tol: float = maxf(distance, 0.000001)
	var out: Array = []
	var merged_count := 0
	var removed_tris := 0
	for s in snap:
		var arrays: Array = (s["arrays"] as Array).duplicate(true)
		var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
		if not (verts is PackedVector3Array) or verts.is_empty():
			out.append(_entry(arrays, s["primitive"], s["format"], s["material"], s["name"]))
			continue
		var count: int = verts.size()
		var grouping := _group_positions(verts, tol, arrays[Mesh.ARRAY_NORMAL], keep_shading)
		var roots: Array = grouping["of"]
		var root_order: PackedInt32Array = grouping["roots"]
		var root_slot: Dictionary = grouping["slot"]
		merged_count += count - root_order.size()
		var normals: Variant = arrays[Mesh.ARRAY_NORMAL]
		var averaged := PackedVector3Array()
		if normals is PackedVector3Array and normals.size() == count:
			var sums := PackedVector3Array()
			sums.resize(count)
			for i in count:
				sums[i] = Vector3.ZERO
			for i in count:
				sums[roots[i]] = sums[roots[i]] + normals[i]
			averaged.resize(root_order.size())
			for k in root_order.size():
				var n: Vector3 = sums[root_order[k]]
				averaged[k] = n.normalized() if n.length_squared() > 0.0000001 else Vector3.UP
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		var tri_src := PackedInt32Array()
		if idx is PackedInt32Array and not idx.is_empty():
			tri_src = idx
		else:
			tri_src.resize(count)
			for i in count:
				tri_src[i] = i
		var new_idx := PackedInt32Array()
		for t in range(0, tri_src.size() - 2, 3):
			var a: int = root_slot[roots[tri_src[t]]]
			var b: int = root_slot[roots[tri_src[t + 1]]]
			var c: int = root_slot[roots[tri_src[t + 2]]]
			if a == b or b == c or a == c:
				removed_tris += 1
				continue
			new_idx.append(a)
			new_idx.append(b)
			new_idx.append(c)
		var compact := PackedInt32Array()
		compact.resize(root_order.size())
		for i in compact.size():
			compact[i] = -1
		var final_roots := PackedInt32Array()
		for v in new_idx.size():
			var g: int = new_idx[v]
			if compact[g] < 0:
				compact[g] = final_roots.size()
				final_roots.append(root_order[g])
			new_idx[v] = compact[g]
		if new_idx.is_empty():
			continue
		for key in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR,
				Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1,
				Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
			var src: Variant = arrays[key]
			if src == null:
				continue
			var gathered: Variant = _gather(src, final_roots, count)
			if gathered == null:
				return {
					"ok": false,
					"error": "канал %d имеет неподдерживаемый формат, меш не изменён" % key,
					"surfaces": [],
					"merged": 0,
					"removed_tris": 0,
				}
			arrays[key] = gathered
		if normals is PackedVector3Array and normals.size() == count and averaged.size() > 0:
			var out_normals := PackedVector3Array()
			out_normals.resize(final_roots.size())
			for k in final_roots.size():
				out_normals[k] = averaged[root_slot[final_roots[k]]]
			arrays[Mesh.ARRAY_NORMAL] = out_normals
		arrays[Mesh.ARRAY_INDEX] = new_idx
		out.append(_entry(arrays, s["primitive"], s["format"], s["material"], s["name"]))
	return {"ok": true, "surfaces": out, "merged": merged_count, "removed_tris": removed_tris}


static func merge_stats(snap: Array, distance: float, keep_shading: bool = true) -> Dictionary:
	var tol: float = maxf(distance, 0.000001)
	var merged := 0
	var removed := 0
	for s in snap:
		var arrays: Array = s["arrays"]
		var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
		if not (verts is PackedVector3Array) or verts.is_empty():
			continue
		var grouping := _group_positions(verts, tol, arrays[Mesh.ARRAY_NORMAL], keep_shading)
		var roots: Array = grouping["of"]
		var root_order: PackedInt32Array = grouping["roots"]
		var root_slot: Dictionary = grouping["slot"]
		merged += verts.size() - root_order.size()
		removed += _degenerate_count(arrays, roots, root_slot)
	return {"merged": merged, "removed_tris": removed}


static func _degenerate_count(arrays: Array, roots: Array, root_slot: Dictionary) -> int:
	var idx: Variant = arrays[Mesh.ARRAY_INDEX]
	var removed := 0
	if idx is PackedInt32Array and not idx.is_empty():
		for t in range(0, idx.size() - 2, 3):
			var a: int = root_slot[roots[idx[t]]]
			var b: int = root_slot[roots[idx[t + 1]]]
			var c: int = root_slot[roots[idx[t + 2]]]
			if a == b or b == c or a == c:
				removed += 1
	else:
		var count: int = roots.size()
		for t in range(0, count - 2, 3):
			var a: int = root_slot[roots[t]]
			var b: int = root_slot[roots[t + 1]]
			var c: int = root_slot[roots[t + 2]]
			if a == b or b == c or a == c:
				removed += 1
	return removed


static func _group_positions(verts: PackedVector3Array, tol: float, normals: Variant = null,
		keep_shading: bool = true) -> Dictionary:
	var count := verts.size()
	var has_normals: bool = keep_shading and normals is PackedVector3Array and normals.size() == count
	var parent: Array = []
	parent.resize(count)
	for i in count:
		parent[i] = i
	var inv := 1.0 / tol
	var tol_sq := tol * tol
	var cells := {}
	for i in count:
		var p: Vector3 = verts[i]
		var key := Vector3i(floori(p.x * inv), floori(p.y * inv), floori(p.z * inv))
		if not cells.has(key):
			cells[key] = []
		var bucket: Array = cells[key]
		bucket.append(i)
	for i in count:
		var p: Vector3 = verts[i]
		var base := Vector3i(floori(p.x * inv), floori(p.y * inv), floori(p.z * inv))
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					var key := base + Vector3i(dx, dy, dz)
					if not cells.has(key):
						continue
					for j in cells[key]:
						if j <= i:
							continue
						if p.distance_squared_to(verts[j]) > tol_sq:
							continue
						if has_normals and normals[i].dot(normals[j]) < 0.9999:
							continue
						_union(parent, i, j)
	var roots: Array = []
	roots.resize(count)
	var root_order := PackedInt32Array()
	var root_slot := {}
	for i in count:
		var r := _find(parent, i)
		roots[i] = r
		if not root_slot.has(r):
			root_slot[r] = root_order.size()
			root_order.append(r)
	return {"of": roots, "roots": root_order, "slot": root_slot}


static func _gather(src: Variant, roots: PackedInt32Array, count: int) -> Variant:
	if src is PackedVector3Array:
		if src.size() != count:
			return null
		var a := PackedVector3Array()
		a.resize(roots.size())
		for i in roots.size():
			a[i] = src[roots[i]]
		return a
	if src is PackedVector2Array:
		if src.size() != count:
			return null
		var a := PackedVector2Array()
		a.resize(roots.size())
		for i in roots.size():
			a[i] = src[roots[i]]
		return a
	if src is PackedColorArray:
		if src.size() != count:
			return null
		var a := PackedColorArray()
		a.resize(roots.size())
		for i in roots.size():
			a[i] = src[roots[i]]
		return a
	if src is PackedByteArray:
		if count <= 0 or src.size() % count != 0:
			return null
		var stride: int = src.size() / count
		if stride <= 0:
			return null
		var a := PackedByteArray()
		a.resize(roots.size() * stride)
		for i in roots.size():
			var src_off: int = roots[i] * stride
			var dst_off: int = i * stride
			for k in stride:
				a[dst_off + k] = src[src_off + k]
		return a
	if src is PackedFloat32Array:
		var stride := _stride_for(src.size(), count)
		if stride == 0:
			return null
		var a := PackedFloat32Array()
		a.resize(roots.size() * stride)
		for i in roots.size():
			for k in stride:
				a[i * stride + k] = src[roots[i] * stride + k]
		return a
	if src is PackedInt32Array:
		var stride := _stride_for(src.size(), count)
		if stride == 0:
			return null
		var a := PackedInt32Array()
		a.resize(roots.size() * stride)
		for i in roots.size():
			for k in stride:
				a[i * stride + k] = src[roots[i] * stride + k]
		return a
	return null


static func _stride_for(total: int, count: int) -> int:
	for stride in [1, 2, 4, 8]:
		if total == count * stride:
			return stride
	return 0


static func _find(parent: Array, i: int) -> int:
	var root: int = i
	while parent[root] != root:
		root = parent[root]
	while parent[i] != root:
		var next: int = parent[i]
		parent[i] = root
		i = next
	return root


static func _union(parent: Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra == rb:
		return
	if ra < rb:
		parent[rb] = ra
	else:
		parent[ra] = rb


static func _same_vertices(a: PackedVector3Array, b: PackedVector3Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].distance_squared_to(b[i]) > 0.00000001:
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
