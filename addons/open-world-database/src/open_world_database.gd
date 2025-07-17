#open_world_database.gd
@tool
extends Node
class_name OpenWorldDatabase

enum Size { SMALL, MEDIUM, LARGE, HUGE }
@export var size_thresholds: Array[float] = [0.5, 2.0, 8.0]
@export var chunk_sizes: Array[float] = [8.0, 16.0, 64.0]
@export var chunk_load_range: int = 3
@export var center_node: Node3D
@export var debug_enabled: bool = false
@export var camera: Node

@export_tool_button("TEST", "save") var test_action = test
@export_tool_button("Save Database", "save") var save_action = save_database
@export_tool_button("Load Database", "load") var load_action = load_database

var nodes_loaded = {}

var database :Database
var chunk_manager :ChunkManager
var node_monitor : NodeMonitor
var is_loading = false

func _ready() -> void:
	NodeUtils.remove_children(self)
	
	chunk_manager = ChunkManager.new(self)
	node_monitor = NodeMonitor.new(self)
	database = Database.new(self)
	setup_listeners(self)
	
# Add this to open_world_database.gd

func _process(_delta: float) -> void:
	if chunk_manager:
		chunk_manager._update_camera_chunks()

	
func setup_listeners(node:Node):
	node.child_entered_tree.connect(_on_child_entered_tree)
	node.child_exiting_tree.connect(_on_child_exiting_tree)

func _on_child_entered_tree(node: Node):
	#if is_loading:
	#	return #track externally
	if node.scene_file_path == "":
		return #not a scene
	if !self.is_ancestor_of(node):
		return
		
	print(node.name, " entered tree of ", node.get_parent())
	if not node.has_method("get_global_position"):
		print("OpenWorldDatabase: Node does not have a position - this will not be saved!")
		return
		
	if node.has_meta("_owd_uid"):
		print("already has meta")
		nodes_loaded[node.name] = node
		print(nodes_loaded.size(), " ", nodes_loaded)
		return
		
	node.name = node.name + '-' + NodeUtils.generate_uid()
	node.set_meta("_owd_uid", node.name)
	
	nodes_loaded[node.name] = node
	print(nodes_loaded.size(), " ", nodes_loaded)
	
	#add listeners after scene has added its internal children
	call_deferred("setup_listeners", node)
	


func _on_child_exiting_tree(node: Node):
	#if is_loading:
	#	return #track externally
	if node.scene_file_path == "":
		return #not a scene
		
	print(node.name, " left tree of ", node.get_parent())
	
	nodes_loaded.erase(node.name)
	print(nodes_loaded.size(), " ", nodes_loaded)
	
func save_database():
	database.save_database()

func load_database():
	database.load_database()
	
func test():
	for node in nodes_loaded.values():
		print(node_monitor.get_properties(node))
		# for each node loaded outputs in the format:
		# { "position": (0.403813, 0.0, 0.985037), "rotation": (0.0, 0.0, 0.0), "scale": (1.0, 1.0, 1.0), "size": 0.5, "test": "woohoo" }
