## Menu de desarrollo. Se activa con Q desde hud.gd.
## Nodo DevMenu en hud.tscn es tipo Control -> extends Control.
extends Control

# Solo usa npc_base.tscn: el arma determina el comportamiento
const NPC_SCENE: String = "res://scenes/npcs/npc_base.tscn"

@onready var panel_principal: Panel        = $PanelPrincipal
@onready var panel_npc: Panel              = $PanelNPC
@onready var btn_invisible: Button         = $PanelPrincipal/VBox/BtnInvisible
@onready var btn_generar: Button           = $PanelPrincipal/VBox/BtnGenerar
@onready var btn_spawn: Button             = $PanelNPC/VBox/BtnSpawn
@onready var btn_volver: Button            = $PanelNPC/VBox/BtnVolver
@onready var opt_relacion: OptionButton    = $PanelNPC/VBox/GridAtributos/OptRelacion
@onready var opt_experiencia: OptionButton = $PanelNPC/VBox/GridAtributos/OptExperiencia
@onready var opt_tipo_npc: OptionButton    = $PanelNPC/VBox/GridAtributos/OptArma
@onready var lbl_status: Label             = $PanelPrincipal/VBox/LblStatus

var opt_arma_dinamico: OptionButton = null
var _armas_lista: Array[String] = []
var is_invisible: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# opt_tipo_npc se reutiliza como selector de arma directamente
	opt_tipo_npc.clear()
	_poblar_armas_en(opt_tipo_npc)

	opt_relacion.clear()
	opt_relacion.add_item("Enemigo",  NpcBase.Relacion.ENEMIGO)
	opt_relacion.add_item("Aliado",   NpcBase.Relacion.AMIGABLE)
	opt_relacion.add_item("Neutral",  NpcBase.Relacion.NEUTRAL)

	opt_experiencia.clear()
	opt_experiencia.add_item("Baja",  NpcBase.Experiencia.BAJA)
	opt_experiencia.add_item("Media", NpcBase.Experiencia.MEDIA)
	opt_experiencia.add_item("Alta",  NpcBase.Experiencia.ALTA)

	visible = false
	panel_principal.visible = true
	panel_npc.visible = false

	btn_invisible.pressed.connect(_on_invisible_pressed)
	btn_generar.pressed.connect(_on_generar_pressed)
	btn_spawn.pressed.connect(_on_spawn_pressed)
	btn_volver.pressed.connect(_on_volver_pressed)

func _poblar_armas_en(opt: OptionButton) -> void:
	_armas_lista.clear()
	opt.clear()
	var armas_raw: Dictionary = {}
	if ConfigManager and ConfigManager._data.has("Armas"):
		armas_raw = ConfigManager._data["Armas"]
	for categoria in armas_raw.keys():
		for nombre in armas_raw[categoria].keys():
			_armas_lista.append(nombre)
			opt.add_item("%s [%s]" % [nombre, categoria])
	# Opcion sin arma (melee)
	_armas_lista.append("")
	opt.add_item("Sin arma (Melee)")
	if _armas_lista.is_empty() or (_armas_lista.size() == 1 and _armas_lista[0] == ""):
		_armas_lista = [""]
		push_warning("DevMenu: sin armas en ConfigManager, solo opcion Melee disponible")

func toggle_menu() -> void:
	visible = !visible
	panel_npc.visible = false
	panel_principal.visible = true
	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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
	var packed: PackedScene = load(NPC_SCENE)
	if not packed:
		push_error("DevMenu: no se pudo cargar escena: " + NPC_SCENE)
		return

	var npc: NpcBase = packed.instantiate() as NpcBase
	if not npc:
		push_error("DevMenu: la escena no instancio NpcBase")
		return

	# Asignar relacion, experiencia y arma ANTES de add_child
	npc._relacion_forzada = true
	npc.relacion    = opt_relacion.get_selected_id() as NpcBase.Relacion
	npc.experiencia = opt_experiencia.get_selected_id() as NpcBase.Experiencia

	var idx: int = opt_tipo_npc.get_selected()
	if idx >= 0 and idx < _armas_lista.size():
		npc.nombre_arma = _armas_lista[idx]

	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if not player:
		push_error("DevMenu: no se encontro al jugador")
		npc.queue_free()
		return

	var spawn_pos: Vector3 = player.global_transform.origin \
		+ player.global_transform.basis.z * -3.0
	spawn_pos.y = player.global_transform.origin.y

	var world: Node = player.get_parent()
	world.add_child(npc)
	npc.global_transform.origin = spawn_pos

	var arma_txt: String = npc.nombre_arma if npc.nombre_arma != "" else "Melee"
	lbl_status.text = "NPC: %s | %s | Arma: %s" % [
		opt_relacion.get_item_text(opt_relacion.get_selected()),
		opt_experiencia.get_item_text(opt_experiencia.get_selected()),
		arma_txt
	]
	panel_npc.visible = false
	panel_principal.visible = true
