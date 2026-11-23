@tool
extends ConfirmationDialog

const UVOps := preload("../uv_ops.gd")

var _mesh_instance: MeshInstance3D
var _channel := 0
var _snapshot: Array = []
var _has_channel := false
var _applied := false
var _slider: HSlider
var _spin: SpinBox
var _hint: Label


func _init() -> void:
	title = "Scale UV"
	exclusive = true
	min_size = Vector2i(380, 0)
	ok_button_text = "Применить"
	cancel_button_text = "Отмена"
	_build()
	confirmed.connect(_on_confirmed)
	visibility_changed.connect(_on_visibility_changed)


func _build() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_slider = HSlider.new()
	_slider.min_value = 0.1
	_slider.max_value = 100.0
	_slider.step = 0.01
	_slider.value = 1.0
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.custom_minimum_size = Vector2(220, 0)
	row.add_child(_slider)
	_spin = SpinBox.new()
	_spin.min_value = 0.1
	_spin.max_value = 100.0
	_spin.step = 0.001
	_spin.value = 1.0
	_spin.custom_minimum_size = Vector2(96, 0)
	row.add_child(_spin)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override("font_color", Color(0.75, 0.62, 0.35))
	box.add_child(_hint)
	_slider.value_changed.connect(_on_slider_changed)
	_spin.value_changed.connect(_on_spin_changed)


func open(mesh_instance: MeshInstance3D, channel: int) -> void:
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
	_channel = channel
	_snapshot = UVOps.snapshot(mesh)
	_applied = false
	title = "Scale UV2" if channel == UVOps.UV2 else "Scale UV"
	_slider.set_value_no_signal(1.0)
	_spin.set_value_no_signal(1.0)
	_hint.text = ""
	_has_channel = UVOps.has_channel(_snapshot, channel)
	if not _has_channel:
		_hint.text = "У меша нет канала %s — масштабировать нечего." % ("UV2" if channel == UVOps.UV2 else "UV")
	_check_hint()
	popup_centered(Vector2i(420, 130))


func _check_hint() -> void:
	if not is_instance_valid(_mesh_instance) or _mesh_instance.mesh == null:
		_hint.text = "Нода меша недоступна."
		return
	var shared := 0
	var root := EditorInterface.get_edited_scene_root()
	if root != null:
		for n in root.find_children("*", "MeshInstance3D", true, false):
			if n != _mesh_instance and (n as MeshInstance3D).mesh == _mesh_instance.mesh:
				shared += 1
	if shared > 0:
		var prefix := _hint.text
		if prefix != "":
			prefix += " "
		_hint.text = prefix + "Меш общий ещё с %d нод(ой) — изменения затронут их тоже." % shared


func _on_slider_changed(value: float) -> void:
	if not is_equal_approx(_spin.value, value):
		_spin.set_value_no_signal(value)
	_apply(value)


func _on_spin_changed(value: float) -> void:
	if not is_equal_approx(_slider.value, value):
		_slider.set_value_no_signal(value)
	_apply(value)


func _apply(factor: float) -> void:
	if not _has_channel:
		return
	if not is_instance_valid(_mesh_instance) or _mesh_instance.mesh == null:
		return
	var mesh := _mesh_instance.mesh as ArrayMesh
	if mesh == null:
		return
	UVOps.apply(mesh, UVOps.scaled(_snapshot, _channel, factor))


func _on_confirmed() -> void:
	_applied = true
	_mark_scene_unsaved()


func _mark_scene_unsaved() -> void:
	if not Engine.is_editor_hint():
		return
	if is_instance_valid(_mesh_instance) and _mesh_instance.mesh is ArrayMesh:
		EditorInterface.set_object_edited(_mesh_instance.mesh, true)
	EditorInterface.mark_scene_as_unsaved()


func _on_visibility_changed() -> void:
	if visible:
		return
	_settle.call_deferred()


func _settle() -> void:
	if visible or _applied:
		return
	_restore()


func _restore() -> void:
	if is_instance_valid(_mesh_instance) and _mesh_instance.mesh is ArrayMesh:
		UVOps.apply(_mesh_instance.mesh as ArrayMesh, _snapshot)
	_mesh_instance = null
