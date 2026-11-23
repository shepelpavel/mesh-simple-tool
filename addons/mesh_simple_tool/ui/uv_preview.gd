@tool
extends Control

var _points: PackedVector2Array = PackedVector2Array()
var _has_uv := false
var _outside := 0


func _init() -> void:
	custom_minimum_size = Vector2(380, 380)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_mesh(mesh: Mesh) -> void:
	_points.clear()
	_has_uv = false
	_outside = 0
	if mesh is ArrayMesh:
		var am := mesh as ArrayMesh
		for si in am.get_surface_count():
			var arrays: Array = am.surface_get_arrays(si)
			var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
			var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
			if not (verts is PackedVector3Array) or not (uvs is PackedVector2Array):
				continue
			if uvs.is_empty() or verts.is_empty():
				continue
			_has_uv = true
			var idx: Variant = arrays[Mesh.ARRAY_INDEX]
			if idx is PackedInt32Array and not idx.is_empty():
				for i in idx.size():
					var k: int = idx[i]
					if k < 0 or k >= uvs.size():
						continue
					_points.append(uvs[k])
			else:
				var limit: int = mini(uvs.size(), verts.size())
				var i := 0
				while i + 2 < limit:
					_points.append(uvs[i])
					_points.append(uvs[i + 1])
					_points.append(uvs[i + 2])
					i += 3
	for p in _points:
		if p.x < 0.0 or p.x > 1.0 or p.y < 0.0 or p.y > 1.0:
			_outside += 1
	queue_redraw()


func _draw() -> void:
	var bg := Color(0.07, 0.08, 0.09, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), bg)
	var side: float = maxf(8.0, minf(size.x, size.y) - 16.0)
	var origin := Vector2((size.x - side) * 0.5, (size.y - side) * 0.5)
	var grid := Color(0.20, 0.22, 0.24, 1.0)
	var border := Color(0.38, 0.41, 0.45, 1.0)
	for i in range(1, 4):
		var t: float = float(i) / 4.0
		draw_line(origin + Vector2(side * t, 0.0), origin + Vector2(side * t, side), grid, 1.0)
		draw_line(origin + Vector2(0.0, side * t), origin + Vector2(side, side * t), grid, 1.0)
	draw_rect(Rect2(origin, Vector2(side, side)), border, false, 1.0)
	if not _has_uv:
		draw_string(
			ThemeDB.fallback_font,
			origin + Vector2(10.0, 22.0),
			"No UV1 on this mesh",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			13,
			Color(0.75, 0.45, 0.45)
		)
		return
	var line_color := Color(0.55, 0.85, 1.0, 0.75)
	var i := 0
	while i + 2 < _points.size():
		var a: Vector2 = _to_px(_points[i], origin, side)
		var b: Vector2 = _to_px(_points[i + 1], origin, side)
		var c: Vector2 = _to_px(_points[i + 2], origin, side)
		draw_line(a, b, line_color, 1.0, true)
		draw_line(b, c, line_color, 1.0, true)
		draw_line(c, a, line_color, 1.0, true)
		i += 3
	var info := "%d tris" % (_points.size() / 3)
	if _outside > 0:
		info += "   %d verts outside 0..1" % _outside
	draw_string(
		ThemeDB.fallback_font,
		origin + Vector2(8.0, side - 8.0),
		info,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		11,
		Color(0.62, 0.66, 0.70)
	)


func _to_px(p: Vector2, origin: Vector2, side: float) -> Vector2:
	return origin + Vector2(p.x, 1.0 - p.y) * side
