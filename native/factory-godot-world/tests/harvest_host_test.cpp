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

O cut(const char* client, const char* request, const char* target) {
    return {{"context", V("harvest-site")}, {"client", V(client)}, {"request", V(request)},
        {"action", V("harvest_source")}, {"target", V(target)}};
}

O craft(const char* client, const char* request, const char* component) {
    return {{"context", V("harvest-site")}, {"client", V(client)}, {"request", V(request)},
        {"action", V("craft_component")}, {"entity", V("pod-fabrication-hub")},
        {"component", V(component)}};
}

void shared_harvest() {
    Host host;
    check(get<bool>(host.initialize_arrival("harvest-site", {"P", "Q"}), "accepted") &&
          get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()), "accepted"),
          "The trusted arrival site initializes one native source roster.");
    const auto initial = host.projection();
    const auto sources = get<O>(initial, "hand_sources");
    check(sources.size() == 4 && get<I>(sources.at("tree-east-south"), "remaining") == 8 &&
          get<I>(sources.at("opening-softmetal"), "remaining") == 16,
          "Three finite trees and one shared ore reserve are visible to both actors.");
    check(get<bool>(host.publish_actor("P", {V(3.3), V(1.0), V(4.95)}, 1), "accepted") &&
          get<bool>(host.publish_actor("Q", {V(1.65), V(1.0), V(8.25)}, 1), "accepted"),
          "P walks to the clear east timber site while Q remains on the deployed deck.");
    const auto p_cut = cut("P", "tree-first", "tree-east-south");
    check(get<bool>(host.command("P", p_cut), "accepted") &&
          get<I>(get<O>(host.projection(), "hand_sources").at("tree-east-south"), "remaining") == 7 &&
          get<I>(get<O>(host.projection(), "cargo").at("P"), "timber") == 1,
          "The first tool action moves exactly one timber into P's native cargo.");
    const auto after_first = host.checkpoint();
    check(get<bool>(host.command("P", p_cut), "duplicate") &&
          !factory::values::typed_difference(after_first, host.checkpoint()),
          "Repeating the exact wire request cannot debit the tree twice.");
    auto forged = std::get<O>(after_first.storage());
    auto native = std::get<O>(forged.at("world").storage());
    auto state = std::get<O>(native.at("state").storage());
    auto material = std::get<O>(state.at("material").storage());
    auto cargo = std::get<O>(material.at("cargo").storage());
    auto p_cargo = std::get<O>(cargo.at("P").storage());
    auto q_cargo = std::get<O>(cargo.at("Q").storage());
    p_cargo.at("timber") = V(I{0});
    q_cargo.at("timber") = V(I{1});
    cargo.at("P") = V(std::move(p_cargo));
    cargo.at("Q") = V(std::move(q_cargo));
    material.at("cargo") = V(std::move(cargo));
    state.at("material") = V(std::move(material));
    native.at("state") = V(std::move(state));
    forged.at("world") = V(std::move(native));
    const V stolen(std::move(forged));
    check(!get<bool>(host.validate_checkpoint(stolen), "accepted") &&
          !get<bool>(host.restore_checkpoint(stolen), "accepted") &&
          !factory::values::typed_difference(after_first, host.checkpoint()),
          "A Host refuses cross-actor timber custody forgery without changing its worksite.");
    const auto far = host.command("Q", cut("Q", "far-tree", "tree-east-south"));
    check(!get<bool>(far, "accepted") && get<std::string>(far, "reason") == "out_of_reach" &&
          get<I>(get<O>(host.projection(), "cargo").at("Q"), "timber") == 0,
          "A second actor cannot cut a tree outside physical reach.");
    check(get<bool>(host.publish_actor("Q", {V(1.65), V(1.0), V(1.65)}, 2), "accepted"),
          "Q can reach the ore side of the site with a new physical observation.");
    check(get<bool>(host.command("Q", cut("Q", "ore-first", "opening-softmetal")), "accepted") &&
          get<I>(get<O>(host.projection(), "hand_sources").at("opening-softmetal"), "remaining") == 15 &&
          get<I>(get<O>(host.projection(), "cargo").at("Q"), "raw") == 1,
          "Manual ore mining debits the same source that feeds a future collector.");
    const auto bench = get<O>(host.projection(), "fabrication_hub");
    check(get<std::string>(V(bench), "id") == "pod-fabrication-hub" &&
          get<I>(V(bench), "generation") == 1,
          "One native bench identity is shared by both actors.");
    const auto first_part = craft("P", "wooden-shaft", "wooden_shaft");
    check(get<bool>(host.command("P", first_part), "accepted") &&
          get<I>(V(get<O>(get<O>(host.projection(), "cargo").at("P"), "components")), "wooden_shaft") == 1 &&
          get<I>(get<O>(host.projection(), "cargo").at("P"), "timber") == 0,
          "P shapes its own harvested timber into one typed shaft at the local bench.");
    const auto after_part = host.checkpoint();
    check(get<bool>(host.command("P", first_part), "duplicate") &&
          !factory::values::typed_difference(after_part, host.checkpoint()),
          "A cached craft wire cannot spend timber or add a second shaft.");
    const auto remote = host.command("Q", craft("Q", "remote-edge", "cutting_edge"));
    check(!get<bool>(remote, "accepted") && get<std::string>(remote, "reason") == "out_of_reach" &&
          get<I>(get<O>(host.projection(), "cargo").at("Q"), "raw") == 1,
          "Ore-side Q cannot use the bench at a distance.");
    check(get<bool>(host.publish_actor("Q", {V(1.65), V(1.0), V(6.6)}, 3), "accepted") &&
          get<bool>(host.command("Q", craft("Q", "near-edge", "cutting_edge")), "accepted") &&
          get<I>(V(get<O>(get<O>(host.projection(), "cargo").at("Q"), "components")), "cutting_edge") == 1 &&
          get<I>(get<O>(host.projection(), "cargo").at("Q"), "raw") == 0,
          "Q's own ore becomes one metal cutting edge after physically reaching the hub.");
    check(get<bool>(host.publish_actor("P", {V(1.65), V(1.0), V(6.6)}, 2), "accepted"),
          "P leaves the remote timber site before installing a part on the deck.");
    const O place{{"context", V("harvest-site")}, {"client", V("P")},
        {"request", V("install-shaft")}, {"action", V("place_component")},
        {"component", V("wooden_shaft")}, {"center", V(A{V(I{8}), V(I{0}), V(I{12})})}};
    const auto installed = host.command("P", place);
    check(get<bool>(installed, "accepted") &&
          get<O>(host.projection(), "placed_components").size() == 1 &&
          get<O>(get<O>(host.projection(), "cargo").at("P"), "components").empty(),
          "Host projects the single installed shaft and debits the actor's component cargo.");
    const auto installed_id = get<std::string>(installed, "entity");
    const auto installed_position = get<A>(get<O>(host.projection(), "placed_components").at(installed_id), "position");
    check(installed_position.size() == 3 &&
          std::abs(std::get<double>(installed_position[0].storage()) - 3.3) < 1e-8 &&
          std::abs(std::get<double>(installed_position[1].storage()) - 0.825) < 1e-8 &&
          std::abs(std::get<double>(installed_position[2].storage()) - 4.95) < 1e-8 &&
          get<bool>(host.command("P", place), "duplicate"),
          "The shaft uses the shared quarter-grid transform and exact wire retry.");
    const O overlap{{"context", V("harvest-site")}, {"client", V("Q")},
        {"request", V("overlap-shaft")}, {"action", V("place_component")},
        {"component", V("cutting_edge")}, {"center", V(A{V(I{8}), V(I{0}), V(I{12})})}};
    const auto blocked = host.command("Q", overlap);
    check(!get<bool>(blocked, "accepted") && get<std::string>(blocked, "reason") == "occupied" &&
          get<I>(V(get<O>(get<O>(host.projection(), "cargo").at("Q"), "components")), "cutting_edge") == 1,
          "A second part cannot occupy the same quarter-grid center or consume its input on refusal.");
    const O reclaim{{"context", V("harvest-site")}, {"client", V("Q")},
        {"request", V("take-shaft")}, {"action", V("reclaim_component")},
        {"entity", V(installed_id)}};
    check(get<bool>(host.command("Q", reclaim), "accepted") &&
          get<O>(host.projection(), "placed_components").empty() &&
          get<I>(V(get<O>(get<O>(host.projection(), "cargo").at("Q"), "components")), "wooden_shaft") == 1,
          "Q reclaims the real shaft into Q's cargo without recreating it.");
    const auto saved = host.checkpoint();
    check(get<bool>(host.validate_checkpoint(saved), "accepted"),
          "The real Host checkpoint validates tree and ore custody.");
    Host restored;
    check(get<bool>(restored.initialize_arrival("harvest-site", {"P", "Q"}), "accepted") &&
          get<bool>(restored.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(restored.restore_checkpoint(saved), "accepted") &&
          !factory::values::typed_difference(saved, restored.checkpoint()),
          "A fresh Host restores both actors and all finite source balances.");
}
}  // namespace

int main() {
    try {
        shared_harvest();
        std::cout << "harvest_host_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "harvest_host_test: " << error.what() << '\n';
        return 1;
    }
}
