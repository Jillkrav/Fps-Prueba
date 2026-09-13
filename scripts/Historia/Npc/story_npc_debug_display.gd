class_name StoryNpcDebugDisplay
extends Node3D

## Visualizador opcional de depuración para NPCs de Historia.
##
## Se crea únicamente cuando `debug_ai_enabled` está activo. Muestra estado,
## schedule, condiciones y memoria en un Label3D, sin depender de modelos,
## animaciones ni audio finales.

var owner_npc: Node3D = null
var label: Label3D = null


func setup(npc: Node3D) -> void:
	owner_npc = npc
	if label == null:
		label = Label3D.new()
		label.name = "Status"
		label.position = Vector3(0.0, 2.4, 0.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.pixel_size = 0.004
		label.modulate = Color(0.7, 1.0, 0.85, 1.0)
		add_child(label)


func refresh(snapshot: Dictionary) -> void:
	if label == null:
		return
	var memory_age: float = float(snapshot.get("memory_age", 0.0))
	var memory_text: String = "%.1fs" % memory_age if bool(snapshot.get("has_memory", false)) else "—"
	# Estado visible de la máquina jerárquica (CORRIENDO·HUIDA, ...), si el
	# NPC la expone en el snapshot.
	var npc_state: String = str(snapshot.get("npc_state", ""))
	var npc_state_line: String = ""
	if not npc_state.is_empty():
		npc_state_line = "► %s\n" % npc_state
	# Línea de voz activa (debug): se muestra en cursiva al final.
	var voice_line: String = str(snapshot.get("voice_line", ""))
	var voice_text: String = ""
	if not voice_line.is_empty():
		voice_text = "\n«%s»" % voice_line
	label.text = "%s[%s] %s\n%s\nMemoria: %s\n%s%s" % [
		npc_state_line,
		str(snapshot.get("state", "IDLE")),
		str(snapshot.get("schedule", "IDLE")),
		str(snapshot.get("task", "Esperar")),
		memory_text,
		str(snapshot.get("reason", "")),
		voice_text,
	]
	# Color por estado visible (máquina jerárquica) si existe; si no, por el
	# estado global del brain táctico (comportamiento original).
	var color_key: String = npc_state.split("·")[0] if not npc_state.is_empty() else str(snapshot.get("state", "IDLE"))
	match color_key:
		"EN_COMBATE":
			label.modulate = Color(1.0, 0.45, 0.35, 1.0)
		"DETECCION", "GANO_COMBATE", "SEARCH", "ALERT":
			label.modulate = Color(1.0, 0.9, 0.35, 1.0)
		"CORRIENDO":
			label.modulate = Color(0.45, 0.85, 1.0, 1.0)
		"DEAD", "MUERTO", "INACTIVE":
			label.modulate = Color(0.65, 0.65, 0.65, 1.0)
		"COMBAT":
			label.modulate = Color(1.0, 0.55, 0.35, 1.0)
		_:
			label.modulate = Color(0.7, 1.0, 0.85, 1.0)
