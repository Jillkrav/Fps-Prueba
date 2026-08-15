class_name StoryExit
extends Area3D

## Final reutilizable de una misión. Puede exigir que no queden enemigos
## de Historia antes de permitir la transición configurada por el controlador.
@export var require_all_enemies_defeated: bool = true
@export var display_name: String = "SALIDA"

@onready var status_label: Label3D = $StatusLabel


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_update_label()


func _on_body_entered(body: Node3D) -> void:
	if not (body is Player or body.is_in_group(&"player")):
		return
	var controller: Node = get_tree().get_first_node_in_group(&"story_level_controller")
	if controller == null or not controller.has_method("request_level_complete"):
		push_warning("[StoryExit] No se encontró StoryLevelController.")
		return
	controller.call("request_level_complete", self)


func _update_label() -> void:
	status_label.text = "%s%s" % [display_name, "\nELIMINA ENEMIGOS" if require_all_enemies_defeated else ""]
