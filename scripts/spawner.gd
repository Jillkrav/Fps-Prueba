# scripts/spawner.gd
# Spawner universal: usa solo npc_base.tscn y asigna armas aleatorias del config.
extends Node3D
class_name NpcSpawner

@export var spawn_interval:         float = 20.0
@export var spawn_count_per_cycle:  int   = 3
@export var spawn_points_paths:     Array[NodePath] = []

## Porcentaje de NPC aliados (0.0 = todos enemigos, 1.0 = todos aliados)
@export_range(0.0, 1.0) var aliado_ratio: float = 0.0

## Si es true, el spawner no genera nada (util para mapas de testeo)
@export var disabled: bool = false

var npc_scene: PackedScene = preload("res://scenes/npcs/npc_base.tscn")

var spawn_timer: Timer
var spawn_points: Array[Marker3D] = []
var hud: CanvasLayer = null
var _selector_abierto: bool = false

func _ready() -> void:
	if disabled:
		return

	for path in spawn_points_paths:
		var node: Node = get_node_or_null(path)
		if node is Marker3D:
			spawn_points.append(node)

	if spawn_points.is_empty():
		for child in get_children():
			if child is Marker3D:
				spawn_points.append(child)

	spawn_timer = Timer.new()
	spawn_timer.wait_time = spawn_interval
	spawn_timer.one_shot  = false
	spawn_timer.autostart = true
	add_child(spawn_timer)
	spawn_timer.timeout.connect(_on_spawn_timeout)

	hud = get_tree().get_first_node_in_group("hud") as CanvasLayer
	if not hud:
		var hud_nodes: Array = get_tree().get_nodes_in_group("hud")
		if not hud_nodes.is_empty():
			hud = hud_nodes[0] as CanvasLayer

	call_deferred("spawn_wave")

func pausar_spawn() -> void:
	_selector_abierto = true
	if spawn_timer and not spawn_timer.is_paused():
		spawn_timer.set_paused(true)

func reanudar_spawn() -> void:
	_selector_abierto = false
	if spawn_timer and spawn_timer.is_paused():
		spawn_timer.set_paused(false)

func _process(_delta: float) -> void:
	if disabled or _selector_abierto:
		return
	if spawn_timer and not spawn_timer.is_stopped():
		if hud and hud.has_method("update_spawn_timer"):
			hud.update_spawn_timer(spawn_timer.time_left)
		else:
			hud = get_tree().get_first_node_in_group("hud") as CanvasLayer

func _on_spawn_timeout() -> void:
	if disabled or _selector_abierto:
		return
	spawn_wave()

func spawn_wave() -> void:
	if disabled or spawn_points.is_empty():
		return
	if not is_inside_tree() or not get_parent().is_inside_tree():
		return

	var equipo_jugador: String = "azul"
	var gs: Node = get_node_or_null("/root/GameState")
	if gs and "selected_team" in gs:
		equipo_jugador = gs.selected_team
	var equipo_enemigo: String = "rojo" if equipo_jugador == "azul" else "azul"

	# Obtener lista de armas disponibles del config
	var armas_lista: Array[String] = []
	if ConfigManager and ConfigManager._data.has("Armas"):
		for categoria in ConfigManager._data["Armas"].keys():
			for nombre in ConfigManager._data["Armas"][categoria].keys():
				armas_lista.append(nombre)
	# Fallback si no hay config de armas
	if armas_lista.is_empty():
		armas_lista = [""]

	for _i in range(spawn_count_per_cycle):
		var point: Marker3D = spawn_points[randi() % spawn_points.size()]
		if not point.is_inside_tree():
			continue

		var npc: NpcBase = npc_scene.instantiate() as NpcBase
		if not npc:
			continue

		# Asignar relacion y equipo ANTES de add_child
		if randf() < aliado_ratio:
			npc.relacion          = NpcBase.Relacion.AMIGABLE
			npc.equipo            = equipo_jugador
			npc._relacion_forzada = true
		else:
			npc.relacion          = NpcBase.Relacion.ENEMIGO
			npc.equipo            = equipo_enemigo
			npc._relacion_forzada = true

		# Asignar arma aleatoria del config
		npc.nombre_arma = armas_lista[randi() % armas_lista.size()]

		var spawn_pos: Vector3 = point.global_transform.origin + Vector3(
			randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)
		)
		get_parent().add_child(npc)
		npc.global_transform.origin = spawn_pos
