#node_monitor.gd
@tool
extends RefCounted
class_name NodeMonitor

var owdb: OpenWorldDatabase
var stored_nodes: Dictionary = {} # uid -> node info
var baseline_props: Array = []

func _init(open_world_database: OpenWorldDatabase):
	owdb = open_world_database
	
	# Get custom properties
	var baseline_node = Node3D.new()
	baseline_props = []
	for prop in baseline_node.get_property_list():
		baseline_props.append(prop.name)
	baseline_props.append("metadata/_owd_uid")
	baseline_props.append("metadata/_owd_last_scale")
	baseline_props.append("metadata/_owd_last_size")
	baseline_node.free()
	
func create_node_info(node: Node) -> Dictionary:
	var info = {
		"uid": node.get_meta("_owd_uid", ""),
		"scene": _get_node_source(node),
		"position": Vector3.ZERO,
		"rotation": Vector3.ZERO,
		"scale": Vector3.ONE,
		"size": NodeUtils.calculate_node_size(node),
		"parent_uid": "",
		"properties": {}
	}
	
	# Only set 3D properties if node is Node3D
	if node is Node3D:
		info.position = node.global_position
		info.rotation = node.global_rotation
		info.scale = node.scale
	
	# Get parent UID
	var parent = node.get_parent()
	if parent and parent.has_meta("_owd_uid"):
		info.parent_uid = parent.get_meta("_owd_uid")
	
	for prop in node.get_property_list():
		if prop.name not in baseline_props and not prop.name.begins_with("_") \
		   and (prop.usage & PROPERTY_USAGE_STORAGE):
			info.properties[prop.name] = node.get(prop.name)
	
	return info

func _get_node_source(node: Node) -> String:
	# If node has scene_file_path, use it (instantiated from scene)
	if node.scene_file_path != "":
		return node.scene_file_path
	# Otherwise, use the class name (created from script/built-in type)
	return node.get_class()

func update_stored_node(node: Node):
	var uid = node.get_meta("_owd_uid", "")
	if uid:
		stored_nodes[uid] = create_node_info(node)

func store_node_hierarchy(node: Node):
	update_stored_node(node)
	for child in node.get_children():
		if child.has_meta("_owd_uid"):
			store_node_hierarchy(child)

func get_nodes_for_chunk(size: OpenWorldDatabase.Size, chunk_pos: Vector2i) -> Array:
	var nodes = []
	if owdb.chunk_lookup.has(size) and owdb.chunk_lookup[size].has(chunk_pos):
		for uid in owdb.chunk_lookup[size][chunk_pos]:
			if stored_nodes.has(uid):
				nodes.append(stored_nodes[uid])
	return nodes
