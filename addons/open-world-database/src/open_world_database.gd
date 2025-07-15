#open_world_database.gd
@tool
extends Node
class_name OpenWorldDatabase

enum Size { SMALL, MEDIUM, LARGE, HUGE }

@export var small_max_size: float = 0.5
@export var medium_max_size: float = 2.0
@export var large_max_size: float = 8.0

@export var small_load_range: float = 8.0
@export var medium_load_range: float = 16.0
@export var large_load_range: float = 64.0

@export var chunk_load_range: int = 3
@export var center_node: Node3D
@export var chunk_size: float = 16.0

@export_tool_button("Save Database", "save") var save_action = save_database
@export_tool_button("Load Database", "load") var load_action = load_database

@export_group("Debug")
@export var debug_enabled: bool = false

var is_loading = false
var next_node_check: int = INF

var current_center_node: Node3D
var current_camera_position: Vector3
var last_camera_chunk: Vector2i

# Track last update position for each size
var last_update_positions: Dictionary = {} # [Size enum] -> Vector3

# Chunk management
var chunk_manager: ChunkManager
var node_data_lookup_chunked: Dictionary = {} # [Size enum] -> [Vector2i] -> [Array of NodeData]

# Component instances
var node_monitor: NodeMonitor
var database: Database

# Size/Range mapping - centralized configuration
var size_config = {
	Size.SMALL: { "max_size": small_max_size, "load_range": small_load_range },
	Size.MEDIUM: { "max_size": medium_max_size, "load_range": medium_load_range },
	Size.LARGE: { "max_size": large_max_size, "load_range": large_load_range },
	Size.HUGE: { "max_size": INF, "load_range": 0.0 }
}

func _ready():
	# Clean up any existing children
	for child in get_children():
		child.free()
	
	# Initialize components
	node_monitor = NodeMonitor.new()
	node_monitor.debug_enabled = debug_enabled
	database = Database.new(self)
	chunk_manager = ChunkManager.new(self)
	
	# Set up center node (camera or specified node)
	current_center_node = center_node
	if current_center_node == null:
		current_center_node = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	
	# Connect signals
	node_monitor.node_properties_updated.connect(_on_node_properties_updated)
	node_monitor.node_needs_rechunking.connect(_on_node_needs_rechunking)
	
	load_database()
	
	# Initialize chunk system
	chunk_manager.initialize()
	if current_center_node:
		current_camera_position = current_center_node.global_position
		last_camera_chunk = get_chunk_position(current_camera_position)
		
		# Initialize last update positions for each size
		for size_enum in Size.values():
			last_update_positions[size_enum] = current_camera_position
	
	# Start monitoring the scene tree
	call_deferred("_start_monitoring")

func _start_monitoring():
	# Set up tree monitoring for the root node
	child_entered_tree.connect(_on_child_entered_tree)
	child_exiting_tree.connect(_on_child_exiting_tree)

func _process(delta: float) -> void:
	# Update monitored nodes periodically
	if next_node_check >= Time.get_ticks_msec():
		return
		
	next_node_check = Time.get_ticks_msec() + 2000
	for node: Node3D in node_monitor.get_all_monitored_nodes():
		node_monitor.update_node_properties(node)
	
	# Update camera chunks based on individual size load ranges
	if not current_center_node:
		return
		
	var new_camera_position = current_center_node.global_position
	var new_camera_chunk = get_chunk_position(new_camera_position)
	
	# Always update current position and chunk
	current_camera_position = new_camera_position
	last_camera_chunk = new_camera_chunk
	
	# Check each size individually based on its load_range
	for size_enum in Size.values():
		var load_range = get_load_range_for_size(size_enum)
		
		# Skip HUGE size as it has no load_range concept
		if size_enum == Size.HUGE:
			continue
			
		var last_pos = last_update_positions[size_enum]
		var distance_moved = current_camera_position.distance_to(last_pos)
		
		if distance_moved >= load_range:
			if debug_enabled:
				print("Updating chunks for size ", size_enum, " - moved ", distance_moved, " units (threshold: ", load_range, ")")
			
			chunk_manager.update_chunks_for_size(size_enum, last_camera_chunk)
			last_update_positions[size_enum] = current_camera_position
	
	# Always update HUGE chunks (they don't have distance-based loading)
	chunk_manager.update_chunks_for_size(Size.HUGE, last_camera_chunk)

# Rest of your existing code remains the same...
# [Include all the other functions from your original code]

# Centralized size/range utilities
func get_size_enum(size: float) -> Size:
	for size_enum in [Size.SMALL, Size.MEDIUM, Size.LARGE]:
		if size <= size_config[size_enum].max_size:
			return size_enum
	return Size.HUGE

func get_load_range_for_size(size_enum: Size) -> float:
	return size_config[size_enum].load_range

func get_chunk_position(pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(pos.x / chunk_size)),
		int(floor(pos.z / chunk_size))
	)

# Chunk management delegation
func add_node_to_chunk(node_data: NodeData):
	chunk_manager.add_node_to_chunk(node_data)

func remove_node_from_chunk(node_data: NodeData):
	chunk_manager.remove_node_from_chunk(node_data)

func rechunk_node(node_data: NodeData):
	chunk_manager.rechunk_node(node_data)

func get_top_level_nodes() -> Array[NodeData]:
	return chunk_manager.get_top_level_nodes()

# Property change handling - simplified
func _set(property: StringName, value):
	var chunk_affecting_properties = ["chunk_load_range", "small_max_size", "medium_max_size", "large_max_size"]
	
	if property in chunk_affecting_properties:
		var old_value = get(property)
		set(property, value)
		if old_value != value:
			_update_size_config()
			call_deferred("_on_chunk_settings_changed")
		return true
	
	return false

func _update_size_config():
	size_config[Size.SMALL].max_size = small_max_size
	size_config[Size.MEDIUM].max_size = medium_max_size
	size_config[Size.LARGE].max_size = large_max_size
	size_config[Size.SMALL].load_range = small_load_range
	size_config[Size.MEDIUM].load_range = medium_load_range
	size_config[Size.LARGE].load_range = large_load_range

func _on_chunk_settings_changed():
	if debug_enabled:
		print("Chunk settings changed - reloading all chunks")
	
	chunk_manager.unload_all_chunks()
	if current_center_node:
		# Reset all last update positions
		for size_enum in Size.values():
			last_update_positions[size_enum] = current_camera_position
		
		# Force update all chunks
		for size_enum in Size.values():
			chunk_manager.update_chunks_for_size(size_enum, last_camera_chunk)

# [Include all your other existing functions like _on_child_entered_tree, etc.]


func _on_child_entered_tree(node: Node):
	if is_loading or node.scene_file_path == "":
		return
		
	if not node.has_method("get_global_position"):
		print("OpenWorldDatabase: Node does not have a position - this will not be saved!")
		return
	
	if node.has_meta("_owd_uid"):
		print("has meta")
		# Handle existing node being re-added to scene
		if not node_monitor.node_data_lookup.has(node.get_meta("_owd_uid")):
			node_monitor.add_node_to_monitoring(node)
			var node_data = node_monitor.add_to_memory(node)
			if NodeUtils.is_top_level_node(node):
				add_node_to_chunk(node_data)
		print("update_node_properties")
		node_monitor.update_node_properties(node, true)
	else:
		print("does not have meta")
		# Handle new node
		var uid = node.name + "-" + NodeUtils.generate_uid()
		node.set_meta("_owd_uid", uid)
		node.name = uid
		
		if debug_enabled:
			print("Added ", node.name)
		
		node_monitor.add_node_to_monitoring(node)
		var node_data = node_monitor.add_to_memory(node)
		
		if NodeUtils.is_top_level_node(node):
			add_node_to_chunk(node_data)
		
		# Set up monitoring for this node's children
		call_deferred("_setup_tree_monitoring", node)
		node_monitor.call_deferred("update_node_properties", node)

func _setup_tree_monitoring(node: Node):
	node.child_entered_tree.connect(_on_child_entered_tree)
	node.child_exiting_tree.connect(_on_child_exiting_tree)

func _on_child_exiting_tree(node: Node):
	if is_loading or not node.has_meta("_owd_uid"):
		return
	
	node_monitor.remove_node_from_monitoring(node)
	var node_data = node_monitor.remove_from_memory(node)
	
	if node_data and NodeUtils.is_top_level_node(node):
		remove_node_from_chunk(node_data)
	
	if debug_enabled:
		print("Removed ", node.name)

# Signal handlers
func _on_node_properties_updated(node_data: NodeData):
	pass

func _on_node_needs_rechunking(node_data: NodeData):
	rechunk_node(node_data)

func save_database():
	database.save_database()

func load_database():
	database.load_database()
