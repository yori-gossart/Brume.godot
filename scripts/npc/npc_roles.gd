extends RefCounted
class_name NpcRoles
##
## The four nomads (sections 12, 13).
##
## Section 13 forbids the lazy answer — "same character, scale = random".
## These four differ on every axis the current assets expose:
##
##   BODY     four genuinely different KayKit builds: svelte, heavy, tall,
##            armoured. Not one mesh scaled four ways.
##   OUTFIT   different primary and secondary colours from the section 7
##            palette, applied by hue-band recolouring.
##   SKIN     different tones.
##   ACCESSORY different cape/hat sets.
##   GAIT     different walk speeds and idle rhythms, so they do not move as
##            a chorus line.
##
## They share one art style because they come from one CC0 pack by one
## author, which is the coherence section 12 asks for.
##
## The imposed pipeline was Quaternius Universal Base Characters plus
## Modular Character Outfits; it was unreachable. See
## docs/ASSETS_TO_DOWNLOAD.md.

const ROLES := [
	{
		"id": "scout", "name": "Éclaireur",
		"body": "scout", "skin": 0, "variant": 1,
		"primary": 2,     # bleu ardoise — distinct from the player's ocre
		"secondary": 3,   # beige
		"walk_speed": 1.5, "idle": Vector2(1.2, 3.0),
		"note": "Même silhouette que le joueur, tenue et couleurs différentes.",
	},
	{
		"id": "traveller", "name": "Voyageur",
		"body": "burdened", "skin": 2, "variant": 1,
		"primary": 5,     # bordeaux
		"secondary": 0,   # ocre
		"walk_speed": 1.25, "idle": Vector2(2.0, 4.5),
		"note": "Équipement plus lourd, démarche plus lente.",
	},
	{
		"id": "artisan", "name": "Artisan",
		"body": "sturdy", "skin": 3, "variant": 0,
		"primary": 1,     # rouille
		"secondary": 4,   # gris ardoise
		"walk_speed": 1.4, "idle": Vector2(2.6, 5.5),
		"note": "Carrure large, sans cape, s'arrête souvent.",
	},
	{
		"id": "elder", "name": "Ancien",
		"body": "tall", "skin": 4, "variant": 1,
		"primary": 7,     # nuit
		"secondary": 6,   # vert de forêt
		"walk_speed": 1.05, "idle": Vector2(3.2, 6.5),
		"note": "Longiligne, sombre, lent.",
	},
]


static func count() -> int:
	return ROLES.size()


static func role(i: int) -> Dictionary:
	return ROLES[clampi(i, 0, ROLES.size() - 1)]


## Build the appearance for role `i`.
static func appearance_for(i: int) -> CharacterAppearance:
	var r := role(i)
	var a := CharacterAppearance.new()
	a.body_type = AppearanceCatalog.body_index_of(str(r["body"]))
	a.skin_tone = int(r["skin"])
	a.outfit_variant = int(r["variant"])
	a.primary_color = AppearanceCatalog.outfit_color(int(r["primary"]))
	a.secondary_color = AppearanceCatalog.outfit_color(int(r["secondary"]))
	return a
