extends Polygon2D

const TEXTURE := preload("res://assets/wildlife.webp")
const DRAW_SCALE := .34
const BODY := Vector2(743, 274)
const NECK := Vector2(843, 273)
const HEAD := Vector2(880, 204)

# Columns trace the flank and keep the source sprite's legs outside the skin mesh.
const BELLY := [
	Vector2(590, 303), Vector2(613, 318), Vector2(632, 331), Vector2(650, 333),
	Vector2(670, 323), Vector2(696, 316), Vector2(722, 324), Vector2(749, 334),
	Vector2(775, 335), Vector2(799, 336), Vector2(822, 331), Vector2(842, 322),
	Vector2(859, 308), Vector2(879, 285), Vector2(904, 264), Vector2(930, 239),
	Vector2(969, 224),
]
const ROWS := 13

var coordinates := PackedVector2Array()
var weights := PackedVector2Array()
var vertices := PackedVector2Array()


func _ready() -> void:
	texture = TEXTURE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var faces: Array[PackedInt32Array] = []
	for column in BELLY.size():
		var edge: Vector2 = BELLY[column]
		for row in ROWS:
			var pixel := Vector2(edge.x, lerpf(38.0, edge.y, float(row) / (ROWS - 1)))
			coordinates.append(pixel)
			weights.append(Vector2(smoothstep(807.0, 877.0, pixel.x), 1.0 - smoothstep(184.0, 233.0, pixel.y)))
			if column > 0 and row > 0:
				var i := coordinates.size() - 1
				faces.append(PackedInt32Array([i - ROWS - 1, i - 1, i, i - ROWS]))
	vertices.resize(coordinates.size())
	uv = coordinates
	polygons = faces


func follow(body: Transform2D, neck: Transform2D, head: Transform2D, facing: float) -> void:
	var mirror := Vector2(facing, 1)
	for i in coordinates.size():
		var pixel := coordinates[i]
		var trunk_point := body * ((pixel - BODY) * DRAW_SCALE * mirror)
		var neck_point := neck * ((pixel - NECK) * DRAW_SCALE * mirror)
		var head_point := head * ((pixel - HEAD) * DRAW_SCALE * mirror)
		vertices[i] = trunk_point.lerp(neck_point, weights[i].x).lerp(head_point, weights[i].y)
	polygon = vertices
