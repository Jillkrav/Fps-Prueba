# scripts/freeze_cube0.gd
# ──────────────────────────────────────────────────────────────────
# CUBO DE CONGELACIÓN POR ROL — Solo afecta a bots ASSAULT y FLANKER
#
# Cuando un NPC toca el área:
#   - Si es ASSAULT  → salta al AssaultPoint semántico más cercano
#   - Si es FLANKER  → salta al AlternatePoint semántico más cercano
#   - Otros roles    → ignora completamente (no congela, no salta)
# ──────────────────────────────────────────────────────────────────
extends Area3D
class_name FreezeCube0


const FREEZE_DURATION: float = 1.5


func _ready() -> void:
	collision_layer = 0
	collision_mask = 6  # capas 2 y 3
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	var npc: NpcBase = body as NpcBase
	if not npc or npc.is_dead or npc.is_frozen:
		return
	if _has_active_role_jump_controller(npc):
		return
	
	# ── Verificar rol táctico ─────────────────────────────────
	var role = npc._tactical_role
	if not role:
		return
	
	# Solo ASSAULT y FLANKER son afectados por este cubo
	if role.type != TacticalRole.Type.ASSAULT and role.type != TacticalRole.Type.FLANKER:
		return
	
	# ── 1. Congelar directamente ──────────────────────────────
	npc.is_frozen = true
	npc.velocity = Vector3.ZERO
	if npc.navigation_agent:
		npc.navigation_agent.target_position = npc.global_position
	
	# ── 2. Buscar punto semántico según el rol ────────────────
	var target_pos: Vector3 = _find_target(npc, role)
	
	# ── 3. Crear y añadir controlador de salto al NPC ─────────
	var ctrl: RoleJumpController = RoleJumpController.new()
	if target_pos != Vector3.ZERO:
		var jump_start: Vector3 = npc.global_position
		
		var diff_xz: Vector2 = Vector2(
			target_pos.x - jump_start.x,
			target_pos.z - jump_start.z
		)
		var h_dist: float = diff_xz.length()
		var jump_duration: float = clamp(0.8 + h_dist * 0.08, 1.0, 2.5)
		var jump_arc: float = clamp(1.5 + h_dist * 0.15, 2.0, 6.0)
		
		ctrl.setup(jump_start, target_pos, jump_duration, jump_arc, FREEZE_DURATION)
	else:
		# Sin punto disponible: solo congelar sin salto
		ctrl.setup(npc.global_position, npc.global_position, 1.0, 0.0, FREEZE_DURATION)
	
	npc.add_child(ctrl)


## Encuentra la posición del SemanticPoint más cercano según el rol.
func _find_target(npc: NpcBase, role) -> Vector3:
	# Asegurar que los puntos semánticos estén cargados
	if not NavigationSystem._semantic_points_loaded:
		NavigationSystem.load_semantic_points()
	
	# Elegir tipo de punto según el rol
	var point_type: int
	match role.type:
		TacticalRole.Type.ASSAULT:
			point_type = SemanticPoint.PointType.ASSAULT
		TacticalRole.Type.FLANKER:
			point_type = SemanticPoint.PointType.ALTERNATE
		_:
			return Vector3.ZERO  # No debería llegar aquí
	
	# Buscar el punto más cercano
	var point: SemanticPoint = NavigationSystem.get_nearest_point(
		point_type, npc.global_position, npc.equipo_id
	)
	
	if point:
		return point.position
	return Vector3.ZERO


func _has_active_role_jump_controller(npc: NpcBase) -> bool:
	var child_nodes: Array[Node] = npc.get_children()
	for child_node: Node in child_nodes:
		if child_node is RoleJumpController:
			return true
	return false
