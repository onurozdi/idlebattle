extends Node2D

signal leave_requested

const FISH_ATLAS := preload("res://assets/lake-fish.webp")
const FISHING_BACKPACK := preload("res://fishing_backpack.gd")
const CAST_SURFACE_Y := 468.0
const LAND_SURFACE_Y := 449.0
const OPEN_WATER_LEFT := 500.0
const CAST_RANGE := 294.0
const CAST_ARC_HEIGHT := 76.0
const LAND_NEAR := 95.0
const HANG_LENGTH := 49.0
const SWING_GRAVITY := 640.0
const LIFTED_FISH_SCALE := 1.12
const LINE_RELEASE := .49
const HOOK_WINDOW := 1.1
const HOOK_DURATION := .32
const LAND_DURATION := .54
const RIPPLE_LIFETIME := .88
const RIPPLE_SPACING := 6.0
const FISH := [
	{"label": "Lake Perch", "level": 1, "chance": 55.0, "fight": .12, "length": 28.0, "kg": .65, "price": 22, "cells": 2, "region": Rect2(55, 210, 530, 290)},
	{"label": "Lake Trout", "level": 2, "chance": 30.0, "fight": .32, "length": 39.0, "kg": 1.45, "price": 38, "cells": 2, "region": Rect2(697, 237, 644, 251)},
	{"label": "Northern Pike", "level": 3, "chance": 15.0, "fight": .57, "length": 51.0, "kg": 3.90, "price": 60, "cells": 3, "region": Rect2(1420, 256, 719, 228)},
]
const SIZES := [
	{"label": "Small", "chance": .58, "length_scale": .78, "weight_scale": .54, "price_scale": .64},
	{"label": "Medium", "chance": .34, "length_scale": 1.0, "weight_scale": 1.0, "price_scale": 1.0},
	{"label": "Trophy", "chance": .08, "length_scale": 1.28, "weight_scale": 1.95, "price_scale": 2.35},
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
var cast_direction := 1.0
var cast_point := Vector2.ZERO
var landing_point := Vector2.ZERO
var flight_origin := Vector2.ZERO
var line_end := Vector2.ZERO
var splash := 0.0
var wake_ripples: Array[Vector3] = []
var last_ripple := Vector2.INF
var line_length := 0.0
var line_start_length := 0.0
var swing_angle := 0.0
var swing_speed := 0.0
var previous_tip := Vector2.ZERO
var previous_tip_speed := Vector2.ZERO
var release_origin := Vector2.ZERO

var ui: CanvasLayer
var action_button: Button
var secondary_button: Button
var rod_picker: OptionButton
var prompt: Label
var tension_meter: ProgressBar
var reel_meter: ProgressBar
var meter_panel: PanelContainer
var meter_fill: StyleBoxFlat
var backpack: Panel


func _ready() -> void:
	z_index = 8
	rng.randomize()
	_make_ui()
	hide()
	ui.hide()


func enter(angler: Node2D) -> void:
	actor = angler
	active = true
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
	backpack.close()
	hide()
	ui.hide()
	leave_requested.emit()


func set_action_input(source: Variant, down: bool) -> void:
	if not down:
		held.erase(source)
	elif not held.has(source):
		held[source] = true
		interact()


func interact() -> void:
	if backpack.visible:
		return
	match phase:
		Phase.READY:
			if not actor.cast():
				return
			_choose_cast_direction()
			fish = size_catch(select_fish(level, rng.randf()), rng.randf())
			wait_time = rng.randf_range(2.6, 4.4)
			_set_phase(Phase.CASTING)
		Phase.BITE:
			_set_phase(Phase.SETTING)
		Phase.REELING:
			pulse = .19
		Phase.CAUGHT:
			backpack.open_catch(fish)


func secondary_action() -> void:
	if backpack.visible:
		backpack.close()
	elif phase == Phase.REELING:
		_reset_line("Line cut · Cast again")
	elif phase == Phase.CAUGHT:
		release_origin = suspended_fish_position()
		line_end = release_origin
		_set_phase(Phase.RELEASING)


func toggle_bag() -> void:
	if phase == Phase.READY or phase == Phase.CAUGHT:
		backpack.toggle()


static func select_fish(rod_level: int, sample: float) -> Dictionary:
	var total := 0.0
	for species in FISH:
		if species.level <= rod_level:
			total += species.chance
	var roll := sample * total
	for species in FISH:
		if species.level > rod_level:
			break
		roll -= species.chance
		if roll < 0.0:
			return species
	return FISH[rod_level - 1]


static func size_catch(species: Dictionary, sample: float) -> Dictionary:
	var size: Dictionary = SIZES.back()
	for option in SIZES:
		sample -= option.chance
		if sample < 0.0:
			size = option
			break
	var catch_data := species.duplicate()
	catch_data.size_label = size.label
	catch_data.length_scale = size.length_scale
	catch_data.length = species.length * size.length_scale
	catch_data.kg = snappedf(species.kg * size.weight_scale, .01)
	catch_data.price = roundi(species.price * size.price_scale)
	return catch_data


func _catch_summary() -> String:
	return "%s · %s · %.2f kg · $%d" % [fish.label, fish.size_label, fish.kg, fish.price]


func _choose_cast_direction() -> void:
	cast_direction = actor.facing
	var x: float = actor.anchor_x
	if x < OPEN_WATER_LEFT:
		cast_direction = 1.0
		actor.facing = cast_direction
		landing_point = Vector2(maxf(OPEN_WATER_LEFT, x + LAND_NEAR), LAND_SURFACE_Y)
		cast_point = Vector2(maxf(landing_point.x + 105.0, x + CAST_RANGE), CAST_SURFACE_Y)
		return
	var far_x := x + cast_direction * CAST_RANGE
	if far_x < OPEN_WATER_LEFT or far_x > actor.STAGE_RIGHT:
		cast_direction = -cast_direction
	actor.facing = cast_direction
	cast_point = Vector2(x + cast_direction * CAST_RANGE, CAST_SURFACE_Y)
	landing_point = Vector2(x + cast_direction * LAND_NEAR, LAND_SURFACE_Y)


func advance(delta: float) -> void:
	time += delta
	elapsed += delta
	splash = maxf(0.0, splash - delta)
	_age_wake(delta)
	pulse = maxf(0.0, pulse - delta)
	pulling = false
	match phase:
		Phase.CASTING:
			if time >= LINE_RELEASE:
				if time - delta < LINE_RELEASE:
					flight_origin = actor.rod.line_tip()
				var flight := clampf(inverse_lerp(LINE_RELEASE, actor.CAST_LENGTH, time), 0.0, 1.0)
				line_end = flight_origin.lerp(cast_point, flight) - Vector2(0.0, sin(flight * PI) * CAST_ARC_HEIGHT)
			if time >= actor.CAST_LENGTH:
				splash = .36
				_set_phase(Phase.WAITING)
		Phase.WAITING:
			line_end = cast_point + Vector2(0, sin(elapsed * 5.0) * 1.3)
			if time >= wait_time:
				_set_phase(Phase.BITE)
		Phase.BITE:
			line_end = cast_point + Vector2(sin(time * 32.0) * 3.0, 4.0 + sin(time * 27.0) * 5.0)
			if time >= HOOK_WINDOW:
				_reset_line("Missed the bite · Cast again")
		Phase.SETTING:
			if time >= HOOK_DURATION:
				_set_phase(Phase.REELING)
		Phase.REELING:
			_reel(delta)
		Phase.LANDING:
			line_length = lerpf(line_start_length, HANG_LENGTH, smoothstep(0.0, LAND_DURATION, time))
			_advance_swing(delta)
			if time >= LAND_DURATION:
				_set_phase(Phase.CAUGHT)
		Phase.CAUGHT:
			_advance_swing(delta)
		Phase.RELEASING:
			line_end = release_origin + Vector2(cast_direction * 84.0 * time, (SWING_GRAVITY * .5 * time - 20.0) * time)
			if line_end.y >= landing_point.y:
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
	var surface := cast_point.lerp(landing_point, progress)
	line_end = surface + Vector2(0.0, 5.0 + sin(time * 8.0) * 3.0)
	if pulling and (last_ripple == Vector2.INF or last_ripple.distance_to(surface) >= RIPPLE_SPACING):
		wake_ripples.append(Vector3(surface.x, surface.y, 0.0))
		last_ripple = surface
	if tension >= 100.0:
		_reset_line("Line snapped · Cast again")
	elif progress >= 1.0:
		splash = .32
		previous_tip = actor.rod.line_tip()
		previous_tip_speed = Vector2.ZERO
		var offset := line_end - previous_tip
		line_start_length = offset.length()
		line_length = line_start_length
		swing_angle = atan2(offset.x, offset.y)
		swing_speed = -.85 * cast_direction
		_set_phase(Phase.LANDING)


func _advance_swing(delta: float) -> void:
	var tip: Vector2 = actor.rod.line_tip()
	var tip_speed := (tip - previous_tip) / delta
	var tip_acceleration := ((tip_speed - previous_tip_speed) / delta).limit_length(520.0)
	var tangent := Vector2(cos(swing_angle), -sin(swing_angle))
	var force := (Vector2(0, SWING_GRAVITY) - tip_acceleration).dot(tangent)
	swing_speed += (force / line_length - 2.2 * swing_speed) * delta
	swing_angle = clampf(swing_angle + swing_speed * delta, -1.35, 1.35)
	previous_tip = tip
	previous_tip_speed = tip_speed


func _age_wake(delta: float) -> void:
	for index in range(wake_ripples.size() - 1, -1, -1):
		wake_ripples[index].z += delta
		if wake_ripples[index].z >= RIPPLE_LIFETIME:
			wake_ripples.remove_at(index)


func suspended_fish_position() -> Vector2:
	return actor.rod.line_tip() + Vector2(sin(swing_angle), cos(swing_angle)) * line_length


func fish_visible() -> bool:
	if phase == Phase.LANDING or phase == Phase.CAUGHT:
		return suspended_fish_position().y + fish.length * LIFTED_FISH_SCALE < landing_point.y
	return phase == Phase.RELEASING and line_end.y < landing_point.y


func _set_phase(next: Phase) -> void:
	phase = next
	time = 0.0
	_refresh_ui()


func _reset_line(message := "") -> void:
	fish = {}
	progress = 0.0
	tension = 12.0
	pulse = 0.0
	wake_ripples.clear()
	last_ripple = Vector2.INF
	_set_phase(Phase.READY)
	if not message.is_empty():
		prompt.text = message


func _draw() -> void:
	if not active or phase == Phase.READY or (phase == Phase.CASTING and time < LINE_RELEASE):
		return
	var tip: Vector2 = actor.rod.line_tip()
	_draw_wake()
	var suspended := phase == Phase.LANDING or phase == Phase.CAUGHT
	if suspended:
		draw_line(tip, suspended_fish_position(), Color("#e9e1cddc"), 1.1, true)
	elif phase != Phase.RELEASING:
		var line := PackedVector2Array()
		var slack := 8.0 * (1.0 - tension / 100.0) if phase == Phase.WAITING else 2.5
		for point in 17:
			var fraction := float(point) / 16.0
			line.append(tip.lerp(line_end, fraction) + Vector2(0.0, sin(fraction * PI) * slack))
		draw_polyline(line, Color("#e9e1cddc"), 1.1, true)
	if fish_visible():
		_draw_fish()
	elif phase in [Phase.CASTING, Phase.WAITING, Phase.BITE, Phase.SETTING]:
		draw_line(line_end + Vector2(0, -5), line_end + Vector2(0, 3), Color("#fff0b4"), 2.0)
		draw_rect(Rect2(line_end - Vector2(2, 2), Vector2(4, 4)), Color("#e3764f"))
	var surface := landing_point if phase == Phase.LANDING else cast_point
	if splash > 0.0 or phase == Phase.BITE:
		var radius := 4.0 + 15.0 * (1.0 - splash / .36) if splash > 0.0 else 6.0 + fposmod(time * 38.0, 12.0)
		draw_set_transform(surface, 0.0, Vector2(1.0, .31))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 25, Color("#cae6d99c"), 1.3, true)
		draw_set_transform(Vector2.ZERO)


func _draw_wake() -> void:
	for ripple in wake_ripples:
		var age := ripple.z / RIPPLE_LIFETIME
		var opacity := pow(1.0 - age, 1.45)
		var center := Vector2(ripple.x + cast_direction * age * 4.0, ripple.y)
		var radius := lerpf(7.0, 32.0, pow(age, .76))
		var phase_offset := ripple.x * .19 + ripple.y * .12
		_draw_wave_crest(center + Vector2(0, 2), Vector2(radius, radius * .3), Vector2(.06, 3.02),
			phase_offset, Color(.025, .21, .25, opacity * .66), 2.2)
		_draw_wave_crest(center, Vector2(radius, radius * .3), Vector2(.12, 2.9),
			phase_offset, Color(.65, .90, .91, opacity * .92), 1.35)
		_draw_wave_crest(center, Vector2(radius * .92, radius * .24), Vector2(3.44, 5.88),
			phase_offset, Color(.31, .68, .75, opacity * .68), 1.0)
		for bead in 4:
			var angle := fposmod(phase_offset + float(bead) * 1.49, TAU)
			var spread := radius * (.61 + bead * .12)
			var crest := center + Vector2(cos(angle) * spread, sin(angle) * spread * .28)
			var shimmer := .65 + .35 * sin(elapsed * 14.0 + phase_offset + bead)
			draw_rect(Rect2(crest.round(), Vector2(2 + bead % 2, 1)), Color(.85, 1.0, .97, opacity * shimmer))
	if phase == Phase.REELING and pulling:
		var surface := cast_point.lerp(landing_point, progress)
		var wake_center := surface + Vector2(cast_direction * 5.0, 1.0)
		var edge := Vector2(15.0 + tension * .09, 4.7)
		draw_set_transform(wake_center + Vector2(0, 1), 0.0, Vector2(1.0, .31))
		draw_circle(Vector2.ZERO, edge.x, Color(.15, .47, .56, .23))
		draw_set_transform(Vector2.ZERO)
		_draw_wave_crest(wake_center, edge, Vector2(.2, 2.91), elapsed * 17.0, Color("#c7f6eddb"), 1.65)
		_draw_wave_crest(wake_center, edge * .73, Vector2(3.46, 6.05), elapsed * 20.0, Color("#5ab7c5b0"), 1.1)
		_draw_wave_crest(wake_center, edge * 1.17, Vector2(.46, 2.34), elapsed * 12.0, Color("#84cfdb8c"), 1.1)
		for drop in 5:
			var arc := fposmod(elapsed * (1.9 + drop * .26) + drop * .31, 1.0)
			var offset := Vector2(cast_direction * (3.0 + arc * (15.0 + drop * 3.0)), sin(arc * PI) * (-5.0 - drop * 1.9))
			draw_rect(Rect2((surface + offset).round(), Vector2(2, 2 if drop < 2 else 1)), Color(.77, .95, .96, sin(arc * PI) * .86))


func _draw_wave_crest(center: Vector2, radius: Vector2, span: Vector2, offset: float, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for vertex in 15:
		var angle := lerpf(span.x, span.y, float(vertex) / 14.0)
		var shimmer := sin(angle * 4.0 + offset) * .55
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y + shimmer))
	draw_polyline(points, color, width, true)


func _draw_fish() -> void:
	var region: Rect2 = fish.region
	var length: float = fish.length * LIFTED_FISH_SCALE
	var size := Vector2(length, length * region.size.y / region.size.x)
	var suspended := phase != Phase.RELEASING
	var center := suspended_fish_position() if suspended else line_end
	var angle := PI * .5 - swing_angle
	if not suspended:
		angle += cast_direction * time * 2.8
	draw_set_transform(center, angle + sin(elapsed * 14.0) * .065)
	var bounds := Rect2(-size * Vector2(.04, .59), size)
	draw_texture_rect_region(FISH_ATLAS, bounds.grow(.8), region, Color("#303224c4"))
	draw_texture_rect_region(FISH_ATLAS, bounds, region)
	draw_set_transform(Vector2.ZERO)


func _make_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var header := _panel_row(Vector2(22, 459), Vector2(416, 53))
	rod_picker = OptionButton.new()
	rod_picker.focus_mode = Control.FOCUS_NONE
	for i in 3:
		rod_picker.add_item("Casting Rod · Lv. %d" % (i + 1))
	rod_picker.item_selected.connect(_set_rod)
	header.add_child(rod_picker)
	prompt = Label.new()
	prompt.position = Vector2(204, 72)
	prompt.add_theme_color_override("font_color", Color("#ffe3b9"))
	prompt.add_theme_color_override("font_shadow_color", Color("#10141b"))
	prompt.add_theme_constant_override("shadow_offset_y", 2)
	ui.add_child(prompt)
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
	var meters := _panel_row(Vector2(623, 106), Vector2(315, 53))
	meter_panel = meters.get_parent()
	tension_meter = _add_meter(meters, "Line tension", Color("#e5ad5e"))
	meter_fill = tension_meter.get_theme_stylebox("fill") as StyleBoxFlat
	reel_meter = _add_meter(meters, "Reel progress", Color("#78bda9"))
	backpack = FISHING_BACKPACK.new()
	backpack.catch_placed.connect(func(label: String): _reset_line("%s kept" % label))
	backpack.catch_dropped.connect(secondary_action)
	ui.add_child(backpack)


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
		Phase.CAUGHT: _set_labels("Keep  E / X", _catch_summary())
		Phase.RELEASING: _set_labels("Releasing…", "")


func _set_labels(action: String, message: String) -> void:
	action_button.text = action
	prompt.text = message


func _update_meters() -> void:
	if phase == Phase.REELING:
		tension_meter.value = tension
		reel_meter.value = progress * 100.0
		meter_fill.bg_color = Color("#e06a55") if tension >= 75.0 else Color("#e5ad5e")
