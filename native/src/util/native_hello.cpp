#include "native_hello.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace godot {

void NativeHello::_bind_methods() {
	ClassDB::bind_static_method("NativeHello", D_METHOD("get_version"), &NativeHello::get_version);
	ClassDB::bind_static_method("NativeHello", D_METHOD("get_answer"), &NativeHello::get_answer);
}

String NativeHello::get_version() {
#ifdef FROSTLINE_NATIVE_VERSION
	return String(FROSTLINE_NATIVE_VERSION);
#else
	return String("frostline-native/dev");
#endif
}

int32_t NativeHello::get_answer() { return 42; }

} // namespace godot
