extends SceneTree
## Headless test runner. Exits non-zero on failure or on script errors.
##
##   godot --headless --path . -s tests/run_tests.gd
##
## Kept dependency-free on purpose; switch to GUT or gdUnit4 once the suite grows.
## The cases live in `suite.gd`, loaded at runtime so they can use autoloads.


func _initialize() -> void:
	_run()


func _run() -> void:
	var suite_script := load("res://tests/suite.gd") as GDScript
	if suite_script == null or not suite_script.can_instantiate():
		printerr("FAIL: tests/suite.gd failed to compile")
		quit(1)
		return
	var suite: RefCounted = suite_script.new(self)
	await suite.run()
	print("\n%d checks, %d failures" % [suite.checks, suite.failures.size()])
	for failure: String in suite.failures:
		printerr("  FAIL: " + failure)
	quit(1 if suite.failures.size() > 0 else 0)
