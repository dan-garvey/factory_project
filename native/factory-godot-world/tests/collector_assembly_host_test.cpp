#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <iostream>
#include <stdexcept>
#include <string>

namespace {
using V = factory::values::Value;
using O = V::Object;
using A = V::Array;
using I = V::Integer;
using Host = factory::godot_world::Host;
int checks{};

void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

template<class T> const T& get(const V& value, const char* key) {
    return std::get<T>(std::get<O>(value.storage()).at(key).storage());
}

O request(const std::string& id, const char* action) {
    return {{"context", V("assembly-site")}, {"client", V("P")},
        {"request", V(id)}, {"action", V(action)}};
}

V ground_inspection(const Host& host) {
    const auto entries = get<A>(host.projection(), "collector_assemblies");
    check(entries.size() == 6, "Both ore workcells and three common-grid heights are inspected.");
    return entries.front();
}

std::string place(Host& host, const char* kind, I x, I y, I z, const char* id) {
    auto wire = request(id, "place_component");
    wire.emplace("component", V(kind));
    wire.emplace("center", V(A{V(x), V(y), V(z)}));
    const auto response = host.command("P", wire);
    check(get<bool>(response, "accepted"), "A crafted component installs through the ordinary Host command.");
    return get<std::string>(response, "entity");
}

void collector_readiness_tracks_real_parts() {
    Host host;
    check(get<bool>(host.initialize_arrival("assembly-site", {"P"}), "accepted") &&
          get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()), "accepted"),
          "The experimental arrival binds one native resource and construction authority.");
    check(get<std::string>(ground_inspection(host), "status") == "missing_frame",
          "An empty ore workcell has no collector.");
    check(get<bool>(host.publish_actor("P", {V(1.65), V(1.0), V(6.6)}, 1), "accepted"),
          "The actor is ready beside the pod bench and nearby tree.");
    for (int index = 0; index < 7; ++index) {
        auto wire = request("timber-" + std::to_string(index), "harvest_source");
        wire.emplace("target", V("tree-east-south"));
        check(get<bool>(host.command("P", wire), "accepted"), "Real timber is harvested for the first collector.");
    }
    check(get<bool>(host.publish_actor("P", {V(0.0), V(1.0), V(1.65)}, 2), "accepted"),
          "The actor moves to the ore deposit.");
    auto ore = request("one-ore", "harvest_source");
    ore.emplace("target", V("opening-softmetal"));
    check(get<bool>(host.command("P", ore), "accepted"),
          "A cutting edge consumes one real ore blank from the shared deposit.");
    check(get<bool>(host.publish_actor("P", {V(1.65), V(1.0), V(6.6)}, 3), "accepted"),
          "The actor returns to the pod bench.");
    for (const auto* name : {"wooden_frame", "tool_mount", "cutting_edge", "receiver_tray", "wooden_shaft"}) {
        auto wire = request(std::string("craft-") + name, "craft_component");
        wire.emplace("entity", V("pod-fabrication-hub"));
        wire.emplace("component", V(name));
        check(get<bool>(host.command("P", wire), "accepted"), "The bench crafts one typed collector component.");
    }
    check(get<bool>(host.publish_actor("P", {V(2.0), V(1.0), V(0.0)}, 4), "accepted"),
          "The actor approaches the deposit-facing workcell without occupying it.");
    const auto frame = place(host, "wooden_frame", 0, 0, 0, "frame");
    check(get<std::string>(ground_inspection(host), "status") == "missing_mount",
          "A frame alone does not become a machine.");
    const auto mount = place(host, "tool_mount", -1, 0, 0, "mount");
    const auto edge = place(host, "cutting_edge", -2, 0, 0, "edge");
    const auto receiver = place(host, "receiver_tray", 0, 0, 1, "receiver");
    check(get<std::string>(ground_inspection(host), "status") == "missing_shaft",
          "The exposed edge and tray still need a geometric drive endpoint.");
    const auto shaft = place(host, "wooden_shaft", 1, 0, 0, "shaft");
    const auto ready = ground_inspection(host);
    const auto parts = get<O>(ready, "parts");
    check(get<std::string>(ready, "status") == "ready" &&
          get<std::string>(V(parts), "frame") == frame &&
          get<std::string>(V(parts), "mount") == mount &&
          get<std::string>(V(parts), "edge") == edge &&
          get<std::string>(V(parts), "receiver") == receiver &&
          get<std::string>(V(parts), "shaft") == shaft,
          "Readiness names the exact five installed identities, not a recipe token.");
    const auto saved = host.checkpoint();
    check(get<bool>(host.validate_checkpoint(saved), "accepted"),
          "A complete component layout validates as an ordinary native checkpoint.");
    Host restored;
    check(get<bool>(restored.initialize_arrival("assembly-site", {"P"}), "accepted") &&
          get<bool>(restored.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(restored.restore_checkpoint(saved), "accepted") &&
          get<std::string>(ground_inspection(restored), "status") == "ready",
          "A fresh Host derives the same collector candidate after restore.");
    check(get<bool>(restored.publish_actor("P", {V(2.0), V(1.0), V(0.0)}, 5), "accepted"),
          "The restored actor publishes a current physical pose before edits.");
    auto take_shaft = request("take-shaft", "reclaim_component");
    take_shaft.emplace("entity", V(shaft));
    check(get<bool>(restored.command("P", take_shaft), "accepted") &&
          get<std::string>(ground_inspection(restored), "status") == "missing_shaft",
          "Removing the actual shaft immediately removes collector readiness.");
    auto take_tray = request("take-tray", "reclaim_component");
    take_tray.emplace("entity", V(receiver));
    check(get<bool>(restored.command("P", take_tray), "accepted"),
          "The original receiver is recovered without losing its material.");
    const auto mirrored_tray = place(restored, "receiver_tray", 0, 0, -1, "mirrored-tray");
    const auto side_shaft = place(restored, "wooden_shaft", 0, 0, 1, "side-shaft");
    const auto mirrored = ground_inspection(restored);
    check(get<std::string>(mirrored, "status") == "ready" &&
          get<std::string>(V(get<O>(mirrored, "parts")), "receiver") == mirrored_tray &&
          get<std::string>(V(get<O>(mirrored, "parts")), "shaft") == side_shaft,
          "The same conserved components support a second receiver and drive layout.");
}
}  // namespace

int main() {
    try {
        collector_readiness_tracks_real_parts();
        std::cout << "collector_assembly_host_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "collector_assembly_host_test: " << error.what() << '\n';
        return 1;
    }
}
