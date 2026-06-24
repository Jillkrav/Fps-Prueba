## Menu de desarrollo. Se activa con Q desde hud.gd.
## Permite: ponerse invisible a los NPC y spawnear NPC con arma elegida del JSON.
extends Control

# ─────────────────────────────────────────────────────
# ESCENAS DE NPC DISPONIBLES
# ─────────────────────────────────────────────────────

const NPC_SCENES: Dictionary = {
	"Melee":      "res://scenes/npcs/npc_melee.tscn",
	"Pistolero":  "res://scenes/npcs/npc_pistolero.tscn",
	"Escopetero": "res://scenes/npcs/npc_escopetero.tscn",
}

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
@onready var lbl_status: Label             = $PanelPrincipal/VBox/LblStatus

# opt_arma_cfg es opcional: si no existe el nodo en la escena, el menú usa
# la primera arma de la lista como fallback sin crashear.
var opt_arma_cfg: OptionButton = null

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

	# Intentar obtener el nodo opcional de selección de arma
	opt_arma_cfg = get_node_or_null("PanelNPC/VBox/GridAtributos/OptArmaCfg") as OptionButton

	# Equipo
	opt_equipo.add_item("Equipo 2 (Enemigo)", NpcBase.Equipo.DOS)
	opt_equipo.add_item("Equipo 1 (Aliado)",  NpcBase.Equipo.UNO)

	# Experiencia
	opt_experiencia.add_item("Baja",  NpcBase.Experiencia.BAJA)
	opt_experiencia.add_item("Media", NpcBase.Experiencia.MEDIA)
	opt_experiencia.add_item("Alta",  NpcBase.Experiencia.ALTA)

	# Tipo de NPC
	for tipo in NPC_SCENES.keys():
		opt_tipo_npc.add_item(tipo)

	# Poblar armas desde ConfigManager (solo si el nodo existe en la escena)
	_poblar_armas()

	visible = false
	panel_principal.visible = true
	panel_npc.visible = false

	btn_invisible.pressed.connect(_on_invisible_pressed)
	btn_generar.pressed.connect(_on_generar_pressed)
	btn_spawn.pressed.connect(_on_spawn_pressed)
	btn_volver.pressed.connect(_on_volver_pressed)

## Llena opt_arma_cfg con todas las armas del JSON.
## Si el nodo no existe en la escena, no hace nada (sin crash).
func _poblar_armas() -> void:
	_armas_lista.clear()
	if opt_arma_cfg == null:
		# El nodo aún no existe en la escena — la lista se usa como fallback
		var armas_raw: Dictionary = ConfigManager._data.get("Armas", {})
		for categoria: Dictionary in armas_raw.values():
			for nombre_arma: String in categoria.keys():
				_armas_lista.append(nombre_arma)
		return

	opt_arma_cfg.clear()
	var armas_raw: Dictionary = ConfigManager._data.get("Armas", {})
	for categoria in armas_raw.keys():
		var cat_dict: Dictionary = armas_raw[categoria]
		for nombre_arma: String in cat_dict.keys():
			_armas_lista.append(nombre_arma)
			opt_arma_cfg.add_item("%s (%s)" % [nombre_arma, categoria])

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
	var tipo_key: String    = NPC_SCENES.keys()[opt_tipo_npc.get_selected()]

	# Obtener arma: usar opt_arma_cfg si existe, sino tomar la primera de la lista
	var arma_nombre: String = "USP"
	if opt_arma_cfg != null:
		var arma_index: int = opt_arma_cfg.get_selected()
		if arma_index >= 0 and arma_index < _armas_lista.size():
			arma_nombre = _armas_lista[arma_index]
	elif not _armas_lista.is_empty():
		arma_nombre = _armas_lista[0]

	# Para NPC Melee ignorar el arma seleccionada
	if tipo_key == "Melee":
		arma_nombre = ""

	var scene_path: String = NPC_SCENES[tipo_key]
	var packed: PackedScene = load(scene_path)
	if not packed:
		push_error("DevMenu: no se pudo cargar la escena: " + scene_path)
		return

	var npc: NpcBase = packed.instantiate() as NpcBase
	if not npc:
		push_error("DevMenu: la escena '%s' no es NpcBase" % scene_path)
		return

	npc.equipo          = equipo_id as NpcBase.Equipo
	npc.experiencia     = experiencia_id as NpcBase.Experiencia
	npc.weapon_name_cfg = arma_nombre

	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if not player:
		push_error("DevMenu: no se encontró al jugador")
		return

	var spawn_pos: Vector3 = player.global_transform.origin + \
		(-player.global_transform.basis.z * 3.0)

	var world: Node = get_tree().get_first_node_in_group("world")
	if not world:
		world = get_tree().current_scene

	world.add_child(npc)
	npc.global_transform.origin = spawn_pos

	var arma_label: String = arma_nombre if not arma_nombre.is_empty() else "Melee"
	lbl_status.text = "[SPAWNED: %s | Arma: %s | Equipo: %d]" % [tipo_key, arma_label, equipo_id]
