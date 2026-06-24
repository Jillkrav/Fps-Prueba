## Menu de desarrollo. Se activa con Q desde hud.gd.
## Permite: ponerse invisible a los NPC y spawnear cualquier NPC con cualquier arma del JSON.
extends Control

# ─────────────────────────────────────────────────────
# ESCENAS DE NPC BASE DISPONIBLES
# Solo 2 tipos: con arma (pistolero) y melee.
# El arma se asigna por separado desde el selector.
# ─────────────────────────────────────────────────────

const NPC_CON_ARMA:  String = "res://scenes/npcs/npc_pistolero.tscn"
const NPC_MELEE:     String = "res://scenes/npcs/npc_melee.tscn"

# ─────────────────────────────────────────────────────
# REFERENCIAS DE NODOS
# ─────────────────────────────────────────────────────

@onready var panel_principal: Panel        = $PanelPrincipal
@onready var panel_npc: Panel              = $PanelNPC
@onready var btn_invisible: Button         = $PanelPrincipal/VBox/BtnInvisible
@onready var btn_generar: Button           = $PanelPrincipal/VBox/BtnGenerar
@onready var btn_spawn: Button             = $PanelNPC/VBox/BtnSpawn
@onready var btn_volver: Button            = $PanelNPC/VBox/BtnVolver
@onready var opt_equipo: OptionButton      = $PanelNPC/VBox/GridAtributos/OptRelacion
@onready var opt_experiencia: OptionButton = $PanelNPC/VBox/GridAtributos/OptExperiencia
@onready var opt_tipo_npc: OptionButton    = $PanelNPC/VBox/GridAtributos/OptArma
@onready var opt_arma: OptionButton        = $PanelNPC/VBox/GridAtributos/OptArmaCfg
@onready var lbl_status: Label             = $PanelPrincipal/VBox/LblStatus
@onready var lbl_arma_detalle: Label       = get_node_or_null("PanelNPC/VBox/LblArmaDetalle")

# ─────────────────────────────────────────────────────
# ESTADO INTERNO
# ─────────────────────────────────────────────────────

var is_invisible: bool = false
var _armas_lista: Array[String] = []

# ─────────────────────────────────────────────────────
# CICLO DE VIDA
# ─────────────────────────────────────────────────────

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# ── Tipo de NPC: Con Arma o Melee ─────────────────────────────────
	opt_tipo_npc.clear()
	opt_tipo_npc.add_item("Con Arma")
	opt_tipo_npc.add_item("Melee")

	# ── Equipo ────────────────────────────────────────────────────────
	opt_equipo.clear()
	opt_equipo.add_item("Equipo 2 (Enemigo)", NpcBase.Equipo.DOS)
	opt_equipo.add_item("Equipo 1 (Aliado)",  NpcBase.Equipo.UNO)

	# ── Experiencia ───────────────────────────────────────────────────
	opt_experiencia.clear()
	opt_experiencia.add_item("Baja",  NpcBase.Experiencia.BAJA)
	opt_experiencia.add_item("Media", NpcBase.Experiencia.MEDIA)
	opt_experiencia.add_item("Alta",  NpcBase.Experiencia.ALTA)

	# ── Armas desde el JSON (toda la lista) ───────────────────────────
	_poblar_armas()

	# ── Reacciones al cambiar tipo de NPC y arma ──────────────────────
	opt_tipo_npc.item_selected.connect(_on_tipo_npc_cambiado)
	opt_arma.item_selected.connect(_on_arma_seleccionada)

	# Disparar una vez para mostrar estado inicial correcto
	_on_tipo_npc_cambiado(0)
	_on_arma_seleccionada(0)

	visible = false
	panel_principal.visible = true
	panel_npc.visible = false

	btn_invisible.pressed.connect(_on_invisible_pressed)
	btn_generar.pressed.connect(_on_generar_pressed)
	btn_spawn.pressed.connect(_on_spawn_pressed)
	btn_volver.pressed.connect(_on_volver_pressed)

# ─────────────────────────────────────────────────────
# POBLADO DE ARMAS
# ─────────────────────────────────────────────────────

func _poblar_armas() -> void:
	_armas_lista.clear()
	opt_arma.clear()
	var armas_raw: Dictionary = ConfigManager._data.get("Armas", {})
	for categoria: String in armas_raw.keys():
		var cat_dict: Dictionary = armas_raw[categoria]
		for nombre_arma: String in cat_dict.keys():
			_armas_lista.append(nombre_arma)
			opt_arma.add_item("%s  [%s]" % [nombre_arma, categoria])

func _on_tipo_npc_cambiado(index: int) -> void:
	# Si es Melee, desactivar el selector de arma (no la necesita)
	var es_melee: bool = (index == 1)
	opt_arma.disabled = es_melee
	if lbl_arma_detalle:
		lbl_arma_detalle.text = "[Melee — sin arma]" if es_melee else ""

func _on_arma_seleccionada(index: int) -> void:
	if lbl_arma_detalle == null or index < 0 or index >= _armas_lista.size():
		return
	var nombre: String = _armas_lista[index]
	var cfg: Dictionary = ConfigManager.get_arma(nombre)
	if cfg.is_empty():
		return
	lbl_arma_detalle.text = (
		"%s — Daño jugador: %s | Daño NPC: %s | Cadencia: %ss" % [
			nombre,
			str(cfg.get("DañoAlJugador", "—")),
			str(cfg.get("DañoAlNPC", "—")),
			str(cfg.get("SegundosPorBala", "—")),
		]
	)

# ─────────────────────────────────────────────────────
# TOGGLE DEL MENU
# ─────────────────────────────────────────────────────

func toggle_menu() -> void:
	visible = !visible
	panel_npc.visible = false
	panel_principal.visible = true
	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ─────────────────────────────────────────────────────
# LOGICA DE BOTONES
# ─────────────────────────────────────────────────────

func _on_invisible_pressed() -> void:
	is_invisible = !is_invisible
	var player: Node = get_tree().get_first_node_in_group("player")
	if player:
		if is_invisible:
			player.add_to_group("invisible_to_npc")
			btn_invisible.text = "Invisible: ON"
			lbl_status.text = "[INVISIBLE ACTIVO]"
		else:
			player.remove_from_group("invisible_to_npc")
			btn_invisible.text = "Invisible: OFF"
			lbl_status.text = ""

func _on_generar_pressed() -> void:
	panel_principal.visible = false
	panel_npc.visible = true

func _on_volver_pressed() -> void:
	panel_npc.visible = false
	panel_principal.visible = true

func _on_spawn_pressed() -> void:
	var equipo_id: int      = opt_equipo.get_selected_id()
	var experiencia_id: int = opt_experiencia.get_selected_id()
	var es_melee: bool      = (opt_tipo_npc.get_selected() == 1)

	# ── Determinar arma ───────────────────────────────────────────────
	var arma_nombre: String = ""
	if not es_melee:
		var arma_index: int = opt_arma.get_selected()
		if arma_index >= 0 and arma_index < _armas_lista.size():
			arma_nombre = _armas_lista[arma_index]
		elif not _armas_lista.is_empty():
			arma_nombre = _armas_lista[0]

	# ── Cargar escena correcta ────────────────────────────────────────
	var scene_path: String = NPC_MELEE if es_melee else NPC_CON_ARMA
	var packed: PackedScene = load(scene_path)
	if not packed:
		push_error("DevMenu: no se pudo cargar la escena: " + scene_path)
		return

	var npc: NpcBase = packed.instantiate() as NpcBase
	if not npc:
		push_error("DevMenu: la escena '%s' no es NpcBase" % scene_path)
		return

	# ── Asignar atributos ANTES de add_child para que _ready() los lea ─
	npc.equipo          = equipo_id as NpcBase.Equipo
	npc.experiencia     = experiencia_id as NpcBase.Experiencia
	npc.weapon_name_cfg = arma_nombre

	# ── Posición frente al jugador ─────────────────────────────────────
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if not player:
		push_error("DevMenu: no se encontró al jugador")
		return
	var spawn_pos: Vector3 = player.global_transform.origin + \
		(-player.global_transform.basis.z * 3.0)

	# ── Agregar al mundo ──────────────────────────────────────────────
	var world: Node = get_tree().get_first_node_in_group("world")
	if not world:
		world = get_tree().current_scene
	world.add_child(npc)
	npc.global_transform.origin = spawn_pos

	var arma_label: String = arma_nombre if not arma_nombre.is_empty() else "Melee"
	lbl_status.text = "[SPAWNED: %s | Arma: %s | Equipo: %d]" % [
		"Melee" if es_melee else "NPC", arma_label, equipo_id
	]
