extends Node3D
class_name EnemySpawner

@export var spawn_interval: float = 20.0
@export var spawn_count_per_cycle: int = 3
@export var spawn_points_paths: Array[NodePath] = []

# Referencias a escenas de enemigos precargadas
var enemy_melee_scene: PackedScene = preload("res://scenes/enemies/enemy_melee.tscn")
var enemy_pistolero_scene: PackedScene = preload("res://scenes/enemies/enemy_pistolero.tscn")
var enemy_escopetero_scene: PackedScene = preload("res://scenes/enemies/enemy_escopetero.tscn")

var spawn_timer: Timer
var spawn_points: Array[Marker3D] = []
var hud: CanvasLayer = null

func _ready() -> void:
	# Encontrar los Marker3D de spawn reales a partir de los paths
	for path in spawn_points_paths:
		var node: Node = get_node_or_null(path)
		if node is Marker3D:
			spawn_points.append(node)
			
	# Si no se configuraron por exportación, buscamos hijos que sean Marker3D
	if spawn_points.is_empty():
		for child in get_children():
			if child is Marker3D:
				spawn_points.append(child)
				
	# Configurar timer de spawn
	spawn_timer = Timer.new()
	spawn_timer.wait_time = spawn_interval
	spawn_timer.one_shot = false
	spawn_timer.autostart = true
	add_child(spawn_timer)
	spawn_timer.timeout.connect(_on_spawn_timeout)
	
	# Buscar la HUD para poder actualizar el tiempo restante
	hud = get_tree().get_first_node_in_group("hud") as CanvasLayer
	if not hud:
		# Si no está en un grupo todavía, la buscamos por tipo
		var hud_nodes: Array = get_tree().get_nodes_in_group("hud")
		if not hud_nodes.is_empty():
			hud = hud_nodes[0] as CanvasLayer
			
	# Realizar un spawn inicial diferido para evitar problemas en ready
	call_deferred("spawn_wave")

func _process(_delta: float) -> void:
	# Actualizar la HUD con el tiempo restante
	if not spawn_timer.is_stopped():
		if hud and hud.has_method("update_spawn_timer"):
			hud.update_spawn_timer(spawn_timer.time_left)
		else:
			# Re-buscar si no se encontró al ready
			hud = get_tree().get_first_node_in_group("hud") as CanvasLayer

func _on_spawn_timeout() -> void:
	spawn_wave()

func spawn_wave() -> void:
	if spawn_points.is_empty():
		return
		
	# Si el nodo spawner o su padre no están listos en el árbol, esperar
	if not is_inside_tree() or not get_parent().is_inside_tree():
		return
		
	for i in range(spawn_count_per_cycle):
		# Elegir punto de spawn aleatorio
		var point: Marker3D = spawn_points[randi() % spawn_points.size()]
		
		# Validar si el punto está dentro del árbol antes de leer global_transform
		if not point.is_inside_tree():
			continue
			
		# Decidir tipo de enemigo de forma balanceada
		var enemy_scene: PackedScene
		var roll: float = randf()
		
		if roll < 0.5:
			enemy_scene = enemy_melee_scene # 50% probabilidad
		elif roll < 0.8:
			enemy_scene = enemy_pistolero_scene # 30% probabilidad
		else:
			enemy_scene = enemy_escopetero_scene # 20% probabilidad
			
		var enemy: CharacterBody3D = enemy_scene.instantiate() as CharacterBody3D
		
		# Solución robusta: Añadir el enemigo al árbol primero de forma diferida,
		# y asignarle la posición global también de forma diferida en un callable,
		# garantizando que tanto el spawner como el spawn point y el enemigo estén totalmente integrados en el scene tree.
		var spawn_pos: Vector3 = point.global_transform.origin + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
		get_parent().add_child(enemy)
		enemy.global_transform.origin = spawn_pos
