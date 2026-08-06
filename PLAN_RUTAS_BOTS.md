# Plan por fases: rutas authored para bots

## Resumen

Se agregan props reutilizables para rutas de bots y saltos authored. Los caminos usan `Path3D` y `Curve3D`: son datos sin colisión física, editables desde el editor y visibles solo cuando se activa `show_debug`. Los saltos usan `Area3D`: detectan el cruce de bots, pero sus capas y máscaras comienzan en cero para no afectar la física ni al jugador hasta que se configure una capa exclusiva de IA.

## Archivos creados

```text
scenes/Multiplayer/caminos/
├── camino_bot.gd
├── camino_bot.tscn
├── asalto/camino_asalto.tscn
├── flanqueador/camino_flanqueador.tscn
├── defensor/camino_defensor.tscn
└── saltos/
    ├── salto_inicio.gd
    ├── salto_inicio.tscn
    ├── salto_fin.gd
    └── salto_fin.tscn
```

## Uso de CaminoBot

1. Instanciar `camino_asalto.tscn`, `camino_flanqueador.tscn` o `camino_defensor.tscn` dentro de un mapa.
2. Seleccionar el `Path3D` y editar los puntos de su `Curve3D` para dibujar la ruta.
3. Asignar un `route_id` único.
4. Agregar las rutas de salida en `next_paths` y sus pesos correspondientes en `next_path_weights`.
5. Activar `show_debug` durante pruebas; desactivarlo para una partida normal.
6. Si la retirada por la misma ruta es válida, mantener `reverse_allowed` activado.

Los pesos son relativos: 50, 30 y 20 producen elecciones de 50%, 30% y 20%.

## Uso de saltos

1. Instanciar `salto_inicio.tscn` en el borde/línea donde debe empezar el salto.
2. Escalar su `CollisionShape3D` para cubrir la línea de activación.
3. Instanciar `salto_fin.tscn` en la zona de aterrizaje y ajustar su `CollisionShape3D`.
4. En `SaltoInicio.target_finish`, asignar manualmente el `SaltoFin` correcto.
5. En `SaltoFin.next_paths`, conectar los Caminos que el bot podrá elegir al aterrizar; definir pesos si hay más de uno.
6. Configurar una capa y máscara exclusiva de triggers de IA antes de probar el salto.

Los scripts esperan que el controlador del bot implemente `start_authored_jump(salto_fin)` y `finish_authored_jump(salto_fin, siguiente_camino)`. Esos métodos no se añadieron todavía porque deben adaptarse al controlador de movimiento real del proyecto.

## Fase 1 — Validación de props

- [ ] Confirmar que los `.tscn` cargan sin errores en Godot.
- [ ] Instanciar un camino de cada rol en un mapa de prueba.
- [ ] Editar curvas rectas y curvas complejas.
- [ ] Activar y desactivar el debug.
- [ ] Configurar al menos una conexión entre dos caminos.

## Fase 2 — Integración de seguimiento

- [ ] Revisar el controlador actual del bot.
- [ ] Añadir referencia a `CaminoBot`, progreso y último camino válido.
- [ ] Hacer que el bot use puntos de `Curve3D` como objetivos de movimiento.
- [ ] Detectar fin de camino y consultar `get_next_path()`.
- [ ] Implementar retorno inverso cuando corresponda.
- [ ] Añadir recuperación ante atasco.

## Fase 3 — Integración de salto

- [ ] Medir el alcance horizontal y vertical del salto real del jugador.
- [ ] Validar distancia entre Inicio y Fin antes de ejecutar el salto.
- [ ] Crear `start_authored_jump` en el bot con las físicas actuales.
- [ ] Crear `finish_authored_jump` para retomar la ruta elegida.
- [ ] Añadir cooldown y manejo de aterrizaje fallido.

## Fase 4 — Pruebas de diseño

- [ ] Construir tres corredores generales de mapa.
- [ ] Crear dos rutas de asalto.
- [ ] Crear cinco rutas de flanqueo.
- [ ] Agregar variantes y bifurcaciones ponderadas.
- [ ] Probar con varios bots y ajustar pesos.

## Límites actuales

- Aún no se modifican los mapas existentes ni los controladores de bots.
- Aún no existe validación automática de alcance máximo de salto.
- Salud, munición, cobertura y vehículos se integrarán después de validar el seguimiento básico.
