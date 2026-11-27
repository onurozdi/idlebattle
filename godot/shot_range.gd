extends Node2D

signal live_target_hit

const FLIGHT_SPEED := 2655.0
const MAX_FLIGHT_DISTANCE := 1770.0 * .74
const TRACE_LENGTH := 41.0
const HIT_LIFE := .16
const GRAVITY := Vector2(0, 84)
const MAX_SKILL := 5
const BEGINNER_SPREAD := 4.4
const EXPERT_SPREAD := .65
const METRE := preload("res://world_units.gd").METRE
const FULL_DAMAGE_RANGE := 2.0 * METRE
const THIRD_DAMAGE_RANGE := 12.0 * METRE
const DAMAGE_LOSS_PER_PIXEL := (2.0 / 3.0) / (THIRD_DAMAGE_RANGE - FULL_DAMAGE_RANGE)

var rounds: Array[Dictionary] = []
var hits: Array[Dictionary] = []
var impact_rng := RandomNumberGenerator.new()


func _ready() -> void:
	impact_rng.randomize()


static func spread_direction(direction: Vector2, skill: int, roll: float, extra_spread := 0.0) -> Vector2:
	var proficiency := inverse_lerp(1.0, MAX_SKILL, clampi(skill, 1, MAX_SKILL))
	var max_angle := lerpf(BEGINNER_SPREAD, EXPERT_SPREAD, proficiency)
	return direction.normalized().rotated(deg_to_rad((max_angle + extra_spread) * roll))


static func damage_multiplier(distance: float) -> float:
	return maxf(0.0, 1.0 - maxf(0.0, distance - FULL_DAMAGE_RANGE) * DAMAGE_LOSS_PER_PIXEL)


func shoot(muzzle: Vector2, direction: Vector2, visual_scale := 1.0) -> void:
	var passed_through: Array[RID] = []
	rounds.append({
		"position": muzzle, "velocity": direction.normalized() * FLIGHT_SPEED,
		"age": 0.0, "origin": muzzle, "distance": 0.0, "passed_through": passed_through,
		"visual_scale": visual_scale,
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
		var remaining: float = MAX_FLIGHT_DISTANCE - round.distance
		var to := from + (velocity * delta).limit_length(remaining)
		var query := PhysicsRayQueryParameters2D.create(from, to, 5)
		query.hit_from_inside = true
		var passed_through: Array[RID] = round.passed_through
		query.exclude = passed_through
		var space := get_world_2d().direct_space_state
		var result := space.intersect_ray(query)
		while not result.is_empty():
			var chance: float = result.collider.get_meta("projectile_hit_chance", 1.0)
			if chance >= 1.0 or impact_rng.randf() < chance:
				break
			# The round keeps moving through all shapes on the missed animal.
			passed_through.append(result.rid)
			query.exclude = passed_through
			result = space.intersect_ray(query)
		if not result.is_empty():
			var body: Node2D = result.collider
			var target: Node = body.get_meta("target", null) if body.has_meta("target") else null
			var surface: Vector2 = result.position
			var multiplier := damage_multiplier(round.distance + from.distance_to(surface))
			hits.append({"point": surface, "direction": velocity.normalized(), "age": 0.0, "target": target != null})
			if target != null and target.receive_shot(body, surface, velocity.normalized(), multiplier):
				live_target_hit.emit()
			rounds.remove_at(i)
			continue
		round.position = to
		round.distance += from.distance_to(to)
		round.age += delta
		if round.distance >= MAX_FLIGHT_DISTANCE - .001:
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
		var size: float = round.visual_scale
		var trail := head - direction * minf(TRACE_LENGTH * size, distance)
		draw_line(trail.round(), head.round(), Color("#c3a07588"), size)
		draw_line(head.round() - direction * minf(14.0 * size, distance), head.round(), Color("#f8e8ba"), 2 * size)
		if round.age < .035:
			draw_line(round.origin, round.origin + direction * 7.0 * size, Color("#efbe77"), 2 * size)
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
