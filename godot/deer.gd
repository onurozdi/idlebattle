extends Node2D

class FallingTorso extends RigidBody2D:
	var death_x: float

	func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
		# Allow the torso to fall and rotate in place without gliding across the deck.
		var pose := state.transform
		pose.origin.x = death_x
		state.transform = pose
		state.linear_velocity = Vector2(0.0, state.linear_velocity.y)


const ART := preload("res://assets/deer-parts.webp")
const SKIN := preload("res://deer_skin.gd")
const HINGE := preload("res://ragdoll_hinge.gd")
const HIT_MARK := preload("res://hit_mark.gd")
const FEET_Y := 378.0
const UPPER_LENGTH := 24.0
const METRE := 64.0
const ALERT_DISTANCE := 6.0 * METRE
const SPAWN_X := 715.0
const WALK_SPEED := 60.0
const RUN_SPEED := 215.0
const ACCELERATION := 430.0
const BRAKING := 560.0
const ALERT_TIME := 4.0
const PATROL_LEFT := 580.0
const PATROL_RIGHT := 805.0
const RANGE_LEFT := 86.0
const RANGE_RIGHT := 874.0
const MAX_HEALTH := 100
const BODY_DAMAGE := 10
const MAX_MARKS := 32
const FLINCH_TIME := .16
const LEGS := ["far_rear", "far_front", "near_rear", "near_front"]
const WALK_CONTACT := [0.0, .25, .50, .75]
const RUN_CONTACT := [0.0, .43, .11, .55]
const ART_REGIONS := [
	Rect2(203, 560, 135, 405), Rect2(666, 546, 196, 423), Rect2(1231, 571, 80, 383),
]

var parts: Dictionary = {}
var hurt_shape_origins: Dictionary = {}
var joints: Array[PinJoint2D] = []
var marks: Array[Node2D] = []
var skin: Polygon2D
var health_meter: ProgressBar
var health := MAX_HEALTH
var flinch := 0.0
var hit_direction := Vector2.ZERO
var fallen := false
var pace := true
var step := 0.0
var speed := 0.0
var alarm := 0.0
var patrol_direction := 1.0
var facing := 1.0
var lane := SPAWN_X


func _ready() -> void:
	_part("body", -1, Vector2.ZERO, Vector2.ZERO, Vector2(0, 1), Vector2(81, 33), 4.8, 3)
	_part("neck", -1, Vector2.ZERO, Vector2.ZERO, Vector2(8, -9), Vector2(21, 28), 1.4, 3)
	_part("head", -1, Vector2.ZERO, Vector2.ZERO, Vector2(12, -5), Vector2(28, 15), 1.1, 4)
	for leg in LEGS:
		var near: bool = leg.begins_with("near")
		var front: bool = leg.ends_with("front")
		_part(leg + "_upper", 0 if front else 1, Vector2(16 if front else 21, 31), Vector2(8 if front else 10, 4),
			Vector2(0, 11), Vector2(11 if front else 15, 25), .7, 2 if near else 1)
		_part(leg + "_lower", 2, Vector2(12, 28), Vector2(5, 4), Vector2(0, 11), Vector2(8, 25), .45, 2 if near else 1)
	skin = SKIN.new()
	skin.z_index = 3
	add_child(skin)
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
	var body: RigidBody2D = FallingTorso.new() if key == "body" else RigidBody2D.new()
	body.name = key
	body.freeze = true
	body.mass = mass
	body.collision_layer = 4
	body.collision_mask = 0
	body.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	body.linear_damp = 1.45
	body.angular_damp = 3.0
	body.z_index = layer
	if tile >= 0:
		# Hooves can fold under the torso instead of bracing against the deck.
		var hoof_contact := PhysicsMaterial.new()
		hoof_contact.friction = .08
		body.physics_material_override = hoof_contact
	body.set_meta("target", self)
	var art := Node2D.new()
	art.name = "Art"
	body.add_child(art)
	if tile >= 0:
		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
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
		art.add_child(sprite)
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


func advance(delta: float, hunter_x: float) -> void:
	if fallen:
		for joint in joints:
			joint.enforce(delta)
		return
	flinch = maxf(0, flinch - delta)
	if pace:
		_move(delta, hunter_x)
	_pose()


func _move(delta: float, hunter_x: float) -> void:
	if absf(lane - hunter_x) < ALERT_DISTANCE:
		alarm = ALERT_TIME
	else:
		alarm = maxf(0.0, alarm - delta)
	if lane <= PATROL_LEFT:
		patrol_direction = 1.0
	elif lane >= PATROL_RIGHT:
		patrol_direction = -1.0
	var direction := patrol_direction
	var target_speed := WALK_SPEED
	if alarm > 0.0:
		direction = facing if is_equal_approx(lane, hunter_x) else signf(lane - hunter_x)
		target_speed = RUN_SPEED
	var limit := RANGE_RIGHT if facing > 0.0 else RANGE_LEFT
	target_speed = minf(target_speed, sqrt(2.0 * BRAKING * absf(limit - lane)))
	if facing != direction:
		target_speed = 0.0
	speed = move_toward(speed, target_speed, (ACCELERATION if speed < target_speed else BRAKING) * delta)
	if speed < 1.0:
		facing = direction
	var next := clampf(lane + facing * speed * delta, RANGE_LEFT, RANGE_RIGHT)
	var stride := lerpf(35.0, 113.0, _gallop())
	step = fposmod(step + absf(next - lane) / stride, 1.0)
	lane = next


func _gallop() -> float:
	return smoothstep(WALK_SPEED + 12.0, RUN_SPEED - 16.0, speed)


func _process(_delta: float) -> void:
	if fallen:
		for joint in joints:
			joint.sync_art()
	_update_skin()


func _update_skin() -> void:
	var to_skin := skin.global_transform.affine_inverse()
	skin.follow(
		to_skin * parts.body.get_node("Art").global_transform,
		to_skin * parts.neck.get_node("Art").global_transform,
		to_skin * parts.head.get_node("Art").global_transform, facing)


func _pose() -> void:
	var run := _gallop()
	var moving := smoothstep(0.0, WALK_SPEED, speed)
	var cycle := step * TAU
	var bob := lerpf(1.0 - cos(cycle * 2.0), 2.5 + maxf(0.0, sin((step - .32) * TAU * 2.0)) * 8.0, run)
	var root := Vector2(lane, FEET_Y - 57.0 - bob * moving)
	root += hit_direction * sin(PI * flinch / FLINCH_TIME) * 3.4
	health_meter.position = (root + Vector2(-43, -101)).round()
	var pitch := .025 + lerpf(sin(cycle) * .035, sin(cycle + .35) * .18, run) * moving
	var chest := root + _flip(((SKIN.NECK - SKIN.BODY) * SKIN.DRAW_SCALE).rotated(pitch))
	var neck_angle := pitch * .6 + (cos(cycle) * .085 + .095) * run
	var skull := chest + _flip(((SKIN.HEAD - SKIN.NECK) * SKIN.DRAW_SCALE).rotated(neck_angle))
	_animate_part("body", root, pitch)
	_animate_part("neck", chest, neck_angle)
	_animate_part("head", skull, -neck_angle * .45)
	for index in LEGS.size():
		_pose_leg(index, root, pitch, run, moving)


static func hoof_cycle(phase: float, stance: float, stride: float, clearance: float) -> Vector2:
	var travel := stride * stance
	if phase < stance:
		return Vector2(travel * .5 - phase * stride, 0)
	var swing := inverse_lerp(stance, 1.0, phase)
	return Vector2(lerpf(-travel * .5, travel * .5, smoothstep(0.0, 1.0, swing)),
		-clearance * sin(swing * PI))


func _pose_leg(index: int, root: Vector2, pitch: float, run: float, moving: float) -> void:
	var leg: String = LEGS[index]
	var front := leg.ends_with("front")
	var far := leg.begins_with("far")
	var mount := Vector2((29.0 if front else -29.0) + (-2.0 if far else 2.0), 10.0)
	var knee_socket := Vector2(-1.5 if front else -4.0, UPPER_LENGTH)
	var hoof_socket := Vector2(2.0, 24.0)
	var walk_hoof := hoof_cycle(fposmod(step - WALK_CONTACT[index], 1.0), .64, 35.0, 11.0)
	var run_hoof := hoof_cycle(fposmod(step - RUN_CONTACT[index], 1.0), .31, 113.0, 27.0 if front else 31.0)
	var stride := walk_hoof.lerp(run_hoof, run) * moving
	var resting_offset := (4.0 if front else -4.0) + (-3.0 if far else 2.0)
	var foot_x := mount.x + resting_offset + stride.x
	var foot_y := FEET_Y + stride.y
	var hip_offset := mount.rotated(pitch)
	var hip := root + _flip(hip_offset)
	var to_foot := Vector2(foot_x - hip_offset.x, foot_y - hip.y)
	var upper_length := knee_socket.length()
	var lower_length := hoof_socket.length()
	var reach := clampf(to_foot.length(), absf(upper_length - lower_length) + .1, upper_length + lower_length - .15)
	var bend := acos(clampf((upper_length * upper_length + reach * reach - lower_length * lower_length) / (2.0 * upper_length * reach), -1.0, 1.0))
	# The forelegs and hocks fold in opposite directions.
	var upper_angle := to_foot.angle() - knee_socket.angle() + (-bend if front else bend)
	var knee_offset := knee_socket.rotated(upper_angle)
	var lower_angle := (to_foot.normalized() * reach - knee_offset).angle() - hoof_socket.angle()
	_animate_part(leg + "_upper", hip, upper_angle)
	_animate_part(leg + "_lower", hip + _flip(knee_offset), lower_angle)


func _flip(point: Vector2) -> Vector2:
	return Vector2(point.x * facing, point.y)


func _animate_part(key: String, at: Vector2, angle: float) -> void:
	var body: RigidBody2D = parts[key]
	body.position = at
	body.rotation = angle * facing
	var sprite := body.get_node_or_null("Art/Sprite") as Sprite2D
	if sprite:
		sprite.flip_h = facing < 0.0
	body.get_node("HurtShape").position = _flip(hurt_shape_origins[key])


func _join(a: String, b: String, lower: float, upper: float) -> void:
	var joint := HINGE.new()
	add_child(joint)
	joint.configure(parts[a], parts[b], Vector2(lower, upper) if facing > 0.0 else Vector2(-upper, -lower))
	joints.append(joint)


func receive_shot(body: RigidBody2D, world_point: Vector2, direction: Vector2) -> bool:
	if marks.size() >= MAX_MARKS:
		marks.pop_front().queue_free()
	marks.append(HIT_MARK.attach(body.get_node("Art"), world_point, direction))
	if fallen:
		return false

	health = 0 if body == parts.head else maxi(0, health - BODY_DAMAGE)
	health_meter.value = health
	health_meter.visible = health > 0
	if health > 0:
		alarm = ALERT_TIME
		flinch = FLINCH_TIME
		hit_direction = direction
	else:
		_start_fall()
	return true


func _start_fall() -> void:
	fallen = true
	parts.body.death_x = parts.body.global_position.x
	_join("body", "neck", -.64, .80)
	_join("neck", "head", -.68, .68)
	for leg in LEGS:
		_join("body", leg + "_upper", -1.53, 1.38)
		if leg.ends_with("front"):
			_join(leg + "_upper", leg + "_lower", 0.0, 2.32)
		else:
			_join(leg + "_upper", leg + "_lower", -2.33, 0.0)
	for bone: RigidBody2D in parts.values():
		bone.linear_velocity = Vector2.ZERO
		bone.angular_velocity = 0.0
		bone.collision_mask = 1
		bone.freeze = false
		bone.sleeping = false


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
	patrol_direction = 1.0
	lane = SPAWN_X
	step = 0.0
	speed = 0.0
	alarm = 0.0
	_pose()
	_update_skin()
