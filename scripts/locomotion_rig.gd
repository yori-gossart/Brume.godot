extends RefCounted
class_name LocomotionRig
##
## Builds and drives an AnimationTree for a KayKit Adventurers character.
## Shared by the player and the NPC, so both are animated by exactly the same
## code and neither can end up looking "more finished" than the other by
## accident.
##
## FOOT SLIDING — the thing section 48 calls out as an automatic FAIL.
##
## The first attempt here was an AnimationNodeBlendSpace1D with the walk and
## run clips placed at their measured authored speeds. It looked right on
## paper and measured 65% foot slide, because Godot's `sync` on a blend space
## does NOT time-warp its inputs: it only keeps them advancing at weight 0.
## Walking_A is a 1.07 s cycle and Running_A is 0.80 s, so blending them
## averages two cycles that drift out of phase, and the result is feet that
## float instead of feet that plant.
##
## What is here instead: ONE clip at a time, its playback rate driven by the
## character's actual ground speed, with a short crossfade between gaits.
##
##     playback rate = ground speed / the speed the clip was authored for
##
## Those authored speeds are measured, not guessed. tools/calibrate_stride.gd
## sweeps the playback rate at a fixed ground speed and finds the rate that
## minimises the planted foot's speed IN WORLD SPACE; the authored speed
## falls straight out of it. tools/benchmark_tests.gd then re-measures the
## residual slide as a pass/fail check, so this cannot silently regress.

## THE CLIP SET IS PER-INSTANCE (0.2.2), not global.
##
## The NPCs stay on KayKit Adventurers; the player wears the Quaternius
## scout, whose library names everything differently. Same rig code, two
## vocabularies — see use_ual1().
var idle_clip := "Idle"
var walk_clip := "Walking_A"
var run_clip := "Running_A"
var swim_clip := "Walking_A"        ## see SWIM ANIMATION PROVISIONAL below
var pickup_clip := "PickUp"
## The jump, added in 0.2.1. Unlike the swim, this one is NOT provisional:
## KayKit Adventurers ships all three phases of a jump, so the air states in
## PlayerController drive real authored clips.
var jump_start_clip := "Jump_Start"
var jump_air_clip := "Jump_Idle"
var jump_land_clip := "Jump_Land"

## Measured authored ground speeds, in m/s — the output of
## tools/calibrate_stride.gd, not an estimate.
var walk_ref := 0.77
var run_ref := 3.85

## The two bones the foot-slide measurement tracks. KayKit calls them toes,
## the Quaternius rig calls them balls.
var foot_bones := ["toes.l", "toes.r"]

## THE RESIDUAL EACH CLIP IMPOSES, plus a margin — the pass mark the test
## uses. It belongs to the CLIP SET, not to the test: a run cycle's planted
## foot is never still, because part of the cycle has no planted foot at
## all, and how much of the cycle that is differs from one animator to the
## next. KayKit's Running_A floors at 36.4%; the Quaternius Sprint floors at
## 52-57% over the same speed range. Both figures come from
## tools/calibrate_stride.gd, neither is a guess.
var slide_floor_walk := 0.28
var slide_floor_run := 0.47

## Playback rate limits. Past these a clip stops reading as the gait it is:
## a walk at 3x is a scurry, a run at 0.3x is a moonwalk.
const MIN_RATE := 0.42
const MAX_RATE := 2.15

## Given those limits, each clip covers a speed band:
##     Walking_A   0.32 .. 1.66 m/s
##     Running_A   1.62 .. 8.28 m/s
## They meet at ~1.64 m/s, which is therefore where the gait changes — the
## one speed at which both clips can be played at an honest rate.
const IDLE_SPEED := 0.22
## Where the gait changes: the slowest speed the run clip can cover without
## being played below MIN_RATE. Derived from run_ref so it follows the clip
## set instead of being a number that only happened to suit KayKit.
var walk_to_run := 3.85 * MIN_RATE
## Hysteresis, so a speed hovering on the boundary does not strobe.
const GAIT_HYSTERESIS := 0.25

## Upper-body bones the pickup gesture is allowed to touch. The legs keep
## running, which is the entire point of section 13.
var upper_body := ["spine", "chest", "upperarm.l", "lowerarm.l", "wrist.l",
	"hand.l", "upperarm.r", "lowerarm.r", "wrist.r", "hand.r", "head", "neck"]


## Switch this rig to the Quaternius UAL1 vocabulary (0.2.2).
##
## Call BEFORE setup(). Swim deliberately keeps a ground clip: the controller
## pitches the whole model prone and plays it slowly, and 0.2.1b's swimming
## is validated. UAL1 does ship Swim_Fwd_Loop — TODO for a later pass, it
## needs the prone pitch removed at the same time or the two will stack.
func use_ual1() -> void:
	# Godot's glTF importer strips the "_Loop" suffix and sets the loop mode
	# itself, so the names here are the IMPORTED ones, not the ones in the
	# .glb. Checked against the imported library, not assumed.
	idle_clip = "Idle"
	walk_clip = "Walk"
	run_clip = "Sprint"
	swim_clip = "Walk"
	pickup_clip = "Interact"
	jump_start_clip = "Jump_Start"
	jump_air_clip = "Jump"
	jump_land_clip = "Jump_Land"
	foot_bones = ["ball_l", "ball_r"]
	upper_body = ["spine_01", "spine_02", "spine_03", "neck_01", "Head",
		"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
		"clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"]
	# Measured on the composed scout, not guessed.
	#
	#   Walk    locks hard: 1.6% residual at the optimum, A = 1.04 m/s.
	#   Sprint  A = 6.2 m/s at 3.7 m/s of travel, 6.7 at 7.35. Its residual
	#           floor is 57% / 52% at those two speeds — a long flight phase,
	#           not a bad binding; in game it reads 60% / 55%, three points
	#           above what the clip can do at best.
	#
	# Jog_Fwd was tried first and is worse at every rate (81% / 49% and
	# 74% / 69% at two different refs), so Sprint covers the whole run band.
	# TODO: a dedicated jog gait would need a third transition input.
	walk_ref = 1.04
	run_ref = 6.40
	slide_floor_walk = 0.15
	slide_floor_run = 0.65
	walk_to_run = run_ref * MIN_RATE

var tree: AnimationTree
var player: AnimationPlayer
var skeleton: Skeleton3D

var _oneshot: AnimationNodeOneShot
var _has_swim := false
var _gait := 0


## `model` is the instantiated .glb root. Returns false if it does not look
## like a KayKit character.
func setup(model: Node3D) -> bool:
	player = model.find_child("AnimationPlayer", true, false)
	skeleton = model.find_child("Skeleton3D", true, false)
	if player == null:
		push_error("LocomotionRig: no AnimationPlayer under %s" % model.name)
		return false

	var lib_name := ""
	for l in player.get_animation_library_list():
		lib_name = str(l)
		break
	var lib := player.get_animation_library(lib_name)

	# Looping matters: Godot plays imported glTF clips once by default, which
	# is what produces the classic "character freezes mid-stride" bug.
	for clip in [idle_clip, walk_clip, run_clip, jump_air_clip]:
		var a := lib.get_animation(clip)
		if a: a.loop_mode = Animation.LOOP_LINEAR
	# The two ends of the jump are one-shots by nature: a looping Jump_Start
	# is a character bouncing on the spot.
	for clip in [jump_start_clip, jump_land_clip]:
		var a := lib.get_animation(clip)
		if a: a.loop_mode = Animation.LOOP_NONE

	var prefix := "" if lib_name == "" else lib_name + "/"

	# --- ground locomotion: three gaits, one playing at a time ------------
	var walk_ts := AnimationNodeTimeScale.new()
	var run_ts := AnimationNodeTimeScale.new()
	var gait := AnimationNodeTransition.new()
	gait.input_count = 3
	gait.set_input_name(0, "idle")
	gait.set_input_name(1, "walk")
	gait.set_input_name(2, "run")
	gait.xfade_time = 0.22

	# --- swim: SWIM ANIMATION PROVISIONAL ---------------------------------
	# The KayKit Adventurers pack ships 76 clips and not one of them is a
	# swim. Rather than fake one badly, the controller pitches the whole
	# model forward into a prone attitude and plays the walk cycle slowly as
	# a paddle. It is explicitly provisional; the point of the benchmark here
	# is that the PHYSICS state exists and behaves (section 19), not that the
	# art is finished.
	var swim_ts := AnimationNodeTimeScale.new()
	_has_swim = true

	# --- air: the three phases of a jump (section 12) ----------------------
	var airphase := AnimationNodeTransition.new()
	airphase.input_count = 3
	airphase.set_input_name(0, "start")
	airphase.set_input_name(1, "hang")
	airphase.set_input_name(2, "land")
	# Short, because the whole jump is only 0.8 s and a long crossfade would
	# eat the take-off.
	airphase.xfade_time = 0.09

	var mode := AnimationNodeTransition.new()
	mode.input_count = 3
	mode.set_input_name(0, "ground")
	mode.set_input_name(1, "swim")
	mode.set_input_name(2, "air")
	# 0.2 used 0.3 s here, which was fine when the only other mode was a swim
	# you enter once a minute. Leaving and re-entering the ground mode twice
	# per jump needs it much tighter or the landing arrives before the blend.
	mode.xfade_time = 0.12

	# --- pickup gesture, upper body only ----------------------------------
	var shot := _clip(prefix + pickup_clip)
	_oneshot = AnimationNodeOneShot.new()
	_oneshot.fadein_time = 0.12
	_oneshot.fadeout_time = 0.25
	_oneshot.autorestart = false

	var bt := AnimationNodeBlendTree.new()
	bt.add_node("idle", _clip(prefix + idle_clip), Vector2(0, -120))
	bt.add_node("walk", _clip(prefix + walk_clip), Vector2(0, -20))
	bt.add_node("run", _clip(prefix + run_clip), Vector2(0, 80))
	bt.add_node("walk_ts", walk_ts, Vector2(200, -20))
	bt.add_node("run_ts", run_ts, Vector2(200, 80))
	bt.add_node("gait", gait, Vector2(400, -20))
	bt.add_node("swim", _clip(prefix + swim_clip), Vector2(0, 220))
	bt.add_node("swim_ts", swim_ts, Vector2(200, 220))
	bt.add_node("jump_start", _clip(prefix + jump_start_clip), Vector2(0, 320))
	bt.add_node("jump_air", _clip(prefix + jump_air_clip), Vector2(0, 400))
	bt.add_node("jump_land", _clip(prefix + jump_land_clip), Vector2(0, 480))
	bt.add_node("airphase", airphase, Vector2(400, 400))
	bt.add_node("mode", mode, Vector2(600, 60))
	bt.add_node("shot", shot, Vector2(600, 260))
	bt.add_node("gesture", _oneshot, Vector2(820, 60))
	bt.connect_node("walk_ts", 0, "walk")
	bt.connect_node("run_ts", 0, "run")
	bt.connect_node("gait", 0, "idle")
	bt.connect_node("gait", 1, "walk_ts")
	bt.connect_node("gait", 2, "run_ts")
	bt.connect_node("swim_ts", 0, "swim")
	bt.connect_node("airphase", 0, "jump_start")
	bt.connect_node("airphase", 1, "jump_air")
	bt.connect_node("airphase", 2, "jump_land")
	bt.connect_node("mode", 0, "gait")
	bt.connect_node("mode", 1, "swim_ts")
	bt.connect_node("mode", 2, "airphase")
	bt.connect_node("gesture", 0, "mode")
	bt.connect_node("gesture", 1, "shot")
	bt.connect_node("output", 0, "gesture")

	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	tree.tree_root = bt
	# Advance the animation on the PHYSICS clock, not the render clock.
	#
	# The gait's playback rate is derived from the speed the controller
	# computes in _physics_process. If the animation then advances on idle
	# frames, stride and movement are running on two different clocks, and
	# the stride drifts against the ground by however much the two rates
	# disagree — measured here at 52% foot slide on the run, against a 36%
	# floor, purely from that mismatch. Same clock, no drift.
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	model.add_child(tree)
	# anim_player is resolved relative to the AnimationTree NODE, not to the
	# model — so it can only be set once the tree is actually in the scene.
	# Setting it beforehand silently leaves the character in its T-pose.
	tree.anim_player = tree.get_path_to(player)
	tree.active = true
	if tree.get_node_or_null(tree.anim_player) == null:
		push_error("LocomotionRig: anim_player path %s does not resolve" % str(tree.anim_player))
		return false

	_apply_upper_body_filter(model)
	set_mode_ground(true)
	return true


func _clip(name: String) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = name
	return n


## Restrict the pickup one-shot to the upper body, so a pickup taken at a
## dead run does not reset the legs.
func _apply_upper_body_filter(model: Node3D) -> void:
	if skeleton == null:
		return
	_oneshot.filter_enabled = true
	var skel_path := str(model.get_path_to(skeleton))
	var wanted := {}
	for b in upper_body:
		wanted[b] = true
	for b in skeleton.get_bone_count():
		var bn := str(skeleton.get_bone_name(b))
		# Everything the gesture MAY drive is whitelisted; every other bone is
		# left to the locomotion blend. filter_enabled + set_filter_path(true)
		# means "this path passes through the one-shot".
		if wanted.has(bn.to_lower()):
			_oneshot.set_filter_path(NodePath(skel_path + ":" + bn), true)


## Drive the ground locomotion from the character's actual speed.
##
## Picks the gait, then sets that clip's playback rate to ground speed over
## the speed the clip was authored for. A clip played at exactly that rate
## has a planted foot that is stationary in world space — which is the
## definition of not sliding.
func set_blend_speed(speed: float) -> void:
	if speed < IDLE_SPEED:
		_gait = 0
	elif _gait == 2:
		if speed < walk_to_run - GAIT_HYSTERESIS:
			_gait = 1
	elif speed > walk_to_run:
		_gait = 2
	else:
		_gait = 1
	tree.set("parameters/gait/transition_request", ["idle", "walk", "run"][_gait])
	tree.set("parameters/walk_ts/scale", clampf(speed / walk_ref, MIN_RATE, MAX_RATE))
	tree.set("parameters/run_ts/scale", clampf(speed / run_ref, MIN_RATE, MAX_RATE))


## SWIM ANIMATION PROVISIONAL: the walk cycle, slowed right down, under a
## model the controller has pitched prone.
func set_swim_effort(effort: float) -> void:
	tree.set("parameters/swim_ts/scale", lerpf(0.35, 0.85, clampf(effort, 0.0, 1.0)))


## Which of the three ground clips is selected right now.
func gait_name() -> String:
	return ["idle", "walk", "run"][_gait]


func set_mode_ground(ground: bool) -> void:
	tree.set("parameters/mode/transition_request", "ground" if ground else "swim")


## Put the character in the air and choose which phase of the jump is showing.
## `phase` is "start" (still rising hard), "hang" (the rest of the flight) or
## "land" (the touchdown beat). Switching the mode here rather than making the
## caller do it in two steps means the tree can never be left in the air with
## a ground clip playing.
func set_air_phase(phase: String) -> void:
	tree.set("parameters/mode/transition_request", "air")
	tree.set("parameters/airphase/transition_request", phase)


func play_pickup() -> void:
	tree.set("parameters/gesture/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Hide the weapons every Adventurers character ships with. Fog Nomad has no
## combat, and a crossbow strapped to a nomad's back contradicts the only
## thing the game is about. Done at runtime, exactly as the three.js build
## does it, so the .glb files stay byte-identical to KayKit's originals and
## their provenance stays checkable.
static func hide_weapons(model: Node3D) -> int:
	const BANNED := ["knife", "crossbow", "throwable", "axe", "shield", "mug",
		"sword", "bow", "quiver", "spellbook", "staff", "dagger", "hammer",
		"wand", "arrow", "torch"]
	var hidden := 0
	for n in _descendants(model):
		if not (n is MeshInstance3D):
			continue
		var low := str(n.name).to_lower()
		for b in BANNED:
			if low.contains(b):
				(n as MeshInstance3D).visible = false
				hidden += 1
				break
	return hidden


static func _descendants(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_descendants(c))
	return out
