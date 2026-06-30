# scripts/ai/memory_system.gd
# ──────────────────────────────────────────────────────────────────
# SISTEMA DE MEMORIA TIPIFICADA PARA NPCs
#
# Almacena información persistente con expiración automática.
# Es la base para que los bots tomen decisiones informadas en lugar
# de reaccionar solo al instante presente.
#
# ── FILOSOFÍA ──
# La memoria transforma una IA reactiva en una IA que "recuerda".
# Un bot que recuerda dónde vio a un enemigo por última vez,
# dónde escuchó un disparo, o dónde hay un botiquín, puede:
#   - Perseguir (HUNT) usando la última posición conocida
#   - Investigar (INVESTIGATE) sonidos sospechosos
#   - Buscar recursos (HEALTH, AMMO) vistos anteriormente
#   - Coordinarse con aliados (ALLY_POSITION)
#
# ── TIPOS DE MEMORIA ──
# Cada tipo tiene su propia duración y propósito.
# Agregar un nuevo tipo: 1) Añadir al enum, 2) Añadir duración en
#   _build_durations(), 3) Usar desde PerceptionSystem o behaviors.
#
# ── USO DESDE PERCEPTIONSYSTEM ──
#   memory.record_enemy_position(enemy_node, enemy_position)
#
# ── USO DESDE BEHAVIORS (vía BotBrain) ──
#   if brain.has_enemy_memory():
#       var pos = brain.get_last_enemy_position()
#       brain.navigate_to(pos, speed, delta)
#
# ── DECAIMIENTO ──
# Cada frame, el sistema reduce el tiempo de vida de todas las
# memorias. Cuando una memoria expira, se elimina automáticamente.
# ──────────────────────────────────────────────────────────────────
extends Node
class_name MemorySystem


# ══════════════════════════════════════════════════════════════════
# ENUM — TIPOS DE MEMORIA
# ══════════════════════════════════════════════════════════════════
# Agrega aquí nuevos tipos. Cada entrada necesita su duración en
# _build_durations() más abajo.
# ══════════════════════════════════════════════════════════════════

enum MemoryType {
	ENEMY_POSITION   = 0,  # Última posición donde se vio a un enemigo
	GUNSHOT          = 1,  # Posición de un disparo/explosión escuchado
	HEALTH_PACK      = 2,  # Botiquín visto (para buscar cura)
	WEAPON_ITEM      = 3,  # Arma vista en el suelo
	SUSPICIOUS_NOISE = 4,  # Ruido desconocido (para INVESTIGATE)
	ALLY_POSITION    = 5,  # Última posición conocida de un aliado
	NAV_TARGET       = 6,  # Hacia dónde se dirige el bot (para debug/replan)
}


# ══════════════════════════════════════════════════════════════════
# CLASE INTERNA: MemoryEntry
# ══════════════════════════════════════════════════════════════════

## Una entrada individual de memoria.
## Cada entrada tiene un tipo, datos flexibles, posición, confianza,
## timestamp de creación y duración restante.
class MemoryEntry:
	var type: int                     # MemoryType
	var data: Dictionary              # Payload flexible (ej: {"enemy": node, "loudness": 0.8})
	var position: Vector3             # Posición mundial del evento
	var confidence: float             # 0.0 (dudoso) a 1.0 (certeza absoluta)
	var timestamp: float              # Tiempo de creación (Time.get_ticks_msec() / 1000.0)
	var duration: float               # Duración total en segundos (antes de expirar)
	var _age: float = 0.0             # Edad acumulada en segundos

	## ¿Esta memoria sigue siendo válida?
	func is_valid() -> bool:
		return _age < duration

	## Progresión de decaimiento (0.0 = recién creada, 1.0 = a punto de expirar)
	func decay_ratio() -> float:
		if duration <= 0.0:
			return 0.0
		return clampf(_age / duration, 0.0, 1.0)

	## Texto descriptivo (para debug)
	func _to_string() -> String:
		return "Mem[type=%d age=%.1f/%.1f conf=%.2f pos=%s]" % [
			type, _age, duration, confidence, str(position.round())
		]


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES
# ══════════════════════════════════════════════════════════════════

## Almacén interno de todas las memorias activas
var _entries: Array[MemoryEntry] = []

## Duraciones por tipo (se cargan en _ready)
var _durations: Dictionary = {}

## Capacidad máxima total de entradas (para evitar leaks por acumulación)
const MAX_ENTRIES: int = 100


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA
# ══════════════════════════════════════════════════════════════════

func _ready() -> void:
	_durations = _build_durations()


## Actualiza el sistema: decae todas las memorias y elimina las expiradas.
## Debe llamarse cada frame (desde NpcBase._physics_process).
func update(delta: float) -> void:
	_decay_all(delta)


# ══════════════════════════════════════════════════════════════════
# CONFIGURACIÓN DE DURACIONES
# ══════════════════════════════════════════════════════════════════
# 🔧 EDICIÓN RÁPIDA: Cambia los números aquí y todos los bots
#    ajustan automáticamente cuánto recuerdan cada cosa.
#
# 🧩 PARA AGREGAR UN NUEVO TIPO:
#    1. Agrega entrada al enum MemoryType (arriba)
#    2. Agrega entrada aquí: MemoryType.NUEVO: X.X
#    3. Listo — el sistema lo reconoce automáticamente
# ══════════════════════════════════════════════════════════════════

static func _build_durations() -> Dictionary:
	return {
		MemoryType.ENEMY_POSITION:   15.0,   # 15s: tiempo para perseguir
		MemoryType.GUNSHOT:          8.0,    # 8s:  sonido reciente, investigar rápido
		MemoryType.HEALTH_PACK:      20.0,   # 20s: botiquín, vale la pena recordar
		MemoryType.WEAPON_ITEM:      25.0,   # 25s: arma, alta prioridad
		MemoryType.SUSPICIOUS_NOISE: 6.0,    # 6s:  ruido vago, olvidar rápido
		MemoryType.ALLY_POSITION:    10.0,   # 10s: posición de aliado
		MemoryType.NAV_TARGET:       5.0,    # 5s:  destino de navegación
	}


# ══════════════════════════════════════════════════════════════════
# API PÚBLICA — Registro de memorias
# ══════════════════════════════════════════════════════════════════

## Registra una nueva memoria o actualiza una existente del mismo tipo
## con datos similares (según el criterio de merge).
##
## Parámetros:
##   type:       MemoryType
##   data:       Dictionary con información adicional
##   position:   Vector3 de la posición mundial
##   confidence: 0.0-1.0 (por defecto 1.0)
func record(type: int, data: Dictionary = {}, position: Vector3 = Vector3.ZERO, confidence: float = 1.0) -> void:
	if _entries.size() >= MAX_ENTRIES:
		# Eliminar la entrada más vieja para hacer espacio
		_entries.sort_custom(func(a, b): return a.timestamp < b.timestamp)
		_entries.pop_front()

	var duration: float = _durations.get(type, 10.0)
	var now: float = Time.get_ticks_msec() / 1000.0

	# Intentar actualizar entrada existente del mismo tipo si está cerca
	for entry in _entries:
		if entry.type == type and _should_merge(entry, data, position):
			entry.data = data
			entry.position = position
			entry.timestamp = now
			entry.confidence = max(entry.confidence, confidence)
			entry._age = 0.0
			entry.duration = duration
			return

	# Crear nueva entrada
	var new_entry := MemoryEntry.new()
	new_entry.type = type
	new_entry.data = data
	new_entry.position = position
	new_entry.confidence = confidence
	new_entry.timestamp = now
	new_entry.duration = duration
	new_entry._age = 0.0
	_entries.append(new_entry)


## Atajo: registra posición de enemigo (el caso más común).
func record_enemy_position(enemy: Node3D, position: Vector3) -> void:
	record(MemoryType.ENEMY_POSITION, {"enemy": enemy}, position, 1.0)


## Atajo: registra un disparo escuchado.
func record_gunshot(position: Vector3, loudness: float = 1.0) -> void:
	record(MemoryType.GUNSHOT, {"loudness": loudness}, position, clampf(loudness, 0.0, 1.0))


## Atajo: registra un botiquín visto.
func record_health_pack(pickup: Node3D, position: Vector3) -> void:
	record(MemoryType.HEALTH_PACK, {"pickup": pickup}, position, 1.0)


## Atajo: registra un arma vista.
func record_weapon_item(pickup: Node3D, position: Vector3) -> void:
	record(MemoryType.WEAPON_ITEM, {"pickup": pickup}, position, 1.0)


## Atajo: registra un ruido sospechoso.
func record_suspicious_noise(position: Vector3, intensity: float = 0.5) -> void:
	record(MemoryType.SUSPICIOUS_NOISE, {"intensity": intensity}, position, clampf(intensity, 0.0, 1.0))


# ══════════════════════════════════════════════════════════════════
# API PÚBLICA — Consultas
# ══════════════════════════════════════════════════════════════════

## Retorna la entrada más reciente de un tipo específico,
## o null si no hay ninguna válida.
func get_most_recent(type: int) -> MemoryEntry:
	var best: MemoryEntry = null
	var best_time: float = -1.0
	for entry in _entries:
		if entry.type == type and entry.is_valid():
			if entry.timestamp > best_time:
				best_time = entry.timestamp
				best = entry
	return best


## Retorna TODAS las entradas válidas de un tipo específico.
func get_all_of_type(type: int) -> Array[MemoryEntry]:
	var result: Array[MemoryEntry] = []
	for entry in _entries:
		if entry.type == type and entry.is_valid():
			result.append(entry)
	return result


## ¿Hay al menos una entrada válida del tipo especificado?
## Si max_age > 0, solo considera entradas más recientes que max_age segundos.
func has_type(type: int, max_age: float = -1.0) -> bool:
	var now: float = Time.get_ticks_msec() / 1000.0
	for entry in _entries:
		if entry.type == type and entry.is_valid():
			if max_age <= 0.0 or (now - entry.timestamp) <= max_age:
				return true
	return false


## Retorna la posición de la entrada más reciente de un tipo,
## o Vector3.ZERO si no hay ninguna.
func get_position(type: int) -> Vector3:
	var entry: MemoryEntry = get_most_recent(type)
	if entry != null:
		return entry.position
	return Vector3.ZERO


## Retorna la última posición conocida de un enemigo.
## Equivalente a get_position(ENEMY_POSITION).
func get_last_enemy_position() -> Vector3:
	return get_position(MemoryType.ENEMY_POSITION)


## ¿Hay memoria de enemigos?
func has_enemy_memory() -> bool:
	return has_type(MemoryType.ENEMY_POSITION)


## Retorna el número total de entradas activas.
func count() -> int:
	return _entries.size()


## Retorna el número de entradas activas de un tipo.
func count_type(type: int) -> int:
	var n: int = 0
	for entry in _entries:
		if entry.type == type and entry.is_valid():
			n += 1
	return n


# ══════════════════════════════════════════════════════════════════
# API PÚBLICA — Limpieza
# ══════════════════════════════════════════════════════════════════

## Elimina todas las entradas de un tipo específico.
func clear_type(type: int) -> void:
	_entries = _entries.filter(func(e): return e.type != type)


## Elimina todas las entradas de memoria.
func clear_all() -> void:
	_entries.clear()


## Elimina todas las entradas expiradas (limpieza forzada).
func clean_expired() -> void:
	_entries = _entries.filter(func(e): return e.is_valid())


# ══════════════════════════════════════════════════════════════════
# INTERNO — Decaimiento y merge
# ══════════════════════════════════════════════════════════════════

## Decae todas las entradas y elimina las expiradas.
func _decay_all(delta: float) -> void:
	var still_valid: Array[MemoryEntry] = []
	for entry in _entries:
		entry._age += delta
		if entry.is_valid():
			still_valid.append(entry)
	_entries = still_valid


## Determina si una entrada existente debe fusionarse con nuevos datos.
## Por defecto, fusiona si es el mismo tipo y la misma posición aproximada.
## Se puede sobrescribir para lógica de merge más específica.
func _should_merge(existing: MemoryEntry, _new_data: Dictionary, new_position: Vector3) -> bool:
	if existing.type == MemoryType.ENEMY_POSITION:
		# Para enemigos, siempre actualizar (es la misma fuente)
		return true
	# Para otros tipos, fusionar si está cerca (5 unidades)
	return existing.position.distance_to(new_position) < 5.0


# ══════════════════════════════════════════════════════════════════
# DEBUG
# ══════════════════════════════════════════════════════════════════

func debug_string() -> String:
	var counts: Dictionary = {}
	for entry in _entries:
		if entry.is_valid():
			counts[entry.type] = counts.get(entry.type, 0) + 1
	var parts: PackedStringArray = []
	for type_id in counts:
		parts.append("%s:%d" % [MemoryType.keys()[type_id], counts[type_id]])
	return "Memory[%s]" % ", ".join(parts)
