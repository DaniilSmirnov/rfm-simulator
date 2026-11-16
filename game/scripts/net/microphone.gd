extends RefCounted
# Which microphone the radio records from. Godot opens one input device for
# the whole game (AudioServer.input_device), so the choice reaches every
# AudioStreamMicrophone: the radio's and any later one. "Default" follows the
# system's choice. A saved device that is no longer plugged in falls back to it.
# The browser build records through the page (web/voice-chat.js), where the
# browser picks the microphone, so the game offers no choice there.
const DEFAULT = "Default"

static func available() -> bool:
	return not OS.has_feature("web") and bool(ProjectSettings.get_setting("audio/driver/enable_input", false))

# The system default first, then every input the audio driver reports.
static func devices() -> Array[String]:
	var list: Array[String] = [DEFAULT]
	if available():
		for device in AudioServer.get_input_device_list():
			if str(device) != DEFAULT and not str(device) in list:
				list.append(str(device))
	return list

# Switches the input to the device; returns the one actually in use.
static func apply(device: String) -> String:
	var chosen = device if device in devices() else DEFAULT
	if available() and AudioServer.input_device != chosen:
		AudioServer.input_device = chosen
	return chosen
