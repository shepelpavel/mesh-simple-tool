@tool
extends ConfirmationDialog

signal finished_apply

const UVOps := preload("../uv_ops.gd")
const UVPreview := preload("uv_preview.gd")

enum Mode { BOX, LIGHTMAP, CYLINDER }

var _mesh_instance: MeshInstance3D
var _snapshot: Array = []
var _applied := false
var _mode := Mode.BOX
var _mode_select: OptionButton
var _preview: Control
var _hint: Label


func _init() -> void:
	title = "Unwrap UV"
	exclusive = true
	min_size = Vector2i(460, 560)
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
	var label := Label.new()
	label.text = "Метод:"
	row.add_child(label)
	_mode_select = OptionButton.new()
	_mode_select.add_item("Box / planar", Mode.BOX)
	_mode_select.add_item("Auto (angle-based)", Mode.LIGHTMAP)
	_mode_select.add_item("Cylindrical (Y)", Mode.CYLINDER)
	_mode_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_mode_select)
	_preview = UVPreview.new()
	box.add_child(_preview)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override("font_color", Color(0.75, 0.62, 0.35))
	box.add_child(_hint)
	_mode_select.item_selected.connect(_on_mode_selected)


func open(mesh_instance: MeshInstance3D) -> void:
	if not is_instance_valid(mesh_instance):
		return
	var mesh := UVOps.ensure_array_mesh(mesh_instance)
	if mesh == null:
		push_warning("MST: mesh type is not supported (need ArrayMesh or PrimitiveMesh)")
		return
	_mesh_instance = mesh_instance
	_snapshot = UVOps.snapshot(mesh)
	_applied = false
	_mode = Mode.BOX
	_mode_select.select(_mode_select.get_item_index(Mode.BOX))
	_hint.text = ""
	_apply_mode()
	popup_centered(Vector2i(480, 580))


func _on_mode_selected(index: int) -> void:
	_mode = _mode_select.get_item_id(index)
	_apply_mode()


func _apply_mode() -> void:
	if not is_instance_valid(_mesh_instance) or _mesh_instance.mesh == null:
		return
	var mesh := _mesh_instance.mesh as ArrayMesh
	if mesh == null:
		return
	_hint.text = ""
	match _mode:
		Mode.BOX:
			UVOps.apply(mesh, UVOps.box_unwrapped(_snapshot, 0.02))
		Mode.LIGHTMAP:
			var result := UVOps.lightmap_unwrapped(_snapshot, 0.02)
			if result["ok"]:
				UVOps.apply(mesh, result["surfaces"])
			else:
				_hint.text = "Auto недоступен: %s. Показываю Box." % result["error"]
				UVOps.apply(mesh, UVOps.box_unwrapped(_snapshot, 0.02))
		Mode.CYLINDER:
			UVOps.apply(mesh, UVOps.cylindrical_unwrapped(_snapshot, 0.02))
	_preview.set_mesh(mesh)


func _on_confirmed() -> void:
	_applied = true
	_mark_scene_unsaved()
	finished_apply.emit()


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
	if _applied:
		return
	_restore()


func _restore() -> void:
	if is_instance_valid(_mesh_instance) and _mesh_instance.mesh is ArrayMesh:
		UVOps.apply(_mesh_instance.mesh as ArrayMesh, _snapshot)
	_mesh_instance = null
