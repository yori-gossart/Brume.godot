extends Resource
class_name CharacterAppearance
##
## Who a character is, as a saveable resource (section 8).
##
## This is the foundation the brief asks for, not the final character screen.
## Its job is to be the ONE thing that survives the asset pipeline changing:
## when the Quaternius base characters and modular outfits arrive, the
## catalog behind it is rewritten and these saved appearances still mean the
## same thing.
##
## Two fields are declared and currently INERT — `hairstyle` and
## `hair_color`. The KayKit bodies have no separable hair mesh (the scout's
## head is a hood, the others are one-piece), so there is nothing to drive.
## They are here because removing them now would mean re-authoring every
## saved appearance later, and because pretending they work would be worse.
## `is_fully_supported()` reports the truth about that.

@export var body_type: int = 0
@export var skin_tone: int = AppearanceCatalog.DEFAULT_SKIN
## INERT until a character pack with separable hair is available.
@export var hairstyle: int = 0
## INERT — see above.
@export var hair_color: Color = Color(0.235, 0.176, 0.133)
@export var outfit_variant: int = 0
@export var primary_color: Color = Color(0.702, 0.510, 0.216)
@export var secondary_color: Color = Color(0.376, 0.396, 0.420)


static func make_default() -> CharacterAppearance:
	var a := CharacterAppearance.new()
	a.body_type = AppearanceCatalog.body_index_of("scout")
	a.skin_tone = AppearanceCatalog.DEFAULT_SKIN
	a.outfit_variant = 0
	# Ocre, not green. Section 7.
	a.primary_color = AppearanceCatalog.outfit_color(AppearanceCatalog.DEFAULT_PRIMARY)
	a.secondary_color = AppearanceCatalog.outfit_color(AppearanceCatalog.DEFAULT_SECONDARY)
	return a


func duplicate_appearance() -> CharacterAppearance:
	var a := CharacterAppearance.new()
	a.body_type = body_type
	a.skin_tone = skin_tone
	a.hairstyle = hairstyle
	a.hair_color = hair_color
	a.outfit_variant = outfit_variant
	a.primary_color = primary_color
	a.secondary_color = secondary_color
	return a


func body_scene_path() -> String:
	return str(AppearanceCatalog.body(body_type)["scene"])


## Which fields currently do anything, given the assets actually present.
func is_fully_supported() -> Dictionary:
	return {
		"body_type": true,
		"skin_tone": true,
		"outfit_variant": true,
		"primary_color": true,
		"secondary_color": true,
		"hairstyle": false,     # no separable hair mesh in the KayKit bodies
		"hair_color": false,
	}


## Paint an instantiated character model.
##
## One ShaderMaterial is built per character and applied as a material
## override to its body meshes, so two NPCs sharing a body still get
## independent colours. The hue bands come from the catalog entry for that
## body, because each atlas puts its cloth in a different place.
func apply_to(model: Node3D) -> void:
	if model == null:
		return
	var entry := AppearanceCatalog.body(body_type)
	var tex := _find_albedo(model)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/character_recolor.gdshader")
	mat.set_shader_parameter("albedo_texture", tex)

	var prim: Dictionary = entry["primary"]
	mat.set_shader_parameter("primary_color", primary_color)
	mat.set_shader_parameter("primary_hue", prim["hue"])
	mat.set_shader_parameter("primary_width", prim["width"])
	mat.set_shader_parameter("primary_min_sat", prim["min_sat"])
	mat.set_shader_parameter("primary_min_val", prim.get("min_val", 0.0))

	var sec: Dictionary = entry["secondary"]
	mat.set_shader_parameter("secondary_color", secondary_color)
	mat.set_shader_parameter("secondary_hue", sec["hue"])
	mat.set_shader_parameter("secondary_width", sec["width"])
	mat.set_shader_parameter("secondary_min_sat", sec["min_sat"])
	mat.set_shader_parameter("secondary_min_val", sec.get("min_val", 0.0))

	var skin := AppearanceCatalog.SKIN_BAND
	mat.set_shader_parameter("skin_color", AppearanceCatalog.skin_color(skin_tone))
	mat.set_shader_parameter("skin_hue", skin["hue"])
	mat.set_shader_parameter("skin_width", skin["width"])
	mat.set_shader_parameter("skin_min_val", skin["min_val"])
	mat.set_shader_parameter("skin_max_sat", skin["max_sat"])

	# --- accessories: the outfit variant, such as it is -------------------
	var show: Array = AppearanceCatalog.variant(body_type, outfit_variant).get("show", [])
	var accessories: Dictionary = entry.get("accessories", {})

	for n in _descendants(model):
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		var low := str(mi.name).to_lower()
		# Weapons stay hidden, as in 0.1 — Fog Nomad has no combat.
		var accessory_key := ""
		for key in accessories:
			if low.contains(str(accessories[key]).to_lower()):
				accessory_key = str(key)
				break
		if accessory_key != "":
			mi.visible = show.has(accessory_key)
		if mi.visible:
			mi.material_override = mat


## The atlas this model's meshes actually use, so the recolour shader
## repaints the real texture rather than a guess at its path.
func _find_albedo(model: Node3D) -> Texture2D:
	for n in _descendants(model):
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m is BaseMaterial3D and (m as BaseMaterial3D).albedo_texture:
				return (m as BaseMaterial3D).albedo_texture
	return null


func _descendants(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_descendants(c))
	return out


## A short human description, for the debug HUD and the customisation UI.
func describe() -> String:
	return "%s / %s / %s" % [
		AppearanceCatalog.body(body_type)["name"],
		AppearanceCatalog.SKIN_TONES[clampi(skin_tone, 0, 5)]["name"],
		AppearanceCatalog.variant(body_type, outfit_variant)["name"],
	]
