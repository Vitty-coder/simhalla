class_name Rng
extends RefCounted
## Generador pseudoaleatorio determinista (SplitMix64) con estado serializable.
##
## Algoritmo explicito y propio (no usa RandomNumberGenerator de Godot) para
## garantizar la misma secuencia entre versiones del motor y plataformas.
## El estado completo es un unico entero de 64 bits (`state`).

const GAMMA := -7046029254386353131 # 0x9E3779B97F4A7C15
const MIX1 := -4658895280553007687 # 0xBF58476D1CE4E5B9
const MIX2 := -7723592293110705685 # 0x94D049BB133111EB
const MASK53 := 0x1FFFFFFFFFFFFF
const INV_2_53 := 1.0 / 9007199254740992.0

var state: int = 0


func _init(seed_value: int = 0) -> void:
	state = seed_value


## Mezcla de 64 bits (finalizador de SplitMix64). Desplazamientos logicos.
static func mix(value: int) -> int:
	var z: int = value
	z = (z ^ ((z >> 30) & 0x3FFFFFFFF)) * MIX1
	z = (z ^ ((z >> 27) & 0x1FFFFFFFFF)) * MIX2
	return z ^ ((z >> 31) & 0x1FFFFFFFF)


## Hash FNV-1a de 64 bits sobre los bytes UTF-8; estable entre plataformas.
static func fnv1a64(text: String) -> int:
	var h: int = -3750763034362895579 # 0xCBF29CE484222325
	for b in text.to_utf8_buffer():
		h = (h ^ b) * 1099511628211
	return h


func next_u64() -> int:
	state += GAMMA
	return mix(state)


## Flotante uniforme en [0, 1) con 53 bits de precision.
func next_float() -> float:
	return float((next_u64() >> 11) & MASK53) * INV_2_53


## Entero uniforme en [0, n). n debe ser > 0. Sesgo despreciable para n pequeno.
func next_int(n: int) -> int:
	assert(n > 0)
	return ((next_u64() >> 11) & MASK53) % n


func get_state() -> int:
	return state


func set_state(value: int) -> void:
	state = value
