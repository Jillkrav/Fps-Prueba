# Plan de Mejoras — Sistema de IA de Bots

> **Para la IA que ejecute este plan:**
> - Trabaja **una tarea a la vez**.
> - Nunca modifiques archivos que no se indiquen en la tarea.
> - Si no entiendes algo, pregunta antes de tocar código.
> - Cada tarea tiene su propio prompt listo para copiar y pegar.
> - Los archivos relevantes están en el repo `Jillkrav/Fps-Prueba`, branch `Perplexity`.

---

## Índice de Fases

| Fase | Nombre | Prioridad |
|------|--------|-----------|
| 1 | Fixes críticos de navegación y señales | 🔴 Alta |
| 2 | Límite de ocupantes en defense_point | 🟠 Media |
| 3 | Patrullador con ruta ordenada | 🟠 Media |
| 4 | VERSÁTIL con rol dinámico real | 🟡 Media |
| 5 | Multi-punto para VERSÁTIL en SemanticPointRules | 🟡 Media |
| 6 | Validación de modo de juego en puntos semánticos | 🟢 Baja |

---

## FASE 1 — Fixes críticos de navegación y señales

> Estos tres fixes son independientes entre sí y no rompen nada existente.
> Son los de mayor impacto con menor esfuerzo.

---

### Tarea 1.1 — Dispersión mínima en fallback sin puntos semánticos

**Archivo a modificar:**
`scripts/Multiplayer/ai/bot_behaviors/state_roaming.gd`

**Problema:**
Cuando no hay ningún punto semántico disponible en el mapa, todos los bots van al core enemigo en exactamente la misma posición. Esto hace que todos mueran en la misma línea de fuego.

**Qué cambiar:**
En el método `_advance_to_core()`, busca el bloque que dice:
```gdscript
# Sin punto semántico → ir directo al core
_nav_target = core.global_position
```
Cambia esa línea por esto:
```gdscript
# Sin punto semántico → ir directo al core con offset aleatorio por bot
var _offset := Vector3(randf_range(-3.5, 3.5), 0.0, randf_range(-3.5, 3.5))
_nav_target = core.global_position + _offset
```

**Importante:** No toques nada más del método ni del archivo.

---

**Prompt listo para IA:**

```
Estás trabajando en el repositorio Jillkrav/Fps-Prueba, branch Perplexity.

Archivo a modificar: scripts/Multiplayer/ai/bot_behaviors/state_roaming.gd

Tarea:
En el método _advance_to_core(), encuentra el bloque de código que dice:

    # Sin punto semántico → ir directo al core
    _nav_target = core.global_position

Sustitúyelo exactamente por:

    # Sin punto semántico → ir directo al core con offset aleatorio por bot
    var _offset := Vector3(randf_range(-3.5, 3.5), 0.0, randf_range(-3.5, 3.5))
    _nav_target = core.global_position + _offset

No modifiques ninguna otra línea del archivo. No cambies la indentación del resto del código.
```

---

### Tarea 1.2 — Excluir puntos PATH del filtro de backtrack

**Archivo a modificar:**
`scripts/Multiplayer/ai/bot_behaviors/state_roaming.gd`

**Problema:**
El método `_get_semantic_point_nearby()` aplica `_requires_backtrack_cached()` a todos los puntos, incluyendo los de tipo `PATH` (patrullador). Esto hace que el patrullador descarte puntos de su ruta que están "detrás" suyo respecto al core enemigo, rompiendo la ronda.

**Qué cambiar:**
Dentro del método `_get_semantic_point_nearby()`, busca el bloque:
```gdscript
# Filtrar backtrack usando cache (evitar map_get_path cada tick)
if _requires_backtrack_cached(p.position, now):
    continue
```
Envuélvelo con una condición para que solo aplique cuando el tipo NO es PATH:
```gdscript
# Filtrar backtrack usando cache — excepto para PATH (patrullador recorre la ruta completa)
if point_type != SemanticPoint.PointType.PATH:
    if _requires_backtrack_cached(p.position, now):
        continue
```

**Importante:** No toques nada más del método. Solo añade la condición envolvente.

---

**Prompt listo para IA:**

```
Estás trabajando en el repositorio Jillkrav/Fps-Prueba, branch Perplexity.

Archivo a modificar: scripts/Multiplayer/ai/bot_behaviors/state_roaming.gd

Tarea:
Dentro del método _get_semantic_point_nearby(), encuentra este bloque:

        # Filtrar backtrack usando cache (evitar map_get_path cada tick)
        if _requires_backtrack_cached(p.position, now):
            continue

Sustitúyelo exactamente por:

        # Filtrar backtrack usando cache — excepto para PATH (patrullador recorre la ruta completa)
        if point_type != SemanticPoint.PointType.PATH:
            if _requires_backtrack_cached(p.position, now):
                continue

No cambies ninguna otra línea del archivo. Respeta la indentación existente (usa tabs).
```

---

### Tarea 1.3 — Conectar señal stuck_resolved para resetear nav_target

**Archivos involucrados:**
- `scripts/Multiplayer/ai/bot_behaviors/state_roaming.gd` (modificar)
- `scripts/Multiplayer/nav/bots/stuck_handler.gd` (solo lectura — no tocar)

**Problema:**
Cuando el `StuckHandler` resuelve un atasco con re-ruteo (fase 3), el estado `StateRoaming` no se entera. El estado sigue esperando llegar a `_nav_target` con el punto semántico fallido, quedando el bot varado silenciosamente.

`StuckHandler` ya tiene la señal `stuck_resolved` declarada pero nadie la conecta.

**Qué cambiar en `state_roaming.gd`:**

1. Agregar un nuevo método al final de la clase (antes del último `}` o al final del archivo):
```gdscript
## Llamado cuando StuckHandler resuelve un atasco.
## Fuerza re-elección del punto semántico en el próximo tick.
func _on_stuck_resolved() -> void:
    _nav_target = Vector3.ZERO
    _nav_target_set_time = 0.0
    _last_semantic_type = -1
    _debug("[StateRoaming] stuck_resolved → forzando re-elección de punto semántico")
```

2. En el método `enter()`, agregar la conexión de la señal al final del método (después de `movement_cmd.reset()`):
```gdscript
# Conectar señal de stuck_resolved para resetear nav_target
var stuck: StuckHandler = null
if bot and bot.movement_sys:
    stuck = bot.movement_sys.get_node_or_null("StuckHandler") as StuckHandler
if stuck and not stuck.stuck_resolved.is_connected(_on_stuck_resolved):
    stuck.stuck_resolved.connect(_on_stuck_resolved)
```

**Importante:** No toques `stuck_handler.gd`. Solo modifica `state_roaming.gd`.

---

**Prompt listo para IA:**

```
Estás trabajando en el repositorio Jillkrav/Fps-Prueba, branch Perplexity.

Archivo a modificar ÚNICAMENTE: scripts/Multiplayer/ai/bot_behaviors/state_roaming.gd
Archivo de referencia (no modificar): scripts/Multiplayer/nav/bots/stuck_handler.gd

Tarea en dos partes:

PARTE A — Agregar método al final del archivo state_roaming.gd:

## Llamado cuando StuckHandler resuelve un atasco.
## Fuerza re-elección del punto semántico en el próximo tick.
func _on_stuck_resolved() -> void:
	_nav_target = Vector3.ZERO
	_nav_target_set_time = 0.0
	_last_semantic_type = -1
	_debug("[StateRoaming] stuck_resolved → forzando re-elección de punto semántico")

PARTE B — En el método enter(), justo después de la línea `movement_cmd.reset()`, agregar:

	# Conectar señal de stuck_resolved para resetear nav_target
	var stuck: StuckHandler = null
	if bot and bot.movement_sys:
		stuck = bot.movement_sys.get_node_or_null("StuckHandler") as StuckHandler
	if stuck and not stuck.stuck_resolved.is_connected(_on_stuck_resolved):
		stuck.stuck_resolved.connect(_on_stuck_resolved)

No toques ningún otro archivo. Respeta la indentación con tabs.
```

---

## FASE 2 — Límite de ocupantes en defense_point

> Esta fase tiene tres tareas que deben hacerse **en orden**.
> La tarea 2.3 depende de las dos anteriores.

---

### Tarea 2.1 — Agregar campos de ocupantes a SemanticPoint

**Archivo a modificar:**
`scripts/Multiplayer/nav/bots/semantic_point.gd`

**Qué cambiar:**
En la sección `# PROPIEDADES`, después de la línea `var name: String = ""`, agregar:
```gdscript
## Máximo de bots que pueden ocupar este punto simultáneamente.
## -1 = sin límite (valor por defecto para todos los tipos excepto DEFENSE).
var max_occupants: int = -1

## Cantidad de bots actualmente ocupando este punto.
var current_occupants: int = 0
```

En el método `_init()`, después de `name = p_name`, agregar:
```gdscript
# Aplicar límite por defecto según tipo
if point_type == PointType.DEFENSE:
    max_occupants = 2
```

---

**Prompt listo para IA:**

```
Estás trabajando en el repositorio Jillkrav/Fps-Prueba, branch Perplexity.

Archivo a modificar: scripts/Multiplayer/nav/bots/semantic_point.gd

Tarea en dos partes:

PARTE A — En la sección de PROPIEDADES, justo después de la línea `var name: String = ""`, agregar:

	## Máximo de bots que pueden ocupar este punto simultáneamente.
	## -1 = sin límite (valor por defecto para todos los tipos excepto DEFENSE).
	var max_occupants: int = -1

	## Cantidad de bots actualmente ocupando este punto.
	var current_occupants: int = 0

PARTE B — En el método _init(), justo después de la línea `name = p_name`, agregar:

	# Aplicar límite por defecto según tipo
	if point_type == PointType.DEFENSE:
		max_occupants = 2

No toques ningún otro archivo. Respeta la indentación con tabs.
```

---

### Tarea 2.2 — Agregar métodos de ocupación a SemanticPoint

**Archivo a modificar:**
`scripts/Multiplayer/nav/bots/semantic_point.gd`

**Qué cambiar:**
Al final del archivo (en la sección `# UTILIDADES`), agregar estos métodos:
```gdscript
## Intenta ocupar este punto. Retorna true si hay lugar disponible.
func try_occupy() -> bool:
    if max_occupants < 0:
        current_occupants += 1
        return true
    if current_occupants < max_occupants:
        current_occupants += 1
        return true
    return false

## Libera un lugar en este punto. Llamar cuando el bot abandona el punto.
func release() -> void:
    current_occupants = max(0, current_occupants - 1)

## Retorna true si este punto tiene lugar para al menos un ocupante más.
func has_capacity() -> bool:
    if max_occupants < 0:
        return true
    return current_occupants < max_occupants
```

---

**Prompt listo para IA:**

```
Estás trabajando en el repositorio Jillkrav/Fps-Prueba, branch Perplexity.

Archivo a modificar: scripts/Multiplayer/nav/bots/semantic_point.gd

Tarea:
Al final del archivo, dentro de la sección # UTILIDADES (antes del cierre del archivo), agrega estos tres métodos:

## Intenta ocupar este punto. Retorna true si hay lugar disponible.
func try_occupy() -> bool:
	if max_occupants < 0:
		current_occupants += 1
		return true
	if current_occupants < max_occupants:
		current_occupants += 1
		return true
	return false

## Libera un lugar en este punto. Llamar cuando el bot abandona el punto.
func release() -> void:
	current_occupants = max(0, current_occupants - 1)

## Retorna true si este punto tiene lugar para al menos un ocupante más.
func has_capacity() -> bool:
	if max_occupants < 0:
		return true
	return current_occupants < max_occupants

No toques ningún otro archivo. Respeta la indentación con tabs.
```

---

### Tarea 2.3 — Filtrar puntos llenos en state_roaming y liberar al salir

**Archivo a modificar:**
`scripts/Multiplayer/ai/bot_behaviors/state_roaming.gd`

**Prerequisito:** Las tareas 2.1 y 2.2 deben estar completadas.

**Qué cambiar — PARTE A:**
En el método `_get_semantic_point_nearby()`, en el bucle `for p in points:`, agrega este filtro ANTES del cálculo del score (justo después de `if _requires_backtrack_cached...`):
```gdscript
# Filtrar puntos sin capacidad disponible
if not p.has_capacity():
    continue
```

**Qué cambiar — PARTE B:**
En `_advance_to_core()`, cuando se asigna un nuevo `target_point`, ocupa el punto:
```gdscript
if target_point != null:
    _nav_target = target_point.position
    _last_semantic_type = target_point.point_type
    _nav_target_set_time = Time.get_ticks_msec() / 1000.0
    target_point.try_occupy()  # ← AGREGAR ESTA LÍNEA
```

**Qué cambiar — PARTE C:**
Agregar una variable de instancia al inicio de la clase (junto a las demás `var`):
```gdscript
## Punto semántico actualmente ocupado por este bot (para liberarlo al salir).
var _occupied_point: SemanticPoint = null
```
Y actualizar la asignación en `_advance_to_core()` para guardarlo:
```gdscript
_occupied_point = target_point  # ← justo después de target_point.try_occupy()
```

**Qué cambiar — PARTE D:**
En el método `enter()`, al inicio, liberar el punto anterior si existía:
```gdscript
if _occupied_point != null:
    _occupied_point.release()
    _occupied_point = null
```

---

**Prompt listo para IA:**

```
Estás trabajando en el repositorio Jillkrav/Fps-Prueba, branch Perplexity.

ARCHIVO A MODIFICAR: scripts/Multiplayer/ai/bot_behaviors/state_roaming.gd

REQUISITO PREVIO: semantic_point.gd ya tiene los métodos try_occupy(), release() y has_capacity().

Cuatro cambios a hacer en orden:

1. Al inicio de la clase, agrega esta variable de instancia junto a las demás:

## Punto semántico actualmente ocupado por este bot (para liberarlo al salir).
var _occupied_point: SemanticPoint = null

2. En el método enter(), al inicio del método (antes de cualquier otra línea), agrega:

if _occupied_point != null:
	_occupied_point.release()
	_occupied_point = null

3. En el método _get_semantic_point_nearby(), en el bucle `for p in points:`, agrega este filtro justo después del bloque de filtrado de backtrack:

		# Filtrar puntos sin capacidad disponible
		if not p.has_capacity():
			continue

4. En el método _advance_to_core(), dentro del bloque `if target_point != null:`, justo después de la línea `_nav_target_set_time = Time.get_ticks_msec() / 1000.0`, agrega:

		target_point.try_occupy()
		_occupied_point = target_point

No toques ningún otro archivo. Respeta la indentación con tabs.
```

---

## FASE 3 — Patrullador con ruta ordenada

> Esta fase agrega el concepto de índice de ruta a los PATH points.
> Tres tareas en orden estricto.

---

### Tarea 3.1 — Agregar route_index a SemanticPoint y SemanticPointMarker

**Archivos a modificar:**
- `scripts/Multiplayer/nav/bots/semantic_point.gd`
- `scripts/Multiplayer/nav/bots/semantic_point_marker.gd`

**Cambio en semantic_point.gd:**
En la sección `# PROPIEDADES`, después de `var current_occupants: int = 0`, agregar:
```gdscript
## Índice de orden en la ruta de patrullaje (solo para PATH points).
## 0, 1, 2, ... define el orden de recorrido.
## -1 = sin orden definido (para todos los demás tipos).
var route_index: int = -1
```

En `_init()`, agregar parámetro y asignación:
```gdscript
# Cambiar la firma del _init a:
func _init(p_type: int = PointType.ASSAULT, p_position: Vector3 = Vector3.ZERO,
           p_team: int = -1, p_name: String = "", p_route_index: int = -1) -> void:
    # ... código existente ...
    route_index = p_route_index
```

**Cambio en semantic_point_marker.gd:**
Busca la variable exportada del tipo de punto (algo como `@export var point_type`) y agrega después:
```gdscript
## Índice de orden en la ruta de patrullaje. Solo relevante para PATH points.
@export var route_index: int = -1
```
En el método que construye el `SemanticPoint` desde el marker (normalmente `to_semantic_point()`), pasar el `route_index`:
```gdscript
return SemanticPoint.new(point_type, global_position, team, name, route_index)
```

---

**Prompt listo para IA:**

```
Estás trabajando en el repositorio Jillkrav/Fps-Prueba, branch Perplexity.

DOS archivos a modificar:

--- ARCHIVO 1: scripts/Multiplayer/nav/bots/semantic_point.gd ---

CAMBIO A: En la sección PROPIEDADES, justo después de `var current_occupants: int = 0`, agrega:

	## Índice de orden en la ruta de patrullaje (solo para PATH points).
	## 0, 1, 2, ... define el orden de recorrido.
	## -1 = sin orden definido.
	var route_index: int = -1

CAMBIO B: Modifica la firma del método _init para aceptar un nuevo parámetro p_route_index al final:

func _init(p_type: int = PointType.ASSAULT, p_position: Vector3 = Vector3.ZERO,
		   p_team: int = -1, p_name: String = "", p_route_index: int = -1) -> void:

Y al final del cuerpo del _init, agrega:
		route_index = p_route_index

--- ARCHIVO 2: scripts/Multiplayer/nav/bots/semantic_point_marker.gd ---

CAMBIO A: Busca las variables @export del archivo y agrega esta propiedad exportada:

	## Índice de orden en la ruta de patrullaje. Solo relevante para PATH points.
	@export var route_index: int = -1

CAMBIO B: En el método to_semantic_point() (o el equivalente que crea un SemanticPoint.new()), agrega route_index como último argumento:

	return SemanticPoint.new(point_type, global_position, team, name, route_index)

No toques ningún otro archivo. Respeta la indentación con tabs.
```

---

### Tarea 3.2 — Agregar get_points_by_route_order() a NavigationSystem

**Archivo a modificar:**
`scripts/Multiplayer/nav/bots/navigation_system.gd`

**Qué cambiar:**
Al final del bloque de métodos estáticos (antes de las propiedades de instancia), agregar este nuevo método estático:
```gdscript
## Retorna todos los PATH points de un equipo ordenados por route_index.
## Los puntos con route_index == -1 van al final (sin orden definido).
static func get_path_points_ordered(team_filter: int = -1) -> Array[SemanticPoint]:
    if not _semantic_points_loaded or all_semantic_points.is_empty():
        return []
    var result: Array[SemanticPoint] = []
    for sp in all_semantic_points:
        if sp.point_type != SemanticPoint.PointType.PATH:
            continue
        if team_filter != -1 and sp.team != -1 and sp.team != team_filter:
            continue
        result.append(sp)
    result.sort_custom(func(a: SemanticPoint, b: SemanticPoint) -> bool:
        if a.route_index < 0:
            return false
        if b.route_index < 0:
            return true
        return a.route_index < b.route_index
    )
    return result
```

---

**Prompt listo para IA:**

```
Estás trabajando en el repositorio Jillkrav/Fps-Prueba, branch Perplexity.

Archivo a modificar: scripts/Multiplayer/nav/bots/navigation_system.gd

Tarea:
Justo antes de la sección de propiedades de instancia (busca el comentario # PROPIEDADES DE INSTANCIA),
agrega este nuevo método estático:

## Retorna todos los PATH points de un equipo ordenados por route_index.
## Los puntos con route_index == -1 van al final (sin orden definido).
static func get_path_points_ordered(team_filter: int = -1) -> Array[SemanticPoint]:
	if not _semantic_points_loaded or all_semantic_points.is_empty():
		return []
	var result: Array[SemanticPoint] = []
	for sp in all_semantic_points:
		if sp.point_type != SemanticPoint.PointType.PATH:
			continue
		if team_filter != -1 and sp.team != -1 and sp.team != team_filter:
			continue
		result.append(sp)
	result.sort_custom(func(a: SemanticPoint, b: SemanticPoint) -> bool:
		if a.route_index < 0:
			return false
		if b.route_index < 0:
			return true
		return a.route_index < b.route_index
	)
	return result

No toques ningún otro archivo. Respeta la indentación con tabs.
```

---

### Tarea 3.3 — Hacer que el patrullador use la ruta ordenada en state_roaming

**Archivo a modificar:**
`scripts/Multiplayer/ai/bot_behaviors/state_roaming.gd`

**Prerequisito:** Tareas 3.1 y 3.2 completadas.

**Qué cambiar — PARTE A:**
Agregar variables de instancia al inicio de la clase:
```gdscript
## Índice actual del patrullador en la ruta PATH (solo usado por rol PATRULLADOR).
var _patrol_index: int = 0
## Cache de ruta PATH ordenada para el patrullador actual.
var _patrol_route: Array[SemanticPoint] = []
```

**Qué cambiar — PARTE B:**
En el método `enter()`, al final, agregar inicialización de la ruta de patrullaje:
```gdscript
# Si el bot es patrullador, pre-cargar la ruta ordenada
if bot and bot._tactical_role and bot._tactical_role.type == Roles.Type.PATRULLADOR:
    _patrol_route = NavigationSystem.get_path_points_ordered(bot.equipo_id)
    _patrol_index = 0
```

**Qué cambiar — PARTE C:**
En el método `_get_semantic_point_nearby()`, al inicio del método, agregar lógica especial para PATH:
```gdscript
# Patrullador: usar ruta ordenada en lugar de cercanía
if point_type == SemanticPoint.PointType.PATH:
    if _patrol_route.is_empty():
        _patrol_route = NavigationSystem.get_path_points_ordered(bot.equipo_id if bot else -1)
    if not _patrol_route.is_empty():
        var idx: int = _patrol_index % _patrol_route.size()
        var next_point: SemanticPoint = _patrol_route[idx]
        # Avanzar al siguiente punto si ya llegamos cerca
        if bot and bot.global_position.distance_to(next_point.position) < 3.0:
            _patrol_index = (_patrol_index + 1) % _patrol_route.size()
            idx = _patrol_index % _patrol_route.size()
            next_point = _patrol_route[idx]
        return next_point
    # Si no hay ruta, caer al sistema normal
```

---

**Prompt listo para IA:**

```
Estás trabajando en el repositorio Jillkrav/Fps-Prueba, branch Perplexity.

Archivo a modificar: scripts/Multiplayer/ai/bot_behaviors/state_roaming.gd

Tres cambios en orden:

1. Al inicio de la clase, junto a las otras variables de instancia, agrega:

## Índice actual del patrullador en la ruta PATH.
var _patrol_index: int = 0
## Cache de ruta PATH ordenada para el patrullador.
var _patrol_route: Array[SemanticPoint] = []

2. En el método enter(), al final del método, agrega:

	# Si el bot es patrullador, pre-cargar la ruta ordenada
	if bot and bot._tactical_role and bot._tactical_role.type == Roles.Type.PATRULLADOR:
		_patrol_route = NavigationSystem.get_path_points_ordered(bot.equipo_id)
		_patrol_index = 0

3. En el método _get_semantic_point_nearby(), al inicio del método (antes de cualquier otro código), agrega:

	# Patrullador: usar ruta ordenada en lugar de cercanía
	if point_type == SemanticPoint.PointType.PATH:
		if _patrol_route.is_empty():
			_patrol_route = NavigationSystem.get_path_points_ordered(bot.equipo_id if bot else -1)
		if not _patrol_route.is_empty():
			var idx: int = _patrol_index % _patrol_route.size()
			var next_point: SemanticPoint = _patrol_route[idx]
			if bot and bot.global_position.distance_to(next_point.position) < 3.0:
				_patrol_index = (_patrol_index + 1) % _patrol_route.size()
				idx = _patrol_index % _patrol_route.size()
				next_point = _patrol_route[idx]
			return next_point

No toques ningún otro archivo. Respeta la indentación con tabs.
```

---

## FASE 4 — VERSÁTIL con rol dinámico real

> Esta fase hace que el VERSÁTIL realmente cambie de perfil de movimiento
> según la orden de TeamAI activa. No toca roles de otros bots.

---

### Tarea 4.1 — Agregar método _refresh_tactical_role en BotBase

**Archivo a modificar:**
`scripts/Multiplayer/ai/bot_behaviors/bot_base.gd`

**Qué cambiar:**
En la sección `# TEAMAI / ORDER SYSTEM (FASE 6)`, al final de `_update_order_cache()`, agregar una llamada:
```gdscript
# Al final de _update_order_cache():
_refresh_tactical_role()
```

Y agregar el nuevo método en esa misma sección:
```gdscript
## Actualiza el perfil de movimiento del VERSÁTIL según la orden activa.
## No modifica roles de otros bots.
func _refresh_tactical_role() -> void:
    if _tactical_role == null:
        return
    if _tactical_role.type != Roles.Type.VERSATIL:
        return
    match current_order_type:
        TeamAI.OrderType.DEFEND, TeamAI.OrderType.HOLD:
            _tactical_role.movement_profile = Roles.MovementProfile.DEFENSIVE
            _tactical_role.base_defense_radius = 18.0
            _tactical_role.aggression = 0.4
        TeamAI.OrderType.ATTACK, TeamAI.OrderType.PATROL, TeamAI.OrderType.CAPTURE:
            _tactical_role.movement_profile = Roles.MovementProfile.AGGRESSIVE
            _tactical_role.base_defense_radius = 0.0
            _tactical_role.aggression = 0.75
        _:
            # FREELANCE u otro: perfil equilibrado
            _tactical_role.movement_profile = Roles.MovementProfile.AGGRESSIVE
            _tactical_role.base_defense_radius = 0.0
            _tactical_role.aggression = 0.6
```

---

**Prompt listo para IA:**

```
Estás trabajando en el repositorio Jillkrav/Fps-Prueba, branch Perplexity.

Archivo a modificar: scripts/Multiplayer/ai/bot_behaviors/bot_base.gd

Dos cambios:

1. En el método _update_order_cache(), al final del método (justo antes de que termine la función), agrega esta llamada:

	_refresh_tactical_role()

2. Justo después del método _update_order_cache(), agrega este nuevo método:

## Actualiza el perfil de movimiento del VERSÁTIL según la orden activa.
## No modifica roles de otros bots.
func _refresh_tactical_role() -> void:
	if _tactical_role == null:
		return
	if _tactical_role.type != Roles.Type.VERSATIL:
		return
	match current_order_type:
		TeamAI.OrderType.DEFEND, TeamAI.OrderType.HOLD:
			_tactical_role.movement_profile = Roles.MovementProfile.DEFENSIVE
			_tactical_role.base_defense_radius = 18.0
			_tactical_role.aggression = 0.4
		TeamAI.OrderType.ATTACK, TeamAI.OrderType.PATROL, TeamAI.OrderType.CAPTURE:
			_tactical_role.movement_profile = Roles.MovementProfile.AGGRESSIVE
			_tactical_role.base_defense_radius = 0.0
			_tactical_role.aggression = 0.75
		_:
			_tactical_role.movement_profile = Roles.MovementProfile.AGGRESSIVE
			_tactical_role.base_defense_radius = 0.0
			_tactical_role.aggression = 0.6

No toques ningún otro archivo. Respeta la indentación con tabs.
```

---

## FASE 5 — Multi-punto para VERSÁTIL en SemanticPointRules

> Actualmente get_point_type_for_role retorna solo el primer tipo que matchea.
> Esta fase lo convierte en una función que retorna todos los tipos posibles
> y actualiza state_roaming para aprovecharlo.

---

### Tarea 5.1 — Agregar get_point_types_for_role en SemanticPointRules

**Archivo a modificar:**
`scripts/Multiplayer/nav/bots/semantic_point_rules.gd`

**Qué cambiar:**
Al final del archivo, agregar este nuevo método (sin tocar el existente `get_point_type_for_role`):
```gdscript
## Retorna TODOS los tipos de punto que puede usar un rol.
## El VERSÁTIL puede usar múltiples tipos según el contexto.
static func get_point_types_for_role(role_type: int) -> Array[int]:
    var config: Dictionary = _load_config()
    var mapping: Dictionary = config.get("point_mapping", {})
    var result: Array[int] = []
    for point_name in mapping.keys():
        var role_names: Array = mapping[point_name]
        for r_name in role_names:
            var role_val: Variant = ROLE_NAMES.get(r_name, null)
            if role_val == role_type:
                var pt: Variant = POINT_TYPES_BY_NAME.get(point_name, null)
                if pt != null and pt not in result:
                    result.append(pt)
    return result
```

---

**Prompt listo para IA:**

```
Estás trabajando en el repositorio Jillkrav/Fps-Prueba, branch Perplexity.

Archivo a modificar: scripts/Multiplayer/nav/bots/semantic_point_rules.gd

Tarea:
Al final del archivo, agrega este nuevo método estático. NO modifiques el método get_point_type_for_role() existente:

## Retorna TODOS los tipos de punto que puede usar un rol.
## El VERSÁTIL puede usar múltiples tipos según el contexto.
static func get_point_types_for_role(role_type: int) -> Array[int]:
	var config: Dictionary = _load_config()
	var mapping: Dictionary = config.get("point_mapping", {})
	var result: Array[int] = []
	for point_name in mapping.keys():
		var role_names: Array = mapping[point_name]
		for r_name in role_names:
			var role_val: Variant = ROLE_NAMES.get(r_name, null)
			if role_val == role_type:
				var pt: Variant = POINT_TYPES_BY_NAME.get(point_name, null)
				if pt != null and pt not in result:
					result.append(pt)
	return result

No toques ningún otro archivo. Respeta la indentación con tabs.
```

---

### Tarea 5.2 — Actualizar semantic_points.json para que VERSÁTIL tenga múltiples tipos

**Archivo a modificar:**
`config/Multiplayer/semantic_points.json`

**Qué cambiar:**
En el JSON actual, `"VERSATIL": ["VERSATIL"]` hace que el VERSÁTIL solo use puntos de tipo VERSATIL.
Cambia ese bloque para que el VERSÁTIL también aparezca en ASSAULT y DEFENSE:

Actual:
```json
"ASSAULT":    ["ASALTO"],
"DEFENSE":    ["DEFENSOR"],
...
"VERSATIL":    ["VERSATIL"],
```

Nuevo:
```json
"ASSAULT":    ["ASALTO", "VERSATIL"],
"DEFENSE":    ["DEFENSOR", "VERSATIL"],
...
"VERSATIL":    ["VERSATIL"],
```

---

**Prompt listo para IA:**

```
Estás trabajando en el repositorio Jillkrav/Fps-Prueba, branch Perplexity.

Archivo a modificar: config/Multiplayer/semantic_points.json

Tarea:
En el bloque "point_mapping", modifica las entradas "ASSAULT" y "DEFENSE" para incluir al VERSÁTIL:

Cambiar:
	"ASSAULT":    ["ASALTO"],
	"DEFENSE":    ["DEFENSOR"],

Por:
	"ASSAULT":    ["ASALTO", "VERSATIL"],
	"DEFENSE":    ["DEFENSOR", "VERSATIL"],

El resto del JSON no cambia. No toques ningún otro archivo.
```

---

### Tarea 5.3 — Hacer que state_roaming use el tipo de punto correcto para el VERSÁTIL

**Archivo a modificar:**
`scripts/Multiplayer/ai/bot_behaviors/state_roaming.gd`

**Prerequisito:** Tareas 5.1 y 5.2 completadas. La Fase 4 también debe estar lista.

**Qué cambiar:**
En `_advance_to_core()`, el bloque que selecciona el punto semántico hace:
```gdscript
var point_type: int = SemanticPointRules.get_point_type_for_role(role.type)
```
Para el VERSÁTIL, necesitamos elegir el tipo según su `movement_profile` actual (que la Fase 4 ya actualiza dinámicamente).

Sustituye ese bloque por:
```gdscript
var point_type: int
if role.type == Roles.Type.VERSATIL:
    # VERSÁTIL elige tipo según perfil activo
    if role.movement_profile == Roles.MovementProfile.DEFENSIVE:
        point_type = SemanticPoint.PointType.DEFENSE
    else:
        point_type = SemanticPoint.PointType.ASSAULT
else:
    point_type = SemanticPointRules.get_point_type_for_role(role.type)
```

---

**Prompt listo para IA:**

```
Estás trabajando en el repositorio Jillkrav/Fps-Prueba, branch Perplexity.

Archivo a modificar: scripts/Multiplayer/ai/bot_behaviors/state_roaming.gd

Tarea:
En el método _advance_to_core(), busca esta línea:

			var point_type: int = SemanticPointRules.get_point_type_for_role(role.type)

Sustitúyela por:

			var point_type: int
			if role.type == Roles.Type.VERSATIL:
				# VERSÁTIL elige tipo según perfil activo
				if role.movement_profile == Roles.MovementProfile.DEFENSIVE:
					point_type = SemanticPoint.PointType.DEFENSE
				else:
					point_type = SemanticPoint.PointType.ASSAULT
			else:
				point_type = SemanticPointRules.get_point_type_for_role(role.type)

No toques ningún otro archivo. Respeta la indentación con tabs.
```

---

## FASE 6 — Validación de modo de juego en puntos semánticos

> Esta fase es la de menor urgencia. Se puede dejar para cuando
> haya más modos de juego implementados.

---

### Tarea 6.1 — Agregar excluded_modes al JSON

**Archivo a modificar:**
`config/Multiplayer/semantic_points.json`

**Qué cambiar:**
Agregar un nuevo bloque `"excluded_modes"` al JSON:
```json
{
    "point_mapping": { ... },
    "cooldowns": { ... },
    "excluded_modes": {
        "DEFENSE": ["DEATHMATCH", "TEAM_DEATHMATCH"],
        "PATH":    [],
        "ASSAULT": [],
        "ALTERNATE": [],
        "VERSATIL": [],
        "OVERWATCH": [],
        "SUPPORT": []
    }
}
```

---

**Prompt listo para IA:**

```
Estás trabajando en el repositorio Jillkrav/Fps-Prueba, branch Perplexity.

Archivo a modificar: config/Multiplayer/semantic_points.json

Tarea:
Agrega un nuevo bloque "excluded_modes" al final del JSON (antes del cierre del objeto raíz `}`).
El resultado final del JSON debe quedar así:

{
	"point_mapping": {
		"ASSAULT":    ["ASALTO", "VERSATIL"],
		"DEFENSE":    ["DEFENSOR", "VERSATIL"],
		"ALTERNATE":  ["FLANQUEADOR"],
		"PATH":       ["PATRULLADOR"],
		"VERSATIL":    ["VERSATIL"],
		"OVERWATCH":  ["FRANCOTIRADOR"],
		"SUPPORT":    ["APOYO"]
	},
	"cooldowns": {
		"ASSAULT":    25.0,
		"DEFENSE":    20.0,
		"ALTERNATE":  15.0,
		"PATH":       20.0,
		"VERSATIL":    30.0,
		"OVERWATCH":  35.0,
		"SUPPORT":    25.0
	},
	"excluded_modes": {
		"DEFENSE":    ["DEATHMATCH", "TEAM_DEATHMATCH"],
		"PATH":       [],
		"ASSAULT":    [],
		"ALTERNATE":  [],
		"VERSATIL":    [],
		"OVERWATCH":  [],
		"SUPPORT":    []
	}
}

No toques ningún otro archivo.
```

---

### Tarea 6.2 — Agregar is_point_allowed_in_mode() a SemanticPointRules

**Archivo a modificar:**
`scripts/Multiplayer/nav/bots/semantic_point_rules.gd`

**Qué cambiar:**
Al final del archivo, agregar:
```gdscript
## Verifica si un tipo de punto está permitido en el modo de juego actual.
## mode_name: string del modo (ej: "DEATHMATCH", "CAPTURA_BANDERA").
## Si mode_name está vacío, retorna true (compatible con todo).
static func is_point_allowed_in_mode(point_type: int, mode_name: String) -> bool:
    if mode_name.is_empty():
        return true
    var config: Dictionary = _load_config()
    var excluded: Dictionary = config.get("excluded_modes", {})
    var type_name: String = POINT_NAMES_BY_VALUE.get(point_type, "")
    if type_name.is_empty():
        return true
    var excluded_list: Array = excluded.get(type_name, [])
    return mode_name.to_upper() not in excluded_list
```

---

**Prompt listo para IA:**

```
Estás trabajando en el repositorio Jillkrav/Fps-Prueba, branch Perplexity.

Archivo a modificar: scripts/Multiplayer/nav/bots/semantic_point_rules.gd

Tarea:
Al final del archivo, agrega este nuevo método estático:

## Verifica si un tipo de punto está permitido en el modo de juego actual.
## mode_name: string del modo (ej: "DEATHMATCH", "CAPTURA_BANDERA").
## Si mode_name está vacío, retorna true (compatible con todo).
static func is_point_allowed_in_mode(point_type: int, mode_name: String) -> bool:
	if mode_name.is_empty():
		return true
	var config: Dictionary = _load_config()
	var excluded: Dictionary = config.get("excluded_modes", {})
	var type_name: String = POINT_NAMES_BY_VALUE.get(point_type, "")
	if type_name.is_empty():
		return true
	var excluded_list: Array = excluded.get(type_name, [])
	return mode_name.to_upper() not in excluded_list

No toques ningún otro archivo. Respeta la indentación con tabs.
```

---

### Tarea 6.3 — Aplicar filtro de modo en _get_semantic_point_nearby

**Archivo a modificar:**
`scripts/Multiplayer/ai/bot_behaviors/state_roaming.gd`

**Prerequisito:** Tareas 6.1 y 6.2 completadas.

**Qué cambiar:**
En `_get_semantic_point_nearby()`, en el bucle `for p in points:`, agregar un filtro de modo de juego. Asumiendo que el modo de juego se obtiene de un autoload `MatchManager` con una propiedad `current_mode_name: String`:

Agrega este filtro DESPUÉS del filtro de cooldown y ANTES del filtro de backtrack:
```gdscript
# Filtrar puntos no permitidos en el modo de juego actual
var current_mode: String = ""
if is_instance_valid(MatchManager):
    current_mode = MatchManager.get("current_mode_name") if MatchManager.get("current_mode_name") else ""
if not SemanticPointRules.is_point_allowed_in_mode(p.point_type, current_mode):
    continue
```

**Nota importante:** Si `MatchManager` no tiene la propiedad `current_mode_name`, adapta esta línea a la forma correcta de obtener el modo de juego en tu proyecto. Si no sabes cómo se obtiene, consulta antes de hacer el cambio.

---

**Prompt listo para IA:**

```
Estás trabajando en el repositorio Jillkrav/Fps-Prueba, branch Perplexity.

Archivo a modificar: scripts/Multiplayer/ai/bot_behaviors/state_roaming.gd

Tarea:
En el método _get_semantic_point_nearby(), dentro del bucle `for p in points:`, agrega este bloque
justo DESPUÉS del bloque que filtra cooldowns y ANTES del bloque que filtra backtrack:

		# Filtrar puntos no permitidos en el modo de juego actual
		var current_mode: String = ""
		if is_instance_valid(MatchManager):
			var mode_val = MatchManager.get("current_mode_name")
			if mode_val != null:
				current_mode = mode_val
		if not SemanticPointRules.is_point_allowed_in_mode(p.point_type, current_mode):
			continue

Si MatchManager no tiene la propiedad current_mode_name, NO hagas el cambio y avisa.
No toques ningún otro archivo. Respeta la indentación con tabs.
```

---

## Resumen de archivos modificados por fase

| Fase | Archivos tocados |
|------|------------------|
| 1.1 | `state_roaming.gd` |
| 1.2 | `state_roaming.gd` |
| 1.3 | `state_roaming.gd` |
| 2.1 | `semantic_point.gd` |
| 2.2 | `semantic_point.gd` |
| 2.3 | `state_roaming.gd` |
| 3.1 | `semantic_point.gd`, `semantic_point_marker.gd` |
| 3.2 | `navigation_system.gd` |
| 3.3 | `state_roaming.gd` |
| 4.1 | `bot_base.gd` |
| 5.1 | `semantic_point_rules.gd` |
| 5.2 | `semantic_points.json` |
| 5.3 | `state_roaming.gd` |
| 6.1 | `semantic_points.json` |
| 6.2 | `semantic_point_rules.gd` |
| 6.3 | `state_roaming.gd` |
