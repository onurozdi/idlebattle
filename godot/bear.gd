extends "res://deer.gd"

signal claw_hit(damage: int, sweep_from: Vector2, sweep_to: Vector2)

const BEAR_SKIN := preload("res://bear_skin.gd")
const SIGHT_RANGE := 12.0 * METRE
const BODY_SHOT_DAMAGE := 2
const HEAD_SHOT_DAMAGE := 50
const CLAW_DAMAGE := 33
const CHARGE_SPEED := 235.0
const ATTACK_DISTANCE := 84.0
const SWIPE_BEGIN := .52
const SWIPE_END := .76
const ATTACK_END := 1.34
const UPPER_SOCKET := Vector2(-1.0, 32.0)
const PAW_SOCKET := Vector2(3.0, 31.0)
const WALK_STRIDE := 51.0
const CHARGE_STRIDE := 107.0

const FRONT_PROFILE := [
	Vector4(-.34, 221, 339, 741), Vector4(0, 220, 339, 774),
	Vector4(.25, 218, 336, 792), Vector4(.49, 216, 333, 812),
	Vector4(.70, 218, 326, 829), Vector4(.86, 223, 320, 844),
	Vector4(1.0, 227, 315, 857), Vector4(1.17, 228, 308, 868),
	Vector4(1.39, 231, 305, 879), Vector4(1.61, 234, 320, 886),
	Vector4(1.83, 235, 329, 895), Vector4(2.0, 239, 330, 904),
]
const REAR_PROFILE := [
	Vector4(-.34, 61, 176, 740), Vector4(0, 60, 177, 773),
	Vector4(.25, 62, 172, 794), Vector4(.49, 64, 165, 813),
	Vector4(.70, 60, 154, 831), Vector4(.86, 57, 146, 845),
	Vector4(1.0, 55, 137, 856), Vector4(1.17, 52, 130, 868),
	Vector4(1.39, 55, 129, 879), Vector4(1.61, 56, 137, 887),
	Vector4(1.83, 63, 141, 895), Vector4(2.0, 68, 144, 904),
]

var hunter_active := true
var aggro := false
var attack_time := -1.0
var connected := false
var previous_claw := Vector2.ZERO


func _ready() -> void:
	_part("body", Vector2(-5, -9), Vector2(111, 61), 13.0, 3)
	_part("neck", Vector2(3, 0), Vector2(42, 41), 3.0, 3)
	_part("head", Vector2(10, -1), Vector2(37, 25), 2.0, 4)
	for leg in LEGS:
		var near: bool = leg.begins_with("near")
		var front: bool = leg.ends_with("front")
		var layer := 2 if near else 1
		_part(leg + "_upper", Vector2(0, 14), Vector2(20, 34), 1.8, layer, true)
		_part(leg + "_lower", Vector2(1, 14), Vector2(15, 34), 1.1, layer, true)
		var leg_skin := LEG_SKIN.new()
		leg_skin.z_index = layer
		leg_skin.configure_profile(FRONT_PROFILE if front else REAR_PROFILE, not near, BEAR_SKIN.BEAR_SCALE)
		add_child(leg_skin)
		leg_skins.append(leg_skin)
	skin = BEAR_SKIN.new()
	skin.z_index = 3
	add_child(skin)
	_make_health_meter()
	reset_pose()


func reset_pose() -> void:
	aggro = false
	hunter_active = true
	attack_time = -1.0
	connected = false
	super.reset_pose()
	facing = -1.0
	_pose()
	_update_skin()


func _shot_damage(head_hit: bool) -> int:
	return HEAD_SHOT_DAMAGE if head_hit else BODY_SHOT_DAMAGE


func _foot_socket() -> Vector2:
	return PAW_SOCKET


func _foot_roll(index: int) -> Vector2:
	if fallen:
		return Vector2.ZERO
	var phase := fposmod(step - WALK_CONTACT[index], 1.0)
	var stance := _stance()
	var swing := clampf(inverse_lerp(stance, 1.0, phase), 0.0, 1.0)
	return Vector2(sin(swing * TAU) * .31, 1.0 - smoothstep(0.0, .29, _stand()))


func advance(delta: float, hunter_x: float) -> void:
	if fallen:
		super.advance(delta, hunter_x)
		return
	flinch = maxf(0.0, flinch - delta)
	if pace:
		_hunt(delta, hunter_x)
	_pose()
	if attack_time >= 0.0:
		var claw: Vector2 = parts.near_front_lower.to_global(_flip(PAW_SOCKET))
		if hunter_active and not connected and attack_time >= SWIPE_BEGIN and attack_time <= SWIPE_END:
			# Swept distance to the character prevents missing fast paw contact between frames.
			var center := Vector2(hunter_x, FEET_Y - 58.0)
			var nearest := Geometry2D.get_closest_point_to_segment(center, previous_claw, claw)
			if Rect2(center - Vector2(19, 39), Vector2(38, 78)).has_point(nearest):
				connected = true
				claw_hit.emit(CLAW_DAMAGE, previous_claw, claw)
		previous_claw = claw


func _hunt(delta: float, hunter_x: float) -> void:
	var separation := hunter_x - lane
	var distance := absf(separation)
	if hunter_active and distance <= SIGHT_RANGE and separation * facing >= 0.0:
		aggro = true
	if attack_time >= 0.0:
		attack_time += delta
		if attack_time >= ATTACK_END:
			attack_time = -1.0
		elif attack_time >= .43 and attack_time < SWIPE_END and separation * facing > 56.0:
			lane = clampf(lane + facing * 64.0 * delta, RANGE_LEFT, RANGE_RIGHT)
		return
	var desired_speed := CHARGE_SPEED if aggro and hunter_active else 0.0
	if desired_speed > 0.0:
		facing = signf(separation) if distance > 1.0 else facing
		var run_room := maxf(0.0, distance - ATTACK_DISTANCE + 1.0)
		desired_speed = minf(desired_speed, sqrt(2.0 * BRAKING * run_room))
		if distance <= ATTACK_DISTANCE:
			speed = 0.0
			attack_time = 0.0
			connected = false
			previous_claw = parts.near_front_lower.to_global(_flip(PAW_SOCKET))
			return
	speed = move_toward(speed, desired_speed, ACCELERATION * delta)
	var next := clampf(lane + facing * speed * delta, RANGE_LEFT, RANGE_RIGHT)
	step = fposmod(step + absf(next - lane) / _stride_length(), 1.0)
	lane = next


func _stride_length() -> float:
	return lerpf(WALK_STRIDE, CHARGE_STRIDE, smoothstep(40.0, CHARGE_SPEED, speed))


func _stance() -> float:
	return lerpf(.64, .51, smoothstep(30.0, CHARGE_SPEED, speed))


func _stand() -> float:
	return smoothstep(0.0, .39, attack_time) * (1.0 - smoothstep(.86, ATTACK_END, attack_time))


func _pose() -> void:
	var running := smoothstep(0.0, CHARGE_SPEED, speed)
	var step_weight := smoothstep(0.0, 28.0, speed)
	var stand := _stand()
	var swipe := smoothstep(.44, .71, attack_time)
	var pitch := lerpf(sin(step * TAU) * .095 * running, -1.16, stand)
	var root := Vector2(lane - facing * 7.0 * stand,
		FEET_Y - lerpf(66.0, 99.0, stand) - 3.5 * running * absf(sin(step * TAU)))
	root += hit_direction * sin(PI * flinch / FLINCH_TIME) * 3.4
	health_meter.position = (root + Vector2(-43, -100 - stand * 19.0)).round()
	var chest := root + _flip(((BEAR_SKIN.SOURCE_NECK - BEAR_SKIN.SOURCE_BODY) * BEAR_SKIN.BEAR_SCALE).rotated(pitch))
	var neck_angle := pitch * .78
	var skull := chest + _flip(((BEAR_SKIN.SOURCE_HEAD - BEAR_SKIN.SOURCE_NECK) * BEAR_SKIN.BEAR_SCALE).rotated(neck_angle))
	_animate_part("body", root, pitch)
	_animate_part("neck", chest, neck_angle)
	_animate_part("head", skull, pitch * .24)
	for i in LEGS.size():
		var leg: String = LEGS[i]
		var front := leg.ends_with("front")
		var far := leg.begins_with("far")
		var mount := Vector2((37.0 if front else -47.0) + (-4.0 if far else 3.0), 12.0).rotated(pitch)
		var shoulder := root + _flip(mount)
		var cycle := fposmod(step - WALK_CONTACT[i], 1.0)
		var stride := hoof_cycle(cycle, _stance(), _stride_length(), lerpf(14.0, 25.0, running)) * step_weight
		var planted_x := (27.0 if far else 48.0) if front else (-51.0 if far else -42.0)
		var foot := Vector2(planted_x + stride.x, FEET_Y + stride.y - shoulder.y)
		var goal := foot - Vector2(mount.x, 0.0)
		if front:
			# The far paw stays bent for balance. Only the near paw tracks the strike.
			var reach := Vector2(26.0, 44.0) if far else Vector2(23.0, -33.0).lerp(Vector2(65.0, 43.0), swipe)
			goal = goal.lerp(reach, stand)
			leg_skins[i].z_index = 1 if far else (4 if stand > .34 and attack_time >= SWIPE_BEGIN else 2)
		else:
			goal.x = lerpf(goal.x, -24.0 - mount.x, stand)
		_pose_paw(leg, shoulder, goal, front)


func _pose_paw(leg: String, shoulder: Vector2, goal: Vector2, front: bool) -> void:
	var upper_length := UPPER_SOCKET.length()
	var lower_length := PAW_SOCKET.length()
	var length := clampf(goal.length(), 3.0, upper_length + lower_length - .2)
	var bend := acos(clampf((upper_length * upper_length + length * length - lower_length * lower_length) /
		(2.0 * upper_length * length), -1.0, 1.0))
	var upper_angle := goal.angle() - UPPER_SOCKET.angle() + (-bend if front else bend)
	var elbow := UPPER_SOCKET.rotated(upper_angle)
	var lower_angle := (goal.normalized() * length - elbow).angle() - PAW_SOCKET.angle()
	_animate_part(leg + "_upper", shoulder, upper_angle)
	_animate_part(leg + "_lower", shoulder + _flip(elbow), lower_angle)
