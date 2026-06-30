# scripts/scoreboard.gd
# Scoreboard definitivo del proyecto.
# Obtiene TODOS los datos del MatchManager (registro centralizado).
# No busca jugadores en la escena ni usa grupos.
#
# Para mostrarlo: mantener TAB presionado.
# Para ocultarlo: soltar TAB.
#
# Uso: instanciar dentro del HUD (CanvasLayer) y llamar a show()/hide().
# El HUD (hud.gd) maneja la logica de TAB.
extends Control
class_name Scoreboard

# ── Referencias a nodos UI (creados en _ready) ─────────────────────────

var _background: ColorRect
var _title: Label
var _blue_header: Label
var _red_header: Label
var _blue_container: VBoxContainer
var _red_container: VBoxContainer
var _global_info: Label

# Cache de filas de jugadores: player_id -> HBoxContainer (row)
var _row_cache: Dictionary[int, HBoxContainer] = {}

# Columna de estadisticas
const COL_NAME: int = 0
const COL_HP: int = 1
const COL_KILLS: int = 2
const COL_DEATHS: int = 3
const COL_STATUS: int = 4
const COL_ROL: int = 5

# Anchuras minimas de cada columna (px)
# Se usan como custom_minimum_size para evitar que colapsen a 0.
const COL_WIDTHS: Array[float] = [100.0, 35.0, 40.0, 45.0, 80.0, 75.0]

# Proporciones de expansion: como se distribuye el espacio SOBRANTE.
# La suma total de ratios determina que columna recibe mas espacio.
const COL_STRETCH: Array[float] = [3.0, 1.0, 1.0, 1.0, 2.0, 2.0]

const COLOR_AZUL: Color = Color(0.15, 0.35, 0.9, 0.9)
const COLOR_ROJO: Color = Color(0.85, 0.15, 0.15, 0.9)
const COLOR_ALIVE: Color = Color(0.3, 0.9, 0.3)
const COLOR_DEAD: Color = Color(0.7, 0.7, 0.7)
const COLOR_RESPAWN: Color = Color(1.0, 0.8, 0.2)
const COLOR_INACTIVE: Color = Color(0.5, 0.5, 0.5)

func _ready() -> void:
	_build_ui()
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

# ═══════════════════════════════════════════
# CONSTRUCCION DE UI (una sola vez)
# ═══════════════════════════════════════════

func _build_ui() -> void:
	_background = ColorRect.new()
	_background.color = Color(0.0, 0.0, 0.0, 0.75)
	_background.anchors_preset = Control.PRESET_FULL_RECT
	add_child(_background)
	
	var main_margin: MarginContainer = MarginContainer.new()
	main_margin.anchors_preset = Control.PRESET_FULL_RECT
	main_margin.add_theme_constant_override("margin_left", 40)
	main_margin.add_theme_constant_override("margin_right", 40)
	main_margin.add_theme_constant_override("margin_top", 25)
	main_margin.add_theme_constant_override("margin_bottom", 25)
	main_margin.clip_contents = true
	add_child(main_margin)
	
	var main_vbox: VBoxContainer = VBoxContainer.new()
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_theme_constant_override("separation", 12)
	main_margin.add_child(main_vbox)
	
	# Titulo
	_title = Label.new()
	_title.text = "SCOREBOARD"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", Color.WHITE)
	_title.add_theme_color_override("font_outline_color", Color.BLACK)
	_title.add_theme_constant_override("outline_size", 2)
	main_vbox.add_child(_title)
	
	# Encabezado de columnas
	var column_header: HBoxContainer = HBoxContainer.new()
	column_header.add_theme_constant_override("separation", 2)
	column_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column_header.clip_contents = true
	
	var header_labels: Array[String] = ["Nombre", "HP", "Kills", "Muertes", "Estado", "Rol activo"]
	for i in range(header_labels.size()):
		var hdr: Label = Label.new()
		hdr.text = header_labels[i]
		hdr.custom_minimum_size.x = COL_WIDTHS[i]
		hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hdr.size_flags_stretch_ratio = COL_STRETCH[i]
		hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if i > 0 else HORIZONTAL_ALIGNMENT_LEFT
		hdr.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		hdr.add_theme_font_size_override("font_size", 14)
		column_header.add_child(hdr)
	main_vbox.add_child(column_header)
	
	# Separador
	var separator: HSeparator = HSeparator.new()
	separator.add_theme_color_override("color", Color(0.5, 0.5, 0.5, 0.5))
	main_vbox.add_child(separator)
	
	# Contenedor de equipos (dos columnas)
	var teams_hbox: HBoxContainer = HBoxContainer.new()
	teams_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	teams_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	teams_hbox.add_theme_constant_override("separation", 20)
	main_vbox.add_child(teams_hbox)
	
	# Columna Azul
	var blue_vbox: VBoxContainer = VBoxContainer.new()
	blue_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blue_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	blue_vbox.add_theme_constant_override("separation", 4)
	teams_hbox.add_child(blue_vbox)
	
	_blue_header = Label.new()
	_blue_header.text = "EQUIPO AZUL"
	_blue_header.add_theme_color_override("font_color", COLOR_AZUL)
	_blue_header.add_theme_font_size_override("font_size", 18)
	_blue_header.add_theme_constant_override("outline_size", 1)
	_blue_header.add_theme_color_override("font_outline_color", Color.BLACK)
	blue_vbox.add_child(_blue_header)
	
	_blue_container = VBoxContainer.new()
	_blue_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_blue_container.add_theme_constant_override("separation", 2)
	blue_vbox.add_child(_blue_container)
	
	var blue_spacer: Control = Control.new()
	blue_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	blue_vbox.add_child(blue_spacer)
	
	# Columna Roja
	var red_vbox: VBoxContainer = VBoxContainer.new()
	red_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	red_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	red_vbox.add_theme_constant_override("separation", 4)
	teams_hbox.add_child(red_vbox)
	
	_red_header = Label.new()
	_red_header.text = "EQUIPO ROJO"
	_red_header.add_theme_color_override("font_color", COLOR_ROJO)
	_red_header.add_theme_font_size_override("font_size", 18)
	_red_header.add_theme_constant_override("outline_size", 1)
	_red_header.add_theme_color_override("font_outline_color", Color.BLACK)
	red_vbox.add_child(_red_header)
	
	_red_container = VBoxContainer.new()
	_red_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_red_container.add_theme_constant_override("separation", 2)
	red_vbox.add_child(_red_container)
	
	var red_spacer: Control = Control.new()
	red_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	red_vbox.add_child(red_spacer)
	
	# Separador inferior
	var sep2: HSeparator = HSeparator.new()
	sep2.add_theme_color_override("color", Color(0.5, 0.5, 0.5, 0.5))
	main_vbox.add_child(sep2)
	
	# Informacion global
	_global_info = Label.new()
	_global_info.text = ""
	_global_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_global_info.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_global_info.add_theme_font_size_override("font_size", 15)
	main_vbox.add_child(_global_info)

# ═══════════════════════════════════════════
# MOSTRAR / OCULTAR
# ═══════════════════════════════════════════

func show_scoreboard() -> void:
	visible = true
	_rebuild_all_rows()

func hide_scoreboard() -> void:
	visible = false

# ═══════════════════════════════════════════
# ACTUALIZACION EN VIVO (solo textos)
# ═══════════════════════════════════════════

func _process(_delta: float) -> void:
	if visible:
		_update_all_rows()

# ═══════════════════════════════════════════
# RECONSTRUCCION COMPLETA
# ═══════════════════════════════════════════

func _rebuild_all_rows() -> void:
	_row_cache.clear()
	for child in _blue_container.get_children():
		child.queue_free()
	for child in _red_container.get_children():
		child.queue_free()
	
	if not is_instance_valid(MatchManager) or not MatchManager.is_match_started():
		return
	
	var all_players: Array[PlayerData] = MatchManager.get_all_players_data()
	if all_players.is_empty():
		return
	
	var blue_players: Array[PlayerData] = []
	var red_players: Array[PlayerData] = []
	
	for pd: PlayerData in all_players:
		match pd.team:
			int(Enums.Equipo.AZUL):
				if pd.status != PlayerData.Status.INACTIVE:
					blue_players.append(pd)
			int(Enums.Equipo.ROJO):
				if pd.status != PlayerData.Status.INACTIVE:
					red_players.append(pd)
	
	_sort_players(blue_players)
	_sort_players(red_players)
	
	_blue_header.text = "EQUIPO AZUL (%d)" % blue_players.size()
	_red_header.text = "EQUIPO ROJO (%d)" % red_players.size()
	
	for pd in blue_players:
		var row: HBoxContainer = _create_row(pd)
		_row_cache[pd.player_id] = row
		_blue_container.add_child(row)
	
	for pd in red_players:
		var row: HBoxContainer = _create_row(pd)
		_row_cache[pd.player_id] = row
		_red_container.add_child(row)
	
	_update_global_info()

# ═══════════════════════════════════════════
# ACTUALIZACION LIGERA (solo textos)
# ═══════════════════════════════════════════

func _update_all_rows() -> void:
	if not is_instance_valid(MatchManager) or not MatchManager.is_match_started():
		return
	
	var all_players: Array[PlayerData] = MatchManager.get_all_players_data()
	if all_players.is_empty():
		return
	
	var blue_count: int = 0
	var red_count: int = 0
	
	for pd: PlayerData in all_players:
		if pd.team == int(Enums.Equipo.AZUL) and pd.status != PlayerData.Status.INACTIVE:
			blue_count += 1
		elif pd.team == int(Enums.Equipo.ROJO) and pd.status != PlayerData.Status.INACTIVE:
			red_count += 1
		
		var row: HBoxContainer = _row_cache.get(pd.player_id)
		if row and is_instance_valid(row):
			_update_row_data(row, pd)
	
	_blue_header.text = "EQUIPO AZUL (%d)" % blue_count
	_red_header.text = "EQUIPO ROJO (%d)" % red_count
	_update_global_info()

func _update_global_info() -> void:
	if not is_instance_valid(MatchManager):
		return
	var total_players: int = MatchManager.count_active_players()
	var alive_count: int = MatchManager.count_players_by_status(PlayerData.Status.ALIVE)
	var dead_respawning: int = MatchManager.count_players_by_status(PlayerData.Status.DEAD) + \
		MatchManager.count_players_by_status(PlayerData.Status.RESPAWNING)
	
	_global_info.text = "Máx: %d  |  Total: %d  |  Vivos: %d  |  Muertos: %d" % [
		MatchManager.max_players_total,
		total_players,
		alive_count,
		dead_respawning
	]

# ═══════════════════════════════════════════
# FILAS DE JUGADORES
# ═══════════════════════════════════════════

func _sort_players(players: Array[PlayerData]) -> void:
	players.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
		if a.status == PlayerData.Status.ALIVE and b.status != PlayerData.Status.ALIVE:
			return true
		if a.status != PlayerData.Status.ALIVE and b.status == PlayerData.Status.ALIVE:
			return false
		return a.kills > b.kills
	)

func _create_row(pd: PlayerData) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.set_meta("player_id", pd.player_id)
	
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(1.0, 1.0, 1.0, 0.05)
	bg.anchors_preset = Control.PRESET_FULL_RECT
	bg.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(bg)
	
	var lbl_name: Label = Label.new()
	lbl_name.name = "Name"
	lbl_name.custom_minimum_size.x = COL_WIDTHS[COL_NAME]
	lbl_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_name.size_flags_stretch_ratio = COL_STRETCH[COL_NAME]
	lbl_name.add_theme_font_size_override("font_size", 13)
	if pd.is_human:
		lbl_name.add_theme_color_override("font_color", Color(1.0, 1.0, 0.5))
	row.add_child(lbl_name)
	
	var lbl_hp: Label = Label.new()
	lbl_hp.name = "HP"
	lbl_hp.custom_minimum_size.x = COL_WIDTHS[COL_HP]
	lbl_hp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_hp.size_flags_stretch_ratio = COL_STRETCH[COL_HP]
	lbl_hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_hp.add_theme_font_size_override("font_size", 13)
	row.add_child(lbl_hp)
	
	var lbl_kills: Label = Label.new()
	lbl_kills.name = "Kills"
	lbl_kills.custom_minimum_size.x = COL_WIDTHS[COL_KILLS]
	lbl_kills.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_kills.size_flags_stretch_ratio = COL_STRETCH[COL_KILLS]
	lbl_kills.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_kills.add_theme_font_size_override("font_size", 13)
	lbl_kills.add_theme_color_override("font_color", Color(0.9, 0.5, 0.2))
	row.add_child(lbl_kills)
	
	var lbl_deaths: Label = Label.new()
	lbl_deaths.name = "Deaths"
	lbl_deaths.custom_minimum_size.x = COL_WIDTHS[COL_DEATHS]
	lbl_deaths.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_deaths.size_flags_stretch_ratio = COL_STRETCH[COL_DEATHS]
	lbl_deaths.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_deaths.add_theme_font_size_override("font_size", 13)
	lbl_deaths.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	row.add_child(lbl_deaths)
	
	var lbl_status: Label = Label.new()
	lbl_status.name = "Status"
	lbl_status.custom_minimum_size.x = COL_WIDTHS[COL_STATUS]
	lbl_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_status.size_flags_stretch_ratio = COL_STRETCH[COL_STATUS]
	lbl_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_status.add_theme_font_size_override("font_size", 13)
	row.add_child(lbl_status)
	
	var lbl_rol: Label = Label.new()
	lbl_rol.name = "Rol"
	lbl_rol.custom_minimum_size.x = COL_WIDTHS[COL_ROL]
	lbl_rol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_rol.size_flags_stretch_ratio = COL_STRETCH[COL_ROL]
	lbl_rol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_rol.add_theme_font_size_override("font_size", 12)
	lbl_rol.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	row.add_child(lbl_rol)
	
	_update_row_data(row, pd)
	return row

func _update_row_data(row: HBoxContainer, pd: PlayerData) -> void:
	var lbl_name: Label = row.get_node("Name") as Label
	if lbl_name:
		lbl_name.text = pd.player_name
	
	var lbl_hp: Label = row.get_node("HP") as Label
	if lbl_hp:
		lbl_hp.text = "%d" % int(pd.health)
		if pd.health <= 0:
			lbl_hp.add_theme_color_override("font_color", COLOR_DEAD)
		elif pd.health < 30:
			lbl_hp.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		else:
			lbl_hp.add_theme_color_override("font_color", Color.WHITE)
	
	var lbl_kills: Label = row.get_node("Kills") as Label
	if lbl_kills:
		lbl_kills.text = "%d" % pd.kills
	
	var lbl_deaths: Label = row.get_node("Deaths") as Label
	if lbl_deaths:
		lbl_deaths.text = "%d" % pd.deaths
	
	var lbl_rol: Label = row.get_node("Rol") as Label
	if lbl_rol:
		lbl_rol.text = pd.tactical_role_name
	
	var lbl_status: Label = row.get_node("Status") as Label
	if lbl_status:
		match pd.status:
			PlayerData.Status.ALIVE:
				lbl_status.text = "Vivo"
				lbl_status.add_theme_color_override("font_color", COLOR_ALIVE)
			PlayerData.Status.DEAD:
				lbl_status.text = "Muerto"
				lbl_status.add_theme_color_override("font_color", COLOR_DEAD)
			PlayerData.Status.RESPAWNING:
				lbl_status.text = "Reaparece (%.1f)" % pd.respawn_time_left
				lbl_status.add_theme_color_override("font_color", COLOR_RESPAWN)
			PlayerData.Status.INACTIVE:
				lbl_status.text = "Inactivo"
				lbl_status.add_theme_color_override("font_color", COLOR_INACTIVE)
