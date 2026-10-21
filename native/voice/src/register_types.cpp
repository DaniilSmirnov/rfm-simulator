#include "data_link.hpp"
#include "voice_encoder.hpp"
#include "voice_link.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>

#include <rtc/rtc.hpp>

#include <chrono>

using namespace godot;

static void initialize_rally_voice(ModuleInitializationLevel level) {
	if (level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
	GDREGISTER_CLASS(RallyVoiceEncoder);
	GDREGISTER_CLASS(RallyVoiceLink);
	GDREGISTER_CLASS(RallyDataLink);
}

static void uninitialize_rally_voice(ModuleInitializationLevel level) {
	if (level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
	// Join libdatachannel's threads before the library is unloaded.
	try {
		rtc::Cleanup().wait_for(std::chrono::seconds(2));
	} catch (...) {
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT rally_voice_init(GDExtensionInterfaceGetProcAddress get_proc_address, GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
	GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
	init.register_initializer(initialize_rally_voice);
	init.register_terminator(uninitialize_rally_voice);
	init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init.init();
}
}
