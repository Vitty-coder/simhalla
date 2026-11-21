# src/reports

**Estado: implementado (fase 8).** Ver `docs/REPORTS.md`.

`IndividualReport`, `BatchReport` (modelos `simhalla.report/1`), `ReportDocument` + `MarkdownRenderer`/`HtmlRenderer` (presentación), `ReportExporter` (JSON/MD/HTML, huella), `ReportVerifier`, `DebugInspector`.
**Entradas:** motor con traza completa o `BatchResult`. **Salidas:** modelo + archivos `.json/.md/.html`. **Errores:** informe individual sin traza completa ⇒ `{ok:false}`; nombres de archivo inválidos ⇒ error; discrepancias ⇒ listas del verificador.
