#include "factory/godot_value.hpp"

#include <cstring>
#include <iostream>
#include <stdexcept>

namespace adapter = factory::godot_values;
namespace {
int checks = 0;
int lookups_after_version = 0;

void version_wrong(GDExtensionGodotVersion2* version) {
    *version = {};
    version->major = 9;
    version->hash = "wrong";
}
void version_right(GDExtensionGodotVersion2* version) {
    *version = {};
    version->major = 4; version->minor = 7; version->patch = 2;
    version->hash = "ed1daf0bf001b61586d9930840f2f1394092c079";
}
GDExtensionInterfaceFunctionPtr missing(const char*) { return nullptr; }
GDExtensionInterfaceFunctionPtr incompatible(const char* name) {
    if (std::strcmp(name, "get_godot_version2") == 0)
        return reinterpret_cast<GDExtensionInterfaceFunctionPtr>(&version_wrong);
    ++lookups_after_version;
    return nullptr;
}
GDExtensionInterfaceFunctionPtr partial(const char* name) {
    if (std::strcmp(name, "get_godot_version2") == 0)
        return reinterpret_cast<GDExtensionInterfaceFunctionPtr>(&version_right);
    return nullptr;
}
void refuses(GDExtensionInterfaceGetProcAddress lookup, adapter::ErrorCode reason) {
    try { const adapter::Boundary invalid(lookup); }
    catch (const adapter::Error& error) {
        if (error.code() != reason) throw std::runtime_error("The API refusal used the wrong reason.");
        ++checks;
        return;
    }
    throw std::runtime_error("The incomplete or incompatible API was accepted.");
}
}  // namespace

int main() {
    try {
        refuses(nullptr, adapter::ErrorCode::missing_symbol);
        refuses(&missing, adapter::ErrorCode::missing_symbol);
        refuses(&incompatible, adapter::ErrorCode::incompatible_engine);
        if (lookups_after_version != 0) throw std::runtime_error("The adapter touched an incompatible API after its version refusal.");
        ++checks;
        refuses(&partial, adapter::ErrorCode::missing_symbol);
        std::cout << "Passed " << checks << " invented API-table refusal checks. No engine was started.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
