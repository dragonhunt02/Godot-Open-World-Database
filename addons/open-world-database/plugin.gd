@tool
extends EditorPlugin

func _enter_tree():
	add_custom_type("OpenWorldDatabase", "Node", preload("src/open_world_database.gd"), preload("icon.png"))

func _exit_tree():
	remove_custom_type("OpenWorldDatabase")
