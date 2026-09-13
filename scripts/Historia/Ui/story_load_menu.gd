extends Control

## ────────────────────────────────────────────────────────────────────────────
##  StoryLoadMenu — Menú de «cargar partida» de la campaña.
##  Escena: res://scenes/Historia/ui/story_load_menu.tscn
##
##  Se instancia desde el menú principal (CAMPAÑA -> CONTINUAR PARTIDA).
##  Lista los slots guardados (autosave + manuales) con su resumen (nivel,
##  vida, arma, fecha). Al elegir uno:
##    SaveManager.load_game(slot)  -> restaura memoria (GameStateSP,
##                                     LevelStateManager, snapshot jugador)
##    GameStateSP.resume_story()   -> activa sesión conservando el checkpoint
##    StoryLoadingScreen.show_loading() + change_scene al nivel guardado
## ────────────────────────────────────────────────────────────────────────────

signal closed

@onready var slot_list: VBoxContainer = $Panel/Scroll/SlotList
@onready var status_label: Label = $Panel/StatusLabel
@onready var back_button: Button = $Panel/BackButton


func _ready() -> void:
	_populate()


## Construye la lista de slots guardados.
func _populate() -> void:
	for child: Node in slot_list.get_children():
		slot_list.remove_child(child)
		child.queue_free()

	var save_manager: Node = get_node_or_null("/root/SaveManager")
	var slots: Array = []
	if save_manager != null and save_manager.has_method("get_save_slots"):
		slots = save_manager.get_save_slots()

	if slots.is_empty():
		var empty: Label = Label.new()
		empty.text = "No hay partidas guardadas.\nJuega a la campaña y pasa un checkpoint para crear una."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 20)
		empty.custom_minimum_size = Vector2(520, 120)
		slot_list.add_child(empty)
		status_label.text = "No hay guardados disponibles."
		return

	slots.sort()
	for slot: Variant in slots:
		if save_manager == null or not save_manager.has_method("read_save_summary"):
			continue
		var summary: Dictionary = save_manager.read_save_summary(int(slot))
		var btn: Button = Button.new()
		btn.name = "SlotButton_%d" % int(slot)
		btn.text = _format_summary(int(slot), summary)
		btn.custom_minimum_size = Vector2(540, 92)
		btn.add_theme_font_size_override("font_size", 18)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_slot_pressed.bind(int(slot)))
		slot_list.add_child(btn)

	status_label.text = "Selecciona un guardado para continuar la campaña."


## Formatea el texto del botón de un slot.
func _format_summary(slot: int, summary: Dictionary) -> String:
	var slot_name: String = "AUTOGUARDADO" if slot == 0 else "GUARDADO %d" % slot
	var level_id: String = str(summary.get("level_id", ""))
	var level_name: String = StoryDataCatalog.campaign_name_for_id(level_id) if not level_id.is_empty() else "¿?"
	var health: int = int(float(summary.get("health", 0.0)))
	var max_health: int = int(float(summary.get("max_health", 100.0)))
	var weapon: String = str(summary.get("weapon", "-"))
	var ammo: int = int(summary.get("ammo_in_mag", 0))
	var timestamp: String = str(summary.get("timestamp", ""))
	var header: String = "%s   ·   %s" % [slot_name, level_name]
	var detail: String = "VIDA %d/%d   ·   %s (%d balas)" % [health, max_health, weapon, ammo]
	if not timestamp.is_empty():
		detail += "   ·   %s" % timestamp
	return "%s\n%s" % [header, detail]


## Carga el slot elegido y entra al nivel guardado.
func _on_slot_pressed(slot: int) -> void:
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	if save_manager == null or not save_manager.has_method("load_game"):
		status_label.text = "SaveManager no disponible."
		return
	if not save_manager.load_game(slot):
		status_label.text = "No se pudo cargar ese guardado."
		return

	var story_state: Node = get_node_or_null("/root/GameStateSP")
	if story_state == null or not story_state.has_method("resume_story"):
		status_label.text = "GameStateSP no disponible."
		return
	story_state.call("resume_story")

	# Evitar que sistemas multijugador se inicien con la campaña.
	GameStateMP.reset_match()
	if is_instance_valid(MatchManager):
		MatchManager.reset_match()

	var level_path: String = str(story_state.get("current_level_path"))
	if level_path.is_empty() or not ResourceLoader.exists(level_path):
		status_label.text = "El guardado no tiene un nivel válido."
		return

	var level_id: String = str(story_state.get("current_level_id"))
	var loading: Node = get_node_or_null("/root/StoryLoadingScreen")
	if loading != null and loading.has_method("show_loading"):
		loading.show_loading("CARGANDO", StoryDataCatalog.campaign_name_for_id(level_id))

	await get_tree().process_frame
	get_tree().change_scene_to_file(level_path)
	queue_free()


func _on_back_pressed() -> void:
	closed.emit()
	queue_free()
