extends Control

@onready var menu_panel: Panel = $MenuPanel
@onready var map_panel: Panel = $MapPanel
@onready var options_menu: Control = $OptionsMenu

func _ready() -> void:
	show_panel("menu")
	if options_menu:
		options_menu.closed.connect(_on_options_closed)

func show_panel(panel_name: String) -> void:
	menu_panel.visible = (panel_name == "menu")
	map_panel.visible = (panel_name == "map")

# --- MENU PRINCIPAL ---
func _on_jugar_pressed() -> void:
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

# --- SELECCION DE MAPA ---
func _on_map_selected(map_path: String) -> void:
	var gs_node: Node = get_node_or_null("/root/GameState")
	if gs_node:
		gs_node.selected_map = map_path
	# Carga el mapa — la selección de equipo/arma ocurre dentro del mapa
	get_tree().change_scene_to_file(map_path)

func _on_map_back_pressed() -> void:
	show_panel("menu")
