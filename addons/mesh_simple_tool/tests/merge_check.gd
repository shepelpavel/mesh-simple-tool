extends SceneTree

const UVOps := preload("res://addons/mesh_simple_tool/uv_ops.gd")

var _failures := 0


func _initialize() -> void:
	_test_multisurface()
	_test_non_indexed()
	_test_empty()
	_test_materials()
	_test_custom_attribute()
	_test_quad()
	_test_degenerate()
	_test_normals()
	_test_uv_independent()
	_test_gather_strides()
	_test_supported()
	_test_scene_mesh()
	_finish()


func _two_surface_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for offset in [0.0, 5.0]:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
			Vector3(offset, 0, 0), Vector3(offset + 1, 0, 0), Vector3(offset, 1, 0),
			Vector3(offset, 0, 0), Vector3(offset + 1, 0, 0), Vector3(offset, 1, 0),
		])
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([
			Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1),
			Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1),
		])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 3, 4, 5])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _test_multisurface() -> void:
	var mesh := _two_surface_mesh()
	_expect(mesh.get_surface_count() == 2, "multi: two surfaces built")
	var snap := UVOps.snapshot(mesh)
	var scaled := UVOps.scaled(snap, UVOps.UV1, 0.5)
	var out := ArrayMesh.new()
	UVOps.apply(out, scaled)
	_expect(out.get_surface_count() == 2, "multi: scale keeps both surfaces")
	var merged := UVOps.merged(snap, 0.001, false)
	var merged_mesh := ArrayMesh.new()
	UVOps.apply(merged_mesh, merged["surfaces"])
	_expect(merged["merged"] == 6, "multi: merge counts both surfaces (got %d)" % merged["merged"])
	_expect(merged_mesh.get_surface_count() == 2, "multi: merge keeps both surfaces")
	for si in merged_mesh.get_surface_count():
		var idx: PackedInt32Array = merged_mesh.surface_get_arrays(si)[Mesh.ARRAY_INDEX]
		_expect(idx.size() == 6, "multi: surface %d keeps both triangles (got %d indices)" % [si, idx.size()])


func _test_non_indexed() -> void:
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0),
	])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1),
	])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var snap := UVOps.snapshot(mesh)
	var merged := UVOps.merged(snap, 0.001, false)
	_expect(merged["ok"], "non-indexed: merge ok")
	var out := ArrayMesh.new()
	UVOps.apply(out, merged["surfaces"])
	var idx: Variant = out.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	_expect(idx is PackedInt32Array and idx.size() == 3, "non-indexed: indices generated")
	var box := ArrayMesh.new()
	UVOps.apply(box, UVOps.box_unwrapped(snap, 0.02))
	var box_uv: Variant = box.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	_expect(box_uv is PackedVector2Array and box_uv.size() == 3, "non-indexed: box unwrap filled uv")


func _test_empty() -> void:
	var mesh := ArrayMesh.new()
	var snap := UVOps.snapshot(mesh)
	_expect(snap.is_empty(), "empty: snapshot is empty")
	var merged := UVOps.merged(snap, 0.01, true)
	_expect(merged["ok"] and merged["surfaces"].is_empty(), "empty: merge returns empty result")
	UVOps.apply(mesh, merged["surfaces"])
	_expect(mesh.get_surface_count() == 0, "empty: apply keeps mesh empty")
	var stats := UVOps.merge_stats(snap, 0.01, true)
	_expect(stats["merged"] == 0, "empty: stats are zero")


func _test_normals() -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0),
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0),
	])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1),
		Vector3(0, 1, 0), Vector3(0, 1, 0), Vector3(0, 1, 0),
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 3, 4, 5])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var snap := UVOps.snapshot(mesh)
	var keep: Dictionary = UVOps.merged(snap, 0.001, true)
	_expect(keep["merged"] == 0, "normals: different normals are not merged (got %d)" % keep["merged"])
	var loose: Dictionary = UVOps.merged(snap, 0.001, false)
	_expect(loose["merged"] == 3, "normals: ignoring normals merges all (got %d)" % loose["merged"])


func _test_uv_independent() -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0),
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0),
	])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1),
		Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1),
	])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(0, 1),
		Vector2(0.5, 0.5), Vector2(0.6, 0.5), Vector2(0.5, 0.6),
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 3, 4, 5])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var snap := UVOps.snapshot(mesh)
	var keep: Dictionary = UVOps.merged(snap, 0.001, true)
	_expect(keep["merged"] == 3, "uv: different uv does not block merge with normals kept (got %d)" % keep["merged"])


func _test_gather_strides() -> void:
	var roots := PackedInt32Array([0, 2])
	var f2 := PackedFloat32Array([0.0, 0.0, 1.0, 1.0, 2.0, 2.0])
	var gathered_f := UVOps._gather(f2, roots, 3)
	_expect(gathered_f is PackedFloat32Array and gathered_f.size() == 4, "gather: float stride 2 kept")
	var i8 := PackedInt32Array()
	i8.resize(24)
	for i in i8.size():
		i8[i] = i
	var gathered_i := UVOps._gather(i8, roots, 3)
	_expect(gathered_i is PackedInt32Array and gathered_i.size() == 16, "gather: int stride 8 kept")
	var bytes := PackedByteArray([0, 0, 0, 255, 255, 0, 0, 255, 0, 255, 0, 255, 9, 9, 9, 9, 8, 8, 8, 8, 7, 7, 7, 7])
	var gathered_b := UVOps._gather(bytes, roots, 6)
	_expect(gathered_b is PackedByteArray and gathered_b.size() == 8, "gather: byte custom attribute kept")
	var bad := PackedFloat32Array([0.0, 1.0, 2.0, 3.0, 4.0])
	_expect(UVOps._gather(bad, roots, 3) == null, "gather: mismatched size rejected")


func _test_custom_attribute() -> void:
	var mesh := _two_surface_mesh()
	var arrays: Array = mesh.surface_get_arrays(0)
	arrays[Mesh.ARRAY_CUSTOM0] = PackedByteArray([
		0, 0, 0, 255, 255, 0, 0, 255, 0, 255, 0, 255,
		0, 0, 0, 255, 255, 0, 0, 255, 0, 255, 0, 255,
	])
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var merged := UVOps.merged(UVOps.snapshot(mesh), 0.001, false)
	_expect(merged["ok"], "custom: merge accepts byte custom attribute")
	if merged["ok"]:
		var out := ArrayMesh.new()
		UVOps.apply(out, merged["surfaces"])
		var got: Variant = out.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0]
		_expect(got is PackedByteArray and got.size() == 12, "custom: attribute rebuilt for 3 vertices")


func _test_materials() -> void:
	var mesh := _two_surface_mesh()
	var mat0 := StandardMaterial3D.new()
	var mat1 := StandardMaterial3D.new()
	mat1.albedo_color = Color(1, 0, 0)
	mesh.surface_set_material(0, mat0)
	mesh.surface_set_material(1, mat1)
	mesh.surface_set_name(0, "first")
	mesh.surface_set_name(1, "second")
	var out := ArrayMesh.new()
	UVOps.apply(out, UVOps.scaled(UVOps.snapshot(mesh), UVOps.UV1, 0.5))
	_expect(out.surface_get_material(0) == mat0 and out.surface_get_material(1) == mat1, "materials: kept after rebuild")
	_expect(out.surface_get_name(0) == "first" and out.surface_get_name(1) == "second", "materials: surface names kept")


func _test_supported() -> void:
	var mesh := ArrayMesh.new()
	_expect(UVOps.check_supported(mesh) == "", "supported: plain mesh ok")
	mesh.add_blend_shape("a")
	_expect(UVOps.check_supported(mesh) != "", "supported: blend shapes rejected")


func _test_quad() -> void:
	var mesh := _quad_mesh()
	var snap := UVOps.snapshot(mesh)
	var result: Dictionary = UVOps.merged(snap, 0.001)
	_expect(result["merged"] == 2, "quad: merged 2 (got %d)" % result["merged"])
	_expect(result["removed_tris"] == 0, "quad: no removed tris (got %d)" % result["removed_tris"])
	var out := ArrayMesh.new()
	UVOps.apply(out, result["surfaces"])
	var arrays: Array = out.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	_expect(verts.size() == 4, "quad: 4 vertices (got %d)" % verts.size())
	_expect(idx.size() == 6, "quad: 6 indices (got %d)" % idx.size())
	_expect(_indices_valid(idx, verts.size()), "quad: indices in range")
	_expect(uvs.size() == verts.size(), "quad: uv size matches vertices")
	var uv0 := uvs[idx[0]]
	_expect(uv0.distance_to(Vector2(0.0, 0.0)) < 1e-5, "quad: uv of first vertex kept (%s)" % uv0)


func _test_degenerate() -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0),
		Vector3(0.00001, 0, 0), Vector3(1.00001, 0, 0), Vector3(0.00001, 0.00001, 0),
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 3, 4, 5])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var result: Dictionary = UVOps.merged(UVOps.snapshot(mesh), 0.001)
	_expect(result["removed_tris"] == 1, "degenerate: one triangle removed (got %d)" % result["removed_tris"])
	var out := ArrayMesh.new()
	UVOps.apply(out, result["surfaces"])
	_expect(out.get_surface_count() == 1, "degenerate: single surface kept")
	var idx: PackedInt32Array = out.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	_expect(idx.size() == 3, "degenerate: one triangle left (got %d indices)" % idx.size())


func _test_scene_mesh() -> void:
	var packed := load("res://tmp/test.tscn") as PackedScene
	if packed == null:
		_fail("scene: cannot load res://tmp/test.tscn")
		return
	var root := packed.instantiate()
	var mi := root.find_child("MeshInstance3D", true, false) as MeshInstance3D
	if mi == null or mi.mesh == null:
		_fail("scene: no MeshInstance3D with a mesh")
		root.free()
		return
	var mesh := mi.mesh as ArrayMesh
	if mesh == null:
		_fail("scene: mesh is not ArrayMesh")
		root.free()
		return
	var snap := UVOps.snapshot(mesh)
	var before: int = mesh.surface_get_array_len(0)
	var unique := {}
	for v in (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		unique[Vector3i(roundi(v.x * 1000000.0), roundi(v.y * 1000000.0), roundi(v.z * 1000000.0))] = true
	print("scene: %d vertices, %d unique positions" % [before, unique.size()])
	var zero: Dictionary = UVOps.merged(snap, 0.0)
	var zero_mesh := ArrayMesh.new()
	UVOps.apply(zero_mesh, zero["surfaces"])
	_expect(zero["merged"] <= before - unique.size(), "scene: keep-shading merges no more than exact duplicates (%d)" % zero["merged"])
	_expect(zero_mesh.surface_get_array_len(0) >= unique.size(), "scene: vertices with distinct normals or UV stay separate")
	var result: Dictionary = UVOps.merged(snap, 0.01)
	var out := ArrayMesh.new()
	UVOps.apply(out, result["surfaces"])
	var arrays: Array = out.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	print("scene: %d -> %d vertices, merged %d, removed %d tris" % [
		before, verts.size(), result["merged"], result["removed_tris"]
	])
	_expect(verts.size() <= zero_mesh.surface_get_array_len(0), "scene: wider distance merges no fewer vertices")
	_expect(_indices_valid(idx, verts.size()), "scene: indices in range")
	_expect(arrays[Mesh.ARRAY_TEX_UV] != null, "scene: uv kept")
	var stats: Dictionary = UVOps.merge_stats(snap, 0.01)
	_expect(stats["merged"] == result["merged"], "scene: stats merged matches applied (%d)" % stats["merged"])
	_expect(stats["removed_tris"] == result["removed_tris"], "scene: stats removed matches applied")
	var normals_before := _normal_set(mesh)
	var normals_after := _normal_set(out)
	_expect(normals_after.size() <= normals_before.size(), "scene: merge keeps existing normals, no new ones")
	if (int(snap[0]["format"]) & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0:
		_expect(
			(out.surface_get_format(0) & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0,
			"scene: compression flag preserved after rebuild"
		)
	var box := ArrayMesh.new()
	UVOps.apply(box, UVOps.box_unwrapped(UVOps.snapshot(out), 0.02))
	_expect(_tri_area_sum(box, UVOps.UV1) > 0.05, "scene: box unwrap after merge is not collapsed (%.3f)" % _tri_area_sum(box, UVOps.UV1))
	var loose: Dictionary = UVOps.merged(snap, 0.01, false)
	_expect(loose["merged"] == before - unique.size(), "scene: position-only merge collapses all duplicates (%d)" % loose["merged"])
	var loose_mesh := ArrayMesh.new()
	UVOps.apply(loose_mesh, loose["surfaces"])
	_expect(loose_mesh.surface_get_array_len(0) == unique.size(), "scene: position-only result equals unique positions (%d)" % loose_mesh.surface_get_array_len(0))
	root.free()


func _quad_mesh() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0),
		Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0),
	])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(0, 1),
		Vector2(0, 0), Vector2(0, 1), Vector2(1, 1),
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 3, 4, 5])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _tri_area_sum(mesh: ArrayMesh, channel: int) -> float:
	var total := 0.0
	for si in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(si)
		var uvs: Variant = arrays[channel]
		if not (uvs is PackedVector2Array) or uvs.is_empty():
			continue
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		if idx is PackedInt32Array and not idx.is_empty():
			var i := 0
			while i + 2 < idx.size():
				total += absf(_tri_area(uvs[idx[i]], uvs[idx[i + 1]], uvs[idx[i + 2]]))
				i += 3
		else:
			var i := 0
			while i + 2 < uvs.size():
				total += absf(_tri_area(uvs[i], uvs[i + 1], uvs[i + 2]))
				i += 3
	return total


func _tri_area(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (b - a).cross(c - a) * 0.5


func _normal_set(mesh: ArrayMesh) -> Dictionary:
	var out := {}
	for si in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(si)
		var normals: Variant = arrays[Mesh.ARRAY_NORMAL]
		if not (normals is PackedVector3Array):
			continue
		for n in normals:
			out["%.3f|%.3f|%.3f" % [n.x, n.y, n.z]] = true
	return out


func _indices_valid(idx: PackedInt32Array, count: int) -> bool:
	if idx.is_empty() or idx.size() % 3 != 0:
		return false
	for i in idx.size():
		if idx[i] < 0 or idx[i] >= count:
			return false
	for t in range(0, idx.size(), 3):
		if idx[t] == idx[t + 1] or idx[t + 1] == idx[t + 2] or idx[t] == idx[t + 2]:
			return false
	return true


func _expect(ok: bool, label: String) -> void:
	if ok:
		print("  ok   %s" % label)
	else:
		_fail(label)


func _fail(label: String) -> void:
	_failures += 1
	print("  FAIL %s" % label)


func _finish() -> void:
	if _failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % _failures)
	quit(0 if _failures == 0 else 1)
