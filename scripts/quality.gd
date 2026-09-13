extends Node
##
## Autoload. Two graphics presets, switchable at runtime from the debug HUD.
##
## The benchmark brief asks for exactly two levels (section 35). Everything
## that costs frame time on a phone reads its budget from here and reacts to
## [signal changed], so flipping the preset is instant and visible.

signal changed(level: int)

enum Level { HIGH, LOW }

var level: int = Level.HIGH:
	set(v):
		v = clampi(v, 0, 1)
		if v == level:
			return
		level = v
		changed.emit(level)

func is_low() -> bool:
	return level == Level.LOW

func toggle() -> void:
	level = Level.LOW if level == Level.HIGH else Level.HIGH

func level_name() -> String:
	return "HIGH" if level == Level.HIGH else "LOW"

## Fraction of the scattered vegetation that stays visible.
func vegetation_ratio() -> float:
	return 1.0 if level == Level.HIGH else 0.55

## Multiplier applied to every fog particle emitter's amount.
func particle_ratio() -> float:
	return 1.0 if level == Level.HIGH else 0.3

## How many fog curtain layers to draw.
func fog_layers() -> int:
	return 3 if level == Level.HIGH else 2

## Shadow range in metres for the sun. 0 disables shadows entirely.
func shadow_distance() -> float:
	return 55.0 if level == Level.HIGH else 26.0

func shadows_enabled() -> bool:
	return true

## Whether small props (grass tufts, water plants, pebbles) are drawn.
func small_props() -> bool:
	return level == Level.HIGH
