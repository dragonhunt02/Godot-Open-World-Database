#node_data.gd
@tool
extends Resource
class_name NodeData

@export var uid: String
@export var scene: String
@export var position: Vector3
@export var rotation: Vector3
@export var scale: Vector3
@export var size: float
@export var properties: Dictionary
@export var children: Array[NodeData] = []
@export var parent_uid: String = "" #if the parent does not exist, don't load this #if a node exists at this path when loading, add this node as a child of it

func _init():
	pass
