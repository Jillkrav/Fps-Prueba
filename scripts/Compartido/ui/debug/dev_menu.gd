## Menu de desarrollo. Se activa con Q desde hud.gd.
extends Control

const BOT_SCENE: String = "res://scenes/Multiplayer/objetos/bots/bot.tscn"

@onready var panel_principal: Panel        = $PanelPrincipal
@onready var panel_npc: Panel              = $PanelNPC
@onready var btn_invisible: Button         = $PanelPrincipal/ScrollContainer/VBox/BtnInvisible
@onready var btn_generar: Button           = $PanelPrincipal/ScrollContainer/VBox/BtnGenerar
@onready var btn_spawn: Button             = $PanelNPC/VBox/BtnSpawn
@onready var btn_volver: Button            = $PanelNPC/VBox/BtnVolver
@onready var opt_relacion: OptionButton    = $PanelNPC/VBox/GridAtributos/OptRelacion
@onready var opt_experiencia: OptionButton = $PanelNPC/VBox/GridAtributos/OptExperiencia
@onready var opt_tipo_npc: OptionButton    = $PanelNPC/VBox/GridAtributos/OptArma
@onready var opt_rol: OptionButton         = $PanelNPC/VBox/GridAtributos/OptRol
@onready var lbl_status: Label             = $PanelPrincipal/ScrollContainer/VBox/LblStatus

var _panel_armas: PanelContainer    = null
var _weapon_list: VBoxContainer     = null
var _panel_equipo: PanelContainer   = null
var _armas_lista: Array[String]     = []
var is_invisible: bool              = false
var ai_disabled: bool               = false
var _mostrar_caminos: bool          = false
var _mostrar_zonas_debug: bool      = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _is_story_mode():
		btn_generar.text = "Spawnear Zombie"

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
	opt_rol.add_item("Versatil",    Roles.Type.VERSATIL)
	opt_rol.add_item("Asalto",        Roles.Type.ASALTO)
	opt_rol.add_item("Flanqueador",   Roles.Type.FLANQUEADOR)
	opt_rol.add_item("Defensor",      Roles.Type.DEFENSOR)
	opt_rol.add_item("Patrullador",   Roles.Type.PATRULLADOR)
	opt_rol.add_item("Francotirador", Roles.Type.FRANCOTIRADOR)
	opt_rol.add_item("Apoyo",         Roles.Type.APOYO)

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
	var vbox: VBoxContainer = get_node_or_null("PanelPrincipal/ScrollContainer/VBox")
	if not vbox:
		return
	var lbl: Label = get_node_or_null("PanelPrincipal/ScrollContainer/VBox/LblStatus")
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

	# Boton cambiar equipo (solo para multijugador).
	if not _is_story_mode():
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

	# Botón mostrar/ocultar todos los caminos (rutas CaminoBot)
	var btn_caminos := Button.new()
	btn_caminos.name = "BtnMostrarCaminos"
	btn_caminos.text = "Mostrar Caminos [OFF]"
	btn_caminos.custom_minimum_size = Vector2(0, 36)
	btn_caminos.add_theme_font_size_override("font_size", 16)
	btn_caminos.pressed.connect(_on_mostrar_caminos_pressed)
	vbox.add_child(btn_caminos)
	vbox.move_child(btn_caminos, insert_idx + 7)

	# Botón mostrar/ocultar las áreas semánticas de depuración del mapa.
	var btn_zonas_debug: Button = Button.new()
	btn_zonas_debug.name = "BtnMostrarZonasDebug"
	btn_zonas_debug.text = "Mostrar Zonas Debug [OFF]"
	btn_zonas_debug.custom_minimum_size = Vector2(0, 36)
	btn_zonas_debug.add_theme_font_size_override("font_size", 16)
	btn_zonas_debug.pressed.connect(_on_mostrar_zonas_debug_pressed)
	vbox.add_child(btn_zonas_debug)
	vbox.move_child(btn_zonas_debug, insert_idx + 8)

	# Boton Modo Dios
	var btn_dios := Button.new()
	btn_dios.name = "BtnGodMode"
	btn_dios.text = "Modo Dios [%s]" % ("ON" if GameState.god_mode else "OFF")
	btn_dios.custom_minimum_size = Vector2(0, 36)
	btn_dios.add_theme_font_size_override("font_size", 16)
	btn_dios.pressed.connect(_on_god_mode_pressed)
	vbox.add_child(btn_dios)
	vbox.move_child(btn_dios, insert_idx + 9)

	# Boton Fuego Amigo
	var btn_amigo := Button.new()
	btn_amigo.name = "BtnFuegoAmigo"
	btn_amigo.text = "Fuego Amigo [%s]" % ("ON" if GameState.friendly_fire else "OFF")
	btn_amigo.custom_minimum_size = Vector2(0, 36)
	btn_amigo.add_theme_font_size_override("font_size", 16)
	btn_amigo.pressed.connect(_on_friendly_fire_pressed)
	vbox.add_child(btn_amigo)
	vbox.move_child(btn_amigo, insert_idx + 10)

	# Botón de puntos semánticos eliminado (migrados por el usuario)

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
	var btn_eq: Button = get_node_or_null("PanelPrincipal/ScrollContainer/VBox/BtnCambiarEquipo")
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
	var btn: Button = get_node_or_null("PanelPrincipal/ScrollContainer/VBox/BtnAiDisable")
	if not btn:
		return

	var bots: Array = []
	if _is_story_mode():
		bots = get_tree().get_nodes_in_group(&"story_enemy")
	else:
		bots = MatchManager.bot_pool
	if ai_disabled:
		for bot: Node in bots:
			if is_instance_valid(bot) and bot.get("is_dead") != true:
				bot.process_mode = Node.PROCESS_MODE_DISABLED
				if bot is CharacterBody3D:
					bot.velocity = Vector3.ZERO
		btn.text = "Ai disable [ON]"
		lbl_status.text = "[AI DISABLE ACTIVO]"
	else:
		for bot: Node in bots:
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
	BotBase.toggle_debug_overlay_all()
	var btn: Button = get_node_or_null("PanelPrincipal/ScrollContainer/VBox/BtnBotDebug")
	if btn:
		btn.text = "Bot Debug Info [ON]" if BotDebugOverlay.enabled else "Bot Debug Info [OFF]"
	lbl_status.text = "Bot Debug %s" % ("ACTIVADO" if BotDebugOverlay.enabled else "DESACTIVADO")

func _on_unit_props_pressed() -> void:
	BotDebugOverlay.toggle_unit_properties_all()
	var btn: Button = get_node_or_null("PanelPrincipal/ScrollContainer/VBox/BtnUnitProps")
	if btn:
		btn.text = "Propiedades de unidad [ON]" if BotDebugOverlay.enabled else "Propiedades de unidad [OFF]"
	lbl_status.text = "Propiedades de unidad %s" % ("ACTIVADO" if BotDebugOverlay.enabled else "DESACTIVADO")

func _on_cambiar_equipo_pressed() -> void:
	visible = false
	_panel_equipo.visible = true

func _on_team_ai_pressed() -> void:
	if _is_story_mode():
		lbl_status.text = "Historia: %d zombies vivos" % get_tree().get_nodes_in_group(&"story_enemy").size()
		return
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
	if _is_story_mode():
		lbl_status.text = "Historia no usa órdenes tácticas de equipos."
		return
	if not is_instance_valid(TeamAI):
		lbl_status.text = "[TeamAI NO DISPONIBLE]"
		return

	TeamAI.assign_orders_all()
	lbl_status.text = "[ORDENES RE-ASIGNADAS a todos los bots]"
	print("[DevMenu] Ordenes re-asignadas a todos los bots via TeamAI")


## Muestra u oculta la geometría de todos los caminos (CaminoBot) en partida.
func _on_mostrar_caminos_pressed() -> void:
	_mostrar_caminos = not _mostrar_caminos
	var rutas: Array[Node] = get_tree().get_nodes_in_group(&"bot_routes")
	var visibles: int = 0
	for ruta in rutas:
		if ruta is CaminoBot:
			ruta.show_debug = _mostrar_caminos
			visibles += 1
	var btn: Button = get_node_or_null("PanelPrincipal/ScrollContainer/VBox/BtnMostrarCaminos")
	if btn:
		btn.text = "Mostrar Caminos [ON]" if _mostrar_caminos else "Mostrar Caminos [OFF]"
	var estado: String = "VISIBLES" if _mostrar_caminos else "OCULTOS"
	lbl_status.text = "Caminos %s (%d)" % [estado, visibles]
	print("[DevMenu] Caminos %s: %d rutas" % [("mostrados" if _mostrar_caminos else "ocultos"), visibles])


## Muestra u oculta los volúmenes de Base Azul, Base Roja y Mitad del Mapa.
## Solo cambia sus MeshInstance3D: las Area3D se mantienen sin colisión.
func _on_mostrar_zonas_debug_pressed() -> void:
	_mostrar_zonas_debug = not _mostrar_zonas_debug
	var zones: Array[Node] = get_tree().get_nodes_in_group(&"map_debug_zones")
	var updated: int = 0
	for zone: Node in zones:
		if zone is DebugMapZone:
			(zone as DebugMapZone).set_display_enabled(_mostrar_zonas_debug)
			updated += 1
	var btn: Button = get_node_or_null("PanelPrincipal/ScrollContainer/VBox/BtnMostrarZonasDebug") as Button
	if btn != null:
		btn.text = "Mostrar Zonas Debug [ON]" if _mostrar_zonas_debug else "Mostrar Zonas Debug [OFF]"
	var state: String = "VISIBLES" if _mostrar_zonas_debug else "OCULTAS"
	lbl_status.text = "Zonas Debug %s (%d)" % [state, updated]
	print("[DevMenu] Zonas Debug %s: %d áreas" % [("mostradas" if _mostrar_zonas_debug else "ocultas"), updated])


func _on_god_mode_pressed() -> void:
	GameState.god_mode = !GameState.god_mode
	var btn: Button = get_node_or_null("PanelPrincipal/ScrollContainer/VBox/BtnGodMode")
	if btn:
		btn.text = "Modo Dios [%s]" % ("ON" if GameState.god_mode else "OFF")
	lbl_status.text = "[MODO DIOS ACTIVO - INMORTAL]" if GameState.god_mode else "[Modo Dios desactivado]"
	print("[DevMenu] Modo Dios = %s" % GameState.god_mode)


func _on_friendly_fire_pressed() -> void:
	GameState.friendly_fire = !GameState.friendly_fire
	var btn: Button = get_node_or_null("PanelPrincipal/ScrollContainer/VBox/BtnFuegoAmigo")
	if btn:
		btn.text = "Fuego Amigo [%s]" % ("ON" if GameState.friendly_fire else "OFF")
	lbl_status.text = "[FUEGO AMIGO ACTIVO]" if GameState.friendly_fire else "[Fuego amigo DESACTIVADO - aliados no se dañan]"
	print("[DevMenu] Fuego Amigo = %s" % GameState.friendly_fire)


# Puntos semánticos eliminados (migrados por el usuario)


func _on_spawn_pressed() -> void:
	var scene_path: String = "res://scenes/Historia/npc/enemies/story_melee_enemy.tscn" if _is_story_mode() else BOT_SCENE
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		push_error("DevMenu: no se pudo cargar escena: " + scene_path)
		return
	var npc: Node3D = packed.instantiate() as Node3D
	if npc == null:
		push_error("DevMenu: la escena no instanció un NPC")
		return
	if npc is BotBase:
		var bot: BotBase = npc as BotBase
		bot.equipo_id = opt_relacion.get_selected_id()
		bot.experiencia = opt_experiencia.get_selected_id()
		bot.rol = opt_rol.get_selected_id()
		var idx: int = opt_tipo_npc.get_selected()
		if idx >= 0 and idx < _armas_lista.size():
			bot.nombre_arma = _armas_lista[idx]

	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		push_error("DevMenu: no se encontró al jugador")
		npc.queue_free()
		return
	var spawn_pos: Vector3 = player.global_position - player.global_transform.basis.z * 3.0
	spawn_pos.y = player.global_position.y
	player.get_parent().add_child(npc)
	npc.global_position = spawn_pos

	if npc is BotBase:
		var spawned_bot: BotBase = npc as BotBase
		var arma_txt: String = spawned_bot.nombre_arma if spawned_bot.nombre_arma != "" else "Melee"
		lbl_status.text = "NPC spawneado: %s | %s | Rol: %s | Arma: %s" % [
			GameState.nombre_equipo(spawned_bot.equipo_id),
			opt_experiencia.get_item_text(opt_experiencia.get_selected()),
			opt_rol.get_item_text(opt_rol.get_selected()),
			arma_txt
		]
	else:
		lbl_status.text = "Zombie lento spawneado para Historia"
	panel_npc.visible = false
	panel_principal.visible = true


func _is_story_mode() -> bool:
	var story_state: Node = get_node_or_null("/root/GameStateSP")
	return story_state != null and story_state.has_method("is_story_active") and bool(story_state.call("is_story_active"))
