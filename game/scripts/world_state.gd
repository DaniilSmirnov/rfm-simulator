extends RefCounted
# Typed simulation state. No UI controls, transport or rendering logic.
var cooking: bool = false
var cook_time: float = 0.0
var grill_servings: int = 10
var eaten: bool = false
var racing: bool = false
var passed: int = 0
var helped: int = 0
var elapsed: float = 0.0
var has_chairs: bool = false
var personal_chairs: Dictionary = {}
var personal_flags: Dictionary = {}
var recovery_links: Array = []
var recovery_helpers: int = 0
