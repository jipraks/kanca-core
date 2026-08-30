class_name MovementControl
extends Control

## What the hub asks of whatever is steering the child (PLAN.md §7.1).
##
## Exists because §16.3 leaves movement controls open: directional buttons are
## the specified default, and a virtual joystick "may be tested as an
## alternative — but only after directional buttons are working and only with
## real children". Both implement this, so swapping between them for a session
## with children is a one-line change in hub.tscn rather than a rewrite.

signal direction_changed(direction: Vector2)


## Current input as a screen-space vector, with -Y meaning away from the camera.
## The player controller polls this each frame — movement input is the one thing
## §15 allows in _process.
func get_direction() -> Vector2:
	return Vector2.ZERO


## Drops any held input. A finger that leaves the screen, or the app losing focus
## mid-hold, must not leave the child walking into a fence forever.
func release_all() -> void:
	pass
