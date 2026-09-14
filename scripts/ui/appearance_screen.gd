extends Control
class_name AppearanceScreen
##
## The customisation screen (section 8).
##
## Explicitly NOT the final character creator — it is the test harness that
## proves CharacterAppearance drives the model. Every change applies to the
## live player immediately, so what you see is the thing that would be saved.
##
## Drawn in _draw() and driven from _input(), like the touch HUD, because it
## has to be usable with a thumb in portrait on a phone.
##
## HONESTY ROW. One row is drawn greyed out and labelled: hairstyle. The
## KayKit bodies have no separable hair mesh, so there is nothing for that
## field to change. Showing it disabled, with the reason, is the truthful
## presentation — hiding it would imply the feature does not exist, and
## faking it would be worse than either.

signal closed

@export var player_path: NodePath

const ROW_BODY := 0
const ROW_SKIN := 1
const ROW_VARIANT := 2
const ROW_PRIMARY := 3
const ROW_SECONDARY := 4
const ROW_HAIR := 5
const ROW_COUNT := 6

var _player: PlayerController
var _appearance: CharacterAppearance
var _primary_index := AppearanceCatalog.DEFAULT_PRIMARY
var _secondary_index := AppearanceCatalog.DEFAULT_SECONDARY

var _rows: Array[Rect2] = []
var _left: Array[Rect2] = []
var _right: Array[Rect2] = []
var _close_rect := Rect2()
var _pressed := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_player = get_node_or_null(player_path) as PlayerController
	visible = false
	get_viewport().size_changed.connect(_layout)


func open() -> void:
	if _player == null:
		return
	_appearance = _player.appearance.duplicate_appearance() if _player.appearance \
		else CharacterAppearance.make_default()
	_primary_index = _nearest_colour(_appearance.primary_color)
	_secondary_index = _nearest_colour(_appearance.secondary_color)
	visible = true
	_layout()


func close() -> void:
	visible = false
	closed.emit()


func toggle() -> void:
	if visible: close()
	else: open()


func _nearest_colour(c: Color) -> int:
	var best := 0
	var best_d := INF
	for i in AppearanceCatalog.OUTFIT_COLORS.size():
		var o: Color = AppearanceCatalog.OUTFIT_COLORS[i]["color"]
		var d := Vector3(o.r - c.r, o.g - c.g, o.b - c.b).length()
		if d < best_d:
			best_d = d
			best = i
	return best


func _layout() -> void:
	var s := size if size.x > 1.0 else get_viewport_rect().size
	var margin := s.x * 0.06
	var w := s.x - margin * 2.0
	var row_h := minf(s.y * 0.072, 84.0)
	var top := s.y * 0.20
	_rows.clear(); _left.clear(); _right.clear()
	for i in ROW_COUNT:
		var r := Rect2(margin, top + float(i) * (row_h + 10.0), w, row_h)
		_rows.append(r)
		_left.append(Rect2(r.position.x, r.position.y, row_h, row_h))
		_right.append(Rect2(r.position.x + r.size.x - row_h, r.position.y, row_h, row_h))
	var last: Rect2 = _rows[ROW_COUNT - 1]
	_close_rect = Rect2(margin, last.position.y + row_h + 26.0, w, row_h * 1.1)
	queue_redraw()


# ------------------------------------------------------------- input -----
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_press(t.position)
		else:
			_pressed = -1
			queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()


func _press(p: Vector2) -> void:
	if _close_rect.has_point(p):
		close()
		return
	for i in ROW_COUNT:
		if i == ROW_HAIR:
			continue     # disabled: no hair meshes in these assets
		if _left[i].has_point(p):
			_step(i, -1); _pressed = i * 2; queue_redraw(); return
		if _right[i].has_point(p):
			_step(i, 1); _pressed = i * 2 + 1; queue_redraw(); return


func _step(row: int, dir: int) -> void:
	match row:
		ROW_BODY:
			var n := AppearanceCatalog.BODIES.size()
			_appearance.body_type = (_appearance.body_type + dir + n) % n
			# Variants are per-body; a stale index would point at nothing.
			_appearance.outfit_variant = 0
		ROW_SKIN:
			var n2 := AppearanceCatalog.SKIN_TONES.size()
			_appearance.skin_tone = (_appearance.skin_tone + dir + n2) % n2
		ROW_VARIANT:
			var v: Array = AppearanceCatalog.body(_appearance.body_type)["variants"]
			_appearance.outfit_variant = (_appearance.outfit_variant + dir + v.size()) % v.size()
		ROW_PRIMARY:
			var n3 := AppearanceCatalog.OUTFIT_COLORS.size()
			_primary_index = (_primary_index + dir + n3) % n3
			_appearance.primary_color = AppearanceCatalog.outfit_color(_primary_index)
		ROW_SECONDARY:
			var n4 := AppearanceCatalog.OUTFIT_COLORS.size()
			_secondary_index = (_secondary_index + dir + n4) % n4
			_appearance.secondary_color = AppearanceCatalog.outfit_color(_secondary_index)
	_apply()


func _apply() -> void:
	if _player:
		_player.apply_appearance(_appearance.duplicate_appearance())
	queue_redraw()


# -------------------------------------------------------------- draw -----
func _draw() -> void:
	var s := size if size.x > 1.0 else get_viewport_rect().size
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.04, 0.05, 0.07, 0.82))

	var title_size := int(minf(s.x * 0.052, 40.0))
	var fs := int(minf(s.x * 0.036, 27.0))
	var small := int(minf(s.x * 0.026, 20.0))

	_text(font, "APPARENCE", Vector2(s.x * 0.06, s.y * 0.12), title_size,
		Color(0.94, 0.92, 0.88))
	_text(font, _appearance.describe(), Vector2(s.x * 0.06, s.y * 0.155), small,
		Color(0.66, 0.70, 0.76))

	var labels := ["CORPS", "PEAU", "TENUE", "COULEUR 1", "COULEUR 2", "CHEVEUX"]
	for i in ROW_COUNT:
		var enabled := i != ROW_HAIR
		var r: Rect2 = _rows[i]
		draw_rect(r, Color(1, 1, 1, 0.05 if enabled else 0.02), true)
		draw_rect(r, Color(1, 1, 1, 0.16 if enabled else 0.07), false, 1.5)
		_text(font, labels[i], r.position + Vector2(r.size.y + 12.0, r.size.y * 0.38),
			small, Color(0.62, 0.67, 0.74) if enabled else Color(0.4, 0.4, 0.44))

		var value := _value_for(i)
		var col := Color(0.95, 0.94, 0.92) if enabled else Color(0.45, 0.45, 0.5)
		_text(font, value, r.position + Vector2(r.size.y + 12.0, r.size.y * 0.82), fs, col)

		# Colour rows get a swatch, because a colour name is not a colour.
		if i == ROW_PRIMARY or i == ROW_SECONDARY:
			var sw := Color(_appearance.primary_color if i == ROW_PRIMARY
				else _appearance.secondary_color)
			var box := Rect2(r.position.x + r.size.x - r.size.y * 2.4,
				r.position.y + r.size.y * 0.22, r.size.y * 0.9, r.size.y * 0.56)
			draw_rect(box, sw, true)
			draw_rect(box, Color(1, 1, 1, 0.35), false, 1.5)

		if enabled:
			_arrow(font, _left[i], "<", fs)
			_arrow(font, _right[i], ">", fs)

	# The honest footnote.
	var hair_row: Rect2 = _rows[ROW_HAIR]
	_text(font, "aucun maillage de cheveux séparable dans ces modèles",
		hair_row.position + Vector2(hair_row.size.y + 12.0, hair_row.size.y + 16.0),
		int(small * 0.85), Color(0.78, 0.62, 0.38))

	draw_rect(_close_rect, Color(0.55, 0.75, 0.62, 0.18), true)
	draw_rect(_close_rect, Color(0.55, 0.85, 0.68, 0.8), false, 2.0)
	var cw := font.get_string_size("FERMER", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_text(font, "FERMER", _close_rect.position
		+ Vector2((_close_rect.size.x - cw) * 0.5, _close_rect.size.y * 0.66), fs,
		Color(1, 1, 1, 0.95))


func _value_for(row: int) -> String:
	match row:
		ROW_BODY:
			return str(AppearanceCatalog.body(_appearance.body_type)["name"])
		ROW_SKIN:
			return str(AppearanceCatalog.SKIN_TONES[_appearance.skin_tone]["name"])
		ROW_VARIANT:
			return str(AppearanceCatalog.variant(_appearance.body_type,
				_appearance.outfit_variant)["name"])
		ROW_PRIMARY:
			return str(AppearanceCatalog.OUTFIT_COLORS[_primary_index]["name"])
		ROW_SECONDARY:
			return str(AppearanceCatalog.OUTFIT_COLORS[_secondary_index]["name"])
		_:
			return "— indisponible"


func _arrow(font: Font, r: Rect2, glyph: String, fs: int) -> void:
	draw_rect(r, Color(1, 1, 1, 0.08), true)
	var w := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_text(font, glyph, r.position + Vector2((r.size.x - w) * 0.5, r.size.y * 0.66), fs,
		Color(1, 1, 1, 0.85))


func _text(font: Font, s: String, at: Vector2, fs: int, col: Color) -> void:
	if font == null:
		return
	draw_string_outline(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.7))
	draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
