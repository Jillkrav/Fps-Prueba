class_name StoryCheckpoint
extends Area3D

## Checkpoint copiable para cualquier misión. El Marker3D hijo define la posición
## segura de reaparición y se puede mover libremente desde el editor.
@export var display_name: String = "CHECKPOINT"

@onready var spawn_marker: Marker3D = $SpawnMarker
@onready var label_3d: Label3D = $Label3D

var _activated: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	label_3d.text = display_name


func _on_body_entered(body: Node3D) -> void:
	if _activated or not (body is Player or body.is_in_group(&"player")):
		return
	var controller: StoryLevelController = get_tree().get_first_node_in_group(&"story_level_controller") as StoryLevelController
	if controller == null:
		return
	controller.set_checkpoint(spawn_marker.global_position)
	_activated = true
	label_3d.text = "%s ✓" % display_name
	label_3d.modulate = Color(0.25, 1.0, 0.4, 1.0)
