extends Node2D


static func attach(art: Node2D, world_point: Vector2, incoming: Vector2) -> Node2D:
	var mark := new()
	art.add_child(mark)
	# Nudge into the silhouette so the mark remains legible at the edge of a collider.
	mark.position = art.to_local(world_point + incoming.normalized() * 3.0)
	mark.rotation = incoming.angle() - art.global_rotation
	mark.z_index = 12
	return mark


func _draw() -> void:
	draw_rect(Rect2(-3, -2, 6, 4), Color("#872d26"))
	draw_rect(Rect2(-2, -1, 4, 2), Color("#291417"))
	draw_rect(Rect2(-2, 1, 2, 1), Color("#c45f43"))
