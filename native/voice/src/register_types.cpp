#include "voice_peer.hpp"
#include <godot_cpp/godot.hpp>
#include <godot_cpp/core/class_db.hpp>
using namespace godot;
void initialize_rally_voice(ModuleInitializationLevel level) { if (level == MODULE_INITIALIZATION_LEVEL_SCENE) ClassDB::register_class<RallyVoicePeer>(); }
void uninitialize_rally_voice(ModuleInitializationLevel level) { (void)level; }
extern "C" {
GDExtensionBool GDE_EXPORT rally_voice_init(const GDExtensionInterface *p_get_proc_address, const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
    GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
    init_obj.register_initializer(initialize_rally_voice); init_obj.register_terminator(uninitialize_rally_voice); init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE); return init_obj.init();
}
}
