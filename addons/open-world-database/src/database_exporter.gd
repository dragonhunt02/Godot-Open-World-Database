#database_exporter.gd
@tool
extends RefCounted
class_name DatabaseExporter

var database: OpenWorldDatabase

func _init(db: OpenWorldDatabase):
	database = db

func save_database():
	print("")
	print("=== OPEN WORLD DATABASE EXPORT ===")
	print("Total Nodes: ", database.node_monitor.node_data_lookup.size())
	
	var top_level_nodes = database.get_top_level_nodes()
	
	# Sort by UID for consistent output
	top_level_nodes.sort_custom(func(a, b): return a.uid < b.uid)
	
	for node_data in top_level_nodes:
		_output_node_recursive(node_data, 0)
	print("=== END DATABASE EXPORT ===")
	
	_output_chunked_structure()

func _output_chunked_structure():
	print("")
	print("=== CHUNKED STORAGE STRUCTURE ===")
	
	# Sort chunk sizes for consistent output
	var sorted_sizes = database.node_data_lookup_chunked.keys()
	sorted_sizes.sort()
	
	for size_enum in sorted_sizes:
		print("Chunk Size: ", size_enum)
		
		# Sort chunk positions for consistent output
		var sorted_positions = database.node_data_lookup_chunked[size_enum].keys()
		sorted_positions.sort_custom(func(a, b): 
			if a.x != b.x: return a.x < b.x
			if a.y != b.y: return a.y < b.y
			return a.z < b.z
		)
		
		for chunk_pos in sorted_positions:
			print("  Chunk Position: ", chunk_pos)
			var nodes_in_chunk = database.node_data_lookup_chunked[size_enum][chunk_pos]
			
			# Sort nodes by UID for consistent output
			var sorted_nodes = nodes_in_chunk.duplicate()
			sorted_nodes.sort_custom(func(a, b): return a.uid < b.uid)
			
			for node_data in sorted_nodes:
				_output_chunked_node_recursive(node_data, 4)
		print("")
	
	print("=== END CHUNKED STORAGE STRUCTURE ===")

func _output_chunked_node_recursive(node_data: NodeData, indent_level: int):
	var indent = " ".repeat(indent_level)
	
	print(indent + "Node: ", node_data.uid)
	print(indent + "  Position: ", node_data.position)
	print(indent + "  Rotation: ", node_data.rotation)
	print(indent + "  Scale: ", node_data.scale)
	print(indent + "  Size: ", node_data.size)
	print(indent + "  Parent UID: ", node_data.parent_uid if node_data.parent_uid != "" else "(none)")
	if node_data.properties.size() > 0:
		print(indent + "  Properties: ", node_data.properties)
	else:
		print(indent + "  Properties: (empty)")
	
	# Output children if they exist
	if node_data.children.size() > 0:
		print(indent + "  Children:")
		
		# Sort children by UID for consistent output
		var sorted_children = node_data.children.duplicate()
		sorted_children.sort_custom(func(a, b): return a.uid < b.uid)
		
		for child in sorted_children:
			_output_chunked_node_recursive(child, indent_level + 4)
	
	print("")

func _output_node_recursive(node_data: NodeData, depth: int):
	var indent = "\t".repeat(depth)
	var size_name = str(database.get_size_enum(node_data.size))
	var chunk = database.get_chunk_position(node_data.position)
	
	var line = indent + node_data.uid + ":\"" + node_data.scene + "\":" + str(node_data.position.x) + "," + str(node_data.position.y) + "," + str(node_data.position.z) + ":" + str(node_data.size) + ":" + size_name + ":" + str(chunk.x) + "," + str(chunk.y)
	
	# Add parent UID info
	if node_data.parent_uid != "":
		line += ":parent=" + node_data.parent_uid
	
	if node_data.properties.size() > 0:
		line += ":" + str(node_data.properties)
	
	print(line)
	
	if node_data.children.size() > 0:
		# Sort children by UID for consistent output
		var sorted_children = node_data.children.duplicate()
		sorted_children.sort_custom(func(a, b): return a.uid < b.uid)
		
		for child in sorted_children:
			_output_node_recursive(child, depth + 1)
