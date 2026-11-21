class_name Stats
extends RefCounted
## Estadistica descriptiva e inferencial de los informes. Funciones puras y deterministas (sin azar).
##
## Metodologia (documentada en docs/REPORTS.md):
##  - Tasas (victorias, empates, uso...): intervalo binomial de WILSON al 95 % (z = 1,959964).
##  - Diferencia de dos tasas independientes: intervalo de NEWCOMBE (metodo hibrido de puntuacion, combina los de Wilson).
##  - Resultados EMPAREJADOS (misma semilla en ambas variantes): diferencias por pareja d_i = a_i - b_i; media y
##    intervalo t de Student al 95 % (valores criticos tabulados), mas el recuento de parejas discordantes.
##  - Media de una metrica: intervalo t de Student al 95 % sobre la media (valores criticos tabulados; normal para df > 120).
##  - Mediana y cuartiles: cuantiles de tipo 7 (interpolacion lineal). Distribuciones: histograma de clases iguales
##    entre minimo y maximo (determinista).
## Los intervalos son APROXIMADOS; con muestras muy pequenas son anchos o poco fiables y el informe muestra n siempre.

const Z95 := 1.959964
## t de Student bilateral al 95 % para df = 1..30
const T95 := [12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306, 2.262, 2.228, 2.201, 2.179, 2.160, 2.145, 2.131,
	2.120, 2.110, 2.101, 2.093, 2.086, 2.080, 2.074, 2.069, 2.064, 2.060, 2.056, 2.052, 2.048, 2.045, 2.042]


static func t_crit95(df: int) -> float:
	if df < 1:
		return INF
	if df <= 30:
		return T95[df - 1]
	if df <= 40:
		return 2.021
	if df <= 60:
		return 2.000
	if df <= 120:
		return 1.980
	return Z95


## Intervalo de Wilson: [lo, hi] para k exitos en n; n = 0 => null.
static func wilson(k: int, n: int, z: float = Z95) -> Variant:
	if n <= 0:
		return null
	var p := float(k) / float(n)
	var z2 := z * z
	var denom := 1.0 + z2 / float(n)
	var center := (p + z2 / (2.0 * float(n))) / denom
	var half := z * sqrt(p * (1.0 - p) / float(n) + z2 / (4.0 * float(n) * float(n))) / denom
	return [maxf(center - half, 0.0), minf(center + half, 1.0)]


## Newcombe (hibrido de puntuacion) para p1 - p2 independientes. {diff, lo, hi} o null.
static func newcombe_diff(k1: int, n1: int, k2: int, n2: int) -> Variant:
	if n1 <= 0 or n2 <= 0:
		return null
	var p1 := float(k1) / float(n1)
	var p2 := float(k2) / float(n2)
	var w1: Array = wilson(k1, n1)
	var w2: Array = wilson(k2, n2)
	var d := p1 - p2
	var lo := d - sqrt(pow(p1 - float(w1[0]), 2.0) + pow(float(w2[1]) - p2, 2.0))
	var hi := d + sqrt(pow(float(w1[1]) - p1, 2.0) + pow(p2 - float(w2[0]), 2.0))
	return {"diff": d, "lo": maxf(lo, -1.0), "hi": minf(hi, 1.0)}


static func mean(v: Array) -> float:
	if v.is_empty():
		return 0.0
	var s := 0.0
	for x in v:
		s += float(x)
	return s / float(v.size())


## Varianza muestral (n-1).
static func variance(v: Array) -> float:
	if v.size() < 2:
		return 0.0
	var m := mean(v)
	var s := 0.0
	for x in v:
		s += (float(x) - m) * (float(x) - m)
	return s / float(v.size() - 1)


static func sd(v: Array) -> float:
	return sqrt(variance(v))


## Cuantil tipo 7 (q en 0..1) de una lista (se ordena una copia).
static func quantile(v: Array, q: float) -> float:
	if v.is_empty():
		return 0.0
	var s: Array = v.duplicate()
	s.sort()
	var h := (float(s.size()) - 1.0) * clampf(q, 0.0, 1.0)
	var lo := int(floor(h))
	var hi := int(ceil(h))
	return float(s[lo]) + (h - float(lo)) * (float(s[hi]) - float(s[lo]))


## Resumen de una metrica: n, media, sd, error tipico, IC95 de la media, mediana, cuartiles, minimo y maximo.
static func summarize(v: Array) -> Dictionary:
	var n := v.size()
	if n == 0:
		return {"n": 0}
	var m := mean(v)
	var s := sd(v)
	var sem := s / sqrt(float(n)) if n > 1 else 0.0
	var half := t_crit95(n - 1) * sem if n > 1 else 0.0
	return {
		"n": n, "mean": m, "sd": s, "sem": sem, "ci95": [m - half, m + half] if n > 1 else null,
		"median": quantile(v, 0.5), "q1": quantile(v, 0.25), "q3": quantile(v, 0.75),
		"min": quantile(v, 0.0), "max": quantile(v, 1.0),
	}


## Histograma de `bins` clases iguales entre min y max: [{lo, hi, count}] (una sola clase si todos son iguales).
static func histogram(v: Array, bins: int = 10) -> Array:
	if v.is_empty():
		return []
	var lo := quantile(v, 0.0)
	var hi := quantile(v, 1.0)
	if is_equal_approx(lo, hi):
		return [{"lo": lo, "hi": hi, "count": v.size()}]
	var out: Array = []
	var w := (hi - lo) / float(bins)
	for i in bins:
		out.append({"lo": lo + w * float(i), "hi": lo + w * float(i + 1), "count": 0})
	for x in v:
		var idx := mini(int(floor((float(x) - lo) / w)), bins - 1)
		out[idx]["count"] += 1
	return out


## Comparacion EMPAREJADA de dos listas de resultados 0/1 (misma semilla por posicion).
## {n_pairs, mean_a, mean_b, diff, ci95 (t sobre las diferencias), a_only, b_only, both, neither}.
static func paired_binary(a: Array, b: Array) -> Dictionary:
	var n := mini(a.size(), b.size())
	var diffs: Array = []
	var a_only := 0
	var b_only := 0
	var both := 0
	var neither := 0
	var sa := 0.0
	var sb := 0.0
	for i in n:
		var x := int(a[i])
		var y := int(b[i])
		diffs.append(float(x - y))
		sa += float(x)
		sb += float(y)
		if x == 1 and y == 1:
			both += 1
		elif x == 1:
			a_only += 1
		elif y == 1:
			b_only += 1
		else:
			neither += 1
	var out := {"n_pairs": n, "a_only": a_only, "b_only": b_only, "both": both, "neither": neither}
	if n == 0:
		return out
	out["mean_a"] = sa / float(n)
	out["mean_b"] = sb / float(n)
	var d := mean(diffs)
	out["diff"] = d
	if n > 1:
		var half := t_crit95(n - 1) * sd(diffs) / sqrt(float(n))
		out["ci95"] = [d - half, d + half]
	else:
		out["ci95"] = null
	return out
