extends CanvasLayer

@onready var health_bar: ProgressBar = $HUD/MarginContainer/VBox/HealthBar
@onready var health_label: Label = $HUD/MarginContainer/VBox/HealthBar/Label
@onready var ammo_label: Label = $HUD/MarginContainer/VBox/AmmoContainer/AmmoLabel
@onready var weapon_label: Label = $HUD/MarginContainer/VBox/AmmoContainer/WeaponLabel
@onready var next_spawn_label: Label = $HUD/MarginContainer/VBox/SpawnLabel
@onready var crosshair: TextureRect = $HUD/Crosshair

# Paneles de Fin de Juego
@onready var death_screen: Panel = $DeathScreen
@onready var pause_screen: Panel = $PauseScreen

var total_time_elapsed: float = 0.0

func _ready() -> void:
	death_screen.visible = false
	pause_screen.visible = false
	
	# Buscar si el jugador existe para conectarnos a sus señales
	var player: Node = get_tree().get_first_node_in_group("player")
	if player:
		connect_player_signals(player)

func connect_player_signals(player: Player) -> void:
	player.health_changed.connect(_on_player_health_changed)
	player.weapon_changed.connect(_on_player_weapon_changed)
	player.ammo_changed.connect(_on_player_ammo_changed)
	player.player_died.connect(_on_player_died)

func update_spawn_timer(time_left: float) -> void:
	next_spawn_label.text = "Siguiente oleada en: " + str(snappedf(time_left, 0.1)) + "s"

func _process(_delta: float) -> void:
	# Manejar pantalla de pausa rápida si se pulsa Escape
	if Input.is_action_just_pressed("ui_cancel"):
		toggle_pause()

func toggle_pause() -> void:
	var is_paused: bool = get_tree().paused
	get_tree().paused = !is_paused
	pause_screen.visible = !is_paused
	if !is_paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# --- EVENTOS DEL JUGADOR ---
func _on_player_health_changed(current: float, max_val: float) -> void:
	health_bar.max_value = max_val
	health_bar.value = current
	health_label.text = "VIDA: " + str(int(current)) + " / " + str(int(max_val))

func _on_player_weapon_changed(w_name: String, ammo_in_mag: int, reserve_ammo: int) -> void:
	weapon_label.text = w_name
	ammo_label.text = str(ammo_in_mag) + " / " + str(reserve_ammo)

func _on_player_ammo_changed(ammo_in_mag: int, reserve_ammo: int) -> void:
	ammo_label.text = str(ammo_in_mag) + " / " + str(reserve_ammo)

func _on_player_died() -> void:
	death_screen.visible = true
	get_tree().paused = true

# --- ACCIONES DE UI ---
func _on_retry_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_resume_pressed() -> void:
	get_tree().paused = false
	pause_screen.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
