#database.gd
@tool
extends RefCounted
class_name Database

var owdb: OpenWorldDatabase

func _init(open_world_database: OpenWorldDatabase):
	owdb = open_world_database

func get_database_path() -> String:
	var scene_path: String = ""
	
	if Engine.is_editor_hint():
		var edited_scene = EditorInterface.get_edited_scene_root()
		if edited_scene:
			scene_path = edited_scene.scene_file_path
	else:
		var current_scene = owdb.get_tree().current_scene
		if current_scene:
			scene_path = current_scene.scene_file_path
	
	if scene_path == "":
		return ""
		
	return scene_path.get_basename() + ".owdb"

func save_database():
	var db_path = get_database_path()
	if db_path == "":
		print("Error: Scene must be saved before saving database")
		return
	
	# First, update all currently loaded nodes and handle size/position changes
	var all_nodes = owdb.get_all_owd_nodes()
	for node in all_nodes:
		# Check for renames
		owdb.handle_node_rename(node)
		
		var uid = node.get_meta("_owd_uid", "")
		if uid == "":
			continue
			
		# Get old info for comparison
		var old_info = owdb.node_monitor.stored_nodes.get(uid, {})
		
		# Update stored node with forced size recalculation
		owdb.node_monitor.update_stored_node(node, true)
		
		# Check if node needs to be moved to different chunk
		if old_info.has("position") and old_info.has("size"):
			var new_info = owdb.node_monitor.stored_nodes[uid]
			var old_pos = old_info.position
			var old_size = old_info.size
			var new_pos = new_info.position
			var new_size = new_info.size
			
			# Check if position or size changed enough to warrant chunk reallocation
			if old_pos.distance_to(new_pos) > 0.01 or abs(old_size - new_size) > 0.01:
				# Remove from old chunk
				owdb.remove_from_chunk_lookup(uid, old_pos, old_size)
				# Add to new chunk
				owdb.add_to_chunk_lookup(uid, new_pos, new_size)
	
	var file = FileAccess.open(db_path, FileAccess.WRITE)
	if not file:
		print("Error: Could not create database file")
		return
	
	var top_level_uids = []
	for uid in owdb.node_monitor.stored_nodes:
		var info = owdb.node_monitor.stored_nodes[uid]
		if info.parent_uid == "":
			top_level_uids.append(uid)
	
	top_level_uids.sort()
	
	for uid in top_level_uids:
		_write_node_recursive(file, uid, 0)
	
	file.close()
	if owdb.debug_enabled:
		print("Database saved successfully!")

func _write_node_recursive(file: FileAccess, uid: String, depth: int):
	var info = owdb.node_monitor.stored_nodes.get(uid, {})
	if info.is_empty():
		return
	
	var indent = "\t".repeat(depth)
	var props_str = "{}"
	if info.properties.size() > 0:
		props_str = JSON.stringify(info.properties)
	
	var line = "%s%s|\"%s\"|%s,%s,%s|%s,%s,%s|%s,%s,%s|%s|%s" % [
		indent, uid, info.scene,
		info.position.x, info.position.y, info.position.z,
		info.rotation.x, info.rotation.y, info.rotation.z,
		info.scale.x, info.scale.y, info.scale.z,
		info.size, props_str
	]
	
	file.store_line(line)
	
	var child_uids = []
	for child_uid in owdb.node_monitor.stored_nodes:
		var child_info = owdb.node_monitor.stored_nodes[child_uid]
		if child_info.parent_uid == uid:
			child_uids.append(child_uid)
	
	child_uids.sort()
	for child_uid in child_uids:
		_write_node_recursive(file, child_uid, depth + 1)

func load_database():
	var db_path = get_database_path()
	if db_path == "" or not FileAccess.file_exists(db_path):
		push_error("Database path not found")
		return
	
	var file = FileAccess.open(db_path, FileAccess.READ)
	if not file:
		return
	
	owdb.node_monitor.stored_nodes.clear()
	owdb.chunk_lookup.clear()
	
	var node_stack = []
	var depth_stack = []
	
	while not file.eof_reached():
		var line = file.get_line()
		if line == "":
			continue
		
		var depth = 0
		while depth < line.length() and line[depth] == "\t":
			depth += 1
		
		var clean_line = line.strip_edges()
		var info = _parse_line(clean_line)
		if not info:
			continue
		
		while depth_stack.size() > 0 and depth <= depth_stack[-1]:
			node_stack.pop_back()
			depth_stack.pop_back()
		
		if node_stack.size() > 0:
			info.parent_uid = node_stack[-1]
		
		node_stack.append(info.uid)
		depth_stack.append(depth)
		
		owdb.node_monitor.stored_nodes[info.uid] = info
		owdb.add_to_chunk_lookup(info.uid, info.position, info.size)
	
	file.close()
	if owdb.debug_enabled:
		print("Database loaded successfully!")

func debug():
	print("")
	print("All known nodes  ", owdb.node_monitor.stored_nodes)
	print("")
	print("Chunked nodes ", owdb.chunk_lookup)
	print("")

func _parse_line(line: String) -> Dictionary:
	var parts = line.split("|")
	if parts.size() < 6:
		return {}
	
	var info = {
		"uid": parts[0],
		"scene": parts[1].strip_edges().trim_prefix("\"").trim_suffix("\""),
		"parent_uid": "",
		"position": _parse_vector3(parts[2]),
		"rotation": _parse_vector3(parts[3]),
		"scale": _parse_vector3(parts[4]),
		"size": parts[5].to_float(),
		"properties": _parse_properties(parts[6] if parts.size() > 6 else "{}")
	}
	
	return info

func _parse_vector3(vector_str: String) -> Vector3:
	var components = vector_str.split(",")
	if components.size() != 3:
		return Vector3.ZERO
	
	return Vector3(
		components[0].to_float(),
		components[1].to_float(),
		components[2].to_float()
	)

func _parse_properties(props_str: String) -> Dictionary:
	if props_str == "{}" or props_str == "":
		return {}
	
	var json = JSON.new()
	if json.parse(props_str) == OK:
		return json.data
	
	return {}
