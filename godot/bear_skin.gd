extends "res://deer_skin.gd"

const SOURCE_BODY := Vector2(246, 741)
const SOURCE_NECK := Vector2(350, 734)
const SOURCE_HEAD := Vector2(399, 730)
const BEAR_SCALE := .40

const BEAR_BELLY := [
	Vector2(54, 811), Vector2(77, 815), Vector2(101, 828), Vector2(126, 832),
	Vector2(152, 830), Vector2(177, 816), Vector2(200, 805), Vector2(224, 808),
	Vector2(247, 820), Vector2(273, 826), Vector2(298, 822), Vector2(323, 804),
	Vector2(348, 787), Vector2(373, 779), Vector2(399, 778), Vector2(425, 775),
	Vector2(451, 768), Vector2(486, 765),
]


func _ready() -> void:
	bind_body = SOURCE_BODY
	bind_neck = SOURCE_NECK
	bind_head = SOURCE_HEAD
	scale_factor = BEAR_SCALE
	_build(BEAR_BELLY, 626.0)


func _skin_weights(pixel: Vector2) -> Vector2:
	return Vector2(smoothstep(303.0, 385.0, pixel.x), smoothstep(355.0, 438.0, pixel.x))
