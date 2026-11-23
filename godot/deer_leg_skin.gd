extends Polygon2D

const TEXTURE := preload("res://assets/wildlife.webp")
const KNEE_ROW := 6
const PIXEL_SCALE := .34

# Each row samples one cross-section of the original leg: length, left, right and y.
# Length 0 is the hip, 1 is the knee or hock and 2 is the sole.
const FORE := [
	Vector4(-.34, 797, 860, 286),
	Vector4(0.0, 795, 859, 305),
	Vector4(.25, 796, 846, 325),
	Vector4(.49, 799, 838, 343),
	Vector4(.70, 799, 834, 356),
	Vector4(.86, 798, 829, 366),
	Vector4(1.0, 797, 825, 375),
	Vector4(1.17, 797, 820, 390),
	Vector4(1.39, 793, 816, 407),
	Vector4(1.61, 788, 813, 425),
	Vector4(1.83, 788, 823, 442),
	Vector4(2.0, 788, 832, 458),
]
const HIND := [
	Vector4(-.34, 641, 718, 274),
	Vector4(0.0, 643, 719, 296),
	Vector4(.25, 640, 704, 315),
	Vector4(.49, 633, 689, 331),
	Vector4(.70, 625, 672, 343),
	Vector4(.86, 614, 661, 352),
	Vector4(1.0, 612, 651, 365),
	Vector4(1.17, 609, 644, 382),
	Vector4(1.39, 606, 639, 402),
	Vector4(1.61, 598, 633, 423),
	Vector4(1.83, 597, 631, 442),
	Vector4(2.0, 598, 638, 458),
]

var section_rows: Array
var vertices := PackedVector2Array()


func configure(is_front: bool, is_far: bool) -> void:
	section_rows = FORE if is_front else HIND
	texture = TEXTURE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if is_far:
		modulate = Color("#b0a297")
	var coordinates := PackedVector2Array()
	var faces: Array[PackedInt32Array] = []
	for i in section_rows.size():
		var row: Vector4 = section_rows[i]
		coordinates.append(Vector2(row.y, row.w))
		coordinates.append(Vector2(row.z, row.w))
		if i > 0:
			var a := i * 2
			faces.append(PackedInt32Array([a - 2, a - 1, a + 1, a]))
	vertices.resize(coordinates.size())
	uv = coordinates
	polygons = faces


func follow(hip: Vector2, knee: Vector2, sole: Vector2, body_down: Vector2, facing: float) -> void:
	var thigh := knee - hip
	var shin := sole - knee
	var thigh_angle := thigh.angle()
	var shin_angle := shin.angle()
	var bend := absf(angle_difference(thigh_angle, shin_angle))
	for i in section_rows.size():
		var row: Vector4 = section_rows[i]
		var along := row.x
		var center := hip + thigh * along if along <= 1.0 else knee + shin * (along - 1.0)
		var tangent := lerp_angle(thigh_angle, shin_angle, smoothstep(.70, 1.30, along))
		var hip_overlap := smoothstep(-.34, .17, along)
		if along < 0.0:
			center = hip + body_down * (along * thigh.length())
		tangent = lerp_angle(body_down.angle(), tangent, hip_overlap)
		var crease := (1.0 - smoothstep(0.0, .36, absf(along - 1.0))) * smoothstep(1.1, 2.4, bend)
		var width := (row.z - row.y) * PIXEL_SCALE * .5 * (1.0 - .29 * crease) * lerpf(.72, 1.0, hip_overlap)
		var across := Vector2.from_angle(tangent - PI * .5) * width * facing
		vertices[2 * i] = center - across
		vertices[2 * i + 1] = center + across
	polygon = vertices
