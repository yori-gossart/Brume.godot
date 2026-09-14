extends RefCounted
class_name AppearanceCatalog
##
## The options a character can be built from (sections 5-8).
##
## HONEST NOTE ABOUT WHAT THIS IS. The imposed pipeline for 0.2 was
## Quaternius Universal Base Characters plus Modular Character Outfits, which
## would make body, outfit and hair a matter of swapping meshes. Those packs
## could not be downloaded (see docs/ASSETS_TO_DOWNLOAD.md), so this catalog
## is built on the four licence-verified KayKit bodies the project already
## owns, and outfit colour is done by hue-band recolouring in the shader
## rather than by changing clothes.
##
## What that means in practice:
##   body_type       REAL — four genuinely different builds
##   skin_tone       REAL — recoloured, 6 tones
##   primary_color   REAL — 8 colours, green demoted to one option among many
##   secondary_color REAL — 8 colours
##   outfit_variant  REAL but shallow — accessory sets (cape, hat) per body
##   hairstyle       INERT — these models have no separable hair mesh
##   hair_color      INERT — same reason
##
## The inert fields are defined anyway, because CharacterAppearance is meant
## to be the thing that survives the asset swap. When the Quaternius packs
## land, this catalog changes and the saved appearances do not.
##
## HUE BANDS ARE MEASURED, NOT GUESSED. Each body's numbers below come from
## clustering its actual atlas — see the table in docs/ART_DIRECTION_0.2.md.

## --- bodies --------------------------------------------------------------
const BODIES := [
	{
		"id": "scout", "name": "Éclaireur",
		"scene": "res://assets/characters/player_hooded_scout.glb",
		"build": "svelte",
		# The green hood sits alone at H 152-164 deg, S 0.87-1.00. Nothing
		# else in this atlas is within 25 degrees of it at that saturation,
		# which is what makes repainting it surgical.
		"primary": {"hue": 0.437, "width": 0.050, "min_sat": 0.55, "min_val": 0.0},
		"secondary": {"hue": 0.189, "width": 0.045, "min_sat": 0.45, "min_val": 0.0},
		"accessories": {"cape": "Cape"},
		"variants": [
			{"name": "Léger", "show": []},
			{"name": "Cape de route", "show": ["cape"]},
		],
	},
	{
		"id": "sturdy", "name": "Robuste",
		"scene": "res://assets/characters/npc_sturdy.glb",
		"build": "heavy",
		# Steel-blue cloth, H ~200-210 deg.
		"primary": {"hue": 0.567, "width": 0.048, "min_sat": 0.34, "min_val": 0.0},
		"secondary": {"hue": 0.097, "width": 0.040, "min_sat": 0.60, "min_val": 0.60},
		"accessories": {"cape": "Cape", "hat": "Hat"},
		"variants": [
			{"name": "Sans cape", "show": []},
			{"name": "Chargé", "show": ["cape", "hat"]},
		],
	},
	{
		"id": "tall", "name": "Longiligne",
		"scene": "res://assets/characters/npc_tall.glb",
		"build": "tall",
		# Deep violet robe, H ~244 deg.
		"primary": {"hue": 0.678, "width": 0.052, "min_sat": 0.32, "min_val": 0.0},
		# Magenta trim, H ~334 deg, very saturated.
		"secondary": {"hue": 0.928, "width": 0.042, "min_sat": 0.60, "min_val": 0.0},
		"accessories": {"cape": "Cape"},
		"variants": [
			{"name": "Robe courte", "show": []},
			{"name": "Robe longue", "show": ["cape"]},
		],
	},
	{
		"id": "burdened", "name": "Équipé",
		"scene": "res://assets/characters/npc_burdened.glb",
		"build": "armoured",
		# Red surcoat, H ~359 deg. It shares its hue neighbourhood with the
		# leather (H 15 deg), so the two are separated by VALUE: the surcoat
		# sits at V 0.95, the leather at V 0.61.
		"primary": {"hue": 0.997, "width": 0.030, "min_sat": 0.48, "min_val": 0.74},
		# Gold, H ~48 deg — clear of both skin (23) and leather (15).
		"secondary": {"hue": 0.133, "width": 0.032, "min_sat": 0.55, "min_val": 0.0},
		"accessories": {"cape": "Cape"},
		"variants": [
			{"name": "Sans cape", "show": []},
			{"name": "Paré", "show": ["cape"]},
		],
	},
]

## --- skin --------------------------------------------------------------
## The atlas skin cluster is H 21-26 deg, S 0.31-0.53, V 0.78-0.97; it is
## told apart from leather by brightness, hence the value floor in the shader.
const SKIN_BAND := {"hue": 0.065, "width": 0.036, "min_val": 0.72, "max_sat": 0.60}

const SKIN_TONES := [
	{"name": "Clair", "color": Color(0.960, 0.784, 0.655)},
	{"name": "Doré", "color": Color(0.898, 0.702, 0.518)},
	{"name": "Olive", "color": Color(0.780, 0.600, 0.427)},
	{"name": "Ambre", "color": Color(0.651, 0.463, 0.322)},
	{"name": "Brun", "color": Color(0.478, 0.329, 0.231)},
	{"name": "Ébène", "color": Color(0.322, 0.216, 0.161)},
]

## --- outfit colours (section 7) ----------------------------------------
## Green is present, and is one option among eight. It is no longer the
## default, and no longer the colour anything starts as.
const OUTFIT_COLORS := [
	{"name": "Ocre", "color": Color(0.702, 0.510, 0.216)},
	{"name": "Rouille", "color": Color(0.573, 0.278, 0.157)},
	{"name": "Bleu ardoise", "color": Color(0.318, 0.404, 0.478)},
	{"name": "Beige", "color": Color(0.745, 0.678, 0.545)},
	{"name": "Gris ardoise", "color": Color(0.376, 0.396, 0.420)},
	{"name": "Bordeaux", "color": Color(0.376, 0.153, 0.180)},
	{"name": "Vert de forêt", "color": Color(0.286, 0.396, 0.263)},
	{"name": "Nuit", "color": Color(0.204, 0.224, 0.290)},
]

## Default appearance for a new scout. Deliberately ocre — section 7.
const DEFAULT_PRIMARY := 0
const DEFAULT_SECONDARY := 4
const DEFAULT_SKIN := 1


static func body(index: int) -> Dictionary:
	return BODIES[clampi(index, 0, BODIES.size() - 1)]


static func body_index_of(id: String) -> int:
	for i in BODIES.size():
		if BODIES[i]["id"] == id:
			return i
	return 0


static func skin_color(index: int) -> Color:
	return SKIN_TONES[clampi(index, 0, SKIN_TONES.size() - 1)]["color"]


static func outfit_color(index: int) -> Color:
	return OUTFIT_COLORS[clampi(index, 0, OUTFIT_COLORS.size() - 1)]["color"]


static func variant(body_index: int, variant_index: int) -> Dictionary:
	var v: Array = body(body_index)["variants"]
	return v[clampi(variant_index, 0, v.size() - 1)]
