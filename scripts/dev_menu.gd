## Menu de desarrollo. Se activa con Q desde player.gd.
## Permite: ponerse invisible a los NPC y spawnear NPC configurados manualmente.
extends Control

# ─────────────────────────────────────────────────────
# ESCENAS DE NPC DISPONIBLES
# Para agregar un arma nueva: agregar entrada aquí + crear su escena.
# ─────────────────────────────────────────────────────

const NPC_SCENES: Dictionary = {
	"melee":      "res://scenes/enemies/enemy_melee.tscn",
	"pistolero":  "res://scenes/enemies/enemy_pistolero.tscn",
	"escopetero": "res://scenes/enemies/enemy_escopetero.tscn",
	# Futura metralleta: "metralleta": "res://scenes/enemies/enemy_metralleta.tscn",
}

# ─────────────────────────────────────────────────────
# REFERENCIAS DE NODOS
# ─────────────────────────────────────────────────────

@onready var panel_principal: Panel        = $PanelPrincipal
@onready var panel_npc: Panel              = $PanelNPC
@onready var btn_invisible: Button         = $PanelPrincipal/VBox/BtnInvisible
@onready var btn_generar: Button           = $PanelPrincipal/VBox/BtnGenerar
@onready var btn_spawn: Button             = $PanelNPC/VBox/BtnSpawn
@onready var btn_volver: Button            = $PanelNPC/VBox/BtnVolver
@onready var opt_relacion: OptionButton    = $PanelNPC/VBox/GridAtributos/OptRelacion
@onready var opt_experiencia: OptionButton = $PanelNPC/VBox/GridAtributos/OptExperiencia
@onready var opt_arma: OptionButton        = $PanelNPC/VBox/GridAtributos/OptArma
@onready var lbl_status: Label             = $PanelPrincipal/VBox/LblStatus

# ─────────────────────────────────────────────────────
# ESTADO INTERNO
# ─────────────────────────────────────────────────────

var is_invisible: bool = false

# ─────────────────────────────────────────────────────
# CICLO DE VIDA
# ─────────────────────────────────────────────────────

func _ready() -> void:
	# Asegurar que este nodo siempre procese aunque el juego esté pausado
	process_mode = Node.PROCESS_MODE_ALWAYS

	opt_relacion.add_item("Enemigo",  EnemyBase.Relacion.ENEMIGO)
	opt_relacion.add_item("Neutral",  EnemyBase.Relacion.NEUTRAL)
	opt_relacion.add_item("Amigable", EnemyBase.Relacion.AMIGABLE)

	opt_experiencia.add_item("Baja",  EnemyBase.Experiencia.BAJA)
	opt_experiencia.add_item("Media", EnemyBase.Experiencia.MEDIA)
	opt_experiencia.add_item("Alta",  EnemyBase.Experiencia.ALTA)

	for arma_key in NPC_SCENES.keys():
		opt_arma.add_item(arma_key.capitalize())

	visible = false
	panel_principal.visible = true
	panel_npc.visible = false

	btn_invisible.pressed.connect(_on_invisible_pressed)
	btn_generar.pressed.connect(_on_generar_pressed)
	btn_spawn.pressed.connect(_on_spawn_pressed)
	btn_volver.pressed.connect(_on_volver_pressed)

# ─────────────────────────────────────────────────────
# TOGGLE DEL MENU (llamado desde player.gd)
# ─────────────────────────────────────────────────────

func toggle_menu() -> void:
	visible = !visible
	panel_npc.visible = false
	panel_principal.visible = true

	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ─────────────────────────────────────────────────────
# LOGICA DE BOTONES
# ─────────────────────────────────────────────────────

func _on_invisible_pressed() -> void:
	is_invisible = !is_invisible
	var player: Node = get_tree().get_first_node_in_group("player")
	if player:
		if is_invisible:
			player.add_to_group("invisible_to_npc")
			btn_invisible.text = "Invisible: ON"
			lbl_status.text = "[INVISIBLE ACTIVO]"
		else:
			player.remove_from_group("invisible_to_npc")
			btn_invisible.text = "Invisible: OFF"
			lbl_status.text = ""

func _on_generar_pressed() -> void:
	panel_principal.visible = false
	panel_npc.visible = true

func _on_volver_pressed() -> void:
	panel_npc.visible = false
	panel_principal.visible = true

func _on_spawn_pressed() -> void:
	var relacion_id: int    = opt_relacion.get_selected_id()
	var experiencia_id: int = opt_experiencia.get_selected_id()
	var arma_key: String    = NPC_SCENES.keys()[opt_arma.get_selected()]

	var scene_path: String = NPC_SCENES[arma_key]
	var packed: PackedScene = load(scene_path)
	if not packed:
		push_error("DevMenu: no se pudo cargar la escena: " + scene_path)
		return

	var npc: EnemyBase = packed.instantiate() as EnemyBase
	if not npc:
		push_error("DevMenu: la escena no es un EnemyBase: " + scene_path)
		return

	npc.relacion    = relacion_id as EnemyBase.Relacion
	npc.experiencia = experiencia_id as EnemyBase.Experiencia

	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if not player:
		push_error("DevMenu: no se encontró al jugador")
		npc.queue_free()
		return

	var spawn_pos: Vector3 = player.global_transform.origin \
		+ player.global_transform.basis.z * -3.0
	spawn_pos.y = player.global_transform.origin.y

	var world: Node = player.get_parent()
	world.add_child(npc)
	npc.global_transform.origin = spawn_pos

	lbl_status.text = "NPC spawneado: " + arma_key.capitalize()
	panel_npc.visible = false
	panel_principal.visible = true
