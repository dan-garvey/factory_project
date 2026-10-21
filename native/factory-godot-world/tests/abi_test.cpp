#include "factory/godot_value.hpp"
#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <array>
#include <cstddef>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

extern "C" int factory_world_live_instances();

namespace {
using Value = factory::values::Value;
using Object = Value::Object;
using Array = Value::Array;
using Integer = Value::Integer;
GDExtensionInterfaceGetProcAddress lookup;
int checks{};

template<class Function> Function api(const char* name) {
    const auto function = lookup(name);
    if (!function) throw std::runtime_error("A native World test interface is absent.");
    return reinterpret_cast<Function>(function);
}

void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

struct Name {
    alignas(std::max_align_t) std::array<std::byte, 16> storage{};
    explicit Name(const char* text) { api<GDExtensionInterfaceStringNameNewWithUtf8Chars>("string_name_new_with_utf8_chars")(storage.data(), text); }
    ~Name() { api<GDExtensionInterfaceVariantGetPtrDestructor>("variant_get_ptr_destructor")(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(storage.data()); }
};

struct Returned {
    alignas(std::max_align_t) std::array<std::byte, 40> storage{};
    ~Returned() { api<GDExtensionInterfaceVariantDestroy>("variant_destroy")(storage.data()); }
};

class EngineHost {
public:
    EngineHost() : boundary_(lookup) {
        Name name("FactoryNativeWorld");
        const auto object = api<GDExtensionInterfaceClassdbConstructObject3>("classdb_construct_object3")(name.storage.data());
        check(object != nullptr, "The real engine must construct the registered native class.");
        api<GDExtensionInterfaceGetVariantFromTypeConstructor>("get_variant_from_type_constructor")(
            GDEXTENSION_VARIANT_TYPE_OBJECT)(receiver_.data(), const_cast<void*>(static_cast<const void*>(&object)));
        initialized_ = true;
        // Construction owns one reference; the receiver Variant now owns the
        // second. Release the construction reference, retaining exactly one.
        const auto released = call("unreference", {});
        check(released.type() == factory::values::Type::boolean && !std::get<bool>(released.storage()),
              "The fixture receiver must retain one real engine reference.");
    }
    ~EngineHost() { if (initialized_) api<GDExtensionInterfaceVariantDestroy>("variant_destroy")(receiver_.data()); }
    EngineHost(const EngineHost&) = delete;
    EngineHost& operator=(const EngineHost&) = delete;

    Value call(const char* method, const std::vector<Value>& arguments, bool expected_error = false) {
        std::vector<factory::godot_values::NativeValue> native;
        std::vector<GDExtensionConstVariantPtr> pointers;
        for (const auto& argument : arguments) native.push_back(boundary_.export_value(argument));
        for (const auto& argument : native) pointers.push_back(argument.get());
        Name name(method);
        Returned result;
        GDExtensionCallError error{};
        api<GDExtensionInterfaceVariantCall>("variant_call")(receiver_.data(), name.storage.data(),
            pointers.data(), static_cast<GDExtensionInt>(pointers.size()), result.storage.data(), &error);
        check((error.error != GDEXTENSION_CALL_OK) == expected_error, "The engine call status must match the intended boundary.");
        return boundary_.import_value(result.storage.data());
    }

private:
    factory::godot_values::Boundary boundary_;
    alignas(std::max_align_t) std::array<std::byte, 40> receiver_{};
    bool initialized_{};
};

template<class T> const T& field(const Value& value, const char* name) {
    return std::get<T>(std::get<Object>(value.storage()).at(name).storage());
}

bool accepted(const Value& value) { return field<bool>(value, "accepted"); }

Object request(const char* action, const std::string& id, const char* actor = "P") {
    return {{"context", Value("engine-adapter-fixture")}, {"client", Value(actor)},
        {"request", Value(id)}, {"action", Value(action)}};
}

Object placement(const char* kind, Integer x, const std::string& id, const char* actor = "P") {
    auto command = request("place", id, actor);
    command.emplace("kind", Value(kind));
    command.emplace("cell", Value(Array{Value(x), Value(Integer{0})}));
    return command;
}

Value issue(EngineHost& host, const Object& request, const char* actor = "P") {
    return host.call("command", {Value(actor), Value(request)});
}

Value publish(EngineHost& host, const char* actor, double x, double z, Integer epoch) {
    return host.call("publish_actor", {Value(actor), Value(Array{Value(x), Value(1.0), Value(z)}), Value(epoch)});
}

Object target(const char* action, const char* id, const std::string& entity, const char* actor = "P") {
    auto result = request(action, id, actor);
    result.emplace("entity", Value(entity));
    return result;
}

Object connection(const char* action, const char* id, const std::string& from, const std::string& to) {
    auto result = request(action, id);
    result.emplace("from", Value(from)); result.emplace("to", Value(to));
    return result;
}

Value edited(const Value& value, const char* key, Value replacement) {
    auto object = std::get<Object>(value.storage());
    object.insert_or_assign(key, std::move(replacement));
    return Value(std::move(object));
}

void run() {
    check(factory_world_live_instances() == 0, "Library registration must not instantiate a live authority.");
    {
        EngineHost host;
        check(accepted(host.call("initialize", {Value("engine-adapter-fixture"), Value(Array{Value("P"), Value("Q")})})),
              "The native class must initialize one finite World through the real ABI.");
        check(!accepted(host.call("initialize", {Value("second"), Value(Array{Value("P")})})),
              "A host cannot create another World beside its existing authority.");
        check(accepted(host.call("configure_terrain", {Value(factory::godot_world::tests::flat_site())})),
              "The ABI test explicitly binds its synthetic terrain before construction.");
        const auto original = host.call("projection", {});
        check(field<Integer>(Value(field<Object>(original, "stock")), "source") == 16 &&
              !field<bool>(Value(field<Object>(Value(field<Object>(original, "actors")), "P")), "ready"),
              "Bootstrap projection must retain finite source and unregistered actor state.");
        const auto early = placement("collector", 0, "before-ready");
        check(field<std::string>(issue(host, early), "reason") == "actor_unready", "Fresh construction requires a producer observation.");
        check(accepted(publish(host, "P", 0.8, 1.65, 1)) && accepted(publish(host, "Q", 20, 0, 1)),
              "Trusted synthetic observation inputs must cross the ABI with exact ordinals.");
        const auto repeated = issue(host, early);
        check(field<bool>(repeated, "duplicate") && field<std::string>(repeated, "reason") == "actor_unready",
              "Readiness must not retarget a historical refusal.");
        check(field<std::string>(issue(host, placement("collector", 0, "Q-far", "Q"), "Q"), "reason") == "out_of_reach",
              "The far actor is refused by native scalar reach before part selection.");

        const auto place = [&](const char* kind, Integer x, const char* request_id) {
            const auto result = issue(host, placement(kind, x, request_id));
            check(accepted(result), "Each near starter machine must consume its finite part.");
            return field<std::string>(result, "entity");
        };
        const auto collector = place("collector", 0, "collector");
        const auto belt = place("belt", 1, "belt");
        const auto press = place("processor", 2, "press");
        const auto wheel = place("wheel", -1, "wheel");
        check(accepted(issue(host, connection("connect", "flow-A", collector, belt))) &&
              accepted(issue(host, connection("connect", "flow-B", belt, press))),
              "Ordinary material commands must bind both native endpoint generations.");
        check(accepted(issue(host, connection("connect_drive", "shaft-A", wheel, collector))) &&
              accepted(issue(host, connection("connect_drive", "shaft-B", collector, belt))) &&
              accepted(issue(host, connection("connect_drive", "shaft-C", belt, press))),
              "Drive commands must place three physical shafts through canonical geometry.");
        check(field<std::string>(issue(host, connection("connect_drive", "duplicate-shaft", wheel, collector)), "reason") == "existing_shaft",
              "Duplicate transmission cannot consume another physical shaft.");
        auto power = request("set_power", "power-on"); power.emplace("active", Value(true));
        check(accepted(issue(host, power)), "A near actor can enable the registered waterwheel source.");
        auto projection = host.call("projection", {});
        check(field<bool>(projection, "powered") && field<Object>(projection, "transmission_parts").size() == 3 &&
              field<Integer>(Value(field<Object>(projection, "parts")), "shaft") == 1,
              "Projection must expose actual geometry and exact finite shaft custody.");
        for (int tick = 0; tick < 8; ++tick) projection = host.call("advance", {});
        const auto stock = Value(field<Object>(projection, "stock"));
        check(field<Integer>(stock, "source") == 11 && field<Integer>(stock, "collector") == 1 &&
              field<Integer>(stock, "belt") == 1 && field<Integer>(stock, "input") == 1 &&
              field<Integer>(stock, "held") == 1 && field<Integer>(stock, "output") == 1 &&
              field<Integer>(projection, "remaining") == 0,
              "Eight host ticks must reach the independent literal blocked-ready distribution of sixteen units.");
        const auto recover = target("recover", "recover-ready", press);
        const auto recovered = issue(host, recover);
        check(accepted(recovered) && field<Integer>(recovered, "moved_raw") == 1 && field<Integer>(recovered, "moved_products") == 1,
              "Recovery must retain raw input, completed output and original ready work distinctly.");
        check(accepted(issue(host, target("remove", "remove-running", press))), "The empty stationary machine can be removed while the drive stays enabled.");
        const auto rebuilt = place("processor", 2, "rebuild");
        const auto replay = issue(host, recover);
        check(field<bool>(replay, "duplicate") && field<std::string>(replay, "entity") == press && press != rebuilt,
              "Original wire lookup precedes target translation after removal and rebuilding.");
        const auto changed = issue(host, target("recover", "recover-ready", belt));
        check(!accepted(changed) && field<std::string>(changed, "reason") == "request_reuse",
              "Changed original wire intent cannot retarget an old request.");
        auto insert = target("insert_work", "insert-original", rebuilt); insert.emplace("work_id", Value(Integer{2}));
        check(accepted(issue(host, insert)), "Insertion must move the original ready lot rather than creating replacement work.");
        const auto saved = host.call("checkpoint", {});
        check(field<Integer>(saved, "schema") == 3 && !field<Object>(saved, "actors").contains("native_epoch"),
              "The physical checkpoint contains seeds, not a saved native registration.");
        check(accepted(host.call("validate_checkpoint", {saved})), "The class exposes detached complete checkpoint validation.");
        check(!accepted(host.call("restore_checkpoint", {saved})), "An already observed host refuses an in-place body reset.");

        EngineHost fresh;
        check(accepted(fresh.call("initialize", {Value("new-boot-context"), Value(Array{Value("P"), Value("Q")})})),
              "A separate host begins with its own unregistered World.");
        auto bad_actors = field<Object>(saved, "actors");
        bad_actors.at("P") = Value(Array{Value(Integer{0}), Value(Integer{1}), Value(Integer{0})});
        check(!accepted(fresh.call("restore_checkpoint", {edited(saved, "actors", Value(std::move(bad_actors)))})),
              "Typed native checkpoint seeds cannot be silently reified from integers.");
        check(accepted(fresh.call("restore_checkpoint", {saved})), "A valid complete candidate replaces the fresh host atomically.");
        const auto restored = fresh.call("projection", {});
        const auto p = Value(field<Object>(Value(field<Object>(restored, "actors")), "P"));
        check(field<std::string>(restored, "context") == "engine-adapter-fixture" && !field<bool>(p, "ready") &&
              field<Integer>(p, "native_epoch") == 0, "Restoration preserves context but requires fresh producer readiness.");
        check(!factory::values::typed_difference(saved, fresh.call("checkpoint", {})),
              "Every typed quantity, original wire intent, cached outcome, identity and seed survives exactly.");
        check(field<bool>(issue(fresh, recover), "duplicate"), "Restored cache lookup works before any new actor observation.");
        check(accepted(publish(fresh, "P", 0.8, 1.65, 1)) && accepted(publish(fresh, "Q", 1.5, 1.65, 1)),
              "Restored actors require new process-local observation ordinals.");
        check(!accepted(publish(fresh, "P", 0.8, 1.65, 1)), "A stale native sample is never admitted.");
        const auto before_bad_type = fresh.call("projection", {});
        (void)fresh.call("publish_actor", {Value("P"), Value(Array{Value(0.8), Value(1.0), Value(1.65)}), Value(2.0)}, true);
        check(!factory::values::typed_difference(before_bad_type, fresh.call("projection", {})),
              "The engine method boundary cannot coerce a float ordinal into authority.");
        (void)fresh.call("advance", {});
        auto collect = target("retrieve", "Q-product", rebuilt, "Q"); collect.emplace("amount", Value(Integer{1}));
        check(accepted(issue(fresh, collect, "Q")), "A fresh actor collects the one resumed product.");
        const auto final = fresh.call("projection", {});
        const auto inventory = Value(field<Object>(final, "inventories"));
        check(field<Integer>(inventory, "P") == 1 && field<Integer>(inventory, "Q") == 1 &&
              field<Integer>(Value(field<Object>(final, "stock")), "source") == 11 && field<Integer>(final, "remaining") == 0,
              "Resumed work preserves P/Q product custody and the original finite source without a producer replay.");
        check(accepted(fresh.call("invalidate_actor", {Value("P")})), "The trusted host can invalidate a producer.");
        check(!accepted(publish(fresh, "P", 0.8, 1.65, 1)), "Invalidation does not reset the monotonic sample boundary.");
        check(accepted(publish(fresh, "P", 0.8, 1.65, 2)), "Only a newer observation restores readiness.");
    }
    check(factory_world_live_instances() == 0, "Engine reference ownership must destroy both native hosts exactly once.");
}
}  // namespace

void factory_world_abi_test(GDExtensionInterfaceGetProcAddress function_lookup) {
    lookup = function_lookup;
    try {
        run();
        std::cout << "{\"status\":\"pass\",\"evidence\":\"native_world_engine_abi\",\"checks\":" << checks
                  << ",\"live_instances\":" << factory_world_live_instances()
                  << ",\"physical_producers\":0,\"script_models\":0}" << std::endl;
    } catch (const std::exception& error) {
        std::cerr << "Native World ABI test failed: " << error.what() << '\n';
        std::cout << "{\"status\":\"fail\",\"evidence\":\"native_world_engine_abi\",\"checks\":" << checks
                  << ",\"live_instances\":" << factory_world_live_instances() << "}" << std::endl;
    }
}
