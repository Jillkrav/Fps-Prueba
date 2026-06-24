extends Control

@onready var menu_panel: Panel = $MenuPanel
@onready var map_panel: Panel = $MapPanel

func _ready() -> void:
	show_panel("menu")

func show_panel(panel_name: String) -> void:
	menu_panel.visible = (panel_name == "menu")
	map_panel.visible = (panel_name == "map")

# --- MENU PRINCIPAL ---
func _on_jugar_pressed() -> void:
	show_panel("map")

func _on_salir_pressed() -> void:
	get_tree().quit()

# --- SELECCION DE MAPA ---
func _on_map_selected(map_path: String) -> void:
	var gs_node: Node = get_node_or_null("/root/GameState")
	if gs_node:
		gs_node.selected_map = map_path
	# Carga el mapa — la selección de equipo/arma ocurre dentro del mapa
	get_tree().change_scene_to_file(map_path)

func _on_map_back_pressed() -> void:
	show_panel("menu")
