# scripts/bot_debug_overlay.gd
# Componente de depuración que se coloca sobre cada unidad (NPC o Jugador).
# Muestra: nombre, barra de vida, HP, munición del cargador y total de balas.
# Se activa/desactiva globalmente mediante BotDebugOverlay.enabled.
extends Node3D
class_name BotDebugOverlay

## Variable global para activar/desactivar todos los overlays.
## Si se cambia en caliente, los overlays existentes responderán en _process.
static var enabled: bool = false

# ─── Referencias a nodos ───────────────────────────────────────────────
@onready var viewport: SubViewport = $Viewport
@onready var sprite: Sprite3D = $Sprite
@onready var name_label: Label = $Viewport/UI/NameLabel
@onready var health_bar: ProgressBar = $Viewport/UI/HealthBar
@onready var health_label: Label = $Viewport/UI/HealthLabel
@onready var ammo_label: Label = $Viewport/UI/AmmoLabel
@onready var reserve_label: Label = $Viewport/UI/ReserveLabel
@onready var role_label: Label = $Viewport/UI/RoleLabel
@onready var state_label: Label = $Viewport/UI/StateLabel
@onready var order_label: Label = $Viewport/UI/OrderLabel
@onready var sem_label: Label = $Viewport/UI/SemLabel

# ─── Referencias al padre ─────────────────────────────────────────────
var _npc: NpcBase = null
var _player: Player = null
var _unit_name: String = ""

func _ready() -> void:
	# Buscar el NpcBase o Player padre
	_npc = get_parent() as NpcBase
	if not _npc:
		_player = get_parent() as Player
	
	if not _npc and not _player:
		push_warning("BotDebugOverlay: debe ser hijo de un NpcBase o Player")
		queue_free()
		return
	
	# Asignar un nombre único
	if _npc:
		var npc_id_val = _npc.get("_npc_id")
		_unit_name = "Bot #%d" % (npc_id_val if npc_id_val != null else randi() % 9999)
	else:
		_unit_name = "Jugador"
	
	# Conectar el Viewport al Sprite3D
	sprite.texture = viewport.get_texture()
	
	# Estado inicial
	visible = enabled

func _process(_delta: float) -> void:
	var parent: Node = get_parent()
	if not is_instance_valid(parent):
		return
	
	# Sincronizar visibilidad con el estado global
	visible = enabled
	
	if not enabled:
		return
	
	# Actualizar nombre
	name_label.text = _unit_name
	
	# ── Obtener datos de vida según el tipo de padre ──────────────────
	var hp_max: float = 0.0
	var hp_cur: float = 0.0
	var weapon = null
	
	if _npc and is_instance_valid(_npc):
		hp_max = _npc.max_health
		hp_cur = _npc.current_health
		weapon = _npc.get("_weapon") if "_weapon" in _npc else null
	elif _player and is_instance_valid(_player):
		hp_max = _player.max_health
		hp_cur = _player.current_health
		weapon = _player.active_weapon
	
	# Actualizar vida
	var hp_pct: float = (hp_cur / hp_max) * 100.0 if hp_max > 0 else 0.0
	health_bar.value = hp_pct
	health_label.text = "%d / %d" % [int(hp_cur), int(hp_max)]
	
	# Color de la barra según porcentaje
	var fill_style: StyleBoxFlat = health_bar.get_theme_stylebox("fill")
	if fill_style:
		if hp_pct < 25.0:
			fill_style.bg_color = Color(1.0, 0.2, 0.2)  # Rojo crítico
		elif hp_pct < 50.0:
			fill_style.bg_color = Color(1.0, 0.7, 0.1)  # Naranja
		else:
			fill_style.bg_color = Color(0.1, 0.8, 0.1)  # Verde
	
	# Actualizar munición (Cargador actual y Total de balas)
	if weapon and is_instance_valid(weapon):
		var mag: int = weapon.ammo_in_mag
		var clip: int = weapon.clip_size
		var reserve: int = weapon.reserve_ammo
		var max_reserve: int = weapon.max_ammo
		ammo_label.text = "Cargador: %d/%d" % [mag, clip]
		reserve_label.text = "Total: %d/%d" % [reserve, max_reserve]

		# Mostrar AI rating del arma (FASE 5)
		if _npc and is_instance_valid(_npc):
			var weapon_sys = _npc.get("weapon_sys")
			if weapon_sys:
				var profile = weapon_sys.get_current_profile()
				if profile:
					# Mostrar rating en una línea compacta
					reserve_label.text += " | AI: %.2f" % profile.ai_rating
	else:
		ammo_label.text = "Sin arma"
		reserve_label.text = ""
	
	# ── Mostrar rol activo (solo NPCs/bots) ─────────────────────────
	if _npc and is_instance_valid(_npc):
		var tactical_role = _npc.get("_tactical_role")
		if tactical_role != null:
			var role_name = tactical_role.display_name if "display_name" in tactical_role else "?"
			role_label.text = "Rol: %s" % role_name
		else:
			role_label.text = "Rol: --"
	elif _player and is_instance_valid(_player):
		role_label.text = "Rol: Jugador"
	
	# ── Mostrar estado FSM (FASE 3) ─────────────────────────────
	if _npc and is_instance_valid(_npc):
		var decision_sys = _npc.get("decision_sys")
		if decision_sys != null and decision_sys.current_state != null:
			state_label.text = "FSM: %s" % decision_sys.current_state.state_name
		else:
			state_label.text = "State: --"
	elif _player and is_instance_valid(_player):
		state_label.text = "State: --"

	# ── Mostrar orden actual de TeamAI (FASE 6) ──────────────
	if _npc and is_instance_valid(_npc):
		var order_name: String = _npc.get("current_order_name")
		if order_name != null and order_name != "" and order_name != "—":
			order_label.text = "Orden: %s" % order_name
		else:
			order_label.text = "Orden: --"
	elif _player and is_instance_valid(_player):
		order_label.text = "Orden: --"

	# ── Mostrar punto semántico cercano (FASE 7) ──────────────
	if _npc and is_instance_valid(_npc) and NavigationSystem._semantic_points_loaded:
		var bot_pos: Vector3 = _npc.global_position
		var nearest: SemanticPoint = NavigationSystem.get_nearest_point(
			SemanticPoint.PointType.PATH, bot_pos, -1, 30.0)
		if nearest == null:
			nearest = NavigationSystem.get_nearest_point(
				SemanticPoint.PointType.AMBUSH, bot_pos, -1, 30.0)
		if nearest == null:
			nearest = NavigationSystem.get_nearest_point(
				SemanticPoint.PointType.DEFENSE, bot_pos, -1, 30.0)
		if nearest:
			var type_name: String = SemanticPoint.PointType.keys()[nearest.point_type] \
				if nearest.point_type < SemanticPoint.PointType.size() else "?"
			var dist: float = nearest.distance_from(bot_pos)
			sem_label.text = "Sem: %s (%.0f)" % [type_name, dist]
		else:
			sem_label.text = "Sem: ninguno"
	else:
		sem_label.text = "Sem: --"

# ─── Toggle global para Propiedades de unidad ─────────────────────────
## Alterna el estado global y actualiza TODAS las unidades (NPCs + Jugador).
static func toggle_unit_properties_all() -> void:
	enabled = not enabled
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not tree:
		return
	
	# Actualizar NPCs (bots)
	var npcs: Array[Node] = tree.get_nodes_in_group("npc")
	for npc in npcs:
		if npc is NpcBase:
			npc._setup_debug_overlay()
	
	# Actualizar Jugador
	var players: Array[Node] = tree.get_nodes_in_group("player")
	for player_node in players:
		if player_node is Player:
			player_node._setup_debug_overlay()
	
	print("[BotDebugOverlay] Propiedades de unidad %s" % ("ACTIVADO" if enabled else "DESACTIVADO"))
