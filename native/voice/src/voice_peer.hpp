#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {
class RallyVoicePeer final : public RefCounted {
    GDCLASS(RallyVoicePeer, RefCounted)
    bool active = false;
protected:
    static void _bind_methods();
public:
    Error start(const String &peer_id, const String &session, const String &ice_json);
    void stop();
    void set_push_to_talk(bool enabled);
    bool is_active() const { return active; }
    String poll_signal();
    Error accept_signal(const String &from, const String &payload);
};
}
