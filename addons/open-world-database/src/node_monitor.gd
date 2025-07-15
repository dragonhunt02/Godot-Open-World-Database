#node_monitor.gd
@tool
extends RefCounted
class_name NodeMonitor

signal node_properties_updated(node_data: NodeData)
signal node_needs_rechunking(node_data: NodeData)

var node_data_lookup: Dictionary = {} # uid -> NodeData
var monitoring: Array[Node] = []
var baseline_properties: Dictionary = {}
var debug_enabled: bool = false
var loaded_scenes: Dictionary = {} # uid -> Node

func _init():
	# Cache baseline properties
	var baseline_node = Node3D.new()
	for property in baseline_node.get_property_list():
		baseline_properties[property.name] = true
	baseline_properties["metadata/_owd_uid"] = true
	baseline_properties["metadata/_owd_custom_properties"] = true
	baseline_properties["metadata/_owd_transform"] = true
	baseline_node.queue_free()

func update_node_properties(node: Node3D, force = false):
	var uid = node.get_meta("_owd_uid")
	if not node_data_lookup.has(uid):
		return
	
	var node_data = node_data_lookup[uid]
	var updated_properties := false
	var needs_rechunking := false
	
	# Check if parent has changed
	var current_parent = node.get_parent()
	var current_parent_uid = ""
	if current_parent and current_parent.has_meta("_owd_uid"):
		current_parent_uid = current_parent.get_meta("_owd_uid")
	
	if node_data.parent_uid != current_parent_uid:
		# Remove from old parent's children
		if node_data.parent_uid != "" and node_data_lookup.has(node_data.parent_uid):
			var old_parent_data = node_data_lookup[node_data.parent_uid]
			var index = old_parent_data.children.find(node_data)
			if index != -1:
				old_parent_data.children.remove_at(index)
		
		# Add to new parent's children
		if current_parent_uid != "" and node_data_lookup.has(current_parent_uid):
			var new_parent_data = node_data_lookup[current_parent_uid]
			new_parent_data.children.append(node_data)
		
		node_data.parent_uid = current_parent_uid
		updated_properties = true
		
		# Parent change affects chunking for top-level nodes
		if NodeUtils.is_top_level_node(node):
			needs_rechunking = true
	
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
			current_transform["size"] = NodeUtils.calculate_node_size(node)
			needs_rechunking = true  # Size change affects chunking
		else:
			current_transform["size"] = previous_transform.get("size", NodeUtils.calculate_node_size(node))
	else:
		current_transform["size"] = NodeUtils.calculate_node_size(node)
		updated_properties = true
		needs_rechunking = true
	
	if force:
		updated_properties = true
		
	# Update memory data with current transform
	if updated_properties:
		node_data.position = current_transform.position
		node_data.rotation = current_transform.rotation
		node_data.scale = current_transform.scale
		node_data.size = current_transform.size
	
	node.set_meta("_owd_transform", current_transform)
	
	# Handle custom properties
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
	
	# Emit signals for changes
	if updated_properties:
		node_properties_updated.emit(node_data)
		if debug_enabled:
			print(node.name," transform: ", current_transform, ", props: ", custom_properties)
	
	if needs_rechunking and NodeUtils.is_top_level_node(node):
		node_needs_rechunking.emit(node_data)

func add_to_memory(node: Node3D) -> NodeData:
	var node_data = NodeData.new()
	node_data.uid = node.get_meta("_owd_uid")
	node_data.scene = node.scene_file_path
	
	node_data_lookup[node_data.uid] = node_data
	
	var parent_node = node.get_parent()
	if parent_node and parent_node.has_meta("_owd_uid"):
		# Set parent_uid and add as child to parent's NodeData
		var parent_uid = parent_node.get_meta("_owd_uid")
		node_data.parent_uid = parent_uid
		
		if node_data_lookup.has(parent_uid):
			node_data_lookup[parent_uid].children.append(node_data)
	
	return node_data

func get_all_monitored_nodes() -> Array[Node]:
	return monitoring.duplicate()

func is_scene_loaded(uid: String) -> bool:
	return loaded_scenes.has(uid)

func get_loaded_scene(uid: String) -> Node:
	return loaded_scenes.get(uid, null)

func add_node_to_monitoring(node: Node):
	if not monitoring.has(node):
		monitoring.append(node)
		
		# Track loaded scenes
		if node.has_meta("_owd_uid"):
			loaded_scenes[node.get_meta("_owd_uid")] = node

func remove_node_from_monitoring(node: Node):
	var index = monitoring.find(node)
	if index != -1:
		monitoring.remove_at(index)
		
		# Remove from loaded scenes
		if node.has_meta("_owd_uid"):
			loaded_scenes.erase(node.get_meta("_owd_uid"))

func remove_from_memory(node: Node) -> NodeData:
	var uid = node.get_meta("_owd_uid")
	
	if not node_data_lookup.has(uid):
		return null
	
	var node_data = node_data_lookup[uid]
	
	# Remove from parent's children array
	if node_data.parent_uid != "" and node_data_lookup.has(node_data.parent_uid):
		var parent_data = node_data_lookup[node_data.parent_uid]
		var index = parent_data.children.find(node_data)
		if index != -1:
			parent_data.children.remove_at(index)
	
	# Update parent_uid in all children to empty (they become orphaned)
	for child in node_data.children:
		child.parent_uid = ""
	
	# Remove from node_data_lookup completely when node is removed from scene
	node_data_lookup.erase(uid)
	loaded_scenes.erase(uid)
	
	return node_data
