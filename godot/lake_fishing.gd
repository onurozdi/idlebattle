extends Node2D

signal leave_requested

const FISH_ATLAS := preload("res://assets/lake-fish.webp")
const ANGLER_X := 277.0
const CAST_POINT := Vector2(561.0, 422.0)
const BANK_POINT := Vector2(461.0, 410.0)
const HANG_POINT := Vector2(367.0, 345.0)
const LINE_RELEASE := .49
const HOOK_WINDOW := 1.1
const HOOK_DURATION := .32
const LAND_DURATION := .54
const RELEASE_DURATION := .62
const BAG_COLUMNS := 5
const BAG_ROWS := 3
const CELL := 45
const FISH := [
	{"label": "Lake Perch", "level": 1, "weight": 55.0, "fight": .12, "length": 28.0, "cells": 2, "region": Rect2(55, 210, 530, 290)},
	{"label": "Lake Trout", "level": 2, "weight": 30.0, "fight": .32, "length": 39.0, "cells": 2, "region": Rect2(697, 237, 644, 251)},
	{"label": "Northern Pike", "level": 3, "weight": 15.0, "fight": .57, "length": 51.0, "cells": 3, "region": Rect2(1420, 256, 719, 228)},
]

enum Phase { READY, CASTING, WAITING, BITE, SETTING, REELING, LANDING, CAUGHT, RELEASING }

var actor: Node2D
var active := false
var phase := Phase.READY
var time := 0.0
var elapsed := 0.0
var wait_time := 0.0
var level := 1
var fish: Dictionary = {}
var rng := RandomNumberGenerator.new()
var held: Dictionary = {}
var pulse := 0.0
var progress := 0.0
var tension := 0.0
var pulling := false
var flight_origin := Vector2.ZERO
var line_end := Vector2.ZERO
var splash := 0.0

var ui: CanvasLayer
var action_button: Button
var secondary_button: Button
var rod_picker: OptionButton
var prompt: Label
var tension_meter: ProgressBar
var reel_meter: ProgressBar
var meter_panel: PanelContainer
var meter_fill: StyleBoxFlat
var bag: Panel
var bag_grid: Control
var bag_cells := PackedByteArray()


func _ready() -> void:
	z_index = 8
	rng.randomize()
	bag_cells.resize(BAG_COLUMNS * BAG_ROWS)
	_make_ui()
	hide()
	ui.hide()


func enter(angler: Node2D) -> void:
	actor = angler
	active = true
	actor.anchor_x = ANGLER_X
	actor.move_speed = 0.0
	actor.fishing_stance = true
	actor.rod.set_level(level)
	_reset_line()
	show()
	ui.show()
	_refresh_ui()


func leave() -> void:
	active = false
	held.clear()
	actor.fishing_stance = false
	actor.cast_time = -1.0
	actor.rod_lift = 0.0
	actor.rod_load = 0.0
	actor.reel_turn = 0.0
	bag.hide()
	hide()
	ui.hide()
	leave_requested.emit()


func set_action_input(source: Variant, down: bool) -> void:
	if not down:
		held.erase(source)
	elif not held.has(source):
		held[source] = true
		_action()


func _action() -> void:
	if bag.visible:
		return
	match phase:
		Phase.READY:
			if not actor.cast():
				return
			fish = select_fish(level, rng.randf())
			wait_time = rng.randf_range(2.6, 4.4)
			_set_phase(Phase.CASTING)
		Phase.BITE:
			_set_phase(Phase.SETTING)
		Phase.REELING:
			pulse = .19
		Phase.CAUGHT:
			if _keep_fish():
				_reset_line("%s kept" % fish.label)
				bag.show()
			else:
				prompt.text = "Backpack full · Release the fish"


func secondary_action() -> void:
	if bag.visible:
		bag.hide()
	elif phase == Phase.REELING:
		_reset_line("Line cut · Cast again")
	elif phase == Phase.CAUGHT:
		_set_phase(Phase.RELEASING)


func toggle_bag() -> void:
	if phase == Phase.READY or phase == Phase.CAUGHT:
		bag.visible = not bag.visible


static func select_fish(rod_level: int, sample: float) -> Dictionary:
	var total := 0.0
	for species in FISH:
		if species.level <= rod_level:
			total += species.weight
	var roll := sample * total
	for species in FISH:
		if species.level > rod_level:
			break
		roll -= species.weight
		if roll < 0.0:
			return species
	return FISH[rod_level - 1]


func advance(delta: float) -> void:
	time += delta
	elapsed += delta
	splash = maxf(0.0, splash - delta)
	pulse = maxf(0.0, pulse - delta)
	pulling = false
	match phase:
		Phase.CASTING:
			if time >= LINE_RELEASE:
				if time - delta < LINE_RELEASE:
					flight_origin = actor.rod.line_tip()
				var flight := clampf(inverse_lerp(LINE_RELEASE, actor.CAST_LENGTH, time), 0.0, 1.0)
				line_end = flight_origin.lerp(CAST_POINT, flight) - Vector2(0.0, sin(flight * PI) * 63.0)
			if time >= actor.CAST_LENGTH:
				splash = .36
				_set_phase(Phase.WAITING)
		Phase.WAITING:
			line_end = CAST_POINT + Vector2(0, sin(elapsed * 5.0) * 1.3)
			if time >= wait_time:
				_set_phase(Phase.BITE)
		Phase.BITE:
			line_end = CAST_POINT + Vector2(sin(time * 32.0) * 3.0, 4.0 + sin(time * 27.0) * 5.0)
			if time >= HOOK_WINDOW:
				_reset_line("Missed the bite · Cast again")
		Phase.SETTING:
			if time >= HOOK_DURATION:
				_set_phase(Phase.REELING)
		Phase.REELING:
			_reel(delta)
		Phase.LANDING:
			var rise := clampf(time / LAND_DURATION, 0.0, 1.0)
			line_end = BANK_POINT.lerp(HANG_POINT, smoothstep(0.0, 1.0, rise))
			line_end.y -= sin(rise * PI) * 13.0
			if time >= LAND_DURATION:
				_set_phase(Phase.CAUGHT)
		Phase.RELEASING:
			var fall := clampf(time / RELEASE_DURATION, 0.0, 1.0)
			line_end = HANG_POINT.lerp(BANK_POINT + Vector2(21, 28), fall)
			line_end.y -= sin(fall * PI) * 22.0
			if time >= RELEASE_DURATION:
				_reset_line("Fish released · Cast again")
	var lifting := phase == Phase.LANDING or phase == Phase.CAUGHT
	var target_lift := .76 if lifting else (.44 if pulling else 0.0)
	if phase == Phase.SETTING:
		target_lift = sin(PI * clampf(time / HOOK_DURATION, 0.0, 1.0))
	actor.rod_lift = move_toward(actor.rod_lift, target_lift, delta * 7.0)
	var load := tension / 100.0 if phase == Phase.REELING else (.29 if lifting else 0.0)
	actor.rod_load = move_toward(actor.rod_load, load, delta * 4.0)
	if pulling:
		actor.reel_turn = fposmod(actor.reel_turn + delta * 17.0, TAU)
	_update_meters()
	queue_redraw()


func _reel(delta: float) -> void:
	pulling = not held.is_empty() or pulse > 0.0
	var resistance := maxf(0.0, fish.fight - (level - 1) * .14)
	var surge := maxf(0.0, sin(time * 3.0)) * 13.0
	var load_rate := 19.0 + surge + resistance * 25.0 if pulling else -34.0 + surge * .4
	tension = clampf(tension + delta * load_rate, 0.0, 100.0)
	if pulling:
		progress = minf(progress + delta * (.34 - resistance * .15), 1.0)
	line_end = CAST_POINT.lerp(BANK_POINT, progress) + Vector2(0.0, 5.0 + sin(time * 8.0) * 3.0)
	if tension >= 100.0:
		_reset_line("Line snapped · Cast again")
	elif progress >= 1.0:
		splash = .32
		_set_phase(Phase.LANDING)


func _set_phase(next: Phase) -> void:
	phase = next
	time = 0.0
	_refresh_ui()


func _reset_line(message := "") -> void:
	fish = {}
	progress = 0.0
	tension = 12.0
	pulse = 0.0
	_set_phase(Phase.READY)
	if not message.is_empty():
		prompt.text = message


func _draw() -> void:
	if not active or phase == Phase.READY or (phase == Phase.CASTING and time < LINE_RELEASE):
		return
	var tip: Vector2 = actor.rod.line_tip()
	if phase != Phase.RELEASING:
		var line := PackedVector2Array()
		var slack := 8.0 * (1.0 - tension / 100.0) if phase == Phase.WAITING else 2.5
		for point in 17:
			var fraction := float(point) / 16.0
			line.append(tip.lerp(line_end, fraction) + Vector2(0.0, sin(fraction * PI) * slack))
		draw_polyline(line, Color("#e9e1cddc"), 1.1, true)
	if phase in [Phase.REELING, Phase.LANDING, Phase.CAUGHT, Phase.RELEASING]:
		_draw_fish()
	else:
		draw_line(line_end + Vector2(0, -5), line_end + Vector2(0, 3), Color("#fff0b4"), 2.0)
		draw_rect(Rect2(line_end - Vector2(2, 2), Vector2(4, 4)), Color("#e3764f"))
	var surface := BANK_POINT if phase == Phase.LANDING else CAST_POINT
	if splash > 0.0 or phase == Phase.BITE:
		var radius := 4.0 + 15.0 * (1.0 - splash / .36) if splash > 0.0 else 6.0 + fposmod(time * 38.0, 12.0)
		draw_set_transform(surface, 0.0, Vector2(1.0, .31))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 25, Color("#cae6d99c"), 1.3, true)
		draw_set_transform(Vector2.ZERO)


func _draw_fish() -> void:
	var region: Rect2 = fish.region
	var length: float = fish.length
	var size := Vector2(length, length * region.size.y / region.size.x)
	var angle := sin(elapsed * 14.0) * .13
	if phase == Phase.CAUGHT or phase == Phase.LANDING:
		var upright := smoothstep(0.0, LAND_DURATION, time) if phase == Phase.LANDING else 1.0
		angle += upright * PI * .5
	elif phase == Phase.RELEASING:
		angle += lerpf(PI * .5, .32, clampf(time / RELEASE_DURATION, 0.0, 1.0))
	var tint := Color(1, 1, 1, .56) if phase == Phase.REELING else Color.WHITE
	draw_set_transform(line_end, angle)
	draw_texture_rect_region(FISH_ATLAS, Rect2(-size * Vector2(.04, .59), size), region, tint)
	draw_set_transform(Vector2.ZERO)


func _make_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var header := _panel_row(Vector2(22, 19), Vector2(916, 44))
	var heading := Label.new()
	heading.text = "Lake Fishing"
	heading.add_theme_color_override("font_color", Color("#ffd698"))
	header.add_child(heading)
	rod_picker = OptionButton.new()
	rod_picker.focus_mode = Control.FOCUS_NONE
	for i in 3:
		rod_picker.add_item("Casting Rod · Lv. %d" % (i + 1))
	rod_picker.item_selected.connect(_set_rod)
	header.add_child(rod_picker)
	prompt = Label.new()
	prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(prompt)
	var backpack_button := _button("Backpack  I", toggle_bag)
	header.add_child(backpack_button)
	header.add_child(_button("Leave  Esc / Y", leave))
	var actions := _panel_row(Vector2(623, 459), Vector2(315, 53))
	action_button = Button.new()
	action_button.focus_mode = Control.FOCUS_NONE
	action_button.custom_minimum_size = Vector2(153, 36)
	action_button.button_down.connect(set_action_input.bind("button", true))
	action_button.button_up.connect(set_action_input.bind("button", false))
	actions.add_child(action_button)
	secondary_button = _button("Break Line  F / B", secondary_action)
	secondary_button.custom_minimum_size.x = 124
	actions.add_child(secondary_button)
	var meters := _panel_row(Vector2(623, 395), Vector2(315, 53))
	meter_panel = meters.get_parent()
	tension_meter = _add_meter(meters, "Line tension", Color("#e5ad5e"))
	meter_fill = tension_meter.get_theme_stylebox("fill") as StyleBoxFlat
	reel_meter = _add_meter(meters, "Reel progress", Color("#78bda9"))
	_make_bag()


func _panel_row(at: Vector2, dimensions: Vector2) -> HBoxContainer:
	var panel := PanelContainer.new()
	panel.position = at
	panel.custom_minimum_size = dimensions
	var style := _panel_style()
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	panel.add_theme_stylebox_override("panel", style)
	ui.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	return row


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#092034ed")
	style.border_color = Color("#ad8250")
	style.set_border_width_all(1)
	return style


func _button(label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	return button


func _add_meter(row: HBoxContainer, label: String, color: Color) -> ProgressBar:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	var caption := Label.new()
	caption.text = label
	column.add_child(caption)
	var meter := ProgressBar.new()
	meter.custom_minimum_size = Vector2(128, 9)
	meter.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	meter.add_theme_stylebox_override("fill", fill)
	column.add_child(meter)
	return meter


func _set_rod(index: int) -> void:
	if phase == Phase.READY:
		level = index + 1
		actor.rod.set_level(level)


func _refresh_ui() -> void:
	rod_picker.disabled = phase != Phase.READY
	action_button.disabled = phase not in [Phase.READY, Phase.BITE, Phase.REELING, Phase.CAUGHT]
	secondary_button.disabled = phase not in [Phase.REELING, Phase.CAUGHT]
	secondary_button.text = "Release  F / B" if phase == Phase.CAUGHT else "Break Line  F / B"
	meter_panel.visible = phase == Phase.REELING
	match phase:
		Phase.READY: _set_labels("Cast  E / X", "")
		Phase.CASTING: _set_labels("Casting…", "")
		Phase.WAITING: _set_labels("Wait", "Watching the float")
		Phase.BITE: _set_labels("Set Hook  E / X", "Bite!")
		Phase.SETTING: _set_labels("Hooked", "")
		Phase.REELING: _set_labels("Reel In  E / X", "Hold to reel · Release to ease tension")
		Phase.LANDING: _set_labels("Landing…", "")
		Phase.CAUGHT: _set_labels("Keep  E / X", fish.label)
		Phase.RELEASING: _set_labels("Releasing…", "")


func _set_labels(action: String, message: String) -> void:
	action_button.text = action
	prompt.text = message


func _update_meters() -> void:
	if phase == Phase.REELING:
		tension_meter.value = tension
		reel_meter.value = progress * 100.0
		meter_fill.bg_color = Color("#e06a55") if tension >= 75.0 else Color("#e5ad5e")


func _make_bag() -> void:
	bag = Panel.new()
	bag.position = Vector2(332, 140)
	bag.size = Vector2(296, 231)
	bag.add_theme_stylebox_override("panel", _panel_style())
	ui.add_child(bag)
	var title := Label.new()
	title.text = "Backpack"
	title.position = Vector2(20, 12)
	bag.add_child(title)
	bag_grid = Control.new()
	bag_grid.position = Vector2(35, 52)
	bag.add_child(bag_grid)
	for index in bag_cells.size():
		var cell := Panel.new()
		cell.position = Vector2(index % BAG_COLUMNS, index / BAG_COLUMNS) * CELL
		cell.size = Vector2.ONE * CELL
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#102a40")
		style.border_color = Color("#50788d")
		style.set_border_width_all(1)
		cell.add_theme_stylebox_override("panel", style)
		bag_grid.add_child(cell)
	var close := _button("Close", bag.hide)
	close.position = Vector2(213, 12)
	bag.add_child(close)
	bag.hide()


func _keep_fish() -> bool:
	var span: int = fish.cells
	for row in BAG_ROWS:
		for column in BAG_COLUMNS - span + 1:
			var start := row * BAG_COLUMNS + column
			if bag_cells.slice(start, start + span).has(1):
				continue
			for index in range(start, start + span):
				bag_cells[index] = 1
			var picture := TextureRect.new()
			var atlas := AtlasTexture.new()
			atlas.atlas = FISH_ATLAS
			atlas.region = fish.region
			picture.texture = atlas
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			picture.position = Vector2(column, row) * CELL + Vector2(3, 2)
			picture.size = Vector2(span * CELL - 6, CELL - 4)
			picture.tooltip_text = fish.label
			bag_grid.add_child(picture)
			return true
	return false
