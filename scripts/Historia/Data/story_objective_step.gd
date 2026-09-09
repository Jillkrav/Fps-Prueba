class_name StoryObjectiveStep
extends Resource

## Paso de objetivo configurable para StoryLevelEvent.
## Define el texto que aparece al comenzar y el texto que se muestra al
## completarlo. El evento determina la condición real (señal, zona, oleada...).

@export_multiline var objective_text: String = ""
@export_multiline var completion_text: String = ""
@export var update_hud_on_start: bool = true
@export var update_hud_on_complete: bool = true
