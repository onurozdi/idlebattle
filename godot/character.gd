extends Node2D

const ART := preload("res://assets/character-parts.webp")
const ROD := preload("res://assets/rods.webp")
const HINGE := preload("res://ragdoll_hinge.gd")
const SCRATCH_SHADER := preload("res://claw_scratch.gdshader")
const SCRATCH_MARKS_PER_PART := 4
const GROUND := 378.0
const LEG := 21.0
const SHIN := 19.0
const ARM := 15.0
const FOREARM := 14.0
const CAST_LENGTH := .87
const MAGAZINE_CAPACITY := 12
const RELOAD_DURATION := .82
const RUN_SPEED := 155.0
const ACCELERATION := 930.0
const WALK_HEALTH_THRESHOLD := 50
const WALK_STRIDE := 55.0
const RUN_STRIDE := 96.0
const BOOT_SIZE := Vector2(20, 16)
const BOOT_COLLAR := Vector2(5.5, 4.0)
const BOOT_HURT_CENTER := Vector2(5.5, 4.0)
const BOOT_HEEL := -2.5
const BOOT_TOE := 12.5
const BOOT_SOLE := 11.0
const KNEE_LIMIT := 2.26
# Time, shoulder, elbow, and rod angle. The other hand follows the reel.
const CAST_KEYS := [
	Vector4(0, .13, -1.32, -.57),
	Vector4(.17, -.60, -1.85, -1.35),
	Vector4(.35, -2.30, -.83, -2.03),
	Vector4(.46, -2.04, -.02, -1.55),
	Vector4(.60, -1.51, -.04, -.22),
	Vector4(.72, -1.30, -.15, .19),
	Vector4(.87, .04, -1.33, -.51),
]
const ART_REGIONS := [
	Rect2(88, 118, 272, 254), Rect2(556, 153, 153, 241), Rect2(947, 252, 162, 137),
	Rect2(176, 506, 105, 244), Rect2(584, 539, 95, 192), Rect2(991, 581, 97, 112),
	Rect2(159, 888, 123, 252), Rect2(573, 900, 104, 233), Rect2(957, 956, 174, 157),
]

var parts: Dictionary = {}
var joints: Array[PinJoint2D] = []
var last_pose: Dictionary = {}
var velocities: Dictionary = {}
var angular_velocities: Dictionary = {}
var scratch_marks: Dictionary = {}
var rod: Sprite2D
var weapon: Node2D
var muzzle: Marker2D
var magazine: Polygon2D
var rounds_in_magazine := MAGAZINE_CAPACITY
var reload_time := -1.0
var aim := Vector2(650, 313)
var recoil := 0.0
var facing := 1.0
var fallen := false
var cast_time := -1.0
var gait_phase := 0.0
var gait_weight := 0.0
var run_blend := 1.0
var gait_direction := 1.0
const START_X := 135.0
const STAGE_LEFT := 32.0
const STAGE_RIGHT := 1407.0
var anchor_x := START_X
var move_speed := 0.0
var cast_has_line := false
var cast_landing := Vector2.ZERO
var lure := Vector2.ZERO
var tip := Vector2.ZERO
var elapsed := 0.0


func _ready() -> void:
	_part("hips", 2, Vector2(24, 19), Vector2(12, 8), Vector2(0, 1), Vector2(20, 16), 2.1, 2)
	_part("torso", 1, Vector2(29, 39), Vector2(14.5, 36), Vector2(0, -16), Vector2(24, 31), 3.4, 3)
	_part("head", 0, Vector2(35, 36), Vector2(17.5, 33), Vector2(0, -16), Vector2(27, 30), 1.6, 4)
	for side in ["far", "near"]:
		var layer: int = 1 if side == "far" else 4
		_part(side + "_thigh", 6, Vector2(17, 27), Vector2(8.5, 3), Vector2(0, LEG * .5), Vector2(13, LEG + 2), 1.3, layer)
		_part(side + "_shin", 7, Vector2(15, 24), Vector2(7.5, 3), Vector2(0, SHIN * .5), Vector2(11, SHIN + 2), .9, layer)
		_part(side + "_boot", 8, BOOT_SIZE, BOOT_COLLAR, BOOT_HURT_CENTER, Vector2(17, 11), .6, layer + 1)
		_part(side + "_arm", 3, Vector2(15, 20), Vector2(7.5, 3), Vector2(0, ARM * .5), Vector2(11, ARM + 2), .6, layer + 1 if side == "near" else 0)
		_part(side + "_forearm", 4, Vector2(13, 18), Vector2(6.5, 3), Vector2(0, FOREARM * .5), Vector2(9, FOREARM + 2), .46, layer + 2 if side == "near" else 0)
	_part("far_hand", 5, Vector2(10, 10), Vector2(5, 5), Vector2.ZERO, Vector2(8, 8), .22, 1)
	_part("hand", 5, Vector2(11, 11), Vector2(5.5, 5.5), Vector2.ZERO, Vector2(9, 9), .26, 8)

	rod = Sprite2D.new()
	var texture := AtlasTexture.new()
	texture.atlas = ROD
	texture.region = Rect2(36, 184, 520, 105)
	texture.filter_clip = true
	rod.texture = texture
	rod.centered = false
	rod.offset = Vector2(-82, -89)
	rod.scale = Vector2.ONE * .245
	rod.z_index = 7
	add_child(rod)
	_make_weapon()
	reset_pose()


func _make_weapon() -> void:
	weapon = Node2D.new()
	weapon.z_index = 7
	add_child(weapon)
	for detail in [
		[PackedVector2Array([Vector2(-7, -8), Vector2(18, -8), Vector2(18, -2), Vector2(4, -2), Vector2(2, 7), Vector2(-6, 7), Vector2(-5, 0), Vector2(-7, 0)]), Color("#16212b")],
		[PackedVector2Array([Vector2(-5, -7), Vector2(17, -7), Vector2(17, -4), Vector2(-5, -4)]), Color("#64717f")],
		[PackedVector2Array([Vector2(-5, 0), Vector2(1, 0), Vector2(0, 6), Vector2(-6, 6)]), Color("#845b41")],
	]:
		var shape := Polygon2D.new()
		shape.polygon = detail[0]
		shape.color = detail[1]
		weapon.add_child(shape)
	magazine = Polygon2D.new()
	magazine.polygon = PackedVector2Array([Vector2(-3, -2), Vector2(2, -2), Vector2(2, 2), Vector2(-3, 2)])
	magazine.color = Color("#64717f")
	magazine.position = Vector2(-2.5, 6.0)
	weapon.add_child(magazine)
	muzzle = Marker2D.new()
	muzzle.position = Vector2(18, -5)
	weapon.add_child(muzzle)


func _part(key: String, tile: int, size: Vector2, pivot: Vector2, shape_center: Vector2, shape_size: Vector2, mass: float, layer: int) -> void:
	var body := RigidBody2D.new()
	body.name = key
	body.freeze = true
	body.mass = mass
	body.collision_layer = 2
	body.collision_mask = 0
	body.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	body.linear_damp = 1.8
	body.angular_damp = 3.0
	body.z_index = layer

	var image := Sprite2D.new()
	var texture := AtlasTexture.new()
	texture.atlas = ART
	texture.region = ART_REGIONS[tile]
	texture.filter_clip = true
	image.texture = texture
	image.centered = false
	image.position = -pivot
	image.scale = size / texture.region.size
	if key.begins_with("far_"):
		image.modulate = Color("#acb2c0")
	var art := Node2D.new()
	art.name = "Art"
	image.name = "Sprite"
	art.add_child(image)
	body.add_child(art)

	var collider := CollisionShape2D.new()
	collider.name = "HurtShape"
	var shape := CapsuleShape2D.new()
	shape.radius = minf(shape_size.x, shape_size.y) * .5
	shape.height = shape_size.y
	collider.shape = shape
	collider.position = shape_center
	body.add_child(collider)
	add_child(body)
	parts[key] = body


func cast() -> void:
	if not fallen and cast_time < 0.0 and reload_time < 0.0:
		cast_time = 0.0
		cast_has_line = false


func reload() -> void:
	if fallen or cast_time >= 0.0 or reload_time >= 0.0 or rounds_in_magazine == MAGAZINE_CAPACITY:
		return
	cast_has_line = false
	reload_time = 0.0


func fire_pistol() -> bool:
	if fallen or cast_time >= 0.0 or reload_time >= 0.0 or rounds_in_magazine <= 0:
		return false
	rounds_in_magazine -= 1
	recoil = .16
	if rounds_in_magazine == 0:
		reload()
	return true


func advance(delta: float, movement: float, left := STAGE_LEFT, right := STAGE_RIGHT, health_percent := 100) -> void:
	if fallen:
		for joint in joints:
			joint.enforce(delta)
		return
	elapsed += delta
	recoil = move_toward(recoil, 0.0, delta * 2.8)
	if reload_time >= 0.0:
		reload_time += delta
		if reload_time >= RELOAD_DURATION:
			rounds_in_magazine = MAGAZINE_CAPACITY
			reload_time = -1.0
	var speed_limit := RUN_SPEED * clampf(health_percent / 100.0, 0.0, 1.0)
	run_blend = move_toward(run_blend, float(health_percent >= WALK_HEALTH_THRESHOLD), delta * 8.0)
	if cast_time < 0.0:
		if absf(movement) > .03 and cast_has_line:
			facing = signf(movement)
			cast_has_line = false
		elif absf(aim.x - anchor_x) > 14.0 and not cast_has_line:
			facing = signf(aim.x - anchor_x)
		move_speed = clampf(move_toward(move_speed, movement * speed_limit, delta * ACCELERATION), -speed_limit, speed_limit)
	else:
		move_speed = 0.0
		cast_time += delta
	var next_x := anchor_x + move_speed * delta
	anchor_x = clampf(next_x, left, right)
	if not is_equal_approx(anchor_x, next_x):
		move_speed = 0.0
	if not is_zero_approx(move_speed):
		gait_direction = signf(move_speed)
		var stride_length := lerpf(WALK_STRIDE, RUN_STRIDE, run_blend)
		gait_phase = fposmod(gait_phase + delta * absf(move_speed) / stride_length, 1.0)
	gait_weight = move_toward(gait_weight, float(not is_zero_approx(move_speed)), delta * 10.0)
	_pose(delta)
	if cast_time >= CAST_LENGTH:
		cast_time = -1.0
	queue_redraw()


func _process(_delta: float) -> void:
	if fallen:
		for joint in joints:
			joint.sync_art()


func _pose(delta: float) -> void:
	var holding_rod := cast_time >= 0.0 or cast_has_line
	var reload_pose := smoothstep(0.0, .18, reload_time) * (1.0 - smoothstep(.62, RELOAD_DURATION, reload_time))
	var rest := Vector4(0, .13, -1.32, -.52)
	var key := _cast_pose() if cast_time >= 0.0 else rest
	var travel := gait_direction * facing
	var lean := lerpf(.035, .14, run_blend) * gait_weight * travel
	if cast_time >= 0.0:
		lean += sin(cast_time / CAST_LENGTH * TAU) * -.09
	var walk_bob := 3.8 + 1.2 * cos(gait_phase * TAU * 2.0)
	var run_bob := 2.4 + 2.7 * cos((gait_phase - .08) * TAU * 2.0)
	var root := Vector2(anchor_x, GROUND - 50 + lerpf(walk_bob, run_bob, run_blend) * gait_weight)
	_move_part("hips", root, lean, delta)
	_move_part("torso", root, lean, delta)
	_move_part("head", root + _flip(Vector2(-1, -35).rotated(lean)), lean * .4, delta)

	_pose_leg("near", gait_phase, root + _flip(Vector2(4.0, 0.0)), travel, delta)
	_pose_leg("far", fposmod(gait_phase + .5, 1.0), root + _flip(Vector2(-4.0, 0.0)), travel, delta)

	var shoulder := root + _flip(Vector2(-4, -29).rotated(lean))
	var upper := key.y
	var fore := upper + key.z
	var aim_in_pose := _flip(aim - shoulder)
	if not holding_rod:
		var pointing := clampf(aim_in_pose.angle(), -1.16, 1.16) - recoil
		pointing = lerpf(pointing, -.74, reload_pose)
		var elbow_bend := lerpf(.23, 1.74, reload_pose)
		upper = pointing - PI * .5 + elbow_bend
		fore = upper - elbow_bend
		key.w = pointing
	var elbow := shoulder + _down(ARM, upper)
	var hand := elbow + _down(FOREARM, fore)
	_move_part("near_arm", shoulder, upper, delta)
	_move_part("near_forearm", elbow, fore, delta)
	_move_part("hand", hand, key.w, delta)

	weapon.visible = not holding_rod
	weapon.global_position = hand + global_position
	var to_aim := aim - weapon.global_position
	var barrel_offset := asin(5.0 * facing / maxf(to_aim.length(), 20.0))
	var aim_rotation := to_aim.angle() + barrel_offset - recoil * facing
	var reload_rotation := _flip(Vector2.RIGHT.rotated(-.74)).angle()
	weapon.rotation = lerp_angle(aim_rotation, reload_rotation, reload_pose)
	weapon.scale.y = facing
	var magazine_drop := smoothstep(.17, .34, reload_time) * (1.0 - smoothstep(.42, .60, reload_time))
	magazine.position.y = 6.0 + 7.0 * magazine_drop

	var rear_shoulder := shoulder + _flip(Vector2(8, 1))
	var rear_hand := hand + _flip(Vector2(5, 6).rotated(key.w))
	var magazine_grip := magazine.to_global(Vector2(0.0, 2.0)) - global_position
	rear_hand = rear_hand.lerp(magazine_grip, reload_pose)
	var reach := Vector2((rear_hand.x - rear_shoulder.x) * facing, rear_hand.y - rear_shoulder.y)
	var distance := clampf(reach.length(), 7.8, ARM + FOREARM - .3)
	var offset := acos(clampf((ARM * ARM + distance * distance - FOREARM * FOREARM) / (2.0 * ARM * distance), -1, 1))
	var rear_upper := reach.angle() - PI * .5 + offset
	var rear_elbow := rear_shoulder + _down(ARM, rear_upper)
	rear_hand = rear_shoulder + _flip(reach.normalized() * distance)
	var rear_fore := (rear_hand - rear_elbow).angle() if facing > 0.0 else Vector2(-(rear_hand.x - rear_elbow.x), rear_hand.y - rear_elbow.y).angle()
	_move_part("far_arm", rear_shoulder, rear_upper, delta)
	_move_part("far_forearm", rear_elbow, rear_fore - PI * .5, delta)
	_move_part("far_hand", rear_hand, key.w, delta)
	parts.far_hand.z_index = 8 if reload_pose > .3 else 1

	rod.visible = holding_rod
	rod.position = hand
	rod.rotation = key.w * facing
	rod.scale.x = .245 * facing
	tip = rod.to_global(Vector2(428, -58)) - global_position
	if cast_time >= .49 and not cast_has_line:
		cast_landing = Vector2(clampf(anchor_x + facing * 260, 24, STAGE_RIGHT + 10), 467)
		cast_has_line = true
	if cast_has_line and cast_time >= 0.0:
		var flight := clampf((cast_time - .49) / (CAST_LENGTH - .49), 0.0, 1.0)
		lure = tip.lerp(cast_landing, flight)
		lure.y -= sin(flight * PI) * 47


func _pose_leg(side: String, phase: float, hip: Vector2, travel: float, delta: float) -> void:
	var stance := lerpf(.63, .42, run_blend)
	var stride := lerpf(WALK_STRIDE, RUN_STRIDE, run_blend)
	var half_step := stance * stride * .5
	var x: float
	var height := 0.0
	var roll: float
	if phase < stance:
		var planted := phase / stance
		# Move the planted sole back at the same rate the body moves forward.
		x = half_step - phase * stride
		roll = -.24 * (1.0 - smoothstep(0.0, .25, planted))
		roll += lerpf(.38, .72, run_blend) * smoothstep(.65, 1.0, planted)
	else:
		var swing := inverse_lerp(stance, 1.0, phase)
		var recovery := pow(swing, lerpf(1.0, .72, run_blend))
		x = lerpf(-half_step, half_step, smoothstep(0.0, 1.0, swing))
		x -= (1.0 - stance) * stride * swing * (1.0 - swing) * (1.0 - 2.0 * swing)
		height = lerpf(7.5, 19.0, run_blend) * sin(PI * recovery)
		roll = lerpf(lerpf(.38, .72, run_blend), -.24, smoothstep(.12, .85, swing))
	roll *= travel * gait_weight
	var pivot := Vector2(BOOT_TOE if roll > 0.0 else BOOT_HEEL, BOOT_SOLE)
	var ankle_target := Vector2(x * travel * gait_weight + pivot.x, GROUND - hip.y - height * gait_weight)
	ankle_target -= pivot.rotated(roll)
	var min_reach := sqrt(LEG * LEG + SHIN * SHIN + 2.0 * LEG * SHIN * cos(KNEE_LIMIT))
	var reach := clampf(ankle_target.length(), min_reach, LEG + SHIN - .05)
	var offset := acos(clampf((LEG * LEG + reach * reach - SHIN * SHIN) / (2.0 * LEG * reach), -1.0, 1.0))
	var thigh := ankle_target.angle() - PI * .5 - offset
	var knee_offset := Vector2.DOWN.rotated(thigh) * LEG
	var shin := (ankle_target.normalized() * reach - knee_offset).angle() - PI * .5
	var knee := hip + _flip(knee_offset)
	_move_part(side + "_thigh", hip, thigh, delta)
	_move_part(side + "_shin", knee, shin, delta)
	_move_part(side + "_boot", knee + _down(SHIN, shin), roll, delta)


func _cast_pose() -> Vector4:
	for i in range(1, CAST_KEYS.size()):
		var later: Vector4 = CAST_KEYS[i]
		if later.x >= cast_time:
			var earlier: Vector4 = CAST_KEYS[i - 1]
			return earlier.lerp(later, smoothstep(earlier.x, later.x, cast_time))
	return CAST_KEYS.back()


func _flip(point: Vector2) -> Vector2:
	return Vector2(point.x * facing, point.y)


func _down(length: float, angle: float) -> Vector2:
	return _flip(Vector2(0, length).rotated(angle))


func mark_scratch_contact(sweep_from: Vector2, sweep_to: Vector2, radius: float, lines: int) -> bool:
	var hit := swept_body_contact(sweep_from, sweep_to, radius)
	if hit.is_empty():
		return false
	var struck: RigidBody2D = hit.body
	_apply_scratch(struck.get_node("Art/Sprite"), hit.point, (sweep_to - sweep_from).normalized(), lines)
	return true


func swept_body_contact(sweep_from: Vector2, sweep_to: Vector2, radius: float) -> Dictionary:
	var best_score := INF
	var contact := Vector2.ZERO
	var struck: RigidBody2D
	for body: RigidBody2D in parts.values():
		var collider: CollisionShape2D = body.get_node("HurtShape")
		var capsule := collider.shape as CapsuleShape2D
		var axis := Vector2(0.0, maxf(0.0, capsule.height * .5 - capsule.radius))
		var nearest := Geometry2D.get_closest_points_between_segments(sweep_from, sweep_to,
			collider.to_global(-axis), collider.to_global(axis))
		var distance := nearest[0].distance_to(nearest[1])
		if distance > capsule.radius + radius:
			continue
		var score := distance - capsule.radius - body.z_index * .18
		if score < best_score:
			best_score = score
			struck = body
			contact = nearest[1] + (nearest[0] - nearest[1]).limit_length(capsule.radius * .46)
	return {} if struck == null else {"body": struck, "point": contact}


func _apply_scratch(sprite: Sprite2D, world_point: Vector2, swipe: Vector2, lines: int) -> void:
	var atlas := sprite.texture as AtlasTexture
	var local_point := sprite.to_local(world_point) * sprite.scale
	var direction := swipe.rotated(-sprite.global_rotation)
	if direction.is_zero_approx():
		direction = Vector2.DOWN
	if sprite.flip_h:
		local_point.x = atlas.region.size.x * sprite.scale.x - local_point.x
		direction.x *= -1.0
	var marks: Array = scratch_marks.get(sprite, [])
	if marks.size() == SCRATCH_MARKS_PER_PART:
		marks.pop_front()
	marks.append({"stroke": Vector4(local_point.x, local_point.y, direction.x, direction.y), "lines": lines})
	scratch_marks[sprite] = marks
	var material := sprite.material as ShaderMaterial
	if material == null:
		material = ShaderMaterial.new()
		material.shader = SCRATCH_SHADER
		material.set_shader_parameter("atlas_origin", atlas.region.position)
		material.set_shader_parameter("sprite_scale", sprite.scale)
		sprite.material = material
	material.set_shader_parameter("contact_count", marks.size())
	var shader_marks := PackedVector4Array()
	shader_marks.resize(SCRATCH_MARKS_PER_PART)
	var cut_counts := PackedFloat32Array()
	cut_counts.resize(SCRATCH_MARKS_PER_PART)
	for i in marks.size():
		shader_marks[i] = marks[i].stroke
		cut_counts[i] = marks[i].lines
	material.set_shader_parameter("contacts", shader_marks)
	material.set_shader_parameter("cut_counts", cut_counts)


func _move_part(key: String, at: Vector2, angle: float, delta: float) -> void:
	var body: RigidBody2D = parts[key]
	var previous: Vector3 = last_pose.get(key, Vector3(at.x, at.y, angle * facing))
	body.position = at
	body.rotation = angle * facing
	var sprite: Sprite2D = body.get_node("Art/Sprite")
	sprite.flip_h = facing < 0.0
	if key.ends_with("_boot"):
		# Mirror the off-center boot around its collar, where the pant cuff ends.
		sprite.position.x = BOOT_COLLAR.x - BOOT_SIZE.x if sprite.flip_h else -BOOT_COLLAR.x
		body.get_node("HurtShape").position = _flip(BOOT_HURT_CENTER)
	last_pose[key] = Vector3(at.x, at.y, body.rotation)
	velocities[key] = ((at - Vector2(previous.x, previous.y)) / delta).limit_length(220)
	angular_velocities[key] = clampf(angle_difference(previous.z, body.rotation) / delta, -7, 7)


func _connect_bodies(a: String, b: String, clockwise: float, counterclockwise: float) -> void:
	var joint := HINGE.new()
	var bounds := Vector2(-counterclockwise, clockwise) if facing > 0 else Vector2(-clockwise, counterclockwise)
	add_child(joint)
	joint.configure(parts[a], parts[b], bounds)
	joints.append(joint)


func fall() -> void:
	if fallen:
		return
	fallen = true
	cast_time = -1
	reload_time = -1.0
	cast_has_line = false
	rod.hide()
	weapon.hide()
	_connect_bodies("hips", "torso", .48, .56)
	_connect_bodies("torso", "head", .65, .65)
	for side in ["far", "near"]:
		_connect_bodies("hips", side + "_thigh", 1.12, 1.05)
		_connect_bodies(side + "_thigh", side + "_shin", 2.30, 0.0)
		_connect_bodies(side + "_shin", side + "_boot", .5, .5)
		_connect_bodies("torso", side + "_arm", 2.58, 2.58)
		_connect_bodies(side + "_arm", side + "_forearm", 0.0, 2.64)
		_connect_bodies(side + "_forearm", "far_hand" if side == "far" else "hand", 1.67, 1.67)
	var kick := Vector2(facing * 77, -49)
	for key: String in parts:
		var body: RigidBody2D = parts[key]
		body.collision_mask = 1
		body.freeze = false
		body.sleeping = false
		body.linear_velocity = velocities[key] + kick
		body.angular_velocity = angular_velocities[key]
	queue_redraw()


func reset_pose() -> void:
	for sprite: Sprite2D in scratch_marks:
		sprite.material = null
	scratch_marks.clear()
	for joint in joints:
		remove_child(joint)
		joint.queue_free()
	joints.clear()
	for body: RigidBody2D in parts.values():
		body.freeze = true
		body.linear_velocity = Vector2.ZERO
		body.angular_velocity = 0
		body.collision_mask = 0
		body.get_node("Art").transform = Transform2D.IDENTITY
	fallen = false
	cast_time = -1.0
	cast_has_line = false
	reload_time = -1.0
	rounds_in_magazine = MAGAZINE_CAPACITY
	anchor_x = START_X
	move_speed = 0
	gait_phase = 0.0
	gait_weight = 0.0
	run_blend = 1.0
	gait_direction = 1.0
	recoil = 0.0
	last_pose.clear()
	_pose(1.0 / 60.0)
	queue_redraw()


func _draw() -> void:
	if not cast_has_line or fallen:
		return
	var points := PackedVector2Array()
	var tension := 9.0 if cast_time < 0.0 else 18.0
	for i in range(15):
		var fraction := float(i) / 14.0
		points.append(tip.lerp(lure, fraction) + Vector2(0, sin(fraction * PI) * tension))
	draw_polyline(points, Color("#e9ddbbe1"), 1)
	draw_rect(Rect2(lure - Vector2(2, 2), Vector2(4, 5)), Color("#f58155"))
