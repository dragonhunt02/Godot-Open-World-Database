@tool

extends Node3D

@export var test : String = "Change me"
@onready var child:Node3D = get_child(0)
func _process(delta: float) -> void:
	child.position.y = sin(child.position.x + child.position.z + Time.get_ticks_msec() * 0.0025) * 0.25
	#child.rotation.y = sin(child.position.x + child.position.z + Time.get_ticks_msec() * 0.005)
