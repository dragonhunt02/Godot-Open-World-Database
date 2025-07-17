#node_monitor.gd
@tool
extends RefCounted
class_name NodeMonitor

signal node_properties_updated(node_data: NodeData)
signal node_needs_rechunking(node_data: NodeData)

var owdb: OpenWorldDatabase

var node_data_lookup: Dictionary = {} # uid -> NodeData
var monitoring: Array[Node] = []
var baseline_properties: Array[String] = []
var debug_enabled: bool = false
var loaded_scenes: Dictionary = {} # uid -> Node

func _init(open_world_database: OpenWorldDatabase):
	owdb = open_world_database
	# Cache baseline properties
	var baseline_node = Node3D.new()
	for property in baseline_node.get_property_list():
		baseline_properties.append(property.name)
	baseline_properties.append("metadata/_owd_uid")
	baseline_properties.append("metadata/_owd_custom_properties")
	baseline_properties.append("metadata/_owd_transform")
	baseline_node.queue_free()

func get_properties(node: Node3D) -> Dictionary:
	var properties := {}
	
	# Core transform properties
	properties["position"] = node.global_position
	properties["rotation"] = node.global_rotation
	properties["scale"] = node.scale
	properties["size"] = NodeUtils.calculate_node_size(node)
	
	# Custom properties (excluding baseline properties)
	for property in node.get_property_list():
		var prop_name = property.name
		
		# Skip baseline properties, private properties, and non-storage properties
		if baseline_properties.has(prop_name) or prop_name.begins_with("_") or not (property.usage & PROPERTY_USAGE_STORAGE):
			continue
		
		properties[prop_name] = node.get(prop_name)
	
	return properties
