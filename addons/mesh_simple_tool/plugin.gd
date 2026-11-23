@tool
extends EditorPlugin

const UVOps := preload("uv_ops.gd")
const ScaleDialog := preload("ui/scale_dialog.gd")
const UnwrapDialog := preload("ui/unwrap_dialog.gd")
const MergeDialog := preload("ui/merge_dialog.gd")

const MENU_TEXT := "MST"
const ID_SCALE_UV2 := 1
const ID_UNWRAP_UV := 2
const ID_SCALE_UV := 3
const ID_MERGE_BY_DISTANCE := 4
const WATCHDOG_INTERVAL := 0.4
const MENU_SEARCH_TICKS := 5

var _menu_button: MenuButton
var _scale_dialog: ConfirmationDialog
var _unwrap_dialog: ConfirmationDialog
var _merge_dialog: ConfirmationDialog
var _selection: EditorSelection
var _watchdog := 0.0
var _miss_count := 0


func _enter_tree() -> void:
	_selection = EditorInterface.get_selection()
	_selection.selection_changed.connect(_on_selection_changed)
	_ensure_menu()


func _exit_tree() -> void:
	if is_instance_valid(_selection) and _selection.selection_changed.is_connected(_on_selection_changed):
		_selection.selection_changed.disconnect(_on_selection_changed)
	if is_instance_valid(_scale_dialog):
		_scale_dialog.call("shutdown")
		_scale_dialog.queue_free()
	if is_instance_valid(_unwrap_dialog):
		_unwrap_dialog.call("shutdown")
		_unwrap_dialog.queue_free()
	if is_instance_valid(_merge_dialog):
		_merge_dialog.queue_free()
	if is_instance_valid(_menu_button):
		_drop_menu_button()
	_menu_button = null


func _drop_menu_button() -> void:
	if not is_instance_valid(_menu_button):
		return
	var parent := _menu_button.get_parent()
	if parent != null:
		parent.remove_child(_menu_button)
	_menu_button.queue_free()


func _process(delta: float) -> void:
	_watchdog += delta
	if _watchdog < WATCHDOG_INTERVAL:
		return
	_watchdog = 0.0
	if is_instance_valid(_menu_button) and _menu_button.is_inside_tree():
		_miss_count = 0
		_update_visibility()
		return
	_miss_count += 1
	if _miss_count < MENU_SEARCH_TICKS:
		return
	_miss_count = 0
	_ensure_menu()
	_update_visibility()


func _on_selection_changed() -> void:
	_ensure_menu()
	_update_visibility()


func _ensure_menu() -> void:
	if is_instance_valid(_menu_button):
		if _menu_button.is_inside_tree():
			return
		_drop_menu_button()
		_menu_button = null
	var mesh_menu := _find_mesh_menu(EditorInterface.get_base_control())
	if mesh_menu == null:
		return
	var parent := mesh_menu.get_parent()
	if parent == null:
		return
	_menu_button = MenuButton.new()
	_menu_button.text = MENU_TEXT
	_menu_button.flat = true
	_menu_button.focus_mode = Control.FOCUS_NONE
	_menu_button.tooltip_text = "Mesh Simple Tool: UV / UV2"
	var popup := _menu_button.get_popup()
	popup.add_item("Scale UV2", ID_SCALE_UV2)
	popup.add_item("Unwrap UV", ID_UNWRAP_UV)
	popup.add_item("Scale UV", ID_SCALE_UV)
	popup.add_item("Merge by distance", ID_MERGE_BY_DISTANCE)
	popup.id_pressed.connect(_on_menu_id_pressed)
	parent.add_child(_menu_button)
	parent.move_child(_menu_button, mesh_menu.get_index() + 1)
	_update_visibility()


func _find_mesh_menu(node: Node) -> MenuButton:
	var fallback: MenuButton = null
	for child in node.get_children():
		if child is MenuButton:
			var mb := child as MenuButton
			if mb.text == MENU_TEXT:
				continue
			if _popup_has_unwrap(mb.get_popup()):
				return mb
			if fallback == null and mb.text == "Mesh":
				fallback = mb
		var nested := _find_mesh_menu(child)
		if nested != null:
			return nested
	return fallback


func _popup_has_unwrap(popup: PopupMenu) -> bool:
	for i in popup.get_item_count():
		var item_text := popup.get_item_text(i)
		if item_text == "Unwrap UV2 for Lightmap/AO" or item_text.contains("UV2"):
			return true
	return false


func _update_visibility() -> void:
	if not is_instance_valid(_menu_button):
		return
	_menu_button.visible = _active_mesh_instance() != null


func _active_mesh_instance() -> MeshInstance3D:
	if not is_instance_valid(_selection):
		return null
	for node in _selection.get_selected_nodes():
		if node is MeshInstance3D:
			return node
	return null


func _on_menu_id_pressed(id: int) -> void:
	var mi := _active_mesh_instance()
	if mi == null:
		return
	match id:
		ID_SCALE_UV2:
			_open_scale(mi, UVOps.UV2)
		ID_SCALE_UV:
			_open_scale(mi, UVOps.UV1)
		ID_UNWRAP_UV:
			_open_unwrap(mi)
		ID_MERGE_BY_DISTANCE:
			_open_merge(mi)


func _open_scale(mi: MeshInstance3D, channel: int) -> void:
	if not is_instance_valid(_scale_dialog):
		_scale_dialog = ScaleDialog.new()
		EditorInterface.get_base_control().add_child(_scale_dialog)
	_scale_dialog.call("open", mi, channel)


func _open_unwrap(mi: MeshInstance3D) -> void:
	if not is_instance_valid(_unwrap_dialog):
		_unwrap_dialog = UnwrapDialog.new()
		EditorInterface.get_base_control().add_child(_unwrap_dialog)
	_unwrap_dialog.call("open", mi)


func _open_merge(mi: MeshInstance3D) -> void:
	if not is_instance_valid(_merge_dialog):
		_merge_dialog = MergeDialog.new()
		EditorInterface.get_base_control().add_child(_merge_dialog)
	_merge_dialog.call("open", mi)
