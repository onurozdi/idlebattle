extends Node2D

const ATLAS := preload("res://assets/rods.webp")
const SCALE := .19
const COLUMNS := 24
# The lower row of the atlas has the reel beneath the grip.
const REGIONS := [Rect2(34, 614, 525, 162), Rect2(618, 614, 528, 171), Rect2(1204, 611, 541, 187)]
const GRIPS := [Vector2(132, 668), Vector2(717, 669), Vector2(1304, 667)]
const TIPS := [Vector2(550, 627), Vector2(1135, 628), Vector2(1735, 623)]
const REELS := [Vector2(129, 744), Vector2(714, 745), Vector2(1315, 752)]

var mesh: Polygon2D
var level := 1
var bend := INF


func _ready() -> void:
	mesh = Polygon2D.new()
	mesh.texture = ATLAS
	mesh.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(mesh)
	var faces: Array[PackedInt32Array] = []
	for column in COLUMNS:
		var i := 2 * column
		faces.append(PackedInt32Array([i, i + 1, i + 3, i + 2]))
	mesh.polygons = faces
	_configure_atlas()
	flex(0.0)


func set_level(value: int) -> void:
	if value == level:
		return
	level = value
	_configure_atlas()
	bend = INF
	flex(0.0)


func _configure_atlas() -> void:
	var region: Rect2 = REGIONS[level - 1]
	var coordinates := PackedVector2Array()
	for column in COLUMNS + 1:
		var x := region.position.x + region.size.x * float(column) / COLUMNS
		coordinates.append(Vector2(x, region.position.y))
		coordinates.append(Vector2(x, region.end.y))
	mesh.uv = coordinates


func flex(amount: float) -> void:
	if is_equal_approx(amount, bend):
		return
	bend = amount
	var vertices := PackedVector2Array()
	for source in mesh.uv:
		vertices.append(_bent_point(source))
	mesh.polygon = vertices


func _bent_point(source: Vector2) -> Vector2:
	var index := level - 1
	var grip: Vector2 = GRIPS[index]
	var tip: Vector2 = TIPS[index]
	var relative := (source - grip) * SCALE
	var along := clampf((source.x - grip.x) / (tip.x - grip.x), 0.0, 1.0)
	relative.y += bend * pow(along, 2.5)
	return relative


func line_tip() -> Vector2:
	return to_global(_bent_point(TIPS[level - 1]))


func reel_grip(turn: float) -> Vector2:
	var grip: Vector2 = (REELS[level - 1] - GRIPS[level - 1]) * SCALE
	return to_global(grip + Vector2(cos(turn) * 3.2, sin(turn) * 3.2))
