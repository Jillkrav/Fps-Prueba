class_name StoryNPCSpawner
extends Node3D

## Spawner genérico de NPCs para niveles de Historia.
##
## Se coloca en cualquier mapa de Historia y se configura entero desde el
## Inspector:
##   - Qué NPC spawnea (NpcType + opcional override_scene).
##   - Cuántos NPCs spawnea (spawn_count).
##   - A qué ritmo (spawn_rate, en NPCs por segundo).
##   - Qué lo activa (TriggerMode, ver enum).
##
## Expone la interfaz estándar del proyecto (activate / deactivate / toggle),
## así que puede conectarse a un StoryActionButton, a una StoryInvisibleWall o
## a cualquier otro elemento que llame a esos métodos.
##
## Para AÑADIR un nuevo tipo de NPC en el futuro:
##   1. Añade un valor al enum NpcType.
##   2. Añade su ruta a NPC_SCENES.
##   3. (Alternativa sin tocar el código) asigna su escena a override_scene.
## El NPC instanciado debe seguir las convenciones de StoryMeleeEnemy: ser un
## CharacterBody3D (o Node3D) que se añade al grupo "story_enemy" en _ready().

signal spawner_activated(spawner: StoryNPCSpawner)
signal spawner_deactivated(spawner: StoryNPCSpawner)
signal npc_spawned(spawner: StoryNPCSpawner, npc: Node3D)
signal spawner_finished(spawner: StoryNPCSpawner)

## Tipos de NPC disponibles. Ampliar al crear más NPCs.
enum NpcType {
	MELEE,
}

## Registro tipo -> escena. Ampliar aquí al crear más NPCs.
const NPC_SCENES: Dictionary = {
	NpcType.MELEE: "res://scenes/Historia/npc/enemies/story_melee_enemy.tscn",
}

enum TriggerMode {
	START_ON_READY,     ## Empieza a invocar solo al cargar el nivel.
	MANUAL_INTERACT,    ## El jugador pulsa la acción estando en la zona.
	AUTOMATIC_ON_ENTER, ## Empieza cuando el jugador entra en la zona.
	EXTERNAL_SIGNAL,    ## Lo activa algo externo (botón, pared...) vía activate().
}

@export_category("Spawn")
@export var npc_type: NpcType = NpcType.MELEE
## Escena alternativa al NpcType. Si se rellena, se usa esta en su lugar
## (útil para prototipar NPCs nuevos antes de registrarlos en NpcType).
@export var override_scene: PackedScene = null
## Número total de NPCs a invocar por cada activación.
@export_range(1, 999, 1) var spawn_count: int = 1
## Ritmo de spawn: cuántos NPCs aparecen por segundo.
@export_range(0.05, 100.0, 0.05) var spawn_rate: float = 1.0
## Desplazamiento aleatorio horizontal alrededor del SpawnPoint para que los
## NPCs no aparezcan apilados en el mismo punto.
@export_range(0.0, 8.0, 0.1) var spread_radius: float = 1.5
## Desplazamiento vertical aplicado a cada NPC al aparecer (posar sobre el suelo).
@export_range(-2.0, 2.0, 0.05) var spawn_height_offset: float = 0.05

@export_category("Trigger")
@export var trigger_mode: TriggerMode = TriggerMode.START_ON_READY
@export var action_name: StringName = &"interact"
## Si true, una vez completada la oleada el spawner ya no se puede reactivar.
@export var one_shot: bool = true
## Tamaño de la zona de trigger (MANUAL_INTERACT / AUTOMATIC_ON_ENTER).
@export var trigger_box_size: Vector3 = Vector3(4.0, 3.0, 4.0)
## Retardo en segundos antes de empezar a invocar (solo START_ON_READY).
@export_range(0.0, 10.0, 0.1) var initial_delay: float = 0.0

@export_category("Presentation")
@export var display_name: String = "SPAWNER"
@export var show_debug_visual: bool = true

@onready var spawn_point: Node3D = $SpawnPoint
@onready var debug_mesh: MeshInstance3D = $DebugMesh
@onready var trigger_area: Area3D = $TriggerArea
@onready var trigger_shape: CollisionShape3D = $TriggerArea/CollisionShape3D
@onready var trigger_zone_mesh: MeshInstance3D = $TriggerArea/DebugZoneMesh
@onready var spawn_timer: Timer = $SpawnTimer
@onready var prompt_label: Label3D = $PromptLabel

var is_active: bool = false
## true cuando una oleada completa ha terminado y one_shot impide reactivar.
var has_finished: bool = false
var spawned_total: int = 0

var _start_delay_timer: float = 0.0
var _player_in_range: Player = null


func _ready() -> void:
	trigger_area.body_entered.connect(_on_body_entered)
	trigger_area.body_exited.connect(_on_body_exited)
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	_apply_trigger_box_size()
	_setup_debug_visuals()
	prompt_label.visible = false
	trigger_area.monitoring = trigger_mode == TriggerMode.MANUAL_INTERACT \
			or trigger_mode == TriggerMode.AUTOMATIC_ON_ENTER
	if trigger_mode == TriggerMode.START_ON_READY:
		if initial_delay > 0.0:
			_start_delay_timer = initial_delay
		else:
			call_deferred("_start_spawning")


func _process(delta: float) -> void:
	if _start_delay_timer <= 0.0:
		return
	_start_delay_timer = maxf(0.0, _start_delay_timer - delta)
	if _start_delay_timer == 0.0:
		_start_spawning()


func _unhandled_input(event: InputEvent) -> void:
	if trigger_mode != TriggerMode.MANUAL_INTERACT:
		return
	if is_active:
		return
	if _player_in_range == null or not is_instance_valid(_player_in_range):
		return
	if event.is_action_pressed(action_name):
		activate()
		get_viewport().set_input_as_handled()


## ── Interfaz estándar (StoryActionButton / StoryInvisibleWall / externos) ──

## Comienza una oleada de spawn (spawn_count NPCs a razón de spawn_rate).
func activate() -> void:
	if one_shot and has_finished:
		return
	_start_spawning()


func _start_spawning() -> void:
	if is_active:
		return
	spawned_total = 0
	is_active = true
	spawner_activated.emit(self)
	_spawn_one()
	if spawned_total >= spawn_count:
		_stop_spawning()
		return
	spawn_timer.wait_time = maxf(1.0 / spawn_rate, 0.01)
	spawn_timer.start()


## Detiene el spawn en curso. Si se vuelve a llamar a activate(), la oleada
## se reinicia desde el principio.
func deactivate() -> void:
	if not is_active:
		return
	spawn_timer.stop()
	is_active = false
	spawner_deactivated.emit(self)


func toggle() -> void:
	if is_active:
		deactivate()
	else:
		activate()


func _on_spawn_timer_timeout() -> void:
	if not is_active:
		return
	_spawn_one()
	if spawned_total >= spawn_count:
		_stop_spawning()


func _spawn_one() -> void:
	if spawned_total >= spawn_count:
		return
	var packed: PackedScene = _resolve_packed_scene()
	if packed == null:
		push_error("[StoryNPCSpawner] %s: no se pudo resolver la escena de NPC (tipo %d)." % [name, npc_type])
		_stop_spawning()
		return
	var npc: Node3D = packed.instantiate() as Node3D
	if npc == null:
		push_error("[StoryNPCSpawner] %s: la escena no instanció un Node3D." % name)
		_stop_spawning()
		return
	var pos: Vector3 = spawn_point.global_position
	if spread_radius > 0.0 and spawned_total > 0:
		var angle: float = randf() * TAU
		var radius: float = randf() * spread_radius
		pos.x += cos(angle) * radius
		pos.z += sin(angle) * radius
	pos.y += spawn_height_offset
	# Normalmente el spawner cuelga del mapa (current_scene). Si no hay escena
	# actual (p. ej. tests), usamos el padre para no depender de ella.
	var target_parent: Node = get_tree().current_scene
	if target_parent == null:
		target_parent = get_parent()
	if target_parent == null:
		push_error("[StoryNPCSpawner] %s: sin destino donde instanciar el NPC." % name)
		return
	target_parent.add_child(npc)
	npc.global_position = pos
	spawned_total += 1
	npc_spawned.emit(self, npc)


func _stop_spawning() -> void:
	spawn_timer.stop()
	is_active = false
	if spawned_total >= spawn_count:
		if one_shot:
			has_finished = true
		spawner_finished.emit(self)


func _resolve_packed_scene() -> PackedScene:
	if override_scene != null:
		return override_scene
	var scene_path: String = NPC_SCENES.get(npc_type, "")
	if scene_path.is_empty():
		return null
	return load(scene_path) as PackedScene


## ── Zona de trigger ──

func _apply_trigger_box_size() -> void:
	var shape: Shape3D = trigger_shape.shape
	if shape is BoxShape3D:
		var box: BoxShape3D = shape.duplicate()
		box.size = trigger_box_size
		trigger_shape.shape = box


func _on_body_entered(body: Node3D) -> void:
	if not (body is Player or body.is_in_group(&"player")):
		return
	_player_in_range = body as Player
	if trigger_mode == TriggerMode.MANUAL_INTERACT:
		prompt_label.text = "[E] %s" % display_name
		prompt_label.visible = true
	elif trigger_mode == TriggerMode.AUTOMATIC_ON_ENTER:
		activate()


func _on_body_exited(body: Node3D) -> void:
	if body == _player_in_range:
		_player_in_range = null
		prompt_label.visible = false


## ── Visuales de debug ──

func _setup_debug_visuals() -> void:
	debug_mesh.visible = show_debug_visual
	var zone_mesh: Mesh = trigger_zone_mesh.mesh
	if zone_mesh is BoxMesh:
		var box_mesh: BoxMesh = zone_mesh.duplicate()
		box_mesh.size = trigger_box_size
		trigger_zone_mesh.mesh = box_mesh
	trigger_zone_mesh.visible = show_debug_visual and (
		trigger_mode == TriggerMode.MANUAL_INTERACT or trigger_mode == TriggerMode.AUTOMATIC_ON_ENTER
	)
