extends Control
class_name MobileHud
##
## The touch interface (section 12). Portrait, thumb-first, no keyboard.
##
## Every touch is dispatched HERE, in _input(), by hit-testing it against the
## control rectangles by hand, instead of letting each widget grab its own
## _gui_input. That is deliberate: Godot's GUI routing plus mouse emulation
## makes it very easy to end up with a joystick that dies the moment a second
## thumb touches a button. Manual dispatch by touch index cannot do that, and
## "hold the stick AND tap RAMASSER" is the single most important thing this
## interface has to get right (section 13).
##
## Everything is drawn in _draw() rather than assembled from textures: it is
## resolution-independent, it costs one canvas item, and it means the whole
## interface is readable and tweakable in one file from a phone.

@export var player_path: NodePath
@export var camera_path: NodePath
@export var appearance_screen_path: NodePath

@export_group("Layout")
@export var stick_radius_ratio: float = 0.115
@export var margin_ratio: float = 0.055
@export var dead_zone: float = 0.13

var _player: PlayerController
var _camera: PlayerCamera
var _interactor: Interactor

# One entry per active finger: index -> what that finger is doing.
var _stick_touch: int = -1
var _run_touch: int = -1
var _act_touch: int = -1
var _jump_touch: int = -1
var _look_touch: int = -1
## How long the RUN touch has been down. See _release() for why.
var _run_hold: float = 0.0
## RUN was tapped rather than held, and is latched on.
var _run_latched: bool = false
## Time the stick has been at rest while RUN is latched.
var _idle_since_run: float = 0.0

var _stick_origin: Vector2
var _stick_vec: Vector2 = Vector2.ZERO
var _look_last: Vector2 = Vector2.ZERO
var _key_driven := false
var _key_run := false

var _stick_c: Vector2
var _stick_r: float
var _run_c: Vector2
var _run_r: float
var _act_c: Vector2
var _act_r: float
var _jump_c: Vector2
var _jump_r: float
var _dbg_c: Vector2
var _dbg_r: float
var _qual_c: Vector2
var _qual_r: float
var _appear_c: Vector2
var _appear_r: float
var _appearance: Node
## Set by WorldRoot: the quality button only exists while the panel is open.
var debug_visible: bool = false

var _prompt := ""
var _flash := 0.0
var _flash_text := ""

signal debug_toggle_pressed


func _ready() -> void:
	_player = get_node_or_null(player_path) as PlayerController
	_camera = get_node_or_null(camera_path) as PlayerCamera
	_appearance = get_node_or_null(appearance_screen_path)
	if _player:
		_interactor = _player.get_node_or_null("Interactor") as Interactor
		if _interactor:
			_interactor.candidate_changed.connect(_on_candidate)
			_interactor.collected.connect(_on_collected)
			_interactor.interacted.connect(_on_interacted)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_layout()
	get_viewport().size_changed.connect(_layout)


func _layout() -> void:
	var s := size
	if s.x < 1.0:
		s = get_viewport_rect().size
	var unit: float = minf(s.x, s.y)
	_stick_r = unit * stick_radius_ratio
	var m := unit * margin_ratio
	_stick_c = Vector2(m + _stick_r, s.y - m - _stick_r)
	# SECTION 29 — where the JUMP button goes, and why RUN moved.
	#
	# The requirement is that the player can run AND jump without letting go
	# of the stick. The stick is the left thumb, so both buttons are the right
	# thumb, and one thumb cannot hold COURIR down and tap SAUTER at the same
	# time. Something had to give.
	#
	# What gives is COURIR's press model, not its position: a TAP latches it
	# on (and a second tap, or coming to a standstill, lets it go), while a
	# HOLD still works exactly as it did in 0.2. So the thumb taps COURIR
	# once, then lives on SAUTER — which is why SAUTER, not COURIR, is now the
	# big button under the resting thumb.
	_jump_r = _stick_r * 0.82
	_jump_c = Vector2(s.x - m - _jump_r, s.y - m - _jump_r)
	_run_r = _stick_r * 0.62
	_run_c = Vector2(_jump_c.x - _jump_r - _run_r - m * 0.45,
		_jump_c.y - _jump_r * 0.52)
	_act_r = _stick_r * 0.74
	_act_c = Vector2(_jump_c.x, _jump_c.y - _jump_r - _act_r - m * 0.6)
	_dbg_r = unit * 0.035
	_dbg_c = Vector2(s.x - m - _dbg_r, m + _dbg_r)
	_qual_r = _dbg_r
	_qual_c = Vector2(_dbg_c.x - _dbg_r * 2.5, _dbg_c.y)
	_appear_r = _dbg_r
	_appear_c = Vector2(m + _appear_r, m + _appear_r)
	queue_redraw()


# ------------------------------------------------------------- input ------
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_press(t.index, t.position)
		else:
			_release(t.index)
		return
	if event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_touch:
			_drag_stick(d.position)
		elif d.index == _look_touch and _camera:
			_camera.look(d.position - _look_last)
			_look_last = d.position
		return
	# Desktop convenience only; the phone never needs these. Routed through
	# the named InputMap actions (section 7) rather than raw keycodes, so a
	# gamepad works too and a rebinding screen would have somewhere to write.
	if event.is_action_pressed(&"jump"):
		if _player: _player.press_jump()
		return
	if event.is_action_released(&"jump"):
		if _player: _player.release_jump()
		return
	if event.is_action_pressed(&"interact"):
		_do_interact()
		return
	if event is InputEventKey and event.pressed and not event.is_echo():
		match (event as InputEventKey).physical_keycode:
			KEY_F3: debug_toggle_pressed.emit()
			KEY_F4: Quality.toggle()


func _press(index: int, pos: Vector2) -> void:
	# The customisation screen takes over input while it is open, so this
	# only ever opens it.
	if _appearance and _hit(pos, _appear_c, _appear_r * 1.4):
		_appearance.call("toggle")
		queue_redraw()
		return
	if _hit(pos, _dbg_c, _dbg_r * 1.4):
		debug_toggle_pressed.emit()
		queue_redraw()
		return
	if debug_visible and _hit(pos, _qual_c, _qual_r * 1.4):
		Quality.toggle()
		queue_redraw()
		return
	if _act_touch == -1 and _prompt != "" and _hit(pos, _act_c, _act_r * 1.25):
		_act_touch = index
		_do_interact()
		queue_redraw()
		return
	if _jump_touch == -1 and _hit(pos, _jump_c, _jump_r * 1.2):
		_jump_touch = index
		if _player: _player.press_jump()
		queue_redraw()
		return
	if _run_touch == -1 and _hit(pos, _run_c, _run_r * 1.3):
		_run_touch = index
		_run_hold = 0.0
		if _player: _player.run_held = true
		queue_redraw()
		return
	# The stick's catch area is much bigger than the stick itself, and the
	# stick re-centres wherever the thumb lands inside it. Chasing a fixed
	# circle with your thumb is the thing that makes virtual sticks hated.
	if _stick_touch == -1 and _hit(pos, _stick_c, _stick_r * 2.4):
		_stick_touch = index
		_stick_origin = pos
		_drag_stick(pos)
		return
	if _look_touch == -1:
		_look_touch = index
		_look_last = pos


func _release(index: int) -> void:
	if index == _stick_touch:
		_stick_touch = -1
		_stick_vec = Vector2.ZERO
		if _player: _player.move_input = Vector2.ZERO
		queue_redraw()
	elif index == _run_touch:
		# A quick tap latches; a deliberate hold releases on lift. The
		# threshold is the same 0.30 s a UI would use to tell a tap from a
		# press, and it means neither habit is wrong.
		_run_touch = -1
		if _run_hold < 0.30:
			_run_latched = not _run_latched
			_idle_since_run = 0.0
		else:
			_run_latched = false
		if _player: _player.run_held = _run_latched
		queue_redraw()
	elif index == _jump_touch:
		_jump_touch = -1
		if _player: _player.release_jump()
		queue_redraw()
	elif index == _act_touch:
		_act_touch = -1
		queue_redraw()
	elif index == _look_touch:
		_look_touch = -1


func _drag_stick(pos: Vector2) -> void:
	var v := (pos - _stick_origin) / _stick_r
	if v.length() > 1.0:
		# Let the origin trail the thumb instead of clamping hard, so a long
		# drag keeps feeling connected.
		_stick_origin = pos - v.normalized() * _stick_r
		v = v.normalized()
	_stick_vec = v
	var out := v
	if out.length() < dead_zone:
		out = Vector2.ZERO
	else:
		out = out.normalized() * inverse_lerp(dead_zone, 1.0, minf(out.length(), 1.0))
	# Screen Y grows downwards; forward is up.
	if _player:
		_player.move_input = Vector2(out.x, -out.y)
	queue_redraw()


func _hit(pos: Vector2, centre: Vector2, radius: float) -> bool:
	return pos.distance_to(centre) <= radius


func _do_interact() -> void:
	if _interactor:
		_interactor.interact()


## The one interaction button relabels itself (sections 71, 72). It is not
## joined by a second button; it becomes PRENDRE, OUVRIR, ALLUMER or
## ACTIVER as appropriate, and it disappears entirely when there is nothing
## in reach rather than sitting there greyed out and unpressable.
func _on_candidate(c: InteractableComponent) -> void:
	_prompt = "" if c == null else c.prompt()
	queue_redraw()


func _on_collected(item: ItemDefinition, amount: int, total: int) -> void:
	var label := item.display_name if item else "?"
	_flash_text = "+%d %s   (%d)" % [amount, label, total]
	_flash = 1.6
	queue_redraw()


## Non-pickup interactions get a confirmation too, so opening a door or
## lighting a fire reads as having happened.
func _on_interacted(c: InteractableComponent, _actor: Node3D) -> void:
	if c is Pickup:
		return
	_flash_text = c.noun if not c.noun.is_empty() else c.prompt()
	_flash = 1.1
	queue_redraw()


func _process(delta: float) -> void:
	_desktop_keys()
	if _run_touch != -1:
		_run_hold += delta
	elif _run_latched and _player:
		# Latched RUN lets go by itself once the player has actually stopped,
		# so nobody walks into the next scene still holding an invisible
		# sprint. Half a second, so a pause at a doorway does not cancel it.
		if _player.move_input.length() < 0.06:
			_idle_since_run += delta
			if _idle_since_run > 0.5:
				_run_latched = false
				_player.run_held = false
				queue_redraw()
		else:
			_idle_since_run = 0.0
	if _flash > 0.0:
		_flash -= delta
		queue_redraw()
	elif _stick_touch != -1 or _prompt != "":
		queue_redraw()


## Desktop convenience so the scene can be driven without a touchscreen
## while developing. The phone never reaches this path: as soon as a finger
## is on the stick, the stick wins.
func _desktop_keys() -> void:
	if _player == null or _stick_touch != -1:
		return
	var v := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT))
			- float(Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
			- float(Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)))
	if v.length() > 1.0:
		v = v.normalized()
	# Only write while the keyboard is actually driving, and for one frame
	# after it lets go. Writing every frame would stomp on anything else
	# that sets move_input (the automated test harness, for one).
	if v != Vector2.ZERO:
		_key_driven = true
		_player.move_input = v
	elif _key_driven:
		_key_driven = false
		_player.move_input = Vector2.ZERO
	if _run_touch == -1 and not _run_latched and (_key_driven or _key_run):
		_key_run = Input.is_action_pressed(&"sprint")
		_player.run_held = _key_run


# -------------------------------------------------------------- draw ------
func _draw() -> void:
	var font := get_theme_default_font()
	var fs: int = int(_stick_r * 0.30)

	# --- stick ------------------------------------------------------------
	var origin := _stick_origin if _stick_touch != -1 else _stick_c
	draw_circle(origin, _stick_r, Color(1, 1, 1, 0.07))
	draw_arc(origin, _stick_r, 0, TAU, 48, Color(1, 1, 1, 0.28), 2.5, true)
	var knob := origin + _stick_vec * _stick_r
	draw_circle(knob, _stick_r * 0.42, Color(0.92, 0.95, 1.0, 0.32))
	draw_arc(knob, _stick_r * 0.42, 0, TAU, 32, Color(1, 1, 1, 0.6), 2.0, true)

	# --- jump -------------------------------------------------------------
	_button(_jump_c, _jump_r, "SAUTER", font, fs, _jump_touch != -1,
		Color(0.72, 0.92, 0.72))

	# --- run --------------------------------------------------------------
	var run_on := _run_touch != -1 or _run_latched
	_button(_run_c, _run_r, "COURIR", font, int(fs * 0.80), run_on,
		Color(0.58, 0.80, 0.95))
	if _run_latched:
		# A latched button has to look different from a held one, or the
		# player cannot tell why they are sprinting.
		draw_arc(_run_c, _run_r * 1.16, 0, TAU, 40, Color(0.58, 0.80, 0.95, 0.75), 2.0, true)

	# --- interact (only when there is something to interact with) ---------
	if _prompt != "":
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
		_button(_act_c, _act_r, _prompt, font, fs, _act_touch != -1,
			Color(0.98, 0.85, 0.45).lerp(Color(1, 1, 1), pulse * 0.35))

	# --- customisation ----------------------------------------------------
	if _appearance:
		_button(_appear_c, _appear_r, "A", font, int(_appear_r * 0.95), false,
			Color(0.85, 0.72, 0.5))

	# --- debug toggle, and the quality switch it reveals -------------------
	_button(_dbg_c, _dbg_r, "i", font, int(_dbg_r * 1.0), debug_visible,
		Color(0.7, 0.75, 0.85))
	if debug_visible:
		_button(_qual_c, _qual_r, Quality.level_name(), font, int(_dbg_r * 0.52), false,
			Color(0.55, 0.9, 0.7) if not Quality.is_low() else Color(0.95, 0.72, 0.45))

	# --- pickup flash -----------------------------------------------------
	if _flash > 0.0 and font:
		var a := clampf(_flash / 0.6, 0.0, 1.0)
		var w := size.x if size.x > 1.0 else get_viewport_rect().size.x
		var y := (size.y if size.y > 1.0 else get_viewport_rect().size.y) * 0.34
		var txt := _flash_text
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(font, Vector2((w - tw) * 0.5, y), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.75 * a))
		draw_string(font, Vector2((w - tw) * 0.5, y), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.93, 0.72, a))


func _button(c: Vector2, r: float, label: String, font: Font, fs: int,
		pressed: bool, tint: Color) -> void:
	var fill := Color(tint.r, tint.g, tint.b, 0.30 if pressed else 0.14)
	draw_circle(c, r, fill)
	draw_arc(c, r, 0, TAU, 40, Color(tint.r, tint.g, tint.b, 0.85), 2.5, true)
	if font == null or label == "":
		return
	var sz := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var p := c - Vector2(sz.x * 0.5, -sz.y * 0.30)
	draw_string_outline(font, p, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.7))
	draw_string(font, p, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
