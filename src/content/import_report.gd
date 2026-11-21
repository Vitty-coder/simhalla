class_name ImportReport
extends RefCounted
## Resultado de validar/importar un paquete. Los errores llevan un codigo entre
## corchetes (p. ej. "[path_traversal]") y la ruta de archivo/propiedad.

var errors: Array[String] = []
var warnings: Array[String] = []
var id: String = ""
var version: String = ""
var type: String = ""
var hash: String = ""
var dependencies: Array = [] ## [{id, version, hash}] resueltas
var stored: bool = false
var balance: Dictionary = {} ## BalanceReport.to_dict() si se pidio valoracion (fase 6)
var already_present: bool = false


func ok() -> bool:
	return errors.is_empty()


func error(msg: String) -> void:
	errors.append(msg)


func summary() -> String:
	if ok():
		return "OK %s@%s (%s) hash=%s%s" % [id, version, type, hash.substr(0, 12), " [ya presente]" if already_present else (" [importado]" if stored else " [validado]")]
	return "RECHAZADO (%d errores):\n  - %s" % [errors.size(), "\n  - ".join(errors)]
