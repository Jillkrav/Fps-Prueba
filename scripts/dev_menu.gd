## Menu de desarrollo. Se activa con Q desde hud.gd.
## Nodo DevMenu en hud.tscn es tipo Control -> extends Control.
extends Control

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

# Panel selector de armas (creado por codigo, no necesita nodo en escena)
var _panel_armas: PanelContainer = null
var _weapon_list: VBoxContainer  = null

var opt_arma_dinamico: OptionButton = null
var _armas_lista: Array[String] = []
var is_invisible: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	opt_tipo_npc.clear()
	_poblar_armas_en(opt_tipo_npc)

	opt_relacion.clear()
	opt_relacion.add_item("Enemigo", NpcBase.Relacion.ENEMIGO)
	opt_relacion.add_item("Aliado",  NpcBase.Relacion.AMIGABLE)
	opt_relacion.add_item("Neutral", NpcBase.Relacion.NEUTRAL)

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

	# Agregar boton Selector de Armas al panel principal
	_agregar_btn_selector_armas()
	# Construir panel de armas oculto
	_build_panel_armas()

# ── Boton selector armas en panel principal ──────────────────────────
func _agregar_btn_selector_armas() -> void:
	var vbox: VBoxContainer = get_node_or_null("PanelPrincipal/VBox")
	if not vbox:
		return
	var btn := Button.new()
	btn.name = "BtnSelectorArmas"
	btn.text = "Selector de Armas"
	btn.custom_minimum_size = Vector2(0, 36)
	btn.add_theme_font_size_override("font_size", 16)
	vbox.add_child(btn)
	# insertar antes de LblStatus si existe
	var lbl: Label = get_node_or_null("PanelPrincipal/VBox/LblStatus")
	if lbl:
		vbox.move_child(btn, lbl.get_index())
	btn.pressed.connect(_on_selector_armas_pressed)

# ── Panel flotante selector de armas ─────────────────────────────────
func _build_panel_armas() -> void:
	_panel_armas = PanelContainer.new()
	_panel_armas.visible = false
	_panel_armas.set_anchors_preset(Control.PRESET_CENTER)
	_panel_armas.custom_minimum_size = Vector2(320, 0)
	_panel_armas.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel_armas.grow_vertical   = Control.GROW_DIRECTION_BOTH
	# Se agrega al mismo CanvasLayer que el DevMenu
	get_parent().add_child(_panel_armas)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top",    14)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.add_theme_constant_override("margin_left",   18)
	margin.add_theme_constant_override("margin_right",  18)
	_panel_armas.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var titulo := Label.new()
	titulo.text = "Selector de Armas"
	titulo.add_theme_font_size_override("font_size", 20)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(titulo)
	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 280)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_weapon_list = VBoxContainer.new()
	_weapon_list.add_theme_constant_override("separation", 4)
	_weapon_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_weapon_list)

	var btn_cerrar := Button.new()
	btn_cerrar.text = "Volver al Menu Dev"
	btn_cerrar.add_theme_font_size_override("font_size", 15)
	btn_cerrar.pressed.connect(_cerrar_panel_armas)
	vbox.add_child(btn_cerrar)

func _poblar_panel_armas() -> void:
	if not is_instance_valid(_weapon_list):
		return
	for child in _weapon_list.get_children():
		child.queue_free()
	var armas_raw: Dictionary = {}
	if ConfigManager and ConfigManager._data.has("Armas"):
		armas_raw = ConfigManager._data["Armas"]
	for categoria in armas_raw.keys():
		var lbl_cat := Label.new()
		lbl_cat.text = "── " + categoria + " ──"
		lbl_cat.add_theme_font_size_override("font_size", 13)
		lbl_cat.modulate = Color(0.75, 0.75, 0.75)
		_weapon_list.add_child(lbl_cat)
		for nombre_arma in armas_raw[categoria].keys():
			var btn := Button.new()
			btn.text = nombre_arma
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.custom_minimum_size = Vector2(0, 36)
			btn.add_theme_font_size_override("font_size", 17)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.pressed.connect(_on_arma_seleccionada.bind(nombre_arma))
			_weapon_list.add_child(btn)

func _on_selector_armas_pressed() -> void:
	_poblar_panel_armas()
	visible = false
	_panel_armas.visible = true

func _cerrar_panel_armas() -> void:
	_panel_armas.visible = false
	visible = true

panel_principal.visible = true

func _on_arma_seleccionada(nombre_arma: String) -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player and player.has_method("cambiar_arma"):
		player.cambiar_arma(nombre_arma)
	_panel_armas.visible = false
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Reanudar spawner si existe
	var spawners: Array = get_tree().get_nodes_in_group("spawner")
	if not spawners.is_empty():
		var sp = spawners[0]
		if sp.has_method("reanudar_spawn"):
			sp.reanudar_spawn()

# ── Helpers existentes ────────────────────────────────────────────────
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
	_armas_lista.append("")
	opt.add_item("Sin arma (Melee)")
	if _armas_lista.is_empty() or (_armas_lista.size() == 1 and _armas_lista[0] == ""):
		_armas_lista = [""]
		push_warning("DevMenu: sin armas en ConfigManager, solo opcion Melee disponible")

func toggle_menu() -> void:
	if is_instance_valid(_panel_armas) and _panel_armas.visible:
		_panel_armas.visible = false
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
