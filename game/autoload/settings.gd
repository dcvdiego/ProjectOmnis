extends Node
## Player settings (graphics quality, field of view, sensitivity), saved to
## `user://settings.cfg` and applied to the viewport and the current map's
## environment.
##
## Quality presets trade effects for frame rate. Movement-heavy shooters feel
## best at a high, stable frame rate, so "Medium" is the default and nothing
## here adds input latency (no TAA smearing, V-Sync off by default).

signal changed

enum Quality { LOW, MEDIUM, HIGH, ULTRA }

const PATH := "user://settings.cfg"
const QUALITY_NAMES := ["Low", "Medium", "High", "Ultra"]

var quality := Quality.MEDIUM
var fov := 90.0
## Extra FOV at full speed / while sliding (set 0 to disable).
var fov_boost := 8.0
var mouse_sensitivity := 1.0
var stick_sensitivity := 1.0
var invert_y := false
var auto_sprint := false
var vsync := false
var max_fps := 0


func _ready() -> void:
	load_settings()
	get_tree().node_added.connect(_on_node_added)
	apply()


func set_quality(value: int) -> void:
	quality = clampi(value, 0, Quality.size() - 1) as Quality
	apply()
	save_settings()


func apply() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport()
	match quality:
		Quality.LOW:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			vp.scaling_3d_scale = 0.77
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			vp.anisotropic_filtering_level = Viewport.ANISOTROPY_2X
			vp.mesh_lod_threshold = 4.0
			vp.positional_shadow_atlas_size = 1024
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
		Quality.MEDIUM:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
			vp.anisotropic_filtering_level = Viewport.ANISOTROPY_4X
			vp.mesh_lod_threshold = 2.0
			vp.positional_shadow_atlas_size = 2048
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		Quality.HIGH:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
			vp.anisotropic_filtering_level = Viewport.ANISOTROPY_8X
			vp.mesh_lod_threshold = 1.0
			vp.positional_shadow_atlas_size = 4096
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
		Quality.ULTRA:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_4X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
			vp.anisotropic_filtering_level = Viewport.ANISOTROPY_16X
			vp.mesh_lod_threshold = 0.5
			vp.positional_shadow_atlas_size = 4096
			RenderingServer.directional_shadow_atlas_set_size(8192, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps
	for env_node in get_tree().get_nodes_in_group("world_environment"):
		apply_environment((env_node as WorldEnvironment).environment)
	changed.emit()


## Turns screen-space effects on or off for the current preset.
func apply_environment(env: Environment) -> void:
	if env == null:
		return
	env.ssao_enabled = quality >= Quality.MEDIUM
	env.ssil_enabled = quality >= Quality.HIGH
	env.ssr_enabled = quality >= Quality.ULTRA
	env.sdfgi_enabled = quality >= Quality.ULTRA
	env.volumetric_fog_enabled = quality >= Quality.HIGH
	env.glow_enabled = true
	RenderingServer.environment_set_ssao_quality(
		RenderingServer.ENV_SSAO_QUALITY_LOW if quality <= Quality.MEDIUM else RenderingServer.ENV_SSAO_QUALITY_MEDIUM,
		true, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(
		RenderingServer.ENV_SSIL_QUALITY_LOW if quality <= Quality.HIGH else RenderingServer.ENV_SSIL_QUALITY_MEDIUM,
		true, 0.5, 4, 50.0, 300.0)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in _keys():
		cfg.set_value("settings", key, get(key))
	cfg.save(PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key in _keys():
		if cfg.has_section_key("settings", key):
			set(key, cfg.get_value("settings", key))
	quality = clampi(quality, 0, Quality.size() - 1) as Quality
	fov = clampf(fov, 70.0, 120.0)


func _keys() -> PackedStringArray:
	return PackedStringArray(["quality", "fov", "fov_boost", "mouse_sensitivity", "stick_sensitivity",
		"invert_y", "auto_sprint", "vsync", "max_fps"])


func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment:
		node.add_to_group("world_environment")
		apply_environment.call_deferred((node as WorldEnvironment).environment)
