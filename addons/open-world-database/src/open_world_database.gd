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

@export_group("Debug")
@export var debug_enabled: bool = false

var is_loading = false
var next_node_check : int = INF

@export_tool_button("Save Database", "save") var save_action = save_database

var database: OpenWorldDatabaseFile
var owdb_path: String
var monitoring: Array[Node] = []
var node_data_lookup: Dictionary = {} # uid -> NodeData
var node_data_lookup_chunked: Dictionary = {} # [Size enum] -> [Vector2i] -> [Array of NodeData]

# Add this as a class variable to cache baseline properties
var baseline_properties: Dictionary = {}


func _ready():
	# Cache baseline properties once
	var baseline_node = Node3D.new()
	for property in baseline_node.get_property_list():
		#if not ["global_position", "global_rotation", "scale"].has(property.name):
		baseline_properties[property.name] = true
	baseline_properties["metadata/_owd_uid"] = true
	baseline_properties["metadata/_owd_custom_properties"] = true
	baseline_properties["metadata/_owd_transform"] = true
	baseline_node.queue_free()
	#print(baseline_properties)
	deferred_child_monitoring(self)

func _process(delta: float) -> void:
	if next_node_check < Time.get_ticks_msec():
		next_node_check = Time.get_ticks_msec() + 2000
				
		for node: Node3D in monitoring:
			update_node_properties(node)

func update_node_properties(node: Node3D):
	var uid = node.get_meta("_owd_uid")
	if not node_data_lookup.has(uid):
		return
	
	var node_data = node_data_lookup[uid]
	var updated_properties := false
	var needs_rechunking := false
	
	# Handle transform data
	var current_transform := {
		"position": node.global_position,
		"rotation": node.global_rotation,
		"scale": node.scale
	}
	
	if node.has_meta("_owd_transform"):
		var previous_transform = node.get_meta("_owd_transform")
		
		# Check if transform changed
		for key in current_transform:
			if current_transform[key] != previous_transform.get(key):
				updated_properties = true
				
				# Check if position changed (needs re-chunking)
				if key == "position":
					needs_rechunking = true
				break
		
		# Only calculate size if scale changed
		if current_transform.scale != previous_transform.get("scale"):
			current_transform["size"] = _calculate_node_size(node)
			needs_rechunking = true  # Size change affects chunking
		else:
			current_transform["size"] = previous_transform.get("size", _calculate_node_size(node))
	else:
		current_transform["size"] = _calculate_node_size(node)
		updated_properties = true
		needs_rechunking = true
	
	# Update memory data with current transform
	if updated_properties:
		node_data.position = current_transform.position
		node_data.rotation = current_transform.rotation
		node_data.scale = current_transform.scale
		node_data.size = current_transform.size
	
	node.set_meta("_owd_transform", current_transform)
	
	# Handle custom properties (existing code)
	var custom_properties := {}
	
	if node.has_meta("_owd_custom_properties"):
		var previous_properties = node.get_meta("_owd_custom_properties")
		
		for prop_name in previous_properties.keys():
			var current_value = node.get(prop_name)
			var previous_value = previous_properties[prop_name]
			
			if current_value != previous_value:
				updated_properties = true
			
			custom_properties[prop_name] = current_value
	else:
		for property in node.get_property_list():
			var prop_name = property.name
			
			if baseline_properties.has(prop_name) or prop_name.begins_with("_") or not (property.usage & PROPERTY_USAGE_STORAGE):
				continue
			
			custom_properties[prop_name] = node.get(prop_name)
		
		if not custom_properties.is_empty():
			updated_properties = true
	
	if not custom_properties.is_empty():
		node.set_meta("_owd_custom_properties", custom_properties)
		node_data.properties = custom_properties
	
	# Handle re-chunking if position or size changed
	if needs_rechunking and _is_top_level_node(node):
		_rechunk_node(node_data)
	
	if updated_properties:
		print(node.name," transform: ", current_transform, ", props: ", custom_properties)

func _is_top_level_node(node: Node) -> bool:
	var parent_node = node.get_parent()
	return not (parent_node and parent_node.has_meta("_owd_uid"))

func _rechunk_node(node_data: NodeData):
	# Remove from old chunk
	var old_size_enum = _get_size_enum(node_data.size)
	var old_chunk_pos = _get_chunk_position(node_data.position)
	
	# Find and remove from old location
	for size_enum in node_data_lookup_chunked:
		for chunk_pos in node_data_lookup_chunked[size_enum]:
			var nodes = node_data_lookup_chunked[size_enum][chunk_pos]
			var index = nodes.find(node_data)
			if index != -1:
				nodes.remove_at(index)
				break
	
	# Add to new chunk
	var new_size_enum = _get_size_enum(node_data.size)
	var new_chunk_pos = _get_chunk_position(node_data.position)
	
	if not node_data_lookup_chunked.has(new_size_enum):
		node_data_lookup_chunked[new_size_enum] = {}
	if not node_data_lookup_chunked[new_size_enum].has(new_chunk_pos):
		node_data_lookup_chunked[new_size_enum][new_chunk_pos] = []
	
	node_data_lookup_chunked[new_size_enum][new_chunk_pos].append(node_data)



func deferred_child_monitoring(node:Node):
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
		#if not in node_data_lookup then needs to be re-added to node_data_lookup_chunked (must have been re-added to scene tree)
		if !node_data_lookup.has(node.get_meta("_owd_uid")):
			monitoring.append(node)
			_add_to_memory(node)
		return
	
	var uid = node.name + "-" + generate_uid()
	node.set_meta("_owd_uid", uid)
	node.name = uid
	
	if debug_enabled:
		print("Added ", node.name)
	
	monitoring.append(node)
	_add_to_memory(node)
	
	call_deferred("deferred_child_monitoring", node)
	call_deferred("update_node_properties", node)
	

func _on_child_exiting_tree(node: Node):
	if is_loading:
		return
		
	if not node.has_meta("_owd_uid"):
		return
	
	var index = monitoring.find(node)
	if index == -1:
		return
	
	monitoring.remove_at(index)
	_remove_from_memory(node)
	
	if debug_enabled:
		print("Removed ", node.name)

func update_node_data():
	print("Updating node data...")
	
	# Clear existing chunked data
	node_data_lookup_chunked.clear()
	
	# Update all node data
	for uid in node_data_lookup:
		var node_data = node_data_lookup[uid]
		var size_enum = _get_size_enum(node_data.size)
		var chunk_pos = _get_chunk_position(node_data.position)
		
		# Only add top-level nodes to chunked lookup
		var is_top_level = true
		for parent_uid in node_data_lookup:
			var parent_data = node_data_lookup[parent_uid]
			if parent_data.children.has(node_data):
				is_top_level = false
				break
		
		if is_top_level:
			if not node_data_lookup_chunked.has(size_enum):
				node_data_lookup_chunked[size_enum] = {}
			if not node_data_lookup_chunked[size_enum].has(chunk_pos):
				node_data_lookup_chunked[size_enum][chunk_pos] = []
			
			node_data_lookup_chunked[size_enum][chunk_pos].append(node_data)
	
	print("Node data updated!")

func save_database():
	print("")
	print("=== OPEN WORLD DATABASE EXPORT ===")
	print("Total Nodes: ", node_data_lookup.size())
	
	# Output all top-level nodes (nodes without parents in the database)
	var top_level_nodes: Array[NodeData] = []
	
	# Find all top-level nodes by checking node_data_lookup_chunked structure
	for size_enum in node_data_lookup_chunked:
		for chunk_pos in node_data_lookup_chunked[size_enum]:
			for node_data in node_data_lookup_chunked[size_enum][chunk_pos]:
				top_level_nodes.append(node_data)
	
	# Sort by UID for consistent output
	top_level_nodes.sort_custom(func(a, b): return a.uid < b.uid)
	
	for node_data in top_level_nodes:
		output_node_recursive(node_data, 0)
	print("=== END DATABASE EXPORT ===")
	
	# Show chunked storage structure
	print("")
	print("=== CHUNKED STORAGE STRUCTURE ===")
	
	# Sort chunk sizes for consistent output
	var sorted_sizes = node_data_lookup_chunked.keys()
	sorted_sizes.sort()
	
	for size_enum in sorted_sizes:
		print("Chunk Size: ", size_enum)
		
		# Sort chunk positions for consistent output
		var sorted_positions = node_data_lookup_chunked[size_enum].keys()
		sorted_positions.sort_custom(func(a, b): 
			if a.x != b.x: return a.x < b.x
			if a.y != b.y: return a.y < b.y
			return a.z < b.z
		)
		
		for chunk_pos in sorted_positions:
			print("  Chunk Position: ", chunk_pos)
			var nodes_in_chunk = node_data_lookup_chunked[size_enum][chunk_pos]
			
			# Sort nodes by UID for consistent output
			var sorted_nodes = nodes_in_chunk.duplicate()
			sorted_nodes.sort_custom(func(a, b): return a.uid < b.uid)
			
			for node_data in sorted_nodes:
				output_chunked_node_recursive(node_data, 4)
		print("")
	
	print("=== END CHUNKED STORAGE STRUCTURE ===")

# Add this new helper function to recursively output nodes with their children
func output_chunked_node_recursive(node_data: NodeData, indent_level: int):
	var indent = " ".repeat(indent_level)
	
	print(indent + "Node: ", node_data.uid)
	print(indent + "  Position: ", node_data.position)
	print(indent + "  Rotation: ", node_data.rotation)
	print(indent + "  Scale: ", node_data.scale)
	print(indent + "  Size: ", node_data.size)
	if node_data.properties.size() > 0:
		print(indent + "  Properties: ", node_data.properties)
	else:
		print(indent + "  Properties: (empty)")
	
	# Output children if they exist
	if node_data.children.size() > 0:
		print(indent + "  Children:")
		
		# Sort children by UID for consistent output
		var sorted_children = node_data.children.duplicate()
		sorted_children.sort_custom(func(a, b): return a.uid < b.uid)
		
		for child in sorted_children:
			output_chunked_node_recursive(child, indent_level + 4)
	
	print("")



func output_node_recursive(node_data: NodeData, depth: int):
	var indent = "\t".repeat(depth)
	var size_name = str(_get_size_enum(node_data.size))
	var chunk = _get_chunk_position(node_data.position)
	
	var line = indent + node_data.uid + ":\"" + node_data.scene + "\":" + str(node_data.position.x) + "," + str(node_data.position.y) + "," + str(node_data.position.z) + ":" + str(node_data.size) + ":" + size_name + ":" + str(chunk.x) + "," + str(chunk.y)
	
	if node_data.properties.size() > 0:
		line += ":" + str(node_data.properties)
	
	print(line)
	
	if node_data.children.size() > 0:
		# Sort children by UID for consistent output
		var sorted_children = node_data.children.duplicate()
		sorted_children.sort_custom(func(a, b): return a.uid < b.uid)
		
		for child in sorted_children:
			output_node_recursive(child, depth + 1)

	
func generate_uid() -> String:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	return str(Time.get_unix_time_from_system()).replace(".", "")+ "_" + str(rng.randi_range(1000,9999))

func _add_to_memory(node: Node3D):
	var node_data = NodeData.new()
	node_data.uid = node.get_meta("_owd_uid")
	node_data.scene = node.scene_file_path
	"""
	node_data.position = node.get_global_position()
	node_data.rotation = node.rotation
	node_data.scale = node.scale
	node_data.size = _calculate_node_size(node)
	"""
	node_data_lookup[node_data.uid] = node_data
	
	var parent_node = node.get_parent()
	if parent_node and parent_node.has_meta("_owd_uid"):
		# Add as child to parent's NodeData
		var parent_uid = parent_node.get_meta("_owd_uid")
		if node_data_lookup.has(parent_uid):
			node_data_lookup[parent_uid].children.append(node_data)
	"""
	else:
		# Add to top-level node_data_lookup_chunked structure
		var size_enum = _get_size_enum(node_data.size)
		var chunk_pos = _get_chunk_position(node_data.position)
		
		if not node_data_lookup_chunked.has(size_enum):
			node_data_lookup_chunked[size_enum] = {}
		if not node_data_lookup_chunked[size_enum].has(chunk_pos):
			node_data_lookup_chunked[size_enum][chunk_pos] = []
		
		node_data_lookup_chunked[size_enum][chunk_pos].append(node_data)
	"""

func _remove_from_memory(node: Node):
	var uid = node.get_meta("_owd_uid")
	
	if not node_data_lookup.has(uid):
		return
	
	var node_data = node_data_lookup[uid]
	var parent_node = node.get_parent()
	
	if parent_node and parent_node.has_meta("_owd_uid"):
		# Remove from parent's children array
		var parent_uid = parent_node.get_meta("_owd_uid")
		if node_data_lookup.has(parent_uid):
			var parent_data = node_data_lookup[parent_uid]
			var index = parent_data.children.find(node_data)
			if index != -1:
				parent_data.children.remove_at(index)
	else:
		# Remove from top-level node_data_lookup_chunked structure
		var size_enum = _get_size_enum(node_data.size)
		var chunk_pos = _get_chunk_position(node_data.position)
		
		if node_data_lookup_chunked.has(size_enum) and node_data_lookup_chunked[size_enum].has(chunk_pos):
			var nodes = node_data_lookup_chunked[size_enum][chunk_pos]
			var index = nodes.find(node_data)
			if index != -1:
				nodes.remove_at(index)
	
	node_data_lookup.erase(uid)
	


func _get_size_enum(size: float) -> Size:
	if size <= small_max_size:
		return Size.SMALL
	elif size <= medium_max_size:
		return Size.MEDIUM
	elif size <= large_max_size:
		return Size.LARGE
	else:
		return Size.HUGE
		
func _calculate_node_size(node: Node3D) -> float:
	var aabb = get_node_aabb(node, false)
	var size = aabb.size
	return max(size.x, max(size.y, size.z))

func _get_chunk_position(pos: Vector3) -> Vector2i:
	var chunk_size = 16.0
	return Vector2i(
		int(floor(pos.x / chunk_size)),
		int(floor(pos.z / chunk_size))
	)
	
func get_node_aabb(node : Node, exclude_top_level_transform: bool = true) -> AABB:
	var bounds : AABB = AABB()

	if node.is_queued_for_deletion():
		return bounds

	if node is VisualInstance3D:
		bounds = node.get_aabb();

	for child in node.get_children():
		var child_bounds : AABB = get_node_aabb(child, false)
		if bounds.size == Vector3.ZERO:
			bounds = child_bounds
		else:
			bounds = bounds.merge(child_bounds)

	if !exclude_top_level_transform:
		bounds = node.transform * bounds

	return bounds
	
class NodeData:
	var uid: String
	var scene: String
	var position: Vector3
	var rotation: Vector3
	var scale: Vector3
	var size: float
	var properties: Dictionary
	var children: Array[NodeData] = []
