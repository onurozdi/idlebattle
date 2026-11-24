extends RefCounted


static func make_meter(max_health: float, width: float) -> ProgressBar:
	var meter := ProgressBar.new()
	meter.custom_minimum_size = Vector2(width, 8)
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.show_percentage = false
	meter.max_value = max_health
	meter.step = 0.0
	meter.z_index = 16
	var background := StyleBoxFlat.new()
	background.bg_color = Color("#1c2225")
	background.border_color = Color("#e0c099")
	background.set_border_width_all(1)
	meter.add_theme_stylebox_override("background", background)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#bd5948")
	fill.set_content_margin_all(1)
	meter.add_theme_stylebox_override("fill", fill)
	return meter
