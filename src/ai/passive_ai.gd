class_name PassiveAI
extends AIController
## IA que siempre espera (pasa el turno). Util como fixture y como fallback.

func ai_id() -> String:
	return "passive"


func decide(_view: Dictionary) -> AIDecision:
	return AIDecision.wait("passive")
