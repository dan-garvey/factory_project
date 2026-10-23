#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <cmath>
#include <iostream>
#include <stdexcept>
#include <tuple>

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
          get<bool>(V(hub), "installed") && get<A>(view, "fabrication_benches").empty() &&
          !factory::values::typed_difference(V(get<A>(V(hub), "center")),
              V(A{V(I{2}), V(I{0}), V(I{4})})),
          "The bench has its own identity on the shared east deck tile.");
    const auto beacon = get<O>(view, "freight_beacon");
    check(get<std::string>(V(beacon), "id") == "first-freight-beacon" &&
          !get<bool>(V(beacon), "order_complete") &&
          get<I>(V(beacon), "shipped_products") == 0 &&
          !factory::values::typed_difference(V(get<A>(V(beacon), "center")),
              V(A{V(I{6}), V(I{0}), V(I{4})})),
          "One empty freight beacon has a native identity five tiles beyond the pod center.");
    const auto trees = get<O>(view, "hand_sources");
    const auto south = get<A>(trees.at("tree-east-south"), "position");
    const auto north = get<A>(trees.at("tree-east-north"), "position");
    check(std::abs(std::get<double>(south[0].storage()) - 6.6) < 1e-8 &&
          std::abs(std::get<double>(south[2].storage()) - 3.3) < 1e-8 &&
          std::abs(std::get<double>(north[0].storage()) - 6.6) < 1e-8 &&
          std::abs(std::get<double>(north[2].storage()) - 11.55) < 1e-8,
          "Both finite east timber sites stand beyond the pod deck and its east bench.");
    const auto recipes = get<O>(view, "component_recipes");
    check(recipes.size() == 12 && get<I>(view, "component_capacity") == 20 &&
          get<I>(recipes.at("wooden_frame"), "timber") == 3 &&
          get<I>(recipes.at("wooden_frame"), "softmetal") == 0 &&
          get<I>(recipes.at("wooden_workbench"), "timber") == 4 &&
          get<I>(recipes.at("wooden_workbench"), "softmetal") == 0 &&
          get<I>(recipes.at("softmetal_cog"), "timber") == 0 &&
          get<I>(recipes.at("softmetal_cog"), "softmetal") == 2,
          "The normal consumer receives every native recipe cost and the carried component limit.");
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
    const auto& p_spawn = get<A>(actors.at("P"), "position");
    const auto& q_spawn = get<A>(actors.at("Q"), "position");
    // Independent envelope from the retained opened-pod mesh: its frontmost
    // hatch begins at z = 6.6 - 0.94 - 0.71 / 2. Keep the whole native capsule
    // on the nine-panel deck and in front of that envelope, with a small gap.
    constexpr double radius = 0.3;
    constexpr double hull_front = 6.6 - 0.94 - 0.71 / 2.0;
    for (const auto* spawn : {&p_spawn, &q_spawn}) {
        const auto x = std::get<double>((*spawn)[0].storage());
        const auto z = std::get<double>((*spawn)[2].storage());
        check(x - radius >= -0.825 && x + radius <= 4.125 &&
              z - radius >= 4.125 && z + radius + 0.1 <= hull_front,
              "Each complete arrival capsule starts on the clear front deck, outside the visible pod hull.");
    }
    check(std::hypot(std::get<double>(p_spawn[0].storage()) - std::get<double>(q_spawn[0].storage()),
          std::get<double>(p_spawn[2].storage()) - std::get<double>(q_spawn[2].storage())) >= 2 * radius + 0.1,
          "The two default arrival capsules have a positive separation.");
    check(factory::values::typed_difference(V(get<A>(actors.at("P"), "position")),
          V(get<A>(actors.at("Q"), "position"))).has_value(),
          "The two actors receive distinct deck positions without duplicate pod stock.");
    check(get<bool>(host.publish_actor("P", p_spawn, 1), "accepted") &&
          get<bool>(host.publish_actor("Q", q_spawn, 1), "accepted"),
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
    other.at("cell") = V(A{V(I{1}), V(I{2})});
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
          std::get<A>(get<O>(restored.projection(), "part_specifications").at("P").storage()).size() == 3,
          "The restored arrival offers three finite route recipes but no complete collector or press.");
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
void fabricated_transmission_stock_is_finite() {
    Host host;
    initialized(host);
    const auto recipes = get<A>(host.projection(), "part_recipes");
    check(recipes.size() == 3, "Arrival projects three powered-route recipes without gifting their kits.");
    check(get<bool>(host.publish_actor("P", {V(3.3), V(1.0), V(6.6)}, 1), "accepted"),
          "The actor reaches the actual pod workshop before trying a route recipe.");
    const auto craft = [](const std::string& request, const char* role, I span) {
        return O{{"context", V("arrival-site")}, {"client", V("P")},
            {"request", V(request)}, {"action", V("craft_part")},
            {"entity", V("pod-fabrication-hub")}, {"role", V(role)},
            {"half_span", V(span)}};
    };
    const auto empty = host.command("P", craft("empty-shaft", "shaft", 2));
    check(!get<bool>(empty, "accepted") && get<std::string>(empty, "reason") == "unavailable_input",
          "The bench refuses a shaft without real harvested timber.");
    check(get<bool>(host.publish_actor("P", {V(6.6), V(1.0), V(3.3)}, 2), "accepted"),
          "The physical actor reaches the first finite tree.");
    for (int index = 0; index < 8; ++index) {
        const O cut{{"context", V("arrival-site")}, {"client", V("P")},
            {"request", V("timber-" + std::to_string(index))}, {"action", V("harvest_source")},
            {"target", V("tree-east-south")}};
        check(get<bool>(host.command("P", cut), "accepted"),
              "Each route timber input comes from the finite visible tree.");
    }
    check(get<bool>(host.publish_actor("P", {V(0.0), V(1.0), V(1.65)}, 3), "accepted"),
          "The actor reaches the finite softmetal outcrop.");
    for (int index = 0; index < 2; ++index) {
        const O cut{{"context", V("arrival-site")}, {"client", V("P")},
            {"request", V("ore-" + std::to_string(index))}, {"action", V("harvest_source")},
            {"target", V("opening-softmetal")}};
        check(get<bool>(host.command("P", cut), "accepted"),
              "Each route clasp input comes from the finite native deposit.");
    }
    check(get<bool>(host.publish_actor("P", {V(3.3), V(1.0), V(6.6)}, 4), "accepted"),
          "The actor returns to the single fabrication hub with actual cargo.");
    for (const auto& [name, role, span] : {
            std::tuple{"shaft-a", "shaft", I{2}}, std::tuple{"shaft-b", "shaft", I{2}},
            std::tuple{"shaft-c", "shaft", I{2}},
            std::tuple{"belt", "belt", I{0}}, std::tuple{"wheel", "waterwheel", I{0}}}) {
        const auto made = host.command("P", craft(name, role, span));
        check(get<bool>(made, "accepted"), "The pod converts actual cargo into one native stationary kit.");
    }
    const auto view = host.projection();
    const auto kit = std::get<O>(get<O>(view, "part_kits").at("P").storage());
    const auto cargo = std::get<O>(get<O>(view, "cargo").at("P").storage());
    check(get<I>(V(kit), "shaft") == 3 && get<I>(V(kit), "belt") == 1 &&
          get<I>(V(kit), "wheel") == 1 && get<I>(V(cargo), "timber") == 1 &&
          get<I>(V(cargo), "raw") == 0,
          "Three shafts, one belt and one wheel embody seven timber and two ore without gifted stock.");
    const auto saved = host.checkpoint();
    check(get<bool>(host.validate_checkpoint(saved), "accepted"),
          "The World checkpoint binds recipe, actor kit custody and spent material history.");
    Host reopened;
    initialized(reopened);
    check(get<bool>(reopened.restore_checkpoint(saved), "accepted") &&
          !factory::values::typed_difference(saved, reopened.checkpoint()),
          "A fresh native process restores the exact fabricated kit and remaining source stock.");
    const auto retried = host.command("P", craft("shaft-a", "shaft", 2));
    check(get<bool>(retried, "accepted") && get<bool>(retried, "duplicate") &&
          !factory::values::typed_difference(saved, host.checkpoint()),
          "Retrying the original shaft receipt cannot consume another timber or mint another kit.");
    auto forged = std::get<O>(saved.storage());
    auto world = std::get<O>(forged.at("world").storage());
    auto state = std::get<O>(world.at("state").storage());
    auto kits = std::get<O>(state.at("kits").storage());
    auto stock = std::get<A>(kits.at("P").storage());
    bool found_shaft = false;
    for (auto& item : stock) {
        auto entry = std::get<O>(item.storage());
        if (get<I>(V(entry), "role") != static_cast<I>(factory::stationary::Role::shaft)) continue;
        entry.at("count") = V(get<I>(V(entry), "count") + 1);
        item = V(std::move(entry));
        found_shaft = true;
    }
    check(found_shaft, "The checkpoint carries one explicit fabricated shaft specification.");
    kits.at("P") = V(std::move(stock));
    state.at("kits") = V(std::move(kits));
    auto material = std::get<O>(state.at("material").storage());
    auto cargo_table = std::get<O>(material.at("cargo").storage());
    auto player = std::get<O>(cargo_table.at("P").storage());
    player.at("timber") = V(get<I>(V(player), "timber") - 1);
    cargo_table.at("P") = V(std::move(player));
    material.at("cargo") = V(std::move(cargo_table));
    material.at("fabricated_timber") = V(get<I>(V(material), "fabricated_timber") + 1);
    state.at("material") = V(std::move(material));
    world.at("state") = V(std::move(state));
    forged.at("world") = V(std::move(world));
    Host forged_target;
    initialized(forged_target);
    const auto fresh_before = forged_target.checkpoint();
    check(!get<bool>(host.validate_checkpoint(V(forged)), "accepted") &&
          !get<bool>(forged_target.restore_checkpoint(V(std::move(forged))), "accepted") &&
          !factory::values::typed_difference(fresh_before, forged_target.checkpoint()),
          "A forged extra shaft fails even if its timber bill is made arithmetically conserved.");
}
}  // namespace

int main() {
    try {
        arrival_projection_and_restore();
        historical_initializer_keeps_its_fixture_kit();
        unique_crank_custody_survives_host_restore();
        fabricated_transmission_stock_is_finite();
        std::cout << "arrival_host_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "arrival_host_test: " << error.what() << '\n';
        return 1;
    }
}
