#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <cmath>
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
    const auto trees = get<O>(view, "hand_sources");
    const auto south = get<A>(trees.at("tree-east-south"), "position");
    const auto north = get<A>(trees.at("tree-east-north"), "position");
    check(std::abs(std::get<double>(south[0].storage()) - 6.6) < 1e-8 &&
          std::abs(std::get<double>(south[2].storage()) - 3.3) < 1e-8 &&
          std::abs(std::get<double>(north[0].storage()) - 6.6) < 1e-8 &&
          std::abs(std::get<double>(north[2].storage()) - 11.55) < 1e-8,
          "Both finite east timber sites stand beyond the pod deck and its east bench.");
    const auto floors = get<O>(view, "foundations");
    check(floors.size() == 9 && floors.contains("pod-floor-0") && floors.contains("pod-floor-8"),
          "The unfolding pod supplied exactly nine ordinary visible foundation identities.");
    const auto kits = get<O>(view, "part_kits");
    check(get<I>(kits.at("P"), "foundation") == 15 &&
          get<I>(kits.at("Q"), "foundation") == 0,
          "Only the initial shared stock supplied the deck and remaining carried floor parts.");
    for (const auto& [actor, stock] : kits)
        for (const auto& [name, count] : std::get<O>(stock.storage()))
            if (name != "foundation")
                check(std::get<I>(count.storage()) == 0,
                      "Arrival must not gift a complete machine or transmission part to either actor.");
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
    auto forged = std::get<O>(saved.storage());
    auto forged_world = std::get<O>(forged.at("world").storage());
    auto forged_state = std::get<O>(forged_world.at("state").storage());
    auto forged_kits = std::get<O>(forged_state.at("foundation_kits").storage());
    forged_kits.at("P") = V(I{13});
    forged_kits.at("Q") = V(I{1});
    forged_state.at("foundation_kits") = V(std::move(forged_kits));
    forged_world.at("state") = V(std::move(forged_state));
    forged.at("world") = V(std::move(forged_world));
    const auto transferred = V(std::move(forged));
    Host fresh;
    initialized(fresh);
    const auto fresh_checkpoint = fresh.checkpoint();
    check(!get<bool>(host.validate_checkpoint(transferred), "accepted") &&
          !get<bool>(fresh.restore_checkpoint(transferred), "accepted") &&
          !factory::values::typed_difference(fresh_checkpoint, fresh.checkpoint()),
          "Host refuses a conserved but unrecorded transfer of one foundation from P to Q without changing the fresh site.");
    Host restored;
    initialized(restored);
    check(get<bool>(restored.restore_checkpoint(saved), "accepted") &&
          !factory::values::typed_difference(saved, restored.checkpoint()),
          "Late join and restore retain one settled pod with the exact same foundation custody.");
    check(get<I>(get<O>(restored.projection(), "part_kits").at("P"), "collector") == 0 &&
          get<I>(get<O>(restored.projection(), "part_kits").at("P"), "processor") == 0 &&
          std::get<A>(get<O>(restored.projection(), "part_specifications").at("P").storage()).empty(),
          "The restored arrival still carries no complete collector or press.");
}

void historical_initializer_keeps_its_fixture_kit() {
    Host host;
    check(get<bool>(host.initialize("legacy-site", {"P"}), "accepted"),
          "The historical initializer remains available for its existing fixture.");
    const auto kits = get<O>(host.projection(), "part_kits");
    check(get<I>(kits.at("P"), "collector") == 1 &&
          get<I>(kits.at("P"), "processor") == 1 &&
          get<I>(kits.at("P"), "shaft") == 8,
          "The historical initializer keeps its original complete-machine kit.");
}
void unique_crank_custody_survives_host_restore() {
    Host host;
    initialized(host);
    const auto initial = get<O>(host.projection(), "hand_crank");
    check(get<std::string>(V(initial), "id") == "pod-hand-crank" &&
          get<std::string>(V(initial), "holder") == "pod",
          "The pod exposes one detachable crank in its tray.");
    check(get<bool>(host.publish_actor("P", {V(1.65), V(1.0), V(6.6)}, 1), "accepted") &&
          get<bool>(host.publish_actor("Q", {V(1.65), V(1.0), V(8.25)}, 1), "accepted"),
          "Both actors can reach the pod tray.");
    const auto command = [](const char* actor, const char* request, const char* action) {
        return O{{"context", V("arrival-site")}, {"client", V(actor)},
            {"request", V(request)}, {"action", V(action)},
            {"entity", V("pod-hand-crank")}};
    };
    const auto take = command("P", "take-crank", "take_hand_crank");
    check(get<bool>(host.command("P", take), "accepted") &&
          get<std::string>(V(get<O>(host.projection(), "hand_crank")), "holder") == "P",
          "Taking the crank transfers the single identity into P's custody.");
    check(get<bool>(host.command("P", take), "duplicate") &&
          get<std::string>(V(get<O>(host.projection(), "hand_crank")), "holder") == "P",
          "A repeated Host command does not duplicate the crank.");
    const auto other_take = host.command("Q", command("Q", "Q-take", "take_hand_crank"));
    check(!get<bool>(other_take, "accepted") &&
          get<std::string>(other_take, "reason") == "crank_held",
          "Another actor cannot take the held crank.");
    const auto saved = host.checkpoint();
    check(get<bool>(host.validate_checkpoint(saved), "accepted"),
          "Host validates a checkpoint with actor-held crank custody.");
    Host restored;
    initialized(restored);
    check(get<bool>(restored.restore_checkpoint(saved), "accepted") &&
          get<std::string>(V(get<O>(restored.projection(), "hand_crank")), "holder") == "P",
          "Late join preserves the exact holder of the unique crank.");
    check(get<bool>(restored.publish_actor("P", {V(1.65), V(1.0), V(6.6)}, 2), "accepted") &&
          get<bool>(restored.publish_actor("Q", {V(1.65), V(1.0), V(8.25)}, 2), "accepted"),
          "Restored actors publish fresh physical observations before new commands.");
    check(get<bool>(restored.command("P", command("P", "return-crank", "return_hand_crank")), "accepted") &&
          get<std::string>(V(get<O>(restored.projection(), "hand_crank")), "holder") == "pod",
          "The holder can return the crank to its tray after restore.");
    check(get<bool>(restored.command("Q", command("Q", "Q-take-after", "take_hand_crank")), "accepted") &&
          get<std::string>(V(get<O>(restored.projection(), "hand_crank")), "holder") == "Q",
          "The other actor can then take the same crank.");
}
}  // namespace

int main() {
    try {
        arrival_projection_and_restore();
        historical_initializer_keeps_its_fixture_kit();
        unique_crank_custody_survives_host_restore();
        std::cout << "arrival_host_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "arrival_host_test: " << error.what() << '\n';
        return 1;
    }
}
