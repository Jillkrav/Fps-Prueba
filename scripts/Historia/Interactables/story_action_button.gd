class_name StoryActionButton
extends Area3D

## Botón reutilizable para abrir puertas, activar warps o disparar futuros
## objetos de misión. Arrastra nodos al array Target Nodes en el Inspector.
signal activated(button: StoryActionButton)

enum TriggerMode {
	MANUAL_INTERACT,
	AUTOMATIC_ON_ENTER,
}

@export_category("Trigger")
@export var trigger_mode: TriggerMode = TriggerMode.MANUAL_INTERACT
@export var action_name: StringName = &"interact"
@export var one_shot: bool = false

@export_category("Targets")
@export var target_nodes: Array[NodePath] = []
@export var target_method: StringName = &"activate"

@export_category("Presentation")
@export var display_name: String = "BOTÓN"

@export_category("Persistencia (campaña)")
## ID único dentro del nivel. Si está vacío, el botón NO participa en la
## persistencia de campaña (se reinicia al volver al mapa).
@export var state_id: String = ""

@onready var prompt_label: Label3D = $PromptLabel
@onready var button_mesh: MeshInstance3D = $ButtonMesh

var _player_in_range: Player = null
var _used: bool = false
var _tint_material: StandardMaterial3D = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	prompt_label.visible = false
	_setup_tint_material()
	if not state_id.is_empty():
		LevelStateManager.register(self)
		call_deferred("_restore_persistent_state")


## El botón usa MeshInstance3D (sin 'modulate', propiedad 2D). Para marcarlo como
## activado teñimos su material override con un StandardMaterial3D duplicado.
func _setup_tint_material() -> void:
	if button_mesh.material_override is StandardMaterial3D:
		_tint_material = (button_mesh.material_override as StandardMaterial3D).duplicate()
		button_mesh.material_override = _tint_material


func _unhandled_input(event: InputEvent) -> void:
	if _used and one_shot:
		return
	if trigger_mode != TriggerMode.MANUAL_INTERACT or _player_in_range == null:
		return
	if event.is_action_pressed(action_name):
		activate()
		get_viewport().set_input_as_handled()


func activate() -> void:
	if _used and one_shot:
		return
	for target_path: NodePath in target_nodes:
		var target: Node = get_node_or_null(target_path)
		if target != null and target.has_method(target_method):
			target.call(target_method)
	_used = true
	if _tint_material != null:
		_tint_material.albedo_color = Color(0.25, 1.0, 0.35)
	prompt_label.text = "%s ACTIVADO" % display_name
	prompt_label.visible = true
	activated.emit(self)


func _on_body_entered(body: Node3D) -> void:
	if not (body is Player or body.is_in_group(&"player")):
		return
	_player_in_range = body as Player
	if trigger_mode == TriggerMode.AUTOMATIC_ON_ENTER:
		activate()
	else:
		prompt_label.text = "[E] %s" % display_name
		prompt_label.visible = true


func _on_body_exited(body: Node3D) -> void:
	if body == _player_in_range:
		_player_in_range = null
		if not _used:
			prompt_label.visible = false


# ── Persistencia de campaña (data-driven) ────────────────────────────────────

## Marca el botón como ya usado (visual) y lo deja sin prompt.
func _mark_used_visual() -> void:
	_used = true
	if _tint_material != null:
		_tint_material.albedo_color = Color(0.25, 1.0, 0.35)
	# Defensivo: sin etiqueta en el mapa no se rompe (el estado se conserva).
	if prompt_label != null:
		prompt_label.text = "%s ACTIVADO" % display_name
		prompt_label.visible = true


func _restore_persistent_state() -> void:
	var st: Dictionary = LevelStateManager.get_state_for(self, state_id)
	if bool(st.get("used", false)):
		_mark_used_visual()


func get_persistent_state() -> Dictionary:
	return {"used": _used}


func apply_persistent_state(state: Dictionary) -> void:
	if bool(state.get("used", false)):
		_mark_used_visual()
