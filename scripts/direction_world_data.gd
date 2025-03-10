
class_name DirectionWorldData extends RefCounted

# 视角变换
var VIEW_PROJECTION: Transform3D
var x_axis: Vector3:
	get: return VIEW_PROJECTION.basis.x.normalized()
var y_axis: Vector3:
	get: return VIEW_PROJECTION.basis.y.normalized()
var z_axis: Vector3:
	get: return VIEW_PROJECTION.basis.z.normalized()

var world_2d: World2D = World2D.new()

# 物理碰撞体的 RID
var physics_rids: Array[RID] = []

# 当前朝向的深度缓存
var body_depth_map: Dictionary[Vector2i, float] = {}
var building_depth_map: Dictionary[Vector2i, float] = {}

# GridMap 投影到当前方向的网格尺寸
var grid_local_size: Vector3
var grid_local_offset: Vector3

func _init(direction: Vector3, bodies: GridMap, buildings: GridMap, scale: int = 50):
	VIEW_PROJECTION = Transform3D().scaled(Vector3(scale, scale, 1.0))
	VIEW_PROJECTION *= Transform3D().looking_at(-direction, Vector3.DOWN)
	var grid_offset = Vector3(
		bodies.cell_size.x * 0.5 * int(bodies.cell_center_x),
		bodies.cell_size.y * 0.5 * int(bodies.cell_center_y),
		bodies.cell_size.z * 0.5 * int(bodies.cell_center_z)
	)
	grid_local_size = to_local(bodies.to_global(bodies.cell_size))
	grid_local_offset = to_local(bodies.to_global(grid_offset))
	rebuild_scene_collision(bodies, buildings)

func clear_all_data():
	for rid in physics_rids:
		PhysicsServer2D.free_rid(rid)
	physics_rids.clear()
	body_depth_map.clear()
	building_depth_map.clear()

func rebuild_grid_depth_buffer(map: GridMap, buffer: Dictionary[Vector2i, float]):
	for pos in map.get_used_cells():
		var local = to_local(map.to_global(map.map_to_local(pos)))
		var key = local_to_grid(local)
		buffer[key] = min(
			buffer.get(key, INF), 
			local.z
		)

func rebuild_collision_world():
	# 创建场景中静态形状的 Body
	var static_body_rid = PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_space(static_body_rid, world_2d.space)
	PhysicsServer2D.body_set_collision_layer(static_body_rid, 1)
	PhysicsServer2D.body_set_mode(static_body_rid, PhysicsServer2D.BodyMode.BODY_MODE_STATIC)
	physics_rids.append(static_body_rid)
	
	# 创建碰撞形状
	for xy_key in body_depth_map:
		if building_depth_map.get(xy_key, INF) < body_depth_map[xy_key]:
			continue
		add_collision_rectangle(static_body_rid, grid_to_local(xy_key), abs(Utility.v2(grid_local_size)) / 2.0)
	
func add_collision_rectangle(body_rid:RID, origin: Vector2, extend: Vector2):
	if not body_rid.is_valid():
		printerr("static_body_rid is invalid")
		return
	
	var shape_rid = PhysicsServer2D.rectangle_shape_create()
	physics_rids.append(shape_rid)
	PhysicsServer2D.shape_set_data(shape_rid, extend)
	PhysicsServer2D.body_add_shape(body_rid, shape_rid)
	var count = PhysicsServer2D.body_get_shape_count(body_rid)
	PhysicsServer2D.body_set_shape_transform(body_rid, count - 1, Transform2D(0, origin))
	PhysicsServer2D.body_set_shape_as_one_way_collision(body_rid, count - 1, true, 1.0)
	
func rebuild_scene_collision(bodies: GridMap, buildings: GridMap):	
	clear_all_data()
	rebuild_grid_depth_buffer(bodies, body_depth_map)
	rebuild_grid_depth_buffer(buildings, building_depth_map)
	rebuild_collision_world()
	
func local_to_grid(local: Vector3) -> Vector2i:
	var pos = Utility.v2(local / grid_local_size)
	return Vector2i(floori(pos.x), floori(pos.y))

func grid_to_local(grid: Vector2i) -> Vector2:
	return Vector2(grid) * Utility.v2(grid_local_size) + Utility.v2(grid_local_offset)

func to_local(global_pos: Vector3) -> Vector3:
	# 从全局坐标到物理世界的变换
	return VIEW_PROJECTION * global_pos

func to_global(local_pos: Vector3) -> Vector3:
	# 从物理世界到全局坐标的变换
	return VIEW_PROJECTION.affine_inverse() * local_pos
	
func get_visible_body_depth(global_pos: Vector3) -> float:
	# 获取可见的可站立平台
	var xy_key = local_to_grid(to_local(global_pos))
	var body_depth = body_depth_map.get(xy_key, INF)
	return body_depth if body_depth < building_depth_map.get(xy_key, INF) else INF

func get_visible_depth(global_pos: Vector3) -> float:
	# 获取可见的深度
	var xy_key = local_to_grid(to_local(global_pos))
	return min(
		building_depth_map.get(xy_key, INF),
		body_depth_map.get(xy_key, INF)
	)
