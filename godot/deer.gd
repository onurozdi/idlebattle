extends Node2D

const ART := preload("res://assets/deer-parts.webp")
const HINGE := preload("res://ragdoll_hinge.gd")
const HIT_MARK := preload("res://hit_mark.gd")
const FEET_Y := 378.0
const UPPER_LENGTH := 24.0
const MAX_HEALTH := 100
const BODY_DAMAGE := 10
const FLINCH_TIME := .16
const LEGS := ["far_rear", "far_front", "near_rear", "near_front"]
const ART_REGIONS := [
	Rect2(51, 171, 436, 220), Rect2(654, 159, 279, 279), Rect2(1077, 32, 370, 432),
	Rect2(203, 560, 135, 405), Rect2(666, 546, 196, 423), Rect2(1231, 571, 80, 383),
]

var parts: Dictionary = {}
var hurt_shape_origins: Dictionary = {}
var last_pose: Dictionary = {}
var velocities: Dictionary = {}
var spin: Dictionary = {}
var joints: Array[PinJoint2D] = []
var marks: Array[Node2D] = []
var health_meter: ProgressBar
var health := MAX_HEALTH
var flinch := 0.0
var hit_direction := Vector2.ZERO
var fallen := false
var pace := true
var step := 0.0
var facing := 1.0
var lane := 625.0


func _ready() -> void:
	_part("body", 0, Vector2(93, 43), Vector2(46, 23), Vector2.ZERO, Vector2(79, 32), 4.8, 3)
	_part("neck", 1, Vector2(33, 44), Vector2(9, 36), Vector2(8, -15), Vector2(21, 31), 1.4, 3)
	_part("head", 2, Vector2(45, 50), Vector2(15, 43), Vector2(8, -5), Vector2(27, 16), 1.1, 4)
	for leg in LEGS:
		var near: bool = leg.begins_with("near")
		var front: bool = leg.ends_with("front")
		_part(leg + "_upper", 3 if front else 4, Vector2(16 if front else 21, 29), Vector2(8 if front else 10, 3),
			Vector2(0, 11), Vector2(11 if front else 15, 25), .7, 4 if near else 1)
		_part(leg + "_lower", 5, Vector2(12, 28), Vector2(5, 3), Vector2(0, 11), Vector2(8, 25), .45, 4 if near else 1)
	_make_health_meter()
	reset_pose()


func _make_health_meter() -> void:
	health_meter = ProgressBar.new()
	health_meter.custom_minimum_size = Vector2(86, 8)
	health_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_meter.show_percentage = false
	health_meter.max_value = MAX_HEALTH
	health_meter.z_index = 16
	var background := StyleBoxFlat.new()
	background.bg_color = Color("#1c2225")
	background.border_color = Color("#e0c099")
	background.set_border_width_all(1)
	health_meter.add_theme_stylebox_override("background", background)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#bd5948")
	fill.set_content_margin_all(1)
	health_meter.add_theme_stylebox_override("fill", fill)
	add_child(health_meter)


func _part(key: String, tile: int, size: Vector2, pivot: Vector2, center: Vector2, bounds: Vector2, mass: float, layer: int) -> void:
	var body := RigidBody2D.new()
	body.name = key
	body.freeze = true
	body.mass = mass
	body.collision_layer = 4
	body.collision_mask = 0
	body.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	body.linear_damp = 1.45
	body.angular_damp = 3.0
	body.z_index = layer
	body.set_meta("target", self)
	var sprite := Sprite2D.new()
	var texture := AtlasTexture.new()
	texture.atlas = ART
	texture.region = ART_REGIONS[tile]
	texture.filter_clip = true
	sprite.texture = texture
	sprite.centered = false
	sprite.position = -pivot
	sprite.scale = size / texture.region.size
	if key.begins_with("far"):
		sprite.modulate = Color("#b2a8a1")
	var art := Node2D.new()
	art.name = "Art"
	sprite.name = "Sprite"
	art.add_child(sprite)
	body.add_child(art)
	var collision := CollisionShape2D.new()
	collision.name = "HurtShape"
	var shape := CapsuleShape2D.new()
	shape.radius = minf(bounds.x, bounds.y) * .5
	shape.height = maxf(bounds.x, bounds.y)
	collision.shape = shape
	collision.position = center
	collision.rotation = PI / 2 if bounds.x > bounds.y else 0.0
	body.add_child(collision)
	add_child(body)
	parts[key] = body
	hurt_shape_origins[key] = center


func advance(delta: float) -> void:
	if fallen:
		for joint in joints:
			joint.enforce(delta)
		return
	flinch = maxf(0, flinch - delta)
	if pace:
		lane += facing * delta * 42.0
		if lane > 801.0 or lane < 570.0:
			facing = -facing
			lane = clampf(lane, 570, 801)
		step += delta * 7.2
	_pose(delta)


func _process(_delta: float) -> void:
	if fallen:
		for joint in joints:
			joint.sync_art()


func _pose(delta: float) -> void:
	var root := Vector2(lane, FEET_Y - 61.0 - absf(sin(step)) * 1.5)
	root += hit_direction * sin(PI * flinch / FLINCH_TIME) * 3.4
	health_meter.position = (root + Vector2(-43, -101)).round()
	var height := sin(step) * .033
	var chest := root + _flip(Vector2(31, -3))
	var skull := chest + _flip(Vector2(17, -31).rotated(height))
	_animate_part("body", root, height, delta)
	_animate_part("neck", chest, height, delta)
	_animate_part("head", skull, height * -.7, delta)
	for index in LEGS.size():
		var leg: String = LEGS[index]
		var front := leg.ends_with("front")
		var cycle := step + (PI if index == 0 or index == 3 else 0.0)
		var upper := sin(cycle) * .42 - (.15 if front else -.15)
		var bend := maxf(0.0, -cos(cycle)) * (.62 if front else -.62)
		var lower := upper + bend
		var hip := root + _flip(Vector2(29 if front else -29, 10))
		var knee := hip + _flip(Vector2(0, UPPER_LENGTH).rotated(upper))
		_animate_part(leg + "_upper", hip, upper, delta)
		_animate_part(leg + "_lower", knee, lower, delta)


func _flip(point: Vector2) -> Vector2:
	return Vector2(point.x * facing, point.y)


func _animate_part(key: String, at: Vector2, angle: float, delta: float) -> void:
	var body: RigidBody2D = parts[key]
	var previous: Vector3 = last_pose.get(key, Vector3(at.x, at.y, angle * facing))
	body.position = at
	body.rotation = angle * facing
	body.get_node("Art/Sprite").flip_h = facing < 0.0
	body.get_node("HurtShape").position = _flip(hurt_shape_origins[key])
	last_pose[key] = Vector3(at.x, at.y, body.rotation)
	velocities[key] = ((at - Vector2(previous.x, previous.y)) / delta).limit_length(90.0)
	spin[key] = clampf(angle_difference(previous.z, body.rotation) / delta, -5.0, 5.0)


func _join(a: String, b: String, lower: float, upper: float) -> void:
	var joint := HINGE.new()
	add_child(joint)
	joint.configure(parts[a], parts[b], Vector2(lower, upper) if facing > 0.0 else Vector2(-upper, -lower))
	joints.append(joint)


func receive_shot(body: RigidBody2D, world_point: Vector2, direction: Vector2) -> bool:
	if marks.size() >= 16:
		marks.pop_front().queue_free()
	marks.append(HIT_MARK.attach(body.get_node("Art"), world_point, direction))
	if fallen:
		_apply_hit_impulse(body, world_point, direction)
		return false

	health = 0 if body == parts.head else maxi(0, health - BODY_DAMAGE)
	health_meter.value = health
	health_meter.visible = health > 0
	if health > 0:
		flinch = FLINCH_TIME
		hit_direction = direction
	else:
		_start_fall()
		_apply_hit_impulse(body, world_point, direction)
	return true


func _start_fall() -> void:
	fallen = true
	_join("body", "neck", -.64, .80)
	_join("neck", "head", -.68, .68)
	for leg in LEGS:
		_join("body", leg + "_upper", -1.53, 1.38)
		if leg.ends_with("front"):
			_join(leg + "_upper", leg + "_lower", 0.0, 2.32)
		else:
			_join(leg + "_upper", leg + "_lower", -2.33, 0.0)
	for key: String in parts:
		var bone: RigidBody2D = parts[key]
		bone.linear_velocity = velocities[key]
		bone.angular_velocity = spin[key]
		bone.collision_mask = 1
		bone.freeze = false
		bone.sleeping = false
	# Briefly buckle the front legs as weight moves forward from the hit.
	for leg in ["near_front_lower", "far_front_lower"]:
		parts[leg].angular_velocity += facing * 2.7


func _apply_hit_impulse(body: RigidBody2D, world_point: Vector2, direction: Vector2) -> void:
	body.apply_impulse(direction * (24.0 + body.mass * 14.0), world_point - body.global_position)


func reset_pose() -> void:
	for joint in joints:
		remove_child(joint)
		joint.queue_free()
	joints.clear()
	for mark in marks:
		mark.queue_free()
	marks.clear()
	for body: RigidBody2D in parts.values():
		body.freeze = true
		body.collision_mask = 0
		body.linear_velocity = Vector2.ZERO
		body.angular_velocity = 0.0
		body.get_node("Art").transform = Transform2D.IDENTITY
	fallen = false
	health = MAX_HEALTH
	health_meter.value = health
	health_meter.hide()
	flinch = 0.0
	facing = 1.0
	lane = 625.0
	step = 0.0
	last_pose.clear()
	_pose(1.0 / 60.0)
