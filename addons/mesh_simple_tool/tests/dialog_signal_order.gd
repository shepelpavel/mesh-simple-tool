extends SceneTree


func _initialize() -> void:
	var d := ConfirmationDialog.new()
	get_root().add_child(d)
	d.show()
	var order: Array = []
	d.visibility_changed.connect(func() -> void: order.append("visibility:%s" % str(d.visible)))
	d.confirmed.connect(func() -> void: order.append("confirmed"))
	d.canceled.connect(func() -> void: order.append("canceled"))
	d.get_ok_button().pressed.emit()
	print("OK ORDER = ", order)
	order.clear()
	d.show()
	d.get_cancel_button().pressed.emit()
	print("CANCEL ORDER = ", order)
	quit()
