extends Panel

signal catch_placed(label: String)
signal catch_dropped

const FISH_ATLAS := preload("res://assets/lake-fish.webp")
const GRID_SIZE := Vector2i(5, 3)
const CELL := 51
const GRID_ORIGIN := Vector2(76, 107)

var items: Array[Dictionary] = []
var pending: Dictionary = {}
var cursor := Vector2i.ZERO
var vertical := false
var moving_index := -1
var summary: Label
var footprint_label: Label
var rotate_button: Button
var place_button: Button
var drop_button: Button


func _ready() -> void:
	position = Vector2(276, 105)
	size = Vector2(408, 315)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#092034f5")
	style.border_color = Color("#ad8250")
	style.set_border_width_all(1)
	add_theme_stylebox_override("panel", style)
	var title := _label(Vector2(20, 14))
	title.text = "Backpack"
	title.add_theme_color_override("font_color", Color("#ffd698"))
	_button("Close", Vector2(323, 12), 65, close)
	summary = _label(Vector2(20, 53))
	footprint_label = _label(Vector2(20, 76))
	footprint_label.add_theme_color_override("font_color", Color("#b7d2dc"))
	rotate_button = _button("Rotate  R / RB", Vector2(20, 274), 124, rotate)
	place_button = _button("Place  E / X", Vector2(152, 274), 120, confirm)
	drop_button = _button("Drop", Vector2(280, 274), 108, _drop_catch)
	_refresh()
	hide()


func open_catch(fish: Dictionary) -> void:
	pending = fish
	moving_index = -1
	cursor = Vector2i.ZERO
	vertical = false
	open()


func open() -> void:
	show()
	_refresh()


func close() -> void:
	pending = {}
	moving_index = -1
	hide()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func rotate() -> void:
	if pending.is_empty():
		return
	vertical = not vertical
	_refresh()


func move_cursor(direction: Vector2i) -> void:
	cursor = (cursor + direction).clamp(Vector2i.ZERO, GRID_SIZE - Vector2i.ONE)
	_refresh()


func confirm() -> void:
	if pending.is_empty():
		_pick_up(cursor)
		return
	if not can_place():
		return
	var entry := {"fish": pending, "cell": cursor, "vertical": vertical}
	var from_lake := moving_index < 0
	if from_lake:
		items.append(entry)
	else:
		items[moving_index] = entry
	pending = {}
	moving_index = -1
	_refresh()
	if from_lake:
		catch_placed.emit(entry.fish.label)


func footprint() -> Vector2i:
	if pending.is_empty():
		return Vector2i.ZERO
	return _fish_size(pending, vertical)


func can_place() -> bool:
	if pending.is_empty():
		return false
	var candidate := Rect2i(cursor, footprint())
	if not Rect2i(Vector2i.ZERO, GRID_SIZE).encloses(candidate):
		return false
	for index in items.size():
		if index != moving_index and candidate.intersects(_item_rect(items[index])):
			return false
	return true


func _pick_up(cell: Vector2i) -> void:
	for index in items.size():
		var entry := items[index]
		if _item_rect(entry).has_point(cell):
			pending = entry.fish
			cursor = entry.cell
			vertical = entry.vertical
			moving_index = index
			break
	_refresh()


func _drop_catch() -> void:
	if pending.is_empty() or moving_index >= 0:
		return
	close()
	catch_dropped.emit()


func _fish_size(fish: Dictionary, rotated: bool) -> Vector2i:
	return Vector2i(1, fish.cells) if rotated else Vector2i(fish.cells, 1)


func _item_rect(entry: Dictionary) -> Rect2i:
	return Rect2i(entry.cell, _fish_size(entry.fish, entry.vertical))


func _label(at: Vector2) -> Label:
	var label := Label.new()
	label.position = at
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _button(label: String, at: Vector2, width: float, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.position = at
	button.custom_minimum_size = Vector2(width, 29)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	add_child(button)
	return button


func _refresh() -> void:
	var placing := not pending.is_empty()
	var fits := can_place()
	rotate_button.disabled = not placing
	place_button.disabled = not fits
	drop_button.disabled = not placing or moving_index >= 0
	if placing:
		summary.text = "%s · %s · %.2f kg · $%d" % [pending.label, pending.size_label, pending.kg, pending.price]
		var cells := footprint()
		var status := "Select a cell, then Place" if fits else "Doesn't fit here"
		footprint_label.text = "%d × %d · %d cells · %s" % [cells.x, cells.y, pending.cells, status]
		footprint_label.modulate = Color.WHITE if fits else Color("#ff9788")
	else:
		summary.text = "Select a fish to move it" if not items.is_empty() else "Empty backpack"
		footprint_label.text = ""
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return
	var point: Vector2 = event.position - GRID_ORIGIN
	var cell := Vector2i((point / CELL).floor())
	if not Rect2i(Vector2i.ZERO, GRID_SIZE).has_point(cell):
		return
	cursor = cell
	if pending.is_empty():
		_pick_up(cell)
	else:
		_refresh()
	accept_event()


func _draw() -> void:
	var candidate := Rect2i(cursor, footprint())
	var fits := can_place()
	for y in GRID_SIZE.y:
		for x in GRID_SIZE.x:
			var at := Vector2i(x, y)
			var tile := Rect2(GRID_ORIGIN + Vector2(at) * CELL, Vector2.ONE * CELL).grow(-1)
			var color := Color("#102a40")
			for index in items.size():
				if index != moving_index and _item_rect(items[index]).has_point(at):
					color = Color("#23516a")
			if candidate.has_point(at):
				color = Color("#327057") if fits else Color("#843e45")
			elif at == cursor and pending.is_empty():
				color = color.lightened(.18)
			draw_rect(tile, color)
			draw_rect(tile, Color("#50788d"), false)
	for index in items.size():
		if index != moving_index:
			var entry := items[index]
			_draw_icon(entry.fish, _item_rect(entry), entry.vertical, Color.WHITE)
	if not pending.is_empty():
		draw_rect(Rect2(GRID_ORIGIN, Vector2(GRID_SIZE) * CELL), Color("#ad8250"), false)
		if Rect2i(Vector2i.ZERO, GRID_SIZE).encloses(candidate):
			_draw_icon(pending, candidate, vertical, Color(1, 1, 1, .8) if fits else Color(1, .5, .5, .72))


func _draw_icon(fish: Dictionary, bounds: Rect2i, rotated: bool, tint: Color) -> void:
	var region: Rect2 = fish.region
	var center := GRID_ORIGIN + (Vector2(bounds.position) + Vector2(bounds.size) * .5) * CELL
	var box := Vector2(fish.cells * CELL - 12.0, CELL - 8.0)
	var icon_scale := minf(box.x / region.size.x, box.y / region.size.y) * minf(1.0, fish.length_scale / 1.28)
	var icon := region.size * icon_scale
	draw_set_transform(center, PI * .5 if rotated else 0.0)
	draw_texture_rect_region(FISH_ATLAS, Rect2(-icon * .5, icon), region, tint)
	draw_set_transform(Vector2.ZERO)
