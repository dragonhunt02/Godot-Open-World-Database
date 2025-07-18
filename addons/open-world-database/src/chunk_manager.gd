#chunk_manager.gd
@tool
extends RefCounted
class_name ChunkManager

var owdb: OpenWorldDatabase
var loaded_chunks: Dictionary = {}
var last_camera_position: Vector3

func _init(open_world_database: OpenWorldDatabase):
	owdb = open_world_database
	reset()

func reset():
	for size in OpenWorldDatabase.Size.values():
		loaded_chunks[size] = {}

func _get_camera() -> Node3D:
	if Engine.is_editor_hint():
		var viewport = EditorInterface.get_editor_viewport_3d(0)
		if viewport:
			return viewport.get_camera_3d()
	
	if owdb.camera and owdb.camera is Node3D:
		return owdb.camera
	
	return null

func _update_camera_chunks():
	var camera = _get_camera()
	if not camera:
		return
	
	var current_pos = camera.global_position
	if last_camera_position.distance_to(current_pos) < owdb.chunk_sizes[OpenWorldDatabase.Size.SMALL] * 0.1:
		return
	
	last_camera_position = current_pos
	
	# Process chunks from largest to smallest for proper hierarchy loading
	var sizes = OpenWorldDatabase.Size.values()
	sizes.reverse()
	
	for size in sizes:
		if size >= owdb.chunk_sizes.size():
			continue
		
		var chunk_size = owdb.chunk_sizes[size]
		var center_chunk = Vector2i(
			int(current_pos.x / chunk_size),
			int(current_pos.z / chunk_size)
		)
		
		var new_chunks = {}
		for x in range(-owdb.chunk_load_range, owdb.chunk_load_range + 1):
			for z in range(-owdb.chunk_load_range, owdb.chunk_load_range + 1):
				var chunk_pos = center_chunk + Vector2i(x, z)
				new_chunks[chunk_pos] = true
		
		# Unload chunks
		for chunk_pos in loaded_chunks[size]:
			if not new_chunks.has(chunk_pos):
				_unload_chunk(size, chunk_pos)
		
		# Load chunks
		for chunk_pos in new_chunks:
			if not loaded_chunks[size].has(chunk_pos):
				_load_chunk(size, chunk_pos)
		
		loaded_chunks[size] = new_chunks

func _load_chunk(size: OpenWorldDatabase.Size, chunk_pos: Vector2i):
	if not owdb.chunk_lookup.has(size) or not owdb.chunk_lookup[size].has(chunk_pos):
		return
	
	owdb.is_loading = true
	
	var node_infos = owdb.node_monitor.get_nodes_for_chunk(size, chunk_pos)
	
	# Sort by hierarchy level (parents first)
	node_infos.sort_custom(func(a, b): return a.parent_uid.length() < b.parent_uid.length())
	
	for info in node_infos:
		if not owdb.get_node_by_uid(info.uid):
			_load_node(info)
	
	owdb.is_loading = false

func _load_node(node_info: Dictionary):
	var scene = load(node_info.scene)
	var instance = scene.instantiate()
	instance.set_meta("_owd_uid", node_info.uid)
	instance.name = node_info.uid
	# Find parent
	var parent_node = null
	if node_info.parent_uid != "":
		parent_node = owdb.get_node_by_uid(node_info.parent_uid)
	
	# Add to parent or owdb
	if parent_node:
		parent_node.add_child(instance)
	else:
		owdb.add_child(instance)
	
	instance.owner = owdb.get_tree().get_edited_scene_root()
	
	# Set properties
	instance.global_position = node_info.position
	instance.global_rotation = node_info.rotation
	instance.scale = node_info.scale
	
	for prop_name in node_info.properties:
		if prop_name not in ["position", "rotation", "scale", "size"]:
			instance.set(prop_name, node_info.properties[prop_name])
	
	# Check for orphaned children and reparent them
	for child in owdb.get_children():
		if child.has_meta("_owd_uid") and child != instance:
			var child_parent_uid = owdb.node_monitor.stored_nodes.get(
				child.get_meta("_owd_uid"), {}
			).get("parent_uid", "")
			if child_parent_uid == node_info.uid:
				child.reparent(instance)

func _unload_chunk(size: OpenWorldDatabase.Size, chunk_pos: Vector2i):
	if not owdb.chunk_lookup.has(size) or not owdb.chunk_lookup[size].has(chunk_pos):
		return
	
	owdb.is_loading = true
	
	for uid in owdb.chunk_lookup[size][chunk_pos]:
		var node = owdb.get_node_by_uid(uid)
		if node:
			# Update stored data before unloading
			owdb.node_monitor.update_stored_node(node)
			node.queue_free()
	
	owdb.is_loading = false
