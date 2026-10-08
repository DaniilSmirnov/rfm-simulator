extends RefCounted
# Typed simulation state. No UI controls, transport or rendering logic.
var in_car: bool = true
var heading: float = 0.0
var view_yaw: float = 0.0
var view_pitch: float = -0.12
var speed: float = 0.0
var condition: float = 100.0
var walker: Vector3 = Vector3.ZERO
var beers: int = 0
var eat_time: float = -1.0
var eat_committed: bool = false
var drink_time: float = -1.0
var drink_committed: bool = false
var seated: bool = false
var jump_height: float = 0.0
var jump_velocity: float = 0.0
