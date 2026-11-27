extends Node2D

const CHARACTER := preload("res://character.gd")
const DEER := preload("res://deer.gd")
const BEAR := preload("res://bear.gd")
const SNAKE := preload("res://snake.gd")
const BOAR := preload("res://boar.gd")
const SHOT_RANGE := preload("res://shot_range.gd")
const LAKE_FISHING := preload("res://lake_fishing.gd")
const LAKE := preload("res://assets/lake.webp")
const SHORE_ACCESS_X := 365.0
const SHORE_ACCESS_RADIUS := 51.0
const DECK_Y := 378.0
const HITS_PER_LEVEL := 4
const STAGE_WIDTH := 1440.0
const VIEW_ZOOM := .85
const HALF_VIEW := 480.0 / VIEW_ZOOM
const PISTOL_INTERVAL := .24
const RIFLE_INTERVAL := .20
const RIFLE_SPREAD_PER_SHOT := .65
const RIFLE_MAX_EXTRA_SPREAD := 7.0
enum Target { DEER, BEAR, SNAKE, BOAR }
const ANIMALS := [DEER, BEAR, SNAKE, BOAR]
const ANIMAL_NAMES := ["Deer", "Bear", "Snake", "Boar"]

var actor: Node2D
var animal: Node2D
var shot_range: Node2D
var camera: Camera2D
var fishing: Node2D
var fishing_return_x := 0.0
var combat_ui: CanvasLayer
var fishing_button: Button
var target_picker: OptionButton
var player_health_label: Label
var ammo_button: Button
var weapon_button: Button
var target := Target.DEER
var player_health := 100
var mouse_aim := false
var pad_buttons: Dictionary = {}
var aim_point := Vector2(650, 315)
var held_fire: Dictionary = {}
var fire_pending := false
var shot_cooldown := 0.0
var rifle_burst_shots := 0
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
	fishing = LAKE_FISHING.new()
	add_child(fishing)
	fishing.leave_requested.connect(_leave_fishing)
	_make_controls()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_select_target(0)
	if "--self-test" in OS.get_cmdline_user_args():
		_self_test.call_deferred()


func _physics_process(delta: float) -> void:
	if fishing.active:
		_advance_fishing(delta)
		return
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
		for control in [JOY_BUTTON_X, JOY_BUTTON_B, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
			var key := Vector2i(pad, control)
			var down := Input.is_joy_button_pressed(pad, control)
			if down and not pad_buttons.get(key, false):
				_command({JOY_BUTTON_X: "cast", JOY_BUTTON_B: "fall", JOY_BUTTON_Y: "reset",
					JOY_BUTTON_LEFT_SHOULDER: "reload", JOY_BUTTON_RIGHT_SHOULDER: "switch_weapon"}[control])
			pad_buttons[key] = down
		_set_fire_input(pad, Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT) > .45)
	var wants_fire: bool = fire_pending or (actor.equipped == CHARACTER.Weapon.RIFLE and not held_fire.is_empty())
	actor.aim = aim_point
	_advance_combatants(delta, movement)
	camera.position.x = move_toward(camera.position.x,
		clampf(actor.anchor_x + 180.0, HALF_VIEW, STAGE_WIDTH - HALF_VIEW), delta * 335.0)
	shot_cooldown = maxf(0.0, shot_cooldown - delta)
	fire_pending = false
	if actor.reload_time >= 0.0 or actor.cast_time >= 0.0 or actor.fallen:
		rifle_burst_shots = 0
	if wants_fire and shot_cooldown <= .00001:
		_fire()
	shot_range.advance(delta)
	_update_ammo()
	fishing_button.disabled = not _at_lake_shore()
	if actor.fallen:
		status.text = "Player down" if player_health == 0 else "Ragdoll"
	elif animal.fallen:
		status.text = "%s down" % ANIMAL_NAMES[target]
	elif target == Target.BEAR and animal.aggro:
		status.text = "Claw swipe" if animal.attack_time >= 0.0 else "Charging"
	elif target == Target.SNAKE and animal.aggro:
		status.text = "Strike" if animal.attack_time >= 0.0 else "Chasing"
	elif target == Target.BOAR and animal.aggro:
		status.text = "Ram" if animal.attack_time >= 0.0 else "Charging"
	else:
		status.text = "Casting" if actor.cast_time >= 0.0 else "Aim"
	queue_redraw()


func _at_lake_shore() -> bool:
	return not actor.fallen and absf(actor.anchor_x - SHORE_ACCESS_X) <= SHORE_ACCESS_RADIUS


func _enter_fishing() -> void:
	if fishing.active or not _at_lake_shore() or actor.reload_time >= 0.0:
		return
	fishing_return_x = actor.anchor_x
	shot_range.clear()
	fire_pending = false
	held_fire.clear()
	rifle_burst_shots = 0
	combat_ui.hide()
	animal.hide()
	fishing.enter(actor)
	actor.advance(1.0 / Engine.physics_ticks_per_second, 0.0)
	camera.position.x = HALF_VIEW
	queue_redraw()


func _leave_fishing() -> void:
	actor.anchor_x = fishing_return_x
	actor.advance(1.0 / Engine.physics_ticks_per_second, 0.0)
	animal.show()
	combat_ui.show()
	queue_redraw()


func _advance_fishing(delta: float) -> void:
	for pad: int in Input.get_connected_joypads():
		for control in [JOY_BUTTON_X, JOY_BUTTON_B, JOY_BUTTON_Y]:
			var key := Vector2i(pad, control)
			var down := Input.is_joy_button_pressed(pad, control)
			var was_down: bool = pad_buttons.get(key, false)
			pad_buttons[key] = down
			if control == JOY_BUTTON_X and down != was_down:
				fishing.set_action_input(pad, down)
			elif down and not was_down:
				if control == JOY_BUTTON_Y:
					fishing.leave()
					return
				if control == JOY_BUTTON_B:
					fishing.secondary_action()
	fishing.advance(delta)
	actor.advance(delta, 0.0)


func _advance_combatants(delta: float, movement: float) -> void:
	var left := CHARACTER.STAGE_LEFT
	var right := CHARACTER.STAGE_RIGHT
	var blocks_player := target == Target.BEAR or target == Target.BOAR
	if target != Target.DEER:
		animal.hunter_active = not actor.fallen
	if blocks_player:
		var approach_side := -1.0 if actor.anchor_x < animal.lane else 1.0
		animal.advance(delta, actor.anchor_x)
		if not animal.fallen:
			var stop_x := clampf(animal.player_stop_x(approach_side), left, right)
			if approach_side < 0.0:
				right = minf(right, stop_x)
			else:
				left = maxf(left, stop_x)
	actor.advance(delta, movement, left, right, player_health)
	if not blocks_player:
		animal.advance(delta, actor.anchor_x)
	match target:
		Target.BEAR: animal.resolve_claw_hit(actor)
		Target.SNAKE: animal.resolve_bite(actor)
		Target.BOAR: animal.resolve_ram(actor)


func _set_fire_input(source: Variant, pressed: bool) -> void:
	if pressed:
		if not held_fire.has(source):
			held_fire[source] = true
			_command("fire")
	elif held_fire.erase(source) and held_fire.is_empty():
		rifle_burst_shots = 0


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if not connected:
		_set_fire_input(device, false)
		fishing.set_action_input(device, false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		held_fire.clear()
		fire_pending = false
		rifle_burst_shots = 0
		if fishing != null:
			fishing.held.clear()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_set_fire_input("mouse", false)
		_set_fire_input("button", false)
		if fishing.active:
			fishing.set_action_input("button", false)
	elif event is InputEventKey and event.physical_keycode == KEY_SPACE and not event.pressed:
		_set_fire_input("key", false)
	elif event is InputEventKey and event.physical_keycode == KEY_E and not event.pressed and fishing.active:
		fishing.set_action_input("key", false)


func _unhandled_input(event: InputEvent) -> void:
	if fishing.active:
		if event is InputEventKey and event.pressed and not event.echo:
			match event.physical_keycode:
				KEY_E: fishing.set_action_input("key", true)
				KEY_F: fishing.secondary_action()
				KEY_I: fishing.toggle_bag()
				KEY_ESCAPE, KEY_BACKSPACE: fishing.leave()
		return
	if event is InputEventMouseMotion:
		mouse_aim = true
		aim_point = get_global_mouse_position()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		mouse_aim = true
		aim_point = get_global_mouse_position()
		_set_fire_input("mouse", true)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_E: _command("cast")
			KEY_F: _command("fall")
			KEY_R: _command("reload")
			KEY_Q: _command("switch_weapon")
			KEY_BACKSPACE: _command("reset")
			KEY_SPACE: _set_fire_input("key", true)
			KEY_1: _select_target(0)
			KEY_2: _select_target(1)
			KEY_3: _select_target(2)
			KEY_4: _select_target(3)


func _command(command: String) -> void:
	match command:
		"cast": _enter_fishing()
		"fall": actor.fall()
		"reload": actor.reload()
		"switch_weapon":
			if actor.switch_weapon():
				rifle_burst_shots = 0
				_update_ammo()
		"fire": fire_pending = true
		"reset":
			actor.reset_pose()
			animal.reset_pose()
			camera.position.x = HALF_VIEW
			player_health = 100
			_update_player_health()
			_update_ammo()
			mouse_aim = false
			aim_point = animal.head.global_position if target == Target.SNAKE else animal.parts.body.global_position
			shot_range.clear()
			fire_pending = false
			held_fire.clear()
			rifle_burst_shots = 0
			shot_cooldown = 0.0


func _select_target(index: int) -> void:
	if is_instance_valid(animal):
		remove_child(animal)
		animal.queue_free()
	target = index as Target
	target_picker.select(index)
	animal = ANIMALS[target].new()
	add_child(animal)
	if target == Target.BEAR:
		animal.claw_hit.connect(_take_animal_damage)
	elif target == Target.SNAKE:
		animal.bite_hit.connect(_take_animal_damage)
	elif target == Target.BOAR:
		animal.ram_hit.connect(_take_animal_damage)
	_command("reset")


func _take_animal_damage(damage: int) -> void:
	if actor.fallen:
		return
	player_health = maxi(0, player_health - damage)
	_update_player_health()
	if player_health == 0:
		actor.fall()


func _update_player_health() -> void:
	player_health_label.text = "Health %d%%" % player_health
	player_health_label.visible = target != Target.DEER


func _update_ammo() -> void:
	var action := "Reloading…" if actor.reload_time >= 0.0 else "Reload R / LB"
	ammo_button.text = "%d / %d   %s" % [actor.rounds_in_magazine, actor.magazine_capacity(), action]
	var weapon_name := "G3" if actor.equipped == CHARACTER.Weapon.RIFLE else "Pistol"
	weapon_button.text = "%s   Q / RB" % weapon_name


func _fire() -> void:
	if not actor.weapon.visible or not actor.fire_weapon():
		return
	var rifle: bool = actor.equipped == CHARACTER.Weapon.RIFLE
	var gun: Node2D = actor.weapon
	var muzzle: Node2D = actor.muzzle
	var barrel := Vector2.RIGHT.rotated(gun.global_rotation)
	var extra_spread := _rifle_extra_spread() if rifle else 0.0
	var direction := SHOT_RANGE.spread_direction(barrel, _shooting_level(), randf_range(-1.0, 1.0), extra_spread)
	shot_range.shoot(muzzle.global_position, direction, .65 if rifle else 1.0)
	shot_cooldown = RIFLE_INTERVAL if rifle else PISTOL_INTERVAL
	if rifle and actor.reload_time < 0.0 and not held_fire.is_empty():
		rifle_burst_shots += 1
	else:
		rifle_burst_shots = 0


func _rifle_extra_spread() -> float:
	return minf(rifle_burst_shots * RIFLE_SPREAD_PER_SHOT, RIFLE_MAX_EXTRA_SPREAD)


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
	combat_ui = layer
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
	for i in ANIMAL_NAMES.size():
		target_picker.add_item("%s · %d" % [ANIMAL_NAMES[i], i + 1], i)
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
	for option in [["Shoot  Space / RT", "fire"], ["Fish Here  E / X", "cast"], ["Fall  F / B", "fall"], ["Reset  Bksp / Y", "reset"]]:
		var button := Button.new()
		button.text = option[0]
		button.focus_mode = Control.FOCUS_NONE
		if option[1] == "fire":
			button.button_down.connect(_set_fire_input.bind("button", true))
			button.button_up.connect(_set_fire_input.bind("button", false))
		else:
			button.pressed.connect(_command.bind(option[1]))
		if option[1] == "cast":
			fishing_button = button
			button.disabled = true
		row.add_child(button)
	weapon_button = Button.new()
	weapon_button.position = Vector2(578, 65)
	weapon_button.size = Vector2(138, 34)
	weapon_button.focus_mode = Control.FOCUS_NONE
	weapon_button.pressed.connect(_command.bind("switch_weapon"))
	layer.add_child(weapon_button)
	ammo_button = Button.new()
	ammo_button.position = Vector2(724, 65)
	ammo_button.size = Vector2(214, 34)
	ammo_button.focus_mode = Control.FOCUS_NONE
	ammo_button.pressed.connect(_command.bind("reload"))
	layer.add_child(ammo_button)


func _draw() -> void:
	if fishing != null and fishing.active:
		draw_texture_rect(LAKE, Rect2(0, -78, STAGE_WIDTH, 770), false)
		return
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
	var sign_x := SHORE_ACCESS_X
	draw_rect(Rect2(sign_x - 2, DECK_Y - 36, 4, 36), Color("#63432e"))
	var board := Rect2(sign_x - 45, DECK_Y - 56, 90, 25)
	draw_rect(board, Color("#092034"))
	draw_rect(board, Color("#ad8250"), false, 1.0)
	draw_string(ThemeDB.fallback_font, board.position + Vector2(12, 17), "Fish Here", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#ffd698"))
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
	shot_range.shoot(head.global_position - Vector2(115, 0), Vector2.RIGHT)
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
	var gait_error := await _check_deer_gait(deer)
	if not gait_error.is_empty():
		push_error(gait_error)
		get_tree().quit(1)
		return
	if not _check_deer_leg_skins(deer):
		push_error("A running leg has a break at the joint.")
		get_tree().quit(1)
		return
	var falloff_error := await _check_damage_falloff(deer)
	if not falloff_error.is_empty():
		push_error(falloff_error)
		get_tree().quit(1)
		return
	var bear_error := await _check_bear()
	if not bear_error.is_empty():
		push_error(bear_error)
		get_tree().quit(1)
		return
	var snake_error := await _check_snake()
	if not snake_error.is_empty():
		push_error(snake_error)
		get_tree().quit(1)
		return
	var boar_error := await _check_boar()
	if not boar_error.is_empty():
		push_error(boar_error)
		get_tree().quit(1)
		return
	var player_gait_error := _check_player_gait()
	if not player_gait_error.is_empty():
		push_error(player_gait_error)
		get_tree().quit(1)
		return
	var reload_error := await _check_pistol_reload()
	if not reload_error.is_empty():
		push_error(reload_error)
		get_tree().quit(1)
		return
	var rifle_error := await _check_rifle()
	if not rifle_error.is_empty():
		push_error(rifle_error)
		get_tree().quit(1)
		return
	var fishing_error := _check_lake_fishing()
	if not fishing_error.is_empty():
		push_error(fishing_error)
		get_tree().quit(1)
		return
	print("Character test passed: lake fishing, weapons, projectile flight, animal combat and player gaits.")
	get_tree().quit()


func _check_pistol_reload() -> String:
	_select_target(Target.DEER)
	var ticks := Engine.physics_ticks_per_second
	var capacity := CHARACTER.MAGAZINE_CAPACITY
	for direction: float in [-1.0, 1.0]:
		for elevation: float in [-300.0, 0.0, 300.0]:
			actor.aim = actor.parts.torso.global_position + Vector2(direction * 240.0, elevation)
			actor.advance(1.0 / ticks, 0.0)
			if actor.parts.far_hand.visible or actor.parts.far_hand.position.distance_to(actor.parts.hand.position) > .01:
				return "The supporting hand must align behind the front hand while aiming."
	aim_point = Vector2(220, 50)
	_command("reload")
	if capacity != 12 or actor.rounds_in_magazine != capacity or actor.reload_time >= 0.0:
		return "The pistol must start with twelve rounds and skip reload while full."
	for remaining in range(capacity - 1, -1, -1):
		_command("fire")
		for tick in 2:
			await get_tree().physics_frame
		if actor.rounds_in_magazine != remaining or (actor.reload_time >= 0.0) != (remaining == 0):
			return "Each shot must spend one round, and only the last shot must start an automatic reload."
		if remaining > 0:
			for tick in ceili(.25 * ticks):
				await get_tree().physics_frame
	for tick in ceili(.34 * ticks):
		await get_tree().physics_frame
	if actor.rounds_in_magazine != 0 or actor.magazine.position.y < 12.0 or not actor.parts.far_hand.visible \
			or not ammo_button.text.contains("Reloading"):
		return "The empty magazine did not animate before refilling."
	for tick in ticks:
		await get_tree().physics_frame
	if actor.rounds_in_magazine != capacity or actor.reload_time >= 0.0:
		return "The automatic reload did not restore all twelve rounds."
	_command("fire")
	for tick in 2:
		await get_tree().physics_frame
	var reload_key := InputEventKey.new()
	reload_key.physical_keycode = KEY_R
	reload_key.pressed = true
	_unhandled_input(reload_key)
	if actor.rounds_in_magazine != capacity - 1 or actor.reload_time < 0.0:
		return "R did not start a manual reload for a partially used magazine."
	for tick in ceili(.3 * ticks):
		await get_tree().physics_frame
	var progress: float = actor.reload_time
	_unhandled_input(reload_key)
	_command("fire")
	_command("cast")
	for tick in 2:
		await get_tree().physics_frame
	if actor.reload_time <= progress or actor.cast_time >= 0.0 or actor.rounds_in_magazine != capacity - 1:
		return "An input interrupted or restarted an active reload."
	for tick in ticks:
		await get_tree().physics_frame
	if actor.rounds_in_magazine != capacity or actor.reload_time >= 0.0 or actor.magazine.position.y != 6.0:
		return "The manual reload did not finish with a full, seated magazine."
	return ""


func _check_rifle() -> String:
	_select_target(Target.DEER)
	var ticks := Engine.physics_ticks_per_second
	var switch_key := InputEventKey.new()
	switch_key.physical_keycode = KEY_Q
	switch_key.pressed = true
	_unhandled_input(switch_key)
	if actor.equipped != CHARACTER.Weapon.RIFLE or actor.magazine_capacity() != 30 or actor.rounds_in_magazine != 30:
		return "Q did not equip a loaded thirty-round rifle."
	var stock_art: Node2D = actor.weapon.get_node("Stock")
	if stock_art.z_as_relative or stock_art.z_index >= actor.parts.torso.z_index:
		return "The rifle stock must be drawn behind the character's shoulder."
	for side: float in [-1.0, 1.0]:
		actor.aim = actor.parts.torso.global_position + Vector2(side * 220.0, -90.0)
		actor.advance(1.0 / ticks, 0.0)
		var grip: Vector2 = actor.weapon.to_global(CHARACTER.RIFLE_ART.FOREGRIP)
		var stock: Vector2 = actor.weapon.to_global(CHARACTER.RIFLE_ART.STOCK_CONTACT)
		var shoulder: Vector2 = actor.parts.near_arm.global_position + Vector2(-2.0 * side, 1.0)
		if stock.distance_to(shoulder) > .01:
			return "The rifle stock did not stay against the shoulder while aiming."
		if actor.weapon.reverse != (side < 0.0) or actor.parts.far_arm.visible or actor.parts.far_forearm.visible \
				or actor.parts.far_hand.global_position.distance_to(grip) > .01:
			return "The rifle must show the correct side and keep the left hand on the foregrip."
	aim_point = Vector2(220.0, 50.0)
	var fire_key := InputEventKey.new()
	fire_key.physical_keycode = KEY_SPACE
	fire_key.pressed = true
	_unhandled_input(fire_key)
	for tick in 2:
		await get_tree().physics_frame
	if actor.rounds_in_magazine != 29 or shot_range.rounds.size() != 1:
		return "The rifle did not fire immediately when pressed."
	var first: Dictionary = shot_range.rounds[0]
	if first.visual_scale >= 1.0 or absf(first.velocity.length() - SHOT_RANGE.FLIGHT_SPEED) > 2.0:
		return "The rifle projectile must be smaller and fly at pistol speed."
	var first_growth := _rifle_extra_spread()
	for tick in ceili(.22 * ticks):
		await get_tree().physics_frame
	if actor.rounds_in_magazine != 28 or _rifle_extra_spread() <= first_growth:
		return "Holding fire did not add a faster second shot and grow its spread budget."
	fire_key.pressed = false
	_input(fire_key)
	for tick in ticks / 3:
		await get_tree().physics_frame
	if actor.rounds_in_magazine != 28 or not is_zero_approx(_rifle_extra_spread()):
		return "Releasing the trigger must stop fire and clear the burst spread."
	_command("switch_weapon")
	if actor.rounds_in_magazine != 12:
		return "The pistol and rifle shared ammunition."
	_command("switch_weapon")
	if actor.rounds_in_magazine != 28:
		return "Switching weapons did not preserve the rifle magazine."
	fire_key.pressed = true
	_unhandled_input(fire_key)
	for tick in 7 * ticks:
		await get_tree().physics_frame
		if actor.reload_time >= 0.0:
			break
	if actor.rounds_in_magazine != 0 or actor.reload_time < 0.0:
		return "A continuous burst did not empty all thirty rounds and start reloading."
	fire_key.pressed = false
	_input(fire_key)
	for tick in ceili(.43 * ticks):
		await get_tree().physics_frame
	var magazine_grip: Vector2 = actor.magazine.to_global(CHARACTER.RIFLE_ART.MAGAZINE_GRIP)
	if actor.magazine.position.y < 7.0 or actor.parts.far_hand.global_position.distance_to(magazine_grip) > 1.0:
		return "The rifle's left hand did not follow its magazine during reload."
	for tick in ticks:
		await get_tree().physics_frame
	if actor.rounds_in_magazine != 30 or actor.reload_time >= 0.0:
		return "Reload did not refill the rifle to thirty rounds."
	return ""


func _check_lake_fishing() -> String:
	_select_target(Target.DEER)
	var dt := 1.0 / Engine.physics_ticks_per_second
	var ticks := Engine.physics_ticks_per_second
	_command("cast")
	if fishing.active or actor.cast_time >= 0.0:
		return "Casting must be unavailable away from the lake shore."
	actor.anchor_x = SHORE_ACCESS_X
	_command("cast")
	if not fishing.active or not actor.fishing_stance or actor.weapon.visible:
		return "The shore interaction did not open fishing with the casting rod."
	for level in range(1, 4):
		var species := LAKE_FISHING.select_fish(level, .999)
		if species.level != level:
			return "The rod level unlocked the wrong lake fish."
		fishing._set_rod(level - 1)
		if actor.rod.to_local(actor.rod.reel_grip(0.0)).y <= 0.0:
			return "A casting rod must keep its reel under the grip."
	fishing._set_rod(0)
	fishing.rng.seed = 423
	for outcome in ["miss", "snap", "keep", "release"]:
		fishing.set_action_input("test", true)
		fishing.set_action_input("test", false)
		if actor.cast_time < 0.0 or fishing.phase != LAKE_FISHING.Phase.CASTING:
			return "The lake action did not start the casting animation."
		for tick in 6 * ticks:
			_advance_fishing(dt)
			if fishing.phase == LAKE_FISHING.Phase.BITE:
				break
		if fishing.phase != LAKE_FISHING.Phase.BITE or fishing.fish.label != "Lake Perch":
			return "A cast with the first rod did not reach a perch bite."
		if outcome == "miss":
			for tick in ceili(1.2 * ticks):
				_advance_fishing(dt)
			if fishing.phase != LAKE_FISHING.Phase.READY or not fishing.prompt.text.contains("Missed"):
				return "The hook timing window never expired."
			continue
		fishing.set_action_input("test", true)
		for tick in ticks / 2:
			_advance_fishing(dt)
		if fishing.phase != LAKE_FISHING.Phase.REELING or actor.reel_turn <= 0.0:
			return "Following a hook set, the reeling hand must start turning the reel."
		if outcome == "snap":
			fishing.tension = 99.9
			_advance_fishing(dt)
			fishing.set_action_input("test", false)
			if fishing.phase != LAKE_FISHING.Phase.READY or not fishing.prompt.text.contains("snapped"):
				return "The line did not snap at maximum tension."
			continue
		for tick in 5 * ticks:
			_advance_fishing(dt)
			if fishing.phase == LAKE_FISHING.Phase.CAUGHT:
				break
		fishing.set_action_input("test", false)
		if fishing.phase != LAKE_FISHING.Phase.CAUGHT or fishing.line_end.distance_to(LAKE_FISHING.HANG_POINT) > .01:
			return "The fish was not lifted and shown at the end of the line."
		if outcome == "keep":
			fishing.set_action_input("test", true)
			fishing.set_action_input("test", false)
			if not fishing.bag.visible or fishing.bag_cells.count(1) != 2:
				return "Keeping the perch did not open its two-cell backpack placement."
			fishing.toggle_bag()
		else:
			fishing.secondary_action()
			for tick in ticks:
				_advance_fishing(dt)
			if fishing.phase != LAKE_FISHING.Phase.READY or fishing.bag_cells.count(1) != 2:
				return "Releasing the catch must leave the backpack empty of that fish."
	fishing.leave()
	if fishing.active or actor.fishing_stance or not is_equal_approx(actor.anchor_x, SHORE_ACCESS_X):
		return "Leaving the lake view did not return the player to the shoreline."
	return ""


func _check_player_gait() -> String:
	var dt := 1.0 / Engine.physics_ticks_per_second
	for direction: float in [-1.0, 1.0]:
		actor.reset_pose()
		actor.anchor_x = STAGE_WIDTH * .5
		actor.aim = Vector2(actor.anchor_x + direction * 650.0, 313.0)
		for health: int in [100, 99, 67, 50, 49, 34, 1, 0]:
			var expected := CHARACTER.RUN_SPEED * (health / 100.0)
			actor.advance(dt, direction, CHARACTER.STAGE_LEFT, CHARACTER.STAGE_RIGHT, health)
			if absf(actor.move_speed) > expected + .001:
				return "The top speed did not decrease immediately with health."
			for tick in 40:
				actor.advance(dt, direction, CHARACTER.STAGE_LEFT, CHARACTER.STAGE_RIGHT, health)
			if not is_equal_approx(actor.move_speed, direction * expected):
				return "Movement speed is incorrect at %d%% health." % health
			var should_run: bool = health >= 50
			if not is_equal_approx(actor.run_blend, float(should_run)):
				return "The gait did not switch below 50 percent health."
			if health != 100 and health != 49:
				continue
			var airborne := false
			for sample in 40:
				actor.gait_phase = sample / 40.0
				actor._pose(dt)
				var soles := []
				for side in ["near", "far"]:
					var thigh: Node2D = actor.parts[side + "_thigh"]
					var shin: Node2D = actor.parts[side + "_shin"]
					var boot: Node2D = actor.parts[side + "_boot"]
					var bend: float = angle_difference(thigh.rotation, shin.rotation) * direction
					if bend < 0.0 or bend > CHARACTER.KNEE_LIMIT + .001:
						return "A knee bent outside its forward hinge range."
					var boot_art: Sprite2D = boot.get_node("Art/Sprite")
					var collar := CHARACTER.BOOT_COLLAR
					if boot_art.flip_h:
						collar.x = CHARACTER.BOOT_SIZE.x - collar.x
					if boot_art.to_global(collar / boot_art.scale).distance_to(shin.to_global(Vector2(0, CHARACTER.SHIN))) > .01:
						return "A boot collar moved away from the pant cuff."
					var sole_x := (CHARACTER.BOOT_TOE if boot.rotation * direction > 0.0 else CHARACTER.BOOT_HEEL) * direction
					soles.append(boot.to_global(Vector2(sole_x, CHARACTER.BOOT_SOLE)).y)
				airborne = airborne or maxf(soles[0], soles[1]) < DECK_Y - .2
			if airborne != should_run:
				return "Running must have a flight phase and walking must keep one foot down."
	return ""


func _check_deer_gait(deer: Node2D) -> String:
	var ticks := Engine.physics_ticks_per_second
	_command("reset")
	deer.pace = true
	for tick in ticks / 4:
		await get_tree().physics_frame
	if deer.alarm > 0.0 or deer.speed > DEER.WALK_SPEED or deer.lane <= DEER.SPAWN_X:
		return "The deer did not patrol with the player outside the twelve-metre radius."
	_command("reset")
	actor.anchor_x = deer.lane - DEER.ALERT_DISTANCE + .5
	for tick in ticks / 2:
		await get_tree().physics_frame
	if deer.alarm <= 0.0 or deer.speed <= DEER.WALK_SPEED or deer.lane <= DEER.SPAWN_X:
		return "A nearby player did not trigger an escape away from them."
	_command("reset")
	var shot_lane := 520.0
	deer.lane = shot_lane
	deer._pose()
	actor.anchor_x = 1380.0
	var body: RigidBody2D = deer.parts.body
	shot_range.shoot(Vector2(actor.anchor_x - 25.0, body.global_position.y - 9.0), Vector2.LEFT)
	for tick in ticks:
		await get_tree().physics_frame
	if deer.fallen or deer.health >= DEER.MAX_HEALTH or deer.speed <= DEER.WALK_SPEED or deer.lane >= shot_lane:
		return "The first non-lethal hit did not trigger an escape from outside the radius."
	var first := DEER.hoof_cycle(.1, .64, 35.0, 11.0)
	var later := DEER.hoof_cycle(.2, .64, 35.0, 11.0)
	if first.y != 0.0 or later.y != 0.0 or not is_equal_approx(first.x - later.x, 3.5):
		return "A grounded walking hoof slipped relative to the deer stride."
	if DEER.hoof_cycle(.6, .31, 113.0, 27.0).y > -20.0:
		return "The running hoof did not lift during its swing."
	return ""


func _check_damage_falloff(deer: Node2D) -> String:
	for sample: Vector2 in [Vector2(0, 1), Vector2(2, 1), Vector2(7, 2.0 / 3.0),
			Vector2(12, 1.0 / 3.0), Vector2(17, 0), Vector2(18, 0)]:
		if absf(SHOT_RANGE.damage_multiplier(sample.x * SHOT_RANGE.METRE) - sample.y) > .00001:
			return "Incorrect linear falloff at %s metres." % sample.x
	_command("reset")
	deer.pace = false
	actor.anchor_x = 550.0
	var hurt_shape: CollisionShape2D = deer.parts.body.get_node("HurtShape")
	var half_width := (hurt_shape.shape as CapsuleShape2D).height * .5
	var distance := SHOT_RANGE.THIRD_DAMAGE_RANGE + half_width
	shot_range.shoot(hurt_shape.global_position - Vector2(distance, 8.0), Vector2.RIGHT)
	if not is_equal_approx(shot_range.rounds[0].velocity.length(), 2655.0):
		return "The pistol projectile did not launch at 150 percent of its previous speed."
	for tick in Engine.physics_ticks_per_second / 2:
		await get_tree().physics_frame
	if absf(deer.health - (100.0 - 10.0 / 3.0)) > .015 or not deer.health_meter.visible:
		return "A real projectile at twelve metres did not apply fractional body damage."
	return ""


func _check_snake() -> String:
	_select_target(Target.SNAKE)
	var snake := animal
	var ticks := Engine.physics_ticks_per_second
	var starting_x: float = snake.lane
	var starting_bend: float = snake.spine[9].y - snake.spine[15].y
	actor.anchor_x = snake.lane - 5.0 * SNAKE.METRE - 30.0
	for tick in ticks / 3:
		await get_tree().physics_frame
	if snake.aggro or snake.lane >= starting_x or absf(snake.spine[9].y - snake.spine[15].y - starting_bend) < 1.0:
		return "The snake did not patrol normally outside five metres."
	if not is_equal_approx(snake.speed, -28.0):
		return "The snake's normal patrol must retain its original crawl speed."
	_command("reset")
	actor.anchor_x = snake.lane - 5.0 * SNAKE.METRE + 1.0
	for tick in ticks / 2:
		await get_tree().physics_frame
	if not snake.aggro or not is_equal_approx(snake.speed, -146.0):
		return "A player within five metres must trigger the doubled chase speed."
	for side: float in [-1.0, 1.0]:
		_command("reset")
		actor.anchor_x = snake.lane + side * 95.0
		for tick in ticks:
			await get_tree().physics_frame
			if player_health < 100:
				break
		if player_health != 85 or snake.facing != side or not snake.bite_connected:
			return "The snake failed to lunge and bite for fifteen health."
		for tick in ticks / 5:
			await get_tree().physics_frame
		if player_health != 85:
			return "One snake bite dealt damage more than once."
	_command("reset")
	actor.anchor_x = snake.lane - SNAKE.ATTACK_DISTANCE
	actor.aim = snake.head.global_position
	_advance_combatants(1.0 / ticks, 0.0)
	for tick in ceili(.28 * ticks):
		_advance_combatants(1.0 / ticks, -1.0)
		if player_health < 100:
			break
	if player_health != 85 or snake.attack_time > SNAKE.LUNGE_END:
		return "The fast lunge failed to catch a player retreating from bite range."
	_command("reset")
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.seed = 5849
	shot_range.impact_rng.seed = expected_rng.seed
	var saw_miss := false
	var saw_roll := false
	for attempt in 26:
		shot_range.clear()
		var should_hit := expected_rng.randf() < .33
		var before: float = snake.health
		var was_aggro: bool = snake.aggro
		var center: Vector2 = snake.to_global(snake.spine[11])
		shot_range.shoot(center - Vector2(0.0, 76.0), Vector2.DOWN)
		for tick in 9:
			await get_tree().physics_frame
		var expected_health := maxf(0.0, before - (40.0 if should_hit else 0.0))
		if snake.health != expected_health or shot_range.impact_rng.state != expected_rng.state:
			return "The snake did not roll exactly once per projectile or apply forty damage on a close hit."
		if shot_range.hits.is_empty() or shot_range.hits[0].target != should_hit:
			return "A missed snake shot did not continue through to the deck."
		if snake.aggro != (was_aggro or should_hit):
			return "The snake must start chasing a distant shooter on a registered hit."
		saw_miss = saw_miss or not should_hit
		if snake.fallen:
			var death_x: float = snake.lane
			var back_uv: Vector2 = snake.skin.uv[18]
			for tick in 2 * ticks / 3:
				await get_tree().physics_frame
			if snake.lane != death_x or snake.head.scale.y >= 0.0 or snake.skin.uv[18].y <= back_uv.y:
				return "The snake did not stop and turn belly-up when killed."
			saw_roll = true
			snake.reset_pose()
	if not saw_miss or not saw_roll:
		return "The snake fixture did not exercise a projectile miss and a lethal roll."
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


func _check_boar() -> String:
	_select_target(Target.BOAR)
	var boar := animal
	var ticks := Engine.physics_ticks_per_second
	actor.anchor_x = boar.lane - 10.0 * BOAR.METRE - 20.0
	for tick in ticks / 4:
		await get_tree().physics_frame
	if boar.aggro or boar.lane >= BOAR.SPAWN_X:
		return "The boar did not patrol normally outside ten metres."
	actor.anchor_x = boar.lane - 10.0 * BOAR.METRE + .5
	for tick in ticks / 3:
		await get_tree().physics_frame
	if not boar.aggro or boar.speed <= 44.0 or boar.facing > 0.0:
		return "A player just inside ten metres did not trigger a charge."
	for side: float in [-1.0, 1.0]:
		_command("reset")
		if side > 0.0:
			boar.lane = 490.0
			boar._pose()
		actor.anchor_x = boar.lane + side * 13.5 * BOAR.METRE
		var body: RigidBody2D = boar.parts.body
		shot_range.shoot(Vector2(actor.anchor_x - side * 27.0, body.global_position.y - 3.0), Vector2(-side, 0.0))
		for tick in ticks:
			await get_tree().physics_frame
			if not boar.marks.is_empty():
				break
			if boar.aggro:
				return "The boar charged before the distant projectile hit."
		if boar.health >= BOAR.MAX_HEALTH or not boar.aggro or absf(actor.anchor_x - boar.lane) <= BOAR.SIGHT_RANGE:
			return "A hit from outside ten metres did not trigger the boar's charge."
		for tick in 6 * ticks:
			await get_tree().physics_frame
			if player_health < 100:
				break
		if player_health != 72 or boar.facing != side:
			return "The boar did not ram the distant shooter for 28 health."
		for tick in ticks / 4:
			await get_tree().physics_frame
		if player_health != 72:
			return "A single boar ram dealt damage more than once."
	_command("reset")
	boar.pace = false
	var torso: RigidBody2D = boar.parts.body
	for hit in range(1, 40):
		boar.receive_shot(torso, torso.global_position, Vector2.LEFT)
		if boar.health != 100.0 - hit * 2.5 or boar.fallen:
			return "The boar's close body-shot damage is incorrect."
	shot_range.shoot(torso.global_position + Vector2(110.0, 0.0), Vector2.LEFT)
	for tick in ticks:
		await get_tree().physics_frame
	if not boar.fallen or boar.health != 0.0 or absf(torso.global_position.x - torso.death_x) > 1.0:
		return "The fortieth close body shot did not drop the boar in place."
	if not _check_deer_leg_skins(boar):
		return "A boar leg separated during its fall."
	return _check_boar_contact(boar)


func _check_boar_contact(boar: Node2D) -> String:
	var ticks := Engine.physics_ticks_per_second
	var dt := 1.0 / ticks
	for side: float in [-1.0, 1.0]:
		_command("reset")
		boar.pace = true
		actor.anchor_x = boar.lane + side * 115.0
		actor.aim = boar.parts.body.global_position
		var reached_stop := false
		var windup_angle := 0.0
		var strike_angle := 0.0
		for tick in 2 * ticks:
			_advance_combatants(dt, -side)
			var clearance: float = (actor.anchor_x - boar.player_stop_x(side)) * side
			if clearance < -.01:
				return "The player or boar crossed the live contact boundary."
			reached_stop = reached_stop or absf(clearance) < .01
			var neck_angle: float = boar.parts.neck.rotation * side
			if boar.attack_time < BOAR.WINDUP_END:
				windup_angle = maxf(windup_angle, neck_angle)
			elif boar.attack_time <= BOAR.RAM_END:
				strike_angle = minf(strike_angle, neck_angle)
			if player_health == 72:
				break
		if not reached_stop or player_health != 72 or actor.scratch_marks.size() != 1:
			return "The closest ram must still hit and scratch the stopped player."
		var impact_x: float = boar.lane
		for tick in ticks / 5:
			_advance_combatants(dt, -side)
			strike_angle = minf(strike_angle, boar.parts.neck.rotation * side)
		if not is_equal_approx(boar.lane, impact_x) or player_health != 72:
			return "The boar kept moving or struck again during the same ram."
		if windup_angle - strike_angle < .5:
			return "The boar's neck did not pull back and snap forward."
		var scratch: Array = actor.scratch_marks.values()[0]
		if scratch.size() != 1 or scratch[0].lines != 1:
			return "A tusk hit must leave one red scratch on the contacted body part."
		var head: RigidBody2D = boar.parts.head
		for hit in 3:
			boar.receive_shot(head, head.global_position, Vector2(-side, 0.0))
		for tick in 2 * ticks:
			_advance_combatants(dt, -side)
		if (actor.anchor_x - boar.lane) * side >= 0.0:
			return "A downed boar still blocked the player."
	return ""


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
	var retaliation_error := await _check_bear_long_range_retaliation(bear)
	if not retaliation_error.is_empty():
		return retaliation_error
	_command("reset")
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
	for head_hit in range(1, 4):
		var head: Node2D = bear.parts.head.get_node("HurtShape")
		shot_range.shoot(head.global_position - Vector2(115, 0), Vector2.RIGHT)
		for frame in 12:
			await get_tree().process_frame
		if bear.health != maxi(0, 100 - head_hit * 34) or bear.fallen != (head_hit == 3):
			return "Close bear head hits must remove 34 percent of maximum health."
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
	if not actor.scratch_marks.is_empty():
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
	for sprite: Sprite2D in actor.scratch_marks:
		marks += actor.scratch_marks[sprite].size()
		for scratch in actor.scratch_marks[sprite]:
			if scratch.lines != 3:
				return "A bear claw must still leave three scratches."
		if sprite.material == null:
			return "A claw mark did not stay on the struck sprite through the fall."
	if marks != 4:
		return "Each connected swipe must leave one local mark."
	_command("reset")
	if not actor.scratch_marks.is_empty():
		return "Claw marks remained after resetting the encounter."
	return _check_close_bear_swipes(bear, dt)


func _check_bear_long_range_retaliation(bear: Node2D) -> String:
	var ticks := Engine.physics_ticks_per_second
	for side: float in [-1.0, 1.0]:
		_command("reset")
		if side > 0.0:
			bear.lane = 490.0
			bear._pose()
		actor.anchor_x = bear.lane + side * 13.5 * BEAR.METRE
		var torso: RigidBody2D = bear.parts.body
		var muzzle := Vector2(actor.anchor_x - side * 27.0, torso.global_position.y - 8.0)
		shot_range.shoot(muzzle, Vector2(-side, 0.0))
		for tick in ticks:
			await get_tree().physics_frame
			if not bear.marks.is_empty():
				break
			if bear.aggro:
				return "The bear charged before the distant bullet hit."
		if bear.marks.is_empty() or bear.health >= BEAR.MAX_HEALTH or not bear.aggro \
				or absf(actor.anchor_x - bear.lane) <= BEAR.SIGHT_RANGE:
			return "A bullet outside the bear's sight range did not trigger retaliation."
		for tick in 6 * ticks:
			await get_tree().physics_frame
			if player_health < 100:
				break
		if bear.facing != side or player_health != 67:
			return "The bear did not turn toward and strike the distant shooter."
	return ""


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
		var scratched_parts: Array = actor.scratch_marks.keys().map(func(sprite: Sprite2D):
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
		for hit in 3:
			bear.receive_shot(head, head.global_position, Vector2(-side, 0.0))
		player_health = 100
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
