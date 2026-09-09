class_name StoryCheckpoint
extends Area3D

## Checkpoint copiable para cualquier misión. El Marker3D hijo define la posición
## segura de reaparición y se puede mover libremente desde el editor.
signal activated(checkpoint: StoryCheckpoint, player: Player)

@export var display_name: String = "CHECKPOINT"

@export_category("Persistencia (campaña)")
## ID único dentro del nivel. Si está vacío, el checkpoint NO se recuerda al
## volver al mapa (pero sigue guardando la partida al activarlo).
@export var state_id: String = ""

@onready var spawn_marker: Marker3D = $SpawnMarker
@onready var label_3d: Label3D = $Label3D

var _activated: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	label_3d.text = display_name
	if not state_id.is_empty():
		LevelStateManager.register(self)
		call_deferred("_restore_persistent_state")


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
	activated.emit(self, body as Player)
	# Autoguardado: al pasar un checkpoint capturamos el estado del nivel y
	# escribimos el autosave (user://savegames/autosave.json).
	var level_state_manager: Node = get_node_or_null("/root/LevelStateManager")
	if level_state_manager != null:
		if not state_id.is_empty() and level_state_manager.has_method("set_entity_state"):
			level_state_manager.set_entity_state(
				LevelStateManager.get_current_level_id(self), state_id, get_persistent_state())
		if level_state_manager.has_method("capture_current_level"):
			level_state_manager.capture_current_level()
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("autosave"):
		save_manager.autosave()


# ── Persistencia de campaña (data-driven) ────────────────────────────────────

func _restore_persistent_state() -> void:
	var st: Dictionary = LevelStateManager.get_state_for(self, state_id)
	apply_persistent_state(st)


## true si este checkpoint es el respawn activo guardado en GameStateSP.
func _is_active_respawn() -> bool:
	var game_state: Node = get_node_or_null("/root/GameStateSP")
	if game_state == null or spawn_marker == null:
		return false
	var pos: Vector3 = game_state.get("checkpoint_position")
	return spawn_marker.global_position.distance_to(pos) < 0.5


func get_persistent_state() -> Dictionary:
	return {"activated": _activated, "was_active_respawn": _is_active_respawn()}


func apply_persistent_state(state: Dictionary) -> void:
	if not bool(state.get("activated", false)):
		return
	_activated = true
	# Defensivo: sin etiqueta/marcador en el mapa no se rompe.
	if label_3d != null:
		label_3d.text = "%s ✓" % display_name
		label_3d.modulate = Color(0.25, 1.0, 0.4, 1.0)
	if bool(state.get("was_active_respawn", false)) and spawn_marker != null and get_tree() != null:
		var controller: StoryLevelController = get_tree().get_first_node_in_group(&"story_level_controller") as StoryLevelController
		if controller != null:
			controller.set_checkpoint(spawn_marker.global_position, false)
