# src/storage

**Estado: implementado (fase 9).** Ver `docs/UI.md` §1.

`AppStorage` (secciones, ajustes, combates/lotes/informes guardados, referencias y borrado protegido), `VersionedStore` (elementos JSON versionados inmutables), `RecordStore` (registros con índice e historial), `BundleIO` (exportación/importación portable `.simbundle`).
**Entradas:** datos validados y registros. **Salidas:** copias con huellas verificadas. **Errores:** códigos `[colision]`, `[version_conflicto]`, `[integridad]`, `[referenciado]`, `[no_encontrado]`, `[nombre]`, `[escritura]`.
