# src/ui

**Estado: implementado (fase 9).** Ver `docs/UI.md`.

`MainUI` (`main.tscn`): navegación y diseño adaptable (barra lateral/inferior). `screens/`: Biblioteca, Importación, Duelo, Visor, Lotes, Informes, Reglas, Depuración, Ajustes (cada una `BaseScreen`). `widgets/`: `UIKit`, `ChartBars`, `ChartHist`, `ReportView`. `LocaleService`: localización por recursos.
**Entradas:** un `AppController`. **Salidas:** presentación y llamadas a los modelos de `src/application`; **no** ejecuta reglas de combate. **Errores:** los muestran los modelos (listas de errores/avisos); la UI no los oculta.
