extends RefCounted
class_name AnimalSpecies
##
## The animals, as data (sections 37, 38).
##
## ===================== ANIMAL_ASSET_BLOCKED =========================
## The imposed pack — Quaternius Ultimate Animated Animal Pack, for a deer
## and a fox — could not be downloaded: quaternius.com answers 403 at the
## network policy, and Quaternius has no official GitHub mirror. Details and
## the exact download list are in docs/ASSETS_TO_DOWNLOAD.md.
##
## So both species below are still PLACEHOLDERS, labelled as such in the
## world. What this table adds over 0.1 is that they are now DATA: build
## proportions, gait, senses and flight behaviour are values, not constants
## buried in a script. Dropping the real models in becomes a matter of
## adding a `scene` path to each row.
##
## The behaviour is real and is tested: IDLE -> WALK -> FLEE, navigation
## around trunks and boulders, and flight from both the player and the Brume.
## ====================================================================

const SPECIES := [
	{
		"id": "browser", "name": "Herbivore",      # stands in for DEER / STAG
		"placeholder": true,
		"scene": "",                                # <- real model goes here
		"body_color": Color(0.494, 0.396, 0.290),
		# Tall, long-legged, narrow: reads as a browsing animal at distance.
		"body_length": 0.95, "body_radius": 0.25, "leg_length": 0.62,
		"neck_length": 0.46, "shoulder_height": 0.86, "ear_length": 0.26,
		"tail_length": 0.18,
		"walk_speed": 1.35, "flee_speed": 6.2, "turn_speed": 5.5,
		"flee_radius": 16.0, "calm_radius": 30.0, "fog_fear": 26.0,
		"idle": Vector2(2.0, 5.0), "stride": 0.82,
		# Browsers lift their heads to check for danger between mouthfuls.
		"graze": true,
	},
	{
		"id": "prowler", "name": "Petit prédateur",  # stands in for FOX / WOLF
		"placeholder": true,
		"scene": "",
		"body_color": Color(0.541, 0.310, 0.176),
		# Low, compact, long tail.
		"body_length": 0.66, "body_radius": 0.17, "leg_length": 0.32,
		"neck_length": 0.24, "shoulder_height": 0.44, "ear_length": 0.17,
		"tail_length": 0.42,
		"walk_speed": 1.9, "flee_speed": 7.4, "turn_speed": 8.0,
		"flee_radius": 11.0, "calm_radius": 22.0, "fog_fear": 20.0,
		"idle": Vector2(0.8, 2.4), "stride": 0.5,
		"graze": false,
	},
]


static func count() -> int:
	return SPECIES.size()


static func get_species(i: int) -> Dictionary:
	return SPECIES[clampi(i, 0, SPECIES.size() - 1)]


static func index_of(id: String) -> int:
	for i in SPECIES.size():
		if SPECIES[i]["id"] == id:
			return i
	return 0


## True while no real model has been supplied for this species.
static func is_placeholder(i: int) -> bool:
	return bool(get_species(i).get("placeholder", true)) or str(get_species(i).get("scene", "")).is_empty()
