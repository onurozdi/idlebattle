extends Node2D

const FOREGRIP := Vector2(17.0, -4.0)
const STOCK_CONTACT := Vector2(-24.0, -6.0)
const MAGAZINE_SEAT := Vector2(8.0, 0.0)
const MAGAZINE_GRIP := Vector2(1.0, 5.0)

var reverse := false:
	set(value):
		if reverse != value:
			reverse = value
			queue_redraw()


func _ready() -> void:
	var stock := Polygon2D.new()
	stock.name = "Stock"
	stock.z_as_relative = false
	stock.z_index = 2
	stock.color = Color("#151d22")
	stock.polygon = PackedVector2Array([
		Vector2(-26, -11), Vector2(-11, -11), Vector2(-6, -9),
		Vector2(-10, -4), Vector2(-23, -1), Vector2(-26, -2),
	])
	add_child(stock)
	var stock_panel := Polygon2D.new()
	stock_panel.color = Color("#626348")
	stock_panel.polygon = PackedVector2Array([
		Vector2(-24, -9), Vector2(-11, -9), Vector2(-8, -6), Vector2(-23, -3),
	])
	stock.add_child(stock_panel)

	var magazine := Polygon2D.new()
	magazine.name = "Magazine"
	magazine.position = MAGAZINE_SEAT
	magazine.polygon = PackedVector2Array([
		Vector2(-4, -2), Vector2(4, -2), Vector2(5, 8), Vector2(3, 12),
		Vector2(-3, 12), Vector2(-5, 9),
	])
	magazine.color = Color("#283238")
	add_child(magazine)
	var rib := Polygon2D.new()
	rib.polygon = PackedVector2Array([Vector2(1, 0), Vector2(3, 0), Vector2(4, 9), Vector2(2, 10)])
	rib.color = Color("#586466")
	magazine.add_child(rib)
	var muzzle := Marker2D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector2(40, -8)
	add_child(muzzle)


func _draw() -> void:
	var outline := Color("#151d22")
	draw_colored_polygon(PackedVector2Array([
		Vector2(-10, -9), Vector2(-6, -9), Vector2(-3, -11),
		Vector2(27, -11), Vector2(27, -5), Vector2(13, 0), Vector2(3, 0),
		Vector2(1, 7), Vector2(-6, 7), Vector2(-5, -3), Vector2(-10, -4),
	]), outline)
	draw_rect(Rect2(25, -10, 15, 4), outline)
	draw_rect(Rect2(29, -9, 10, 1), Color("#747d79"))
	draw_rect(Rect2(36, -11, 5, 6), outline)
	draw_rect(Rect2(26, -14, 3, 5), outline)
	draw_rect(Rect2(-5, -14, 5, 3), outline)
	draw_rect(Rect2(-6, -9, 20, 7), Color("#4e5c61"))
	draw_rect(Rect2(-5, -9, 18, 1), Color("#838d8b"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(12, -9), Vector2(26, -9), Vector2(25, -5), Vector2(13, -2),
	]), Color("#66684b"))
	for x in [16, 19, 22]:
		draw_rect(Rect2(x, -8, 2, 2), Color("#333b35"))
	draw_rect(Rect2(-5, 1, 5, 5), Color("#575844"))
	if reverse:
		draw_rect(Rect2(1, -8, 10, 3), Color("#202a30"))
		draw_rect(Rect2(3, -8, 5, 1), Color("#92938a"))
	else:
		draw_rect(Rect2(-3, -7, 11, 1), Color("#242e34"))
		draw_rect(Rect2(-1, -5, 3, 2), Color("#92938a"))
