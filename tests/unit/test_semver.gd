extends TestCase
## Versiones semanticas y restricciones.


func test_parse_valid_and_invalid() -> void:
	assert_eq(SemVer.parse("1.2.3"), [1, 2, 3, ""])
	assert_eq(SemVer.parse("0.0.1-beta.2"), [0, 0, 1, "beta.2"])
	for bad in ["", "1", "1.2", "1.2.3.4", "01.2.3", "1.2.x", "v1.2.3", "1.2.3-", "-1.2.3", "1.2.3 "]:
		assert_false(SemVer.is_valid(bad), "invalida: '%s'" % bad)


func test_compare() -> void:
	assert_eq(SemVer.compare("1.2.3", "1.2.3"), 0)
	assert_eq(SemVer.compare("1.2.3", "1.10.0"), -1, "comparacion numerica, no textual")
	assert_eq(SemVer.compare("2.0.0", "1.99.99"), 1)
	assert_eq(SemVer.compare("1.0.0-alpha", "1.0.0"), -1, "prerelease < release")
	assert_eq(SemVer.compare("1.0.0", "1.0.0-rc1"), 1)
	assert_eq(SemVer.compare("1.0.0-alpha", "1.0.0-beta"), -1)


func test_constraints() -> void:
	assert_true(SemVer.satisfies("1.2.3", "*"))
	assert_true(SemVer.satisfies("1.2.3", "1.2.3"))
	assert_false(SemVer.satisfies("1.2.4", "1.2.3"))
	assert_true(SemVer.satisfies("1.9.0", "^1.2.3"))
	assert_false(SemVer.satisfies("2.0.0", "^1.2.3"))
	assert_false(SemVer.satisfies("1.2.2", "^1.2.3"))
	assert_true(SemVer.satisfies("0.2.9", "^0.2.1"), "con major 0, ^ fija el minor")
	assert_false(SemVer.satisfies("0.3.0", "^0.2.1"))
	assert_true(SemVer.satisfies("1.2.9", "~1.2.3"))
	assert_false(SemVer.satisfies("1.3.0", "~1.2.3"))
	assert_true(SemVer.satisfies("3.0.0", ">=1.0.0"))
	assert_false(SemVer.satisfies("0.9.9", ">=1.0.0"))
	assert_false(SemVer.satisfies("1.0.0", "basura"))
	assert_false(SemVer.is_valid_constraint("^1.2"))
