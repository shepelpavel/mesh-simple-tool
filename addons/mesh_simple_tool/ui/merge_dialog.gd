@tool
extends ConfirmationDialog

const UVOps := preload("../uv_ops.gd")

const STATS_INTERVAL_MS := 100
const BIG_MESH_VERTS := 30000

var _mesh_instance: MeshInstance3D
var _snapshot: Array = []
var _max_distance := 0.01
var _distance := 0.001
var _diagonal := 0.0
var _slider: HSlider
var _spin: SpinBox
var _info: Label
var _keep_shading: CheckBox
var _stats_pending := false
var _last_stats_ms := 0
var _vertex_count := 0


func _init() -> void:
	title = "Merge by distance"
	exclusive = true
	min_size = Vector2i(460, 0)
	ok_button_text = "Применить"
	cancel_button_text = "Отмена"
	_build()
	confirmed.connect(_on_confirmed)


func _build() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var label := Label.new()
	label.text = "Distance:"
	row.add_child(label)
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 0.01
	_slider.step = 0.00001
	_slider.value = 0.001
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.custom_minimum_size = Vector2(240, 0)
	row.add_child(_slider)
	_spin = SpinBox.new()
	_spin.min_value = 0.0
	_spin.max_value = 1000.0
	_spin.step = 0.0001
	_spin.value = 0.001
	_spin.custom_minimum_size = Vector2(110, 0)
	row.add_child(_spin)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_color_override("font_color", Color(0.62, 0.66, 0.70))
	box.add_child(_info)
	_keep_shading = CheckBox.new()
	_keep_shading.text = "Сохранять плоское затенение (учитывать нормали)"
	_keep_shading.button_pressed = true
	_keep_shading.tooltip_text = "Не сливать вершины с разными нормалями: hard edges останутся на месте"
	box.add_child(_keep_shading)
	_keep_shading.toggled.connect(_on_keep_shading_toggled)
	_slider.value_changed.connect(_on_slider_changed)
	_slider.drag_ended.connect(_on_slider_drag_ended)
	_spin.value_changed.connect(_on_spin_changed)


func open(mesh_instance: MeshInstance3D) -> void:
	if not is_instance_valid(mesh_instance):
		return
	var mesh := UVOps.ensure_array_mesh(mesh_instance)
	if mesh == null:
		push_warning("MST: mesh type is not supported (need ArrayMesh or PrimitiveMesh)")
		return
	var reason := UVOps.check_supported(mesh)
	if reason != "":
		push_warning("MST: " + reason)
		return
	_mesh_instance = mesh_instance
	_snapshot = UVOps.snapshot(mesh)
	_vertex_count = 0
	for s in _snapshot:
		var verts: Variant = (s["arrays"] as Array)[Mesh.ARRAY_VERTEX]
		if verts is PackedVector3Array:
			_vertex_count += verts.size()
	var aabb := mesh.get_aabb()
	_diagonal = aabb.size.length()
	_max_distance = clampf(_diagonal * 0.005, 0.0001, 100.0)
	var start := maxf(_diagonal * 0.001, _max_distance * 0.001)
	_slider.min_value = 0.0
	_slider.max_value = _max_distance
	_slider.step = _max_distance / 1000.0
	_slider.set_value_no_signal(start)
	_spin.min_value = 0.0
	_spin.max_value = _max_distance
	_spin.step = _max_distance / 10000.0
	_spin.set_value_no_signal(start)
	_distance = start
	_refresh_info(true)
	popup_centered(Vector2i(500, 150))


func _refresh_info(force: bool = false) -> void:
	if _vertex_count > BIG_MESH_VERTS and not force:
		_info.text = "Меш большой (%d вершин): отпустите ползунок или переключите галочку для расчёта." % _vertex_count
		return
	if _stats_pending:
		return
	_stats_pending = true
	var elapsed := Time.get_ticks_msec() - _last_stats_ms
	if elapsed >= STATS_INTERVAL_MS:
		_update_stats.call_deferred()
		return
	var timer := get_tree().create_timer((STATS_INTERVAL_MS - elapsed) / 1000.0)
	timer.timeout.connect(_update_stats, CONNECT_ONE_SHOT)


func _update_stats() -> void:
	_stats_pending = false
	_last_stats_ms = Time.get_ticks_msec()
	if _snapshot.is_empty():
		_info.text = ""
		return
	var keep_on: bool = _keep_shading.button_pressed
	var loose_stats: Dictionary = UVOps.merge_stats(_snapshot, _distance, false)
	var keep_stats: Dictionary = UVOps.merge_stats(_snapshot, _distance, true)
	var main_stats: Dictionary = keep_stats if keep_on else loose_stats
	var other_stats: Dictionary = loose_stats if keep_on else keep_stats
	var percent := 0.0
	if _diagonal > 0.0:
		percent = _distance / _diagonal * 100.0
	var lines := PackedStringArray()
	lines.append("Distance %.6f (%.3f%% диагонали меша)." % [_distance, percent])
	if main_stats["merged"] > 0:
		lines.append("Будет слито %d вершин, удалено %d треугольников." % [
			main_stats["merged"], main_stats["removed_tris"]
		])
	else:
		lines.append("Слияние ничего не изменит.")
	if keep_on:
		lines.append("Если не учитывать нормали, слилось бы %d (нормали усреднятся)." % other_stats["merged"])
	else:
		lines.append("С сохранением затенения слилось бы %d." % other_stats["merged"])
	_info.text = " ".join(lines)


func _on_keep_shading_toggled(_pressed: bool) -> void:
	_refresh_info(true)


func _on_slider_drag_ended(_value_changed: bool) -> void:
	_refresh_info(true)


func _on_slider_changed(value: float) -> void:
	if not is_equal_approx(_spin.value, value):
		_spin.set_value_no_signal(value)
	_distance = value
	_refresh_info()


func _on_spin_changed(value: float) -> void:
	if not is_equal_approx(_slider.value, value):
		_slider.set_value_no_signal(value)
	_distance = value
	_refresh_info(true)


func _on_confirmed() -> void:
	if not is_instance_valid(_mesh_instance) or _mesh_instance.mesh == null:
		return
	var mesh := _mesh_instance.mesh as ArrayMesh
	if mesh == null:
		return
	var result: Dictionary = UVOps.merged(_snapshot, _distance, _keep_shading.button_pressed)
	if not result["ok"]:
		if Engine.is_editor_hint():
			EditorInterface.get_editor_toaster().push_toast("MST: " + String(result["error"]))
		_mesh_instance = null
		return
	UVOps.apply(mesh, result["surfaces"])
	if Engine.is_editor_hint():
		EditorInterface.set_object_edited(mesh, true)
		EditorInterface.mark_scene_as_unsaved()
		EditorInterface.get_editor_toaster().push_toast(
			"MST: слито %d вершин, удалено %d треугольников." % [result["merged"], result["removed_tris"]]
		)
	_mesh_instance = null
