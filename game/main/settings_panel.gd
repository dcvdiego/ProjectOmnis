class_name SettingsPanel
extends GridContainer
## Settings controls (built in code), used by the main menu and the pause menu.


func _ready() -> void:
	columns = 2
	add_theme_constant_override("h_separation", 16)
	add_theme_constant_override("v_separation", 8)

	var quality := OptionButton.new()
	for i in Settings.QUALITY_NAMES.size():
		quality.add_item(Settings.QUALITY_NAMES[i], i)
	quality.selected = Settings.quality
	quality.item_selected.connect(func(i: int) -> void: Settings.set_quality(i))
	_row("Graphics", quality)

	_row("Field of view", _slider(70, 120, 1, Settings.fov, func(v: float) -> void: Settings.fov = v, "%d°"))
	_row("Speed FOV boost", _slider(0, 15, 1, Settings.fov_boost, func(v: float) -> void: Settings.fov_boost = v, "+%d°"))
	_row("Mouse sensitivity", _slider(0.1, 4.0, 0.05, Settings.mouse_sensitivity,
		func(v: float) -> void: Settings.mouse_sensitivity = v, "%.2f"))
	_row("Stick sensitivity", _slider(0.2, 3.0, 0.05, Settings.stick_sensitivity,
		func(v: float) -> void: Settings.stick_sensitivity = v, "%.2f"))
	_row("Invert look", _check(Settings.invert_y, func(on: bool) -> void: Settings.invert_y = on))
	_row("Always sprint", _check(Settings.auto_sprint, func(on: bool) -> void: Settings.auto_sprint = on))
	_row("V-Sync", _check(Settings.vsync, func(on: bool) -> void:
		Settings.vsync = on
		Settings.apply()))


func _row(label_text: String, control: Control) -> void:
	var label := Label.new()
	label.text = label_text
	add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(control)


func _slider(min_value: float, max_value: float, step: float, value: float, setter: Callable, fmt: String) -> Control:
	var box := HBoxContainer.new()
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = value
	slider.custom_minimum_size.x = 160
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var readout := Label.new()
	readout.custom_minimum_size.x = 48
	readout.text = fmt % value
	slider.value_changed.connect(func(v: float) -> void:
		setter.call(v)
		readout.text = fmt % v)
	slider.drag_ended.connect(func(_changed: bool) -> void: Settings.save_settings())
	box.add_child(slider)
	box.add_child(readout)
	return box


func _check(value: bool, setter: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.button_pressed = value
	check.toggled.connect(func(on: bool) -> void:
		setter.call(on)
		Settings.save_settings())
	return check
