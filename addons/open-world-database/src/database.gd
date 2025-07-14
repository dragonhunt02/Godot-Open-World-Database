#database.gd
@tool
extends RefCounted
class_name OpenWorldDatabaseFile

var file_path: String

func init(path: String = ""):
	file_path = path

func save_memory_data(memory_data: Dictionary) -> bool:
	print(memory_data)
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		print("Error: Could not open file for writing: ", file_path)
		return false
	
	for size_enum in memory_data:
		for chunk_pos in memory_data[size_enum]:
			for node_data in memory_data[size_enum][chunk_pos]:
				_write_node_data(file, node_data)
	
	file.close()
	print("Saved database: ", file_path)
	return true

func _write_node_data(file: FileAccess, node_data: OpenWorldDatabase.NodeData) -> void:
	var line = "%s|%f,%f,%f|%f|%d\n" % [
		node_data.scene,
		node_data.position.x, node_data.position.y, node_data.position.z,
		node_data.size,
		node_data.children.size()
	]
	file.store_string(line)
	
	for child in node_data.children:
		_write_node_data(file, child)

func load_memory_data() -> Dictionary:
	var memory_data: Dictionary = {}
	
	if not FileAccess.file_exists(file_path):
		print("Database file does not exist: ", file_path)
		return memory_data
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		print("Error: Could not open file for reading: ", file_path)
		return memory_data
	
	var lines: Array[String] = []
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line != "":
			lines.append(line)
	file.close()
	
	var index = 0
	while index < lines.size():
		var node_data = _parse_node_data(lines, index)
		if node_data:
			_add_to_memory_data(memory_data, node_data)
	
	print("Loaded database: ", file_path)
	return memory_data

func _parse_node_data(lines: Array[String], index: int) -> OpenWorldDatabase.NodeData:
	if index >= lines.size():
		return null
	
	var parts = lines[index].split("|")
	if parts.size() != 4:
		return null
	
	var node_data = OpenWorldDatabase.NodeData.new()
	node_data.scene = parts[0]
	
	var pos_parts = parts[1].split(",")
	if pos_parts.size() != 3:
		return null
	node_data.position = Vector3(pos_parts[0].to_float(), pos_parts[1].to_float(), pos_parts[2].to_float())
	
	node_data.size = parts[2].to_float()
	var child_count = parts[3].to_int()
	
	# Parse children
	for i in range(child_count):
		index += 1
		var child_data = _parse_node_data(lines, index)
		if child_data:
			node_data.children.append(child_data)
	
	return node_data

func _add_to_memory_data(memory_data: Dictionary, node_data: OpenWorldDatabase.NodeData) -> void:
	var size_enum = _get_size_enum(node_data.size)
	var chunk_pos = _get_chunk_position(node_data.position)
	
	if not memory_data.has(size_enum):
		memory_data[size_enum] = {}
	if not memory_data[size_enum].has(chunk_pos):
		memory_data[size_enum][chunk_pos] = []
	
	memory_data[size_enum][chunk_pos].append(node_data)

func _get_size_enum(size: float) -> OpenWorldDatabase.Size:
	if size <= 1.0:
		return OpenWorldDatabase.Size.SMALL
	elif size <= 8.0:
		return OpenWorldDatabase.Size.MEDIUM
	elif size <= 32.0:
		return OpenWorldDatabase.Size.LARGE
	else:
		return OpenWorldDatabase.Size.HUGE

func _get_chunk_position(pos: Vector3) -> Vector2i:
	return Vector2i(int(pos.x / 16.0), int(pos.z / 16.0))
