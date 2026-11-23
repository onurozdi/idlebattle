extends Node2D

signal live_target_hit

const FLIGHT_SPEED := 1770.0
const SHOT_LENGTH := .74
const TRACE_LENGTH := 41.0
const HIT_LIFE := .16
const GRAVITY := Vector2(0, 84)
const MAX_SKILL := 5
const BEGINNER_SPREAD := 4.4
const EXPERT_SPREAD := .65

var rounds: Array[Dictionary] = []
var hits: Array[Dictionary] = []


static func spread_direction(direction: Vector2, skill: int, roll: float) -> Vector2:
	var proficiency := inverse_lerp(1.0, MAX_SKILL, clampi(skill, 1, MAX_SKILL))
	var max_angle := lerpf(BEGINNER_SPREAD, EXPERT_SPREAD, proficiency)
	return direction.normalized().rotated(deg_to_rad(max_angle * roll))


func shoot(muzzle: Vector2, direction: Vector2) -> void:
	rounds.append({
		"position": muzzle, "velocity": direction.normalized() * FLIGHT_SPEED,
		"age": 0.0, "origin": muzzle,
	})
	queue_redraw()


func clear() -> void:
	rounds.clear()
	hits.clear()
	queue_redraw()


func advance(delta: float) -> void:
	for i in range(rounds.size() - 1, -1, -1):
		var round: Dictionary = rounds[i]
		var from: Vector2 = round.position
		round.velocity += GRAVITY * delta
		var velocity: Vector2 = round.velocity
		var to := from + velocity * delta
		var query := PhysicsRayQueryParameters2D.create(from, to, 5)
		query.hit_from_inside = true
		var result := get_world_2d().direct_space_state.intersect_ray(query)
		if not result.is_empty():
			var body: Node2D = result.collider
			var target: Node = body.get_meta("target", null) if body.has_meta("target") else null
			var surface: Vector2 = result.position
			hits.append({"point": surface, "direction": velocity.normalized(), "age": 0.0, "target": target != null})
			if target != null and target.receive_shot(body, surface, velocity.normalized()):
				live_target_hit.emit()
			rounds.remove_at(i)
			continue
		round.position = to
		round.age += delta
		if round.age >= SHOT_LENGTH:
			rounds.remove_at(i)
	for i in range(hits.size() - 1, -1, -1):
		hits[i].age += delta
		if hits[i].age >= HIT_LIFE:
			hits.remove_at(i)
	queue_redraw()


func _draw() -> void:
	for round in rounds:
		var head: Vector2 = round.position
		var distance := head.distance_to(round.origin)
		var direction: Vector2 = round.velocity.normalized()
		var trail := head - direction * minf(TRACE_LENGTH, distance)
		draw_line(trail.round(), head.round(), Color("#c3a07588"), 1)
		draw_line(head.round() - direction * minf(14.0, distance), head.round(), Color("#f8e8ba"), 2)
		if round.age < .035:
			draw_line(round.origin, round.origin + direction * 7.0, Color("#efbe77"), 2)
	for hit in hits:
		var point: Vector2 = hit.point
		var direction: Vector2 = hit.direction
		var fraction: float = hit.age / HIT_LIFE
		var shade := Color("#a44838") if hit.target else Color("#dac1a3")
		shade.a = 1.0 - fraction
		for i in range(3):
			var offset := direction.rotated((i - 1) * .65 + PI) * (3.0 + 13.0 * fraction)
			var particle := (point + offset + Vector2(0, 7 * fraction * fraction)).round()
			draw_rect(Rect2(particle, Vector2(2, 2)), shade)
