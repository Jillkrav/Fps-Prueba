extends Control

@onready var menu_panel: Panel = $MenuPanel
@onready var map_panel: Panel = $MapPanel
@onready var options_menu: Control = $OptionsMenu
@onready var map_list_container: VBoxContainer = $MapPanel/ContentArea/MapScroll/MapList
@onready var btn_play: Button = $MapPanel/BottomBar/BtnPlay
@onready var btn_character: Button = $MenuPanel/Buttons/BtnCharacter
@onready var max_players_spin: SpinBox = $MapPanel/ContentArea/RightPanel/MaxPlayersSpin

## NUEVO:
## Este nodo debe existir en main_menu.tscn:
## MapPanel/ContentArea/RightPanel/DifficultyOption
@onready var difficulty_option: OptionButton = $MapPanel/ContentArea/RightPanel/DifficultyOption
@onready var character_option: OptionButton = $MapPanel/ContentArea/RightPanel/CharacterOption
@onready var bot_skins_button: Button = $MapPanel/ContentArea/RightPanel/BotSkinsButton
var _blue_bot_skin_id: String = "teddy"
var _red_bot_skin_id: String = "teddy"

## Ruta al archivo JSON que contiene la lista de mapas.
const MAP_LIST_PATH: String = "res://config/Multiplayer/maps/MPMapList.json"
const STORY_MAP_LIST_PATH: String = "res://config/Historia/story_map_list.json"

## Cache de la lista de mapas cargada desde el JSON.
var _map_list: Array[Dictionary] = []

## Ruta del mapa actualmente seleccionado.
var _selected_map_path: String = ""

## Boton del mapa actualmente seleccionado para resaltado visual.
var _selected_btn: Button = null

## Cantidad maxima de jugadores elegida.
var _max_players: int = 10


func _ready() -> void:
	# Limpiar estado de partida previa por si la transicion no lo hizo.
	var story_state: Node = get_node_or_null("/root/GameStateSP")
	if story_state != null and story_state.has_method("reset_session"):
		story_state.call("reset_session")
	if is_instance_valid(MatchManager):
		MatchManager.reset_match()

	if is_instance_valid(GameState):
		GameStateMP.reset_match()

	show_panel("menu")
	if btn_character:
		btn_character.visible = false
	_setup_character_options()
	if bot_skins_button:
		bot_skins_button.pressed.connect(_on_bot_skins_pressed)

	if options_menu:
		options_menu.closed.connect(_on_options_closed)

	# Cargar la lista de mapas desde JSON.
	_load_map_list()

	# NUEVO: crear opciones de dificultad.
	_setup_difficulty_option()

	# El boton JUGAR empieza deshabilitado.
	_update_play_button()


func show_panel(panel_name: String) -> void:
	menu_panel.visible = (panel_name == "menu")
	map_panel.visible = (panel_name == "map")


# ══════════════════════════════════════════════════════════════════
# DIFICULTAD DE BOTS
# ══════════════════════════════════════════════════════════════════

## Puebla el selector de dificultad.
## Los IDs coinciden con BotDifficulty.Level.
func _setup_character_options() -> void:
	if character_option == null:
		return
	character_option.clear()
	var skins: Array[SkinData] = SkinManager.get_skins()
	for skin: SkinData in skins:
		character_option.add_item(skin.name)
		character_option.set_item_metadata(character_option.item_count - 1, skin.id)
		if skin.id == SkinManager.get_selected_skin_id():
			character_option.select(character_option.item_count - 1)
	character_option.item_selected.connect(_on_character_option_selected)

func _on_character_option_selected(index: int) -> void:
	var id: String = str(character_option.get_item_metadata(index))
	SkinManager.select_skin(id)

func _on_bot_skins_pressed() -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "SKINS DE BOTS"
	var panel: VBoxContainer = VBoxContainer.new()
	var blue: OptionButton = _create_skin_option("BOT AZUL", _blue_bot_skin_id)
	var red: OptionButton = _create_skin_option("BOT ROJO", _red_bot_skin_id)
	panel.add_child(blue)
	panel.add_child(red)
	dialog.add_child(panel)
	dialog.confirmed.connect(func() -> void:
		_blue_bot_skin_id = str(blue.get_selected_metadata())
		_red_bot_skin_id = str(red.get_selected_metadata())
		MatchManager.set_bot_skin_ids(_blue_bot_skin_id, _red_bot_skin_id)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(420, 220))

func _create_skin_option(label_text: String, selected_id: String) -> OptionButton:
	var option: OptionButton = OptionButton.new()
	option.text = label_text
	for skin: SkinData in SkinManager.get_skins():
		option.add_item(skin.name)
		option.set_item_metadata(option.item_count - 1, skin.id)
		if skin.id == selected_id:
			option.select(option.item_count - 1)
	return option

func _setup_difficulty_option() -> void:
	if difficulty_option == null:
		push_warning(
			"[MainMenu] DifficultyOption no encontrado. "
			+ "Agregar OptionButton en "
			+ "MapPanel/ContentArea/RightPanel/DifficultyOption"
		)
		return

	difficulty_option.clear()

	difficulty_option.add_item("Facil", BotDifficulty.Level.FACIL)
	difficulty_option.add_item("Normal", BotDifficulty.Level.NORMAL)
	difficulty_option.add_item("Dificil", BotDifficulty.Level.DIFICIL)

	# Normal es la dificultad por defecto.
	difficulty_option.select(BotDifficulty.Level.NORMAL)


## Guarda la dificultad elegida en el autoload.
func _save_selected_difficulty() -> void:
	if difficulty_option == null:
		BotDifficulty.set_level(BotDifficulty.Level.NORMAL)
		return

	var selected_id: int = difficulty_option.get_selected_id()
	BotDifficulty.set_level(selected_id)


# ══════════════════════════════════════════════════════════════════
# CARGA DINAMICA DE MAPAS DESDE JSON
# ══════════════════════════════════════════════════════════════════

## Carga MPMapList.json y construye los botones de mapa.
func _load_map_list() -> void:
	var file: FileAccess = FileAccess.open(MAP_LIST_PATH, FileAccess.READ)

	if not file:
		push_error("[MainMenu] No se pudo abrir: %s" % MAP_LIST_PATH)
		return

	var json_str: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var parse_result: Error = json.parse(json_str)

	if parse_result != OK:
		push_error(
			"[MainMenu] Error parseando %s: %s"
			% [MAP_LIST_PATH, json.get_error_message()]
		)
		return

	var data = json.data

	if typeof(data) != TYPE_ARRAY:
		push_error(
			"[MainMenu] Formato invalido en %s: se esperaba un array"
			% MAP_LIST_PATH
		)
		return

	_map_list = []

	for entry in data:
		if typeof(entry) != TYPE_DICTIONARY:
			continue

		if not entry.has("scene_path") or not entry.has("display_name"):
			continue

		# Saltar mapas deshabilitados.
		if entry.has("enabled") and not entry["enabled"]:
			continue

		# Verificar que la escena realmente existe.
		if not ResourceLoader.exists(entry["scene_path"]):
			push_warning(
				"[MainMenu] Mapa no encontrado, se omite: %s"
				% entry["scene_path"]
			)
			continue

		_map_list.append(entry)

	_build_map_buttons()


## Genera dinamicamente los botones de seleccion de mapa.
func _build_map_buttons() -> void:
	# Limpiar botones existentes.
	for child in map_list_container.get_children():
		map_list_container.remove_child(child)
		child.queue_free()

	_selected_map_path = ""
	_selected_btn = null

	if _map_list.is_empty():
		var label: Label = Label.new()
		label.text = "No hay mapas disponibles"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 22)
		label.custom_minimum_size = Vector2(500, 80)
		map_list_container.add_child(label)
		return

	for map_data in _map_list:
		var btn: Button = Button.new()
		btn.text = map_data["display_name"]
		btn.custom_minimum_size = Vector2(400, 80)
		btn.add_theme_font_size_override("font_size", 22)

		var scene_path: String = map_data["scene_path"]

		btn.pressed.connect(
			_on_map_pressed.bind(btn, scene_path)
		)

		map_list_container.add_child(btn)


# ══════════════════════════════════════════════════════════════════
# SELECCION DE MAPA Y JUGADORES
# ══════════════════════════════════════════════════════════════════

## Guarda el mapa elegido y resalta su boton.
func _on_map_pressed(btn: Button, map_path: String) -> void:
	# Desseleccionar boton anterior.
	if _selected_btn and _selected_btn != btn:
		_selected_btn.modulate = Color.WHITE

	# Seleccionar boton nuevo.
	btn.modulate = Color(0.5, 0.8, 1.0)
	_selected_btn = btn
	_selected_map_path = map_path

	# Guardar seleccion en GameState.
	var gs_node: Node = get_node_or_null("/root/GameState")

	if gs_node:
		gs_node.selected_map = map_path

	_update_play_button()


## Se ejecuta al cambiar el SpinBox de maximo de jugadores.
func _on_max_players_changed(value: float) -> void:
	_max_players = int(value)
	_update_play_button()


## Activa o desactiva el boton JUGAR.
func _update_play_button() -> void:
	btn_play.disabled = _selected_map_path.is_empty() or _max_players < 1


# ══════════════════════════════════════════════════════════════════
# MENU PRINCIPAL
# ══════════════════════════════════════════════════════════════════

func _on_campana_pressed() -> void:
	_show_story_map_selector()


## Construye la selección de Historia desde su JSON independiente del modo MP.
func _show_story_map_selector() -> void:
	var levels: Array[Dictionary] = _load_story_map_list()
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "CAMPAÑA — SELECCIONAR MISIÓN"
	dialog.min_size = Vector2i(560, 340)
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	var intro: Label = Label.new()
	intro.text = "Elige un mapa de pruebas. Completa el Mapa 1 para avanzar al Mapa 2 jugando."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(intro)
	for level: Dictionary in levels:
		var button: Button = Button.new()
		button.text = "%s\n%s" % [str(level.get("display_name", "Misión")), str(level.get("description", ""))]
		button.custom_minimum_size = Vector2(500, 68)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_start_story_level.bind(str(level.get("id", "")), str(level.get("scene_path", "")), dialog))
		content.add_child(button)
	if levels.is_empty():
		var empty_label: Label = Label.new()
		empty_label.text = "No hay misiones de Historia disponibles."
		content.add_child(empty_label)
	dialog.add_child(content)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _load_story_map_list() -> Array[Dictionary]:
	var levels: Array[Dictionary] = []
	var file: FileAccess = FileAccess.open(STORY_MAP_LIST_PATH, FileAccess.READ)
	if file == null:
		push_error("[MainMenu] No se pudo abrir: %s" % STORY_MAP_LIST_PATH)
		return levels
	var json: JSON = JSON.new()
	var parse_result: Error = json.parse(file.get_as_text())
	file.close()
	if parse_result != OK or not (json.data is Array):
		push_error("[MainMenu] JSON de Historia inválido: %s" % STORY_MAP_LIST_PATH)
		return levels
	for raw_entry: Variant in json.data:
		if not (raw_entry is Dictionary):
			continue
		var entry: Dictionary = raw_entry as Dictionary
		var scene_path: String = str(entry.get("scene_path", ""))
		if entry.get("enabled", true) and not scene_path.is_empty() and ResourceLoader.exists(scene_path):
			levels.append(entry)
	return levels


func _start_story_level(level_id: String, scene_path: String, dialog: AcceptDialog) -> void:
	if level_id.is_empty() or scene_path.is_empty():
		return
	var story_state: Node = get_node_or_null("/root/GameStateSP")
	if story_state == null or not story_state.has_method("begin_story"):
		push_error("[MainMenu] GameStateSP no está disponible.")
		return
	story_state.call("begin_story", level_id, scene_path)
	GameStateMP.reset_match()
	if is_instance_valid(MatchManager):
		MatchManager.reset_match()
	dialog.queue_free()
	get_tree().change_scene_to_file(scene_path)

func _on_multijugador_pressed() -> void:
	# Reiniciar seleccion al abrir el panel de mapas.
	_selected_map_path = ""
	_selected_btn = null
	_max_players = int(max_players_spin.value)

	# Restaurar color de botones si habia uno seleccionado.
	for child in map_list_container.get_children():
		if child is Button:
			child.modulate = Color.WHITE

	_update_play_button()
	show_panel("map")


func _on_salir_pressed() -> void:
	get_tree().quit()


func _on_character_pressed() -> void:
	var skins: Array[SkinData] = SkinManager.get_skins()
	if skins.is_empty():
		return
	var popup: PopupMenu = PopupMenu.new()
	for index: int in skins.size():
		popup.add_item(skins[index].name, index)
	popup.id_pressed.connect(_on_character_selected.bind(skins))
	add_child(popup)
	popup.position = btn_character.global_position + Vector2(0, btn_character.size.y)
	popup.popup()

func _on_character_selected(index: int, skins: Array[SkinData]) -> void:
	if index < 0 or index >= skins.size():
		return
	SkinManager.select_skin(skins[index].id)
	btn_character.text = "PERSONAJE: %s" % skins[index].name

func _on_options_pressed() -> void:
	if options_menu:
		menu_panel.visible = false
		options_menu.toggle()


func _on_options_closed() -> void:
	if options_menu:
		options_menu.visible = false

	menu_panel.visible = true


# ══════════════════════════════════════════════════════════════════
# INICIAR PARTIDA
# ══════════════════════════════════════════════════════════════════

## Valida la seleccion, guarda la dificultad y carga la escena del mapa.
func _on_play_pressed() -> void:
	if _selected_map_path.is_empty():
		return

	var gs_node: Node = get_node_or_null("/root/GameState")
	var gs_mp_node: Node = get_node_or_null("/root/GameStateMP")

	if gs_node:
		gs_node.selected_map = _selected_map_path

	if gs_mp_node:
		gs_mp_node.max_players_total = _max_players

	# NUEVO: guardar la dificultad global antes de cargar el mapa.
	_save_selected_difficulty()
	var story_state: Node = get_node_or_null("/root/GameStateSP")
	if story_state != null and story_state.has_method("reset_session"):
		story_state.call("reset_session")
	if is_instance_valid(MapManager) and MapManager.has_method("prepare_multiplayer_map_setup"):
		MapManager.prepare_multiplayer_map_setup()

	get_tree().change_scene_to_file(_selected_map_path)


func _on_map_back_pressed() -> void:
	show_panel("menu")
