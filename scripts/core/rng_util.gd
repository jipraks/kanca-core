class_name RngUtil
extends RefCounted

## Randomness helpers that draw from a caller-supplied generator.
##
## Array.shuffle() uses the engine's global RNG, which makes any seeded generator
## passed around alongside it decorative. That is not a crash, it is worse: it
## silently takes the decision away from the mini-game that thought it owned it.
## Five Warung customers in a row asking for the same fruit is how it showed up.


static func shuffle(items: Array[String], rng: RandomNumberGenerator) -> void:
	for i: int in range(items.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: String = items[i]
		items[i] = items[j]
		items[j] = swap
