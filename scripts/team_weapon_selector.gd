# scripts/team_weapon_selector.gd
# Pantalla de selección de equipo y arma antes de entrar al mapa.
# Nodo raíz de la escena es CanvasLayer → extends CanvasLayer.
extends CanvasLayer

# Referencias reales de team_weapon_selector.tscn
@onready var team_panel:      VBoxContainer = $TeamPanel
@onready var weapon_panel:    VBoxContainer = $WeaponPanel
@onready var btn_rojo:        Button        = $TeamPanel/BtnRojo
@onready var btn_azul:        Button        = $TeamPanel/BtnAzul
@onready var btn_metralleta:  Button        = $WeaponPanel/WeaponsRow/BtnMetralleta
@onready var btn_escopeta:    Button        = $WeaponPanel/WeaponsRow/BtnEscopeta
@onready var btn_volver:      Button        = $WeaponPanel/BtnVolver
@onready var weapon_title:    Label         = $WeaponPanel/Title

# Lista de armas disponibles (del JSON), se rellena dinámicamente
var _armas_lista: Array[String] = []
var _armas_buttons: Array[Button] = []
var _selected_team: String = "azul"

func _ready() -> void:
	team_panel.visible   = true
	weapon_panel.visible = false
	# Señales de equipo ya conectadas en la escena
	# Poblar botones de armas dinámicamente desde ConfigManager
	_poblar_armas()

func _poblar_armas() -> void:
	_armas_lista.clear()
	# Eliminar botones dinámicos previos (mantener BtnVolver)
	for btn in _armas_buttons:
		btn.queue_free()
	_armas_buttons.clear()

	var armas_raw: Dictionary = {}
	if ConfigManager and ConfigManager._data.has("Armas"):
		armas_raw = ConfigManager._data["Armas"]

	# Ocultar botones hardcodeados de la escena (Metralleta/Escopeta) si hay config
	if not armas_raw.is_empty():
		btn_metralleta.visible = false
		btn_escopeta.visible   = false
		var row: HBoxContainer = $WeaponPanel/WeaponsRow
		for categoria in armas_raw.keys():
			for nombre_arma in armas_raw[categoria].keys():
				_armas_lista.append(nombre_arma)
				var btn := Button.new()
				btn.text = nombre_arma
				btn.custom_minimum_size = Vector2(160, 80)
				btn.theme_override_font_sizes["font_size"] = 18
				btn.pressed.connect(_on_weapon_pressed.bind(nombre_arma))
				row.add_child(btn)
				_armas_buttons.append(btn)
	# Fallback: si no hay config usar los botones hardcodeados
	else:
		btn_metralleta.visible = true
		btn_escopeta.visible   = true

func _on_team_rojo_pressed() -> void:
	_selected_team = "rojo"
	team_panel.visible   = false
	weapon_panel.visible = true

func _on_team_azul_pressed() -> void:
	_selected_team = "azul"
	team_panel.visible   = false
	weapon_panel.visible = true

func _on_weapon_pressed(nombre_arma: String) -> void:
	_confirmar_seleccion(nombre_arma)

func _on_weapon_metralleta_pressed() -> void:
	_confirmar_seleccion("MP7")

func _on_weapon_escopeta_pressed() -> void:
	_confirmar_seleccion("M3")

func _on_weapon_back_pressed() -> void:
	weapon_panel.visible = false
	team_panel.visible   = true

func _confirmar_seleccion(nombre_arma: String) -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs:
		if "selected_weapon" in gs:
			gs.selected_weapon = nombre_arma
		if "selected_team" in gs:
			gs.selected_team = _selected_team
	queue_free()
