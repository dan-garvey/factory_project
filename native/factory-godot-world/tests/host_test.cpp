#include "factory/godot_world.hpp"
#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <array>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <utility>

namespace {
using V = factory::values::Value;
using O = V::Object;
using A = V::Array;
using I = V::Integer;
using Host = factory::godot_world::Host;
int checks{};

void check(bool value, const char* message) {
    ++checks;
    if (!value) throw std::runtime_error(message);
}

template<class T> const T& field(const V& value, const char* name) {
    return std::get<T>(std::get<O>(value.storage()).at(name).storage());
}

bool accepted(const V& value) { return field<bool>(value, "accepted"); }

O request(const char* action, const char* id) {
    return {{"context", V("host-boundary")}, {"client", V("P")}, {"request", V(id)}, {"action", V(action)}};
}

O target(const char* action, const char* id, const std::string& entity) {
    auto wire = request(action, id);
    wire.emplace("entity", V(entity));
    return wire;
}

O link(const char* action, const char* id, const std::string& from, const std::string& to) {
    auto wire = request(action, id);
    wire.emplace("from", V(from)); wire.emplace("to", V(to));
    return wire;
}

V alter_wire(const V& saved, const std::string& request_id, const std::string& key, V replacement) {
    auto root = std::get<O>(saved.storage());
    auto world = field<O>(saved, "world");
    auto history = field<O>(V(world), "history");
    auto records = field<A>(V(history), "records");
    bool found = false;
    for (auto& value : records) {
        auto record = std::get<O>(value.storage());
        auto intent = field<O>(value, "intent");
        if (field<std::string>(V(intent), "request") != request_id) continue;
        auto wire = field<O>(V(intent), "wire");
        wire.insert_or_assign(key, std::move(replacement));
        intent.at("wire") = V(std::move(wire));
        record.at("intent") = V(std::move(intent));
        value = V(std::move(record));
        found = true;
        break;
    }
    check(found, "The mutation must alter an existing original request.");
    history.at("records") = V(std::move(records));
    world.at("history") = V(std::move(history));
    root.at("world") = V(std::move(world));
    return V(std::move(root));
}

void historical_translation() {
    Host host;
    check(accepted(host.initialize("host-boundary", {"P"})), "The finite test World initializes.");
    check(accepted(host.configure_terrain(factory::godot_world::tests::channel_site())), "The test binds its explicit synthetic terrain.");
    check(accepted(host.publish_actor("P", {V(1.65), V(1.0), V(1.65)}, 1)), "The disclosed synthetic observation is ready.");
    const auto place = [&](const char* kind, I x, const char* id) {
        auto wire = request("place", id);
        wire.emplace("kind", V(kind)); wire.emplace("cell", V(A{V(x), V(I{0})})); wire.emplace("axis", V("z"));
        const auto reply = host.command("P", wire);
        check(accepted(reply), (std::string("The starter placement succeeds: ") + kind + ", " + field<std::string>(reply, "reason")).c_str());
        return field<std::string>(reply, "entity");
    };
    auto base = request("place_foundation", "collector-base");
    base.emplace("cell", V(A{V(I{0}), V(I{0})})); base.emplace("level", V(I{0}));
    check(accepted(host.command("P", base)), "The synthetic stream bank supports a collector foundation.");
    const auto collector = place("collector", 0, "collector");
    const auto belt = place("belt", 1, "belt");
    const auto press = place("processor", 2, "press");
    const auto wheel = place("wheel", -1, "wheel");
    const auto flow_a = host.command("P", link("connect", "flow-A", collector, belt));
    const auto flow_b = host.command("P", link("connect", "flow-B", belt, press));
    check(!accepted(flow_a) && field<std::string>(flow_a, "reason") == "existing_link",
          "Collector-to-belt placement already attached the first material path.");
    check(!accepted(flow_b) && field<std::string>(flow_b, "reason") == "existing_link",
          "Belt-to-press placement already attached the second material path.");
    const std::array<std::string, 4> hubs{wheel, collector, belt, press};
    const std::array<const char*, 4> shaft_ids{"shaft-A", "shaft-B", "shaft-C", "shaft-D"};
    for (std::size_t n = 0; n < hubs.size(); ++n) {
        const I x = static_cast<I>(n) - 1;
        check(accepted(host.publish_actor("P", {V(static_cast<double>(x) * 1.65), V(1.0), V(-1.65)}, static_cast<I>(n) + 2)),
              "The synthetic actor reaches each cog and its machine.");
        auto cog = request("place_gear", shaft_ids[n]);
        cog.at("request") = V(std::string("gear-") + std::to_string(n));
        cog.emplace("center", V(A{V(4 * x), V(I{0}), V(I{4})}));
        cog.emplace("axis", V("z")); cog.emplace("teeth", V(I{2}));
        const auto placed = host.command("P", cog);
        check(accepted(placed), "The finite adjacent cog is placed.");
        const auto touching = host.command("P", link("connect_drive", shaft_ids[n], hubs[n], field<std::string>(placed, "entity")));
        check(!accepted(touching) && field<std::string>(touching, "reason") == "axles_already_touch",
              "Touching axles do not consume a shaft.");
    }
    check(accepted(host.publish_actor("P", {V(-1.65), V(1.0), V(-1.4)}, 6)), "The actor reaches the source control.");
    auto power = request("set_power", "power"); power.emplace("active", V(true));
    check(accepted(host.command("P", power)), "The existing wheel supplies the test line.");
    for (int index = 0; index < 8; ++index) (void)host.advance();
    check(accepted(host.publish_actor("P", {V(3.3), V(1.0), V(-1.4)}, 7)), "The actor reaches the press.");
    auto collect = target("retrieve", "collect", press); collect.emplace("amount", V(I{1}));
    check(accepted(host.command("P", collect)), "The checkpoint includes an accepted product amount.");
    const auto recovery = target("recover", "recover", press);
    check(accepted(host.command("P", recovery)), "The checkpoint includes accepted recovery of the original target.");
    check(accepted(host.command("P", target("remove", "remove", press))), "The original target can be removed.");
    auto malformed = request("place", "malformed"); malformed.emplace("cell", V(false));
    check(!accepted(host.command("P", malformed)), "An intentionally malformed adapter refusal is retained.");
    const auto saved = host.checkpoint();
    check(accepted(host.validate_checkpoint(saved)), "Removed historical targets and malformed refusals remain valid.");
    const auto reject = [&](const char* id, const char* key, V value) {
        const auto changed = alter_wire(saved, id, key, std::move(value));
        const auto reply = host.validate_checkpoint(changed);
        check(!accepted(reply) && field<std::string>(reply, "reason") == "inconsistent_wire_history",
              "An inconsistent original wire cannot import a normalized cached receipt.");
        check(!factory::values::typed_difference(saved, host.checkpoint()), "Refused validation never changes the live authority.");
    };
    reject("recover", "entity", V(belt));
    reject("collect", "amount", V(I{2}));
    reject("collect", "amount", V(1.0));
    reject("collect", "action", V("recover"));
    reject("flow-A", "to", V(wheel));
    reject("shaft-A", "from", V(belt));
    reject("power", "active", V(false));
    reject("collector", "cell", V(A{V(I{0}), V(I{1})}));
    reject("collector", "kind", V("belt"));
    Host fresh;
    check(accepted(fresh.initialize("new-host", {"P"})), "A separate fresh Host initializes.");
    check(accepted(fresh.configure_terrain(factory::godot_world::tests::channel_site())), "The fresh Host binds the same synthetic terrain.");
    check(accepted(fresh.restore_checkpoint(saved)), "The unchanged complete checkpoint restores.");
    check(!factory::values::typed_difference(saved, fresh.checkpoint()), "Restore preserves the original typed history and state.");
    const auto retry = fresh.command("P", recovery);
    check(accepted(retry) && field<bool>(retry, "duplicate") && field<std::string>(retry, "entity") == press,
          "Historical recovery replays before present target lookup or native readiness.");
}

void exact_observation_conversion() {
    Host host;
    check(accepted(host.initialize("host-boundary", {"P"})), "The observation test Host initializes.");
    for (const I coordinate : {I{9007199254740993}, I{-9007199254740993}}) {
        const auto reply = host.publish_actor("P", {V(coordinate), V(I{1}), V(I{0})}, 1);
        check(!accepted(reply) && field<std::string>(reply, "reason") == "invalid_actor_sample",
              "The original integer immediately beyond either exact boundary is refused before conversion.");
        check(!field<bool>(V(field<O>(V(field<O>(host.projection(), "actors")), "P")), "ready"),
              "A lossy observation cannot mark the actor ready.");
    }
    I epoch = 1;
    for (const I coordinate : {I{9007199254740992}, I{-9007199254740992}}) {
        check(accepted(host.publish_actor("P", {V(coordinate), V(I{1}), V(I{0})}, epoch++)),
              "An exact integer at either inclusive boundary remains accepted.");
        const auto actor = V(field<O>(V(field<O>(host.projection(), "actors")), "P"));
        check(std::get<double>(field<A>(actor, "position").at(0).storage()) == static_cast<double>(coordinate),
              "The accepted boundary retains its exact numeric coordinate.");
    }
}
}  // namespace

int main(int argc, char** argv) {
    try {
        if (argc == 1 || (argc == 2 && std::string(argv[1]) == "--wire")) historical_translation();
        if (argc == 1 || (argc == 2 && std::string(argv[1]) == "--point")) exact_observation_conversion();
        if (argc > 2 || (argc == 2 && std::string(argv[1]) != "--wire" && std::string(argv[1]) != "--point"))
            throw std::runtime_error("Unknown Host regression selection.");
        std::cout << "{\"status\":\"pass\",\"evidence\":\"native_host_source_regressions\",\"checks\":" << checks
                  << ",\"engine_calls\":0,\"physical_producers\":0}" << std::endl;
        return 0;
    } catch (const std::exception& failure) {
        std::cerr << failure.what() << '\n';
        return 1;
    }
}
