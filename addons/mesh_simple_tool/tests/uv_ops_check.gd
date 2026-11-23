extends SceneTree

const UVOps := preload("res://addons/mesh_simple_tool/uv_ops.gd")

var _failures := 0
var _root: Node


func _initialize() -> void:
	var packed := load("res://tmp/test.tscn") as PackedScene
	if packed == null:
		_fail("cannot load res://tmp/test.tscn")
		_finish()
		return
	var root := packed.instantiate()
	_root = root
	var mi := root.find_child("MeshInstance3D", true, false) as MeshInstance3D
	if mi == null:
		_fail("no MeshInstance3D in test scene")
		_finish()
		return
	var mesh := mi.mesh as ArrayMesh
	if mesh == null:
		_fail("mesh is not ArrayMesh")
		_finish()
		return
	print("surfaces: %d, vertices: %d" % [mesh.get_surface_count(), mesh.surface_get_array_len(0)])
	var snap := UVOps.snapshot(mesh)
	print("has UV1: %s, has UV2: %s" % [UVOps.has_channel(snap, UVOps.UV1), UVOps.has_channel(snap, UVOps.UV2)])
	var uv2_before := _uv_channel(mesh, UVOps.UV2)
	var rect_before := _uv_rect(uv2_before)
	var center_before := rect_before.get_center()

	UVOps.apply(mesh, UVOps.scaled(snap, UVOps.UV2, 0.5))
	var uv2_scaled := _uv_channel(mesh, UVOps.UV2)
	var rect_after := _uv_rect(uv2_scaled)
	var center_after := rect_after.get_center()
	_expect(absf(rect_after.size.x - rect_before.size.x * 0.5) < 1e-4, "UV2 scale x (%.6f vs %.6f)" % [rect_after.size.x, rect_before.size.x * 0.5])
	_expect(absf(rect_after.size.y - rect_before.size.y * 0.5) < 1e-4, "UV2 scale y (%.6f vs %.6f)" % [rect_after.size.y, rect_before.size.y * 0.5])
	_expect(center_after.distance_to(center_before) < 1e-4, "UV2 pivot kept")

	UVOps.apply(mesh, snap)
	var uv2_restored := _uv_channel(mesh, UVOps.UV2)
	_expect(_same(uv2_before, uv2_restored), "UV2 restored after cancel")

	UVOps.apply(mesh, UVOps.box_unwrapped(snap, 0.02))
	var box_uv := _uv_channel(mesh, UVOps.UV1)
	_expect(_in_range(box_uv, 0.0, 1.0), "box unwrap inside 0..1")
	_expect(_tri_area_sum(mesh, UVOps.UV1) > 0.05, "box unwrap is not collapsed (uv area %.3f)" % _tri_area_sum(mesh, UVOps.UV1))

	UVOps.apply(mesh, UVOps.cylindrical_unwrapped(snap, 0.02))
	var cyl_uv := _uv_channel(mesh, UVOps.UV1)
	_expect(_in_range(cyl_uv, 0.0, 1.0), "cylindrical unwrap inside 0..1")

	UVOps.apply(mesh, snap)
	var result: Dictionary = UVOps.lightmap_unwrapped(snap, 0.02)
	_expect(result["ok"], "lightmap unwrap ok (%s)" % String(result.get("error", "")))
	if result["ok"]:
		var lm := ArrayMesh.new()
		UVOps.apply(lm, result["surfaces"])
		var lm_uv := _uv_channel(lm, UVOps.UV1)
		_expect(_in_range(lm_uv, 0.0, 1.0), "lightmap unwrap inside 0..1")
		_expect(_uv_rect(lm_uv).get_area() > 0.3, "lightmap unwrap fills (area %.3f)" % _uv_rect(lm_uv).get_area())
		if _same(uv2_before, _uv_channel(lm, UVOps.UV2)):
			print("  ok   lightmap unwrap keeps original UV2")
		else:
			print("  info lightmap unwrap changed topology, UV2 replaced by the new unwrap")
		print("lightmap unwrap vertices: %d -> %d" % [uv2_before.size(), lm_uv.size()])

	_finish()


func _uv_channel(mesh: ArrayMesh, channel: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(i)
		var uvs: Variant = arrays[channel]
		if uvs is PackedVector2Array:
			out.append_array(uvs)
	return out


func _uv_rect(uvs: PackedVector2Array) -> Rect2:
	if uvs.is_empty():
		return Rect2()
	var mn := uvs[0]
	var mx := uvs[0]
	for p in uvs:
		mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
		mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
	return Rect2(mn, mx - mn)


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


func _in_range(uvs: PackedVector2Array, lo: float, hi: float) -> bool:
	if uvs.is_empty():
		return false
	for p in uvs:
		if is_nan(p.x) or is_nan(p.y):
			return false
		if p.x < lo - 1e-5 or p.x > hi + 1e-5 or p.y < lo - 1e-5 or p.y > hi + 1e-5:
			return false
	return true


func _same(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].distance_to(b[i]) > 1e-6:
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
	if is_instance_valid(_root):
		_root.free()
	if _failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % _failures)
	quit(0 if _failures == 0 else 1)
