extends CanvasLayer

# Emitida cuando el jugador confirma equipo y arma
signal selection_finished(team: String, weapon: String)

var selected_team: String = ""
var selected_weapon: String = ""

@onready var team_panel: Control = $TeamPanel
@onready var weapon_panel: Control = $WeaponPanel

func _ready() -> void:
	# Este nodo debe procesar aunque el juego esté pausado
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = true
	show_team_panel()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func show_team_panel() -> void:
	team_panel.visible = true
	weapon_panel.visible = false

func show_weapon_panel() -> void:
	team_panel.visible = false
	weapon_panel.visible = true

# --- BOTONES DE EQUIPO ---
func _on_team_rojo_pressed() -> void:
	selected_team = "rojo"
	show_weapon_panel()

func _on_team_azul_pressed() -> void:
	selected_team = "azul"
	show_weapon_panel()

# --- BOTONES DE ARMA ---
func _on_weapon_metralleta_pressed() -> void:
	selected_weapon = "metralleta"
	_finish_selection()

func _on_weapon_escopeta_pressed() -> void:
	selected_weapon = "escopeta"
	_finish_selection()

func _on_weapon_back_pressed() -> void:
	show_team_panel()

# --- CONFIRMAR Y ARRANCAR ---
func _finish_selection() -> void:
	var gs_node: Node = get_node_or_null("/root/GameState")
	if gs_node:
		gs_node.selected_team = selected_team
		gs_node.selected_weapon = selected_weapon

	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	selection_finished.emit(selected_team, selected_weapon)
	queue_free()
