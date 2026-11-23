extends PinJoint2D

var parent_body: RigidBody2D
var child_body: RigidBody2D
var parent_art: Node2D
var child_art: Node2D
var parent_socket: Vector2
var lower: float
var upper: float


func configure(parent: RigidBody2D, child: RigidBody2D, limits: Vector2) -> void:
	parent_body = parent
	child_body = child
	parent_art = parent.get_node("Art")
	child_art = child.get_node("Art")
	parent_socket = parent.to_local(child.global_position)
	lower = limits.x
	upper = limits.y
	global_position = child.global_position
	node_a = parent.get_path()
	node_b = child.get_path()
	disable_collision = true


func sync_art() -> void:
	# Use the same socket for both sprites even while contact forces stretch the pin.
	child_art.global_position = parent_art.to_global(parent_socket)
	child_art.global_rotation = parent_art.global_rotation + clampf(relative_angle(), lower, upper)


func enforce(delta: float) -> void:
	# Predict the next local angle. The joint is free to move within its arc.
	var current := relative_angle()
	var speed := child_body.angular_velocity - parent_body.angular_velocity
	var allowed := clampf(current, lower, upper)
	if absf(allowed - current) > .055:
		# Resolve strong contact overshoot at the child pivot without moving the joint.
		child_body.global_rotation = parent_body.global_rotation + allowed
		if (current - allowed) * speed > 0.0:
			child_body.angular_velocity = parent_body.angular_velocity
			speed = 0.0
		current = allowed
	var next_angle := current + speed * delta
	var cushion := minf(absf(speed) * delta * 2.0, .16)
	var min_angle := lower + cushion if speed < 0.0 else lower
	var max_angle := upper - cushion if speed > 0.0 else upper
	var bounded := clampf(next_angle, min_angle, max_angle)
	motor_target_velocity = clampf((bounded - current) / delta, -30.0, 30.0)
	var needs_stop := not is_equal_approx(bounded, next_angle)
	if motor_enabled != needs_stop:
		motor_enabled = needs_stop

	# Project large pin errors gradually so collisions still control the body.
	var pin_error := parent_body.to_global(parent_socket) - child_body.global_position
	if pin_error.length_squared() > 4.0:
		child_body.global_position += pin_error.limit_length(2.5) * .55


func relative_angle() -> float:
	return angle_difference(parent_body.global_rotation, child_body.global_rotation)
