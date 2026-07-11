extends Control

@onready var menu_panel: Panel = $MenuPanel
@onready var map_panel: Panel = $MapPanel
@onready var options_menu: Control = $OptionsMenu
@onready var map_list_container: VBoxContainer = $MapPanel/ContentArea/MapScroll/MapList
@onready var btn_play: Button = $MapPanel/BottomBar/BtnPlay
@onready var max_players_spin: SpinBox = $MapPanel/ContentArea/RightPanel/MaxPlayersSpin

## Ruta al archivo JSON que contiene la lista de mapas.
const MAP_LIST_PATH: String = "res://config/maps/MPMapList.json"

## Cache de la lista de mapas cargada desde el JSON.
var _map_list: Array[Dictionary] = []

## Ruta del mapa actualmente seleccionado.
var _selected_map_path: String = ""

## Boton del mapa actualmente seleccionado (para resaltado visual).
var _selected_btn: Button = null

## Cantidad maxima de jugadores elegida.
var _max_players: int = 10

func _ready() -> void:
	# Limpiar estado de partida previa (por si la transicion no lo hizo)
	if is_instance_valid(MatchManager):
		MatchManager.reset_match()
	if is_instance_valid(GameState):
		GameState.reset_match()
	show_panel("menu")
	if options_menu:
		options_menu.closed.connect(_on_options_closed)
	# Cargar la lista de mapas desde el JSON
	_load_map_list()
	# El boton JUGAR empieza deshabilitado
	_update_play_button()

func show_panel(panel_name: String) -> void:
	menu_panel.visible = (panel_name == "menu")
	map_panel.visible = (panel_name == "map")

# --- CARGA DINAMICA DE MAPAS DESDE JSON ---

## Carga el archivo MPMapList.json y construye los botones de mapa.
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
		push_error("[MainMenu] Error parseando %s: %s" % [MAP_LIST_PATH, json.get_error_message()])
		return
	
	var data = json.data
	if typeof(data) != TYPE_ARRAY:
		push_error("[MainMenu] Formato invalido en %s: se esperaba un array" % MAP_LIST_PATH)
		return
	
	_map_list = []
	for entry in data:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if not entry.has("scene_path") or not entry.has("display_name"):
			continue
		# Saltar mapas deshabilitados
		if entry.has("enabled") and not entry["enabled"]:
			continue
		# Verificar que la escena realmente existe
		if not ResourceLoader.exists(entry["scene_path"]):
			push_warning("[MainMenu] Mapa no encontrado, se omite: %s" % entry["scene_path"])
			continue
		_map_list.append(entry)
	
	_build_map_buttons()

## Genera dinamicamente los botones de seleccion de mapa en el MapList.
func _build_map_buttons() -> void:
	# Limpiar botones existentes
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
		btn.pressed.connect(_on_map_pressed.bind(btn, scene_path))
		map_list_container.add_child(btn)

# --- SELECCION DE MAPA Y JUGADORES ---

## Se ejecuta al presionar un boton de mapa. Guarda la seleccion
## y resalta visualmente el boton elegido.
func _on_map_pressed(btn: Button, map_path: String) -> void:
	# Desseleccionar el boton anterior
	if _selected_btn and _selected_btn != btn:
		_selected_btn.modulate = Color.WHITE
	
	# Seleccionar el nuevo
	btn.modulate = Color(0.5, 0.8, 1.0)
	_selected_btn = btn
	_selected_map_path = map_path
	
	# Guardar en GameState
	var gs_node: Node = get_node_or_null("/root/GameState")
	if gs_node:
		gs_node.selected_map = map_path
	
	_update_play_button()

## Se ejecuta al cambiar el SpinBox de maximo de jugadores.
func _on_max_players_changed(value: float) -> void:
	_max_players = int(value)
	_update_play_button()

## Activa o desactiva el boton JUGAR segun las selecciones actuales.
func _update_play_button() -> void:
	btn_play.disabled = _selected_map_path.is_empty() or _max_players < 1

# --- MENU PRINCIPAL ---

func _on_jugar_pressed() -> void:
	# Reiniciar seleccion al abrir el panel de mapas
	_selected_map_path = ""
	_selected_btn = null
	_max_players = int(max_players_spin.value)
	# Restaurar color de botones si es que habia alguno seleccionado
	for child in map_list_container.get_children():
		if child is Button:
			child.modulate = Color.WHITE
	_update_play_button()
	show_panel("map")

func _on_salir_pressed() -> void:
	get_tree().quit()

func _on_options_pressed() -> void:
	"""Open the options menu from the main menu."""
	if options_menu:
		menu_panel.visible = false
		options_menu.toggle()

func _on_options_closed() -> void:
	"""Go back to main menu when options are closed."""
	if options_menu:
		options_menu.visible = false
	menu_panel.visible = true

# --- INICIAR PARTIDA ---

## Se ejecuta al presionar el boton JUGAR en el panel de seleccion.
## Valida que haya mapa seleccionado y carga la escena.
func _on_play_pressed() -> void:
	if _selected_map_path.is_empty():
		return
	
	var gs_node: Node = get_node_or_null("/root/GameState")
	if gs_node:
		gs_node.selected_map = _selected_map_path
		gs_node.max_players_total = _max_players
	
	get_tree().change_scene_to_file(_selected_map_path)

func _on_map_back_pressed() -> void:
	show_panel("menu")
