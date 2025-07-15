#database.gd
@tool
extends RefCounted
class_name Database

var open_world_database: OpenWorldDatabase

func _init(owdb: OpenWorldDatabase):
	open_world_database = owdb

func get_database_path() -> String:
	var scene_path = EditorInterface.get_edited_scene_root().scene_file_path
	if scene_path == "":
		return ""
	return scene_path.get_basename() + ".owdb"

func save_database():
	var db_path = get_database_path()
	if db_path == "":
		print("Error: Scene must be saved before saving database")
		return
	
	var file = FileAccess.open(db_path, FileAccess.WRITE)
	if not file:
		print("Error: Could not create database file at ", db_path)
		return
	
	print("Saving database to: ", db_path)
	
	var top_level_nodes = open_world_database.get_top_level_nodes()
	top_level_nodes.sort_custom(func(a, b): return a.uid < b.uid)
	
	for node_data in top_level_nodes:
		_write_node_recursive(file, node_data, 0)
	
	file.close()
	print("Database saved successfully!")

func _write_node_recursive(file: FileAccess, node_data: NodeData, depth: int):
	var indent = "\t".repeat(depth)
	var properties_str = "{}"
	
	if node_data.properties.size() > 0:
		properties_str = JSON.stringify(node_data.properties)
	
	var line = "%s%s|\"%s\"|%s,%s,%s|%s,%s,%s|%s,%s,%s|%s|%s" % [
		indent,
		node_data.uid,
		node_data.scene,
		node_data.position.x, node_data.position.y, node_data.position.z,
		node_data.rotation.x, node_data.rotation.y, node_data.rotation.z,
		node_data.scale.x, node_data.scale.y, node_data.scale.z,
		node_data.size,
		properties_str
	]
	
	file.store_line(line)
	
	# Sort children by UID for consistent output
	var sorted_children = node_data.children.duplicate()
	sorted_children.sort_custom(func(a, b): return a.uid < b.uid)
	
	for child in sorted_children:
		_write_node_recursive(file, child, depth + 1)


func load_database():
	var db_path = get_database_path()
	if db_path == "":
		print("Error: Scene must be saved before loading database")
		return
	
	if not FileAccess.file_exists(db_path):
		print("No database file found at ", db_path)
		return
	
	var file = FileAccess.open(db_path, FileAccess.READ)
	if not file:
		print("Error: Could not open database file at ", db_path)
		return
	
	print("Loading database from: ", db_path)
	open_world_database.is_loading = true
	
	# Clear existing data
	open_world_database.node_data_lookup_chunked.clear()
	open_world_database.node_monitor.node_data_lookup.clear()
	open_world_database.node_monitor.monitoring.clear()
	
	# Parse the file
	var node_stack: Array[NodeData] = []
	var depth_stack: Array[int] = []
	
	while not file.eof_reached():
		var line = file.get_line().strip_edges(false, true)  # Keep leading spaces
		if line == "":
			continue
		
		var depth = _get_line_depth(line)
		var clean_line = line.strip_edges()
		
		var node_data = _parse_node_line(clean_line)
		if not node_data:
			continue
		
		# Handle parent-child relationships based on indentation
		while depth_stack.size() > 0 and depth <= depth_stack[-1]:
			node_stack.pop_back()
			depth_stack.pop_back()
		
		if node_stack.size() > 0:
			var parent_data = node_stack[-1]
			node_data.parent_uid = parent_data.uid
			parent_data.children.append(node_data)
		
		node_stack.append(node_data)
		depth_stack.append(depth)
		
		# Add to node monitor
		open_world_database.node_monitor.node_data_lookup[node_data.uid] = node_data
		
		# Add top-level nodes to chunks
		if node_data.parent_uid == "":
			open_world_database.add_node_to_chunk(node_data)
	
	file.close()
	open_world_database.is_loading = false
	print("Database loaded successfully!")

func _get_line_depth(line: String) -> int:
	var depth = 0
	for i in range(line.length()):
		if line[i] == "\t":
			depth += 1
		else:
			break
	return depth

func _parse_node_line(line: String) -> NodeData:
	var parts = line.split("|")
	if parts.size() < 6:
		print("Error: Invalid line format: ", line)
		return null
	
	var node_data = NodeData.new()
	node_data.uid = parts[0]
	node_data.scene = parts[1].strip_edges().trim_prefix("\"").trim_suffix("\"")
	
	# Parse position
	var pos_parts = parts[2].split(",")
	if pos_parts.size() == 3:
		node_data.position = Vector3(
			pos_parts[0].to_float(),
			pos_parts[1].to_float(),
			pos_parts[2].to_float()
		)
	
	# Parse rotation
	var rot_parts = parts[3].split(",")
	if rot_parts.size() == 3:
		node_data.rotation = Vector3(
			rot_parts[0].to_float(),
			rot_parts[1].to_float(),
			rot_parts[2].to_float()
		)
	
	# Parse scale
	var scale_parts = parts[4].split(",")
	if scale_parts.size() == 3:
		node_data.scale = Vector3(
			scale_parts[0].to_float(),
			scale_parts[1].to_float(),
			scale_parts[2].to_float()
		)
	
	# Parse size
	node_data.size = parts[5].to_float()
	
	# Parse properties
	if parts.size() > 6 and parts[6] != "{}":
		var json = JSON.new()
		var parse_result = json.parse(parts[6])
		if parse_result == OK:
			node_data.properties = json.data
	
	return node_data
