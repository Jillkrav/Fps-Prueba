## Menu de desarrollo. Se activa con Q desde hud.gd.
## Permite: ponerse invisible a los NPC y spawnear cualquier NPC con cualquier arma del JSON.
extends Control

# ─────────────────────────────────────────────────────
# ESCENAS DE NPC BASE DISPONIBLES
# Solo 2 tipos: con arma (pistolero) y melee.
# El arma se asigna por separado desde el selector.
# ─────────────────────────────────────────────────────

const NPC_CON_ARMA: String = "res://scenes/npcs/npc_pistolero.tscn"
const NPC_MELEE:    String = "res://scenes/npcs/npc_melee.tscn"

# ─────────────────────────────────────────────────────
# REFERENCIAS DE NODOS  (estructura real de hud.tscn)
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
	opt_tipo_npc.item_selected.connect(_on_tipo_npc_changed)

	# ── Equipo ────────────────────────────────────────────────────────
	opt_equipo.clear()
	opt_equipo.add_item("Equipo 2 (Enemigo)", NpcBase.Equipo.DOS)
	opt_equipo.add_item("Equipo 1 (Aliado)",  NpcBase.Equipo.UNO)

	# ── Experiencia ───────────────────────────────────────────────────
	opt_experiencia.clear()
	opt_experiencia.add_item("Baja",  NpcBase.Experiencia.BAJA)
	opt_experiencia.add_item("Media", NpcBase.Experiencia.MEDIA)
	opt_experiencia.add_item("Alta",  NpcBase.Experiencia.ALTA)

	# ── Armas desde ConfigManager ─────────────────────────────────────
	_populate_armas()

	# ── Estado inicial ────────────────────────────────────────────────
	visible = false
	panel_principal.visible = true
	panel_npc.visible = false

	btn_invisible.pressed.connect(_on_invisible_pressed)
	btn_generar.pressed.connect(_on_generar_pressed)
	btn_spawn.pressed.connect(_on_spawn_pressed)
	btn_volver.pressed.connect(_on_volver_pressed)
	opt_arma.item_selected.connect(_on_arma_selected)

# Lee las armas disponibles desde ConfigManager
func _populate_armas() -> void:
	_armas_lista.clear()
	opt_arma.clear()
	# Obtener todas las categorías y armas del JSON
	var armas_cfg: Dictionary = {}
	if ConfigManager and ConfigManager._data.has("Armas"):
		armas_cfg = ConfigManager._data["Armas"]
	for categoria in armas_cfg.values():
		for nombre in categoria.keys():
			_armas_lista.append(nombre)
			opt_arma.add_item(nombre)
	# Fallback si no hay config cargada
	if _armas_lista.is_empty():
		_armas_lista = ["USP"]
		opt_arma.add_item("USP")
	opt_arma.disabled = false

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
	# Refrescar armas al abrir el panel
	_populate_armas()

func _on_volver_pressed() -> void:
	panel_npc.visible = false
	panel_principal.visible = true

func _on_tipo_npc_changed(index: int) -> void:
	# Si es Melee, deshabilitar selector de arma
	var es_melee: bool = (index == 1)
	opt_arma.disabled = es_melee
	if lbl_arma_detalle:
		lbl_arma_detalle.text = ""

func _on_arma_selected(index: int) -> void:
	if lbl_arma_detalle == null:
		return
	if index < 0 or index >= _armas_lista.size():
		return
	var nombre: String = _armas_lista[index]
	var cfg: Dictionary = ConfigManager.get_arma(nombre)
	if cfg.is_empty():
		lbl_arma_detalle.text = ""
		return
	lbl_arma_detalle.text = "%s  |  Daño: %s  |  Cadencia: %ss  |  Cargador: %s" % [
		nombre,
		str(cfg.get("DañoAlNPC", "?")),
		str(cfg.get("SegundosPorBala", "?")),
		str(cfg.get("TamañoCargador", "?"))
	]

func _on_spawn_pressed() -> void:
	var es_melee: bool = (opt_tipo_npc.get_selected() == 1)
	var escena_path: String = NPC_MELEE if es_melee else NPC_CON_ARMA

	var packed: PackedScene = load(escena_path)
	if not packed:
		push_error("DevMenu: no se pudo cargar escena: " + escena_path)
		return

	var npc: NpcBase = packed.instantiate() as NpcBase
	if not npc:
		push_error("DevMenu: la escena no es un NpcBase: " + escena_path)
		return

	# ── Aplicar equipo y experiencia ──────────────────────────────────
	npc.equipo      = opt_equipo.get_selected_id() as NpcBase.Equipo
	npc.experiencia = opt_experiencia.get_selected_id() as NpcBase.Experiencia

	# ── Asignar arma si no es melee ───────────────────────────────────
	if not es_melee and _armas_lista.size() > 0:
		var idx: int = opt_arma.get_selected()
		if idx >= 0 and idx < _armas_lista.size():
			npc.nombre_arma = _armas_lista[idx]

	# ── Spawn cerca del jugador ───────────────────────────────────────
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if not player:
		push_error("DevMenu: no se encontró al jugador")
		npc.queue_free()
		return

	var spawn_pos: Vector3 = player.global_transform.origin \
		+ player.global_transform.basis.z * -3.0
	spawn_pos.y = player.global_transform.origin.y

	var world: Node = player.get_parent()
	world.add_child(npc)
	npc.global_transform.origin = spawn_pos

	var nombre_arma_txt: String = _armas_lista[opt_arma.get_selected()] if not es_melee else "Melee"
	lbl_status.text = "NPC spawneado | %s | %s | Arma: %s" % [
		opt_equipo.get_item_text(opt_equipo.get_selected()),
		opt_experiencia.get_item_text(opt_experiencia.get_selected()),
		nombre_arma_txt
	]
	panel_npc.visible = false
	panel_principal.visible = true
