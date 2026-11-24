extends "res://deer_skin.gd"

const SOURCE_BODY := Vector2(1246, 310)
const SOURCE_NECK := Vector2(1330, 311)
const SOURCE_HEAD := Vector2(1394, 318)
const BOAR_SCALE := .29

const BOAR_BELLY := [
	Vector2(1077, 370), Vector2(1101, 367), Vector2(1120, 358), Vector2(1140, 358),
	Vector2(1158, 358), Vector2(1179, 363), Vector2(1198, 369), Vector2(1215, 376),
	Vector2(1233, 378), Vector2(1250, 377), Vector2(1270, 371), Vector2(1290, 370),
	Vector2(1310, 370), Vector2(1330, 373), Vector2(1355, 374), Vector2(1380, 376),
	Vector2(1405, 377), Vector2(1430, 379), Vector2(1454, 379), Vector2(1484, 379),
]


func _ready() -> void:
	bind_body = SOURCE_BODY
	bind_neck = SOURCE_NECK
	bind_head = SOURCE_HEAD
	scale_factor = BOAR_SCALE
	_build(BOAR_BELLY, 196.0)


func _skin_weights(pixel: Vector2) -> Vector2:
	return Vector2(smoothstep(1272.0, 1354.0, pixel.x), smoothstep(1342.0, 1428.0, pixel.x))
