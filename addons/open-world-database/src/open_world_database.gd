#open_world_database.gd
@tool
extends Node
class_name OpenWorldDatabase

enum Size { SMALL, MEDIUM, LARGE, HUGE }

@export_group("Size Thresholds")
@export var small_max_size: float = 0.5
@export var medium_max_size: float = 4.0
@export var large_max_size: float = 16.0

@export_tool_button("Update Node Data", "update") var update_action = update_node_data

@export_group("Load Ranges")
@export var small_load_range: float = 16.0
@export var medium_load_range: float = 32.0
@export var large_load_range: float = 128.0

@export_group("Chunking")
@export var chunk_load_range: int = 3
@export var center_node: Node3D
var current_center_node: Node3D

@export_group("Debug")
@export var debug_enabled: bool = false

var is_loading = false
var next_node_check: int = INF

@export_tool_button("Save Database", "save") var save_action = save_database
@export_tool_button("Load Database", "load") var load_action = load_database

var owdb_path: String

# Chunk management
var node_data_lookup_chunked: Dictionary = {} # [Size enum] -> [Vector2i] -> [Array of NodeData]
var chunk_size: float = 16.0

# Component instances
var node_monitor: NodeMonitor
var database: Database

func _ready():
	_initialize_components()
	_setup_center_node()
	_connect_signals()
	call_deferred("_start_monitoring")
	call_deferred("load_database")  # Auto-load on ready

func _initialize_components():
	node_monitor = NodeMonitor.new()
	node_monitor.debug_enabled = debug_enabled
	database = Database.new(self)

func _setup_center_node():
	current_center_node = center_node
	if current_center_node == null:
		current_center_node = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()

func _connect_signals():
	node_monitor.node_properties_updated.connect(_on_node_properties_updated)
	node_monitor.node_needs_rechunking.connect(_on_node_needs_rechunking)

func _start_monitoring():
	_setup_tree_monitoring(self)

func _process(delta: float) -> void:
	if next_node_check < Time.get_ticks_msec():
		next_node_check = Time.get_ticks_msec() + 2000
		
		for node: Node3D in node_monitor.get_all_monitored_nodes():
			node_monitor.update_node_properties(node)

# Chunk management methods
func get_size_enum(size: float) -> Size:
	if size <= small_max_size:
		return Size.SMALL
	elif size <= medium_max_size:
		return Size.MEDIUM
	elif size <= large_max_size:
		return Size.LARGE
	else:
		return Size.HUGE

func get_chunk_position(pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(pos.x / chunk_size)),
		int(floor(pos.z / chunk_size))
	)

func add_node_to_chunk(node_data: NodeData):
	var size_enum = get_size_enum(node_data.size)
	var chunk_pos = get_chunk_position(node_data.position)
	
	if not node_data_lookup_chunked.has(size_enum):
		node_data_lookup_chunked[size_enum] = {}
	if not node_data_lookup_chunked[size_enum].has(chunk_pos):
		node_data_lookup_chunked[size_enum][chunk_pos] = []
	
	node_data_lookup_chunked[size_enum][chunk_pos].append(node_data)

func remove_node_from_chunk(node_data: NodeData):
	# Find and remove from old location
	for size_enum in node_data_lookup_chunked:
		for chunk_pos in node_data_lookup_chunked[size_enum]:
			var nodes = node_data_lookup_chunked[size_enum][chunk_pos]
			var index = nodes.find(node_data)
			if index != -1:
				nodes.remove_at(index)
				return

func rechunk_node(node_data: NodeData):
	remove_node_from_chunk(node_data)
	add_node_to_chunk(node_data)

func get_top_level_nodes() -> Array[NodeData]:
	var top_level_nodes: Array[NodeData] = []
	
	for size_enum in node_data_lookup_chunked:
		for chunk_pos in node_data_lookup_chunked[size_enum]:
			for node_data in node_data_lookup_chunked[size_enum][chunk_pos]:
				top_level_nodes.append(node_data)
	
	return top_level_nodes

# Tree monitoring
func _setup_tree_monitoring(node: Node):
	node.child_entered_tree.connect(_on_child_entered_tree)
	node.child_exiting_tree.connect(_on_child_exiting_tree)

func _on_child_entered_tree(node: Node):
	if is_loading:
		return
	
	if node.owner != null:
		return
		
	if node.scene_file_path == "":
		return
		
	if not node.has_method("get_global_position"):
		print("OpenWorldDatabase: Node does not have a position - this will not be saved!")
		return
		
	if node.has_meta("_owd_uid"):
		# If not in node_data_lookup then needs to be re-added (must have been re-added to scene tree)
		if not node_monitor.node_data_lookup.has(node.get_meta("_owd_uid")):
			node_monitor.add_node_to_monitoring(node)
			var node_data = node_monitor.add_to_memory(node)
			if NodeUtils.is_top_level_node(node):
				add_node_to_chunk(node_data)
		return
	
	var uid = node.name + "-" + NodeUtils.generate_uid()
	node.set_meta("_owd_uid", uid)
	node.name = uid
	
	if debug_enabled:
		print("Added ", node.name)
	
	node_monitor.add_node_to_monitoring(node)
	var node_data = node_monitor.add_to_memory(node)
	
	if NodeUtils.is_top_level_node(node):
		add_node_to_chunk(node_data)
	
	call_deferred("_setup_tree_monitoring", node)
	node_monitor.call_deferred("update_node_properties", node)

func _on_child_exiting_tree(node: Node):
	if is_loading:
		return
		
	if not node.has_meta("_owd_uid"):
		return
	
	node_monitor.remove_node_from_monitoring(node)
	var node_data = node_monitor.remove_from_memory(node)
	
	if node_data and NodeUtils.is_top_level_node(node):
		remove_node_from_chunk(node_data)
	
	if debug_enabled:
		print("Removed ", node.name)

# Signal handlers
func _on_node_properties_updated(node_data: NodeData):
	# Handle any additional logic when node properties are updated
	pass

func _on_node_needs_rechunking(node_data: NodeData):
	rechunk_node(node_data)

# Public interface methods
func update_node_data():
	print("Updating node data...")
	
	# Clear existing chunked data
	node_data_lookup_chunked.clear()
	
	# Update all node data and rebuild parent-child relationships
	for uid in node_monitor.node_data_lookup:
		var node_data = node_monitor.node_data_lookup[uid]
		
		# Clear existing children array to rebuild it
		node_data.children.clear()
		node_data.parent_uid = ""
	
	# Rebuild parent-child relationships
	for uid in node_monitor.node_data_lookup:
		var node_data = node_monitor.node_data_lookup[uid]
		
		# Find the actual node to check its parent
		var actual_node: Node = null
		for monitored_node in node_monitor.monitoring:
			if monitored_node.has_meta("_owd_uid") and monitored_node.get_meta("_owd_uid") == uid:
				actual_node = monitored_node
				break
		
		if actual_node:
			var parent_node = actual_node.get_parent()
			if parent_node and parent_node.has_meta("_owd_uid"):
				var parent_uid = parent_node.get_meta("_owd_uid")
				if node_monitor.node_data_lookup.has(parent_uid):
					node_data.parent_uid = parent_uid
					node_monitor.node_data_lookup[parent_uid].children.append(node_data)
	
	# Add only top-level nodes (those without parent_uid) to chunked lookup
	for uid in node_monitor.node_data_lookup:
		var node_data = node_monitor.node_data_lookup[uid]
		if node_data.parent_uid == "":
			add_node_to_chunk(node_data)
	
	print("Node data updated!")

# Update the save_database method:
func save_database():
	database.save_database()

# Add load_database method:
func load_database():
	database.load_database()
