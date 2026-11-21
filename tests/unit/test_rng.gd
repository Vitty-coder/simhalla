extends TestCase
## RNG determinista: vectores conocidos de SplitMix64, flujos y estado.


func test_splitmix64_known_vectors() -> void:
	# Vectores de referencia de SplitMix64 con semilla 0 (calculados de forma independiente).
	var r := Rng.new(0)
	assert_eq(r.next_u64(), -2152535657050944081, "salida 1 (0xE220A8397B1DCDAF)")
	assert_eq(r.next_u64(), 7960286522194355700, "salida 2 (0x6E789E6AA1B965F4)")
	assert_eq(r.next_u64(), 487617019471545679, "salida 3 (0x06C45D188009454F)")


func test_same_seed_same_sequence() -> void:
	var a := Rng.new(12345)
	var b := Rng.new(12345)
	for i in 100:
		assert_eq(a.next_u64(), b.next_u64(), "u64 #%d" % i)


func test_different_seed_different_sequence() -> void:
	assert_ne(Rng.new(1).next_u64(), Rng.new(2).next_u64())


func test_float_in_unit_interval() -> void:
	var r := Rng.new(99)
	var lo := 1.0
	var hi := 0.0
	for i in 5000:
		var f := r.next_float()
		assert_true(f >= 0.0 and f < 1.0, "fuera de [0,1): %s" % f)
		lo = minf(lo, f)
		hi = maxf(hi, f)
	assert_true(lo < 0.05 and hi > 0.95, "cobertura del intervalo")


func test_next_int_range_and_uniformity() -> void:
	var r := Rng.new(7)
	var counts := [0, 0, 0, 0]
	for i in 4000:
		var v := r.next_int(4)
		assert_true(v >= 0 and v < 4)
		counts[v] += 1
	for c in counts:
		assert_true(c > 800 and c < 1200, "distribucion razonable: %s" % str(counts))


func test_state_save_restore() -> void:
	var r := Rng.new(5)
	for i in 10:
		r.next_u64()
	var saved := r.get_state()
	var expected: Array[int] = []
	for i in 5:
		expected.append(r.next_u64())
	r.set_state(saved)
	for i in 5:
		assert_eq(r.next_u64(), expected[i], "reanudado #%d" % i)


func test_streams_are_independent_and_reproducible() -> void:
	var s1 := RngService.new(42)
	var s2 := RngService.new(42)
	# Consumir "hit" en s1 no altera "crit".
	for i in 10:
		s1.stream("hit").next_u64()
	assert_eq(s1.stream("crit").next_u64(), s2.stream("crit").next_u64(), "crit independiente de hit")
	assert_ne(RngService.new(42).stream("hit").next_u64(), RngService.new(42).stream("crit").next_u64(), "flujos distintos")
	assert_ne(RngService.new(42).stream("hit").next_u64(), RngService.new(43).stream("hit").next_u64(), "semillas distintas")


func test_fnv1a64_stable() -> void:
	# FNV-1a 64 de "" es el offset basis; de "a" es 0xAF63DC4C8601EC8C.
	assert_eq(Rng.fnv1a64(""), -3750763034362895579)
	assert_eq(Rng.fnv1a64("a"), -5808556873153909620)
