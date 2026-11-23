extends Node2D

const CHARACTER := preload("res://character.gd")
const DEER := preload("res://deer.gd")
const SHOT_RANGE := preload("res://shot_range.gd")
const LAKE := preload("res://assets/lake.webp")
const DECK_Y := 378.0

var actor: Node2D
var deer: Node2D
var shot_range: Node2D
var pad_buttons: Dictionary = {}
var aim_point := Vector2(650, 315)
var fire_pending := false
var shot_cooldown := 0.0
var deck_blocks := [
	Rect2(0, DECK_Y, 960, 162),
	Rect2(-20, 205, 20, 260),
	Rect2(960, 205, 20, 260),
]
var status: Label


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
	deer = DEER.new()
	add_child(deer)
	shot_range = SHOT_RANGE.new()
	shot_range.z_index = 15
	add_child(shot_range)
	_make_controls()
	if "--self-test" in OS.get_cmdline_user_args():
		_self_test.call_deferred()


func _physics_process(delta: float) -> void:
	var movement := float(Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D))
	movement -= float(Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A))
	for pad: int in Input.get_connected_joypads():
		var axis := Input.get_joy_axis(pad, JOY_AXIS_LEFT_X)
		if absf(axis) > .22:
			movement = axis
		var look := Vector2(Input.get_joy_axis(pad, JOY_AXIS_RIGHT_X), Input.get_joy_axis(pad, JOY_AXIS_RIGHT_Y))
		if look.length() > .26:
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
	actor.advance(delta, movement)
	deer.advance(delta)
	shot_cooldown = maxf(0.0, shot_cooldown - delta)
	if fire_pending:
		fire_pending = false
		if not actor.fallen and actor.cast_time < 0.0 and shot_cooldown <= 0.0:
			_fire()
	shot_range.advance(delta)
	status.text = "Ragdoll" if actor.fallen else ("Casting" if actor.cast_time >= 0.0 else ("Deer down" if deer.fallen else "Aim"))
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		aim_point = get_global_mouse_position()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		aim_point = get_global_mouse_position()
		_command("fire")
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_E: _command("cast")
			KEY_F: _command("fall")
			KEY_R: _command("reset")
			KEY_SPACE: _command("fire")


func _command(command: String) -> void:
	match command:
		"cast": actor.cast()
		"fall": actor.fall()
		"fire":
			actor.cast_has_line = false
			fire_pending = true
		"reset":
			actor.reset_pose()
			deer.reset_pose()
			shot_range.clear()
			shot_cooldown = 0.0


func _fire() -> void:
	var gun: Node2D = actor.weapon
	var muzzle: Node2D = actor.muzzle
	shot_range.shoot(muzzle.global_position, Vector2.RIGHT.rotated(gun.global_rotation))
	actor.recoil = .16
	shot_cooldown = .24


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
	title.text = "Soundings · Shooting Test"
	title.add_theme_color_override("font_color", Color("#ffd698"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	status = Label.new()
	status.custom_minimum_size.x = 80
	row.add_child(status)
	for option in [["Shoot  Space / RT", "fire"], ["Cast  E / X", "cast"], ["Fall  F / B", "fall"], ["Reset  R / Y", "reset"]]:
		var button := Button.new()
		button.text = option[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_command.bind(option[1]))
		row.add_child(button)


func _draw() -> void:
	draw_texture_rect(LAKE, Rect2(0, 0, 960, 540), false)
	var deck: Rect2 = deck_blocks[0]
	for x in range(18, 960, 92):
		draw_rect(Rect2(x, DECK_Y, 10, 76), Color("#4b3429"))
		draw_rect(Rect2(x + 2, DECK_Y, 3, 75), Color("#8e6242"))
	draw_rect(Rect2(deck.position, Vector2(deck.size.x, 24)), Color("#4e352a"))
	draw_rect(Rect2(deck.position, Vector2(deck.size.x, 10)), Color("#b8814f"))
	draw_line(deck.position, deck.position + Vector2(deck.size.x, 0), Color("#eac78b"), 2)
	for x in range(11, 958, 25):
		draw_line(Vector2(x, DECK_Y + 2), Vector2(x, DECK_Y + 9), Color("#6e492f"))
	if actor != null and not actor.fallen and actor.weapon.visible:
		var at := aim_point.round()
		var color := Color("#f1dab1")
		for axis in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
			draw_line(at + axis * 5, at + axis * 9, Color("#152129"), 3)
			draw_line(at + axis * 5, at + axis * 9, color, 1)


func _self_test() -> void:
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
	aim_point = deer.parts.body.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	_fire()
	if deer.fallen or shot_range.rounds.size() != 1:
		push_error("The projectile skipped its flight.")
		get_tree().quit(1)
		return
	for tick in 23 * ticks:
		await get_tree().physics_frame
	if not deer.fallen or deer.marks.size() != 1 or deer.joints.size() != deer.parts.size() - 1:
		push_error("The shot did not attach a mark and activate the animal ragdoll.")
		get_tree().quit(1)
		return
	var mark: Node2D = deer.marks[0]
	var original_offset := mark.position
	var original_world := mark.global_position
	for frame in 115:
		await get_tree().process_frame
		for joint in deer.joints:
			if joint.relative_angle() < joint.lower - .20 or joint.relative_angle() > joint.upper + .20:
				push_error("Ragdoll hinge exceeded its working arc: %s %s %s" % [joint.node_b, joint.relative_angle(), Vector2(joint.lower, joint.upper)])
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
	if deer.fallen or not deer.marks.is_empty() or not deer.joints.is_empty():
		push_error("Reset did not clean up the animal ragdoll.")
		get_tree().quit(1)
		return
	shot_range.shoot(Vector2(470, 345), Vector2.DOWN)
	for tick in 5 * ticks:
		await get_tree().physics_frame
	if shot_range.hits.is_empty() or shot_range.hits[0].target or deer.fallen:
		push_error("A projectile hitting the deck must stop without damaging the deer.")
		get_tree().quit(1)
		return
	print("Shooting test passed: casting, projectile travel and floor collision, persistent local entry mark, constrained animal ragdoll and reset.")
	get_tree().quit()
