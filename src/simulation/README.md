# src/simulation

**Estado: implementado (fase 7).** Ver `docs/SIMULATION.md`.

- `SimulationSession`: simulación individual controlable (pasos por acción/turno, pausa, instantánea, previsión, reconstrucción determinista hacia atrás).
- `BatchPlan` / `BatchModes`: planificación determinista (semillas derivadas de la maestra) y modalidades (duelo, torneo, biblioteca, versiones, IA, reglamentos, variación de parámetros).
- `BatchRunner` / `BatchResult` / `BatchAccumulator`: ejecución cooperativa o con hilos, cancelación, reproducción y agregación incremental.

**Entradas:** configuraciones de `DuelRunner` y planes `simhalla.batch/1`. **Salidas:** `CombatResult`, registros por trabajo, resumen agregado y huella. **Errores:** de preparación (`setup_error`), abortos técnicos (`aborted`) y cancelaciones (`cancelled`), siempre separados de victorias/derrotas/empates.
