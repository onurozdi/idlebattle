extends Node2D

const CHARACTER := preload("res://character.gd")
const DEER := preload("res://deer.gd")
const BEAR := preload("res://bear.gd")
const SHOT_RANGE := preload("res://shot_range.gd")
const LAKE := preload("res://assets/lake.webp")
const DECK_Y := 378.0
const HITS_PER_LEVEL := 4
const STAGE_WIDTH := 1440.0
const VIEW_ZOOM := .85
const HALF_VIEW := 480.0 / VIEW_ZOOM

var actor: Node2D
var animal: Node2D
var shot_range: Node2D
var camera: Camera2D
var target_picker: OptionButton
var player_health_label: Label
var bear_selected := false
var player_health := 100
var mouse_aim := false
var pad_buttons: Dictionary = {}
var aim_point := Vector2(650, 315)
var fire_pending := false
var shot_cooldown := 0.0
var deck_blocks := [
	Rect2(0, DECK_Y, STAGE_WIDTH, 162),
	Rect2(-20, 205, 20, 260),
	Rect2(STAGE_WIDTH, 205, 20, 260),
]
var status: Label
var skill_status: Label
var training_hits := 0


func _ready() -> void:
	for rect: Rect2 in deck_blocks:
		var platform := StaticBody2D.new()
		var collider := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		collider.shape = shape
		platform.position = rect.get_center()
		platform.add_child(collider)
		add_child(platform)

	actor = CHARACTER.new()
	add_child(actor)
	camera = Camera2D.new()
	camera.zoom = Vector2.ONE * VIEW_ZOOM
	camera.position = Vector2(HALF_VIEW, 270.0)
	add_child(camera)
	shot_range = SHOT_RANGE.new()
	shot_range.z_index = 15
	add_child(shot_range)
	shot_range.live_target_hit.connect(_train_shooting)
	_make_controls()
	_select_target(0)
	if "--self-test" in OS.get_cmdline_user_args():
		_self_test.call_deferred()


func _physics_process(delta: float) -> void:
	if mouse_aim:
		aim_point = get_global_mouse_position()
	var movement := float(Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D))
	movement -= float(Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A))
	for pad: int in Input.get_connected_joypads():
		var axis := Input.get_joy_axis(pad, JOY_AXIS_LEFT_X)
		if absf(axis) > .22:
			movement = axis
		var look := Vector2(Input.get_joy_axis(pad, JOY_AXIS_RIGHT_X), Input.get_joy_axis(pad, JOY_AXIS_RIGHT_Y))
		if look.length() > .26:
			mouse_aim = false
			aim_point = actor.parts.torso.position + look.normalized() * 340
		for control in [JOY_BUTTON_X, JOY_BUTTON_B, JOY_BUTTON_Y]:
			var key := Vector2i(pad, control)
			var down := Input.is_joy_button_pressed(pad, control)
			if down and not pad_buttons.get(key, false):
				_command({JOY_BUTTON_X: "cast", JOY_BUTTON_B: "fall", JOY_BUTTON_Y: "reset"}[control])
			pad_buttons[key] = down
		var trigger := Vector2i(pad, -1)
		var firing := Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT) > .45
		if firing and not pad_buttons.get(trigger, false):
			_command("fire")
		pad_buttons[trigger] = firing
	actor.aim = aim_point
	_advance_combatants(delta, movement)
	camera.position.x = move_toward(camera.position.x,
		clampf(actor.anchor_x + 180.0, HALF_VIEW, STAGE_WIDTH - HALF_VIEW), delta * 335.0)
	shot_cooldown = maxf(0.0, shot_cooldown - delta)
	if fire_pending:
		fire_pending = false
		if not actor.fallen and actor.cast_time < 0.0 and shot_cooldown <= 0.0:
			_fire()
	shot_range.advance(delta)
	if actor.fallen:
		status.text = "Player down" if player_health == 0 else "Ragdoll"
	elif animal.fallen:
		status.text = "Bear down" if bear_selected else "Deer down"
	elif bear_selected and animal.aggro:
		status.text = "Claw swipe" if animal.attack_time >= 0.0 else "Charging"
	else:
		status.text = "Casting" if actor.cast_time >= 0.0 else "Aim"
	queue_redraw()


func _advance_combatants(delta: float, movement: float) -> void:
	var left := CHARACTER.STAGE_LEFT
	var right := CHARACTER.STAGE_RIGHT
	if bear_selected:
		var approach_side := -1.0 if actor.anchor_x < animal.lane else 1.0
		animal.hunter_active = not actor.fallen
		animal.advance(delta, actor.anchor_x)
		if not animal.fallen:
			var stop_x := clampf(animal.player_stop_x(approach_side), left, right)
			if approach_side < 0.0:
				right = minf(right, stop_x)
			else:
				left = maxf(left, stop_x)
	actor.advance(delta, movement, left, right)
	if bear_selected:
		animal.resolve_claw_hit(actor)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_aim = true
		aim_point = get_global_mouse_position()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		mouse_aim = true
		aim_point = get_global_mouse_position()
		_command("fire")
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_E: _command("cast")
			KEY_F: _command("fall")
			KEY_R: _command("reset")
			KEY_SPACE: _command("fire")
			KEY_1: _select_target(0)
			KEY_2: _select_target(1)


func _command(command: String) -> void:
	match command:
		"cast": actor.cast()
		"fall": actor.fall()
		"fire":
			actor.cast_has_line = false
			fire_pending = true
		"reset":
			actor.reset_pose()
			animal.reset_pose()
			camera.position.x = HALF_VIEW
			player_health = 100
			_update_player_health()
			mouse_aim = false
			aim_point = animal.parts.body.global_position
			shot_range.clear()
			fire_pending = false
			shot_cooldown = 0.0


func _select_target(index: int) -> void:
	if is_instance_valid(animal):
		remove_child(animal)
		animal.queue_free()
	bear_selected = index == 1
	target_picker.select(index)
	animal = BEAR.new() if bear_selected else DEER.new()
	add_child(animal)
	if bear_selected:
		animal.claw_hit.connect(_take_claw_damage)
	_command("reset")


func _take_claw_damage(damage: int) -> void:
	if actor.fallen:
		return
	player_health = maxi(0, player_health - damage)
	_update_player_health()
	if player_health == 0:
		actor.fall()


func _update_player_health() -> void:
	player_health_label.text = "Health %d%%" % player_health
	player_health_label.visible = bear_selected


func _fire() -> void:
	var gun: Node2D = actor.weapon
	var muzzle: Node2D = actor.muzzle
	var barrel := Vector2.RIGHT.rotated(gun.global_rotation)
	var direction := SHOT_RANGE.spread_direction(barrel, _shooting_level(), randf_range(-1.0, 1.0))
	shot_range.shoot(muzzle.global_position, direction)
	actor.recoil = .16
	shot_cooldown = .24


func _shooting_level() -> int:
	return 1 + floori(float(training_hits) / HITS_PER_LEVEL)


func _train_shooting() -> void:
	if _shooting_level() < SHOT_RANGE.MAX_SKILL:
		training_hits += 1
		_update_skill_status()


func _update_skill_status() -> void:
	var level := _shooting_level()
	skill_status.text = "Shooting Lv. %s" % level
	if level < SHOT_RANGE.MAX_SKILL:
		skill_status.text += "  %s/%s" % [training_hits % HITS_PER_LEVEL, HITS_PER_LEVEL]


func _make_controls() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bar := PanelContainer.new()
	bar.position = Vector2(22, 19)
	bar.custom_minimum_size.x = 916
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("#092034ed")
	panel.border_color = Color("#ad8250")
	panel.set_border_width_all(1)
	panel.content_margin_left = 14
	panel.content_margin_right = 14
	panel.content_margin_top = 8
	panel.content_margin_bottom = 8
	bar.add_theme_stylebox_override("panel", panel)
	layer.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	var title := Label.new()
	title.text = "Soundings"
	title.add_theme_color_override("font_color", Color("#ffd698"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	target_picker = OptionButton.new()
	target_picker.add_item("Deer · 1", 0)
	target_picker.add_item("Bear · 2", 1)
	target_picker.focus_mode = Control.FOCUS_NONE
	target_picker.item_selected.connect(_select_target)
	row.add_child(target_picker)
	status = Label.new()
	status.custom_minimum_size.x = 80
	row.add_child(status)
	skill_status = Label.new()
	skill_status.custom_minimum_size.x = 109
	row.add_child(skill_status)
	_update_skill_status()
	player_health_label = Label.new()
	player_health_label.position = Vector2(35, 69)
	player_health_label.add_theme_color_override("font_color", Color("#ffe3b9"))
	player_health_label.add_theme_color_override("font_shadow_color", Color("#10141b"))
	player_health_label.add_theme_constant_override("shadow_offset_x", 1)
	player_health_label.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(player_health_label)
	for option in [["Shoot  Space / RT", "fire"], ["Cast  E / X", "cast"], ["Fall  F / B", "fall"], ["Reset  R / Y", "reset"]]:
		var button := Button.new()
		button.text = option[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_command.bind(option[1]))
		row.add_child(button)


func _draw() -> void:
	draw_texture_rect(LAKE, Rect2(0, -51, STAGE_WIDTH, 642), false)
	var deck: Rect2 = deck_blocks[0]
	for x in range(18, int(STAGE_WIDTH), 92):
		draw_rect(Rect2(x, DECK_Y, 10, 76), Color("#4b3429"))
		draw_rect(Rect2(x + 2, DECK_Y, 3, 75), Color("#8e6242"))
	draw_rect(Rect2(deck.position, Vector2(deck.size.x, 24)), Color("#4e352a"))
	draw_rect(Rect2(deck.position, Vector2(deck.size.x, 10)), Color("#b8814f"))
	draw_line(deck.position, deck.position + Vector2(deck.size.x, 0), Color("#eac78b"), 2)
	for x in range(11, int(STAGE_WIDTH) - 2, 25):
		draw_line(Vector2(x, DECK_Y + 2), Vector2(x, DECK_Y + 9), Color("#6e492f"))
	if actor != null and not actor.fallen and actor.weapon.visible:
		var at := aim_point.round()
		var color := Color("#f1dab1")
		for axis in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
			draw_line(at + axis * 5, at + axis * 9, Color("#152129"), 3)
			draw_line(at + axis * 5, at + axis * 9, color, 1)


func _self_test() -> void:
	var deer := animal
	var ticks := Engine.physics_ticks_per_second / 60
	actor.cast()
	for step in 20 * ticks:
		await get_tree().physics_frame
	var hand: RigidBody2D = actor.parts.hand
	var grip: Node2D = actor.rod
	var before := hand.position
	if before.y > DECK_Y - 85.0 or grip.position.distance_to(before) > 1.0:
		push_error("Cast failed to raise the hand and keep the rod anchored.")
		get_tree().quit(1)
		return
	actor.fall()
	if hand.position.distance_to(before) > 1.0 or actor.joints.size() != actor.parts.size() - 1:
		push_error("Ragdoll did not inherit the current animation pose.")
		get_tree().quit(1)
		return
	for step in 205 * ticks:
		await get_tree().physics_frame
	var torso: RigidBody2D = actor.parts.torso
	if torso.position.y < DECK_Y - 32.0 or torso.position.y > DECK_Y + 4.0:
		push_error("Ragdoll did not settle on the deck: %s, %s" % [torso.position, torso.linear_velocity])
		get_tree().quit(1)
		return
	actor.reset_pose()
	if actor.fallen or not torso.freeze or not actor.joints.is_empty():
		push_error("Reset failed to restore animation.")
		get_tree().quit(1)
		return
	deer.pace = false
	deer.reset_pose()
	if deer.health_meter.visible:
		push_error("An unharmed deer showed health.")
		get_tree().quit(1)
		return
	for count in range(1, 11):
		var target: Vector2 = deer.parts.body.global_position
		shot_range.shoot(target - Vector2(159, 0), Vector2.RIGHT)
		if deer.fallen or shot_range.rounds.size() != 1:
			push_error("The shot or the health threshold skipped projectile flight.")
			get_tree().quit(1)
			return
		for tick in 24 * ticks:
			await get_tree().physics_frame
		if deer.health != 100 - count * 10 or deer.health_meter.visible != (count < 10) or deer.fallen != (count == 10):
			push_error("Incorrect body damage or health meter after hit %s." % count)
			get_tree().quit(1)
			return
	if deer.marks.size() != 10 or deer.joints.size() != deer.parts.size() - 1 or _shooting_level() != 3:
		push_error("Missing hit marks, ragdoll links or shooting progression.")
		get_tree().quit(1)
		return
	var mark: Node2D = deer.marks[0]
	var original_offset := mark.position
	var original_world := mark.global_position
	for frame in 115:
		await get_tree().physics_frame
		for joint in deer.joints:
			joint.sync_art()
			var drawn_angle := angle_difference(joint.parent_art.global_rotation, joint.child_art.global_rotation)
			if drawn_angle < joint.lower - .001 or drawn_angle > joint.upper + .001:
				push_error("A rendered ragdoll hinge exceeded its working arc.")
				get_tree().quit(1)
				return
			if joint.child_art.global_position.distance_to(joint.parent_art.to_global(joint.parent_socket)) > .01:
				push_error("A rendered joint separated during the fall.")
				get_tree().quit(1)
				return
	if mark.position != original_offset or mark.global_position.distance_to(original_world) < 3.0:
		push_error("The entrance mark did not follow the part as the animal fell.")
		get_tree().quit(1)
		return
	for part: RigidBody2D in deer.parts.values():
		if part.position.y > DECK_Y + 9.0:
			push_error("An animal limb sank through the deck: %s %s" % [part.name, part.position])
			get_tree().quit(1)
			return
	_command("reset")
	if deer.fallen or deer.health != 100 or not deer.marks.is_empty() or not deer.joints.is_empty() or _shooting_level() != 3:
		push_error("Reset did not clean up the animal ragdoll.")
		get_tree().quit(1)
		return
	deer.facing = -1.0
	for tick in 2 * ticks:
		await get_tree().physics_frame
	var head: Node2D = deer.parts.head.get_node("HurtShape")
	shot_range.shoot(head.global_position - Vector2(145, 0), Vector2.RIGHT)
	for tick in 19 * ticks:
		await get_tree().physics_frame
	if not deer.fallen or deer.health != 0 or deer.marks.size() != 1:
		push_error("One head hit on the mirrored deer must be lethal.")
		get_tree().quit(1)
		return
	_command("reset")
	shot_range.shoot(Vector2(470, 345), Vector2.DOWN)
	for tick in 5 * ticks:
		await get_tree().physics_frame
	if shot_range.hits.is_empty() or shot_range.hits[0].target or deer.fallen:
		push_error("A projectile hitting the deck must stop without damaging the deer.")
		get_tree().quit(1)
		return
	for roll in [-1.0, 1.0]:
		var novice := SHOT_RANGE.spread_direction(Vector2.RIGHT, 1, roll)
		var expert := SHOT_RANGE.spread_direction(Vector2.RIGHT, 5, roll)
		if signf(novice.angle()) != roll or signf(expert.angle()) != roll or absf(expert.angle()) >= absf(novice.angle()):
			push_error("Shooting spread must narrow with training in both directions.")
			get_tree().quit(1)
			return
	deer.pace = true
	for tick in 18 * ticks:
		await get_tree().physics_frame
	var death_origin: Vector2 = deer.parts.body.global_position
	deer.receive_shot(deer.parts.head, deer.parts.head.global_position, Vector2.RIGHT)
	for part: RigidBody2D in deer.parts.values():
		if part.linear_velocity != Vector2.ZERO or not is_zero_approx(part.angular_velocity):
			push_error("The deer inherited movement or received an impulse on death.")
			get_tree().quit(1)
			return
	for frame in 94:
		await get_tree().process_frame
		if absf(deer.parts.body.global_position.x - death_origin.x) > 1.1:
			push_error("The ragdoll slid away from the spot where the deer died.")
			get_tree().quit(1)
			return
	if deer.parts.body.global_position.y - death_origin.y < 27.0:
		push_error("The deer did not collapse under gravity.")
		get_tree().quit(1)
		return
	var body: RigidBody2D = deer.parts.body
	var velocity := body.linear_velocity
	var spin := body.angular_velocity
	deer.receive_shot(body, body.global_position, Vector2.LEFT)
	if not body.linear_velocity.is_equal_approx(velocity) or not is_equal_approx(body.angular_velocity, spin):
		push_error("An impact moved the corpse.")
		get_tree().quit(1)
		return
	var oldest: Node2D = deer.marks[0]
	while deer.marks.size() < DEER.MAX_MARKS:
		deer.receive_shot(body, body.global_position, Vector2.RIGHT)
	if not deer.marks.has(oldest) or deer.marks.size() != 32:
		push_error("The first entry mark disappeared before the 32-mark limit.")
		get_tree().quit(1)
		return
	deer.receive_shot(body, body.global_position, Vector2.RIGHT)
	if deer.marks.has(oldest) or deer.marks.size() != 32:
		push_error("Only the oldest entry mark should be dropped when the limit is exceeded.")
		get_tree().quit(1)
		return
	if not _check_deer_leg_skins(deer):
		push_error("A folded leg has a break at the joint.")
		get_tree().quit(1)
		return
	var gait_error := _check_deer_gait(deer)
	if not gait_error.is_empty():
		push_error(gait_error)
		get_tree().quit(1)
		return
	if not _check_deer_leg_skins(deer):
		push_error("A running leg has a break at the joint.")
		get_tree().quit(1)
		return
	var bear_error := await _check_bear()
	if not bear_error.is_empty():
		push_error(bear_error)
		get_tree().quit(1)
		return
	print("Shooting test passed: deer 12 m alert, bear detection, body/head damage, close-range guard and local claw scratches.")
	get_tree().quit()


func _check_deer_gait(deer: Node2D) -> String:
	var dt := 1.0 / Engine.physics_ticks_per_second
	deer.reset_pose()
	deer.advance(dt, deer.lane - DEER.ALERT_DISTANCE - .5)
	if deer.alarm > 0.0:
		return "The deer ran from a player outside the twelve-metre radius."
	deer.reset_pose()
	var observer: float = deer.lane - DEER.ALERT_DISTANCE + .5
	for tick in Engine.physics_ticks_per_second / 2:
		deer.advance(dt, observer)
	if deer.alarm <= 0.0 or deer.speed <= DEER.WALK_SPEED or deer.lane <= DEER.SPAWN_X:
		return "A nearby player did not trigger an escape away from them."
	deer.reset_pose()
	var body: RigidBody2D = deer.parts.body
	deer.receive_shot(body, body.global_position, Vector2.LEFT)
	observer = deer.lane + DEER.ALERT_DISTANCE + 30.0
	for tick in Engine.physics_ticks_per_second / 2:
		deer.advance(dt, observer)
	if deer.fallen or deer.health != 90 or deer.speed <= DEER.WALK_SPEED or deer.lane >= DEER.SPAWN_X:
		return "The first non-lethal hit did not trigger an escape from outside the radius."
	var first := DEER.hoof_cycle(.1, .64, 35.0, 11.0)
	var later := DEER.hoof_cycle(.2, .64, 35.0, 11.0)
	if first.y != 0.0 or later.y != 0.0 or not is_equal_approx(first.x - later.x, 3.5):
		return "A grounded walking hoof slipped relative to the deer stride."
	if DEER.hoof_cycle(.6, .31, 113.0, 27.0).y > -20.0:
		return "The running hoof did not lift during its swing."
	return ""


func _check_deer_leg_skins(deer: Node2D) -> bool:
	deer._update_skin()
	var row := DEER.LEG_SKIN.KNEE_ROW
	for i in DEER.LEGS.size():
		var leg: String = DEER.LEGS[i]
		var mesh: Polygon2D = deer.leg_skins[i]
		var first := 2 * row
		var second := first + 1
		# Both sides of the bend must use the same vertex pair at the joint.
		for face_index in [2 * row - 1, 2 * row]:
			var face: PackedInt32Array = mesh.polygons[face_index]
			if not face.has(first) or not face.has(second):
				return false
		var center := mesh.polygon[first].lerp(mesh.polygon[second], .5)
		var knee: Node2D = deer.parts[leg + "_lower"].get_node("Art")
		if center.distance_to(deer.to_local(knee.global_position)) > .01:
			return false
	return true


func _check_bear() -> String:
	var dt := 1.0 / Engine.physics_ticks_per_second
	_select_target(1)
	var bear := animal
	bear.advance(dt, bear.lane - BEAR.SIGHT_RANGE - 1.0)
	bear.advance(dt, bear.lane + 100.0)
	if bear.aggro:
		return "The bear saw the player outside its sight range or behind it."
	bear.advance(dt, bear.lane - BEAR.SIGHT_RANGE + .5)
	if not bear.aggro or bear.speed <= 0.0:
		return "The bear did not chase a visible player within twelve metres."
	if not _check_bear_paws(bear):
		return "A planted bear paw rolled outward during a charge."
	if not _check_single_paw_swipe(bear):
		return "The bear must keep its far paw in place while the near paw swipes."
	bear.pace = false
	var torso: RigidBody2D = bear.parts.body
	for hit in range(1, 50):
		bear.receive_shot(torso, torso.global_position, Vector2.LEFT)
		if bear.health != 100 - hit * 2 or bear.fallen:
			return "Bear body-hit damage is incorrect after hit %s." % hit
	shot_range.shoot(torso.global_position + Vector2(170, -8), Vector2.LEFT)
	for frame in 16:
		await get_tree().process_frame
	if not bear.fallen or bear.health != 0 or bear.marks.size() != 32:
		return "The fiftieth body shot must kill the bear without exceeding 32 marks."
	_command("reset")
	bear.pace = false
	for head_hit in range(1, 3):
		var head: Node2D = bear.parts.head.get_node("HurtShape")
		shot_range.shoot(head.global_position - Vector2(135, 0), Vector2.RIGHT)
		for frame in 12:
			await get_tree().process_frame
		if bear.health != 100 - head_hit * 50 or bear.fallen != (head_hit == 2):
			return "Bear head hits must remove 50 percent of maximum health."
	_command("reset")
	bear.pace = true
	actor.anchor_x = bear.lane - 82.0
	for frame in 26:
		await get_tree().process_frame
	actor.anchor_x = bear.lane - 190.0
	for frame in 24:
		await get_tree().process_frame
	if player_health != 100:
		return "The bear hit the player outside its claw reach."
	if not actor.claw_marks.is_empty():
		return "A missed swipe left a claw mark."
	_command("reset")
	actor.anchor_x = bear.lane - 82.0
	var health_samples: Array[int] = []
	var last := player_health
	for frame in 320:
		await get_tree().process_frame
		if player_health != last:
			health_samples.append(player_health)
			last = player_health
	if health_samples != [67, 34, 1, 0] or not actor.fallen:
		return "Each connected claw swipe must remove 33 percent once."
	var marks := 0
	for sprite: Sprite2D in actor.claw_marks:
		marks += actor.claw_marks[sprite].size()
		if sprite.material == null:
			return "A claw mark did not stay on the struck sprite through the fall."
	if marks != 4:
		return "Each connected swipe must leave one local mark."
	_command("reset")
	if not actor.claw_marks.is_empty():
		return "Claw marks remained after resetting the encounter."
	return _check_close_bear_swipes(bear, dt)


func _check_close_bear_swipes(bear: Node2D, dt: float) -> String:
	for side in [-1.0, 1.0]:
		_command("reset")
		bear.facing = side
		actor.anchor_x = bear.lane + side * 120.0
		actor.aim = bear.parts.body.global_position
		var reached_stop := false
		for tick in 5 * Engine.physics_ticks_per_second:
			_advance_combatants(dt, -side)
			var clearance: float = (actor.anchor_x - bear.player_stop_x(side)) * side
			if clearance < -.01 or actor.fallen:
				return "The player crossed the live bear or took more than three swipes."
			reached_stop = reached_stop or is_zero_approx(clearance)
			if player_health == 1:
				break
		var scratched_parts: Array = actor.claw_marks.keys().map(func(sprite: Sprite2D):
			return String(sprite.get_parent().get_parent().name))
		if not reached_stop or player_health != 1 or not scratched_parts.has("head"):
			return "Closest approach failed (side %s, reached stop %s, health %s, marked parts %s)." % [
				side, reached_stop, player_health, scratched_parts]
		if not scratched_parts.any(func(part: String):
			return part == "torso" or part.ends_with("arm") or part.ends_with("hand")):
			return "A mid-height swipe could not scratch the torso, arm, or hand."
		if not scratched_parts.any(func(part: String):
			return part.ends_with("thigh") or part.ends_with("shin") or part.ends_with("boot")):
			return "A low swipe could not scratch a leg."
		var head: RigidBody2D = bear.parts.head
		bear.receive_shot(head, head.global_position, Vector2(-side, 0.0))
		bear.receive_shot(head, head.global_position, Vector2(-side, 0.0))
		for tick in 2 * Engine.physics_ticks_per_second:
			_advance_combatants(dt, -side)
		if (actor.anchor_x - bear.lane) * side >= 0.0:
			return "A downed bear still blocked movement."
	return ""


func _check_bear_paws(bear: Node2D) -> bool:
	var saved_speed: float = bear.speed
	var saved_step: float = bear.step
	var saved_facing: float = bear.facing
	bear.speed = BEAR.CHARGE_SPEED
	for facing in [-1.0, 1.0]:
		bear.facing = facing
		for phase in range(0, 16):
			bear.step = float(phase) / 16.0
			bear._pose()
			bear._update_skin()
			for i in DEER.LEGS.size():
				if fposmod(bear.step - DEER.WALK_CONTACT[i], 1.0) >= bear._stance():
					continue
				var vertices: PackedVector2Array = bear.leg_skins[i].polygon
				var heel := vertices[vertices.size() - 2]
				var toe := vertices[vertices.size() - 1]
				if absf(heel.y - toe.y) > .03 or (toe.x - heel.x) * facing <= 0.0:
					return false
	bear.speed = saved_speed
	bear.step = saved_step
	bear.facing = saved_facing
	bear._pose()
	bear._update_skin()
	return true


func _check_single_paw_swipe(bear: Node2D) -> bool:
	var saved_facing: float = bear.facing
	var saved_speed: float = bear.speed
	bear.speed = 0.0
	for facing in [-1.0, 1.0]:
		bear.facing = facing
		bear.attack_time = .43
		bear._pose()
		var striking: RigidBody2D = bear.parts.near_front_lower
		var tucked: RigidBody2D = bear.parts.far_front_lower
		var paw_offset := Vector2(BEAR.PAW_SOCKET.x * facing, BEAR.PAW_SOCKET.y)
		var start := striking.to_global(paw_offset)
		var brace := tucked.to_global(paw_offset)
		for frame in 15:
			bear.attack_time = lerpf(.44, .71, float(frame) / 14.0)
			bear._pose()
			if tucked.to_global(paw_offset).distance_to(brace) > .01:
				return false
			if striking.to_global(paw_offset).distance_to(brace) < 17.0:
				return false
		if striking.to_global(paw_offset).distance_to(start) < 30.0:
			return false
	bear.attack_time = -1.0
	bear.facing = saved_facing
	bear.speed = saved_speed
	bear._pose()
	return true
