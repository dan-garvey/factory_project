#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <iostream>
#include <stdexcept>

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

void initialized(Host& host) {
    check(get<bool>(host.initialize_arrival("arrival-site", {"P", "Q"}), "accepted"),
          "The new native opening initializes one pod for a shared roster.");
    check(get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()), "accepted"),
          "The normal terrain producer still binds the authored site.");
}

void arrival_projection_and_restore() {
    Host host;
    initialized(host);
    const auto view = host.projection();
    const auto pod = get<O>(view, "landing_pod");
    check(get<std::string>(V(pod), "id") == "landing-pod" &&
          get<bool>(V(pod), "deployed") && get<bool>(V(pod), "hub_ready") &&
          !factory::values::typed_difference(V(get<A>(V(pod), "center")),
              V(A{V(I{1}), V(I{0}), V(I{4})})),
          "The view describes a settled pod with a usable local fabrication hub.");
    const auto hub = get<O>(view, "fabrication_hub");
    check(get<std::string>(V(hub), "id") == "pod-fabrication-hub" &&
          !factory::values::typed_difference(V(get<A>(V(hub), "center")),
              V(A{V(I{2}), V(I{0}), V(I{4})})),
          "The bench has its own identity on the shared east deck tile.");
    const auto floors = get<O>(view, "foundations");
    check(floors.size() == 9 && floors.contains("pod-floor-0") && floors.contains("pod-floor-8"),
          "The unfolding pod supplied exactly nine ordinary visible foundation identities.");
    const auto kits = get<O>(view, "part_kits");
    check(get<I>(kits.at("P"), "foundation") == 15 &&
          get<I>(kits.at("Q"), "foundation") == 0,
          "Only the initial shared stock supplied the deck and remaining carried floor parts.");
    const auto actors = get<O>(view, "actors");
    check(factory::values::typed_difference(V(get<A>(actors.at("P"), "position")),
          V(get<A>(actors.at("Q"), "position"))).has_value(),
          "The two actors receive distinct deck positions without duplicate pod stock.");
    check(get<bool>(host.publish_actor("P", {V(1.65), V(1.0), V(6.6)}, 1), "accepted") &&
          get<bool>(host.publish_actor("Q", {V(1.65), V(1.0), V(8.25)}, 1), "accepted"),
          "Both physical actors can become ready on the same deployed deck.");
    const O build{{"context", V("arrival-site")}, {"client", V("P")},
        {"request", V("expand-east")}, {"action", V("place_foundation")},
        {"cell", V(A{V(I{3}), V(I{4})})}, {"level", V(I{0})}};
    const auto first = host.command("P", build);
    check(get<bool>(first, "accepted") &&
          get<I>(get<O>(host.projection(), "part_kits").at("P"), "foundation") == 14,
          "A physical player can extend the pod using one of the fifteen remaining parts.");
    check(get<bool>(host.command("P", build), "duplicate") &&
          get<I>(get<O>(host.projection(), "part_kits").at("P"), "foundation") == 14,
          "A retried construction command cannot mint another tile or spend twice.");
    auto other = build;
    other.at("client") = V("Q");
    other.at("request") = V("Q-expand");
    other.at("cell") = V(A{V(I{3}), V(I{5})});
    const auto q_result = host.command("Q", other);
    check(!get<bool>(q_result, "accepted") &&
          get<std::string>(q_result, "reason") == "no_part" &&
          get<I>(get<O>(host.projection(), "part_kits").at("Q"), "foundation") == 0,
          "The second actor sees shared foundations without receiving a second kit.");
    const auto saved = host.checkpoint();
    check(get<bool>(host.validate_checkpoint(saved), "accepted"),
          "The normal physical checkpoint validates the pod and both actors.");
    Host restored;
    initialized(restored);
    check(get<bool>(restored.restore_checkpoint(saved), "accepted") &&
          !factory::values::typed_difference(saved, restored.checkpoint()),
          "Late join and restore retain one settled pod with the exact same foundation custody.");
}
}  // namespace

int main() {
    try {
        arrival_projection_and_restore();
        std::cout << "arrival_host_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "arrival_host_test: " << error.what() << '\n';
        return 1;
    }
}
