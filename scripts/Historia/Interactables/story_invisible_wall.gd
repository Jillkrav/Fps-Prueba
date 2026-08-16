class_name StoryInvisibleWall
extends Area3D

## Pared invisible reutilizable (Historia). Funciona como gatillo genérico:
## al cruzarla llama "action_on_enter" sobre cada nodo destino (p. ej.
## "activate" para abrir una StoryDoor o encender un StoryWarp) y, al salir,
## llama "action_on_exit" (p. ej. "deactivate" para cerrarla/apagarla).
##
## Sirve para CUALQUIER elemento actual o futuro que exponga métodos públicos
## (activate / deactivate / toggle / set_active / un método propio). Y a su
## vez la propia pared es un objetivo más: puede activarse/desactivarse desde
## un StoryActionButton u otro trigger usando la misma interfaz estándar.
signal triggered(wall: StoryInvisibleWall, entering: bool)

enum TriggerMode {
	AUTO_ON_ENTER,    ## Se dispara al entrar/salir un cuerpo relevante.
	MANUAL_INTERACT,  ## Requiere pulsar la acción ("E") estando dentro del área.
	EXTERNAL_SIGNAL,  ## No detecta cuerpos: algo externo llama activate() y la pared hace de relé.
}

enum DetectFilter {
	PLAYER_ONLY,       ## Solo el jugador la dispara.
	STORY_ENEMY_ONLY,  ## Solo enemigos de Historia (grupo "story_enemy").
	ANY_BODY,          ## Cualquier cuerpo físico (o grupos creados en el futuro).
}

@export_category("Trigger")
@export var trigger_mode: TriggerMode = TriggerMode.AUTO_ON_ENTER
@export var action_name: StringName = &"interact"
@export var active: bool = true
@export var one_shot: bool = false
@export var detect_filter: DetectFilter = DetectFilter.PLAYER_ONLY

@export_category("Targets")
## Método que se llama sobre cada destino al cruzar/activar la pared.
@export var action_on_enter: StringName = &"activate"
## Método que se llama al salir ("" = no hacer nada). Permite "desactivar"
## lo que se activó al entrar (cerrar puerta, apagar warp, etc.).
@export var action_on_exit: StringName = &"deactivate"
@export var target_nodes: Array[NodePath] = []

@export_category("Presentation")
@export var display_name: String = "PARED"
## Visual plano semitransparente solo en juego (en editor siempre se ve).
@export var show_debug_visual: bool = false

@onready var debug_mesh: MeshInstance3D = $DebugMesh
@onready var prompt_label: Label3D = $PromptLabel

var _player_in_range: Player = null
var _relevant_bodies_in: int = 0
var _used: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	debug_mesh.visible = show_debug_visual and active
	prompt_label.visible = false
	# En EXTERNAL_SIGNAL la pared no detecta cuerpos: funciona solo como relé.
	monitoring = active and trigger_mode != TriggerMode.EXTERNAL_SIGNAL


func _unhandled_input(event: InputEvent) -> void:
	if trigger_mode != TriggerMode.MANUAL_INTERACT or not active:
		return
	if _player_in_range == null or not is_instance_valid(_player_in_range):
		return
	if event.is_action_pressed(action_name):
		_fire_on_enter()
		get_viewport().set_input_as_handled()


## Entrada estándar compartida (llamada por StoryActionButton, cinemáticas,
## otras paredes o elementos futuros).
## - EXTERNAL_SIGNAL: la pared hace de relé → dispara la acción de entrada.
## - AUTO/MANUAL: enciende la pared (reactiva el monitoreo de cuerpos).
func activate() -> void:
	set_active(true)
	if trigger_mode == TriggerMode.EXTERNAL_SIGNAL:
		_fire_on_enter()


## Apaga la pared: deja de detectar cuerpos.
func deactivate() -> void:
	set_active(false)


func toggle() -> void:
	set_active(not active)


func set_active(enabled: bool, instant: bool = false) -> void:
	if active == enabled and not instant:
		return
	active = enabled
	if trigger_mode != TriggerMode.EXTERNAL_SIGNAL:
		monitoring = enabled
	debug_mesh.visible = show_debug_visual and enabled
	if not enabled:
		_player_in_range = null
		_relevant_bodies_in = 0
		prompt_label.visible = false


func _fire_on_enter() -> void:
	if not active:
		return
	if one_shot and _used:
		return
	_apply_action(action_on_enter)
	_used = true
	triggered.emit(self, true)
	if one_shot:
		deactivate()


func _fire_on_exit() -> void:
	if one_shot or not active:
		return
	if action_on_exit == &"":
		return
	_apply_action(action_on_exit)
	triggered.emit(self, false)


func _apply_action(method_name: StringName) -> void:
	if method_name == &"":
		return
	for target_path: NodePath in target_nodes:
		var target: Node = get_node_or_null(target_path)
		if target != null and target.has_method(method_name):
			target.call(method_name)


func _on_body_entered(body: Node3D) -> void:
	if not active or not _is_relevant(body):
		return
	_relevant_bodies_in += 1
	if body is Player:
		_player_in_range = body as Player
		if trigger_mode == TriggerMode.MANUAL_INTERACT:
			prompt_label.text = "[E] %s" % display_name
			prompt_label.visible = true
	if trigger_mode == TriggerMode.AUTO_ON_ENTER and _relevant_bodies_in == 1:
		_fire_on_enter()


func _on_body_exited(body: Node3D) -> void:
	if not _is_relevant(body):
		return
	if body == _player_in_range:
		_player_in_range = null
		prompt_label.visible = false
	_relevant_bodies_in = maxi(_relevant_bodies_in - 1, 0)
	if trigger_mode == TriggerMode.AUTO_ON_ENTER and _relevant_bodies_in == 0:
		_fire_on_exit()


func _is_relevant(body: Node3D) -> bool:
	match detect_filter:
		DetectFilter.PLAYER_ONLY:
			return body is Player or body.is_in_group(&"player")
		DetectFilter.STORY_ENEMY_ONLY:
			return body.is_in_group(&"story_enemy")
		DetectFilter.ANY_BODY:
			return true
	return false
