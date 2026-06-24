# scripts/spawner.gd
extends Node3D
class_name NpcSpawner

@export var spawn_interval: float = 20.0
@export var spawn_count_per_cycle: int = 3
@export var spawn_points_paths: Array[NodePath] = []

## Porcentaje de NPC aliados (Relacion.AMIGABLE) por wave (0.0 = todos enemigos, 1.0 = todos aliados)
@export_range(0.0, 1.0) var aliado_ratio: float = 0.0

var npc_melee_scene: PackedScene      = preload("res://scenes/npcs/npc_melee.tscn")
var npc_pistolero_scene: PackedScene  = preload("res://scenes/npcs/npc_pistolero.tscn")
var npc_escopetero_scene: PackedScene = preload("res://scenes/npcs/npc_escopetero.tscn")

var spawn_timer: Timer
var spawn_points: Array[Marker3D] = []
var hud: CanvasLayer = null

# Mientras el selector de armas este abierto, el timer se pausa.
var _selector_abierto: bool = false

func _ready() -> void:
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
	spawn_timer.one_shot = false
	spawn_timer.autostart = true
	add_child(spawn_timer)
	spawn_timer.timeout.connect(_on_spawn_timeout)

	hud = get_tree().get_first_node_in_group("hud") as CanvasLayer
	if not hud:
		var hud_nodes: Array = get_tree().get_nodes_in_group("hud")
		if not hud_nodes.is_empty():
			hud = hud_nodes[0] as CanvasLayer

	call_deferred("spawn_wave")

# ── API publica para pausar/reanudar el spawn desde el HUD ──────────
func pausar_spawn() -> void:
	_selector_abierto = true
	if not spawn_timer.is_paused():
		spawn_timer.set_paused(true)

func reanudar_spawn() -> void:
	_selector_abierto = false
	if spawn_timer.is_paused():
		spawn_timer.set_paused(false)

func _process(_delta: float) -> void:
	if _selector_abierto:
		return
	if not spawn_timer.is_stopped():
		if hud and hud.has_method("update_spawn_timer"):
			hud.update_spawn_timer(spawn_timer.time_left)
		else:
			hud = get_tree().get_first_node_in_group("hud") as CanvasLayer

func _on_spawn_timeout() -> void:
	if _selector_abierto:
		return
	spawn_wave()

func spawn_wave() -> void:
	if spawn_points.is_empty():
		return
	if not is_inside_tree() or not get_parent().is_inside_tree():
		return

	# Leer equipo del jugador para asignarlo a los aliados
	var equipo_jugador: String = "azul"
	var gs: Node = get_node_or_null("/root/GameState")
	if gs and "selected_team" in gs:
		equipo_jugador = gs.selected_team
	var equipo_enemigo: String = "rojo" if equipo_jugador == "azul" else "azul"

	for i in range(spawn_count_per_cycle):
		var point: Marker3D = spawn_points[randi() % spawn_points.size()]
		if not point.is_inside_tree():
			continue

		var npc_scene: PackedScene
		var roll: float = randf()
		if roll < 0.5:
			npc_scene = npc_melee_scene
		elif roll < 0.8:
			npc_scene = npc_pistolero_scene
		else:
			npc_scene = npc_escopetero_scene

		var npc: NpcBase = npc_scene.instantiate() as NpcBase
		if not npc:
			continue

		# Asignar relacion Y equipo ANTES de add_child para que _ready() los reciba
		if randf() < aliado_ratio:
			npc.relacion = NpcBase.Relacion.AMIGABLE
			npc.equipo   = equipo_jugador
		else:
			npc.relacion = NpcBase.Relacion.ENEMIGO
			npc.equipo   = equipo_enemigo

		var spawn_pos: Vector3 = point.global_transform.origin + Vector3(
			randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)
		)
		get_parent().add_child(npc)
		npc.global_transform.origin = spawn_pos
