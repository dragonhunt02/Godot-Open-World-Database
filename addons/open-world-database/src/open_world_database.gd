@tool
extends Node
class_name OpenWorldDatabase

## A simplified database node for managing open world scenes with automatic chunking

signal chunk_loaded(chunk_position: Vector3i)
signal chunk_unloaded(chunk_position: Vector3i)

@export var chunk_size = 8
@export var chunk_range = 1
@export var data_directory = "owd_data"
@export var hide_loaded_chunks = true
@export var auto_chunk_new_nodes = true
@export var movement_poll_interval = 0.5  # How often to check for movement (seconds)
@export var movement_settle_time = 1.0    # How long to wait after movement stops before moving node (seconds)

var chunks_loaded: Dictionary = {}
var camera_position_current = Vector3.ZERO
var camera_chunk_current = Vector3i.ZERO
var camera: Camera3D
var scene_name: String
var chunk_scene_path: String
var tracked_nodes: Dictionary = {} # Track nodes and their last known chunk positions
var node_last_positions: Dictionary = {} # Track last known positions for movement detection
var node_movement_timers: Dictionary = {} # Track when nodes last moved
var movement_check_timer: float = 0.0

func _ready():
	if not Engine.is_editor_hint():
		return
	
	for child in get_children():
		child.free()
		
	_setup_chunking_system()
	_find_camera()
	
	# Connect to track new children
	child_entered_tree.connect(_on_child_entered_tree)
	
	# Clear any non-chunk children on startup and move them to chunks
	_process_existing_children()

func _setup_chunking_system():
	var edited_scene = get_tree().get_edited_scene_root()
	if edited_scene and edited_scene.scene_file_path != "":
		scene_name = edited_scene.scene_file_path.get_file().get_basename()
		var scene_dir = edited_scene.scene_file_path.get_base_dir()
		chunk_scene_path = scene_dir + "/" + data_directory + "/" + scene_name + "/"
		DirAccess.make_dir_recursive_absolute(chunk_scene_path)

func _find_camera():
	camera = _find_camera_recursive(get_tree().root)

func _find_camera_recursive(node: Node) -> Camera3D:
	if node is Camera3D:
		return node as Camera3D
	for child in node.get_children():
		var result = _find_camera_recursive(child)
		if result:
			return result
	return null

func _process_existing_children():
	var children_to_move = []
	for child in get_children():
		if not child.has_meta("chunk_node") and child is Node3D:
			children_to_move.append(child)
	
	for child in children_to_move:
		_move_node_to_chunk(child)

func _on_child_entered_tree(node: Node):
	# Only handle direct children that are Node3D and not chunks
	if node.get_parent() != self:
		return
	if node.has_meta("chunk_node"):
		return
	if not node is Node3D:
		return
	if not auto_chunk_new_nodes:
		return
	
	# Move to appropriate chunk
	call_deferred("_move_node_to_chunk", node)

func _ensure_unique_name(node: Node, parent: Node) -> void:
	"""Ensure the node has a unique name within its parent"""
	var original_name = node.name
	var base_name = original_name
	var counter = 1
	
	# Check if name is already unique
	if not parent.has_node(NodePath(original_name)):
		return
	
	# Find a unique name by appending numbers
	while parent.has_node(NodePath(base_name + str(counter))):
		counter += 1
	
	node.name = base_name + str(counter)



func _move_node_to_chunk(node: Node3D):
	if not node or not is_instance_valid(node):
		return
	
	if not node.is_inside_tree():
		return
	
	var chunk_position = get_chunk_position(node.global_position)
	var chunk_node = _find_or_create_chunk_with_content(chunk_position)
	
	if chunk_node and node.get_parent() == self:
		# Store global transform
		var global_transform = node.global_transform
		
		# Remove from current parent
		remove_child(node)
		
		# Ensure unique name in the chunk before adding
		_ensure_unique_name(node, chunk_node)
		
		# Move to chunk
		chunk_node.add_child(node)
		
		# Restore global transform
		call_deferred("_restore_global_transform", node, global_transform)
		
		# Set ownership
		var scene_root = get_tree().get_edited_scene_root()
		if scene_root:
			node.owner = scene_root
		
		# Track this node (only if it's a scene instance)
		if node.scene_file_path != "":
			tracked_nodes[node] = chunk_position
			call_deferred("_update_node_position_tracking", node)
			node_movement_timers[node] = 0.0


func _restore_global_transform(node: Node3D, transform: Transform3D):
	if node and is_instance_valid(node) and node.is_inside_tree():
		node.global_transform = transform

func _update_node_position_tracking(node: Node3D):
	if node and is_instance_valid(node) and node.is_inside_tree():
		node_last_positions[node] = node.global_position

func _process(delta):
	if not Engine.is_editor_hint() or not camera:
		return
		
	if camera.transform.origin != camera_position_current:
		camera_position_current = camera.transform.origin
		var new_camera_chunk = get_chunk_position(camera_position_current)
		if new_camera_chunk != camera_chunk_current:
			camera_chunk_current = new_camera_chunk
			_update_chunks()
	
	# Update movement check timer
	movement_check_timer += delta
	if movement_check_timer >= movement_poll_interval:
		movement_check_timer = 0.0
		_check_node_movements(delta)

func _check_node_movements(delta: float):
	var nodes_to_remove = []
	var nodes_to_move = []
	
	for node in tracked_nodes.keys():
		# Clean up invalid nodes
		if not is_instance_valid(node):
			nodes_to_remove.append(node)
			continue
		
		# Check if the node is still a Node3D and in the tree
		if not node is Node3D:
			nodes_to_remove.append(node)
			continue
			
		if not node.is_inside_tree():
			nodes_to_remove.append(node)
			continue
		
		# Only track scene instances (nodes with scene_file_path)
		if node.scene_file_path == "":
			nodes_to_remove.append(node)
			continue
		
		var node_3d = node as Node3D
		var current_position = node_3d.global_position
		var current_chunk = get_chunk_position(current_position)
		var last_known_chunk = tracked_nodes[node]
		
		# Check if position has changed
		var position_changed = false
		if node in node_last_positions:
			var last_position = node_last_positions[node]
			position_changed = current_position.distance_to(last_position) > 0.01
		else:
			position_changed = true
		
		# Update movement timer
		if position_changed:
			node_movement_timers[node] = 0.0  # Reset timer - node is still moving
			node_last_positions[node] = current_position
		else:
			# Node hasn't moved, increment timer
			if node in node_movement_timers:
				node_movement_timers[node] += movement_poll_interval
			else:
				node_movement_timers[node] = 0.0
		
		# Check if node has been stationary long enough AND is in a different chunk
		if current_chunk != last_known_chunk:
			if node in node_movement_timers and node_movement_timers[node] >= movement_settle_time:
				nodes_to_move.append(node)
	
	# Clean up invalid nodes
	for node in nodes_to_remove:
		_cleanup_node_tracking(node)
	
	# Process movements for nodes that have settled
	for node in nodes_to_move:
		if is_instance_valid(node) and node.is_inside_tree():
			var node_3d = node as Node3D
			var current_chunk = get_chunk_position(node_3d.global_position)
			var old_chunk = tracked_nodes[node]
			_move_node_between_chunks(node_3d, old_chunk, current_chunk)

func _cleanup_node_tracking(node: Node):
	"""Clean up tracking data for a node"""
	tracked_nodes.erase(node)
	node_last_positions.erase(node)
	node_movement_timers.erase(node)

func _move_node_between_chunks(node: Node3D, old_chunk: Vector3i, new_chunk: Vector3i):
	"""Move a node from one chunk to another"""
	
	# Safety checks
	if not node or not is_instance_valid(node):
		_cleanup_node_tracking(node)
		return
	
	if not node.is_inside_tree():
		_cleanup_node_tracking(node)
		return
	
	# Find or create the new chunk
	var new_chunk_node = _find_or_create_chunk_with_content(new_chunk)
	if not new_chunk_node:
		return
	
	# Store the current global transform
	var global_transform = node.global_transform
	var old_parent = node.get_parent()
	
	# Remove from old parent
	if old_parent and old_parent != new_chunk_node:
		old_parent.remove_child(node)
	
	# Ensure unique name in the new chunk before adding
	_ensure_unique_name(node, new_chunk_node)
	
	# Add to new chunk
	new_chunk_node.add_child(node)
	
	# Restore global transform
	call_deferred("_restore_global_transform", node, global_transform)
	
	# Set ownership
	var scene_root = get_tree().get_edited_scene_root()
	if scene_root:
		node.owner = scene_root
		# Don't recursively set ownership for scene instances - preserve their internal structure
		if node.scene_file_path == "":
			_set_owner_recursive(node, scene_root)
	
	# Update tracking
	tracked_nodes[node] = new_chunk
	call_deferred("_update_node_position_tracking", node)
	node_movement_timers[node] = 0.0  # Reset movement timer
	
	# Check if old chunk is now empty and should be cleaned up
	call_deferred("_cleanup_empty_chunk", old_chunk)


func _cleanup_empty_chunk(chunk_position: Vector3i):
	var chunk_node = _find_chunk_node(chunk_position)
	if chunk_node and chunk_node.get_child_count() == 0:
		# Check if this chunk is within range, if not, unload it
		var diff = camera_chunk_current - chunk_position
		if abs(diff.x) > chunk_range or abs(diff.y) > chunk_range or abs(diff.z) > chunk_range:
			var chunk_key = str(chunk_position)
			chunks_loaded.erase(chunk_key)
			
			# Delete the chunk file if it exists since the chunk is now empty
			_delete_chunk_file(chunk_position)
			
			chunk_node.queue_free()
			
func _delete_chunk_file(chunk_position: Vector3i):
	"""Delete the chunk file for an empty chunk"""
	var chunk_filename = _chunk_filename(chunk_position)
	var chunk_path = chunk_scene_path + chunk_filename
	
	if FileAccess.file_exists(chunk_path):
		DirAccess.remove_absolute(chunk_path)
			
func _update_chunks():
	# Load nearby chunks that have content
	for x in range(-chunk_range, chunk_range + 1):
		for y in range(-chunk_range, chunk_range + 1):
			for z in range(-chunk_range, chunk_range + 1):
				var chunk_pos = camera_chunk_current + Vector3i(x, y, z)
				_load_chunk_if_exists(chunk_pos)
	
	# Unload distant chunks
	var chunks_to_unload = []
	for chunk_key in chunks_loaded:
		var chunk_pos: Vector3i = chunks_loaded[chunk_key]
		var diff = camera_chunk_current - chunk_pos
		if abs(diff.x) > chunk_range or abs(diff.y) > chunk_range or abs(diff.z) > chunk_range:
			chunks_to_unload.append(chunk_key)
	
	for chunk_key in chunks_to_unload:
		var chunk_pos = chunks_loaded[chunk_key]
		_unload_chunk(chunk_pos)
		chunks_loaded.erase(chunk_key)

func _load_chunk_if_exists(chunk_position: Vector3i):
	var chunk_key = str(chunk_position)
	
	# Check if already loaded
	if chunk_key in chunks_loaded:
		return
	
	# Only load if chunk file exists
	var chunk_filename = _chunk_filename(chunk_position)
	var chunk_path = chunk_scene_path + chunk_filename
	
	if FileAccess.file_exists(chunk_path):
		_find_or_create_chunk(chunk_position)

func get_chunk_position(position: Vector3) -> Vector3i:
	return Vector3i(
		floor(position.x / chunk_size),
		floor(position.y / chunk_size),
		floor(position.z / chunk_size)
	)

func _chunk_filename(chunk_position: Vector3i) -> String:
	return "%d_%d_%d.tscn" % [chunk_position.x, chunk_position.y, chunk_position.z]

func _find_or_create_chunk_with_content(chunk_position: Vector3i) -> Node3D:
	"""Create a chunk only when there's content to put in it"""
	var chunk_key = str(chunk_position)
	
	# Check if already loaded
	if chunk_key in chunks_loaded:
		return _find_chunk_node(chunk_position)
	
	# Create the chunk since we have content for it
	return _find_or_create_chunk(chunk_position)

func _find_or_create_chunk(chunk_position: Vector3i) -> Node3D:
	var chunk_key = str(chunk_position)
	
	# Check if already loaded
	if chunk_key in chunks_loaded:
		return _find_chunk_node(chunk_position)
	
	# Load or create chunk
	var chunk_filename = _chunk_filename(chunk_position)
	var chunk_path = chunk_scene_path + chunk_filename
	
	var chunk_node: Node3D
	
	# Try to load existing chunk file
	if FileAccess.file_exists(chunk_path):
		var chunk_scene = load(chunk_path)
		if chunk_scene:
			chunk_node = chunk_scene.instantiate()
			
			# Track all loaded scene instances from this chunk
			call_deferred("_track_loaded_chunk_scenes", chunk_node, chunk_position)
		else:
			chunk_node = Node3D.new()
	else:
		# Create empty chunk
		chunk_node = Node3D.new()
	
	# Setup chunk node
	chunk_node.name = "chunk_%d_%d_%d" % [chunk_position.x, chunk_position.y, chunk_position.z]
	chunk_node.position = Vector3(chunk_position) * chunk_size
	chunk_node.set_meta("chunk_node", true)
	chunk_node.set_meta("chunk_position", chunk_position)
	
	if hide_loaded_chunks:
		chunk_node.visible = false
	
	# Add to scene
	add_child(chunk_node)
	
	# Set ownership
	var scene_root = get_tree().get_edited_scene_root()
	if scene_root:
		chunk_node.owner = scene_root
		_set_owner_recursive(chunk_node, scene_root)
	
	# Track the chunk
	chunks_loaded[chunk_key] = chunk_position
	
	chunk_loaded.emit(chunk_position)
	return chunk_node

func _track_loaded_chunk_scenes(chunk_node: Node3D, chunk_position: Vector3i):
	"""Track only scene instances that were loaded from a chunk file"""
	for child in chunk_node.get_children():
		if child is Node3D and child.scene_file_path != "":
			tracked_nodes[child] = chunk_position
			if child.is_inside_tree():
				node_last_positions[child] = child.global_position
			else:
				node_last_positions[child] = Vector3.ZERO
			node_movement_timers[child] = 0.0

func _unload_chunk(chunk_position: Vector3i):
	var chunk_node = _find_chunk_node(chunk_position)
	if not chunk_node:
		return
	
	# Remove tracking for scene instances in this chunk
	var nodes_to_remove = []
	for node in tracked_nodes.keys():
		if is_instance_valid(node) and node.get_parent() == chunk_node and node.scene_file_path != "":
			nodes_to_remove.append(node)
	
	for node in nodes_to_remove:
		_cleanup_node_tracking(node)
	
	# Save chunk if it has content, otherwise delete the file
	if chunk_node.get_child_count() > 0:
		_save_chunk(chunk_node, chunk_position)
	else:
		# Chunk is empty, delete the file if it exists
		_delete_chunk_file(chunk_position)
	
	# Remove chunk
	chunk_node.queue_free()
	
	chunk_unloaded.emit(chunk_position)

func _save_chunk(chunk_node: Node, chunk_position: Vector3i):
	var chunk_filename = _chunk_filename(chunk_position)
	var chunk_path = chunk_scene_path + chunk_filename
	
	# Remove old file
	if FileAccess.file_exists(chunk_path):
		DirAccess.remove_absolute(chunk_path)
	
	# Create packed scene
	var packed_scene = PackedScene.new()
	
	# Temporarily change ownership for packing
	var original_owner = chunk_node.owner
	chunk_node.owner = null
	_set_owner_recursive(chunk_node, chunk_node)
	
	# Pack and save
	var result = packed_scene.pack(chunk_node)
	if result == OK:
		ResourceSaver.save(packed_scene, chunk_path)
	
	# Restore original ownership
	chunk_node.owner = original_owner
	var scene_root = get_tree().get_edited_scene_root()
	if scene_root:
		_set_owner_recursive(chunk_node, scene_root)

func _set_owner_recursive(node: Node, owner: Node):
	for child in node.get_children():
		if child != owner:
			child.owner = owner
		# Only recurse if this child is NOT a scene instance
		if child.get_child_count() > 0 and child.scene_file_path == "":
			_set_owner_recursive(child, owner)

func _find_chunk_node(chunk_position: Vector3i) -> Node3D:
	for child in get_children():
		if child.has_meta("chunk_node") and child.get_meta("chunk_position") == chunk_position:
			return child as Node3D
	return null

## Public API

func add_scene_to_world(scene_path: String, position: Vector3) -> Node:
	"""Add a scene instance to the world at the specified position"""
	var scene_resource = load(scene_path)
	if not scene_resource:
		return null
	
	var scene_instance = scene_resource.instantiate()
	if not scene_instance is Node3D:
		scene_instance.queue_free()
		return null
	
	var scene_3d = scene_instance as Node3D
	scene_3d.position = position
	
	# Find or create appropriate chunk
	var chunk_position = get_chunk_position(position)
	var chunk_node = _find_or_create_chunk_with_content(chunk_position)
	
	if chunk_node:
		# Ensure unique name before adding to chunk
		_ensure_unique_name(scene_instance, chunk_node)
		
		chunk_node.add_child(scene_instance)
		
		# Set ownership
		var scene_root = get_tree().get_edited_scene_root()
		if scene_root:
			scene_instance.owner = scene_root
			# Don't recursively set ownership for scene instances
		
		# Track the scene instance
		tracked_nodes[scene_instance] = chunk_position
		call_deferred("_update_node_position_tracking", scene_instance)
		node_movement_timers[scene_instance] = 0.0
		
		return scene_instance
	
	return null


func remove_scene_from_world(scene_node: Node):
	"""Remove a scene instance from the world"""
	if scene_node and is_instance_valid(scene_node):
		# Stop tracking the node
		_cleanup_node_tracking(scene_node)
		
		# Check if the parent chunk will be empty after removal
		var parent_chunk = scene_node.get_parent()
		if parent_chunk and parent_chunk.has_meta("chunk_node"):
			var chunk_position = parent_chunk.get_meta("chunk_position")
			scene_node.queue_free()
			
			# Clean up empty chunk after a frame
			call_deferred("_cleanup_empty_chunk", chunk_position)
		else:
			scene_node.queue_free()

func get_loaded_chunks() -> Array[Vector3i]:
	var chunks: Array[Vector3i] = []
	for chunk_pos in chunks_loaded.values():
		chunks.append(chunk_pos)
	return chunks

func save_all_chunks():
	"""Save all currently loaded chunks"""
	for chunk_pos in chunks_loaded.values():
		var chunk_node = _find_chunk_node(chunk_pos)
		if chunk_node and chunk_node.get_child_count() > 0:
			_save_chunk(chunk_node, chunk_pos)

func set_chunks_visible(visible: bool):
	"""Show/hide all loaded chunks"""
	for child in get_children():
		if child.has_meta("chunk_node"):
			child.visible = visible

func toggle_chunk_visibility():
	"""Toggle visibility of all chunks"""
	hide_loaded_chunks = !hide_loaded_chunks
	set_chunks_visible(!hide_loaded_chunks)

## Additional utility functions for better node movement detection

func force_check_node_movements():
	"""Manually trigger a check for node movements - useful for debugging"""
	_check_node_movements(0.0)

func get_node_chunk_position(node: Node3D) -> Vector3i:
	"""Get the chunk position for a specific node"""
	if not node.is_inside_tree():
		return Vector3i.ZERO
	return get_chunk_position(node.global_position)

func is_node_tracked(node: Node) -> bool:
	"""Check if a node is being tracked by the system"""
	return node in tracked_nodes

func get_tracked_nodes_count() -> int:
	"""Get the number of nodes currently being tracked"""
	return tracked_nodes.size()

func get_node_movement_status(node: Node) -> Dictionary:
	"""Get movement status for a tracked node"""
	if not node in tracked_nodes:
		return {}
	
	var status = {
		"is_tracked": true,
		"current_chunk": tracked_nodes[node],
		"time_since_movement": node_movement_timers.get(node, 0.0),
		"is_settled": node_movement_timers.get(node, 0.0) >= movement_settle_time
	}
	
	if node is Node3D and node.is_inside_tree():
		status["actual_chunk"] = get_chunk_position(node.global_position)
		status["needs_movement"] = status["actual_chunk"] != status["current_chunk"]
	
	return status
