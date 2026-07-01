# scripts/team_ai.gd
# ──────────────────────────────────────────────────────────────────
# TEAM AI — Sistema de Objetivos y Ordenes de Equipo (FASE 6)
#
# Autoload singleton registrado como "TeamAI".
# Gestiona objetivos de equipo y asigna ordenes a los bots.
#
# ── PROPIETARIO DE (solo el escribe) ──
#   objectives:       Array[Objective] — todos los objetivos del mapa
#   bot_orders:       Dictionary — ordenes asignadas a cada bot
#   team_scores:      Dictionary — puntuaciones por equipo
#
# ── NUNCA ESCRIBE ──
#   velocity, target_entity, movement_command, combat_command
#
# ── COMUNICACION ──
#   Emite senales -> DecisionSystem / BotBrain los escuchan
#   Los estados FSM consultan TeamAI para saber su orden actual
# ──────────────────────────────────────────────────────────────────
extends Node


# ══════════════════════════════════════════════════════════════════
# ENUMS — Tipos de orden
# ══════════════════════════════════════════════════════════════════

enum OrderType {
	FREELANCE = 0,
	ATTACK = 1,
	DEFEND = 2,
	FOLLOW = 3,
	HOLD = 4,
	PATROL = 5,
	RETURN = 6,
	CAPTURE = 7,
}


# ══════════════════════════════════════════════════════════════════
# SENALES
# ══════════════════════════════════════════════════════════════════

signal objective_completed(objective_id: String, team: int)
signal orders_changed(bot_id: int, new_order_type: int, target: NodePath)


# ══════════════════════════════════════════════════════════════════
# ESTADO — ObjectiveSystem
# ══════════════════════════════════════════════════════════════════

var objectives: Array[Objective] = []
var _objectives_by_team: Dictionary = {}


# ══════════════════════════════════════════════════════════════════
# ESTADO — OrderSystem
# ══════════════════════════════════════════════════════════════════

var bot_orders: Dictionary = {}
var _temp_orders: Dictionary = {}
var team_scores: Dictionary = {}
var _has_scanned: bool = false


# ══════════════════════════════════════════════════════════════════
# STRUCTS INTERNOS
# ══════════════════════════════════════════════════════════════════

class OrderData:
	var order_type: int = OrderType.FREELANCE
	var target_node: NodePath = NodePath()
	var target_position: Vector3 = Vector3.ZERO
	var issued_at: float = 0.0


class TempOrderData:
	var order_type: int = OrderType.ATTACK
	var target_position: Vector3 = Vector3.ZERO
	var expires_at: float = 0.0
	var reason: String = ""


# ══════════════════════════════════════════════════════════════════
# INICIALIZACION
# ══════════════════════════════════════════════════════════════════

func _ready() -> void:
	for team_id in range(1, 5):
		team_scores[team_id] = 0
	_scan_map_for_objectives()
	print("[TeamAI] Inicializado. Escaneando objetivos...")


func _scan_map_for_objectives() -> void:
	if _has_scanned:
		return
	_has_scanned = true
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not tree:
		return
	if tree.is_connected("process_frame", _delayed_scan):
		return
	tree.process_frame.connect(_delayed_scan)


func _delayed_scan() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree and tree.is_connected("process_frame", _delayed_scan):
		tree.process_frame.disconnect(_delayed_scan)

	objectives.clear()
	_objectives_by_team.clear()

	var cores: Array[Node] = get_tree().get_nodes_in_group("core")
	if cores.is_empty():
		print("[TeamAI] No se encontraron cores en el mapa.")
		return

	for core in cores:
		if not is_instance_valid(core):
			continue
		if core.get("is_destroyed") == true:
			continue

		var core_team: int = core.get("team") if "team" in core else -1
		var core_pos: Vector3 = core.global_position
		var core_name: String = core.name

		for team_id in [int(Enums.Equipo.AZUL), int(Enums.Equipo.ROJO)]:
			if team_id == core_team:
				var defend_obj := Objective.defend(core_pos, team_id, "defend_%s" % core_name)
				defend_obj.target_node = core.get_path()
				defend_obj.completion_radius = 8.0
				defend_obj.priority = 5.0
				_add_objective(defend_obj)
			else:
				var attack_obj := Objective.attack(core_pos, team_id, "attack_%s" % core_name)
				attack_obj.target_node = core.get_path()
				attack_obj.completion_radius = 3.0
				attack_obj.priority = 10.0
				_add_objective(attack_obj)

	print("[TeamAI] Escaneo completado: %d objetivos generados" % objectives.size())


func _add_objective(obj: Objective) -> void:
	objectives.append(obj)
	if not _objectives_by_team.has(obj.team):
		_objectives_by_team[obj.team] = []
	_objectives_by_team[obj.team].append(obj)


# ══════════════════════════════════════════════════════════════════
# API PUBLICA — ObjectiveSystem
# ══════════════════════════════════════════════════════════════════

func get_objectives_for_team(team: int) -> Array[Objective]:
	var result: Array[Objective] = []
	for obj in _objectives_by_team.get(team, []):
		if obj == null or obj.is_completed:
			continue
		if obj.target_node != NodePath():
			var target: Node = _resolve_node(obj.target_node)
			if not is_instance_valid(target) or not target.is_inside_tree():
				obj.is_completed = true
				objective_completed.emit(obj.objective_id, team)
				continue
			obj.position = target.global_position
		result.append(obj)
	return result


func get_priority_objective_for_team(team: int) -> Objective:
	var team_objs: Array[Objective] = get_objectives_for_team(team)
	if team_objs.is_empty():
		return null
	var best: Objective = null
	var best_priority: float = -1.0
	for obj in team_objs:
		if obj.priority > best_priority:
			best_priority = obj.priority
			best = obj
	return best


func complete_objective(objective_id: String) -> void:
	for obj in objectives:
		if obj.objective_id == objective_id:
			obj.is_completed = true
			objective_completed.emit(objective_id, obj.team)
			return


func refresh_objectives() -> void:
	_has_scanned = false
	_scan_map_for_objectives()


# ══════════════════════════════════════════════════════════════════
# API PUBLICA — OrderSystem
# ══════════════════════════════════════════════════════════════════

func assign_order(bot: NpcBase, order_type: int, target: NodePath = NodePath()) -> void:
	if not is_instance_valid(bot):
		return
	var order := OrderData.new()
	order.order_type = order_type
	order.target_node = target
	order.issued_at = Time.get_ticks_msec() / 1000.0
	if target != NodePath():
		var target_node: Node = _resolve_node(target)
		if is_instance_valid(target_node):
			order.target_position = target_node.global_position
	bot_orders[bot] = order
	if _temp_orders.has(bot):
		_temp_orders.erase(bot)
	orders_changed.emit(bot.get_instance_id(), order_type, target)


func get_order_for_bot(bot: NpcBase) -> Dictionary:
	if not is_instance_valid(bot):
		return _empty_order()
	if _temp_orders.has(bot):
		var temp: TempOrderData = _temp_orders[bot]
		if temp.expires_at <= 0.0 or Time.get_ticks_msec() / 1000.0 < temp.expires_at:
			return {
				"type": temp.order_type,
				"target_position": temp.target_position,
				"target_node": NodePath(),
				"is_temp": true,
				"reason": temp.reason,
			}
		else:
			_temp_orders.erase(bot)
	if bot_orders.has(bot):
		var order: OrderData = bot_orders[bot]
		return {
			"type": order.order_type,
			"target_position": order.target_position,
			"target_node": order.target_node,
			"is_temp": false,
			"reason": "",
		}
	return _empty_order()


func set_temp_order(bot: NpcBase, order_type: int, target_pos: Vector3, duration: float = 10.0, reason: String = "") -> void:
	if not is_instance_valid(bot):
		return
	var temp := TempOrderData.new()
	temp.order_type = order_type
	temp.target_position = target_pos
	temp.expires_at = (Time.get_ticks_msec() / 1000.0) + duration if duration > 0 else 0.0
	temp.reason = reason
	_temp_orders[bot] = temp


func clear_temp_order(bot: NpcBase) -> void:
	if _temp_orders.has(bot):
		_temp_orders.erase(bot)


func assign_order_by_role(bot: NpcBase) -> void:
	if not is_instance_valid(bot):
		return
	var role: int = bot.rol
	var team: int = bot.equipo_id
	var own_core: Node = _get_own_core(team)
	var enemy_core: Node = _get_enemy_core(team)

	match role:
		int(Enums.Rol.SOLDADO):
			if enemy_core:
				assign_order(bot, OrderType.ATTACK, enemy_core.get_path())
			else:
				assign_order(bot, OrderType.FREELANCE)
		int(Enums.Rol.FRANCOTIRADOR):
			if own_core:
				assign_order(bot, OrderType.DEFEND, own_core.get_path())
			else:
				assign_order(bot, OrderType.DEFEND)
		int(Enums.Rol.APOYO):
			if own_core:
				assign_order(bot, OrderType.DEFEND, own_core.get_path())
			else:
				assign_order(bot, OrderType.DEFEND)
		int(Enums.Rol.EXPLORADOR):
			if enemy_core:
				assign_order(bot, OrderType.ATTACK, enemy_core.get_path())
			else:
				assign_order(bot, OrderType.ATTACK)
		int(Enums.Rol.COMANDANTE):
			if _needs_defense(team):
				if own_core:
					assign_order(bot, OrderType.DEFEND, own_core.get_path())
				else:
					assign_order(bot, OrderType.DEFEND)
			else:
				if enemy_core:
					assign_order(bot, OrderType.ATTACK, enemy_core.get_path())
				else:
					assign_order(bot, OrderType.FREELANCE)
		_:
			assign_order(bot, OrderType.FREELANCE)


func assign_orders_for_team(team: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not tree:
		return
	var npcs: Array[Node] = tree.get_nodes_in_group("npc")
	for npc in npcs:
		if not is_instance_valid(npc) or npc is not NpcBase:
			continue
		var bot: NpcBase = npc as NpcBase
		if bot.equipo_id != team or bot.is_dead:
			continue
		assign_order_by_role(bot)


func assign_orders_all() -> void:
	for team_id in [int(Enums.Equipo.AZUL), int(Enums.Equipo.ROJO)]:
		assign_orders_for_team(team_id)


func order_type_name(order_type: int) -> String:
	match order_type:
		OrderType.FREELANCE:  return "Libre"
		OrderType.ATTACK:     return "Atacar"
		OrderType.DEFEND:     return "Defender"
		OrderType.FOLLOW:     return "Seguir"
		OrderType.HOLD:       return "Mantener"
		OrderType.PATROL:     return "Patrullar"
		OrderType.RETURN:     return "Retornar"
		OrderType.CAPTURE:    return "Capturar"
	return "?" + str(order_type)


# ══════════════════════════════════════════════════════════════════
# EVALUACION TACTICA
# ══════════════════════════════════════════════════════════════════

func _needs_defense(team: int) -> bool:
	var enemy_team: int = _get_enemy_team(team)
	if enemy_team < 0:
		return false
	var attackers: int = _count_bots_with_order(enemy_team, [OrderType.ATTACK, OrderType.CAPTURE])
	var defenders: int = _count_bots_with_order(team, [OrderType.DEFEND, OrderType.HOLD])
	return attackers > defenders


func _count_bots_with_order(team: int, order_types: Array) -> int:
	var count: int = 0
	for bot in bot_orders.keys():
		if not is_instance_valid(bot):
			bot_orders.erase(bot)
			continue
		if bot.equipo_id != team:
			continue
		var order: OrderData = bot_orders[bot]
		if order.order_type in order_types:
			count += 1
	return count


# ══════════════════════════════════════════════════════════════════
# HELPERS
# ══════════════════════════════════════════════════════════════════

func _resolve_node(path: NodePath) -> Node:
	if path == NodePath():
		return null
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not tree:
		return null
	return tree.root.get_node_or_null(path)


func _get_own_core(team: int) -> Node:
	if team == int(Enums.Equipo.AZUL):
		return GameState.core_blue if is_instance_valid(GameState.core_blue) else null
	elif team == int(Enums.Equipo.ROJO):
		return GameState.core_red if is_instance_valid(GameState.core_red) else null
	return null


func _get_enemy_core(team: int) -> Node:
	var enemy_team: int = _get_enemy_team(team)
	if enemy_team < 0:
		return null
	return _get_own_core(enemy_team)


func _get_enemy_team(team: int) -> int:
	if team == int(Enums.Equipo.AZUL):
		return int(Enums.Equipo.ROJO)
	elif team == int(Enums.Equipo.ROJO):
		return int(Enums.Equipo.AZUL)
	return -1


func _empty_order() -> Dictionary:
	return {
		"type": OrderType.FREELANCE,
		"target_position": Vector3.ZERO,
		"target_node": NodePath(),
		"is_temp": false,
		"reason": "",
	}


# ══════════════════════════════════════════════════════════════════
# EVENTOS DEL MAPA
# ══════════════════════════════════════════════════════════════════

func on_core_destroyed(destroyed_team: int) -> void:
	var prefix_attack: String = "attack_Core%s" % destroyed_team
	var prefix_defend: String = "defend_Core%s" % destroyed_team
	for obj in objectives:
		if obj.objective_id.begins_with(prefix_attack) or obj.objective_id.begins_with(prefix_defend):
			obj.is_completed = true
	var enemy_team: int = _get_enemy_team(destroyed_team)
	if enemy_team >= 0:
		assign_orders_for_team(enemy_team)
	print("[TeamAI] Core del equipo %s destruido." % GameState.nombre_equipo(destroyed_team))


# ══════════════════════════════════════════════════════════════════
# DEBUG
# ══════════════════════════════════════════════════════════════════

func get_debug_summary() -> String:
	var lines: PackedStringArray = []
	lines.append("=== TeamAI ===")
	lines.append("Objetivos totales: %d" % objectives.size())
	for team_id in [int(Enums.Equipo.AZUL), int(Enums.Equipo.ROJO)]:
		var team_objs: Array[Objective] = get_objectives_for_team(team_id)
		lines.append("  %s: %d objetivos" % [GameState.nombre_equipo(team_id), team_objs.size()])
		for obj in team_objs:
			lines.append("    - %s prior=%.1f" % [obj.display_name, obj.priority])
	lines.append("Ordenes asignadas: %d bots" % bot_orders.size())
	for bot in bot_orders.keys():
		if not is_instance_valid(bot):
			continue
		var order: OrderData = bot_orders[bot]
		lines.append("  Bot #%d: %s" % [bot.get_instance_id(), order_type_name(order.order_type)])
	return "\n".join(lines)
