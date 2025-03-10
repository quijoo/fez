class_name Utility extends RefCounted

static func v2(value: Vector3) -> Vector2:
	return Vector2(value.x, value.y)

static func v2i(value: Vector3) -> Vector2i:
	return Vector2i(roundi(value.x), roundi(value.y))

static func v3(xy:Vector2, z: float = 0) -> Vector3:
	return Vector3(xy.x, xy.y, z)

static func set_node_enabled(node: Node, enable: bool):
	node.set_process(enable)
	node.set_process_input(enable)
	node.set_process_internal(enable)
	node.set_process_unhandled_input(enable)
	node.set_process_unhandled_key_input(enable)
	node.set_physics_process(enable)
	node.set_physics_process_internal(enable)

static func debug_draw_polyline(polyline:Array[Vector3], color: Color):
	for index in range(polyline.size()):
		DebugDraw3D.draw_line(polyline[index], polyline[(index + 1) % polyline.size()], color)
