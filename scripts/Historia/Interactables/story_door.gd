class_name StoryDoor
extends Node3D

## Puerta reutilizable para Historia. Se configura íntegramente desde el Inspector.
## Los modos MANUAL, AUTOMATIC y EXTERNAL permiten ampliar la campaña sin
## alterar este script.
signal opened(door: StoryDoor)
signal closed(door: StoryDoor)
signal interaction_available(door: StoryDoor, available: bool)

enum TriggerMode {
	MANUAL_INTERACT,
	AUTOMATIC_ON_ENTER,
	EXTERNAL_SIGNAL,
}

@export_category("Trigger")
@export var trigger_mode: TriggerMode = TriggerMode.MANUAL_INTERACT
@export var action_name: StringName = &"interact"
@export var starts_open: bool = false
@export var auto_close_delay: float = 0.0
@export var require_player: bool = true

@export_category("Motion")
@export_range(0.05, 5.0, 0.05) var animation_duration: float = 0.45
@export_range(-180.0, 180.0, 1.0) var open_angle_degrees: float = 90.0

@export_category("Presentation")
@export var display_name: String = "PUERTA"
@export var show_prompt: bool = true

@export_category("NPC (apertura automática)")
## Si true, los NPCs de Historia (grupo "npc") pueden abrir esta puerta
## automáticamente al pasar por ella. Solo la abren si van EN MOVIMIENTO
## (navegando hacia su destino); un guardia quieto no la abre. Funciona en
## cualquier trigger_mode (manual, automático o externo).
@export var npc_openable: bool = true
## Segundos que tarda en cerrarse tras el último NPC que pasó. 0 = cerrar en
## cuanto el NPC sale del área de la puerta.
@export_range(0.0, 10.0, 0.25) var npc_auto_close_delay: float = 0.0

@export_category("Persistencia (campaña)")
## ID único dentro del nivel. Si está vacío, la puerta NO participa en la
## persistencia de campaña (se reinicia al volver al mapa, como antes).
@export var state_id: String = ""

@onready var door_pivot: Node3D = $DoorPivot
@onready var door_collision: CollisionShape3D = $DoorPivot/DoorBody/CollisionShape3D
@onready var interaction_area: Area3D = $InteractionArea
@onready var auto_close_timer: Timer = $AutoCloseTimer
@onready var npc_close_timer: Timer = $NpcCloseTimer
@onready var prompt_label: Label3D = $PromptLabel

var is_open: bool = false
var _player_in_range: Player = null
var _door_tween: Tween = null
## true cuando la puerta la abrió un NPC (para no cerrar una abierta por el jugador).
var _opened_by_npc: bool = false
var _npc_check_accum: float = 0.0
const NPC_CHECK_INTERVAL: float = 0.2


func _ready() -> void:
	interaction_area.body_entered.connect(_on_interaction_body_entered)
	interaction_area.body_exited.connect(_on_interaction_body_exited)
	auto_close_timer.timeout.connect(_on_auto_close_timer_timeout)
	npc_close_timer.timeout.connect(_on_npc_close_timer_timeout)
	set_open(starts_open, true)
	_update_prompt()
	if not state_id.is_empty():
		LevelStateManager.register(self)
		call_deferred("_restore_persistent_state")


func _unhandled_input(event: InputEvent) -> void:
	if trigger_mode != TriggerMode.MANUAL_INTERACT:
		return
	if _player_in_range == null or not is_instance_valid(_player_in_range):
		return
	if event.is_action_pressed(action_name):
		toggle()
		get_viewport().set_input_as_handled()


## ── Apertura automática por NPCs ──────────────────────────────────────────
## Los NPCs de Historia pueden abrir la puerta al pasar. Se evalúa cada poco
## tiempo mientras el área tiene cuerpos: si hay un NPC en movimiento dentro
## del área, la puerta se abre (y se mantiene abierta mientras pasa); cuando
## el último NPC sale, se cierra (con npc_auto_close_delay si se configuró).
## Una puerta abierta por el JUGADOR no se fuerza a cerrar.

func _physics_process(delta: float) -> void:
	if not npc_openable:
		return
	_npc_check_accum += delta
	if _npc_check_accum < NPC_CHECK_INTERVAL:
		return
	_npc_check_accum = 0.0
	_evaluate_npc_passage()


func _evaluate_npc_passage() -> void:
	var has_moving_npc: bool = false
	for body: Node3D in interaction_area.get_overlapping_bodies():
		if _is_npc(body) and _npc_is_moving(body):
			has_moving_npc = true
			break
	if has_moving_npc:
		npc_close_timer.stop()
		if not is_open:
			_opened_by_npc = true
			set_open(true)
	elif _opened_by_npc:
		# El jugador sigue dentro: no cerrar una puerta que podría necesitar.
		if _player_in_range != null:
			return
		_opened_by_npc = false
		if npc_auto_close_delay > 0.0:
			npc_close_timer.start(npc_auto_close_delay)
		else:
			set_open(false)


func _is_npc(body: Node3D) -> bool:
	return body != null and body.is_in_group(&"npc")


func _npc_is_moving(body: Node3D) -> bool:
	var cb: CharacterBody3D = body as CharacterBody3D
	if cb == null:
		return false
	return cb.velocity.length() > 0.25


func _on_npc_close_timer_timeout() -> void:
	set_open(false)


## Punto de entrada para StoryActionButton, cinemáticas y futuros objetivos.
func activate() -> void:
	set_open(true)


func deactivate() -> void:
	set_open(false)


func toggle() -> void:
	set_open(not is_open)


func set_open(open: bool, instant: bool = false) -> void:
	if is_open == open and not instant:
		return
	is_open = open
	if _door_tween != null and _door_tween.is_valid():
		_door_tween.kill()
	var target_angle: float = deg_to_rad(open_angle_degrees) if open else 0.0
	if instant:
		door_pivot.rotation.y = target_angle
	else:
		_door_tween = create_tween()
		_door_tween.set_trans(Tween.TRANS_SINE)
		_door_tween.set_ease(Tween.EASE_IN_OUT)
		_door_tween.tween_property(door_pivot, "rotation:y", target_angle, animation_duration)
	if door_collision != null:
		door_collision.set_deferred("disabled", open)
	if open:
		opened.emit(self)
		if auto_close_delay > 0.0:
			auto_close_timer.start(auto_close_delay)
	else:
		closed.emit(self)
	_update_prompt()


func _on_interaction_body_entered(body: Node3D) -> void:
	if not _is_valid_player(body):
		return
	_player_in_range = body as Player
	if trigger_mode == TriggerMode.AUTOMATIC_ON_ENTER:
		set_open(true)
	_update_prompt()


func _on_interaction_body_exited(body: Node3D) -> void:
	if body == _player_in_range:
		_player_in_range = null
		if trigger_mode == TriggerMode.AUTOMATIC_ON_ENTER and auto_close_delay > 0.0:
			auto_close_timer.start(auto_close_delay)
	_update_prompt()


func _on_auto_close_timer_timeout() -> void:
	set_open(false)


func _is_valid_player(body: Node3D) -> bool:
	if not require_player:
		return true
	return body is Player or body.is_in_group(&"player")


func _update_prompt() -> void:
	if prompt_label == null:
		return
	var can_interact: bool = trigger_mode == TriggerMode.MANUAL_INTERACT and _player_in_range != null
	prompt_label.visible = show_prompt and can_interact
	if can_interact:
		prompt_label.text = "[E] %s" % ("CERRAR " + display_name if is_open else "ABRIR " + display_name)
	interaction_available.emit(self, can_interact)


# ── Persistencia de campaña (data-driven) ────────────────────────────────────
# Contrato: register + _restore_persistent_state + get_persistent_state +
# apply_persistent_state (ver LevelStateManager).

## Restaura la puerta sin arrancar el temporizador de cierre automático
## (al volver al mapa una puerta abierta debe seguir abierta).
func _restore_open(open: bool) -> void:
	is_open = open
	if _door_tween != null and _door_tween.is_valid():
		_door_tween.kill()
	# Defensivo: en un mapa sin nodo visual de pivote (o durante restauración
	# temprana) no se rompe; el estado booleano se conserva igualmente.
	if door_pivot != null:
		door_pivot.rotation.y = deg_to_rad(open_angle_degrees) if open else 0.0
	if door_collision != null:
		door_collision.set_deferred("disabled", open)
	if open:
		opened.emit(self)
	else:
		closed.emit(self)
	_update_prompt()


func _restore_persistent_state() -> void:
	var st: Dictionary = LevelStateManager.get_state_for(self, state_id)
	if st.has("open"):
		_restore_open(bool(st["open"]))


func get_persistent_state() -> Dictionary:
	return {"open": is_open}


func apply_persistent_state(state: Dictionary) -> void:
	if state.has("open"):
		_restore_open(bool(state["open"]))
