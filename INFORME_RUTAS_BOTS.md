# Informe de rutas y orientación de bots

## Alcance

Se revisó la rama `Perplexity` (commit base `a851412b80cb65441d5795db3872d4ca5d29ab14`) para corregir el desplazamiento de espalda de los bots y permitir rutas authored escalables por rol y mapa.

No se movieron archivos existentes ni se mezclaron responsabilidades entre `Multiplayer`, `Campaña` y `Compartido`. La solución se concentra en `scripts/Multiplayer`, `scenes/Multiplayer` y configuraciones ya existentes.

## Cambios aplicados

### 1. Orientación mientras navega

- `scripts/Multiplayer/nav/bots/movement_system.gd` incorpora `_face_movement_direction(delta)`.
- El cuerpo del bot gira suavemente hacia la velocidad horizontal de desplazamiento durante navegación.
- La rotación no interviene cuando hay combate activo, objetivo vivo o una orden explícita de apuntar; en esos casos el sistema de combate conserva la prioridad.
- Esto evita que el bot avance de espalda y mantiene alineados el movimiento, el cuerpo y el frente del arma.

### 2. Percepción desde el arma

- `scripts/Multiplayer/ai/bot_behaviors/perception_system.gd` calcula el cono de visión desde el arma y usa su forward real.
- Se añadió un FOV por defecto de 110 grados, con posibilidad de que cada arma defina `ai_vision_fov_degrees`.
- La línea de visión se calcula desde el origen de disparo hacia el objetivo.
- `combat_system.gd` reutiliza la visibilidad confirmada por PerceptionSystem para objetivos de tipo personaje, evitando rutas de disparo que ignoren la visibilidad.

### 3. Rutas authored reutilizables

- `scripts/Multiplayer/caminos/camino_bot.gd` define los roles de ruta `ASSAULT`, `FLANKER` y `DEFENDER`.
- Cada `CaminoBot` puede tener `route_id`, `enabled`, puntos de curva, dirección reversible y conexiones opcionales mediante `next_paths` con pesos.
- Las rutas se registran en el grupo `bot_routes` y pueden mostrar una línea de depuración.
- Se agregó `scripts/Multiplayer/nav/bots/bot_route_navigator.gd`, que selecciona rutas compatibles por rol, sigue waypoints, cambia de dirección según el extremo más cercano y se recupera después de un atasco.

### 4. Rutas específicas por mapa

- Los caminos permanecen dentro del contenido de Multiplayer y se instancian desde las escenas de los mapas.
- `state_roaming.gd` busca rutas dentro de la escena del mapa activa, no en una lista global fija.
- Al agregar un mapa, se pueden crear tantos `CaminoBot` como se necesiten en su propia escena y asignarles rol e ID sin modificar el código central.
- En `map_1.tscn` se observa una organización local de caminos bajo `Puntos clave/Caminos`, con categorías de asalto y flanco.

### 5. Selección y fallback

- Los roles se traducen a categorías de ruta: asalto -> `ASSAULT`, flanqueador -> `FLANKER`, defensor/patrullador/francotirador/apoyo -> `DEFENDER`.
- Si no existe una ruta compatible o esta termina, el bot conserva un fallback seguro: navegación al objetivo o patrulla normal.
- Los `next_paths` permiten encadenar rutas y usar pesos para variar la elección sin recalcular caminos continuamente.

## Organización respetada

- Código de rutas y navegación: `scripts/Multiplayer/caminos` y `scripts/Multiplayer/nav/bots`.
- Estados y percepción de IA: `scripts/Multiplayer/ai/bot_behaviors`.
- Plantillas y rutas de escena: `scenes/Multiplayer/caminos`.
- Mapas: `scenes/Multiplayer/mapas`.
- No se introdujeron dependencias de rutas en `Campaña`.

## Cómo crear rutas en un mapa nuevo

1. Abrir la escena del mapa en `scenes/Multiplayer/mapas`.
2. Crear un nodo contenedor local, por ejemplo `Puntos clave/Caminos`.
3. Instanciar `scenes/Multiplayer/caminos/camino_bot.tscn` una vez por ruta.
4. Dibujar los puntos de la `Curve3D` dentro del NavMesh del mapa.
5. Definir `role` como asalto, flanqueo o defensa.
6. Definir un `route_id` único dentro de ese mapa, por ejemplo `asalto_centro_01`.
7. Opcionalmente configurar `next_paths` y `next_path_weights` para conectar tramos o diversificar rutas.
8. Probar con el debug de caminos antes de dar por terminada la ruta.

## Validación pendiente en Godot

No se ejecutó el proyecto desde el editor durante esta revisión, por lo que antes de fusionar o continuar se debe comprobar manualmente:

- El bot rota hacia el siguiente waypoint durante roaming.
- Al detectar un enemigo, conserva la mira hacia el objetivo y no pelea con la rotación de navegación.
- Cada ruta dibujada se mantiene sobre el NavMesh.
- Las rutas de asalto, flanqueo y defensa se asignan solo a los roles esperados.
- Al terminar una ruta o quedar atascado, el bot usa el fallback y no se queda detenido.
- En multijugador, la autoridad que controle los bots debe ser la que determine su comportamiento y estado.

## Resumen

La rama ya implementa una solución modular y ligera: los bots se orientan hacia su movimiento fuera de combate, perciben desde la dirección real del arma y siguen rutas definidas dentro de cada mapa. Cada mapa puede contener una cantidad indefinida de rutas organizadas por rol, sin modificar una lista global ni afectar campaña o componentes compartidos.
