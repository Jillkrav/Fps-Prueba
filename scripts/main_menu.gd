extends Control

@onready var menu_panel: Panel = $MenuPanel
@onready var map_panel: Panel = $MapPanel
@onready var weapon_panel: Panel = $WeaponPanel

func _ready() -> void:
	show_panel("menu")

func show_panel(panel_name: String) -> void:
	menu_panel.visible = (panel_name == "menu")
	map_panel.visible = (panel_name == "map")
	weapon_panel.visible = (panel_name == "weapon")

# --- MENU PRINCIPAL ---
func _on_jugar_pressed() -> void:
	show_panel("map")

func _on_salir_pressed() -> void:
	get_tree().quit()

# --- SELECCION DE MAPA ---
func _on_map_selected(map_path: String) -> void:
	# Guardamos el mapa en GameState
	if Engine.has_meta("GameState"):
		Engine.get_meta("GameState").selected_map = map_path
	else:
		# Si es autoload registrado
		var gs_node: Node = get_node_or_null("/root/GameState")
		if gs_node:
			gs_node.selected_map = map_path
	show_panel("weapon")

func _on_map_back_pressed() -> void:
	show_panel("menu")

# --- SELECCION DE ARMA ---
func _on_weapon_selected(weapon_key: String) -> void:
	if Engine.has_meta("GameState"):
		Engine.get_meta("GameState").selected_weapon = weapon_key
	else:
		var gs_node: Node = get_node_or_null("/root/GameState")
		if gs_node:
			gs_node.selected_weapon = weapon_key
			
	# Cargar el mapa seleccionado
	var target_map: String = "res://scenes/maps/map_1.tscn"
	var gs_node2: Node = get_node_or_null("/root/GameState")
	if gs_node2:
		target_map = gs_node2.selected_map
	
	get_tree().change_scene_to_file(target_map)

func _on_weapon_back_pressed() -> void:
	show_panel("map")
