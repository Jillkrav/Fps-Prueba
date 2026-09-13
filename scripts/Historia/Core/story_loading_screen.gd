## AUTOLOAD /root/StoryLoadingScreen (no usar class_name: el nombre del autoload
## ya es el identificador global y declarar un class_name igual rompe la compilación).
extends CanvasLayer

## ────────────────────────────────────────────────────────────────────────────
##  StoryLoadingScreen — Pantalla de carga de la campaña.
##  Autoload (/root/StoryLoadingScreen). CanvasLayer en la capa más alta, por
##  encima de todo el HUD, que se muestra DURANTE el cambio de escena y se oculta
##  cuando el mapa terminó de cargar, aplicar su estado persistente y entregar
##  control al jugador.
##
##  Uso:
##    StoryLoadingScreen.show_loading("CARGANDO...")   # antes del change_scene
##    StoryLoadingScreen.hide_loading()               # al terminar _initialize_level
## ────────────────────────────────────────────────────────────────────────────

## La UI vive en una escena .tscn editable por el diseñador:
##   res://scenes/Historia/ui/story_loading_screen.tscn
## Nodos que usa este script (por ruta):
##   CenterBox/MapLabel, CenterBox/DotsLabel, CenterBox/Progress, CenterBox/TipLabel
const UI_SCENE := preload("res://scenes/Historia/ui/story_loading_screen.tscn")

## Tiempo mínimo (ms) que la pantalla permanece visible para que el jugador la
## perciba (fade + barra + consejo), aunque el mapa cargue en pocos frames.
const MIN_DISPLAY_MS := 600

## Consejos que se muestran al azar mientras carga.
const TIPS: Array[String] = [
	"Recoge armas y munición para sobrevivir.",
	"Los botones abren puertas: busca el camino.",
	"Activa los checkpoints para no perder el progreso.",
	"Los NPC eliminados no vuelven a aparecer.",
	"Tu progreso se guarda en los checkpoints y al cambiar de nivel.",
]

var _ui: Control = null
var _map_label: Label = null
var _dots_label: Label = null
var _tip_label: Label = null
var _progress: ProgressBar = null
var _dots_timer: Timer = null
var _dots_frame: int = 0
var _tween: Tween = null
var _shown_at_ms: int = 0


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	hide_loading()


## Muestra la pantalla de carga con un título y el nombre del mapa (opcional).
func show_loading(text: String = "CARGANDO", map_name: String = "") -> void:
	_shown_at_ms = Time.get_ticks_msec()
	if _map_label != null:
		_map_label.text = text if map_name.is_empty() else "%s — %s" % [text, map_name]
	if _tip_label != null:
		_tip_label.text = TIPS[randi() % TIPS.size()]
	if _progress != null:
		_progress.value = 0.0
	if _dots_label != null:
		_dots_label.text = ""
		_dots_frame = 0
	if _dots_timer != null and _dots_timer.is_stopped():
		_dots_timer.start()
	visible = true
	if _ui != null:
		_kill_tween()
		_ui.modulate = Color(1, 1, 1, 0.0)
		_tween = create_tween()
		_tween.tween_property(_ui, "modulate:a", 1.0, 0.25)
		if _progress != null:
			_tween.parallel().tween_property(_progress, "value", 100.0, 1.6) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Oculta la pantalla de carga (al terminar de cargar y restaurar el mapa).
## Garantiza un tiempo mínimo de visualización para que el jugador la perciba.
func hide_loading() -> void:
	if _shown_at_ms > 0:
		var elapsed: int = Time.get_ticks_msec() - _shown_at_ms
		if elapsed < MIN_DISPLAY_MS:
			await get_tree().create_timer(float(MIN_DISPLAY_MS - elapsed) / 1000.0).timeout
	_do_hide_loading()


func _do_hide_loading() -> void:
	if _dots_timer != null:
		_dots_timer.stop()
	_kill_tween()
	if _ui == null:
		visible = false
		return
	if is_inside_tree():
		_tween = create_tween()
		_tween.tween_property(_ui, "modulate:a", 0.0, 0.15)
		_tween.tween_callback(func() -> void: visible = false)
	else:
		_ui.modulate = Color(1, 1, 1, 0.0)
		visible = false


func _on_dots_timeout() -> void:
	_dots_frame = (_dots_frame + 1) % 4
	if _dots_label != null:
		_dots_label.text = ".".repeat(_dots_frame)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _build_ui() -> void:
	_ui = UI_SCENE.instantiate() as Control
	if _ui == null:
		push_error("[StoryLoadingScreen] No se pudo instanciar la UI.")
		return
	_ui.name = "LoadingUI"
	add_child(_ui)
	_map_label = _ui.get_node_or_null("CenterBox/MapLabel") as Label
	_dots_label = _ui.get_node_or_null("CenterBox/DotsLabel") as Label
	_tip_label = _ui.get_node_or_null("CenterBox/TipLabel") as Label
	_progress = _ui.get_node_or_null("CenterBox/Progress") as ProgressBar
	_dots_timer = Timer.new()
	_dots_timer.name = "DotsTimer"
	_dots_timer.wait_time = 0.35
	_dots_timer.timeout.connect(_on_dots_timeout)
	add_child(_dots_timer)
