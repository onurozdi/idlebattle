extends Node2D

const CHARACTER := preload("res://character.gd")
const LAKE := preload("res://assets/lake.webp")
const DECK_Y := 378.0

var actor: Node2D
var pad_buttons: Dictionary = {}
var deck_blocks := [
	Rect2(0, DECK_Y, 705, 24),
	Rect2(705, DECK_Y + 23, 255, 24),
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
		for control in [JOY_BUTTON_X, JOY_BUTTON_B, JOY_BUTTON_Y]:
			var key := Vector2i(pad, control)
			var down := Input.is_joy_button_pressed(pad, control)
			if down and not pad_buttons.get(key, false):
				_command({JOY_BUTTON_X: "cast", JOY_BUTTON_B: "fall", JOY_BUTTON_Y: "reset"}[control])
			pad_buttons[key] = down
	actor.advance(delta, movement)
	status.text = "Ragdoll" if actor.fallen else ("Casting" if actor.cast_time >= 0.0 else "Ready")


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_E: _command("cast")
			KEY_F: _command("fall")
			KEY_R: _command("reset")


func _command(command: String) -> void:
	match command:
		"cast": actor.cast()
		"fall": actor.fall()
		"reset": actor.reset_pose()


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
	title.text = "Soundings · Character Test"
	title.add_theme_color_override("font_color", Color("#ffd698"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	status = Label.new()
	status.custom_minimum_size.x = 80
	row.add_child(status)
	for option in [["Cast  E / X", "cast"], ["Fall  F / B", "fall"], ["Reset  R / Y", "reset"]]:
		var button := Button.new()
		button.text = option[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_command.bind(option[1]))
		row.add_child(button)


func _draw() -> void:
	draw_texture_rect(LAKE, Rect2(0, 0, 960, 540), false)
	for i in 2:
		var deck: Rect2 = deck_blocks[i]
		for x in range(int(deck.position.x) + 18, int(deck.end.x), 92):
			draw_rect(Rect2(x, deck.position.y, 10, 76), Color("#4b3429"))
			draw_rect(Rect2(x + 2, deck.position.y, 3, 75), Color("#8e6242"))
		draw_rect(deck, Color("#4e352a"))
		draw_rect(Rect2(deck.position, Vector2(deck.size.x, 10)), Color("#b8814f"))
		draw_line(deck.position, deck.position + Vector2(deck.size.x, 0), Color("#eac78b"), 2)
		for x in range(int(deck.position.x) + 11, int(deck.end.x) - 2, 25):
			draw_line(Vector2(x, deck.position.y + 2), Vector2(x, deck.position.y + 9), Color("#6e492f"))


func _self_test() -> void:
	actor.cast()
	for step in 20:
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
	for step in 145:
		await get_tree().physics_frame
	var torso: RigidBody2D = actor.parts.torso
	if torso.position.y < DECK_Y - 55.0 or torso.position.y > DECK_Y + 4.0 or torso.linear_velocity.length() > 35.0:
		push_error("Ragdoll did not settle on the deck: %s, %s" % [torso.position, torso.linear_velocity])
		get_tree().quit(1)
		return
	actor.reset_pose()
	if actor.fallen or not torso.freeze or not actor.joints.is_empty():
		push_error("Reset failed to restore animation.")
		get_tree().quit(1)
		return
	print("Character test passed: cast grip, pose handoff, linked-body fall, deck contact and reset.")
	get_tree().quit()
