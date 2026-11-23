extends SceneTree

const UVOps := preload("res://addons/mesh_simple_tool/uv_ops.gd")
const TMP_PATH := "res://tmp/mst_saved_check.tscn"


func _initialize() -> void:
	var packed := load("res://tmp/test.tscn") as PackedScene
	if packed == null:
		print("FAIL: no test scene")
		quit(1)
		return
	var root := packed.instantiate()
	var mi := root.find_child("MeshInstance3D", true, false) as MeshInstance3D
	if mi == null or mi.mesh == null or not (mi.mesh is ArrayMesh):
		print("FAIL: no ArrayMesh in test scene")
		root.free()
		quit(1)
		return
	var mesh := mi.mesh as ArrayMesh
	var snap := UVOps.snapshot(mesh)
	UVOps.apply(mesh, UVOps.box_unwrapped(snap, 0.02))
	var before := _first_uv(mesh)
	var packed_scene := PackedScene.new()
	if packed_scene.pack(root) != OK:
		print("FAIL: pack")
		root.free()
		quit(1)
		return
	var err := ResourceSaver.save(packed_scene, TMP_PATH)
	if err != OK:
		print("FAIL: save %s" % error_string(err))
		root.free()
		quit(1)
		return
	var reloaded := (load(TMP_PATH) as PackedScene).instantiate()
	var mi2 := reloaded.find_child("MeshInstance3D", true, false) as MeshInstance3D
	var after := _first_uv(mi2.mesh as ArrayMesh)
	if before.distance_to(after) < 1e-5:
		print("SAVE OK: uv %s -> %s" % [before, after])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))
		root.free()
		reloaded.free()
		quit(0)
	else:
		print("SAVE FAIL: uv %s -> %s" % [before, after])
		root.free()
		reloaded.free()
		quit(1)


func _first_uv(mesh: ArrayMesh) -> Vector2:
	var arrays: Array = mesh.surface_get_arrays(0)
	var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
	if uvs is PackedVector2Array and not uvs.is_empty():
		return uvs[0]
	return Vector2(-1, -1)
