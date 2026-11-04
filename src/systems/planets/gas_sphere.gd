class_name GasSphere
extends PlanetSphere
## A gas giant as a real ball (the ringed giant, content/core/planets/ringed_giant.json):
## the same kind of ball as the home planet and the asteroid (PlanetSphere), so you
## fly round it, gravity pulls toward its centre and "up" turns with it. Its
## radius is the deck's level: the town floats on a deck on top (PlatformWorld),
## and the cloud tops lie `depth` metres below it all the way round, smooth.
## Nothing there holds you up: a ship that goes down into the clouds is lost
## (WorldGround.lethal_at), and a person who falls off the deck dies on the way
## down (PlatformWorld).
##
## Settings: the gas_ball type's "surface" in content/core/planets/types.json.

var depth := 120.0


func _init(r: float = 3500.0, surface: Dictionary = {}) -> void:
	super._init(r)
	depth = float(surface.get("depth", depth))
	flat_radius = float(surface.get("flat_radius", 200.0))
	up_blend = float(surface.get("up_blend", 300.0))


## The cloud tops: the same height everywhere (no plateau under the town: it floats).
func elevation(_dir: Vector3, _grow: float = 2.0) -> float:
	return -depth
