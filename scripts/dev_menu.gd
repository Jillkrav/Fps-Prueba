## Menu de desarrollo. Se activa con Q desde hud.gd.
extends Control

const NPC_SCENE: String = "res://scenes/npcs/npc.tscn"

@onready var panel_principal: Panel        = $PanelPrincipal
@onready var panel_npc: Panel              = $PanelNPC
@onready var btn_invisible: Button         = $PanelPrincipal/VBox/BtnInvisible
@onready var btn_generar: Button           = $PanelPrincipal/VBox/BtnGenerar
@onready var btn_spawn: Button             = $PanelNPC/VBox/BtnSpawn
@onready var btn_volver: Button            = $PanelNPC/VBox/BtnVolver
@onready var opt_relacion: OptionButton    = $PanelNPC/VBox/GridAtributos/OptRelacion
@onready var opt_experiencia: OptionButton = $PanelNPC/VBox/GridAtributos/OptExperiencia
@onready var opt_tipo_npc: OptionButton    = $PanelNPC/VBox/GridAtributos/OptArma
@onready var opt_rol: OptionButton         = $PanelNPC/VBox/GridAtributos/OptRol
@onready var lbl_status: Label             = $PanelPrincipal/VBox/LblStatus

var _panel_armas: PanelContainer    = null
var _weapon_list: VBoxContainer     = null
var _panel_equipo: PanelContainer   = null
var _armas_lista: Array[String]     = []
var is_invisible: bool              = false
var ai_disabled: bool               = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# --- Equipo para spawn de NPC ---
	opt_relacion.clear()
	for id in GameState.NOMBRE_EQUIPO.keys():
		opt_relacion.add_item(GameState.nombre_equipo(id), id)
	_seleccionar_opcion(opt_relacion, Enums.Equipo.ROJO)

	# --- Experiencia ---
	opt_experiencia.clear()
	opt_experiencia.add_item("Baja",  Enums.Experiencia.BAJA)
	opt_experiencia.add_item("Media", Enums.Experiencia.MEDIA)
	opt_experiencia.add_item("Alta",  Enums.Experiencia.ALTA)

	# --- Arma del NPC ---
	opt_tipo_npc.clear()
	_poblar_armas_en(opt_tipo_npc)

	# --- Rol del NPC ---
	opt_rol.clear()
	opt_rol.add_item("Soldado",       Enums.Rol.SOLDADO)
	opt_rol.add_item("Francotirador", Enums.Rol.FRANCOTIRADOR)
	opt_rol.add_item("Apoyo",         Enums.Rol.APOYO)
	opt_rol.add_item("Explorador",    Enums.Rol.EXPLORADOR)
	opt_rol.add_item("Comandante",    Enums.Rol.COMANDANTE)

	visible = false
	panel_principal.visible = true
	panel_npc.visible       = false

	btn_invisible.pressed.connect(_on_invisible_pressed)
	btn_generar.pressed.connect(_on_generar_pressed)
	btn_spawn.pressed.connect(_on_spawn_pressed)
	btn_volver.pressed.connect(_on_volver_pressed)

	_agregar_botones_extras()
	_build_panel_armas.call_deferred()
	_build_panel_equipo.call_deferred()

# Selecciona la opcion del OptionButton cuyo id coincide
func _seleccionar_opcion(opt: OptionButton, id: int) -> void:
	for i in opt.item_count:
		if opt.get_item_id(i) == id:
			opt.select(i)
			return

# ── Botones extras en panel principal ────────────────────────────────────────
func _agregar_botones_extras() -> void:
	var vbox: VBoxContainer = get_node_or_null("PanelPrincipal/VBox")
	if not vbox:
		return
	var lbl: Label = get_node_or_null("PanelPrincipal/VBox/LblStatus")
	var insert_idx: int = lbl.get_index() if lbl else vbox.get_child_count()

	# Boton selector de armas
	var btn_armas := Button.new()
	btn_armas.name = "BtnSelectorArmas"
	btn_armas.text = "Selector de Armas"
	btn_armas.custom_minimum_size = Vector2(0, 36)
	btn_armas.add_theme_font_size_override("font_size", 16)
	btn_armas.pressed.connect(_on_selector_armas_pressed)
	vbox.add_child(btn_armas)
	vbox.move_child(btn_armas, insert_idx)

	# Boton cambiar equipo
	var btn_equipo := Button.new()
	btn_equipo.name = "BtnCambiarEquipo"
	btn_equipo.text = "Cambiar Equipo [%s]" % GameState.nombre_equipo(GameState.player_team)
	btn_equipo.custom_minimum_size = Vector2(0, 36)
	btn_equipo.add_theme_font_size_override("font_size", 16)
	btn_equipo.pressed.connect(_on_cambiar_equipo_pressed)
	vbox.add_child(btn_equipo)
	vbox.move_child(btn_equipo, insert_idx + 1)

	# Boton AI disable
	var btn_ai := Button.new()
	btn_ai.name = "BtnAiDisable"
	btn_ai.text = "Ai disable [OFF]"
	btn_ai.custom_minimum_size = Vector2(0, 36)
	btn_ai.add_theme_font_size_override("font_size", 16)
	btn_ai.pressed.connect(_on_ai_disable_pressed)
	vbox.add_child(btn_ai)
	vbox.move_child(btn_ai, insert_idx + 2)
	
	# Boton debug overlay
	var btn_debug_overlay := Button.new()
	btn_debug_overlay.name = "BtnBotDebug"
	btn_debug_overlay.text = "Bot Debug Info [OFF]"
	btn_debug_overlay.custom_minimum_size = Vector2(0, 36)
	btn_debug_overlay.add_theme_font_size_override("font_size", 16)
	btn_debug_overlay.pressed.connect(_on_bot_debug_pressed)
	vbox.add_child(btn_debug_overlay)
	vbox.move_child(btn_debug_overlay, insert_idx + 3)
	
	# Boton propiedades de unidad (Cargador, Total balas, Vida)
	var btn_unit_props := Button.new()
	btn_unit_props.name = "BtnUnitProps"
	btn_unit_props.text = "Propiedades de unidad [OFF]"
	btn_unit_props.custom_minimum_size = Vector2(0, 36)
	btn_unit_props.add_theme_font_size_override("font_size", 16)
	btn_unit_props.pressed.connect(_on_unit_props_pressed)
	vbox.add_child(btn_unit_props)
	vbox.move_child(btn_unit_props, insert_idx + 4)

	# ── Botones de TeamAI (FASE 6) ──
	# Boton mostrar resumen de TeamAI
	var btn_team_ai := Button.new()
	btn_team_ai.name = "BtnTeamAI"
	btn_team_ai.text = "Mostrar TeamAI"
	btn_team_ai.custom_minimum_size = Vector2(0, 36)
	btn_team_ai.add_theme_font_size_override("font_size", 16)
	btn_team_ai.pressed.connect(_on_team_ai_pressed)
	vbox.add_child(btn_team_ai)
	vbox.move_child(btn_team_ai, insert_idx + 5)

	# Boton re-asignar ordenes a todos los bots
	var btn_reassign := Button.new()
	btn_reassign.name = "BtnReassignOrders"
	btn_reassign.text = "Re-asignar Ordenes"
	btn_reassign.custom_minimum_size = Vector2(0, 36)
	btn_reassign.add_theme_font_size_override("font_size", 16)
	btn_reassign.pressed.connect(_on_reassign_orders_pressed)
	vbox.add_child(btn_reassign)
	vbox.move_child(btn_reassign, insert_idx + 6)

	# ── Boton mostrar puntos semánticos (FASE 7) ──
	var btn_semantic := Button.new()
	btn_semantic.name = "BtnSemanticPoints"
	btn_semantic.text = "Mostrar Puntos Semánticos [OFF]"
	btn_semantic.custom_minimum_size = Vector2(0, 36)
	btn_semantic.add_theme_font_size_override("font_size", 16)
	btn_semantic.pressed.connect(_on_semantic_points_pressed)
	vbox.add_child(btn_semantic)
	vbox.move_child(btn_semantic, insert_idx + 7)

# ── Panel flotante selector de armas ─────────────────────────────────────────
# FIX: se usa PRESET_CENTER_TOP + offset para que el panel NO se salga de pantalla.
# El panel se agrega al CanvasLayer raiz (HUDLayer) para que siempre quede en pantalla.
func _build_panel_armas() -> void:
	_panel_armas = PanelContainer.new()
	_panel_armas.visible = false

	# Anclar al centro de la pantalla con tamano fijo
	_panel_armas.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE, 0)
	_panel_armas.anchor_left   = 0.5
	_panel_armas.anchor_top    = 0.5
	_panel_armas.anchor_right  = 0.5
	_panel_armas.anchor_bottom = 0.5
	_panel_armas.offset_left   = -175.0
	_panel_armas.offset_top    = -220.0
	_panel_armas.offset_right  =  175.0
	_panel_armas.offset_bottom =  220.0
	_panel_armas.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel_armas.grow_vertical   = Control.GROW_DIRECTION_BOTH

	# Subir al nodo padre que sea CanvasLayer para que quede sobre todo
	var canvas_parent: Node = get_parent()
	canvas_parent.add_child(_panel_armas)

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

# ── Panel flotante cambiar equipo ─────────────────────────────────────────────
func _build_panel_equipo() -> void:
	_panel_equipo = PanelContainer.new()
	_panel_equipo.visible = false

	_panel_equipo.anchor_left   = 0.5
	_panel_equipo.anchor_top    = 0.5
	_panel_equipo.anchor_right  = 0.5
	_panel_equipo.anchor_bottom = 0.5
	_panel_equipo.offset_left   = -160.0
	_panel_equipo.offset_top    = -160.0
	_panel_equipo.offset_right  =  160.0
	_panel_equipo.offset_bottom =  160.0
	_panel_equipo.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel_equipo.grow_vertical   = Control.GROW_DIRECTION_BOTH

	var canvas_parent: Node = get_parent()
	canvas_parent.add_child(_panel_equipo)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top",    14)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.add_theme_constant_override("margin_left",   18)
	margin.add_theme_constant_override("margin_right",  18)
	_panel_equipo.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var titulo := Label.new()
	titulo.text = "Cambiar Equipo"
	titulo.add_theme_font_size_override("font_size", 20)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(titulo)
	vbox.add_child(HSeparator.new())

	for id in GameState.NOMBRE_EQUIPO.keys():
		var nombre: String = GameState.nombre_equipo(id)
		var color: Color   = GameState.color_equipo(id)
		var btn := Button.new()
		btn.text = nombre
		btn.custom_minimum_size = Vector2(0, 40)
		btn.add_theme_font_size_override("font_size", 18)
		btn.add_theme_color_override("font_color", color)
		btn.pressed.connect(_on_equipo_elegido.bind(id))
		vbox.add_child(btn)

	vbox.add_child(HSeparator.new())
	var btn_cerrar := Button.new()
	btn_cerrar.text = "Cancelar"
	btn_cerrar.add_theme_font_size_override("font_size", 15)
	btn_cerrar.pressed.connect(_cerrar_panel_equipo)
	vbox.add_child(btn_cerrar)

func _on_equipo_elegido(id: int) -> void:
	# Solo permitir cambio de equipo si la partida ya empezo.
	# Antes de eso, el jugador usa team_weapon_selector para elegir equipo.
	if is_instance_valid(MatchManager) and MatchManager.is_match_started():
		MatchManager.cambiar_equipo_jugador(id)
	else:
		# No hacer nada — el jugador no deberia cambiar equipo antes de empezar
		push_warning("[DevMenu] No se puede cambiar equipo: la partida no ha empezado")
		_cerrar_panel_equipo()
		return
	
	# Actualizar texto del boton
	var btn_eq: Button = get_node_or_null("PanelPrincipal/VBox/BtnCambiarEquipo")
	if is_instance_valid(btn_eq):
		btn_eq.text = "Cambiar Equipo [%s]" % GameState.nombre_equipo(id)
	_cerrar_panel_equipo()

func _cerrar_panel_equipo() -> void:
	_panel_equipo.visible = false
	visible = true
	panel_principal.visible = true

# ── Logica panel armas ────────────────────────────────────────────────────────
func _poblar_panel_armas() -> void:
	if not is_instance_valid(_weapon_list):
		return
	for child in _weapon_list.get_children():
		child.queue_free()
	# Categorias conocidas de skill.json (sin acceder a _data directamente)
	var categorias: Array[String] = ["Pistolas", "Escopetas", "Subfusiles", "Rifles", "Francotiradores", "Melee"]
	for categoria in categorias:
		var armas_cat: Array[String] = ConfigManager.get_nombres_armas(categoria)
		if armas_cat.is_empty():
			continue
		var lbl_cat := Label.new()
		lbl_cat.text = "-- " + categoria + " --"
		lbl_cat.add_theme_font_size_override("font_size", 13)
		lbl_cat.modulate = Color(0.75, 0.75, 0.75)
		_weapon_list.add_child(lbl_cat)
		for nombre_arma in armas_cat:
			var btn := Button.new()
			btn.text = nombre_arma
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.custom_minimum_size = Vector2(0, 36)
			btn.add_theme_font_size_override("font_size", 17)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.pressed.connect(_on_arma_seleccionada.bind(nombre_arma))
			_weapon_list.add_child(btn)

func _on_selector_armas_pressed() -> void:
	if not is_instance_valid(_panel_armas):
		await get_tree().process_frame
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
	# Los spawners ya no gestionan timers de spawn.
	# El MatchManager maneja toda la logica de respawn.
	if MatchManager.get("player") != null:
		print("[DevMenu] MatchManager activo - %d bots en pool, %d activos azul, %d activos rojo" % [
			MatchManager.bot_pool.size(), MatchManager.blue_bots_active, MatchManager.red_bots_active
		])

# ── Helpers generales ─────────────────────────────────────────────────────────
func _poblar_armas_en(opt: OptionButton) -> void:
	_armas_lista.clear()
	opt.clear()
	_armas_lista = ConfigManager.get_nombres_armas()
	for nombre in _armas_lista:
		opt.add_item(nombre)
	_armas_lista.append("")
	opt.add_item("Sin arma (Melee)")

func toggle_menu() -> void:
	if is_instance_valid(_panel_armas) and _panel_armas.visible:
		_panel_armas.visible = false
	if is_instance_valid(_panel_equipo) and _panel_equipo.visible:
		_panel_equipo.visible = false
	visible = !visible
	panel_npc.visible       = false
	panel_principal.visible = true
	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_invisible_pressed() -> void:
	is_invisible = !is_invisible
	var player: Node = get_tree().get_first_node_in_group("player")
	if player:
		player.is_invisible = is_invisible
		btn_invisible.text = "Invisible: ON" if is_invisible else "Invisible: OFF"
		lbl_status.text = "[INVISIBLE ACTIVO]" if is_invisible else ""

func _on_ai_disable_pressed() -> void:
	ai_disabled = !ai_disabled
	var btn: Button = get_node_or_null("PanelPrincipal/VBox/BtnAiDisable")
	if not btn:
		return

	if ai_disabled:
		for bot in MatchManager.bot_pool:
			if is_instance_valid(bot) and not bot.is_dead:
				bot.process_mode = Node.PROCESS_MODE_DISABLED
				if bot is CharacterBody3D:
					bot.velocity = Vector3.ZERO
		btn.text = "Ai disable [ON]"
		lbl_status.text = "[AI DISABLE ACTIVO]"
	else:
		for bot in MatchManager.bot_pool:
			if is_instance_valid(bot):
				bot.process_mode = Node.PROCESS_MODE_INHERIT
		btn.text = "Ai disable [OFF]"
		lbl_status.text = ""

func _on_generar_pressed() -> void:
	panel_principal.visible = false
	panel_npc.visible       = true

func _on_volver_pressed() -> void:
	panel_npc.visible       = false
	panel_principal.visible = true

func _on_bot_debug_pressed() -> void:
	NpcBase.toggle_debug_overlay_all()
	var btn: Button = get_node_or_null("PanelPrincipal/VBox/BtnBotDebug")
	if btn:
		btn.text = "Bot Debug Info [ON]" if BotDebugOverlay.enabled else "Bot Debug Info [OFF]"
	lbl_status.text = "Bot Debug %s" % ("ACTIVADO" if BotDebugOverlay.enabled else "DESACTIVADO")

func _on_unit_props_pressed() -> void:
	BotDebugOverlay.toggle_unit_properties_all()
	var btn: Button = get_node_or_null("PanelPrincipal/VBox/BtnUnitProps")
	if btn:
		btn.text = "Propiedades de unidad [ON]" if BotDebugOverlay.enabled else "Propiedades de unidad [OFF]"
	lbl_status.text = "Propiedades de unidad %s" % ("ACTIVADO" if BotDebugOverlay.enabled else "DESACTIVADO")

func _on_cambiar_equipo_pressed() -> void:
	visible = false
	_panel_equipo.visible = true

func _on_team_ai_pressed() -> void:
	# Mostrar resumen del estado de TeamAI en la consola
	if not is_instance_valid(TeamAI):
		lbl_status.text = "[TeamAI NO DISPONIBLE]"
		return

	var summary: String = TeamAI.get_debug_summary()
	print(summary)
	lbl_status.text = "TeamAI: %d objetivos, %d bots con orden" % [
		TeamAI.objectives.size(),
		TeamAI.bot_orders.size()
	]


func _on_reassign_orders_pressed() -> void:
	if not is_instance_valid(TeamAI):
		lbl_status.text = "[TeamAI NO DISPONIBLE]"
		return

	TeamAI.assign_orders_all()
	lbl_status.text = "[ORDENES RE-ASIGNADAS a todos los bots]"
	print("[DevMenu] Ordenes re-asignadas a todos los bots via TeamAI")


var _semantic_points_visible: bool = false

func _on_semantic_points_pressed() -> void:
	_semantic_points_visible = not _semantic_points_visible
	
	var btn: Button = get_node_or_null("PanelPrincipal/VBox/BtnSemanticPoints")
	if btn:
		btn.text = "Mostrar Puntos Semánticos [ON]" if _semantic_points_visible else "Mostrar Puntos Semánticos [OFF]"
	
	# Mostrar/ocultar marcadores de puntos semánticos en el mapa
	if _semantic_points_visible:
		var points: Array = NavigationSystem.all_semantic_points
		if points.size() == 0:
			NavigationSystem.load_semantic_points()
			points = NavigationSystem.all_semantic_points
		lbl_status.text = "Puntos semánticos: %d cargados" % points.size()
		_debug_draw_semantic_points()
	else:
		_clear_semantic_point_debug()
		lbl_status.text = "Puntos semánticos ocultos"


## Dibuja marcadores 3D temporales para los puntos semánticos.
func _debug_draw_semantic_points() -> void:
	var points: Array = NavigationSystem.all_semantic_points
	for sp in points:
		_show_semantic_point_marker(sp)


## Crea un marcador visual 3D para un punto semántico.
func _show_semantic_point_marker(sp: SemanticPoint) -> void:
	var marker := MeshInstance3D.new()
	
	# Color según tipo
	var color: Color
	match sp.point_type:
		SemanticPoint.PointType.PATH:
			color = Color(1, 1, 1)  # Blanco
		SemanticPoint.PointType.AMBUSH:
			color = Color(1, 0.5, 0)  # Naranja
		SemanticPoint.PointType.DEFENSE:
			color = Color(0, 0.5, 1)  # Azul claro
		SemanticPoint.PointType.ALTERNATE:
			color = Color(1, 0, 1)  # Magenta
		SemanticPoint.PointType.LIFT:
			color = Color(0, 1, 0.5)  # Verde agua
		SemanticPoint.PointType.ITEM:
			color = Color(1, 1, 0)  # Amarillo
		SemanticPoint.PointType.SNIPER:
			color = Color(1, 0, 0)  # Rojo
		_:
			color = Color(0.5, 0.5, 0.5)
	
	# Crear un cubo pequeño como marcador
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.5
	mat.vertex_color_use_as_albedo = false
	
	box.material = mat
	marker.mesh = box
	
	# Nombrarlo para poder limpiarlo después
	var type_id: int = sp.point_type
	marker.name = "SemPointDebug_%d" % type_id
	
	# Crear etiqueta de texto con el nombre del tipo
	var label := Label3D.new()
	var type_name: String = SemanticPoint.PointType.keys()[type_id] \
		if type_id >= 0 and type_id < SemanticPoint.PointType.size() else "?"
	label.text = type_name
	label.font_size = 24
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	label.outline_modulate = Color(0, 0, 0, 0.8)
	label.outline_size = 2
	label.name = "SemPointLabel_%d" % type_id
	
	# Añadir al nodo raíz PRIMERO, luego posicionar
	var root: Node = get_tree().current_scene
	if root:
		root.add_child(marker)
		marker.global_position = sp.position + Vector3.UP * 1.0
		root.add_child(label)
		label.global_position = sp.position + Vector3.UP * 1.8


## Limpia los marcadores de debug de puntos semánticos.
func _clear_semantic_point_debug() -> void:
	var root: Node = get_tree().current_scene
	if not root:
		return
	for child in root.get_children():
		if child.name.begins_with("SemPointDebug_") or child.name.begins_with("SemPointLabel_"):
			child.queue_free()


func _on_spawn_pressed() -> void:
	var packed: PackedScene = load(NPC_SCENE)
	if not packed:
		push_error("DevMenu: no se pudo cargar escena: " + NPC_SCENE)
		return
	var npc: NpcBase = packed.instantiate() as NpcBase
	if not npc:
		push_error("DevMenu: la escena no instancio NpcBase")
		return

	npc.equipo_id = opt_relacion.get_selected_id()
	npc.experiencia = opt_experiencia.get_selected_id()
	npc.rol = opt_rol.get_selected_id()
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
	player.get_parent().add_child(npc)
	npc.global_transform.origin = spawn_pos

	var arma_txt: String = npc.nombre_arma if npc.nombre_arma != "" else "Melee"
	lbl_status.text = "NPC spawneado: %s | %s | Rol: %s | Arma: %s" % [
		GameState.nombre_equipo(npc.equipo_id),
		opt_experiencia.get_item_text(opt_experiencia.get_selected()),
		opt_rol.get_item_text(opt_rol.get_selected()),
		arma_txt
	]
	panel_npc.visible       = false
	panel_principal.visible = true
