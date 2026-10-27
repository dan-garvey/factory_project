#include "factory/godot_value.hpp"
#include "factory/projection_contract.hpp"
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

Value merged_tick(const Value& previous, const Value& delivery) {
    const auto& packet = std::get<Object>(delivery.storage());
    if (const auto full = packet.find("full"); full != packet.end()) return full->second;
    auto merged = std::get<Object>(previous.storage());
    for (const auto& key : field<Array>(delivery, "removed"))
        merged.erase(std::get<std::string>(key.storage()));
    for (const auto& [key, value] : field<Object>(delivery, "changes"))
        merged.insert_or_assign(key, value);
    return Value(std::move(merged));
}

void run() {
    check(factory_world_live_instances() == 0, "Library registration must not instantiate a live authority.");
    {
        EngineHost host;
        check(accepted(host.call("initialize", {Value("engine-adapter-fixture"), Value(Array{Value("P"), Value("Q")})})),
              "The native class must initialize one finite World through the real ABI.");
        check(!accepted(host.call("initialize", {Value("second"), Value(Array{Value("P")})})),
              "A host cannot create another World beside its existing authority.");
        Array axis{Value(-128.0), Value(-2.8), Value(-2.0), Value(128.0)}, heights;
        for (int row = 0; row < 4; ++row) {
            heights.emplace_back(-1.65); heights.emplace_back(-1.65);
            heights.emplace_back(-0.02); heights.emplace_back(-0.02);
        }
        const Object site{{"axis", Value(axis)}, {"heights", Value(heights)}, {"obstacles", Value(Array{})},
            {"water", Value(Array{Value(Array{Value(Integer{-8}), Value(Integer{0}), Value(Integer{-20}),
                Value(Integer{-400}), Value(Integer{0}), Value(Integer{200})})})}};
        check(accepted(host.call("configure_terrain", {Value(site)})),
              "The ABI test explicitly binds its synthetic terrain before construction.");
        const auto original = host.call("projection", {});
        check(field<Integer>(Value(field<Object>(original, "stock")), "source") > 0 &&
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

        Integer epoch = 1;
        const auto at = [&](double x, double z) {
            check(accepted(publish(host, "P", x, z, ++epoch)), "The actor observation reaches construction.");
        };
        const auto place = [&](const char* kind, Integer x, const char* id) {
            auto wire = placement(kind, x, id);
            wire.at("cell") = Value(Array{Value(x), Value(Integer{1})});
            wire.emplace("axis", Value("z")); wire.emplace("level", Value(Integer{4}));
            if (std::string(kind) == "wheel") {
                wire.at("cell") = Value(Array{Value(x), Value(Integer{0})}); wire.at("axis") = Value("x");
            }
            const auto reply = issue(host, wire);
            check(accepted(reply), (std::string("Machine placement: ") + kind + ": " + field<std::string>(reply, "reason")).c_str());
            return field<std::string>(reply, "entity");
        };
        const auto foundation = [&](Integer x, const char* id) {
            auto wire = request("place_foundation", id);
            wire.emplace("cell", Value(Array{Value(x), Value(Integer{1})})); wire.emplace("level", Value(Integer{4}));
            check(accepted(issue(host, wire)), "The machine foundation is placed.");
        };
        const auto cog = [&](Integer x, Integer z, const char* axis_name, Integer teeth, const char* id) {
            auto wire = request("place_gear", id);
            wire.emplace("center", Value(Array{Value(x), Value(Integer{4}), Value(z)}));
            wire.emplace("axis", Value(axis_name)); wire.emplace("teeth", Value(teeth));
            const auto reply = issue(host, wire);
            check(accepted(reply), ("Cog placement: " + field<std::string>(reply, "reason")).c_str());
        };
        const auto shaft = [&](Integer x, Integer z, const char* id) {
            auto wire = request("place_shaft", id);
            wire.emplace("center", Value(Array{Value(x), Value(Integer{4}), Value(z)}));
            wire.emplace("axis", Value("z")); wire.emplace("half_span", Value(Integer{2}));
            const auto reply = issue(host, wire);
            check(accepted(reply), ("Shaft placement: " + field<std::string>(reply, "reason")).c_str());
            return field<std::string>(reply, "entity");
        };
        at(-1.65, 3.3); (void)place("wheel", -2, "wheel");
        at(0, 0); foundation(0, "collector-base");
        const auto collector = place("collector", 0, "collector");
        at(-3.3, 0); cog(-4, 0, "x", 4, "input-cog");
        at(-3.3, -1.65); cog(0, -4, "z", 4, "output-cog");
        for (Integer x : {Integer{0}, Integer{4}}) {
            at(static_cast<double>(x) * 1.65 / 4.0, -3.3);
            const auto id = "front-cog-" + std::to_string(x); cog(x, 0, "z", 2, id.c_str());
        }
        for (Integer x : {Integer{4}, Integer{8}, Integer{12}}) {
            at(static_cast<double>(x) * 1.65 / 4.0, -3.3);
            const auto id = "rear-cog-" + std::to_string(x); cog(x, -4, "z", 2, id.c_str());
        }
        at(4.95, -3.3); (void)shaft(12, 0, "press-drive");
        at(1.65, 0); const auto first = shaft(4, 4, "first-shaft");
        at(3.3, 0); const auto last = shaft(8, 4, "last-shaft");
        at(2.475, 0);
        const auto belt_reply = issue(host, connection("place_belt_span", "span", first, last));
        check(accepted(belt_reply), "The belt joins its two physical shafts.");
        at(4.95, 0); foundation(3, "press-base");
        const auto press = place("processor", 3, "press");
        at(-1.65, 0);
        auto projection = host.call("projection", {});
        const auto schema = host.call("projection_fields", {});
        check(field<std::string>(schema, "context") == "string" &&
                  field<std::string>(schema, "stock") == "object" &&
                  field<std::string>(schema, "opening_engineering") == "object" &&
                  factory::godot_world::projection_contract::complete(projection, true),
              "The real extension exposes the same typed complete-view contract it publishes.");
        check(field<bool>(projection, "powered") && field<Integer>(Value(field<Object>(projection, "parts")), "shaft") == 5,
              "The powered line consumes three physical shafts.");
        bool blocked_ready = false;
        bool active_delta_without_topology = false;
        for (int tick = 0; tick < 500; ++tick) {
            const auto delivery = host.call("advance_delta", {});
            const auto next = merged_tick(projection, delivery);
            const auto fresh = host.call("projection", {});
            check(!factory::values::typed_difference(next, fresh),
                  "Every active tick delta must reconstruct the fresh full engine projection.");
            const bool changed_material = bool(factory::values::typed_difference(
                Value(field<Object>(projection, "stock")), Value(field<Object>(next, "stock"))));
            if (const auto* packet = std::get_if<Object>(&delivery.storage())) {
                const auto found = packet->find("changes");
                if (found != packet->end()) {
                    const auto& changes = std::get<Object>(found->second.storage());
                    active_delta_without_topology |= changed_material &&
                        !changes.contains("entities") && !changes.contains("transmission_parts") &&
                        !changes.contains("motion") && !changes.contains("engagements");
                }
            }
            projection = next;
            const auto stock = Value(field<Object>(projection, "stock"));
            if (field<Integer>(stock, "held") > 0 && field<Integer>(stock, "output") > 0) {
                blocked_ready = true; break;
            }
        }
        check(blocked_ready, "The physical line reaches blocked ready work and completed output.");
        check(active_delta_without_topology,
              "The active line changes material while the delta omits unchanged machine topology.");
        at(4.95, 0);
        const auto recover = target("recover", "recover-ready", press);
        const auto recovered = issue(host, recover);
        const auto lots = field<Array>(recovered, "moved_work");
        check(accepted(recovered) && field<Integer>(recovered, "moved_products") == 1 && lots.size() == 1,
              "Recovery retains completed output and the original ready work.");
        const auto work_id = field<Integer>(lots.front(), "id");
        check(accepted(issue(host, target("remove", "remove-running", press))), "The recovered machine can be removed.");
        const auto rebuilt = place("processor", 3, "rebuild");
        const auto replay = issue(host, recover);
        check(field<bool>(replay, "duplicate") && field<std::string>(replay, "entity") == press && press != rebuilt,
              "Original wire lookup precedes target translation after rebuilding.");
        const auto changed = issue(host, target("recover", "recover-ready", collector));
        check(!accepted(changed) && field<std::string>(changed, "reason") == "request_reuse",
              "Changed wire intent cannot retarget an old request.");
        auto insert = target("insert_work", "insert-original", rebuilt); insert.emplace("work_id", Value(work_id));
        check(accepted(issue(host, insert)), "Insertion moves the original ready lot.");
        const auto saved = host.call("checkpoint", {});
        check(field<Integer>(saved, "schema") == 4 && !field<Object>(saved, "support_routes").empty() &&
                  !field<Object>(saved, "actors").contains("native_epoch"),
              "The physical checkpoint contains chosen support routes, not a saved actor registration.");
        check(accepted(host.call("validate_checkpoint", {saved})), "The class exposes detached complete checkpoint validation.");
        check(!accepted(host.call("restore_checkpoint", {saved})), "An already observed host refuses an in-place body reset.");

        EngineHost fresh;
        check(accepted(fresh.call("initialize", {Value("new-boot-context"), Value(Array{Value("P"), Value("Q")})})),
              "A separate host begins with its own unregistered World.");
        check(accepted(fresh.call("configure_terrain", {Value(site)})), "The fresh host binds the same terrain.");
        auto bad_actors = field<Object>(saved, "actors");
        bad_actors.at("P") = Value(Array{Value(Integer{0}), Value(Integer{1}), Value(Integer{0})});
        check(!accepted(fresh.call("restore_checkpoint", {edited(saved, "actors", Value(std::move(bad_actors)))})),
              "Typed native checkpoint seeds cannot be silently reified from integers.");
        (void)fresh.call("projection", {});
        check(accepted(fresh.call("restore_checkpoint", {saved})), "A valid complete candidate replaces the fresh host atomically.");
        check(!factory::values::typed_difference(saved, fresh.call("checkpoint", {})),
              "Every typed quantity, original wire intent, cached outcome, identity and seed survives exactly.");
        const auto after_restore = fresh.call("advance_delta", {});
        check(std::get<Object>(after_restore.storage()).contains("full"),
              "A Store restore invalidates the prior native delta base.");
        const auto restored = merged_tick(Value(Object{}), after_restore);
        check(!factory::values::typed_difference(restored, fresh.call("projection", {})),
              "The first post-restore tick delivers the exact complete view.");
        const auto p = Value(field<Object>(Value(field<Object>(restored, "actors")), "P"));
        check(field<std::string>(restored, "context") == "engine-adapter-fixture" && !field<bool>(p, "ready") &&
              field<Integer>(p, "native_epoch") == 0, "Restoration preserves context but requires fresh producer readiness.");
        check(field<bool>(issue(fresh, recover), "duplicate"), "Restored cache lookup works before any new actor observation.");
        check(accepted(publish(fresh, "P", 4.95, 0, 1)) && accepted(publish(fresh, "Q", 4.95, 0, 1)),
              "Restored actors require new process-local observation ordinals.");
        check(!accepted(publish(fresh, "P", 4.95, 0, 1)), "A stale native sample is never admitted.");
        const auto after_refusal = fresh.call("advance_delta", {});
        check(std::get<Object>(after_refusal.storage()).contains("full") &&
              !factory::values::typed_difference(merged_tick(restored, after_refusal), fresh.call("projection", {})),
              "A refused actor sample discards the old delta base and delivers complete current facts.");
        const auto before_bad_type = fresh.call("projection", {});
        (void)fresh.call("publish_actor", {Value("P"), Value(Array{Value(0.8), Value(1.0), Value(1.65)}), Value(2.0)}, true);
        check(!factory::values::typed_difference(before_bad_type, fresh.call("projection", {})),
              "The engine method boundary cannot coerce a float ordinal into authority.");
        for (int tick = 0; tick < 200; ++tick) (void)fresh.call("advance", {});
        auto collect = target("retrieve", "Q-product", rebuilt, "Q"); collect.emplace("amount", Value(Integer{1}));
        check(accepted(issue(fresh, collect, "Q")), "A fresh actor collects the one resumed product.");
        const auto final = fresh.call("projection", {});
        const auto inventory = Value(field<Object>(final, "inventories"));
        check(field<Integer>(inventory, "P") == 1 && field<Integer>(inventory, "Q") == 1 &&
              field<Integer>(Value(field<Object>(final, "stock")), "source") <= field<Integer>(Value(field<Object>(projection, "stock")), "source"),
              "Resumed work preserves P/Q product custody and the original finite source without a producer replay.");
        check(accepted(fresh.call("invalidate_actor", {Value("P")})), "The trusted host can invalidate a producer.");
        check(!accepted(publish(fresh, "P", 4.95, 0, 1)), "Invalidation does not reset the monotonic sample boundary.");
        check(accepted(publish(fresh, "P", 4.95, 0, 2)), "Only a newer observation restores readiness.");
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
