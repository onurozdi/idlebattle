extends "res://deer.gd"

signal ram_hit(damage: int)

const BOAR_SKIN := preload("res://boar_skin.gd")
const SIGHT_RANGE := 10.0 * METRE
const BODY_SHOT_DAMAGE := 2.5
const HEAD_SHOT_DAMAGE := 40.0
const RAM_DAMAGE := 28
const CHARGE_SPEED := 212.0
const RAM_SPEED := 230.0
const ATTACK_DISTANCE := 81.0
const WINDUP_END := .17
const RAM_BEGIN := .19
const RAM_END := .40
const RECOVERY_END := .86
const RAM_RADIUS := 13.0
const NOSE := Vector2(21, 12)
const BOAR_HOOF := Vector2(2, 16)
const WALK_STRIDE := 35.0
const RUN_STRIDE := 77.0
const GALLOP_CONTACT := [0.0, .35, .12, .49]

const FRONT_PROFILE := [
	Vector4(-.34, 1258, 1321, 328), Vector4(0, 1261, 1325, 346),
	Vector4(.25, 1265, 1326, 357), Vector4(.49, 1269, 1323, 368),
	Vector4(.70, 1272, 1320, 377), Vector4(.86, 1274, 1319, 385),
	Vector4(1.0, 1278, 1318, 394), Vector4(1.17, 1282, 1316, 402),
	Vector4(1.39, 1285, 1314, 412), Vector4(1.61, 1284, 1314, 422),
	Vector4(1.83, 1285, 1320, 435), Vector4(2.0, 1292, 1325, 445),
]
const REAR_PROFILE := [
	Vector4(-.34, 1131, 1181, 328), Vector4(0, 1132, 1184, 346),
	Vector4(.25, 1130, 1179, 356), Vector4(.49, 1122, 1175, 365),
	Vector4(.70, 1117, 1172, 374), Vector4(.86, 1116, 1154, 382),
	Vector4(1.0, 1117, 1149, 392), Vector4(1.17, 1116, 1146, 402),
	Vector4(1.39, 1114, 1144, 413), Vector4(1.61, 1112, 1144, 422),
	Vector4(1.83, 1114, 1148, 433), Vector4(2.0, 1121, 1152, 445),
]

var hunter_active := true
var aggro := false
var attack_time := -1.0
var connected := false
var ram_from := Vector2.ZERO
var ram_to := Vector2.ZERO


func _ready() -> void:
	_part("body", Vector2(-3, -3), Vector2(66, 43), 8.8, 3)
	_part("neck", Vector2(2, 0), Vector2(33, 36), 2.3, 3)
	_part("head", Vector2(8, 5), Vector2(31, 25), 1.9, 4)
	for leg in LEGS:
		var near: bool = leg.begins_with("near")
		var front: bool = leg.ends_with("front")
		var layer := 2 if near else 1
		_part(leg + "_upper", Vector2(0, 6), Vector2(12, 18), 1.1, layer, true)
		_part(leg + "_lower", Vector2(1, 8), Vector2(10, 20), .7, layer, true)
		var leg_skin := LEG_SKIN.new()
		leg_skin.z_index = layer
		leg_skin.configure_profile(FRONT_PROFILE if front else REAR_PROFILE, not near, BOAR_SKIN.BOAR_SCALE)
		add_child(leg_skin)
		leg_skins.append(leg_skin)
	skin = BOAR_SKIN.new()
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
	patrol_direction = facing
	_pose()
	_update_skin()
	ram_to = parts.head.to_global(_flip(NOSE))
	ram_from = ram_to


func _shot_damage(head_hit: bool) -> float:
	return HEAD_SHOT_DAMAGE if head_hit else BODY_SHOT_DAMAGE


func receive_shot(body: RigidBody2D, world_point: Vector2, direction: Vector2, damage_multiplier := 1.0) -> bool:
	var hit := super.receive_shot(body, world_point, direction, damage_multiplier)
	if hit and not fallen:
		aggro = true
	return hit


func advance(delta: float, hunter_x: float) -> void:
	super.advance(delta, hunter_x)
	if not fallen:
		ram_from = ram_to
		ram_to = parts.head.to_global(_flip(NOSE))


func resolve_ram(hunter: Node2D) -> void:
	if fallen or not hunter_active or connected or attack_time < RAM_BEGIN or attack_time > RAM_END:
		return
	if not hunter.swept_body_contact(ram_from, ram_to, RAM_RADIUS).is_empty():
		connected = true
		ram_hit.emit(RAM_DAMAGE)


func _move(delta: float, hunter_x: float) -> void:
	var separation := hunter_x - lane
	var distance := absf(separation)
	if hunter_active and distance <= SIGHT_RANGE:
		aggro = true
	if attack_time >= 0.0:
		attack_time += delta
		var shove := smoothstep(WINDUP_END, .22, attack_time) * (1.0 - smoothstep(.30, .48, attack_time))
		speed = RAM_SPEED * shove
		_travel(delta)
		if attack_time >= RECOVERY_END:
			attack_time = -1.0
		return
	if lane <= PATROL_LEFT:
		patrol_direction = 1.0
	elif lane >= PATROL_RIGHT:
		patrol_direction = -1.0
	var direction := patrol_direction
	var target_speed := 44.0
	if hunter_active and aggro:
		direction = signf(separation) if distance > .1 else facing
		if distance <= ATTACK_DISTANCE:
			facing = direction
			speed = 0.0
			attack_time = 0.0
			connected = false
			return
		var room := distance - ATTACK_DISTANCE + 8.0
		target_speed = minf(CHARGE_SPEED, sqrt(2.0 * BRAKING * room))
	if direction != facing:
		target_speed = 0.0
	speed = move_toward(speed, target_speed, (ACCELERATION if speed < target_speed else BRAKING) * delta)
	if speed < 1.0:
		facing = direction
	_travel(delta)


func _travel(delta: float) -> void:
	var next := clampf(lane + facing * speed * delta, RANGE_LEFT, RANGE_RIGHT)
	step = fposmod(step + absf(next - lane) / lerpf(WALK_STRIDE, RUN_STRIDE, _gallop()), 1.0)
	lane = next


func _gallop() -> float:
	return smoothstep(62.0, CHARGE_SPEED, speed)


func _foot_socket() -> Vector2:
	return BOAR_HOOF


func _foot_roll(index: int) -> Vector2:
	if fallen:
		return Vector2.ZERO
	var run := _gallop()
	var phase := fposmod(step - lerpf(WALK_CONTACT[index], GALLOP_CONTACT[index], run), 1.0)
	var swing := smoothstep(lerpf(.64, .43, run), 1.0, phase)
	return Vector2(sin(swing * TAU) * .32, 1.0)


func _pose() -> void:
	var run := _gallop()
	var movement := smoothstep(0.0, 35.0, speed)
	var brace := smoothstep(0.0, WINDUP_END, attack_time) * (1.0 - smoothstep(RAM_END, .59, attack_time))
	var pitch := sin(step * TAU) * lerpf(.035, .10, run) * movement + .10 * brace
	var bob := (1.0 - cos(step * TAU * 2.0)) * lerpf(.7, 1.6, run) * movement
	var root := Vector2(lane, FEET_Y - lerpf(39.5, 36.0, movement) - bob + 1.8 * brace)
	root += hit_direction * sin(PI * flinch / FLINCH_TIME) * 2.8
	var chest := root + _flip(((BOAR_SKIN.SOURCE_NECK - BOAR_SKIN.SOURCE_BODY) * BOAR_SKIN.BOAR_SCALE).rotated(pitch))
	var neck_angle := pitch * .65 + .13 * brace
	var skull := chest + _flip(((BOAR_SKIN.SOURCE_HEAD - BOAR_SKIN.SOURCE_NECK) * BOAR_SKIN.BOAR_SCALE).rotated(neck_angle))
	_animate_part("body", root, pitch)
	_animate_part("neck", chest, neck_angle)
	_animate_part("head", skull, neck_angle * .7)
	health_meter.position = (root + Vector2(-43, -57)).round()
	for index in LEGS.size():
		var leg: String = LEGS[index]
		var front := leg.ends_with("front")
		var far := leg.begins_with("far")
		var mount := Vector2((15.0 if front else -29.0) + (5.0 if far else -2.0), 10.0)
		var hip_offset := mount.rotated(pitch)
		var hip := root + _flip(hip_offset)
		var phase := fposmod(step - lerpf(WALK_CONTACT[index], GALLOP_CONTACT[index], run), 1.0)
		var stride := hoof_cycle(phase, lerpf(.64, .43, run), lerpf(WALK_STRIDE, RUN_STRIDE, run), lerpf(6.0, 16.5, run)) * movement
		var foot := Vector2(mount.x + stride.x - hip_offset.x, FEET_Y + stride.y - hip.y)
		var knee_socket := Vector2(-1.0 if front else -6.0, 15.0)
		_pose_hoof(leg, hip, foot, knee_socket, front)
