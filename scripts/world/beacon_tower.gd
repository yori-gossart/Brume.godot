extends Node3D
class_name BeaconTower
##
## The beacon (section 23).
##
## The three.js version assembled the tower from Halloween-pack pillars and a
## couple of CylinderGeometry rings, and it read as a stack of props. This one
## is built as a structure: a stone footing, four raking timber legs braced
## against each other, a planked platform with a railing, a forged iron crown
## and a crystal in it.
##
## "Active" is shown three ways at once, all on the same clock: the crystal's
## emission, the OmniLight3D it casts, and a slow rotation of the crown. A
## light that pulses while the object it is in stays flat is the tell of a
## fake beacon.

signal pulsed(strength: float)

@export var height: float = 11.0
@export var base_radius: float = 2.6
@export var top_radius: float = 1.5
@export var pulse_period: float = 3.4

var footprint_radius: float:
	get: return base_radius + 1.6

var _crystal_mat: ShaderMaterial
var _light: OmniLight3D
var _crown: Node3D
var _crystal: Node3D
var _t := 0.0
var pulse: float = 0.0
var merged_away: int = 0


func _ready() -> void:
	var body := StaticBody3D.new()
	body.name = "TowerCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	var stone := BuildKit.material(Color(0.353, 0.345, 0.329), 0.94)
	var stone_dark := BuildKit.material(Color(0.259, 0.255, 0.247), 0.96)
	var timber := BuildKit.material(Color(0.376, 0.275, 0.184), 0.86)
	var plank := BuildKit.material(Color(0.451, 0.357, 0.247), 0.8)
	var iron := BuildKit.material(Color(0.208, 0.216, 0.231), 0.42, 0.85)

	# --- stone footing ----------------------------------------------------
	BuildKit.cylinder(self, body, stone, Vector3(0, 0.45, 0), base_radius, 0.9, Vector3.ZERO, true, 10)
	BuildKit.cylinder(self, body, stone_dark, Vector3(0, 1.05, 0), base_radius * 0.82, 0.4, Vector3.ZERO, true, 10)
	# Rough stones around the footing so it sits in the ground, not on it.
	for i in 7:
		var a := TAU * float(i) / 7.0 + 0.3
		var r := base_radius + 0.45
		BuildKit.box(self, null, stone_dark,
			Vector3(cos(a) * r, 0.18, sin(a) * r),
			Vector3(0.7, 0.45, 0.55), Vector3(0.2, a, 0.15), false)

	var deck_y := height - 2.4

	# --- four raking legs -------------------------------------------------
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		var bx := cos(a) * (base_radius * 0.72)
		var bz := sin(a) * (base_radius * 0.72)
		var tx := cos(a) * (top_radius * 0.78)
		var tz := sin(a) * (top_radius * 0.78)
		var from := Vector3(bx, 1.2, bz)
		var to := Vector3(tx, deck_y, tz)
		_beam(body, timber, from, to, 0.19)

	# --- horizontal bracing rings, at two levels --------------------------
	for level in [0.36, 0.72]:
		var y := lerpf(1.2, deck_y, level)
		var r := lerpf(base_radius * 0.72, top_radius * 0.78, level)
		for i in 4:
			var a0 := TAU * float(i) / 4.0 + PI * 0.25
			var a1 := TAU * float(i + 1) / 4.0 + PI * 0.25
			_beam(body, timber, Vector3(cos(a0) * r, y, sin(a0) * r),
				Vector3(cos(a1) * r, y, sin(a1) * r), 0.10)
	# --- diagonal cross-braces on two faces, for a real truss silhouette --
	for i in [0, 2]:
		var a0 := TAU * float(i) / 4.0 + PI * 0.25
		var a1 := TAU * float(i + 1) / 4.0 + PI * 0.25
		var ylo := lerpf(1.2, deck_y, 0.36)
		var yhi := lerpf(1.2, deck_y, 0.72)
		var rlo := lerpf(base_radius * 0.72, top_radius * 0.78, 0.36)
		var rhi := lerpf(base_radius * 0.72, top_radius * 0.78, 0.72)
		_beam(body, timber, Vector3(cos(a0) * rlo, ylo, sin(a0) * rlo),
			Vector3(cos(a1) * rhi, yhi, sin(a1) * rhi), 0.08)
		_beam(body, timber, Vector3(cos(a1) * rlo, ylo, sin(a1) * rlo),
			Vector3(cos(a0) * rhi, yhi, sin(a0) * rhi), 0.08)

	# --- platform ---------------------------------------------------------
	BuildKit.cylinder(self, body, plank, Vector3(0, deck_y + 0.09, 0),
		top_radius + 0.55, 0.18, Vector3.ZERO, true, 10)
	# Railing
	for i in 10:
		var a := TAU * float(i) / 10.0
		var r := top_radius + 0.42
		BuildKit.box(self, null, timber, Vector3(cos(a) * r, deck_y + 0.55, sin(a) * r),
			Vector3(0.09, 0.8, 0.09), Vector3.ZERO, false)
	BuildKit.cylinder(self, body, timber, Vector3(0, deck_y + 0.95, 0),
		top_radius + 0.47, 0.09, Vector3.ZERO, false, 12, top_radius + 0.47)

	# --- iron crown, which rotates with the pulse -------------------------
	_crown = Node3D.new()
	_crown.name = "Crown"
	_crown.position = Vector3(0, deck_y + 1.25, 0)
	add_child(_crown)
	for i in 6:
		var a := TAU * float(i) / 6.0
		BuildKit.box(_crown, null, iron, Vector3(cos(a) * 0.62, 0.35, sin(a) * 0.62),
			Vector3(0.07, 0.95, 0.07), Vector3(cos(a) * 0.22, -a, sin(a) * 0.22), false)
	BuildKit.cylinder(_crown, null, iron, Vector3(0, 0.0, 0), 0.72, 0.1,
		Vector3.ZERO, false, 12, 0.72)

	# --- the crystal ------------------------------------------------------
	_crystal_mat = ShaderMaterial.new()
	_crystal_mat.shader = load("res://shaders/crystal.gdshader")
	var gem := MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = 0.46
	gm.height = 1.25
	gm.radial_segments = 6
	gm.rings = 3
	gem.mesh = gm
	gem.material_override = _crystal_mat
	gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_crystal = Node3D.new()
	_crystal.name = "Crystal"
	_crystal.position = Vector3(0, deck_y + 1.85, 0)
	_crystal.add_child(gem)
	add_child(_crystal)

	_light = OmniLight3D.new()
	_light.name = "BeaconLight"
	_light.position = Vector3(0, deck_y + 1.85, 0)
	_light.light_color = Color(0.55, 0.95, 0.9)
	_light.omni_range = 26.0
	_light.shadow_enabled = false
	add_child(_light)

	# A collision cylinder for the whole shaft, so the player cannot squeeze
	# between the legs and stand inside the tower.
	var core := CylinderShape3D.new()
	core.radius = top_radius * 0.55
	core.height = deck_y
	var cs := CollisionShape3D.new()
	cs.shape = core
	cs.position = Vector3(0, deck_y * 0.5, 0)
	body.add_child(cs)

	# Merge the static structure. The crown and the crystal are excluded
	# because the script rotates them every frame.
	merged_away = BuildKit.merge_by_material(self, [_crown, _crystal, _light])


## A timber between two points, with matching collision.
func _beam(body: StaticBody3D, mat: Material, from: Vector3, to: Vector3, r: float) -> void:
	var mid := (from + to) * 0.5
	var dir := to - from
	var len := dir.length()
	if len < 0.001:
		return
	var basis := Basis()
	var up := dir.normalized()
	var ref := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var xa := ref.cross(up).normalized()
	var za := up.cross(xa).normalized()
	basis = Basis(xa, up, za)
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = len
	mesh.radial_segments = 6
	mesh.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(basis, mid)
	add_child(mi)
	if body:
		var shape := CylinderShape3D.new()
		shape.radius = r
		shape.height = len
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = Transform3D(basis, mid)
		body.add_child(cs)


func _process(delta: float) -> void:
	_t += delta
	# Two beats of different length, so the pulse never settles into an
	# obvious metronome.
	var a := sin(_t * TAU / pulse_period)
	var b := sin(_t * TAU / (pulse_period * 0.37) + 1.1)
	pulse = clampf(0.5 + a * 0.38 + b * 0.12, 0.0, 1.0)
	_crystal_mat.set_shader_parameter("pulse", pulse)
	_light.light_energy = lerpf(1.6, 5.2, pulse)
	_light.omni_range = lerpf(22.0, 30.0, pulse)
	_crown.rotate_y(delta * (0.12 + pulse * 0.20))
	_crystal.rotate_y(delta * -0.55)
	_crystal.position.y += sin(_t * 1.3) * delta * 0.09
	pulsed.emit(pulse)
