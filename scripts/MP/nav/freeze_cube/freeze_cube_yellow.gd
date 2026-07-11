# scripts/freeze_cube2.gd
# ──────────────────────────────────────────────────────────────────
# CUBO DE CONGELACIÓN MORADO — 100% autónomo.
# No llama a ningún método de npc_base.gd.
#
# Cuando un NPC toca el área:
#   1. Congela directamente al NPC (is_frozen, velocity, nav)
#   2. Añade un YellowJumpController como hijo del NPC
#   3. El controlador maneja el salto al YellowCube + descongelar
# ──────────────────────────────────────────────────────────────────
extends Area3D
class_name FreezeCube2


const FREEZE_DURATION: float = 3


func _ready() -> void:
	collision_layer = 0
	collision_mask = 6  # capas 2 y 3
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	var npc: NpcBase = body as NpcBase
	if not npc or npc.is_dead or npc.is_frozen:
		return
	if _has_active_yellow_jump_controller(npc):
		return
	
	# ── 1. Congelar directamente (sin usar métodos de npc_base) ─
	npc.is_frozen = true
	npc.velocity = Vector3.ZERO
	if npc.navigation_agent:
		npc.navigation_agent.target_position = npc.global_position
	
	# ── 2. Buscar YellowCube más cercano ────────────────────────
	var target: Node3D = _find_nearest_yellow_cube()
	
	# ── 3. Crear y añadir controlador de salto al NPC ───────────
	var ctrl: YellowJumpController = YellowJumpController.new()
	if target:
		# Calcular parámetros del salto
		var jump_start: Vector3 = npc.global_position
		var jump_target: Vector3 = target.global_position
		
		var diff_xz: Vector2 = Vector2(
			jump_target.x - jump_start.x,
			jump_target.z - jump_start.z
		)
		var h_dist: float = diff_xz.length()
		var jump_duration: float = clamp(0.8 + h_dist * 0.08, 1.0, 2.5)
		var jump_arc: float = clamp(1.5 + h_dist * 0.15, 2.0, 6.0)
		
		ctrl.setup(jump_start, jump_target, jump_duration, jump_arc, FREEZE_DURATION)
	else:
		# Sin yellow cube: solo congelar el tiempo sin salto
		ctrl.setup(npc.global_position, npc.global_position, 1.0, 0.0, FREEZE_DURATION)
	
	npc.add_child(ctrl)


func _find_nearest_yellow_cube() -> Node3D:
	var cubes: Array[Node] = get_tree().get_nodes_in_group("yellow_cube")
	var nearest: Node3D = null
	var nearest_dist: float = INF
	
	for cube in cubes:
		if not is_instance_valid(cube):
			continue
		var dist: float = global_position.distance_squared_to(cube.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = cube as Node3D
	
	return nearest


func _has_active_yellow_jump_controller(npc: NpcBase) -> bool:
	var child_nodes: Array[Node] = npc.get_children()
	for child_node: Node in child_nodes:
		if child_node is YellowJumpController:
			return true
	return false
