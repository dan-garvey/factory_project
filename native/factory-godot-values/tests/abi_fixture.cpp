#include "factory/godot_value.hpp"

#include <array>
#include <cstddef>
#include <functional>
#include <iostream>
#include <limits>
#include <string>
#include <utility>

namespace adapter = factory::godot_values;
namespace values = factory::values;
using values::Value;

namespace {
struct Context { GDExtensionInterfaceGetProcAddress lookup = nullptr; bool ran = false; };
Context context;
int checks = 0;

void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
    ++checks;
}
void refuses(const std::function<void()>& operation, adapter::ErrorCode reason) {
    try { operation(); }
    catch (const adapter::Error& error) {
        require(error.code() == reason, "An adapter control used the wrong refusal.");
        return;
    }
    throw std::runtime_error("An invalid adapter input was accepted.");
}
template<class Function> Function api(const char* name) {
    const auto address = context.lookup(name);
    if (!address) throw std::runtime_error("A fixture engine function is unavailable.");
    return reinterpret_cast<Function>(address);
}

struct RawVariant {
    alignas(std::max_align_t) std::array<std::byte, 40> bytes{};
    GDExtensionInterfaceVariantDestroy destroy;
    RawVariant(GDExtensionVariantType kind, void* input)
        : destroy(api<GDExtensionInterfaceVariantDestroy>("variant_destroy")) {
        const auto constructor = api<GDExtensionInterfaceGetVariantFromTypeConstructor>("get_variant_from_type_constructor")(kind);
        if (!constructor) throw std::runtime_error("A fixture Variant constructor is unavailable.");
        constructor(bytes.data(), input);
    }
    ~RawVariant() { destroy(bytes.data()); }
    RawVariant(const RawVariant&) = delete;
    RawVariant& operator=(const RawVariant&) = delete;
};

void run() {
    adapter::Boundary boundary(context.lookup);
    const Value examples[]{
        Value(), Value(false), Value(true),
        Value(Value::Integer{0}), Value(std::numeric_limits<Value::Integer>::min()),
        Value(std::numeric_limits<Value::Integer>::max()), Value(Value::Integer{9007199254740993}),
        Value(0.0), Value(-0.0), Value(4.5), Value(""), Value("P \xf0\x9f\x9a\x80"),
        Value(Value::Array{Value(Value::Integer{1}), Value(1.0), Value(false)}),
        Value(Value::Object{{"P", Value(Value::Integer{4})}, {"Q", Value(Value::Integer{1})},
                           {"nested", Value(Value::Array{Value(), Value("text"), Value(2.0)})}})
    };
    for (const auto& plain : examples) {
        auto native = boundary.export_value(plain);
        const auto recovered = boundary.import_value(native.get());
        require(!values::typed_difference(plain, recovered), "A real C API roundtrip changed a scalar kind or nested value.");
        auto moved = std::move(native);
        require(native.get() == nullptr && !values::typed_difference(plain, boundary.import_value(moved.get())),
                "Moving an owned Variant did not transfer its lifetime exactly once.");
    }
    auto integer = boundary.export_value(Value(Value::Integer{1}));
    auto floating = boundary.export_value(Value(1.0));
    auto boolean = boundary.export_value(Value(true));
    const auto get_type = api<GDExtensionInterfaceVariantGetType>("variant_get_type");
    require(get_type(integer.get()) == GDEXTENSION_VARIANT_TYPE_INT &&
            get_type(floating.get()) == GDEXTENSION_VARIANT_TYPE_FLOAT &&
            get_type(boolean.get()) == GDEXTENSION_VARIANT_TYPE_BOOL,
            "The engine must retain integer, floating-point and boolean types separately.");

    refuses([&]{ (void)boundary.import_value(nullptr); }, adapter::ErrorCode::unsupported_type);
    for (double number : {std::numeric_limits<double>::infinity(), -std::numeric_limits<double>::infinity(),
                          std::numeric_limits<double>::quiet_NaN()}) {
        RawVariant native(GDEXTENSION_VARIANT_TYPE_FLOAT, &number);
        refuses([&]{ (void)boundary.import_value(native.bytes.data()); }, adapter::ErrorCode::unsupported_type);
    }
    std::array<float, 3> point{1.0f, 2.0f, 3.0f};
    RawVariant vector(GDEXTENSION_VARIANT_TYPE_VECTOR3, point.data());
    refuses([&]{ (void)boundary.import_value(vector.bytes.data()); }, adapter::ErrorCode::unsupported_type);
    for (const auto& text : {std::string("x\0y", 3), std::string("\xc0\xaf"),
                             std::string("\xed\xa0\x80"), std::string("\xf4\x90\x80\x80")})
        refuses([&]{ (void)boundary.export_value(Value(text)); }, adapter::ErrorCode::invalid_string);
    refuses([&]{ (void)boundary.export_value(Value(std::string(1024 * 1024 + 1, 'x'))); }, adapter::ErrorCode::limit);

    Value nested(Value::Integer{7});
    for (int depth = 0; depth < 32; ++depth) nested = Value(Value::Array{nested});
    auto deep = boundary.export_value(nested);
    require(!values::typed_difference(nested, boundary.import_value(deep.get())), "The inclusive depth limit must roundtrip.");
    nested = Value(Value::Array{nested});
    refuses([&]{ (void)boundary.export_value(nested); }, adapter::ErrorCode::limit);

    auto dictionary = boundary.export_value(Value(Value::Object{}));
    auto key = boundary.export_value(Value(Value::Integer{3}));
    auto item = boundary.export_value(Value("three"));
    const auto set = api<GDExtensionInterfaceVariantSet>("variant_set");
    GDExtensionBool valid = false;
    set(dictionary.get(), key.get(), item.get(), &valid);
    require(valid, "The invented nonstring-key control must be an actual engine dictionary.");
    refuses([&]{ (void)boundary.import_value(dictionary.get()); }, adapter::ErrorCode::unsupported_type);

    const Value original(Value::Object{{"P", Value(Value::Integer{4})}});
    auto exported = boundary.export_value(original);
    const auto imported = boundary.import_value(exported.get());
    auto name = boundary.export_value(Value("P"));
    auto changed = boundary.export_value(Value(Value::Integer{99}));
    valid = false;
    set(exported.get(), name.get(), changed.get(), &valid);
    require(valid && !values::typed_difference(original, imported), "An imported plain dictionary must not alias later engine mutation.");
    require(values::typed_difference(original, boundary.import_value(exported.get())).has_value(),
            "The altered engine value must actually change while original plain custody remains detached.");
}

void initialize(void* data, GDExtensionInitializationLevel level) {
    auto& current = *static_cast<Context*>(data);
    if (level != GDEXTENSION_INITIALIZATION_SCENE || current.ran) return;
    current.ran = true;
    try {
        run();
        std::cout << "{\"status\":\"pass\",\"evidence\":\"invented_engine_value_abi_fixture\",\"checks\":"
                  << checks << ",\"game_worlds\":0}" << std::endl;
    } catch (const std::exception& error) {
        std::cerr << "The native value ABI fixture failed: " << error.what() << '\n';
        std::cout << "{\"status\":\"fail\",\"evidence\":\"invented_engine_value_abi_fixture\",\"checks\":"
                  << checks << ",\"game_worlds\":0}" << std::endl;
    }
}
void deinitialize(void*, GDExtensionInitializationLevel) {}
}  // namespace

extern "C" GDExtensionBool factory_value_fixture_init(GDExtensionInterfaceGetProcAddress lookup,
        GDExtensionClassLibraryPtr, GDExtensionInitialization* initialization) {
    if (!lookup || !initialization) return false;
    context = Context{lookup, false};
    initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
    initialization->userdata = &context;
    initialization->initialize = &initialize;
    initialization->deinitialize = &deinitialize;
    return true;
}
