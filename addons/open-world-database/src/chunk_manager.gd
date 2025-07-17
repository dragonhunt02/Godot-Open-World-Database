#chunk_manager.gd
@tool
extends RefCounted
class_name ChunkManager

var owdb: OpenWorldDatabase
var loaded_chunks: Dictionary = {} # [Size enum] -> Set of Vector2i chunk positions
var last_camera_position: Vector3
var camera_ref: Node3D

func _init(open_world_database: OpenWorldDatabase):
	owdb = open_world_database
	
	# Initialize loaded chunks for each size
	for size in OpenWorldDatabase.Size.values():
		loaded_chunks[size] = {}
	
	# Start checking camera position
	_update_camera_chunks()

func _update_camera_chunks():
	var camera = _get_camera()
	if not camera:
		return
		
	var current_pos = camera.global_position
	
	# Check if camera moved enough to warrant chunk update
	if last_camera_position.distance_to(current_pos) < owdb.chunk_sizes[OpenWorldDatabase.Size.SMALL] * 0.1:
		return
		
	last_camera_position = current_pos
	
	# Check chunks for each size
	for size in OpenWorldDatabase.Size.values():
		if size >= owdb.chunk_sizes.size():
			continue
			
		var chunk_size = owdb.chunk_sizes[size]
		var load_range = owdb.chunk_load_range
		
		# Calculate current chunk position
		var center_chunk = Vector2i(
			int(current_pos.x / chunk_size),
			int(current_pos.z / chunk_size)
		)
		
		# Get chunks that should be loaded
		var new_chunks = {}
		for x in range(-load_range, load_range + 1):
			for z in range(-load_range, load_range + 1):
				var chunk_pos = center_chunk + Vector2i(x, z)
				new_chunks[chunk_pos] = true
		
		# Find chunks to unload (in old but not in new)
		for chunk_pos in loaded_chunks[size]:
			if not new_chunks.has(chunk_pos):
				_on_chunk_exit(size, chunk_pos)
		
		# Find chunks to load (in new but not in old)
		for chunk_pos in new_chunks:
			if not loaded_chunks[size].has(chunk_pos):
				_on_chunk_enter(size, chunk_pos)
		
		# Update loaded chunks
		loaded_chunks[size] = new_chunks

func _get_camera() -> Node3D:
	# In editor, use viewport camera
	if Engine.is_editor_hint():
		var viewport = EditorInterface.get_editor_viewport_3d(0)
		if viewport:
			return viewport.get_camera_3d()
	
	# In game, use assigned camera node
	if owdb.camera and owdb.camera is Node3D:
		return owdb.camera
		
	return null

func _on_chunk_enter(size: OpenWorldDatabase.Size, chunk_pos: Vector2i):
	var size_name = _get_size_name(size)
	print("Entering %s %s chunk: %s" % [size, size_name, chunk_pos])

func _on_chunk_exit(size: OpenWorldDatabase.Size, chunk_pos: Vector2i):
	var size_name = _get_size_name(size)
	print("Leaving  %s %s chunk: %s" % [size, size_name, chunk_pos])

func _get_size_name(size: OpenWorldDatabase.Size) -> String:
	match size:
		OpenWorldDatabase.Size.SMALL:
			return "SMALL"
		OpenWorldDatabase.Size.MEDIUM:
			return "MEDIUM"
		OpenWorldDatabase.Size.LARGE:
			return "LARGE"
		OpenWorldDatabase.Size.HUGE:
			return "HUGE"
		_:
			return "UNKNOWN"
