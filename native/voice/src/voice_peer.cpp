#include "voice_peer.hpp"
#include <godot_cpp/core/class_db.hpp>

using namespace godot;
void RallyVoicePeer::_bind_methods() {
    ClassDB::bind_method(D_METHOD("start", "peer_id", "session", "ice_json"), &RallyVoicePeer::start);
    ClassDB::bind_method(D_METHOD("stop"), &RallyVoicePeer::stop);
    ClassDB::bind_method(D_METHOD("set_push_to_talk", "enabled"), &RallyVoicePeer::set_push_to_talk);
    ClassDB::bind_method(D_METHOD("is_active"), &RallyVoicePeer::is_active);
    ClassDB::bind_method(D_METHOD("poll_signal"), &RallyVoicePeer::poll_signal);
    ClassDB::bind_method(D_METHOD("accept_signal", "from", "payload"), &RallyVoicePeer::accept_signal);
}
Error RallyVoicePeer::start(const String &, const String &, const String &) { active = true; return OK; }
void RallyVoicePeer::stop() { active = false; }
void RallyVoicePeer::set_push_to_talk(bool) {}
String RallyVoicePeer::poll_signal() { return String(); }
Error RallyVoicePeer::accept_signal(const String &, const String &) { return ERR_UNAVAILABLE; }
