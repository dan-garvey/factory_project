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

O shape(const char* client, const char* request, const char* component) {
    return {{"context", V("field-site")}, {"client", V(client)}, {"request", V(request)},
        {"action", V("field_craft")}, {"component", V(component)}};
}

O field_cut(const char* request) {
    return {{"context", V("field-site")}, {"client", V("P")}, {"request", V(request)},
        {"action", V("harvest_source")}, {"target", V("tree-east-south")}};
}

void field_wood_uses_physical_actor_and_one_ledger() {
    Host host;
    check(get<bool>(host.initialize_arrival("field-site", {"P", "Q"}), "accepted") &&
          get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(host.publish_actor("P", {V(6.6), V(1.0), V(3.3)}, 1), "accepted") &&
          get<bool>(host.publish_actor("Q", {V(3.3), V(1.0), V(8.25)}, 1), "accepted"),
          "Two physical actors initialize, with P beyond the pod bench's reach.");
    for (int index = 0; index < 4; ++index) {
        const auto request = "field-cut-" + std::to_string(index);
        const auto outcome = host.command("P", field_cut(request.c_str()));
        check(get<bool>(outcome, "accepted"),
              "The multitool moves one finite timber from the field tree into P's cargo.");
    }
    const auto made = shape("P", "field-frame", "wooden_frame");
    check(get<bool>(host.command("P", made), "accepted") &&
          get<I>(get<O>(host.projection(), "cargo").at("P"), "timber") == 1 &&
          get<I>(V(get<O>(get<O>(host.projection(), "cargo").at("P"), "components")), "wooden_frame") == 1 &&
          get<I>(get<O>(host.projection(), "hand_sources").at("tree-east-south"), "remaining") == 4,
          "P shapes a wooden frame at the tree while the distant bench stays unused.");
    const auto after = host.checkpoint();
    check(get<bool>(host.command("P", made), "duplicate") &&
          !factory::values::typed_difference(after, host.checkpoint()),
          "The exact Host wire replay does not create another wooden frame.");
    const auto metal = host.command("P", shape("P", "field-metal", "cutting_edge"));
    check(!get<bool>(metal, "accepted") && get<std::string>(metal, "reason") == "unavailable_recipe" &&
          get<I>(get<O>(host.projection(), "cargo").at("P"), "timber") == 1 &&
          get<I>(V(get<O>(get<O>(host.projection(), "cargo").at("P"), "components")), "wooden_frame") == 1 &&
          get<I>(get<O>(host.projection(), "hand_sources").at("tree-east-south"), "remaining") == 4,
          "The same tool refuses metal forming in the field without changing custody.");
    const auto other = host.command("Q", shape("Q", "other-wood", "wooden_shaft"));
    check(!get<bool>(other, "accepted") && get<std::string>(other, "reason") == "unavailable_input" &&
          get<I>(get<O>(host.projection(), "cargo").at("P"), "timber") == 1,
          "Q cannot spend P's carried timber with the same field tool command.");
    check(get<bool>(host.validate_checkpoint(host.checkpoint()), "accepted"),
          "Host validates the shaped frame and both actors' conserved cargo.");
    Host restored;
    check(get<bool>(restored.initialize_arrival("field-site", {"P", "Q"}), "accepted") &&
          get<bool>(restored.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(restored.restore_checkpoint(host.checkpoint()), "accepted") &&
          !factory::values::typed_difference(host.checkpoint(), restored.checkpoint()),
          "Fresh Host continuation retains the field craft, finite timber and refused requests.");
    check(get<bool>(restored.publish_actor("P", {V(3.3), V(1.0), V(4.8)}, 2), "accepted") &&
          get<bool>(restored.command("P", O{{"context", V("field-site")}, {"client", V("P")},
              {"request", V("bench-shaft")}, {"action", V("craft_component")},
              {"entity", V("pod-fabrication-hub")}, {"component", V("wooden_shaft")}}), "accepted"),
          "The existing pod bench still crafts from the remaining carried timber after restore.");
}

void opening_actor_carries_finite_site_across_restore() {
    Host host;
    check(get<bool>(host.initialize_arrival("harvest-site", {"P"}), "accepted") &&
          get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()), "accepted"),
          "The opening actor starts with finite native sources.");
    int epoch = 0;
    int cuts = 0;
    for (const char* source : {"tree-east-south", "tree-east-north", "tree-north", "tree-east-upstream"}) {
        const auto source_view = get<O>(host.projection(), "hand_sources").at(source);
        const auto position = get<A>(source_view, "position");
        check(get<bool>(host.publish_actor("P", {position[0], V(1.0), position[2]}, ++epoch), "accepted"),
              "The actor reaches each distinct finite tree.");
        while (get<I>(get<O>(host.projection(), "hand_sources").at(source), "remaining") > 0) {
            const auto request = "carry-cut-" + std::to_string(++cuts);
            const auto result = host.command("P", cut("P", request.c_str(), source));
            if (!get<bool>(result, "accepted"))
                throw std::runtime_error(std::string("Harvest refused at ") + source + " after " +
                    std::to_string(cuts) + " cuts: " + get<std::string>(result, "reason"));
        }
    }
    check(cuts > 24 && get<I>(get<O>(host.projection(), "cargo").at("P"), "timber") == cuts &&
          get<bool>(host.validate_checkpoint(host.checkpoint()), "accepted"),
          "The actor carries more than the former bag limit without minting or losing timber.");
    Host reopened;
    check(get<bool>(reopened.initialize_arrival("harvest-site", {"P"}), "accepted") &&
          get<bool>(reopened.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(reopened.restore_checkpoint(host.checkpoint()), "accepted") &&
          !factory::values::typed_difference(host.checkpoint(), reopened.checkpoint()) &&
          get<I>(get<O>(reopened.projection(), "cargo").at("P"), "timber") == cuts,
          "Save and rejoin retain all carried timber and depleted source stock.");
}

void shared_harvest() {
    Host host;
    check(get<bool>(host.initialize_arrival("harvest-site", {"P", "Q"}), "accepted") &&
          get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()), "accepted"),
          "The trusted arrival site initializes one native source roster.");
    const auto initial = host.projection();
    const auto sources = get<O>(initial, "hand_sources");
    check(sources.size() == 5 && get<I>(sources.at("tree-east-south"), "remaining") == 8 &&
          get<I>(sources.at("opening-softmetal"), "remaining") == 16,
          "Four finite trees and one shared ore reserve are visible to both actors.");
    check(get<bool>(host.publish_actor("P", {V(3.3), V(1.0), V(4.95)}, 1), "accepted") &&
          get<bool>(host.publish_actor("Q", {V(3.3), V(1.0), V(8.25)}, 1), "accepted"),
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
    check(get<bool>(host.publish_actor("Q", {V(0.0), V(1.0), V(4.8)}, 3), "accepted") &&
          get<bool>(host.command("Q", craft("Q", "near-edge", "cutting_edge")), "accepted") &&
          get<I>(V(get<O>(get<O>(host.projection(), "cargo").at("Q"), "components")), "cutting_edge") == 1 &&
          get<I>(get<O>(host.projection(), "cargo").at("Q"), "raw") == 0,
          "Q's own ore becomes one metal cutting edge after physically reaching the hub.");
    check(get<bool>(host.publish_actor("P", {V(1.65), V(1.0), V(4.8)}, 2), "accepted"),
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

void placed_bench_preserves_two_actor_custody() {
    Host host;
    check(get<bool>(host.initialize_arrival("bench-site", {"P", "Q"}), "accepted") &&
          get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(host.publish_actor("P", {V(6.6), V(1.0), V(3.3)}, 1), "accepted") &&
          get<bool>(host.publish_actor("Q", {V(1.65), V(1.0), V(1.65)}, 1), "accepted"),
          "Two actors initialize beside different finite material sources.");
    for (int index = 0; index < 4; ++index) {
        const O cut_wood{{"context", V("bench-site")}, {"client", V("P")},
            {"request", V("bench-timber-" + std::to_string(index))},
            {"action", V("harvest_source")}, {"target", V("tree-east-south")}};
        check(get<bool>(host.command("P", cut_wood), "accepted"),
              "P harvests one of four finite workbench timbers.");
    }
    const O shape_bench{{"context", V("bench-site")}, {"client", V("P")},
        {"request", V("shape-workbench")}, {"action", V("field_craft")},
        {"component", V("wooden_workbench")}};
    check(get<bool>(host.command("P", shape_bench), "accepted") &&
          get<I>(V(get<O>(get<O>(host.projection(), "cargo").at("P"), "components")),
              "wooden_workbench") == 1,
          "P shapes a bench from four carried timbers away from the pod.");
    const O place_bench{{"context", V("bench-site")}, {"client", V("P")},
        {"request", V("place-workbench")}, {"action", V("place_component")},
        {"component", V("wooden_workbench")},
        {"center", V(A{V(I{20}), V(I{0}), V(I{8})})}};
    const auto placed = host.command("P", place_bench);
    check(get<bool>(placed, "accepted"),
          "P installs the wooden bench on a ground tile beyond the pod deck.");
    const auto bench_id = get<std::string>(placed, "entity");
    const auto benches = get<A>(host.projection(), "fabrication_benches");
    check(benches.size() == 1 && get<std::string>(benches.front(), "id") == bench_id &&
          get<I>(benches.front(), "generation") == get<I>(placed, "generation") &&
          get<O>(get<O>(host.projection(), "cargo").at("P"), "components").empty(),
          "Host projects the confirmed bench identity and moves P's part into placed custody.");
    check(get<bool>(host.publish_actor("P", {V(3.3), V(1.0), V(6.6)}, 2), "accepted"),
          "P reaches the pod workshop before unbolting it.");
    const O stow{{"context", V("bench-site")}, {"client", V("P")},
        {"request", V("stow-pod-bench")}, {"action", V("stow_fabrication_hub")},
        {"entity", V("pod-fabrication-hub")}};
    check(get<bool>(host.command("P", stow), "accepted") &&
          !get<bool>(V(get<O>(host.projection(), "fabrication_hub")), "installed") &&
          get<std::string>(V(get<O>(host.projection(), "fabrication_hub")), "holder") == "P",
          "The issued pod workshop moves into P's explicit custody without removing the placed bench.");
    const O mine{{"context", V("bench-site")}, {"client", V("Q")},
        {"request", V("bench-ore")}, {"action", V("harvest_source")},
        {"target", V("opening-softmetal")}};
    check(get<bool>(host.command("Q", mine), "accepted"),
          "Q mines one softmetal blank from the same finite source used by collectors.");
    const O craft_edge{{"context", V("bench-site")}, {"client", V("Q")},
        {"request", V("remote-bench-edge")}, {"action", V("craft_component")},
        {"entity", V(bench_id)}, {"component", V("cutting_edge")}};
    const auto remote = host.command("Q", craft_edge);
    check(!get<bool>(remote, "accepted") && get<std::string>(remote, "reason") == "out_of_reach" &&
          get<I>(get<O>(host.projection(), "cargo").at("Q"), "raw") == 1,
          "Q cannot spend its ore from outside physical bench reach.");
    check(get<bool>(host.publish_actor("Q", {V(8.25), V(1.0), V(4.95)}, 2), "accepted"),
          "Q walks to the player-built bench without moving its inventory into P's custody.");
    auto local_craft = craft_edge;
    local_craft.at("request") = V("local-bench-edge");
    const auto shaped = host.command("Q", local_craft);
    check(get<bool>(shaped, "accepted") &&
          get<I>(V(get<O>(get<O>(host.projection(), "cargo").at("Q"), "components")),
              "cutting_edge") == 1 &&
          get<I>(get<O>(host.projection(), "cargo").at("Q"), "raw") == 0,
          "Q uses the placed bench to cold shape its own ore into one cutting edge.");
    check(get<bool>(host.publish_actor("P", {V(6.6), V(1.0), V(3.3)}, 3), "accepted"),
          "P returns to the timber site while Q's crafted edge remains in Q's cargo.");
    auto fifth_wood = O{{"context", V("bench-site")}, {"client", V("P")},
        {"request", V("bench-fifth-timber")}, {"action", V("harvest_source")},
        {"target", V("tree-east-south")}};
    check(get<bool>(host.command("P", fifth_wood), "accepted"),
          "P harvests one more finite timber for a powered route kit.");
    const O craft_shaft{{"context", V("bench-site")}, {"client", V("P")},
        {"request", V("placed-bench-shaft")}, {"action", V("craft_part")},
        {"entity", V(bench_id)}, {"role", V("shaft")}, {"half_span", V(I{2})}};
    check(get<bool>(host.command("P", craft_shaft), "accepted"),
          "The player-built bench also replaces the pod for finite stationary shaft kits.");
    const O raised_floor{{"context", V("bench-site")}, {"client", V("P")},
        {"request", V("raised-pod-workshop-floor")}, {"action", V("place_foundation")},
        {"cell", V(A{V(I{6}), V(I{2})})}, {"level", V(I{2})}};
    check(get<bool>(host.command("P", raised_floor), "accepted"),
          "P seats a second ordinary foundation at the two-unit height step.");
    const auto saved = host.checkpoint();
    check(get<bool>(host.command("Q", local_craft), "duplicate") &&
          !factory::values::typed_difference(saved, host.checkpoint()),
          "A repeated craft wire does not mint another metal component.");
    Host restored;
    check(get<bool>(restored.initialize_arrival("bench-site", {"P", "Q"}), "accepted") &&
          get<bool>(restored.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(restored.restore_checkpoint(saved), "accepted") &&
          !factory::values::typed_difference(saved, restored.checkpoint()) &&
          get<A>(restored.projection(), "fabrication_benches").size() == 1,
          "Fresh Host restore retains the placed bench and both actors' exact material ownership.");
    check(get<bool>(restored.publish_actor("P", {V(8.25), V(1.0), V(1.65)}, 1), "accepted"),
          "P establishes a fresh physical observation after the checkpoint restore.");
    const O deploy{{"context", V("bench-site")}, {"client", V("P")},
        {"request", V("redeploy-pod-bench")}, {"action", V("deploy_fabrication_hub")},
        {"entity", V("pod-fabrication-hub")},
        {"center", V(A{V(I{24}), V(I{2}), V(I{8})})}};
    const auto redeployed = restored.command("P", deploy);
    if (!get<bool>(redeployed, "accepted"))
        throw std::runtime_error("Pod workshop redeploy refused: " + get<std::string>(redeployed, "reason"));
    const auto valid_redeploy = restored.validate_checkpoint(restored.checkpoint());
    if (!get<bool>(valid_redeploy, "accepted"))
        throw std::runtime_error("Redeployed workshop checkpoint refused: " +
            get<std::string>(valid_redeploy, "reason"));
    check(get<bool>(redeployed, "accepted") &&
          get<bool>(V(get<O>(restored.projection(), "fabrication_hub")), "installed") &&
          get<I>(V(get<O>(restored.projection(), "fabrication_hub")), "generation") == 1 &&
          get<bool>(valid_redeploy, "accepted"),
          "The same pod workshop redeploys on the half-height foundation after a fresh Host restore.");
}
}  // namespace

int main() {
    try {
        shared_harvest();
        field_wood_uses_physical_actor_and_one_ledger();
        opening_actor_carries_finite_site_across_restore();
        placed_bench_preserves_two_actor_custody();
        std::cout << "harvest_host_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "harvest_host_test: " << error.what() << '\n';
        return 1;
    }
}
