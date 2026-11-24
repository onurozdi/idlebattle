extends Node2D

signal bite_hit(damage: int)

const TEXTURE := preload("res://assets/wildlife.webp")
const HIT_MARK := preload("res://hit_mark.gd")
const TARGET_HEALTH := preload("res://target_health.gd")
const METRE := preload("res://world_units.gd").METRE
const GROUND := 378.0
const SPAWN_X := 940.0
const PATROL_HALF_WIDTH := 85.0
const ALERT_RANGE := 3.0 * METRE
const ATTACK_DISTANCE := 83.0
const BITE_BEGIN := .28
const BITE_END := .43
const RECOVERY_END := .90
const BITE_RADIUS := 8.0
const BITE_DAMAGE := 15
const BASE_SHOT_DAMAGE := 40.0
const SHOT_HIT_CHANCE := .33
const MAX_HEALTH := 100.0
const ROLL_DURATION := .55
const ART_SCALE := .24
const MOUTH := Vector2(14.0, 1.5)
const HEAD_REGION := Rect2(885, 754, 73, 45)
# Source columns with the upper and lower edges of the body in the wildlife atlas.
const PROFILE := [
	Vector3(552, 804, 829), Vector3(564, 793, 820), Vector3(576, 786, 809),
	Vector3(590, 781, 806), Vector3(604, 779, 808), Vector3(618, 780, 816),
	Vector3(632, 784, 832), Vector3(648, 797, 837), Vector3(664, 801, 840),
	Vector3(680, 796, 840), Vector3(696, 774, 836), Vector3(712, 762, 826),
	Vector3(728, 757, 811), Vector3(744, 755, 806), Vector3(760, 755, 808),
	Vector3(776, 760, 819), Vector3(792, 768, 829), Vector3(808, 783, 835),
	Vector3(824, 791, 837), Vector3(840, 793, 837), Vector3(856, 787, 834),
	Vector3(872, 771, 824), Vector3(888, 760, 803), Vector3(898, 756, 796),
]

var health := MAX_HEALTH
var fallen := false
var hunter_active := true
var attack_time := -1.0
var lane := SPAWN_X
var facing := -1.0
var speed := 0.0
var slither_phase := 0.0
var patrol_direction := -1.0
var bite_connected := false
var bite_from := Vector2.ZERO
var bite_to := Vector2.ZERO
var roll_time := 0.0
var health_meter: ProgressBar
var hit_body: StaticBody2D
var skin: Polygon2D
var head: Node2D
var jaw: Node2D
var sections: Array[CollisionShape2D] = []
var mark_anchors: Array[Node2D] = []
var marks: Array[Node2D] = []
var spine := PackedVector2Array()
var death_spine := PackedVector2Array()
var death_head_angle := 0.0


func _ready() -> void:
	skin = Polygon2D.new()
	skin.texture = TEXTURE
	var quads: Array[PackedInt32Array] = []
	for i in PROFILE.size() - 1:
		quads.append(PackedInt32Array([2 * i, 2 * i + 1, 2 * i + 3, 2 * i + 2]))
	skin.polygons = quads
	add_child(skin)
	_make_head()
	hit_body = StaticBody2D.new()
	hit_body.collision_layer = 4
	hit_body.collision_mask = 0
	hit_body.set_meta("target", self)
	hit_body.set_meta("projectile_hit_chance", SHOT_HIT_CHANCE)
	add_child(hit_body)
	for i in PROFILE.size():
		var section := CollisionShape2D.new()
		section.shape = CapsuleShape2D.new()
		hit_body.add_child(section)
		sections.append(section)
		var anchor := Node2D.new()
		add_child(anchor)
		mark_anchors.append(anchor)
	health_meter = TARGET_HEALTH.make_meter(MAX_HEALTH, 58.0)
	add_child(health_meter)
	reset_pose()


func _make_head() -> void:
	head = Node2D.new()
	add_child(head)
	jaw = Node2D.new()
	jaw.position = Vector2(4.8, 1.2)
	head.add_child(jaw)
	for detail in [
		[PackedVector2Array([Vector2(-3, -1), Vector2(12, -2), Vector2(10, 1.4), Vector2(3, 3), Vector2(-2, 2)]), Color("#292a1c")],
		[PackedVector2Array([Vector2(-2, 0), Vector2(10, -1), Vector2(8, 1.3), Vector2(2, 2)]), Color("#c5b186")],
		[PackedVector2Array([Vector2(6, -2), Vector2(8, -2), Vector2(7.6, 1)]), Color("#ebd8aa")],
	]:
		var shape := Polygon2D.new()
		shape.polygon = detail[0]
		shape.color = detail[1]
		jaw.add_child(shape)
	var image := Sprite2D.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = TEXTURE
	atlas.region = HEAD_REGION
	atlas.filter_clip = true
	image.texture = atlas
	image.centered = false
	image.position = Vector2(-4.0, -5.0)
	image.scale = Vector2.ONE * ART_SCALE
	head.add_child(image)


func reset_pose() -> void:
	for mark in marks:
		mark.queue_free()
	marks.clear()
	health = MAX_HEALTH
	health_meter.value = health
	health_meter.hide()
	fallen = false
	hunter_active = true
	attack_time = -1.0
	bite_connected = false
	lane = SPAWN_X
	facing = -1.0
	patrol_direction = facing
	speed = 0.0
	slither_phase = 0.0
	roll_time = 0.0
	_pose()
	bite_to = head.to_global(MOUTH)
	bite_from = bite_to


func advance(delta: float, hunter_x: float) -> void:
	if fallen:
		if roll_time < ROLL_DURATION:
			roll_time = minf(roll_time + delta, ROLL_DURATION)
			_pose()
		return
	if attack_time >= 0.0:
		attack_time += delta
		if attack_time >= RECOVERY_END:
			attack_time = -1.0
	else:
		_crawl(delta, hunter_x)
	_pose()
	bite_from = bite_to
	bite_to = head.to_global(MOUTH)


func _crawl(delta: float, hunter_x: float) -> void:
	var separation := hunter_x - lane
	if lane <= SPAWN_X - PATROL_HALF_WIDTH:
		patrol_direction = 1.0
	elif lane >= SPAWN_X + PATROL_HALF_WIDTH:
		patrol_direction = -1.0
	var approaching := hunter_active and absf(separation) <= ALERT_RANGE
	var direction := signf(separation) if approaching and not is_zero_approx(separation) else patrol_direction
	if approaching and absf(separation) <= ATTACK_DISTANCE:
		facing = direction
		speed = 0.0
		attack_time = 0.0
		bite_connected = false
		return
	var target_speed := 73.0 if approaching else 28.0
	speed = move_toward(speed, direction * target_speed, delta * 230.0)
	if not is_zero_approx(speed):
		facing = signf(speed)
	lane = clampf(lane + speed * delta, 86.0, 1350.0)
	slither_phase = fposmod(slither_phase + (absf(speed) * .12 + .6) * delta, TAU)


func resolve_bite(hunter: Node2D) -> void:
	if fallen or not hunter_active or bite_connected or attack_time < BITE_BEGIN or attack_time > BITE_END:
		return
	if not hunter.swept_body_contact(bite_from, bite_to, BITE_RADIUS).is_empty():
		bite_connected = true
		bite_hit.emit(BITE_DAMAGE)


func receive_shot(_body: Node2D, point: Vector2, direction: Vector2, damage_multiplier := 1.0) -> bool:
	var anchor := mark_anchors.back() as Node2D
	var nearest := INF
	for candidate in mark_anchors:
		var distance := candidate.global_position.distance_squared_to(point)
		if distance < nearest:
			nearest = distance
			anchor = candidate
	if marks.size() >= 12:
		marks.pop_front().queue_free()
	var mark := HIT_MARK.attach(anchor, point, direction)
	mark.scale = Vector2.ONE * .65
	marks.append(mark)
	if fallen:
		return false
	health = maxf(0.0, health - BASE_SHOT_DAMAGE * damage_multiplier)
	if is_zero_approx(health):
		health = 0.0
	health_meter.value = health
	health_meter.visible = health > 0.0
	if is_zero_approx(health):
		fallen = true
		attack_time = -1.0
		speed = 0.0
		death_spine = spine.duplicate()
		death_head_angle = head.rotation
	return true


func _pose() -> void:
	var cock := smoothstep(0.0, .21, attack_time) * (1.0 - smoothstep(.21, .35, attack_time))
	var thrust := smoothstep(.21, .35, attack_time) * (1.0 - smoothstep(.43, .82, attack_time))
	var turn := smoothstep(0.0, ROLL_DURATION, roll_time)
	var belly := smoothstep(.42, .94, turn)
	var squash := maxf(.44, absf(cos(turn * PI)))
	var points := PackedVector2Array()
	var uv := PackedVector2Array()
	spine.resize(PROFILE.size())
	for i in PROFILE.size():
		var source: Vector3 = PROFILE[i]
		var progress := float(i) / (PROFILE.size() - 1)
		var forward_weight := smoothstep(.27, 1.0, progress)
		var coil := .5 + .5 * sin(progress * TAU * 1.8 + slither_phase)
		var half_height := (source.z - source.y) * ART_SCALE * .5
		var x := (source.x - 739.0) * ART_SCALE + sin(coil * PI) * 3.0 * (1.0 - progress)
		x += forward_weight * (36.0 * thrust - 13.0 * cock)
		var lift := 10.0 * coil * (1.0 - .68 * thrust) + forward_weight * (14.0 * cock + 19.0 * thrust)
		var center := Vector2(lane + facing * x, GROUND - half_height - lift)
		if fallen:
			var settled_lift := pow(sin(progress * PI), 2.0) * (.7 + 2.3 * coil)
			var settled := Vector2(lane + facing * x, GROUND - half_height * squash - settled_lift)
			center = death_spine[i].lerp(settled, turn)
		spine[i] = center
		points.append(center - Vector2(0, half_height * squash))
		points.append(center + Vector2(0, half_height * squash))
		uv.append(Vector2(source.x, lerpf(source.y, lerpf(source.y, source.z, .53), belly)))
		uv.append(Vector2(source.x, source.z))
	skin.polygon = points
	skin.uv = uv
	var neck := spine[spine.size() - 3]
	var head_base := spine[spine.size() - 1]
	head.position = head_base
	var pitch := atan2(head_base.y - neck.y, absf(head_base.x - neck.x)) * .6 - .12 * cock
	head.rotation = lerpf(death_head_angle, 0.0, turn) if fallen else clampf(pitch, -.43, .36) * facing
	head.scale = Vector2(facing, squash if turn < .5 else -squash)
	jaw.visible = not fallen and thrust > .08
	jaw.rotation = thrust * .54
	_update_hit_sections(squash)
	health_meter.position = head_base.lerp(Vector2(lane, head_base.y), .8) + Vector2(-29, -48)
	queue_redraw()


func _update_hit_sections(squash: float) -> void:
	for i in sections.size() - 1:
		var from := spine[i]
		var to := spine[i + 1]
		var profile: Vector3 = PROFILE[i]
		var radius := maxf(1.2, (profile.z - profile.y) * ART_SCALE * .42 * squash)
		_set_hit_section(i, from, to, radius)
	var mouth := to_local(head.to_global(MOUTH))
	_set_hit_section(sections.size() - 1, head.position, mouth, 3.6 * squash)


func _set_hit_section(index: int, from: Vector2, to: Vector2, radius: float) -> void:
	var section := sections[index]
	section.position = from.lerp(to, .5)
	section.rotation = (to - from).angle() - PI * .5
	var shape := section.shape as CapsuleShape2D
	shape.height = from.distance_to(to) + radius * 2.0
	shape.radius = radius
	mark_anchors[index].position = section.position
	mark_anchors[index].rotation = section.rotation


func _draw() -> void:
	if spine.is_empty():
		return
	draw_line(Vector2(spine[0].x, GROUND + 1.0), Vector2(spine[spine.size() - 1].x, GROUND + 1.0), Color("#1c171447"), 3.0)
