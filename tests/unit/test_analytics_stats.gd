extends TestCase
## Estadistica de los informes: Wilson, Newcombe, t de Student, cuantiles, histogramas y comparacion emparejada.

func test_wilson_interval_matches_reference_values() -> void:
	var w0: Array = Stats.wilson(0, 10)
	assert_almost(w0[0], 0.0, 1e-9)
	assert_almost(w0[1], 0.2775, 0.0005)
	var w5: Array = Stats.wilson(5, 10)
	assert_almost(w5[0], 0.2366, 0.0005)
	assert_almost(w5[1], 0.7634, 0.0005)
	var w10: Array = Stats.wilson(10, 10)
	assert_almost(w10[0], 0.7225, 0.0005)
	assert_almost(w10[1], 1.0, 1e-9)
	var w: Array = Stats.wilson(50, 100)
	assert_almost(w[0], 0.4038, 0.0005)
	assert_almost(w[1], 0.5962, 0.0005)
	assert_true(Stats.wilson(1, 0) == null, "n = 0: sin intervalo")
	for k in 21:
		var iv: Array = Stats.wilson(k, 20)
		assert_true(iv[0] >= 0.0 and iv[1] <= 1.0 and iv[0] <= float(k) / 20.0 and iv[1] >= float(k) / 20.0, "contiene la proporcion k=%d" % k)


func test_newcombe_difference_matches_published_example() -> void:
	# Newcombe (1998), 56/70 vs 48/80: diferencia 0,2000; IC95 (0,0524 ; 0,3339)
	var d: Dictionary = Stats.newcombe_diff(56, 70, 48, 80)
	assert_almost(d["diff"], 0.2, 1e-9)
	assert_almost(d["lo"], 0.0524, 0.002)
	assert_almost(d["hi"], 0.3339, 0.002)
	assert_true(Stats.newcombe_diff(1, 0, 1, 1) == null)
	var same: Dictionary = Stats.newcombe_diff(10, 20, 10, 20)
	assert_almost(same["diff"], 0.0)
	assert_true(same["lo"] < 0.0 and same["hi"] > 0.0, "sin diferencia: el intervalo contiene 0")


func test_descriptive_statistics_and_quantiles() -> void:
	var v := [1.0, 2.0, 3.0, 4.0]
	assert_almost(Stats.mean(v), 2.5)
	assert_almost(Stats.variance(v), 1.6666666667, 1e-9)
	assert_almost(Stats.quantile(v, 0.5), 2.5)
	assert_almost(Stats.quantile(v, 0.25), 1.75, 1e-9, "cuantil tipo 7")
	assert_almost(Stats.quantile(v, 0.0), 1.0)
	assert_almost(Stats.quantile(v, 1.0), 4.0)
	assert_almost(Stats.quantile([5.0], 0.3), 5.0)
	var s: Dictionary = Stats.summarize([2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0])
	assert_eq(s["n"], 8)
	assert_almost(s["mean"], 5.0)
	assert_almost(s["sd"], 2.13809, 1e-4)
	assert_almost(s["sem"], 2.13809 / sqrt(8.0), 1e-4)
	assert_almost(s["ci95"][0], 5.0 - 2.365 * s["sem"], 1e-3, "t(7) = 2,365")
	assert_almost(s["median"], 4.5)
	assert_eq(Stats.summarize([]), {"n": 0})
	assert_true(Stats.summarize([3.0])["ci95"] == null, "n = 1: sin intervalo")
	assert_almost(Stats.t_crit95(1), 12.706)
	assert_almost(Stats.t_crit95(30), 2.042)
	assert_almost(Stats.t_crit95(500), 1.959964)
	assert_true(Stats.t_crit95(0) == INF)


func test_histogram_is_deterministic_and_complete() -> void:
	var v: Array = []
	for i in 100:
		v.append(float(i))
	var h: Array = Stats.histogram(v, 10)
	assert_eq(h.size(), 10)
	var total := 0
	for b in h:
		total += int(b["count"])
	assert_eq(total, 100)
	assert_eq(h[0]["count"], 10)
	assert_eq(h[9]["count"], 10, "el maximo cae en la ultima clase")
	assert_eq(Stats.histogram([3.0, 3.0, 3.0], 10), [{"lo": 3.0, "hi": 3.0, "count": 3}])
	assert_eq(Stats.histogram([], 5), [])
	assert_eq(Stats.histogram(v, 10), h)


func test_paired_binary_comparison() -> void:
	var a := [1, 1, 0, 0, 1, 1, 0, 1]
	var b := [1, 0, 0, 1, 0, 1, 0, 0]
	var p: Dictionary = Stats.paired_binary(a, b)
	assert_eq(p["n_pairs"], 8)
	assert_eq(p["both"], 2)
	assert_eq(p["a_only"], 3)
	assert_eq(p["b_only"], 1)
	assert_eq(p["neither"], 2)
	assert_almost(p["diff"], 0.25)
	assert_almost(p["mean_a"], 5.0 / 8.0)
	assert_true(p["ci95"] != null and p["ci95"][0] < 0.25 and p["ci95"][1] > 0.25)
	assert_eq(Stats.paired_binary([], []), {"n_pairs": 0, "a_only": 0, "b_only": 0, "both": 0, "neither": 0})
	assert_true(Stats.paired_binary([1], [0])["ci95"] == null)
