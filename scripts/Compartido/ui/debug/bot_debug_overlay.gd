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
@onready var move_label: Label = $Viewport/UI/MoveLabel
@onready var stuck_label: Label = $Viewport/UI/StuckLabel
@onready var cooldown_label: Label = $Viewport/UI/CooldownLabel
# sem_label eliminado — los puntos semánticos se migraron

# ─── Referencias al padre ─────────────────────────────────────────────
var _npc: BotBase = null
var _player: Player = null
## Unidad genérica: NPC de Historia (Tirador / CuerpoACuerpo) que no es
## BotBase ni Player. Muestra vida, arma y schedule de IA del cerebro táctico.
var _unit: Node3D = null
var _unit_name: String = ""

func _ready() -> void:
	# Buscar el BotBase o Player padre
	_npc = get_parent() as BotBase
	if not _npc:
		_player = get_parent() as Player
	
	# NPC de Historia (Tirador / CuerpoACuerpo): unidad genérica con vida.
	# Se detecta por duck-typing (tiene current_health / max_health), así
	# cualquier NPC nuevo de campaña queda cubierto sin tocar este script.
	if not _npc and not _player:
		var parent_unit: Node = get_parent()
		if parent_unit != null and "current_health" in parent_unit and "max_health" in parent_unit:
			_unit = parent_unit as Node3D
			if _unit.is_in_group(&"tirador"):
				_unit_name = "Tirador"
			elif _unit.is_in_group(&"enemigo"):
				_unit_name = "Zombie"
			else:
				_unit_name = "NPC Historia"
	
	if not _npc and not _player and not _unit:
		push_warning("BotDebugOverlay: debe ser hijo de un BotBase, Player o NPC de Historia")
		queue_free()
		return
	
	# Asignar un nombre único
	if _npc:
		var npc_id_val = _npc.get("_npc_id")
		_unit_name = "Bot #%d" % (npc_id_val if npc_id_val != null else randi() % 9999)
	elif _player:
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
	elif _unit and is_instance_valid(_unit):
		# NPC de Historia: vida por duck-typing y arma interna (_weapon).
		hp_max = float(_unit.get("max_health"))
		hp_cur = float(_unit.get("current_health"))
		weapon = _unit.get("_weapon") if "_weapon" in _unit else null
	
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
	elif _unit and is_instance_valid(_unit):
		# NPC de Historia: en lugar de rol de multijugador mostramos su arma.
		var unit_weapon_name: String = ""
		if weapon != null and is_instance_valid(weapon) and "weapon_name" in weapon:
			unit_weapon_name = str(weapon.get("weapon_name"))
		if unit_weapon_name.is_empty():
			role_label.text = "Arma: Melee"
		else:
			role_label.text = "Arma: %s" % unit_weapon_name
	
	# ── Mostrar estado FSM (FASE 3) ─────────────────────────────
	if _npc and is_instance_valid(_npc):
		var decision_sys = _npc.get("decision_sys")
		if decision_sys != null and decision_sys.current_state != null:
			state_label.text = "FSM: %s" % decision_sys.current_state.state_name
		else:
			state_label.text = "State: --"
	elif _player and is_instance_valid(_player):
		state_label.text = "State: --"
	elif _unit and is_instance_valid(_unit):
		# NPC de Historia: schedule del cerebro táctico (IA de campaña).
		var brain: Variant = _unit.get("_tactical_brain") if "_tactical_brain" in _unit else null
		if brain != null and is_instance_valid(brain) and brain.has_method("get_schedule_name"):
			state_label.text = "IA: %s" % str(brain.call("get_schedule_name"))
		else:
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
	elif _unit and is_instance_valid(_unit):
		order_label.text = "Orden: --"

	# ── MOVIMIENTO (FASE 7) ────────────────────────────────────
	if _npc and is_instance_valid(_npc):
		var mov_cmd = _npc.get("movement_cmd")
		if mov_cmd:
			move_label.text = "Mov: %s" % mov_cmd.current_action_desc()
		else:
			move_label.text = "Mov: --"
		
		# ── STUCK RECOVERY (FASE 7) ────────────────────────────
		var mov_sys = _npc.get("movement_sys")
		if mov_sys:
			var handler = mov_sys.stuck_handler
			if handler:
				var phase: int = handler.recovery_phase if handler.get("recovery_phase") != null else 0
				var phase_names: Dictionary = {0: "normal", 1: "retro", 2: "lateral", 3: "reruta"}
				stuck_label.text = "Stuck: %s (fase %d)" % [phase_names.get(phase, "?"), phase]
			else:
				stuck_label.text = "Stuck: sin handler"
		else:
			stuck_label.text = "Stuck: --"
		
		# ── CAMINO AUTHORED ACTIVO ─────────────────────────────
		var roam_state: Variant = null
		var dec_sys: Variant = _npc.get("decision_sys")
		if dec_sys != null:
			roam_state = dec_sys.get("current_state")
		if roam_state != null and roam_state.get("state_name") == "roaming":
			var navigator: Variant = roam_state.get("_route_navigator")
			if navigator != null and navigator.has_active_route():
				var route: CaminoBot = navigator.get_current_route()
				cooldown_label.text = "Camino: %s" % route.name if route != null else "Camino: --"
			else:
				cooldown_label.text = "Camino: directo"
		else:
			cooldown_label.text = "Camino: --"
	elif _player and is_instance_valid(_player):
		move_label.text = "Mov: --"
		stuck_label.text = "Stuck: --"
		cooldown_label.text = "Cubo: --"
	elif _unit and is_instance_valid(_unit):
		move_label.text = "Mov: --"
		stuck_label.text = "Stuck: --"
		cooldown_label.text = "Camino: --"

# ─── Toggle global para Propiedades de unidad ─────────────────────────
## Alterna el estado global y actualiza TODAS las unidades (NPCs + Jugador).
static func toggle_unit_properties_all() -> void:
	enabled = not enabled
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not tree:
		return
	
	# Actualizar NPCs (bots de multijugador Y NPCs de Historia: cualquiera
	# del grupo "npc" que implemente _setup_debug_overlay, p. ej. Tirador y
	# CuerpoACuerpo).
	var npcs: Array[Node] = tree.get_nodes_in_group("npc")
	for npc in npcs:
		if npc.has_method("_setup_debug_overlay"):
			npc.call("_setup_debug_overlay")
	
	# Actualizar Jugador
	var players: Array[Node] = tree.get_nodes_in_group("player")
	for player_node in players:
		if player_node is Player:
			player_node._setup_debug_overlay()
	
	print("[BotDebugOverlay] Propiedades de unidad %s" % ("ACTIVADO" if enabled else "DESACTIVADO"))
