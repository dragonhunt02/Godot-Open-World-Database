#chunk_manager.gd
@tool
extends RefCounted
class_name ChunkManager

var owdb: OpenWorldDatabase
var loaded_chunks: Dictionary = {} # [Size enum] -> Set of Vector2i chunk positions

func _init(open_world_database: OpenWorldDatabase):
	owdb = open_world_database

func initialize():
	for size_enum in owdb.Size.values():
		loaded_chunks[size_enum] = {}

func clear_chunks():
	owdb.node_data_lookup_chunked.clear()

# New method: Update chunks for a specific size only
func update_chunks_for_size(size_enum, camera_chunk: Vector2i):
	if size_enum == owdb.Size.HUGE:
		_update_huge_chunks()
	else:
		_update_regular_chunks(size_enum, camera_chunk)

# Keep the old method for backward compatibility, but now it calls the new method
func update_chunks_for_camera(camera_chunk: Vector2i):
	for size_enum in owdb.Size.values():
		update_chunks_for_size(size_enum, camera_chunk)

func _update_huge_chunks():
	if not owdb.node_data_lookup_chunked.has(owdb.Size.HUGE):
		return
	
	for chunk_pos in owdb.node_data_lookup_chunked[owdb.Size.HUGE]:
		if not loaded_chunks[owdb.Size.HUGE].has(chunk_pos):
			_load_chunk_scenes(owdb.Size.HUGE, chunk_pos)
			loaded_chunks[owdb.Size.HUGE][chunk_pos] = true
func _update_regular_chunks(size_enum, camera_chunk: Vector2i):
	var load_range = owdb.get_load_range_for_size(size_enum)
	var chunk_range = _calculate_chunk_range(load_range)
	var required_chunks = _get_surrounding_chunks(camera_chunk, chunk_range)
	var current_loaded = loaded_chunks[size_enum].keys()
	
	# Load new chunks
	for chunk_pos in required_chunks:
		if not loaded_chunks[size_enum].has(chunk_pos):
			_load_chunk_scenes(size_enum, chunk_pos)
			loaded_chunks[size_enum][chunk_pos] = true
	
	# Unload old chunks
	for chunk_pos in current_loaded:
		if chunk_pos not in required_chunks:
			_unload_chunk_scenes(size_enum, chunk_pos)
			loaded_chunks[size_enum].erase(chunk_pos)

func _calculate_chunk_range(load_range: float) -> int:
	return int(ceil(load_range / owdb.chunk_size))

func _get_surrounding_chunks(center_chunk: Vector2i, range_size: int) -> Array[Vector2i]:
	var chunks: Array[Vector2i] = []
	
	for x in range(center_chunk.x - range_size, center_chunk.x + range_size + 1):
		for z in range(center_chunk.y - range_size, center_chunk.y + range_size + 1):
			chunks.append(Vector2i(x, z))
	
	return chunks

func _load_chunk_scenes(size_enum, chunk_pos: Vector2i):
	var nodes_in_chunk = _get_nodes_in_chunk(size_enum, chunk_pos)
	if nodes_in_chunk.is_empty():
		return
	
	if owdb.debug_enabled:
		print("Loading chunk ", chunk_pos, " for size ", size_enum, " with ", nodes_in_chunk.size(), " nodes")
	
	for node_data in nodes_in_chunk:
		_load_scene_from_node_data(node_data)

func _unload_chunk_scenes(size_enum, chunk_pos: Vector2i):
	var nodes_in_chunk = _get_nodes_in_chunk(size_enum, chunk_pos)
	if nodes_in_chunk.is_empty():
		return
	
	if owdb.debug_enabled:
		print("Unloading chunk ", chunk_pos, " for size ", size_enum, " with ", nodes_in_chunk.size(), " nodes")
	
	for node_data in nodes_in_chunk:
		_unload_scene_from_node_data(node_data)

func _get_nodes_in_chunk(size_enum, chunk_pos: Vector2i) -> Array:
	if not owdb.node_data_lookup_chunked.has(size_enum):
		return []
	if not owdb.node_data_lookup_chunked[size_enum].has(chunk_pos):
		return []
	
	return owdb.node_data_lookup_chunked[size_enum][chunk_pos]

func _load_scene_from_node_data(node_data: NodeData):
	print("_load_scene_from_node_data") # Check if scene is already loaded if node_monitor.is_scene_loaded(node_data.uid): print("scene already present") return
	# Load the scene
	var scene_resource = load(node_data.scene)
	if not scene_resource:
			return

	var scene_instance : Node3D = scene_resource.instantiate()
	if not scene_instance:
		return

	# Set up the node with stored data
	scene_instance.set_meta("_owd_uid", node_data.uid)
	scene_instance.name = node_data.uid
		
	# Apply custom properties
	for prop_name in node_data.properties:
		if scene_instance.has_method("set") and prop_name in scene_instance:
			scene_instance.set(prop_name, node_data.properties[prop_name])

	# Find parent or add to scene root
	var parent_node = owdb
	if node_data.parent_uid != "":
		var parent_scene = owdb.node_monitor.get_loaded_scene(node_data.parent_uid)
		if parent_scene:
			parent_node = parent_scene
		else:
			# Parent not loaded, skip loading this node for now
			scene_instance.free()
			return

	# Add to scene tree
	owdb.is_loading = true
	parent_node.add_child(scene_instance)
	scene_instance.owner = owdb.get_tree().get_edited_scene_root()
	owdb.is_loading = false


	# Apply transform
	scene_instance.global_position = node_data.position
	scene_instance.global_rotation = node_data.rotation
	scene_instance.scale = node_data.scale

	# Add to monitoring
	owdb.node_monitor.add_node_to_monitoring(scene_instance)
	owdb.node_monitor.loaded_scenes[node_data.uid] = scene_instance

	# Load children
	for child_data in node_data.children:
		_load_scene_from_node_data(child_data)

	if owdb.debug_enabled:
		print("Loaded scene: ", node_data.uid)
		

	#call_deferred("_setup_tree_monitoring", scene_instance)
	owdb.node_monitor.call_deferred("update_node_properties", scene_instance)


func _unload_scene_from_node_data(node_data: NodeData):
	var scene_node = owdb.node_monitor.get_loaded_scene(node_data.uid)
	if not scene_node:
		return

	# First unload all children
	for child_data in node_data.children:
		_unload_scene_from_node_data(child_data)

	# Update node properties before unloading to save current state
	if scene_node is Node3D:
		owdb.node_monitor.update_node_properties(scene_node)

	# Remove the problematic check - we want to unload when this function is called
	# The chunk management logic should handle when to call this function

	# Remove from monitoring and scene
	owdb.node_monitor.remove_node_from_monitoring(scene_node)
	owdb.node_monitor.loaded_scenes.erase(node_data.uid)

	owdb.is_loading = true
	scene_node.free()  # Use queue_free() instead of free() for safety
	owdb.is_loading = false

	if owdb.debug_enabled:
		print("Unloaded scene: ", node_data.uid)


func add_node_to_chunk(node_data: NodeData):
	var size_enum = owdb.get_size_enum(node_data.size)
	var chunk_pos = owdb.get_chunk_position(node_data.position)
	
	if not owdb.node_data_lookup_chunked.has(size_enum):
		owdb.node_data_lookup_chunked[size_enum] = {}
	if not owdb.node_data_lookup_chunked[size_enum].has(chunk_pos):
		owdb.node_data_lookup_chunked[size_enum][chunk_pos] = []
	
	owdb.node_data_lookup_chunked[size_enum][chunk_pos].append(node_data)

func remove_node_from_chunk(node_data: NodeData):
	for size_enum in owdb.node_data_lookup_chunked:
		for chunk_pos in owdb.node_data_lookup_chunked[size_enum]:
			var nodes = owdb.node_data_lookup_chunked[size_enum][chunk_pos]
			var index = nodes.find(node_data)
			if index != -1:
				nodes.remove_at(index)
				return

func rechunk_node(node_data: NodeData):
	remove_node_from_chunk(node_data)
	add_node_to_chunk(node_data)

func get_top_level_nodes() -> Array[NodeData]:
	var top_level_nodes: Array[NodeData] = []
	
	for size_enum in owdb.node_data_lookup_chunked:
		for chunk_pos in owdb.node_data_lookup_chunked[size_enum]:
			for node_data in owdb.node_data_lookup_chunked[size_enum][chunk_pos]:
				top_level_nodes.append(node_data)
	
	return top_level_nodes

func unload_all_chunks():
	for size_enum in owdb.Size.values():
		for chunk_pos in loaded_chunks[size_enum].keys():
			_unload_chunk_scenes(size_enum, chunk_pos)
		loaded_chunks[size_enum].clear()
