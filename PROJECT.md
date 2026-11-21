# Sandbox universal de combates ATB — Documento maestro de diseño e implementación

**Versión de la especificación:** 1.0 (diseño inicial)  
**Plataformas:** PC y Android  
**Motor obligatorio:** Godot  
**Idioma de interfaz:** español; identificadores técnicos en inglés  
**Destinatario:** IA desarrolladora y responsables del proyecto

## 0. Cómo utilizar este documento

Este documento consolida las decisiones de diseño tomadas durante la definición del proyecto. Es la referencia inicial para implementar el software y elaborar documentación especializada para generar contenido mediante IA externa.

- **Confirmado:** requisitos funcionales acordados; no eliminarlos ni sustituirlos unilateralmente.
- **Propuesta técnica:** solución recomendada, modificable si se justifica y se conserva el comportamiento requerido.
- **Pendiente:** decisión de detalle no acordada. No presentar valores provisionales como reglas de equilibrio definitivas.

La IA desarrolladora debe implementar por fases, mantener un registro de decisiones técnicas, actualizar pruebas y documentación junto al código, y evitar dependencias de pago. No intentar construir todas las funcionalidades en una sola iteración. Las funcionalidades avanzadas pertenecen al alcance objetivo de esta primera etapa del producto, pero se entregarán incrementalmente. Un prototipo reducido no equivale a completar la etapa.

## 1. Visión, objetivos y alcance confirmado

Construir un sandbox de simulación automática de combates por turnos con iniciativa ATB. El producto no es inicialmente un RPG tradicional: es un entorno universal que ofrece las reglas, herramientas y sistemas necesarios para crear personajes (PJ) de cualquier arquetipo, importarlos, enfrentarlos y analizar los resultados.

### 1.1 Objetivos

- Crear personajes completamente distintos sin modificar el código fuente del motor para cada uno.
- Importar estadísticas, habilidades, artefactos, recursos, efectos, mecánicas especiales, scripts e IA propia.
- Ejecutar duelos automáticos individuales con reproducción visual e inspección detallada.
- Ejecutar grandes cantidades de combates sin renderizado para comparar resultados y estrategias.
- Calcular automáticamente los puntos de creación conforme a un documento de equilibrio seleccionable.
- Exportar informes para seres humanos, herramientas externas e IA.
- Mantener independencia entre motor, reglamento matemático, equilibrio, personajes e IA.

### 1.2 Límites de la versión inicial

- Duelos 1 contra 1 como modalidad inicial. El modelo interno debe soportar equipos, múltiples participantes, relaciones aliado/enemigo e invocaciones, sin codificar la lógica suponiendo exactamente dos entidades.
- Escenario abstracto: no hay casillas, movimiento espacial, distancias, alcance posicional ni terreno táctico.
- Acciones decididas automáticamente por la IA de cada PJ; no control manual inicial.
- Interfaz abstracta con retratos, barras y registro; no se requieren sprites animados ni entorno 3D.
- Creación de contenido con archivos externos, no editor visual integrado inicialmente.
- Sin campaña, clases obligatorias, niveles, progresión, multijugador ni servicios online como requisitos iniciales.
- No integrar IA generativa: una IA externa podrá producir archivos conforme a la documentación pública del proyecto.
- Funcionamiento local y offline como objetivo; sin servicios de pago, suscripciones ni claves de API obligatorias. El proceso de instalación del entorno de desarrollo puede requerir descargar herramientas gratuitas.

## 2. Arquitectura conceptual confirmada

| Capa | Responsabilidad |
|---|---|
| Motor universal | Tiempo virtual, turnos, eventos, acciones, recursos, efectos, RNG, scripts y registro. |
| Reglamento global de combate | Define fórmulas de daño, probabilidades, ATB, orden y reglas matemáticas de resolución. |
| Perfil/documento de equilibrio | Define valores base, presupuesto, criterios y fórmulas automáticas de coste, restricciones de construcción y validación. |
| Contenido importable | Personajes, habilidades, artefactos, efectos, recursos, IA, scripts y activos gráficos. |
| Aplicación | Biblioteca, importación, configuración, reproducción, ejecución masiva, informes y persistencia. |

No confundir reglamento global con equilibrio. El primero determina qué ocurre en combate; el segundo determina si una construcción es admisible y cuánto cuesta. Ambos serán configurables y versionados. Un personaje puede ser técnicamente válido pero no reglamentario. El modo libre permite lo segundo, nunca elude seguridad o validez técnica.

El motor no debe depender de la UI, del framerate, del tiempo de pared ni de servicios externos. Los contenidos se interpretan mediante operaciones de dominio y scripts aislados; no mediante clases de PJ codificadas individualmente.

## 3. Estadísticas y recursos

### 3.1 Catálogo universal y referencia inicial

Los valores siguientes son una **referencia provisional aceptada**, no una escala de equilibrio definitiva. Deben residir en el perfil de equilibrio y no incrustarse en el motor.

| ID provisional | Significado | Base gratuita de referencia |
|---|---|---:|
| `HP` | Vida máxima; distinguir de vida actual en el estado | 1000 |
| `ATK` | Ataque físico | 100 |
| `MAG` | Ataque mágico | 100 |
| `DEF` | Defensa física | 100 |
| `RES` | Resistencia mágica | 100 |
| `SPD` | Velocidad e iniciativa | 100 |
| `ACC` | Precisión | 100 % |
| `EVA` | Evasión | 10 % |
| `CRIT` | Probabilidad de crítico | 10 % |
| `CRIT_DMG` | Multiplicador crítico | 150 % (×1,5) |
| `HEAL_REC` | Multiplicador de curación recibida | 100 % (×1) |
| `ELEM_AFF` | Afinidades ofensivas por elemento | 0 % |
| `ELEM_RES` | Resistencias defensivas por elemento | 0 % |

Permitir estadísticas personalizadas además del catálogo base. Documentar unidad y representación coherentes para cada estadística (por ejemplo, probabilidades internas normalizadas de 0 a 1, porcentaje en interfaz). La precisión decimal interna y el redondeo configurable y determinista están confirmados.

### 3.2 Recursos

Únicos recursos obligatorios: vida e iniciativa ATB. Cualquier otro recurso es opcional y configurable por PJ: maná, energía, furia, cargas, corrupción, temperatura, etc. Cada recurso puede especificar valor inicial, capacidad, mínimos, regeneración, consumo, eventos y comportamiento en límites; permitir modificar esas propiedades durante combate. No imponer una moneda de recursos universal.

### 3.3 Modificadores de estadísticas

Soportar modificaciones planas, porcentuales aditivas, multiplicativas, sustituciones, conversiones entre estadísticas, intercambios, máximos y mínimos, y fórmulas dinámicas (p. ej. ATK según HP perdido). Deben poder combinarse, expirar y eliminarse de forma ordenada, con origen y prioridad identificables. El orden exacto de combinación, dependencias y tratamiento de ciclos se documentará en el reglamento y motor. No confundir estadísticas base con valores efectivos.

## 4. Sistema ATB y turnos (confirmado)

- Usar tiempo virtual de combate, independiente de la velocidad de reproducción en pantalla.
- Umbral predeterminado de iniciativa: 1000 puntos, configurable.
- Ganancia de iniciativa proporcional a `SPD`. Referencia matemática: `delta_initiative = SPD * delta_virtual_time`.
- Al alcanzar el umbral, la entidad puede iniciar turno; descontar el umbral y conservar excedente.
- Las acciones ordinarias son instantáneas en tiempo virtual; canalización, carga u otras mecánicas pueden consumir tiempo o programar eventos futuros.
- La velocidad y la iniciativa pueden modificarse dinámicamente: adelantar, retrasar, robar, transferir, bloquear, suspender, conceder turnos adicionales, etc.
- Los empates de iniciativa se resuelven mediante un criterio configurable y reproducible.
- Sistema base por turno: una acción principal, acciones gratuitas y reacciones (incluidas fuera del turno propio). Las habilidades pueden modificar el número, tipo y disponibilidad de acciones.
- Las acciones gratuitas y reacciones no tienen una cuota de diseño universal: cada habilidad determina sus límites (usos, cargas, cooldown, proc, condición…). Los límites técnicos contra bucles sí son obligatorios.
- Ataque básico universal opcional y gratuito en puntos de creación. Un PJ puede depender enteramente del ataque básico o carecer de él. La fórmula concreta del ataque básico aún debe definirse.
- Acción universal de espera/pasar turno válida como alternativa, incluso si no existen otras acciones válidas.

**Propuesta técnica:** programador de eventos discretos que calcule directamente el próximo instante relevante (turno, expiración, canalización, evento temporal) sin simular frames vacíos. Actualizar correctamente la iniciativa acumulada antes de modificar SPD. Resolver simultaneidades con una clave de orden estable. Definir por reglamento el tratamiento de SPD cero, negativa, parada del tiempo, acciones encadenadas y posibles empates.

## 5. Reglamento matemático predeterminado

Las fórmulas siguientes son configurables globalmente. No requieren recompilar el juego. La habilidad puede introducir excepciones explícitas a través del motor.

### 5.1 Daño y elementos

Tres tipos universales de daño:

- **Físico**: mitigado por DEF.
- **Mágico**: mitigado por RES.
- **Verdadero**: ignora exclusivamente DEF y RES por defecto; sigue sujeto a resistencias elementales, escudos y demás defensas aplicables. Una habilidad puede especificar otros bypass.

Tipo de daño y elemento son propiedades independientes. Ejemplo: daño físico de fuego. Una acción puede contener múltiples componentes de daño, con tipos y elementos distintos y resolución individual. Definir explícitamente si las tiradas se comparten por ataque o se realizan por componente; no asumirlo para todos los casos.

Catálogo elemental configurable y ampliable (fuego, agua, tierra, aire, rayo, hielo, luz, oscuridad son ejemplos, no catálogo cerrado). Permitir daño sin elemento. Afinidad elemental aumenta o modifica daño causado con ese elemento; resistencia modifica daño recibido. Admitir vulnerabilidad, inmunidad y absorción elemental (conversión a curación). La fórmula exacta de combinación de afinidades y resistencias, tratamiento de valores extremos y de absorción deberá documentarse.

### 5.2 Mitigación base de referencia confirmada

Para DEF no negativa:

```text
physical_damage = base_damage * 100 / (100 + effective_DEF)
magical_damage  = base_damage * 100 / (100 + effective_RES)
true_damage     = base_damage
```

Ejemplo: 200 de daño físico frente a DEF 100 produce 100 antes de otros modificadores. Son fórmulas con rendimientos decrecientes en el porcentaje mitigado. Definir el dominio válido de DEF/RES y el caso de valores negativos para evitar división por cero; pendiente de política definitiva.

Herramientas de penetración física, mágica y elemental: plana y porcentual. No constituyen estadísticas base obligatorias. Orden de penetración, combinación y límites configurables/documentados.

### 5.3 Probabilidades, críticos y curación

- Probabilidad de impacto inicial: `P(hit) = ACC - EVA` (en unidades coherentes), con límites mínimo y máximo configurables. La habilidad puede modificar o ignorar la comprobación.
- Críticos: probabilidad basada en CRIT y multiplicador CRIT_DMG para daño; también pueden afectar curación, duración, recursos y otras acciones cuando las habilidades lo autoricen. No aplicar automáticamente el multiplicador de daño a todo.
- Sin variación aleatoria adicional de daño por defecto (no rango ±5 %). Sí existe azar de impacto, crítico, aplicación de efectos y procs, modificado por estadísticas y reglas.
- HEAL_REC modifica las curaciones recibidas; definir si afecta a absorciones u otros efectos, y los casos de bloqueo o inversión de curación.
- **Propuesta:** `effective_heal = raw_heal * HEAL_REC` antes de limitar a vida faltante y registrar exceso. Mantener extensión para excepciones explícitas.
- Todo el azar del combate procede del RNG controlado por el motor, con semillas y trazabilidad.

### 5.4 Defensas nativas

Herramientas para escudos de absorción, bloqueo, parada, reducción plana y porcentual, inmunidad, redirección y conversión de daño a otros tipos o recursos, absorción elemental y prevención de muerte. No son capacidades gratuitas universales; se conceden mediante contenido. Mantener información de origen, prioridad, duración y cantidades mitigadas.

## 6. Habilidades, efectos y eventos

### 6.1 Habilidades declarativas y programables

Deben coexistir dos mecanismos: operaciones declarativas predefinidas, fáciles de validar y valorar, y código personalizado aislado para mecánicas extraordinarias. Se pueden combinar dentro de un mismo componente. Una habilidad especifica al menos identidad, objetivos, tipo de acción, requisitos, costes de combate, límites, efectos, etiquetas y enlaces a scripts cuando proceda.

Categorías combinables: activa, pasiva, reactiva, automática, canalizada, cargada, sostenida, alternable y transformación. Una habilidad puede cambiar dinámicamente su tipo (principal a gratuita con proc), potencia, coste o cooldown. Soportar múltiples efectos por acción, secuencias, combos, condiciones y efectos dependientes de eventos.

### 6.2 Restricciones y costes de uso en combate

Operaciones para coste de recursos, cooldown, usos por combate/turno, cargas, umbrales de vida o recurso, estados requeridos, procs, combos, eventos, probabilidad y condición personalizada. Se pueden combinar. Posibilidad de interrumpir, cancelar o reservar habilidades y reacciones. Definir explícitamente cuándo se pagan recursos, se consumen cargas y comienza el cooldown, y qué sucede al ser interrumpida una habilidad.

### 6.3 Duraciones y acumulación de efectos

Soportar duración medida en turnos del afectado, turnos del lanzador, actuaciones globales, tiempo ATB o eventos (p. ej. tres golpes recibidos). Además, efectos permanentes o condicionados cuando su definición lo requiera. El mismo sistema sirve para cooldowns. Definir su evento de decremento exacto para evitar errores de un turno.

Catálogo nativo de estados como veneno, quemadura, sangrado, aturdimiento, silencio, congelación, regeneración, provocación y otros; se podrán crear estados personalizados. Los ejemplos no imponen aún sus efectos matemáticos.

Políticas de reaplicación: acumular intensidad, acumular duración, instancias independientes, reiniciar duración, reemplazar, conservar el más potente o ignorar. Cada efecto determina su política, límites, fuente y condiciones de eliminación.

Operaciones nativas para eliminar/disipar, robar, transferir, copiar, extender, acortar, bloquear e invertir efectos. Incluir etiquetas, inmunidades, propagación, activación y expiración controladas.

### 6.4 Motor de eventos

Motor basado en eventos, con suscripción/filtrado y extensiones personalizadas. Eventos antes y después de la resolución de operaciones relevantes. Catálogo mínimo de familias:

- Inicio/fin de combate y turno; avance de tiempo e iniciativa; acción seleccionada/iniciada/resuelta/interrumpida.
- Ataque, impacto, fallo, esquiva, crítico y proc.
- Antes/después de daño, curación, mitigación, escudos, bloqueo y parada.
- Cambio de HP, recursos, estadísticas o umbrales; aplicación/eliminación/expiración de estados.
- Transformación, invocación, cambio de configuración; antes de muerte, muerte y resurrección.
- Eventos de usuario autorizados y métricas personalizadas.

Los manejadores pueden modificar o cancelar acontecimientos aún pendientes, reflejar, interrumpir, sustituir, aplazar y desencadenar otras acciones. No modificar silenciosamente un acontecimiento ya registrado; emitir nuevas operaciones trazables.

**Propuesta técnica:** eventos tipados con ID, instante virtual, emisor, objetivo, origen, causa padre, fase, prioridad y datos; distinguir interceptores pre-resolución de notificaciones posteriores. Orden de reacciones estable; proteger profundidad, cantidad de eventos, instrucciones ejecutadas y recursión. No usar cadenas de señales no controladas como único sistema de resolución.

### 6.5 Orden de resolución propuesto (no aprobado en detalle)

1. Selección de acción y objetivo por la IA.
2. Validación de disponibilidad, tipo de acción, restricciones y objetivo.
3. Activación y pago de costes según política.
4. Eventos previos, modificadores, reacciones e interrupciones.
5. Comprobaciones de impacto, crítico y otros procs.
6. Cálculo de cada efecto y componente de daño.
7. Resolución defensiva (orden fino pendiente).
8. Aplicación de cambios efectivos.
9. Eventos posteriores y cadenas derivadas.
10. Comprobación de muerte/victoria y excepciones de acuerdo con la fase.
11. Registro e indicadores, emitidos durante todo el proceso, no solo al final.

Definir explícitamente muerte simultánea, reacción a golpe letal, ejecución multigolpe, revalidación de objetivos, cancelación y devoluciones. No resolver una victoria prematura que impida una resurrección autorizada. Las reglas exactas son pendientes del reglamento técnico inicial.

### 6.6 Manipulación temporal y de acontecimientos

Herramientas para restaurar selectivamente valores anteriores de HP/recursos/estados, retrasar aplicación del daño, repetir habilidades, copiar acciones enemigas, almacenar efectos para liberar posteriormente, restaurar parte de una configuración anterior, suspender efectos y cooldowns. La restauración de combate es distinta del retroceso del visor: el primero modifica el estado mediante operaciones registradas; el segundo solo inspecciona la historia. No rebobinar el RNG de forma implícita al restaurar HP. Definir qué elementos pueden restaurarse, límites y reglas de no duplicación por operación.

## 7. Personajes, artefactos, modularidad e invocaciones

Un PJ puede contener estadísticas base y personalizadas, habilidades, recursos, efectos, scripts y mecánicas propias, transformaciones, invocaciones, etiquetas, artefacto opcional e IA. No existen clases obligatorias; el arquetipo emerge de las herramientas utilizadas.

- **Artefacto:** un único hueco genérico opcional. Puede representar un arma, objeto, armadura, implante, etc. Tiene las mismas herramientas que una habilidad: estadísticas, pasivas, activas, reacciones, recursos, scripts, procs y reglas de IA específicas. No añadir espacios de equipamiento tradicionales en esta fase.
- **Transformaciones/fases:** pueden cambiar cualquier propiedad de combate, incluyendo stats, habilidades, artefacto, recursos, efectos, afinidades, resistencias y comportamiento de IA. Definir transiciones y políticas de persistencia.
- **Invocaciones:** se admiten aunque el duelo inicial sea 1v1. Entidades simples o completas con HP, estadísticas, barra ATB, habilidades, recursos e IA propias. Ejemplos: mascotas, clones, torretas o barreras. Modelar ownership, facción, validez de objetivos, ciclo de vida y participación en victoria; política concreta pendiente del reglamento.
- **Etiquetas (`tags`):** sistema universal, personalizable y utilizable en condiciones y filtros para PJ, habilidades, artefactos, recursos, efectos, entidades o acciones. Ejemplos: `undead`, `sword`, `fire`, `spell`. Sin implicaciones automáticas salvo las definidas por reglas.
- **Reutilización:** cada componente puede existir independientemente y formar parte de una biblioteca. Permitir referencias versionadas o contenido exclusivo del personaje.

## 8. Código personalizado y seguridad

**Confirmado:** las habilidades y la IA pueden incorporar código personalizado. **Propuesta técnica obligatoria para una implementación segura:** no ejecutar GDScript importado, binarios, plugins, escenas arbitrarias ni código nativo de terceros con permisos completos. El hecho de que Godot use GDScript no convierte a ese lenguaje en un sandbox de seguridad.

Implementar o elegir un intérprete gratuito, embebible y aislado compatible con PC y Android (por ejemplo, un lenguaje restringido con variables, funciones, condiciones, bucles acotados y API de dominio). Validar su aislamiento mediante pruebas antes de aceptar scripts externos. El lenguaje concreto queda delegado al desarrollo.

API versionada y de lista permitida: consultas del estado autorizado, operaciones de combate, eventos, RNG propio del motor, variables de script, almacenamiento de estado de combate y métricas. Las acciones mutantes pasan por validación y eventos. La IA solo consulta la vista permitida, predice y propone acciones; no altera HP ni recursos directamente.

Sin acceso libre a archivos, red, sistema operativo, procesos, reloj real, código dinámico del host, memoria del motor ni objetos Godot sin filtrar. Límites de instrucciones, memoria, profundidad, número de operaciones/eventos y tamaño de entrada. Errores controlados y reproducibles; abortar una simulación con diagnóstico si no puede continuar sin corromper datos. No contar un error técnico como derrota o empate silenciosamente.

## 9. Equilibrio y puntos de creación (PC)

Este sistema es independiente de los costes de uso durante combate. Los PC solo regulan la construcción del PJ.

### 9.1 Reglas confirmadas

- Todo PJ parte de estadísticas básicas gratuitas, definidas por el perfil seleccionado.
- Mejoras de estadísticas y cualquier capacidad de creación (habilidad, artefacto, pasiva, recurso con ventaja, transformación, invocación, inmunidad, mecánica o script, etc.) cuestan PC según su efecto.
- Desventajas/debilidades conceden puntos de vuelta. Las restricciones (cooldown, coste, activación condicionada, límite de usos, riesgo, canalización, etc.) pueden reducir el coste de una habilidad.
- Cálculo **automático** según reglas declaradas externamente; no aceptar costes arbitrarios introducidos por el creador.
- Presupuesto global libre, sin límites por categoría como regla inicial. Admite categorías de presupuesto distintas (500/1000/2000/5000 PC son ejemplos, no cifras definitivas).
- Las sinergias no tienen sobrecoste adicional; cada parte debe equilibrarse individualmente. Las simulaciones detectarán combinaciones excesivas y permitirán corregir la valoración de sus componentes en futuros perfiles.
- La IA de comportamiento es gratuita en PC. No otorgar capacidades mecánicas ocultas mediante scripts de IA.
- Ataque básico universal opcional gratuito. Las mejoras que lo potencian sí se valoran.
- No se diseñará ahora la tabla completa de costes. Se desarrollará de manera independiente del motor y se ajustará empíricamente.

### 9.2 Valoración automática y trazabilidad

El motor interpreta fórmulas y criterios de equilibrio versionados. Como contrato conceptual:

```text
creation_cost = stat_adjustments + purchased_component_costs
              + other_mechanical_costs - disadvantage_credits
remaining_points = budget - creation_cost
```

Las ecuaciones reales, descuentos, mínimos, redondeo y límites de devoluciones quedan pendientes. Mostrar desglose por componente, operación, regla aplicada, ajustes y origen. Evitar cobrar dos veces un componente meramente referenciado o contar dos veces una misma desventaja. Una instancia concedida por otra capacidad debe valorarse según el alcance de esta capacidad, con trazabilidad del cálculo.

**Limitación técnica:** no es posible deducir automáticamente la potencia de cualquier programa arbitrario. Propuesta: valorar operaciones declarativas o scripts sujetos a contratos mecánicos verificables (límites de efecto/uso, operaciones permitidas) y fórmulas de valoración. Los scripts no evaluables deben marcarse sin inventar un precio. En modo reglamentado deben quedar fuera hasta que el perfil pueda evaluarlos; en modo libre podrán ejecutarse si son técnicamente válidos. No convertir una declaración no verificada del autor en coste automático legítimo. La IA desarrolladora deberá concretar esta solución con pruebas.

### 9.3 Modos y validaciones

| Modo | Comportamiento |
|---|---|
| Libre | Permite exceder presupuesto e incumplir equilibrio con advertencias; exige validez técnica y seguridad. |
| Reglamentado | Exige validación técnica y de equilibrio según perfil seleccionado, incluido presupuesto y evaluabilidad. |

Validación técnica: esquema, tipos, dependencias, referencias, fórmulas y scripts seguros. Validación reglamentaria: criterios y costes del perfil. Evaluación empírica: resultados de combate, separada de las dos anteriores. No afirmar que igualdad de PC implica igualdad de poder.

Los documentos de equilibrio tendrán dos representaciones coherentes: documentación legible de creación y configuración estructurada ejecutable por el validador. Evitar que la IA deba interpretar prosa para calcular los PC.

## 10. IA de comportamiento

### 10.1 Requisitos confirmados

Cada personaje puede importar una IA propia e intercambiarla sin modificar su construcción. Sistema híbrido que admita prioridades fijas, puntuaciones dinámicas, árboles de comportamiento, máquinas de estados y código personalizado aislado. Las prioridades dinámicas son una opción de partida, no una restricción.

La IA debe poder seleccionar objetivos y acciones principales, gratuitas y reacciones, incluyendo decidir no actuar o reservar una acción. Gestionar habilidades en función de vida, recursos, procs y situación. No introducir selección estratégica aleatoria como requisito inicial; desempates deterministas por defecto. El azar del combate sigue existiendo independientemente.

Permitir memoria durante el combate (variables, observaciones, acciones anteriores, combos, cambios de estrategia) y consultas de predicción con información accesible. No compartir memoria mutable entre batallas. Los perfiles genéricos serán agresivo, defensivo, equilibrado, conservador, oportunista y un perfil aleatorio opcional propuesto previamente; este último no es necesario en la primera implementación por la preferencia de evitar azar estratégico. Permitir comparar perfiles sin coste en PC.

### 10.2 Información y predicción

La IA conoce su estado propio y, inicialmente, solo el **estado actual** del oponente. No asumir acceso total a habilidades ocultas, estadísticas completas, cooldowns, variables internas ni estrategia enemiga. La interpretación inicial propuesta limita la vista del rival a HP, recursos, iniciativa y efectos observables; la lista exacta de campos visibles debe confirmarse o configurarse. Puede conservar información observada mediante su memoria, pero no leer el historial interno privilegiado.

Proporcionar estimaciones de daño, probabilidad de acertar, curación efectiva, potencial letal, aplicación de estados, eficacia elemental, mitigación, tiempo hasta siguiente turno y reacciones previsibles en la medida en que la información visible lo permita. Admitir predicción hipotética más avanzada si puede aislarse. No filtrar valores ocultos a través de consultas exactas; devolver estimaciones, rangos o desconocido cuando sea necesario. No conocer ni consumir las próximas tiradas RNG reales, ni modificar el estado real al predecir.

### 10.3 Ciclo de decisión

1. Construir una vista de solo lectura del combate y memoria disponible.
2. Evaluar la estrategia y condiciones, y obtener candidatos/objetivos posibles.
3. Filtrar o puntuar candidatos con las herramientas de consulta y predicción.
4. Proponer acción y objetivo, o rechazo/espera.
5. El motor revalida la propuesta y resuelve la acción; la IA nunca cambia el combate directamente.
6. Actualizar memoria según acontecimientos observables y registrar la decisión, regla utilizada, prioridades, candidatos relevantes y motivos de descarte cuando sea posible.

Si la IA falla o ninguna acción es legal, aplicar política documentada de fallback (espera o error controlado); no ejecutar automáticamente una capacidad de la que el PJ carezca. Mantener límites de complejidad y seguridad también para la IA. Sus archivos son independientes, reutilizables, versionados y compatibles con los perfiles de habilidades del PJ; usar identificadores estables y validar referencias.

## 11. Formatos de contenido, importación y biblioteca

**Confirmado:** personajes creados fuera del programa y distribuidos como paquetes estructurados con múltiples archivos. Los esquemas deben poder interpretarse por una IA externa y ser fáciles de inspeccionar. La extensión y nombres exactos son propuestas.

```text
example_character/
  manifest.json       # Identidad, versión, esquema, dependencias
  character.json      # Stats, referencias, configuración, tags
  abilities.json      # Habilidades propias o referencias
  artifact.json       # Opcional, un único artefacto
  resources.json      # Recursos personalizados
  effects.json        # Efectos y estados propios
  ai.json             # Estrategia o referencia a una versión de IA
  summons.json        # Opcional, entidades auxiliares
  scripts/           # Código aislado; no scripts de host sin restricciones
  assets/            # Retrato, iconos y recursos gráficos admitidos
  README.md          # Descripción humana opcional
```

Propuesta: carpeta o ZIP de intercambio, JSON UTF-8 como formato principal y MD para documentación. Soportar importación de cada tipo de componente de forma independiente. Definir esquemas canónicos y validador con errores claros por archivo y ruta de propiedad. No prometer compatibilidad con todos los JSON/XML de juegos ajenos: una IA externa debe convertirlos al esquema propio.

Ejemplo ilustrativo de una habilidad declarativa (no contrato definitivo ni fórmula de coste):

```json
{
  "id": "fireball",
  "name": "Bola de fuego",
  "action_type": "main",
  "cost": {"mana": 20},
  "effects": [
    {"type": "damage", "damage_type": "magical", "element": "fire", "formula": "caster.MAG * 1.5"},
    {"type": "apply_status", "status": "burn", "chance": 0.30, "duration": 3, "duration_type": "target_turns"}
  ]
}
```

Las expresiones se interpretan mediante una gramática segura limitada, nunca mediante `eval` de código anfitrión. Definir IDs/namespaces, versiones y reglas de migración. No cargar archivos fuera de la raíz del paquete; defender contra rutas relativas peligrosas, archivos comprimidos enormes, referencias cíclicas no permitidas y recursos no compatibles. Validar antes de incorporar el paquete a la biblioteca. No ejecutar scripts durante la mera importación.

### 11.1 Biblioteca persistente

Secciones para personajes, habilidades, artefactos, efectos/estados, IA, reglamentos, perfiles de equilibrio, configuraciones de simulación, combates e informes. Conservar diferentes versiones de todos los componentes. Importar una actualización como versión nueva o manejar colisiones explícitamente; no sobrescribir contenido necesario para reproducir batallas antiguas.

Identidades y dependencias versionadas; guardar una copia inmutable o referencias verificables a versiones exactas. Propuesta: hashes de contenido, esquema de manifiesto, índice local y exportaciones portables. Usar almacenamiento de usuario compatible con ambas plataformas; respetar el acceso a archivos permitido por Android.

## 12. Simulación individual y condiciones de finalización

### 12.1 Configuración inicial

Seleccionar PJ y versiones, IA, reglamento global, perfil de equilibrio, modo libre/reglamentado y semilla. Por defecto, vida máxima, iniciativa cero y recursos personalizados en sus valores iniciales. Permitir configurar estados iniciales alternativos para reproducir situaciones concretas. Las diferencias en la configuración inicial deberán quedar registradas.

### 12.2 Finalización

Victoria estándar: reducir HP enemigo a cero, después de resolver las excepciones de muerte correspondientes (prevención de muerte, resurrección, fases, etc.). También admitir condiciones alternativas de victoria/derrota configurables o definidas por mecánicas del PJ a través de la API.

Contemplar empate, muerte simultánea, ausencia de progreso, imposibilidad de actuar y condiciones terminales especiales. Límites configurables de tiempo virtual, turnos, acciones y estancamiento; al llegar al límite de combate aplicar empate o criterio de desempate del reglamento. Diferenciar este resultado del aborto técnico por error, cancelación del usuario o límite de seguridad del runtime. El rol de invocaciones vivas al morir su dueño y las prioridades entre condiciones de victoria simultáneas deben especificarse.

### 12.3 Reproducción visual

Interfaz abstracta con retratos, vida, iniciativa, recursos, estados, información de turnos y registro cronológico. Previsión de próximos turnos según estado ATB actual, indicando que puede cambiar si cambian las condiciones.

Controles: pausar/reanudar, avanzar por acciones o turnos, cambiar velocidad, resolver instantáneamente hasta el final, retroceder para inspeccionar estados anteriores, reproducir batalla guardada y repetirla con la misma semilla. Inspeccionar un evento para consultar decisiones, fórmulas, tiradas y modificadores.

Propuesta: el visor recorre eventos y snapshots/checkpoints, o reconstruye estados de forma determinista. No confundir inspección hacia atrás con modificación de la partida real. La UI no debe ejecutar reglas de combate propias.

## 13. Simulaciones masivas y análisis

Ejecutar N combates automáticos sin renderizado (por ejemplo, 100, 1000, 10000, sin fijar aún máximo de hardware). Modalidades confirmadas:

- Repetición de duelo A vs B.
- Todos contra todos en forma de torneo de duelos 1v1 (no combate simultáneo multijugador).
- PJ de prueba contra biblioteca de adversarios.
- Comparación de versiones de PJ/componentes.
- Comparación de perfiles de IA.
- Comparación de reglamentos globales.
- Variación controlada de parámetros (stats, configuraciones, etc.).

Propuesta: planificar cada trabajo con índice, configuración y semilla derivados determinísticamente de una semilla maestra; el resultado no debe depender del orden de ejecución ni de cantidad de workers. Permitir progreso, cancelación, concurrencia limitada y agregación incremental sin bloquear interfaz, especialmente en Android. Evitar ciclos de escenas o nodos por cada duelo. Guardar trazas completas de todos los combates opcionalmente, no como requisito de cada lote; conservar datos necesarios para reproducir los duelos concretos.

Estadísticas: victorias/derrotas/empates, porcentaje y denominador, errores por separado, daño y curación medios, duración media, medianas, distribuciones, variabilidad e intervalos de confianza, eficacia de habilidades, comparativas de enfrentamientos favorables/desfavorables y métricas personalizadas. Propuesta estadística: intervalos binomiales de Wilson para tasas individuales y metodología documentada para intervalos de otras métricas o resultados emparejados. No confundir correlación de uso de habilidad con causalidad de victoria. Mostrar tamaño de muestra y configuración del lote.

## 14. Informes y depuración

### 14.1 Informe individual

| Categoría | Datos mínimos |
|---|---|
| Resultado | Ganador/perdedor/empate, causa de victoria o terminación. |
| Duración | Tiempo ATB, turnos propios/globales, acciones y eventos. |
| Daño | Causado, recibido, mitigado, absorbido, tipo/elemento y fuente. |
| Curación | Generada, efectiva, recibida y desperdiciada (overheal). |
| Ataques | Impactos, fallos, críticos y esquivas, recuentos y tasas. |
| Habilidades | Usos, efectos, eficacia, gastos y contribución observada. |
| Recursos | Generación, consumo, pérdidas y desperdicio. |
| Estados | Aplicaciones, duración, acumulaciones, disipaciones, efecto. |
| Defensas | Escudos, bloqueos, paradas, inmunidades y mitigación. |
| IA | Decisiones, prioridades, motivos y candidatos relevantes. |
| Aleatoriedad | Tiradas, probabilidades y resultados. |
| Equilibrio | Coste y desglose de creación, discrepancias, perfil empleado. |
| Historial | Eventos cronológicos y relaciones causales; metadatos de versiones y semilla. |

Permitir métricas personalizadas definidas por contenido, con nombre, unidad, tipo, origen y reglas de agregación. Separar daño intentado, premitigación, daño efectivo y sobreexceso para evitar doble conteo. Cuando un efecto produce otros efectos, registrar su causalidad y definir atribución coherente.

### 14.2 Informe masivo y exportación

Gráficas, tablas, intervalos y comparaciones indicadas en la sección anterior. Los informes deben poder guardarse y consultarse desde la biblioteca. Tres formatos confirmados: **Markdown (.md), JSON (.json) y HTML (.html)**. No se exige CSV ni PDF.

Propuesta: generar los tres a partir de un mismo modelo versionado. Markdown legible para personas e IA; JSON estructurado para automatización; HTML autónomo con estilos y gráficas locales, sin CDN ni red. Escapar texto y datos importados para evitar inyección HTML. El modo masivo puede exportar resumen con referencias/semillas y no todos los eventos; el individual admite informe detallado.

### 14.3 Modo avanzado de depuración

Inspección completa del estado interno, variables de scripts, memoria de IA, cola de eventos, fórmulas intermedias, tiradas RNG, modificaciones de stats, resolución de puntos de creación y causas de validación. Los permisos del depurador son distintos de la vista limitada que recibe la IA y no deben filtrarse a ella. Filtros por entidad, evento, habilidad y cadena causal; mostrar diagnósticos claros para contenido inválido o abortos.

## 15. Determinismo, trazabilidad y rendimiento

Reproducibilidad: misma versión del motor y API, mismos contenidos y dependencias versionados, mismas reglas, configuración inicial y semilla => misma secuencia y resultado. Guardar versiones, identificadores/hashes, parámetros RNG y configuración. Las modificaciones de reglas o contenido no deben alterar informes históricos.

Propuestas técnicas: RNG de algoritmo explícito y estado serializable controlado por dominio; semillas de subflujos si se documentan; orden total estable de eventos; iteraciones canónicas cuando afecten al resultado; representación numérica determinista (p. ej. punto fijo decimal o similar si las pruebas muestran divergencias). No prometer determinismo exacto multiplataforma sin comprobarlo; tratarlo como objetivo técnico y registrar incompatibilidad si aparece. Semilla igual no garantiza el mismo resultado al cambiar las reglas.

Separar estado runtime de datos inmutables. Evitar operaciones innecesarias y registro completo en lotes. Mantener modos de traza reducida/completa que no cambien el resultado de la batalla. Medir rendimiento real en PC y Android con escenarios sencillos, efectos complejos e invocaciones. No fijar ahora límites de tiempo por combate ni objetivos de throughput sin medir hardware. Límites técnicos configurados con máximos seguros y jamás desactivables por contenido importado.

## 16. Interfaz y navegación

Pantallas principales confirmadas o derivadas del alcance: biblioteca de contenido, importación/validación y detalle de PJ, configuración de duelo, visor de batalla, configuración y ejecución masiva, informes, reglamentos/equilibrio, depuración y ajustes.

Propuesta visual: UI 2D abstracta y adaptable a tamaño de pantalla, con controles táctiles en Android y teclado/ratón en PC. Mostrar coste calculado, presupuesto, advertencias, versiones y validación antes del combate. Presentar claramente modo libre vs reglamentado. Navegación y filtros, búsqueda y selección de versiones; retrato opcional con sustituto gráfico. Traducir interfaz mediante recursos de localización, no mediante IDs cambiantes en archivos. Español inicial, IDs técnicos en inglés.

## 17. Tecnología y estructura del repositorio

### 17.1 Requisitos tecnológicos confirmados

- Godot es obligatorio como motor general de aplicación.
- Herramientas y dependencias gratuitas. Preferir software libre/código abierto, con licencias compatibles y sin servicios obligatorios de pago. Verificar licencias y atribuciones de terceros, activos gráficos incluidos.
- La IA desarrolladora puede elegir el resto de tecnología con justificación; debe ser compatible con ambos destinos, ejecución offline y motor sin gráficos.

**Propuesta inicial:** Godot 4.x estable, fijar versión exacta al comenzar; GDScript tipado para aplicación y núcleo inicial, JSON para intercambio, almacenamiento local (archivos versionados e índice; base de datos gratuita solo si es necesaria), pruebas automatizadas ejecutables headless en PC. Evaluar alternativas únicamente si mediciones o requisitos técnicos lo justifican. No usar el lenguaje de host sin protección para extensiones de terceros. Probar exportación a Android desde las primeras fases, aunque la interfaz final llegue tarde.

Referencias oficiales para el desarrollo (consultadas durante el cierre del diseño):

- Godot, uso de línea de comandos y modo headless: https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html
- Godot, exportación Android: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html
- Godot, características: https://docs.godotengine.org/en/stable/about/list_of_features.html

El requisito de gratuidad se aplica al desarrollo y al funcionamiento del producto. No se ha acordado publicar en tiendas; si se decidiera hacerlo, comprobar costes y condiciones de distribución por separado. No introducir una cuota de tienda en el alcance inicial.

### 17.2 Módulos y contratos sugeridos

```text
project.godot
src/
  domain/          # Modelos, IDs, datos inmutables y estado runtime
  combat/          # ATB, turnos, pipeline, RNG, victoria
  events/          # Cola, interceptores y despacho determinista
  effects/         # Operaciones, estados, stats y recursos
  scripting/       # Intérprete seguro y API versionada
  ai/              # Vista limitada, estrategias, predicción
  balance/         # Cálculo de PC y validación reglamentaria
  content/         # Esquemas, carga, referencias, importación
  simulation/      # Simulación individual, lotes y planificación
  analytics/       # Agregación y estadísticas
  reports/         # Modelo y exportadores MD/JSON/HTML
  storage/         # Índices, persistencia, historial y versiones
  application/     # Casos de uso y coordinación
  ui/              # Escenas y vistas Godot
content/           # Fixtures, perfiles y personajes de ejemplo
schemas/           # Esquemas públicos versionados
docs/              # Referencia humana y para IA
tests/             # Pruebas unitarias, integración, regresión
```

El núcleo depende únicamente de contratos de dominio, sin acoplarse a escenas. La aplicación coordina y la UI consume resultados. Invertir dependencias para almacenamiento y logs. La simulación masiva utiliza el mismo motor que el combate individual. Cada módulo del repositorio debe documentar entradas, salidas y errores. Las funciones concretas no quedan fijadas por este documento.

## 18. Hoja de ruta de implementación (orden aceptado)

| Fase | Entrega verificable | Criterio para avanzar |
|---|---|---|
| 1. Núcleo | Motor headless, reloj ATB, stats, dos entidades de prueba, acción básica/espera, daño, RNG y victoria. | Reproducción determinista y pruebas matemáticas. |
| 2. Contenido | Paquetes, esquemas, dependencias y validación. | Importar dos PJ externos y rechazar paquetes inválidos. |
| 3. Habilidades y eventos | Operaciones, reacciones, estados, recursos y artefacto; ampliar gradualmente a invocaciones, formas y temporalidad. | Casos de prueba combinados con trazabilidad y límites. |
| 4. IA | Estrategias declarativas, estado, memoria, predicción y reacciones. | Comparar estrategias intercambiables y comprobar privacidad de la vista. |
| 5. Scripts | Runtime aislado, API de dominio y scripts de IA/efectos. | Mecánicas nuevas sin modificar motor; pruebas de aislamiento y límites. |
| 6. Equilibrio | Motor de fórmulas de valoración, presupuestos y modos libre/reglamentado. | Costes automáticos trazables para perfil de prueba y no evaluables detectados. |
| 7. Simulaciones | Control individual sin UI final, lotes y variaciones de escenarios. | Resultados coherentes entre modos, cancelación y rendimiento medido. |
| 8. Informes | Métricas, agregaciones y exportadores MD/JSON/HTML. | Datos consistentes y reproducibles desde los informes. |
| 9. UI y biblioteca | Interfaz abstracta, almacenamiento, reproducción, importación, depurador e informes. | Flujo completo importación → duelo/lote → informe usable. |
| 10. Plataformas | Pruebas finales, optimización, exportación PC/Android, documentación y distribución local. | Prueba real en ambos destinos, offline y sin dependencias de pago. |

El orden es conceptual: realizar verificaciones de compatibilidad móvil, determinismo, seguridad y diseño de interfaces de módulo desde el inicio. No dejar todo el riesgo para la última fase. Las pruebas y documentación son transversales. Habilidades avanzadas, scripts y análisis masivos pueden necesitar iteraciones internas.

El diseño concreto de tablas de coste y perfil de equilibrio definitivo es un trabajo separado: definir y probar el intérprete con un perfil técnico ilustrativo, luego crear fórmulas reales y ajustarlas con simulaciones; no bloquear el núcleo hasta disponer del equilibrio final. Etiquetar los informes de prueba como tales.

## 19. Pruebas y criterios de aceptación globales

Como mínimo, incluir pruebas reproducibles de:

1. Fórmulas de defensa (200 contra DEF 100 = 100 antes de otros modificadores), daño mágico y verdadero, ACC−EVA con límites, críticos autorizados y curación recibida.
2. ATB con SPD distintas, exceso de iniciativa, cambios de velocidad, empates, ganancia instantánea, canalización e iniciativa suspendida.
3. Acción principal, gratuitas y reacciones limitadas por cooldown, usos y procs; PJ sin ataque básico y espera como opción.
4. Daño mixto, resistencias, vulnerabilidades, inmunidad, absorción, escudos, penetración y orden de resolución reproducible.
5. Todas las unidades de duración y políticas de reaplicación; eventos de expiración, disipación, copia, transferencia y suspensión.
6. Transformaciones con cambio de IA, recursos y capacidades; invocaciones simples y completas; etiquetas y filtros.
7. Interceptores, cancelación y modificación de acontecimientos, daño retrasado, restauración temporal parcial y causalidad.
8. Prevención de muerte, efectos posteriores, resurrecciones, victoria alternativa, empate y estancamiento; ausencia de loop infinito.
9. Validez de paquetes, versiones, dependencias faltantes, rutas maliciosas, esquemas incorrectos y errores informativos.
10. Código externo limitado: bucle, memoria, llamadas prohibidas, acceso a recursos del sistema, mutaciones indebidas de IA y seguridad de importación.
11. IA intercambiable, gestión de reacciones, memoria aislada, predicción sin alterar estado/RNG y pruebas contra filtración de datos ocultos.
12. Costes automáticos, stats base gratis, descuentos y desventajas, sin recargo de sinergias, IA gratuita, referencias no duplicadas, scripts no evaluables, ambos modos.
13. Repetición de la misma semilla, compatibilidad de versiones y paridad entre motor individual/masivo y diferentes niveles de traza.
14. Agregación de resultados, denominadores y errores, métricas personalizadas, comparación de lotes e informe en los tres formatos.
15. Reproducción hacia delante/atrás, persistencia de historial, uso offline, importación/exportación real y UI táctil en Android.

Propuesta de fixtures: dos atacantes simples; defensor con escudo; PJ de procs; invocador con mascota; personaje que se transforma; personaje temporal con script; personaje incapaz de infligir daño; pareja con muerte simultánea; scripts inválidos; y dos IA distintas del mismo PJ. Los fixtures no son personajes canónicos ni constituyen un perfil de equilibrio definitivo.

## 20. Documentación para la IA creadora de contenido

Además de mantener actualizado este `PROJECT.md`, el proyecto debe generar documentación de referencia basada en las capacidades **realmente implementadas**, no en operaciones todavía inexistentes. Estructura propuesta:

| Archivo | Contenido |
|---|---|
| `ARCHITECTURE.md` | Módulos, contratos, dependencias y ejecución. |
| `COMBAT_RULES.md` | Reglamento, tiempo, turnos, pipeline, fórmulas y casos límite. |
| `CHARACTER_CREATION.md` | Cómo crear/importar un PJ válido con ejemplos completos. |
| `ABILITY_REFERENCE.md` | Catálogo de operaciones, condiciones, duraciones, eventos y parámetros. |
| `SCRIPTING_API.md` | Lenguaje admitido, permisos, API, límites, contratos de coste y ejemplos. |
| `AI_REFERENCE.md` | Modelos, vistas, memoria, predicción, reacciones y estrategias. |
| `BALANCE_RULES.md` | Perfil de equilibrio, presupuesto, valores y cálculo de coste. |
| `DATA_SCHEMAS.md` | Manifiestos, esquemas, versiones y referencias. |
| `REPORTS.md` | Métricas, formatos, metadatos, trazas y agregación. |
| `TESTING.md` | Comandos, fixtures y criterios de aceptación. |
| `ROADMAP.md` | Estado de fases, pendientes y limitaciones conocidas. |

Incluir ejemplos funcionales y validados de extremo a extremo, mensajes de errores, instrucciones para una IA externa y reglas para no inventar operaciones o campos inexistentes. El esquema ejecutable y la documentación humana deben mantenerse sincronizados con pruebas.

## 21. Decisiones abiertas que no deben confundirse con requisitos acordados

- Nombre comercial del proyecto, estética final y versión concreta de Godot; SO de PC prioritarios y requisitos mínimos de dispositivos.
- Lenguaje/intérprete aislado para contenido, esquema final, formato exacto del paquete, almacenamiento y estrategia de versiones/migración.
- Orden exacto de resolución, coste y devolución en interrupciones, tiradas por componente/multigolpe, empates ATB, dominios numéricos y redondeo, SPD no positiva y límites de probabilidad.
- Fórmula de ataque básico, curación en casos especiales, combinación de afinidades/resistencias, penetración y orden de defensas.
- Catálogo inicial concreto de elementos/estados y sus parámetros; multiplicadores críticos no relacionados con daño.
- Campos visibles exactos del oponente, alcance de predicción y comportamiento de fallo de IA; el perfil aleatorio no es prioritario.
- Políticas de invocaciones, muerte simultánea, restauración temporal y condiciones alternativas de victoria; límites técnicos y criterios de estancamiento.
- Presupuesto definitivo, ecuaciones de coste, descuentos, devolución de PC y reglas verificables para scripts no declarativos. No fijar cifras inventadas de costes como definitivas.
- Rendimiento objetivo por dispositivo, tamaño máximo de lotes y política de retención de trazas/snapshots.

Cuando una decisión pendiente sea necesaria para una fase, proponer el valor inicial más simple que respete los requisitos, externalizarlo si corresponde y documentar el motivo. Las decisiones de equilibrio de fondo deben poder revisarse de forma independiente.

## 22. Instrucción inicial para la IA implementadora

> Utiliza este `PROJECT.md` como especificación maestra. Crea un proyecto nuevo en Godot con herramientas gratuitas y una arquitectura independiente de la interfaz. Comienza exclusivamente por la fase 1 de la hoja de ruta. Presenta la estructura técnica, los contratos y las decisiones mínimas pendientes que resuelvas provisionalmente. Implementa el núcleo ATB reproducible y pruebas automatizadas ejecutables en modo headless. Crea fixtures sencillos, registra las limitaciones y documenta cómo ejecutar las pruebas. No adelantes una UI compleja, integración generativa o reglas definitivas de equilibrio. Conserva la capacidad de evolucionar hacia las demás fases descritas. Antes de declarar una fase completa, ejecuta las pruebas y distingue lo verificado de lo pendiente. Mantén los requisitos confirmados, justifica cambios técnicos y actualiza la documentación para que futuras IAs puedan crear contenido válido sin inventar APIs.

## 23. Estado de implementación (mantenido por la IA implementadora)

> Sección añadida durante el desarrollo. **No modifica** los requisitos confirmados de las secciones 0–22: solo registra el estado real y las decisiones tomadas. Última actualización: 2026-11-20 (fase 10).

### 23.1 Estado por fase (hoja de ruta de la sección 18)

| Fase | Estado | Evidencia |
|---|---|---|
| 1. Núcleo | **Completada y verificada** | 125 casos / ~9 600 aserciones OK (`tools/run_tests.sh`); duelo de referencia reproducible entre procesos (`tests/golden`) |
| 2. Contenido | **Completada y verificada** | 165 casos / ~9 850 aserciones OK; 2 PJ externos importados y enfrentados; paquetes inválidos rechazados (`docs/PACKAGES.md`, `schemas/`) |
| 3. Habilidades y eventos | **Completada y cerrada** | 279 casos / ~14 200 aserciones OK; estados, duraciones, restricciones, defensas, reacciones, canalización, invocaciones, formas, temporalidad (`docs/ABILITY_REFERENCE.md`, `docs/EVENTS.md`) |
| 4. IA | **Completada y verificada** | 310 casos / ~14 750 aserciones OK; estrategias `priority_list`/`scored`/`state_machine`/`behavior_tree`, memoria observable, predicción con rango, política de reacciones, 6 perfiles genéricos (`docs/AI_REFERENCE.md`) |
| 5. Scripts | **Completada y verificada** | 339 casos OK; SimScript v1 aislado (compilador + intérprete con presupuesto + API versionada de lista permitida), operación `script`, IA `script`, `scripts/*.sim` en paquetes de personaje (`docs/SCRIPTING_API.md`) |
| 6. Equilibrio | **Completada y verificada** | 367 casos OK; valorador automático/trazable (`BalanceEvaluator`), perfil de costes de PRUEBA (`reference_costs`), modos libre/reglamentado, contratos de script (`docs/BALANCE_RULES.md`) |
| 7. Simulaciones | **Completada y verificada** | 385 casos OK; sesión individual controlable, lotes (7 modalidades) con semillas derivadas, hilos, cancelación, reproducción y agregación incremental (`docs/SIMULATION.md`) |
| 8. Informes | **Completada y verificada** | 408 casos OK; informes individual y masivo (`simhalla.report/1`) en JSON/MD/HTML, estadística documentada (Wilson, Newcombe, t), verificador y depurador (`docs/REPORTS.md`) |
| 9. UI y biblioteca | **Completada y verificada en headless** | 434 casos OK; almacenamiento versionado con combates reproducibles y bundles portables, modelos de aplicación, interfaz Godot adaptable y localizada, flujo completo automatizado (`docs/UI.md`); sin prueba visual/dispositivo |
| 10. Plataformas | **Completada salvo verificación en dispositivo** | 445 casos OK; exportados Linux (autoprueba OK en directorio vacío) y APK arm64 firmado sin permisos; batería de conformidad `PlatformCheck`, selector de archivos, ejemplos incluidos (`docs/PLATFORMS.md`); **Android sin ejecutar en dispositivo y determinismo PC↔Android sin verificar** |

### 23.2 Decisiones abiertas de la sección 21 resueltas (provisionalmente)

- **Versión de Godot:** 4.7.2 stable. Lenguaje del núcleo: GDScript tipado. Pruebas headless con marco propio (sin dependencias).
- **Numérico/determinismo:** tiempo e iniciativa enteros en microunidades; RNG SplitMix64 propio con flujos con nombre; huella SHA-256 del registro de eventos.
- **Reglamento técnico inicial** (orden de resolución, empates ATB, SPD no positiva, tiradas por acción, redondeo, penetración, límites de probabilidad, muerte simultánea, límites de combate, ataque básico físico `caster.ATK`, vista de IA): ver `docs/COMBAT_RULES.md` y `docs/DECISIONS.md` (D-008…D-020). Todas son **provisionales** y están externalizadas en `content/rulesets/default_ruleset.json`.
- **Fase 2:** formato de paquete (carpeta/ZIP, `manifest.json`, tipos `character|abilities|ai`), esquemas públicos `/1` en `schemas/`, IDs `namespace/nombre`, semver con restricciones, biblioteca de versiones inmutables con huella y comprobación de integridad (D-030…D-038). `effects.json`, `summons.json` y `scripts/` se rechazan hasta sus fases.
- **Fase 3:** estados como datos con 7 políticas de reaplicación y duraciones en 6 unidades; restricciones de uso (cooldown, usos, cargas, `requires`); defensas nativas; reacciones/automáticas/pasivas por eventos; canalización; invocaciones; formas (estados con bloque `form`); guardar/restaurar, efectos retrasados, repetir/copiar; eventos y métricas de usuario (D-039…D-050; convenciones provisionales en `docs/COMBAT_RULES.md` §11). Cierre de la fase 3 (D-051…D-058): invertir/propagar estados, suspender efectos y cooldowns, restaurar estados, artefacto completo, selectores deterministas y catálogo elemental validado; "reservar" como patrón (la decisión es de la IA, fase 4).
- **Fase 4:** IA declarativa híbrida (prioridades, puntuaciones, máquina de estados, árboles de comportamiento), memoria solo con hechos observables y reiniciada por combate, predicción como estimación con rango (mitigación solo observada), política de reacciones por IA (`reaction_declined`), perfiles genéricos; motor 0.3.0 (D-059…D-064). Lista exacta de campos visibles y pesos de perfiles siguen provisionales.
- **Fase 5:** lenguaje propio «SimScript v1» (D-068…D-075) con API versionada de lista permitida, límites `scripting.*` con techos duros, errores de efecto = aborto con diagnóstico y de IA = fallback, scripts solo compilados al importar, marcados como no evaluables (valoración: fase 6); motor 0.4.0.
- **Fase 6:** valoración automática de PC según perfiles externos (D-076…D-085): costes como fórmulas de la gramática segura sobre hechos nombrados, créditos automáticos con tope, IA/ataque básico gratuitos, referencias no duplicadas, no evaluables sin precio, scripts con contrato verificable, modos libre/reglamentado; cifras del perfil **ilustrativas**; motor 0.5.0.
- **Fase 7:** simulación individual y por lotes sobre el mismo motor (D-086…D-092): semillas derivadas de la maestra independientes de orden/workers, hilos con aislamiento por trabajo, cancelación que no cuenta como resultado, agregación incremental mínima (la estadística inferencial es de la fase 8); rendimiento medido en PC (sin Android).
- **Fase 8:** modelo de informe versionado con tres formatos derivados, estadística documentada (D-093…D-100), verificación de coherencia y reproducibilidad, HTML autónomo con escape total, depurador separado de la IA; persistencia de informes: fase 9.
- **Fase 9:** tres capas (almacenamiento / aplicación / interfaz) con combates guardados fijados y reproducibles, versiones inmutables, colisiones explícitas, borrado protegido, bundles portables, UI Godot adaptable es/en (D-101…D-110); interfaz verificada solo en headless.
- **Resolución de la §21 (revisión 2026-11-21):** catálogo elemental (D-057, `elements` del reglamento), estados nativos (fase 3.1), invocaciones (D-047), restauración de estados (D-055), muerte simultánea/estancamiento/límites (`COMBAT_RULES.md`), tamaño máximo de lotes (`BatchPlan.MAX_JOBS`/`MAX_SCENARIOS`) y retención de trazas (D-090: registros compactos + reproducción por plan y semilla; `keep_traces` opcional) están resueltos de forma **provisional y revisable**. **Rendimiento objetivo**: fijado provisionalmente y externalizado en `content/conformance/targets.json` (D-116).
- **Sigue abierto (por mandato de §21):** presupuesto definitivo, ecuaciones de coste, descuentos y devolución de PC: **no se fijan cifras inventadas**; el perfil `reference_costs` sigue siendo ILUSTRATIVO y es el **valor por defecto provisional** (D-117, D-119). Existe un **calibrador empírico** (`BalanceCalibrator`, D-118; sección propia en Reglas y equilibrio) que propone perfiles ilustrativos a partir de torneos; falta calibrar con contenido real. También: migraciones reales (no hay aún un `/2`), medición en dispositivo y política de snapshots.

### 23.3 Documentación técnica generada

`README.md`, `docs/EVENTS.md`, `docs/PACKAGES.md`, `schemas/README.md`, `docs/ARCHITECTURE.md`, `docs/COMBAT_RULES.md`, `docs/DECISIONS.md`, `docs/DATA_SCHEMAS.md`, `docs/CHARACTER_CREATION.md`, `docs/ABILITY_REFERENCE.md`, `docs/AI_REFERENCE.md`, `docs/TESTING.md`, `docs/ROADMAP.md`; `docs/BALANCE_RULES.md`, `docs/SCRIPTING_API.md` y `docs/REPORTS.md` existen como marcadores "no implementado". Regla del proyecto: la documentación solo describe capacidades realmente implementadas.

### 23.4 Limitaciones conocidas (resumen; detalle en `docs/ROADMAP.md`)

Determinismo PC↔Android sin verificar; APK de Android exportado pero no ejecutado en dispositivo; rendimiento medido (≈ 33 duelos/s en traza reducida) sin objetivo fijado; cooldowns, estados, reacciones reales, artefacto, transformaciones, invocación dinámica, escudos/absorción y restauración temporal pendientes de la fase 3.

### 23.5 Registro de cambios

| Fecha | Cambio |
|---|---|
| 2026-11-21 | Historial/exportación de biblioteca, migraciones de esquema (`SchemaMigrator`), objetivos de rendimiento provisionales (`targets.json`) y calibrador empírico de costes (`BalanceCalibrator`, `tools/calibrate_tool.gd`); 470 casos OK; pantalla de calibración, auditoría de maquetación móvil (D-120: la navegación pedía 585 px a 360 px) y corrección de bundles (orden de importación y dependencias transitivas, D-122); la batería de plataforma incluye un flujo de aplicación completo. |
| 2026-11-20 | Fase 10: `PlatformCheck` + pantalla Plataforma + `--selftest`, `FilePicker` (nativo/diálogo/bandeja), ejemplos incluidos, presets Linux/Android, scripts de compilación y verificación, `docs/PLATFORMS.md`, `docs/LICENSES.md`, pruebas `test_platform.gd` (445 casos). Android no ejecutado en dispositivo. |
| 2026-11-20 | Fase 9 completada: `AppStorage`/`VersionedStore`/`RecordStore`/`BundleIO`, `AppController` y modelos de aplicación, interfaz `MainUI` con 9 pantallas y widgets, `LocaleService` (es/en), retratos, `ruleset_data`/`profile_data`/`data`/`hash` en `DuelRunner`, `BatchResult.to_storable`; 26 pruebas nuevas (434 en total). |
| 2026-11-20 | Fase 8 completada: `Stats`, `IndividualReport`, `BatchReport`, `ReportDocument`/`MarkdownRenderer`/`HtmlRenderer`, `ReportExporter`, `ReportVerifier`, `DebugInspector`, estadísticas por habilidad en `CombatStats`, esquema `report.schema.json`, CLI `report_tool`; 23 pruebas nuevas (408 en total). |
| 2026-11-20 | Fase 7 completada: `SimulationSession`, `BatchPlan`/`BatchModes`/`BatchRunner`/`BatchAccumulator`/`BatchResult`, `patch` y `ruleset_overrides` en `DuelRunner`, esquema `batch.schema.json`, CLI `batch_tool`, plan de ejemplo `content/batches/demo_duel.json`; 18 pruebas nuevas (385 en total). |
| 2026-11-20 | Fase 6 completada: `BalanceEvaluator`/`BalanceReport`/`CostRules`, perfil de PRUEBA `reference_costs` + esquema `balance.schema.json`, modos libre/reglamentado, contratos de script (`max_damage`/`max_heal`) con cumplimiento en el motor, integración en importador y `DuelRunner`, CLI `balance_tool`, motor 0.5.0 (golden regenerado: solo versión/huella); 28 pruebas nuevas (367 en total). |
| 2026-11-20 | Fase 5 completada: SimScript v1 (`src/scripting`), operación `script`, IA `script`, `scripts/*.sim` en personajes, límites `scripting.*`, evento `script_run`, `get_error()`, paquete de ejemplo `rune_caster`, motor 0.4.0 (golden regenerado: solo versión/huellas); 29 pruebas nuevas (339 en total). |
| 2026-11-20 | Fase 4 completada: `ScoredAI`, `StateMachineAI`, condiciones de memoria/objetivo/predicción, `AIMemory`, `AIPredictor`, política de reacciones, paquete `ai_profiles`, esquema común ampliado, motor 0.3.0 (golden regenerado: solo versión/huella); 24 pruebas nuevas (303 en total); ampliada después con árboles de comportamiento, `OverlayAI` para `ai_rules` del artefacto y `time_to_turn`/`reactions_seen` declarativos (310 en total). |
| 2026-11-20 | Cierre de la fase 3: inversión y propagación de estados, suspensión de efectos/cooldowns, restauración de estados, artefacto con recursos/estados/invocaciones/reglas de IA, selectores `on` deterministas, catálogo elemental validado, `on_death`; 22 pruebas nuevas (279 en total). |
| 2026-11-20 | Fase 3 completada: estados/duraciones/políticas, restricciones de uso, defensas nativas, reacciones y automáticas, canalización, invocaciones, formas, temporalidad, eventos y métricas de usuario, 20 operaciones, paquetes con `effects.json`/`summons.json`; corrección de fuga de memoria (`dispose()`); motor 0.2.0; 92 pruebas nuevas (257 en total). Pendientes de la fase 3 en `docs/ROADMAP.md`. |
| 2026-11-20 | Fase 2 completada: paquetes de contenido (carpeta/ZIP), esquemas públicos, validación en capas, dependencias y versiones, biblioteca inmutable con huella, artefacto, CLI `package_tool`, 40 pruebas nuevas (165 en total). |
| 2026-11-20 | Fase 1 completada: núcleo ATB headless, reglamento por defecto, daño/curación, eventos interceptables, IA por prioridades, `DuelRunner`, 125 pruebas, documentación técnica. |

---
Fin del documento maestro. Esta especificación es de diseño inicial: no implica que el motor, las fórmulas finales de equilibrio o los esquemas estén ya implementados.
