extends Control
class_name DebugHud
##
## The performance journal (section 34).
##
## Display only: every touch in this project is dispatched by MobileHud, so
## this panel deliberately owns no input at all. Toggled with the "i" button
## (or F3 on a desktop).
##
## Everything here is a real engine counter, not an estimate. Draw calls and
## primitives come from RenderingServer's own per-frame monitors, which is
## what makes this panel worth trusting when comparing against three.js.

@export var player_path: NodePath
@export var fog_path: NodePath
@export var npc_path: NodePath
@export var animal_path: NodePath
@export var world_path: NodePath
@export var refresh_interval: float = 0.25

var _player: PlayerController
var _fog: FogWall
var _npc: NpcController
var _animal: AnimalPlaceholder
var _world: Node

var _label: Label
var _t := 0.0
var _fps_min := 9999.0
var _fps_sum := 0.0
var _fps_n := 0
var _window := 0.0


func _ready() -> void:
	_player = get_node_or_null(player_path) as PlayerController
	_fog = get_node_or_null(fog_path) as FogWall
	_npc = get_node_or_null(npc_path) as NpcController
	_animal = get_node_or_null(animal_path) as AnimalPlaceholder
	_world = get_node_or_null(world_path)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.07, 0.72)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(12, 12)
	panel.size = Vector2(330, 10)
	add_child(panel)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.85, 0.90, 0.95))
	panel.add_child(_label)
	visible = false
	_refresh()


func _process(delta: float) -> void:
	var fps := Engine.get_frames_per_second()
	_fps_min = minf(_fps_min, fps)
	_fps_sum += fps
	_fps_n += 1
	_window += delta
	if _window > 12.0:
		# Roll the window so a single hitch at load does not brand the whole
		# session as slow.
		_window = 0.0
		_fps_min = fps
		_fps_sum = fps
		_fps_n = 1
	if not visible:
		return
	_t -= delta
	if _t <= 0.0:
		_t = refresh_interval
		_refresh()


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()


func _refresh() -> void:
	if _label == null:
		return
	var rs := RenderingServer
	var draws := rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var objs := rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)

	var lines := PackedStringArray()
	lines.append("FOG NOMAD — GODOT BENCHMARK 0.1")
	lines.append("FPS %d   min %d   avg %d" % [
		Engine.get_frames_per_second(), int(_fps_min),
		int(_fps_sum / maxf(_fps_n, 1))])
	lines.append("draws %d   prims %s   objects %d" % [draws, _short(prims), objs])
	lines.append("quality  %s        renderer  %s" % [Quality.level_name(), _renderer_name()])

	if _player:
		lines.append("")
		lines.append("player   %s   depth %.2f m" % [_player.state_name(), _player.water_depth])
		lines.append("speed    %.2f m/s   %s" % [
			_player.horizontal_speed, "RUN" if _player.run_held else "walk"])
		lines.append("surface  %s   in-volume %s" % [
			_player.surface_name(), "yes" if _player.in_water_volume else "no"])
		var inter := _player.get_node_or_null("Interactor") as Interactor
		if inter:
			lines.append("interact %s   bois %d  cristal %d" % [
				(inter.prompt() if inter.has_candidate() else "—"),
				inter.total_of("BOIS"), inter.total_of("CRISTAL")])
		if _fog:
			var d := _fog.distance_to(_player.global_position)
			lines.append("brume    %.1f m %s" % [absf(d), "INSIDE" if d <= 0.0 else "ahead"])

	if _npc or _animal:
		lines.append("")
		if _npc:
			lines.append("npc      %s   %.2f m/s" % [_npc.state_name(), _npc.horizontal_speed])
		if _animal:
			lines.append("animal   %s   %.2f m/s   (PLACEHOLDER)" % [
				_animal.state_name(), _animal.horizontal_speed])

	if _world and _world.has_method("build_report"):
		lines.append("")
		lines.append_array(str(_world.call("build_report")).split("\n"))

	lines.append("")
	lines.append("[i] hide    F3 panel    F4 quality")
	_label.text = "\n".join(lines)


## Report the renderer actually in use, never a hardcoded label. If this ever
## prints anything but MOBILE, the benchmark's core constraint is not being
## honoured and the panel should say so.
func _renderer_name() -> String:
	# Godot 4.3 has no RenderingServer.get_current_rendering_method() (it
	# arrives in 4.4), so the effective method is the command-line override
	# if there is one, and the project setting otherwise.
	var m := str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"))
	var args := OS.get_cmdline_args()
	for i in args.size():
		if args[i] == "--rendering-method" and i + 1 < args.size():
			m = args[i + 1]
	return "MOBILE" if m == "mobile" else m.to_upper()


func _short(v: int) -> String:
	if v >= 1000000:
		return "%.2fM" % (v / 1000000.0)
	if v >= 1000:
		return "%.1fk" % (v / 1000.0)
	return str(v)
