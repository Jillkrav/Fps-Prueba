class_name StoryDoor
extends Node3D

## Puerta reutilizable para Historia. Se configura íntegramente desde el Inspector.
## Los modos EXTERNAL y CLEAR_AREA permiten ampliar la campaña sin alterar este script.
signal opened(door: StoryDoor)
signal closed(door: StoryDoor)
signal interaction_available(door: StoryDoor, available: bool)

enum TriggerMode {
	MANUAL_INTERACT,
	AUTOMATIC_ON_ENTER,
	EXTERNAL_SIGNAL,
	CLEAR_AREA,
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

@onready var door_pivot: Node3D = $DoorPivot
@onready var door_collision: CollisionShape3D = $DoorPivot/DoorBody/CollisionShape3D
@onready var interaction_area: Area3D = $InteractionArea
@onready var enemy_watch_area: Area3D = $EnemyWatchArea
@onready var auto_close_timer: Timer = $AutoCloseTimer
@onready var prompt_label: Label3D = $PromptLabel

var is_open: bool = false
var _player_in_range: Player = null
var _door_tween: Tween = null


func _ready() -> void:
	interaction_area.body_entered.connect(_on_interaction_body_entered)
	interaction_area.body_exited.connect(_on_interaction_body_exited)
	enemy_watch_area.body_entered.connect(_on_enemy_watch_body_changed)
	enemy_watch_area.body_exited.connect(_on_enemy_watch_body_changed)
	auto_close_timer.timeout.connect(_on_auto_close_timer_timeout)
	enemy_watch_area.monitoring = trigger_mode == TriggerMode.CLEAR_AREA
	set_open(starts_open, true)
	call_deferred("_refresh_clear_area_state")
	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if trigger_mode != TriggerMode.MANUAL_INTERACT:
		return
	if _player_in_range == null or not is_instance_valid(_player_in_range):
		return
	if event.is_action_pressed(action_name):
		toggle()
		get_viewport().set_input_as_handled()


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


func _on_enemy_watch_body_changed(_body: Node3D) -> void:
	if trigger_mode == TriggerMode.CLEAR_AREA:
		call_deferred("_refresh_clear_area_state")


func _refresh_clear_area_state() -> void:
	if trigger_mode != TriggerMode.CLEAR_AREA:
		return
	var enemies_present: bool = false
	for body: Node3D in enemy_watch_area.get_overlapping_bodies():
		if body.is_in_group(&"story_enemy") and body.get("is_dead") != true:
			enemies_present = true
			break
	set_open(not enemies_present)


func _on_auto_close_timer_timeout() -> void:
	if trigger_mode == TriggerMode.CLEAR_AREA:
		return
	set_open(false)


func _is_valid_player(body: Node3D) -> bool:
	if not require_player:
		return true
	return body is Player or body.is_in_group(&"player")


func _update_prompt() -> void:
	if prompt_label == null:
		return
	var can_interact: bool = trigger_mode == TriggerMode.MANUAL_INTERACT and _player_in_range != null
	prompt_label.visible = show_prompt and (can_interact or trigger_mode == TriggerMode.CLEAR_AREA)
	if trigger_mode == TriggerMode.CLEAR_AREA:
		prompt_label.text = "%s: %s" % [display_name, "ABIERTO" if is_open else "ELIMINA ENEMIGOS"]
	elif can_interact:
		prompt_label.text = "[E] %s" % ("CERRAR " + display_name if is_open else "ABRIR " + display_name)
	interaction_available.emit(self, can_interact)
