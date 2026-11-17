extends SceneTree
## Headless test runner. Exits non-zero on failure or on script errors.
##
##   godot --headless --path . -s tests/run_tests.gd
##
## Kept dependency-free on purpose; switch to GUT or gdUnit4 once the suite grows.
## The cases live in `suite.gd`, loaded at runtime so they can use autoloads.
##
## First it compiles every script in the project (like `tsc --noEmit`), so
## warnings treated as errors (see [debug] in project.godot) fail the run even
## in scripts no test touches.

const SCRIPT_ROOTS: Array[String] = ["res://game", "res://tests", "res://tools"]


func _initialize() -> void:
	_run()


func _run() -> void:
	var broken := _compile_all()
	if not broken.is_empty():
		for path in broken:
			printerr("FAIL: %s failed to compile (see SCRIPT ERROR above)" % path)
		quit(1)
		return
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


## Loads every .gd file under SCRIPT_ROOTS; returns the ones that don't compile.
func _compile_all() -> Array[String]:
	var broken: Array[String] = []
	var dirs: Array[String] = SCRIPT_ROOTS.duplicate()
	var count := 0
	while not dirs.is_empty():
		var dir := dirs.pop_back() as String
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for sub in DirAccess.get_directories_at(dir):
			dirs.append(dir.path_join(sub))
		for file in DirAccess.get_files_at(dir):
			if file.get_extension() != "gd":
				continue
			count += 1
			var path := dir.path_join(file)
			var script := ResourceLoader.load(path, "GDScript") as GDScript
			if script == null or not script.can_instantiate():
				broken.append(path)
	print("Compiled %d scripts" % count)
	return broken
