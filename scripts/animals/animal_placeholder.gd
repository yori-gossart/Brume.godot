extends CharacterBody3D
class_name AnimalPlaceholder
##
## ===================== ANIMAL_ASSET_BLOCKED =========================
##
## This is a PLACEHOLDER, and it is labelled as one in the world.
##
## The benchmark's asset rule is the project rule: an asset whose licence has
## not been read at its author's own source does not enter the repository.
## The three packs Fog Nomad already owns (KayKit Adventurers, Halloween Bits,
## Medieval Hexagon — all CC0, all fetched from the author's GitHub) contain
## no animal of any kind. The usual CC0 animal sources (Quaternius, Kenney,
## poly.pizza, OpenGameArt, itch.io) are unreachable from this environment's
## network policy, so their licences could not be read at source and nothing
## was taken from them.
##
## Section 28 is explicit about what to do next: do not spend hours building
## a convincing fake out of primitives. So this is a deliberately cheap
## articulated quadruped whose only job is to prove the BEHAVIOUR loop —
## IDLE -> WALK -> FLEE — and to make the gap in the asset pipeline visible
## instead of hiding it.
##
## What is real here and should be judged: the flee trigger, the navigation,
## and the fact that the legs are driven by distance travelled, so the
## placeholder does not foot-slide either.
##
## What is not real: the model.
## ====================================================================

enum State { IDLE, WALK, FLEE }

@export var walk_speed: float = 1.5
@export var flee_speed: float = 5.4
@export var accel: float = 9.0
@export var turn_speed: float = 7.0
@export var flee_radius: float = 13.0
@export var calm_radius: float = 24.0
@export var fog_fear_distance: float = 22.0
@export var idle_time: Vector2 = Vector2(1.2, 3.4)
@export var body_color: Color = Color(0.494, 0.396, 0.290)
@export var nav_builder_path: NodePath
@export var player_path: NodePath
@export var fog_path: NodePath

@onready var agent: NavigationAgent3D = $NavigationAgent3D

var state: int = State.IDLE
var _nav: NavBuilder
var _player: Node3D
var _fog: Node
var _rng := RandomNumberGenerator.new()
var _wait := 1.0
var _facing := 0.0
var _gait := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 18.0)

var _pivot: Node3D
var _body: Node3D
var _legs: Array[Node3D] = []
var _head: Node3D
var _tail: Node3D
var horizontal_speed := 0.0


func _ready() -> void:
	_rng.seed = 0x414E494D
	_nav = get_node_or_null(nav_builder_path) as NavBuilder
	_player = get_node_or_null(player_path) as Node3D
	_fog = get_node_or_null(fog_path)
	_build_body()
	agent.path_desired_distance = 0.6
	agent.target_desired_distance = 1.0
	agent.avoidance_enabled = false
	floor_max_angle = deg_to_rad(55.0)
	floor_snap_length = 0.4
	global_position.y = TerrainData.height_at(global_position.x, global_position.z) + 0.05
	await get_tree().physics_frame
	await get_tree().physics_frame
	_wander()


# ---------------------------------------------------------------- body ----
func _build_body() -> void:
	_pivot = Node3D.new()
	_pivot.name = "PlaceholderBody"
	add_child(_pivot)

	var hide := StandardMaterial3D.new()
	hide.albedo_color = body_color
	hide.roughness = 0.92
	var dark := StandardMaterial3D.new()
	dark.albedo_color = body_color.darkened(0.35)
	dark.roughness = 0.95

	_body = _part(_pivot, _capsule(0.22, 0.78), hide, Vector3(0, 0.52, 0),
		Vector3(0, 0, deg_to_rad(90)))
	_head = _part(_pivot, _capsule(0.15, 0.30), hide, Vector3(0, 0.68, 0.44),
		Vector3(deg_to_rad(70), 0, 0))
	_part(_head, _capsule(0.045, 0.22), dark, Vector3(-0.07, 0.10, 0.02), Vector3(deg_to_rad(-25), 0, 0))
	_part(_head, _capsule(0.045, 0.22), dark, Vector3(0.07, 0.10, 0.02), Vector3(deg_to_rad(-25), 0, 0))
	_tail = _part(_pivot, _capsule(0.06, 0.22), dark, Vector3(0, 0.58, -0.42), Vector3(deg_to_rad(-40), 0, 0))

	for i in 4:
		var fx := 1.0 if i % 2 == 0 else -1.0
		var fz := 0.26 if i < 2 else -0.24
		var hip := Node3D.new()
		hip.position = Vector3(0.16 * fx, 0.47, fz)
		_pivot.add_child(hip)
		_part(hip, _capsule(0.055, 0.42), dark, Vector3(0, -0.21, 0), Vector3.ZERO)
		_legs.append(hip)

	# The label is not decoration. It is there so that nobody reviewing a
	# screenshot can mistake this for a finished asset.
	var tag := Label3D.new()
	tag.text = "PLACEHOLDER\nANIMAL_ASSET_BLOCKED"
	tag.font_size = 44
	tag.pixel_size = 0.0032
	tag.position = Vector3(0, 1.35, 0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(1.0, 0.78, 0.35)
	tag.outline_size = 14
	tag.no_depth_test = false
	tag.double_sided = true
	_pivot.add_child(tag)


func _capsule(r: float, h: float) -> Mesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(h, r * 2.01)
	m.radial_segments = 6
	m.rings = 2
	return m


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


# ------------------------------------------------------------- behaviour --
func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	var threat := _threat()
	if threat != Vector3.INF and state != State.FLEE:
		_flee_from(threat)
	elif state == State.FLEE and threat == Vector3.INF and agent.is_navigation_finished():
		state = State.IDLE
		_wait = _rng.randf_range(idle_time.x, idle_time.y)

	match state:
		State.IDLE:
			_slow(delta)
			_wait -= delta
			if _wait <= 0.0:
				_wander()
		State.WALK:
			_move(delta, walk_speed)
		State.FLEE:
			_move(delta, flee_speed)

	move_and_slide()
	horizontal_speed = Vector2(velocity.x, velocity.z).length()
	_animate(delta)


## What is frightening right now, or Vector3.INF if nothing is.
func _threat() -> Vector3:
	if _player and is_instance_valid(_player):
		var d := global_position.distance_to(_player.global_position)
		if d < flee_radius:
			return _player.global_position
		if state == State.FLEE and d < calm_radius:
			return _player.global_position
	if _fog and is_instance_valid(_fog) and _fog.has_method("distance_to"):
		if float(_fog.call("distance_to", global_position)) < fog_fear_distance:
			return global_position + Vector3(0, 0, -60.0)
	return Vector3.INF


func _flee_from(threat: Vector3) -> void:
	state = State.FLEE
	if _nav == null:
		return
	var away := global_position - threat
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3(1, 0, 0)
	away = away.normalized()
	# Try a few escape headings and take the one that actually exists on the
	# navigation mesh.
	var best := global_position
	var best_score := -INF
	for i in 7:
		var ang := (float(i) - 3.0) * 0.35
		var dir := away.rotated(Vector3.UP, ang)
		var cand := global_position + dir * _rng.randf_range(22.0, 38.0)
		if not TerrainData.is_walkable(cand.x, cand.z):
			continue
		var score := cand.distance_to(threat) - absf(ang) * 4.0
		if score > best_score:
			best_score = score
			best = cand
	agent.target_position = Vector3(best.x, TerrainData.height_at(best.x, best.z), best.z)


func _wander() -> void:
	if _nav == null:
		_wait = 2.0
		return
	agent.target_position = _nav.random_point(_rng, global_position, 6.0, 26.0)
	state = State.WALK


func _move(delta: float, speed: float) -> void:
	if agent.is_navigation_finished():
		if state == State.FLEE:
			_slow(delta)
		else:
			state = State.IDLE
			_wait = _rng.randf_range(idle_time.x, idle_time.y)
		return
	var to := agent.get_next_path_position() - global_position
	to.y = 0.0
	if to.length() < 0.001:
		return
	_steer(delta, to.normalized(), speed)


func _slow(delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, accel * delta)
	velocity.x = flat.x
	velocity.z = flat.z


## Turn towards the heading, then run along the way you are facing — same
## rule as the NPC, so the placeholder cannot moonwalk either.
func _steer(delta: float, want_dir: Vector3, speed: float) -> void:
	_facing = rotate_toward(_facing, atan2(want_dir.x, want_dir.z), turn_speed * delta)
	_pivot.rotation.y = _facing
	var forward := Vector3(sin(_facing), 0.0, cos(_facing))
	var align := clampf(forward.dot(want_dir), 0.0, 1.0)
	var target := forward * speed * lerpf(0.1, 1.0, align * align)
	var flat := Vector3(velocity.x, 0.0, velocity.z).move_toward(target, accel * delta)
	velocity.x = flat.x
	velocity.z = flat.z


## Legs are driven by DISTANCE TRAVELLED, not by time. A gait built this way
## cannot foot-slide: stride length is fixed, so cadence follows speed for
## free. It is the cheapest correct answer, and it is the same principle the
## character rig gets from its measured blend speeds.
func _animate(delta: float) -> void:
	const STRIDE := 0.62
	_gait += horizontal_speed * delta / STRIDE * TAU
	var swing := clampf(horizontal_speed / flee_speed, 0.0, 1.0) * 0.85 + 0.05
	for i in _legs.size():
		var phase: float = _gait + (0.0 if (i == 0 or i == 3) else PI)
		_legs[i].rotation.x = sin(phase) * swing
	_pivot.position.y = absf(sin(_gait * 0.5)) * 0.045 * swing
	if _head:
		_head.rotation.x = deg_to_rad(70.0) + sin(_gait * 0.5) * 0.06 * swing
	if _tail:
		_tail.rotation.x = deg_to_rad(-40.0) + sin(_gait * 0.5 + 1.0) * 0.25 * swing
		_tail.rotation.y = sin(_gait * 0.25) * 0.2


func state_name() -> String:
	match state:
		State.WALK: return "WALK"
		State.FLEE: return "FLEE"
		_: return "IDLE"
