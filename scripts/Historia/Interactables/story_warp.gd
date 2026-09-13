class_name StoryWarp
extends Area3D

## Teletransportador reutilizable. Dos instancias se vuelven bidireccionales
## asignando target_warp_path de cada una a la otra desde el Inspector.
signal warped(body: Node3D, source: StoryWarp, destination: StoryWarp)

enum TriggerMode {
	ON_ENTER,
	MANUAL_INTERACT,
	EXTERNAL_SIGNAL,
}

@export_category("Connection")
@export var target_warp_path: NodePath
@export var destination_marker_path: NodePath = NodePath("Destination")
@export var bidirectional_hint: bool = true

@export_category("Trigger")
@export var trigger_mode: TriggerMode = TriggerMode.ON_ENTER
@export var action_name: StringName = &"interact"
@export var active: bool = true
@export_range(0.1, 3.0, 0.05) var cooldown_seconds: float = 0.5

@export_category("Presentation")
@export var display_name: String = "WARP"
@export var show_debug_visual: bool = false

@export_category("Persistencia (campaña)")
## ID único dentro del nivel. Si está vacío, el warp NO se recuerda al volver
## al mapa (vuelve a su estado activo original).
@export var state_id: String = ""

@onready var debug_mesh: MeshInstance3D = $DebugMesh
@onready var prompt_label: Label3D = $PromptLabel

var _player_in_range: Player = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	debug_mesh.visible = show_debug_visual
	prompt_label.visible = false
	if not state_id.is_empty():
		LevelStateManager.register(self)
		call_deferred("_restore_persistent_state")


func _unhandled_input(event: InputEvent) -> void:
	if not active or trigger_mode != TriggerMode.MANUAL_INTERACT:
		return
	if _player_in_range == null or not is_instance_valid(_player_in_range):
		return
	if event.is_action_pressed(action_name):
		activate(_player_in_range)
		get_viewport().set_input_as_handled()


## Entrada común para un botón, una misión o un trigger externo.
func activate(body: Node3D = null) -> void:
	# Llamado sin un jugador desde StoryActionButton: habilita el portal.
	if body == null and _player_in_range == null:
		set_active(true)
		return
	if not active:
		return
	var body_to_warp: Node3D = body
	if body_to_warp == null:
		body_to_warp = _player_in_range
	if body_to_warp == null or not is_instance_valid(body_to_warp):
		return
	if not _is_player(body_to_warp) or _is_on_cooldown(body_to_warp):
		return
	var target: StoryWarp = get_node_or_null(target_warp_path) as StoryWarp
	if target == null:
		push_warning("[StoryWarp] '%s' no tiene target_warp_path válido." % name)
		return
	target.receive_teleport(body_to_warp, self)


func receive_teleport(body: Node3D, source: StoryWarp) -> void:
	if body == null or not is_instance_valid(body):
		return
	var destination: Marker3D = get_node_or_null(destination_marker_path) as Marker3D
	if destination == null:
		push_warning("[StoryWarp] '%s' no tiene Marker3D de destino." % name)
		return
	body.global_transform = destination.global_transform
	body.velocity = Vector3.ZERO
	_set_cooldown(body)
	warped.emit(body, source, self)


func set_active(enabled: bool) -> void:
	active = enabled
	monitoring = enabled
	# Defensivo: sin etiqueta en el mapa no se rompe.
	if prompt_label != null:
		prompt_label.visible = false
	if enabled and trigger_mode == TriggerMode.ON_ENTER and _player_in_range != null:
		activate(_player_in_range)


func _on_body_entered(body: Node3D) -> void:
	if not _is_player(body):
		return
	_player_in_range = body as Player
	if active and trigger_mode == TriggerMode.ON_ENTER:
		activate(body)
	elif active and trigger_mode == TriggerMode.MANUAL_INTERACT:
		prompt_label.visible = true
		prompt_label.text = "[E] %s" % display_name


func _on_body_exited(body: Node3D) -> void:
	if body == _player_in_range:
		_player_in_range = null
		prompt_label.visible = false


func _is_player(body: Node3D) -> bool:
	return body is Player or body.is_in_group(&"player")


func _is_on_cooldown(body: Node3D) -> bool:
	var expires_at: float = float(body.get_meta(&"story_warp_cooldown_until", 0.0))
	return Time.get_ticks_msec() / 1000.0 < expires_at


func _set_cooldown(body: Node3D) -> void:
	var expires_at: float = Time.get_ticks_msec() / 1000.0 + cooldown_seconds
	body.set_meta(&"story_warp_cooldown_until", expires_at)


# ── Persistencia de campaña (data-driven) ────────────────────────────────────

func _restore_persistent_state() -> void:
	var st: Dictionary = LevelStateManager.get_state_for(self, state_id)
	apply_persistent_state(st)


func get_persistent_state() -> Dictionary:
	return {"active": active}


func apply_persistent_state(state: Dictionary) -> void:
	if state.has("active"):
		set_active(bool(state["active"]))
