#ifndef FROSTLINE_NATIVE_HELLO_H
#define FROSTLINE_NATIVE_HELLO_H

#include <godot_cpp/classes/ref_counted.hpp>

namespace godot {

// Smoke-test class for the M0 acceptance: proves the GDExtension built by the
// pipeline is loaded by the engine.
class NativeHello : public RefCounted {
	GDCLASS(NativeHello, RefCounted)

protected:
	static void _bind_methods();

public:
	static String get_version();
	static int32_t get_answer();
};

} // namespace godot

#endif // FROSTLINE_NATIVE_HELLO_H
