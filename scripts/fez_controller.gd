class_name FEZController extends SubViewport

# 2D 物理空间与 3D 物理空间的尺度是不同的
const PHYSICS_WORLD_SCALE = 50

# grid
@export var grid_building: GridMap
@export var grid_body: GridMap

# characters
@export var character: CharacterBody2D
@export var mesh_instance: MeshInstance3D
@export var animated_sprite: AnimatedSprite2D
@export var collision_shape: CollisionShape2D

# camera
@export var camera: Camera3D

# 真实生效的物理世界
var worlds: Array[DirectionWorldData]
var world_current: DirectionWorldData = null:
	set(v):
		world_current = v
		self.world_2d = world_current.world_2d
		character.global_position = Utility.v2(world_current.to_local(mesh_instance.global_position))
		
var world_desire: DirectionWorldData = null:
	set(v):
		world_desire = v
		world_current = get_next_world(world_desire, 2)
		
var camera_rotate_tweener: Tween = null

func _ready() -> void:
	assert(grid_body != null)
	assert(grid_body.global_transform == Transform3D.IDENTITY)
	assert(grid_building != null)
	assert(grid_building.global_transform == Transform3D.IDENTITY)
	assert(grid_building.cell_size == grid_body.cell_size)
	assert(grid_body.cell_center_x == grid_building.cell_center_x)
	assert(grid_body.cell_center_y == grid_building.cell_center_y)
	assert(grid_body.cell_center_z == grid_building.cell_center_z)
	worlds = [
		DirectionWorldData.new(Vector3.FORWARD, grid_body, grid_building, PHYSICS_WORLD_SCALE),
		DirectionWorldData.new(Vector3.RIGHT, grid_body, grid_building, PHYSICS_WORLD_SCALE),
		DirectionWorldData.new(Vector3.BACK, grid_body, grid_building, PHYSICS_WORLD_SCALE),
		DirectionWorldData.new(Vector3.LEFT, grid_body, grid_building, PHYSICS_WORLD_SCALE),
	]
	world_desire = worlds[0]
	world_current = worlds[0]
	self.world_2d = world_current.world_2d
	character.global_position = Utility.v2(world_current.to_local(mesh_instance.global_position))
	(collision_shape.shape as RectangleShape2D).size = Vector2.ONE * PHYSICS_WORLD_SCALE
	set_camera_direction(-world_current.z_axis)

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		for world in worlds:
			world.clear_all_data()

func _process(_delta: float) -> void:
	# 处理角色在障碍物后边的情况
	if world_desire != world_current and is_character_visible():
		world_current = world_desire
	
	# 同步 2D / 3D 位置
	mesh_instance.global_position = get_position_from_physics_space()
	
	# 处理切换视角的输入
	var view_input = Input.get_axis("view_right", "view_left")
	try_set_world_desire(floori(view_input))

func _physics_process(delta):
	var SPEED = 300.0
	var JUMP_VELOCITY = -550.0
	# gravity
	if not character.is_on_floor():
		character.velocity += character.get_gravity() * delta

	# jump
	if Input.is_action_just_pressed("ui_accept") and character.is_on_floor():
		character.velocity.y = JUMP_VELOCITY
	# movement
	var input := Input.get_axis("ui_left", "ui_right")
	var reverse := 1.0 if world_desire == world_current else -1.0
	var direction := input * reverse
	if direction:
		character.velocity.x = direction * SPEED
	else:
		character.velocity.x = move_toward(character.velocity.x, 0, SPEED)
	character.move_and_slide()
	# animation
	if not character.is_on_floor():
		animated_sprite.play("JUMP")
	elif character.velocity.is_zero_approx():
		animated_sprite.play("IDLE")
	else:
		animated_sprite.play("RUN")
	# direction
	if input * animated_sprite.scale.x < 0:
		animated_sprite.scale.x = -animated_sprite.scale.x

func set_camera_direction(direction: Vector3):
	var center = Vector3(0, camera.global_position.y, 0) 
	camera.global_position = center + direction * 25
	camera.look_at(center)
	
func try_set_world_desire(offset: int):
	if offset == 0:
		return
	if camera_rotate_tweener != null and camera_rotate_tweener.is_running():
		return
		
	# 吸附到最近的平台(转动时才吸附可以避免与深度吸附的冲突)
	mesh_instance.global_position = snap_to_platform(mesh_instance.global_position)
	var new_world = get_next_world(world_desire, offset)
	
	Utility.set_node_enabled(self, false)
	Utility.set_node_enabled(character, false)

	# 相机转动动画
	var lerp_method = lerp_camera.bind(camera.global_basis.z, -new_world.z_axis)
	camera_rotate_tweener = get_tree().create_tween()
	camera_rotate_tweener.tween_method(lerp_method, 0.0, 1.0, 0.35)
	await camera_rotate_tweener.finished
	
	# 设置新的物理世界		
	world_desire = new_world
	
	# 恢复物理模拟
	Utility.set_node_enabled(self, true)
	Utility.set_node_enabled(character, true)
	
func lerp_camera(value: float, origin: Vector3, target: Vector3):
	var current = lerp(origin, target, value)
	set_camera_direction(current)

# snap method

func snap_to_platform(global_pos: Vector3) -> Vector3:
	var ground_position = global_pos + Vector3.DOWN * grid_body.cell_size.y
	var local = world_current.to_local(global_pos)
	if not is_body_cell(ground_position):
		var depth = world_current.get_visible_body_depth(ground_position)
		local.z = local.z if is_inf(depth) else depth
	return world_current.to_global(local)

func get_position_from_physics_space() -> Vector3:
	var current_depth = world_current.to_local(mesh_instance.global_position).z
	var cell_depth = abs(world_current.grid_local_size.z)
	for cornor_pos in get_cornors():
		current_depth = min(current_depth, world_current.get_visible_depth(cornor_pos) - cell_depth)
	return world_current.to_global(Utility.v3(character.global_position, current_depth))

# utility

func is_character_visible() -> bool:
	var local = world_desire.to_local(mesh_instance.global_position)
	var condition = func(pos): 
		return local.z < world_desire.get_visible_depth(pos)
	return get_cornors().all(condition)

func is_body_cell(global: Vector3) -> bool:
	var index = grid_body.local_to_map(grid_body.to_local(global))
	return GridMap.INVALID_CELL_ITEM != grid_body.get_cell_item(index)

func get_cornors() -> Array[Vector3]:
	var result:Array[Vector3] = []
	for cornor in [[1, 1], [1, -1], [-1, 1], [-1, -1]]:
		var point = mesh_instance.global_position \
			+ cornor[0] * 0.5 * world_desire.x_axis \
			+ cornor[1] * 0.5 * Vector3.UP
		result.append(point)
	return result

func get_next_world(current: DirectionWorldData, offset: int) -> DirectionWorldData:
	var current_index = worlds.find(current)
	return worlds[(current_index + offset + worlds.size()) % worlds.size()]
