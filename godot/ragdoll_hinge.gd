extends PinJoint2D

var parent_body: RigidBody2D
var child_body: RigidBody2D
var lower: float
var upper: float


func configure(parent: RigidBody2D, child: RigidBody2D, limits: Vector2) -> void:
	parent_body = parent
	child_body = child
	lower = limits.x
	upper = limits.y
	global_position = child.global_position
	node_a = parent.get_path()
	node_b = child.get_path()
	disable_collision = true


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


func relative_angle() -> float:
	return angle_difference(parent_body.global_rotation, child_body.global_rotation)
