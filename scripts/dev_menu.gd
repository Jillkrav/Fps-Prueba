## Menu de desarrollo. Se activa con Q desde hud.gd.
## Nodo DevMenu en hud.tscn es tipo Control → extends Control.
extends Control

# ─────────────────────────────────────────────────────
# ESCENAS DE NPC BASE DISPONIBLES
# ─────────────────────────────────────────────────────

const NPC_CON_ARMA: String = "res://scenes/npcs/npc_pistolero.tscn"
const NPC_MELEE:    String = "res://scenes/npcs/npc_melee.tscn"

# ─────────────────────────────────────────────────────
# REFERENCIAS DE NODOS  (estructura real de hud.tscn)
# DevMenu
#   ├── PanelPrincipal/VBox/BtnInvisible
#   ├── PanelPrincipal/VBox/BtnGenerar
#   ├── PanelPrincipal/VBox/LblStatus
#   └── PanelNPC/VBox/
#         ├── GridAtributos/OptRelacion
#         ├── GridAtributos/OptExperiencia
#         ├── GridAtributos/OptArma   ← selector de TIPO (Con Arma / Melee)
#         ├── BtnSpawn
#         └── BtnVolver
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
@onready var lbl_status: Label             = $PanelPrincipal/VBox/LblStatus

# Selector de arma creado dinámicamente (no existe como nodo fijo en la escena)
var opt_arma_dinamico: OptionButton = null
var _armas_lista: Array[String] = []
var is_invisible: bool = false

# ─────────────────────────────────────────────────────
# CICLO DE VIDA
# ─────────────────────────────────────────────────────

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# ── Tipo de NPC ───────────────────────────────────────────────────
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

	# ── Crear selector de arma dinámico ───────────────────────────────
	_crear_selector_arma()

	# ── Estado inicial ────────────────────────────────────────────────
	visible = false
	panel_principal.visible = true
	panel_npc.visible = false

	btn_invisible.pressed.connect(_on_invisible_pressed)
	btn_generar.pressed.connect(_on_generar_pressed)
	btn_spawn.pressed.connect(_on_spawn_pressed)
	btn_volver.pressed.connect(_on_volver_pressed)

# Crea un OptionButton dinámico para armas debajo del GridAtributos
func _crear_selector_arma() -> void:
	if opt_arma_dinamico != null:
		opt_arma_dinamico.queue_free()

	opt_arma_dinamico = OptionButton.new()
	opt_arma_dinamico.theme_override_font_sizes["font_size"] = 14
	$PanelNPC/VBox.add_child(opt_arma_dinamico)
	# Mover antes del BtnSpawn
	$PanelNPC/VBox.move_child(opt_arma_dinamico, btn_spawn.get_index())

	_poblar_armas()

func _poblar_armas() -> void:
	if opt_arma_dinamico == null:
		return
	_armas_lista.clear()
	opt_arma_dinamico.clear()

	var armas_raw: Dictionary = {}
	if ConfigManager and ConfigManager._data.has("Armas"):
		armas_raw = ConfigManager._data["Armas"]

	for categoria in armas_raw.keys():
		for nombre in armas_raw[categoria].keys():
			_armas_lista.append(nombre)
			opt_arma_dinamico.add_item("%s [%s]" % [nombre, categoria])

	if _armas_lista.is_empty():
		_armas_lista = ["USP"]
		opt_arma_dinamico.add_item("USP [Pistolas]")
		push_warning("DevMenu: sin armas en ConfigManager, usando USP como fallback")

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

func _on_tipo_npc_changed(index: int) -> void:
	var es_melee: bool = (index == 1)
	if opt_arma_dinamico != null:
		opt_arma_dinamico.disabled = es_melee

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

	npc.equipo      = opt_equipo.get_selected_id() as NpcBase.Equipo
	npc.experiencia = opt_experiencia.get_selected_id() as NpcBase.Experiencia

	if not es_melee and opt_arma_dinamico != null:
		var idx: int = opt_arma_dinamico.get_selected()
		if idx >= 0 and idx < _armas_lista.size():
			npc.nombre_arma = _armas_lista[idx]

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

	var arma_txt: String = "Melee"
	if not es_melee and opt_arma_dinamico != null:
		var idx: int = opt_arma_dinamico.get_selected()
		if idx >= 0 and idx < _armas_lista.size():
			arma_txt = _armas_lista[idx]

	lbl_status.text = "NPC: %s | %s | Arma: %s" % [
		opt_equipo.get_item_text(opt_equipo.get_selected()),
		opt_experiencia.get_item_text(opt_experiencia.get_selected()),
		arma_txt
	]
	panel_npc.visible = false
	panel_principal.visible = true
