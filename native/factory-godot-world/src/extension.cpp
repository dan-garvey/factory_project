#include "factory/godot_world.hpp"
#include "factory/godot_value.hpp"
#include "factory/opening_engineering.hpp"
#include "factory/projection_contract.hpp"

#include <array>
#include <atomic>
#include <cstddef>
#include <cstring>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>

namespace {
using Value = factory::values::Value;
using Object = Value::Object;

struct Api;
std::unique_ptr<Api> current;
std::atomic<int> live_instances{};

struct Instance {
    factory::godot_world::Host host;
    std::optional<Value> last_view;
    Instance() { ++live_instances; }
    ~Instance() { --live_instances; }
};

struct Api {
    GDExtensionInterfaceGetProcAddress lookup;
    GDExtensionClassLibraryPtr library;
    factory::godot_values::Boundary boundary;
    GDExtensionInterfaceClassdbConstructObject3 construct;
    GDExtensionInterfaceObjectSetInstance set_instance;
    GDExtensionInterfaceObjectDestroy destroy_object;
    GDExtensionInterfaceVariantNewCopy copy_variant;
    GDExtensionInterfaceVariantDestroy destroy_variant;
    GDExtensionInterfaceVariantCall call_variant;
    GDExtensionInterfaceGetVariantFromTypeConstructor from_type;
    GDExtensionInterfaceStringNameNewWithUtf8Chars name_new;
    GDExtensionPtrDestructor name_destroy;
    GDExtensionInterfaceStringNewWithUtf8Chars string_new;
    GDExtensionPtrDestructor string_destroy;
    GDExtensionInterfaceClassdbRegisterExtensionClass6 register_class;
    GDExtensionInterfaceClassdbUnregisterExtensionClass unregister_class;
    GDExtensionInterfaceClassdbRegisterExtensionClassMethod register_method;

    template<class Function> Function get(const char* name) const {
        const auto function = lookup(name);
        if (!function) throw std::runtime_error("Missing native World engine interface.");
        return reinterpret_cast<Function>(function);
    }

    Api(GDExtensionInterfaceGetProcAddress lookup_value, GDExtensionClassLibraryPtr library_value)
        : lookup(lookup_value), library(library_value), boundary(lookup_value) {
        construct = get<GDExtensionInterfaceClassdbConstructObject3>("classdb_construct_object3");
        set_instance = get<GDExtensionInterfaceObjectSetInstance>("object_set_instance");
        destroy_object = get<GDExtensionInterfaceObjectDestroy>("object_destroy");
        copy_variant = get<GDExtensionInterfaceVariantNewCopy>("variant_new_copy");
        destroy_variant = get<GDExtensionInterfaceVariantDestroy>("variant_destroy");
        call_variant = get<GDExtensionInterfaceVariantCall>("variant_call");
        from_type = get<GDExtensionInterfaceGetVariantFromTypeConstructor>("get_variant_from_type_constructor");
        name_new = get<GDExtensionInterfaceStringNameNewWithUtf8Chars>("string_name_new_with_utf8_chars");
        name_destroy = get<GDExtensionInterfaceVariantGetPtrDestructor>("variant_get_ptr_destructor")(GDEXTENSION_VARIANT_TYPE_STRING_NAME);
        string_new = get<GDExtensionInterfaceStringNewWithUtf8Chars>("string_new_with_utf8_chars");
        string_destroy = get<GDExtensionInterfaceVariantGetPtrDestructor>("variant_get_ptr_destructor")(GDEXTENSION_VARIANT_TYPE_STRING);
        register_class = get<GDExtensionInterfaceClassdbRegisterExtensionClass6>("classdb_register_extension_class6");
        unregister_class = get<GDExtensionInterfaceClassdbUnregisterExtensionClass>("classdb_unregister_extension_class");
        register_method = get<GDExtensionInterfaceClassdbRegisterExtensionClassMethod>("classdb_register_extension_class_method");
        if (!name_destroy || !string_destroy) throw std::runtime_error("Missing native World string destructor.");
    }
};

struct Name {
    alignas(std::max_align_t) std::array<std::byte, 16> storage{};
    explicit Name(const char* text) { current->name_new(storage.data(), text); }
    ~Name() { current->name_destroy(storage.data()); }
    Name(const Name&) = delete;
    Name& operator=(const Name&) = delete;
    void* get() { return storage.data(); }
};

struct ObjectVariant {
    alignas(std::max_align_t) std::array<std::byte, 40> storage{};
    explicit ObjectVariant(GDExtensionObjectPtr object) {
        current->from_type(GDEXTENSION_VARIANT_TYPE_OBJECT)(storage.data(), &object);
    }
    ~ObjectVariant() { current->destroy_variant(storage.data()); }
};

struct EmptyText {
    alignas(std::max_align_t) std::array<std::byte, 16> storage{};
    EmptyText() { current->string_new(storage.data(), ""); }
    ~EmptyText() { current->string_destroy(storage.data()); }
    void* get() { return storage.data(); }
};

enum class Method { initialize, initialize_arrival, initialize_arrival_advanced_fixture, terrain, command, publish, actor_projection, invalidate, advance, advance_delta, projection, projection_fields, projection_record_fields, checkpoint, restore, validate };
struct Description { const char* name; Method method; std::uint32_t arguments; };
std::array methods{
    Description{"initialize", Method::initialize, 2},
    Description{"initialize_arrival", Method::initialize_arrival, 2},
    Description{"initialize_arrival_advanced_fixture", Method::initialize_arrival_advanced_fixture, 2},
    Description{"command", Method::command, 2},
    Description{"configure_terrain", Method::terrain, 1},
    Description{"publish_actor", Method::publish, 3}, Description{"actor_projection", Method::actor_projection, 1},
    Description{"invalidate_actor", Method::invalidate, 1},
    Description{"advance", Method::advance, 0}, Description{"advance_delta", Method::advance_delta, 0},
    Description{"projection", Method::projection, 0},
    Description{"projection_fields", Method::projection_fields, 0},
    Description{"projection_record_fields", Method::projection_record_fields, 0},
    Description{"checkpoint", Method::checkpoint, 0}, Description{"restore_checkpoint", Method::restore, 1},
    Description{"validate_checkpoint", Method::validate, 1}};

template<class T> const T& typed(const std::vector<Value>& values, std::size_t index) {
    const auto* value = std::get_if<T>(&values.at(index).storage());
    if (!value) throw std::invalid_argument("Wrong native World argument type.");
    return *value;
}

Value with_opening_engineering(Value state) {
    const auto* original = std::get_if<Object>(&state.storage());
    if (!original) return state;
    const auto found = original->find("inventories");
    if (found == original->end()) return state;
    const auto* inventories = std::get_if<Object>(&found->second.storage());
    if (!inventories) return state;
    Object progress;
    for (const auto& [actor, count] : *inventories) {
        (void)count;
        progress.emplace(actor, factory::opening_engineering::projection(state, actor));
    }
    // A derived view only: no command, actor registration, progress flag or
    // checkpoint mutation. Session publishes these same per-actor facts.
    Object root = std::move(state).take_object();
    root.insert_or_assign("opening_engineering", Value(std::move(progress)));
    return Value(std::move(root));
}

Value invoke(Instance& instance, Method method, const std::vector<Value>& args) {
    auto& host = instance.host;
    // All authority mutations invalidate the previous exported view. A refusal
    // is allowed to do the same: the next tick simply delivers a full view.
    if (method == Method::initialize || method == Method::initialize_arrival ||
        method == Method::initialize_arrival_advanced_fixture ||
        method == Method::terrain || method == Method::command || method == Method::publish ||
        method == Method::invalidate || method == Method::restore) instance.last_view.reset();
    switch (method) {
        case Method::terrain: return host.configure_terrain(typed<Object>(args, 0));
        case Method::initialize:
        case Method::initialize_arrival:
        case Method::initialize_arrival_advanced_fixture: {
            std::vector<std::string> actors;
            for (const auto& value : typed<Value::Array>(args, 1)) {
                const auto* actor = std::get_if<std::string>(&value.storage());
                if (!actor) throw std::invalid_argument("Wrong actor roster type.");
                actors.push_back(*actor);
            }
            if (method == Method::initialize_arrival)
                return host.initialize_arrival(typed<std::string>(args, 0), actors);
            if (method == Method::initialize_arrival_advanced_fixture)
                return host.initialize_arrival_advanced_fixture(typed<std::string>(args, 0), actors);
            return host.initialize(typed<std::string>(args, 0), actors);
        }
        case Method::command: return host.command(typed<std::string>(args, 0), typed<Object>(args, 1));
        case Method::publish: return host.publish_actor(typed<std::string>(args, 0), typed<Value::Array>(args, 1), typed<Value::Integer>(args, 2));
        case Method::actor_projection: return host.actor_projection(typed<std::string>(args, 0));
        case Method::projection_fields: return factory::godot_world::projection_contract::fields(true);
        case Method::projection_record_fields: return factory::godot_world::projection_contract::record_fields();
        case Method::invalidate: return host.invalidate_actor(typed<std::string>(args, 0));
        case Method::advance:
        case Method::projection: {
            Value view = with_opening_engineering(method == Method::advance ? host.advance() : host.projection());
            if (factory::godot_world::projection_contract::complete(view, true))
                instance.last_view = view;
            else instance.last_view.reset();
            return view;
        }
        case Method::advance_delta: {
            if (!instance.last_view ||
                !factory::godot_world::projection_contract::complete(*instance.last_view, true)) {
                Value view = with_opening_engineering(host.advance());
                if (factory::godot_world::projection_contract::complete(view, true))
                    instance.last_view = view;
                else instance.last_view.reset();
                return Value(Object{{"full", std::move(view)}});
            }
            Value tick = host.advance_tick_fields();
            const auto* fields = std::get_if<Object>(&tick.storage());
            if (!fields || !fields->contains("revision")) {
                instance.last_view.reset();
                return tick;
            }
            Object next = std::move(*instance.last_view).take_object();
            Object tick_changes = std::move(tick).take_object();
            Object changes;
            for (auto& [key, value] : tick_changes) {
                const auto found = next.find(key);
                if (found == next.end() || factory::values::typed_difference(found->second, value)) {
                    changes.emplace(key, value);
                    next.insert_or_assign(key, std::move(value));
                }
            }
            // Engineering progress reads inventory and machine topology plus
            // belt contents and loose drops. Tick cannot change the first two.
            // A wheel-only tick therefore keeps the exact derived value.
            Value view;
            if (changes.contains("belt_spans") || changes.contains("dropped_material")) {
                next.erase("opening_engineering");
                view = with_opening_engineering(Value(std::move(next)));
                changes.emplace("opening_engineering", std::get<Object>(view.storage()).at("opening_engineering"));
            } else {
                view = Value(std::move(next));
            }
            if (!factory::godot_world::projection_contract::complete(view, true)) {
                instance.last_view.reset();
                return Value(Object{{"accepted", Value(false)},
                    {"reason", Value("incomplete_projection")}, {"uncertain", Value(true)}});
            }
            instance.last_view = std::move(view);
            return Value(Object{{"changes", Value(std::move(changes))}, {"removed", Value(Value::Array{})}});
        }
        case Method::checkpoint: return host.checkpoint();
        case Method::restore: return host.restore_checkpoint(args.at(0));
        case Method::validate: return host.validate_checkpoint(args.at(0));
    }
    throw std::invalid_argument("Unknown native World method.");
}

void call(void* data, GDExtensionClassInstancePtr pointer, const GDExtensionConstVariantPtr* arguments,
          GDExtensionInt count, GDExtensionVariantPtr output, GDExtensionCallError* error) noexcept {
    if (error) *error = {GDEXTENSION_CALL_OK, 0, 0};
    try {
        const auto& method = *static_cast<Description*>(data);
        if (!pointer || !output || count < 0 || static_cast<std::uint64_t>(count) != method.arguments ||
            (count != 0 && !arguments)) throw std::invalid_argument("Wrong native World argument count.");
        std::vector<Value> plain;
        for (GDExtensionInt index = 0; index < count; ++index) plain.push_back(current->boundary.import_value(arguments[index]));
        auto result = current->boundary.export_value(invoke(*static_cast<Instance*>(pointer), method.method, plain));
        current->destroy_variant(output); // ClassMethodCall supplies an initialized Variant.
        current->copy_variant(output, result.get());
    } catch (...) {
        if (error) *error = {GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT, 0, GDEXTENSION_VARIANT_TYPE_NIL};
        if (output && current) {
            try {
                auto refusal = current->boundary.export_value(Value(Object{
                    {"accepted", Value(false)}, {"reason", Value("native_boundary_refused")}}));
                current->destroy_variant(output);
                current->copy_variant(output, refusal.get());
            } catch (...) { /* The engine-owned output remains intact on preparation failure. */ }
        }
    }
}

GDExtensionObjectPtr create(void*, GDExtensionBool notify) noexcept {
    GDExtensionObjectPtr object = nullptr;
    try {
        auto instance = std::make_unique<Instance>();
        Name parent("RefCounted"), name("FactoryNativeWorld");
        object = current->construct(parent.get());
        if (!object) return nullptr;
        current->set_instance(object, name.get(), instance.get());
        instance.release(); // Godot now owns this native instance.
        if (notify) {
            ObjectVariant receiver(object);
            Name notification("notification");
            auto code = current->boundary.export_value(Value(Value::Integer{0}));
            auto reversed = current->boundary.export_value(Value(false));
            const GDExtensionConstVariantPtr args[]{code.get(), reversed.get()};
            auto result = current->boundary.export_value(Value());
            // variant_call expects uninitialized output, unlike ClassMethodCall.
            current->destroy_variant(result.get());
            GDExtensionCallError error{};
            current->call_variant(receiver.storage.data(), notification.get(), args, 2, result.get(), &error);
            if (error.error != GDEXTENSION_CALL_OK) throw std::runtime_error("Native World postinitialization failed.");
        }
        return object;
    } catch (...) {
        if (object) current->destroy_object(object);
        return nullptr;
    }
}

void free_instance(void*, GDExtensionClassInstancePtr instance) noexcept { delete static_cast<Instance*>(instance); }

void register_world() {
    Name name("FactoryNativeWorld"), parent("RefCounted"), empty(""), result_name("result");
    EmptyText hint;
    GDExtensionClassCreationInfo6 info{};
    info.is_exposed = true;
    info.is_runtime = true;
    info.create_instance_func = create;
    info.free_instance_func = free_instance;
    current->register_class(current->library, name.get(), parent.get(), &info);
    for (auto& method : methods) {
        Name method_name(method.name), arg0("arg0"), arg1("arg1"), arg2("arg2");
        GDExtensionPropertyInfo result_info{GDEXTENSION_VARIANT_TYPE_DICTIONARY, result_name.get(), empty.get(), 0, hint.get(), 0};
        // Variant argument metadata preserves exact scalar types. In particular,
        // neither the VM nor this bridge may reify a float as an authority int.
        std::array<GDExtensionPropertyInfo, 3> arguments{{
            {GDEXTENSION_VARIANT_TYPE_NIL, arg0.get(), empty.get(), 0, hint.get(), 1U << 17},
            {GDEXTENSION_VARIANT_TYPE_NIL, arg1.get(), empty.get(), 0, hint.get(), 1U << 17},
            {GDEXTENSION_VARIANT_TYPE_NIL, arg2.get(), empty.get(), 0, hint.get(), 1U << 17}}};
        std::array<GDExtensionClassMethodArgumentMetadata, 3> metadata{};
        GDExtensionClassMethodInfo method_info{};
        method_info.name = method_name.get();
        method_info.method_userdata = &method;
        method_info.call_func = call;
        // This boundary implements Variant calls only. Mark it variadic so
        // the VM cannot select an absent typed/validated ptrcall callback.
        // call() still enforces the exact declared arity and scalar types.
        method_info.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL | GDEXTENSION_METHOD_FLAG_VARARG;
        method_info.has_return_value = true;
        method_info.return_value_info = &result_info;
        method_info.argument_count = method.arguments;
        method_info.arguments_info = arguments.data();
        method_info.arguments_metadata = metadata.data();
        current->register_method(current->library, name.get(), &method_info);
    }
}
}  // namespace

extern "C" int factory_world_live_instances() { return live_instances.load(); }

#ifdef FACTORY_NATIVE_WORLD_SELF_TEST
void factory_world_abi_test(GDExtensionInterfaceGetProcAddress lookup);
#endif

namespace {
void initialize(void*, GDExtensionInitializationLevel level) noexcept {
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    try {
        register_world();
#ifdef FACTORY_NATIVE_WORLD_SELF_TEST
        factory_world_abi_test(current->lookup);
#endif
    } catch (...) {
        // The class is absent or unusable; the caller must fail its startup.
        // No script authority is created or selected as a fallback.
    }
}

void deinitialize(void*, GDExtensionInitializationLevel level) noexcept {
    if (level != GDEXTENSION_INITIALIZATION_SCENE || !current) return;
    { Name name("FactoryNativeWorld"); current->unregister_class(current->library, name.get()); }
    current.reset();
}
}  // namespace

extern "C" GDExtensionBool factory_native_world_init(GDExtensionInterfaceGetProcAddress lookup,
        GDExtensionClassLibraryPtr library, GDExtensionInitialization* initialization) {
    if (!lookup || !initialization || current) return false;
    try { current = std::make_unique<Api>(lookup, library); }
    catch (...) { return false; }
    initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
    initialization->initialize = initialize;
    initialization->deinitialize = deinitialize;
    initialization->userdata = nullptr;
    return true;
}
