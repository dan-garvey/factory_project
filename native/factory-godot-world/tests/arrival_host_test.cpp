#include "factory/projection_contract.hpp"
#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <iostream>
#include <stdexcept>
#include <string_view>
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
    check(get<bool>(host.initialize_arrival_advanced_fixture("arrival-site", {"P", "Q"}), "accepted"),
          "The new native opening initializes one pod for a shared roster.");
    check(get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()), "accepted"),
          "The normal terrain producer still binds the authored site.");
}

void arrival_projection_contract() {
    for (const bool advanced : {false, true}) {
        Host host;
        const auto initialized = advanced ?
            host.initialize_arrival_advanced_fixture("arrival-contract", {"P", "Q"}) :
            host.initialize_arrival("arrival-contract", {"P", "Q"});
        check(get<bool>(initialized, "accepted") &&
              get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()), "accepted"),
              "The arrival projection contract test starts from a configured native site.");
        check(factory::godot_world::projection_contract::complete(host.projection()),
              "Both supported arrival profiles publish complete nested topology records.");
        const auto complete = std::get<O>(host.projection().storage());
        check(get<bool>(V(get<O>(V(complete), "options")), "arrival"),
              "The native profile identifies an arrival independently of its pod record.");
        const auto options = get<O>(V(complete), "options");
        check(get<bool>(V(options), "copper_material") &&
                  get<bool>(V(options), "manual_sources") &&
                  get<I>(V(get<O>(V(complete), "material_mass")), "accounted_mass") ==
                      get<I>(V(get<O>(V(complete), "material_mass")), "initial_mass") &&
                  get<O>(V(complete), "hand_sources").contains("opening-copper"),
              "The arrival profile identifies its finite hand sources and copper mass ledger.");
        for (const char* name : {"material_mass", "hand_sources"}) {
            auto missing = complete;
            missing.erase(name);
            check(!factory::godot_world::projection_contract::complete(V(missing)),
                  "An arrival cannot omit an enabled native material readout.");
        }
        const auto invalid_mass = [&](const char* field, V bad) {
            auto malformed = complete;
            auto ledger = get<O>(V(malformed), "material_mass");
            ledger.at(field) = std::move(bad);
            malformed.at("material_mass") = V(std::move(ledger));
            return !factory::godot_world::projection_contract::complete(V(malformed));
        };
        const auto invalid_source = [&](const char* field, V bad) {
            auto malformed = complete;
            auto sources = get<O>(V(malformed), "hand_sources");
            auto ore = get<O>(V(sources), "opening-copper");
            ore[field] = std::move(bad);
            sources.at("opening-copper") = V(std::move(ore));
            malformed.at("hand_sources") = V(std::move(sources));
            return !factory::godot_world::projection_contract::complete(V(malformed));
        };
        check(invalid_mass("stock_chunks", V("many")) &&
                  invalid_mass("accounted_mass", V(true)) &&
                  invalid_source("kind", V("mineral")) &&
                  invalid_source("position", V(A{V(0.0), V(0.0)})) &&
                  invalid_source("remaining", V(2.0)) &&
                  invalid_source("contact_bounds", V(A{V(A{V(0.0), V(0.0)}),
                      V(A{V(1.0), V(1.0), V(1.0)})})),
              "Mistyped mass counts, source coordinates and ore contact bounds refuse.");
        Host bounded;
        auto bounded_site = factory::godot_world::tests::flat_site();
        bounded_site.insert_or_assign("obstacles", V(A{V(A{
            V(A{V(-1.4), V(0.0), V(-1.2)}),
            V(A{V(-0.9), V(1.2), V(1.2)})})}));
        bounded_site.emplace("source_obstacle", V(I{0}));
        const auto bounded_init = advanced ?
            bounded.initialize_arrival_advanced_fixture("arrival-bounded", {"P"}) :
            bounded.initialize_arrival("arrival-bounded", {"P"});
        check(get<bool>(bounded_init, "accepted") &&
                  get<bool>(bounded.configure_terrain(bounded_site), "accepted") &&
                  factory::godot_world::projection_contract::complete(bounded.projection()) &&
                  get<A>(get<O>(bounded.projection(), "hand_sources").at("opening-copper"),
                      "contact_bounds").size() == 2,
              "A configured ore contact hull retains its floating world bounds in the complete view.");
        for (const char* name : {"supplied_hardware_boxes", "landing_pod",
                 "fabrication_hub", "fabrication_benches", "crank_items",
                 "placed_components", "slide_phases"}) {
            auto missing = complete;
            missing.erase(name);
            check(!factory::godot_world::projection_contract::complete(V(missing)),
                  "Every arrival worksite readout is required by the native profile fact.");
        }
        const auto malformed_worksite = [&](const char* name, V replacement) {
            auto malformed = complete;
            malformed.at(name) = std::move(replacement);
            return !factory::godot_world::projection_contract::complete(V(malformed));
        };
        check(malformed_worksite("supplied_hardware_boxes", V(O{{"broken", V(O{
                  {"entity", V("box")}, {"generation", V(I{1})},
                  {"center", V(A{V(1.0), V(2.0)})},
                  {"half", V(A{V(1.0), V(1.0), V(1.0)})}})}})) &&
              malformed_worksite("fabrication_hub", V(O{{"id", V("hub")},
                  {"generation", V(I{1})}, {"installed", V(true)},
                  {"holder", V(false)}, {"center", V(A{V(I{0}), V(I{0}), V(I{0})})},
                  {"position", V(A{V(0.0), V(0.0), V(0.0)})}})) &&
              malformed_worksite("fabrication_benches", V(A{V(O{{"id", V("bench")}})})) &&
              malformed_worksite("crank_items", V(O{{"broken", V(O{
                  {"id", V("crank")}, {"generation", V(I{1})},
                  {"holder", V("")}, {"attached_to", V("")},
                  {"port", V(A{V(I{1}), V(I{2})})}, {"face", V(A{})}})}})) &&
              malformed_worksite("placed_components", V(O{{"broken", V(O{
                  {"component", V("wooden_frame")}, {"generation", V(I{1})},
                  {"center", V(A{V(I{0}), V(I{0}), V(I{0})})},
                  {"occupied", V(O{{"center", V(A{V(0.0), V(0.0), V(0.0)})},
                      {"half", V(A{V(1.0), V(1.0)})}})},
                  {"position", V(A{V(0.0), V(0.0), V(0.0)})}})}})) &&
              malformed_worksite("slide_phases", V(O{{"broken", V(O{
                  {"subticks", V(I{0})}, {"remainder", V(I{0})},
                  {"denominator", V("one")}, {"cycle_subticks", V(I{1})}})}})),
              "Physical arrival records reject missing bounds, bad custody and mistyped phases.");
        for (const char* name : {"collector_assemblies", "press_assemblies",
                 "guided_press_assemblies", "sliding_press_assemblies",
                 "broad_press_assemblies", "broad_shear_assemblies"}) {
            auto missing = complete;
            missing.erase(name);
            auto wrong_container = complete;
            wrong_container.at(name) = V(O{});
            auto malformed_entry = complete;
            malformed_entry.at(name) = V(A{V(O{{"status", V("ready")}})});
            check(!factory::godot_world::projection_contract::complete(V(missing)) &&
                  !factory::godot_world::projection_contract::complete(V(wrong_container)) &&
                  !factory::godot_world::projection_contract::complete(V(malformed_entry)),
                  "Every arrival assembly needs its typed array and stable machine coordinates.");
        }
        for (const char* name : {"component_capacity", "workshop_completed_actors",
                 "first_plate_unlock", "component_recipes", "part_recipes",
                 "foundation_recipe"}) {
            auto missing = complete;
            missing.erase(name);
            check(!factory::godot_world::projection_contract::complete(V(missing)),
                  "An arrival cannot omit a native-owned build choice or workshop progress field.");
        }
        const auto malformed_catalog = [&](const char* name, V replacement) {
            auto malformed = complete;
            malformed.at(name) = std::move(replacement);
            return !factory::godot_world::projection_contract::complete(V(malformed));
        };
        check(malformed_catalog("component_capacity", V("unlimited")) &&
              malformed_catalog("workshop_completed_actors", V(A{V(I{1})})) &&
              malformed_catalog("first_plate_unlock", V(I{1})) &&
              malformed_catalog("component_recipes", V(O{{"wooden_frame", V(O{
                  {"timber", V(I{3})}, {"copper", V("zero")}})}})) &&
              malformed_catalog("part_recipes", V(A{V(O{
                  {"kind", V("shaft")}, {"teeth", V(true)},
                  {"half_span", V(I{2})}, {"timber", V(I{1})},
                  {"copper", V(I{0})}})})) &&
              malformed_catalog("foundation_recipe", V(O{
                  {"timber", V(I{2})}, {"copper", V(false)}})),
              "Recipe costs, workshop actor IDs, capacity and unlock flags keep their native types.");
        const auto tick = host.advance_tick_fields();
        const auto refreshed = host.projection();
        check(get<I>(tick, "revision") == get<I>(refreshed, "revision") &&
              factory::godot_world::projection_contract::complete(refreshed),
              "A native arrival tick retains the complete nested topology record shapes.");
        const auto spawn = get<A>(get<O>(refreshed, "actors").at("P"), "position");
        check(get<bool>(host.publish_actor("P", spawn, 1), "accepted") &&
                  factory::godot_world::projection_contract::complete(host.projection()),
              "A ready native actor publishes one clearance for each hand source.");
        const auto ready_view = std::get<O>(host.projection().storage());
        const auto invalid_clearance = [&](const char* mode) {
            auto malformed = ready_view;
            auto actors = get<O>(V(malformed), "actors");
            auto actor = get<O>(actors.at("P"), "harvest_clear");
            if (std::string_view(mode) == "missing") actor.erase("opening-copper");
            if (std::string_view(mode) == "extra") actor.emplace("invented-source", V(true));
            if (std::string_view(mode) == "mistyped") actor.at("opening-copper") = V("clear");
            auto record = std::get<O>(actors.at("P").storage());
            record.at("harvest_clear") = V(std::move(actor));
            actors.at("P") = V(std::move(record));
            malformed.at("actors") = V(std::move(actors));
            return !factory::godot_world::projection_contract::complete(V(malformed));
        };
        check(invalid_clearance("missing") && invalid_clearance("extra") &&
                  invalid_clearance("mistyped"),
              "A ready actor refuses omitted, invented or mistyped source-clearance entries.");
    }
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
    check(get<A>(view, "workshop_completed_actors").empty() &&
          !std::get<O>(view.storage()).contains("freight_beacon"),
          "Fresh arrival has no shipment entity or completed actor goal.");
    const auto trees = get<O>(view, "hand_sources");
    const auto ore = trees.at("opening-copper");
    const auto deposit = get<O>(view, "source_deposit");
    check(get<I>(view, "initial_feed") == 4096 && get<I>(V(deposit), "initial_units") == 4096 &&
          get<I>(V(get<O>(view, "stock")), "source") == 4096 &&
          get<I>(ore, "initial") == 4096 && get<I>(ore, "remaining") == 4096,
          "The ordinary fresh arrival exposes one finite 4096-unit source through every native projection.");
    const auto south = get<A>(trees.at("tree-east-south"), "position");
    const auto north = get<A>(trees.at("tree-east-north"), "position");
    const auto upstream = get<A>(trees.at("tree-east-upstream"), "position");
    check(std::abs(std::get<double>(south[0].storage()) - 6.6) < 1e-8 &&
          std::abs(std::get<double>(south[2].storage()) - 3.3) < 1e-8 &&
          std::abs(std::get<double>(north[0].storage()) - 6.6) < 1e-8 &&
          std::abs(std::get<double>(north[2].storage()) - 11.55) < 1e-8 &&
          std::abs(std::get<double>(upstream[0].storage()) - 6.6) < 1e-8 &&
          std::abs(std::get<double>(upstream[2].storage()) + 1.65) < 1e-8,
          "Finite east timber sites include a separate upstream tree for the constructed plate route.");
    const auto recipes = get<O>(view, "component_recipes");
    check(recipes.size() == 20 && get<I>(view, "component_capacity") == 0 &&
          get<I>(recipes.at("wooden_frame"), "timber") == 3 &&
          get<I>(recipes.at("wooden_frame"), "copper") == 0 &&
          get<I>(recipes.at("wooden_workbench"), "timber") == 4 &&
          get<I>(recipes.at("wooden_workbench"), "copper") == 0 &&
          get<I>(recipes.at("copper_cog"), "timber") == 0 &&
          get<I>(recipes.at("copper_cog"), "copper") == 2 &&
          get<I>(recipes.at("flat_head"), "timber") == 0 &&
          get<I>(recipes.at("flat_head"), "copper") == 1 &&
          get<I>(recipes.at("hand_crank"), "timber") == 2 &&
          get<I>(recipes.at("hand_crank"), "copper") == 0 &&
          get<I>(recipes.at("channel_narrow_x"), "timber") == 2 &&
          get<I>(recipes.at("channel_narrow_z"), "timber") == 2 &&
          get<I>(recipes.at("channel_broad_x"), "timber") == 4 &&
          get<I>(recipes.at("channel_broad_z"), "timber") == 4,
          "The normal consumer receives every native recipe cost and no opening carry bound.");
    check(get<I>(recipes.at("wooden_slide"), "timber") == 3 &&
          get<I>(recipes.at("wooden_slide"), "load_rating") == 8 &&
          get<I>(recipes.at("copper_slide"), "copper") == 4 &&
          get<I>(recipes.at("copper_slide"), "load_rating") == 24,
          "The one-part slide bills contain a matching material input and distinct load ratings.");
    check(get<I>(recipes.at("wooden_shaft"), "load_rating") == 8 &&
          get<I>(recipes.at("wooden_cog"), "load_rating") == 8 &&
          get<I>(recipes.at("copper_shaft"), "load_rating") == 24 &&
          get<I>(recipes.at("copper_cog"), "load_rating") == 24 &&
          !std::get<O>(recipes.at("wooden_frame").storage()).contains("load_rating"),
          "The native recipe projection exposes only the four placed drive ratings.");
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
          std::get<A>(get<O>(restored.projection(), "part_specifications").at("P").storage()).size() == 7,
          "The restored arrival offers finite route recipes but no complete collector or press.");
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
void crafted_cranks_keep_distinct_identities_before_first_plate() {
    Host host;
    check(get<bool>(host.initialize_arrival("crank-item-site", {"P", "Q"}), "accepted") &&
          get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(host.publish_actor("P", {V(5.8), V(1.0), V(3.3)}, 1), "accepted"),
          "A fresh Chapter 1 actor can reach finite timber before the first plate.");
    const auto command = [&](const char* request, const char* action, O extra) {
        O wire{{"context", V("crank-item-site")}, {"client", V("P")},
            {"request", V(request)}, {"action", V(action)}};
        wire.merge(extra);
        return host.command("P", wire);
    };
    check(get<bool>(host.projection(), "first_plate_unlock") &&
          get<A>(host.projection(), "workshop_completed_actors").empty() &&
          get<bool>(command("fast", "set_developer_conveniences", {{"enabled", V(true)}}), "accepted"),
          "Only the test's cutting duration is shortened; the first-plate recipe gate stays closed.");
    for (const char* request : {"wood-1", "wood-2", "wood-3", "wood-4"})
        check(get<bool>(command(request, "harvest_source", {{"target", V("tree-east-south")}}), "accepted"),
              "Four finite timber units move into actor P's native cargo.");
    const auto first = command("crank-1", "field_craft", {{"component", V("hand_crank")}});
    const auto second = command("crank-2", "field_craft", {{"component", V("hand_crank")}});
    check(get<bool>(first, "accepted") && get<bool>(second, "accepted") &&
          get<std::string>(first, "crank_id") != get<std::string>(second, "crank_id") &&
          get<I>(first, "crank_generation") != get<I>(second, "crank_generation"),
          "Two pre-plate timber recipes issue distinct persistent crank item identities.");
    const auto items = get<O>(host.projection(), "crank_items");
    const auto cargo = get<O>(get<O>(host.projection(), "cargo").at("P"), "components");
    check(items.size() == 2 &&
          get<std::string>(items.at(get<std::string>(first, "crank_id")), "holder") == "P" &&
          get<std::string>(items.at(get<std::string>(second, "crank_id")), "holder") == "P" &&
          get<I>(V(cargo), "hand_crank") == 2 &&
          get<I>(get<O>(host.projection(), "cargo").at("P"), "timber") == 0,
          "The two identities agree with one actor's finite carried component count.");
    const auto before_bad_shapes = host.projection();
    const std::array<std::tuple<const char*, const char*, O>, 4> malformed{{
        {"bad-field", "field_craft", {{"component", V(I{1})}}},
        {"bad-floor", "craft_foundation", {{"entity", V(I{1})}}},
        {"bad-component", "craft_component",
            {{"entity", V("pod-fabrication-hub")}, {"component", V("hand_crank")},
             {"free_stock", V(true)}}},
        {"bad-part", "craft_part",
            {{"entity", V("pod-fabrication-hub")}, {"role", V("shaft")},
             {"half_span", V(2.0)}}},
    }};
    for (const auto& [request, action, fields] : malformed) {
        const auto refusal = command(request, action, fields);
        check(!get<bool>(refusal, "accepted") &&
              get<std::string>(refusal, "reason") == "invalid_command",
              "Malformed crafting requests refuse at the production Host boundary.");
    }
    const auto after_bad_shapes = host.projection();
    check(get<I>(before_bad_shapes, "revision") == get<I>(after_bad_shapes, "revision") &&
          !factory::values::typed_difference(
              V(get<O>(before_bad_shapes, "cargo")), V(get<O>(after_bad_shapes, "cargo"))) &&
          !factory::values::typed_difference(
              V(get<O>(before_bad_shapes, "part_kits")), V(get<O>(after_bad_shapes, "part_kits"))) &&
          !factory::values::typed_difference(
              V(get<O>(before_bad_shapes, "crank_items")), V(get<O>(after_bad_shapes, "crank_items"))),
          "Malformed crafting requests leave native revision, stock, kits and crank identities unchanged.");
    const auto duplicate = command("crank-2", "field_craft", {{"component", V("hand_crank")}});
    check(get<bool>(duplicate, "duplicate") && get<O>(host.projection(), "crank_items").size() == 2,
          "Retransmitting a craft command cannot mint a third crank item.");
    const auto saved = host.checkpoint();
    check(get<bool>(host.validate_checkpoint(saved), "accepted"),
          "The finite pair validates through native checkpoint history.");
    Host restored;
    check(get<bool>(restored.initialize_arrival("crank-item-site", {"P", "Q"}), "accepted") &&
          get<bool>(restored.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(restored.restore_checkpoint(saved), "accepted") &&
          !factory::values::typed_difference(saved, restored.checkpoint()),
          "A new Host restores both exact pre-plate crank identities and their paid timber.");
    const auto resumed = [&](const char* request, const char* action, O extra) {
        O wire{{"context", V("crank-item-site")}, {"client", V("P")},
            {"request", V(request)}, {"action", V(action)}};
        wire.merge(extra);
        return restored.command("P", wire);
    };
    check(get<bool>(restored.publish_actor("P", {V(5.8), V(1.0), V(3.3)}, 2), "accepted"),
          "A restored actor publishes a fresh observation before further cutting.");
    for (const char* request : {"wood-5", "wood-6", "wood-7"})
        check(get<bool>(resumed(request, "harvest_source", {{"target", V("tree-east-south")}}),
            "accepted"), "The remaining finite timber pays for a separate slide body.");
    check(get<bool>(resumed("slide-craft", "field_craft",
              {{"component", V("wooden_slide")}}), "accepted") &&
          get<bool>(restored.publish_actor("P", {V(4.2), V(1.0), V(3.3)}, 3), "accepted"),
          "The actor carries a separate slide body to a reachable rotary port.");
    const auto slide = resumed("slide-place", "place_component",
        {{"component", V("wooden_slide")},
         {"center", V(A{V(I{12}), V(I{0}), V(I{8})})}});
    check(get<bool>(slide, "accepted"), "The slide body spends its own crafted item.");
    const auto slide_id = get<std::string>(slide, "entity");
    const auto first_id = get<std::string>(first, "crank_id");
    const auto second_id = get<std::string>(second, "crank_id");
    const O attach{{"entity", V(slide_id)}, {"crank", V(first_id)},
        {"port", V(A{V(I{13}), V(I{0}), V(I{8})})}};
    const auto fitted = resumed("attach-first", "attach_hand_crank", attach);
    check(get<bool>(fitted, "accepted") && get<std::string>(fitted, "entity") == first_id &&
          get<I>(get<O>(restored.projection(), "placed_components").at(slide_id),
              "crank_axis") == 0 &&
          get<std::string>(get<O>(restored.projection(), "crank_items").at(first_id),
              "attached_to") == slide_id &&
          !factory::values::typed_difference(
              V(get<A>(get<O>(restored.projection(), "crank_items").at(first_id), "face")),
              V(A{V(I{1}), V(I{0}), V(I{0})})) &&
          get<I>(V(get<O>(get<O>(restored.projection(), "cargo").at("P"),
              "components")), "hand_crank") == 1,
          "The first crafted crank attaches at the real port while the second stays carried.");
    check(get<bool>(resumed("attach-first", "attach_hand_crank", attach), "duplicate") &&
          !get<bool>(resumed("attach-second", "attach_hand_crank",
              {{"entity", V(slide_id)}, {"crank", V(second_id)},
               {"port", V(A{V(I{13}), V(I{0}), V(I{8})})}}), "accepted") &&
          !get<bool>(resumed("reclaim-with-crank", "reclaim_component",
              {{"entity", V(slide_id)}}), "accepted"),
          "A retry cannot mint a crank, and one occupied port blocks another crank and slide reclaim.");
    const auto before_bad_crank_commands = restored.projection();
    for (const auto& refused : {
             resumed("bad-attach", "attach_hand_crank",
                 {{"entity", V(slide_id)}, {"crank", V(first_id)},
                  {"port", V(A{V(I{13}), V(I{0}), V(I{8})})}, {"face", V(true)}}),
             resumed("bad-detach", "detach_hand_crank",
                 {{"entity", V(first_id)}, {"unexpected", V(I{1})}}),
             resumed("bad-operate", "operate_hand_crank", {{"entity", V(I{7})}}),
             resumed("bad-turn", "turn_hand_crank", {{"entity", V(slide_id)},
                 {"unexpected", V(I{1})}}),
             resumed("bad-slide-turn", "turn_slide_crank",
                 {{"entity", V(slide_id)}, {"port", V("not a port")}})})
        check(!get<bool>(refused, "accepted") &&
              get<std::string>(refused, "reason") == "invalid_command",
              "Malformed crank fields refuse through the production Host command path.");
    const auto after_bad_crank_commands = restored.projection();
    check(get<I>(before_bad_crank_commands, "revision") ==
              get<I>(after_bad_crank_commands, "revision") &&
          !factory::values::typed_difference(
              V(get<O>(before_bad_crank_commands, "crank_items")),
              V(get<O>(after_bad_crank_commands, "crank_items"))) &&
          !factory::values::typed_difference(
              V(get<O>(before_bad_crank_commands, "slide_phases")),
              V(get<O>(after_bad_crank_commands, "slide_phases"))),
          "Malformed crank requests leave the native revision, item custody and slide phase unchanged.");
    const auto turn = resumed("turn-fitted", "turn_slide_crank",
        {{"entity", V(slide_id)},
         {"port", V(A{V(I{13}), V(I{0}), V(I{8})})}});
    check(get<bool>(turn, "accepted") &&
          get<I>(get<O>(restored.projection(), "slide_phases").at(slide_id), "subticks") > 0,
          "Turning the fitted crank advances the actual slide phase.");
    const auto before_pulse = get<I>(get<O>(restored.projection(), "slide_phases")
        .at(slide_id), "subticks");
    const auto pulse = resumed("pulse-fitted", "operate_hand_crank",
        {{"entity", V(first_id)}});
    const auto after_pulse = get<I>(get<O>(restored.projection(), "slide_phases")
        .at(slide_id), "subticks");
    check(get<bool>(pulse, "accepted") && after_pulse != before_pulse &&
          get<bool>(resumed("pulse-fitted", "operate_hand_crank",
              {{"entity", V(first_id)}}), "duplicate") &&
          get<I>(get<O>(restored.projection(), "slide_phases")
              .at(slide_id), "subticks") == after_pulse,
          "One fitted-crank request consumes one native source pulse, while an exact retry cannot turn again.");
    const auto fitted_checkpoint = restored.checkpoint();
    const auto fitted_validation = restored.validate_checkpoint(fitted_checkpoint);
    check(get<bool>(fitted_validation, "accepted"),
          "Checkpoint validation preserves both paid crank identities and attached port custody.");
    Host fitted_reopened;
    check(get<bool>(fitted_reopened.initialize_arrival("crank-item-site", {"P", "Q"}), "accepted") &&
          get<bool>(fitted_reopened.configure_terrain(
              factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(fitted_reopened.restore_checkpoint(fitted_checkpoint), "accepted") &&
          !factory::values::typed_difference(
              V(get<A>(get<O>(fitted_reopened.projection(), "crank_items").at(first_id), "face")),
              V(A{V(I{1}), V(I{0}), V(I{0})})),
          "A fresh Host reopens the exact fitted crank face and finite identity.");
    const auto removed = resumed("detach-first", "detach_hand_crank", {{"entity", V(first_id)}});
    check(get<bool>(removed, "accepted") &&
          get<std::string>(get<O>(restored.projection(), "crank_items").at(first_id),
              "holder") == "P" &&
          get<I>(V(get<O>(get<O>(restored.projection(), "cargo").at("P"),
              "components")), "hand_crank") == 2 &&
          !get<bool>(resumed("turn-after-detach", "turn_slide_crank",
              {{"entity", V(slide_id)},
               {"port", V(A{V(I{13}), V(I{0}), V(I{8})})}}), "accepted"),
          "Detaching returns the same crank identity and removes its manual drive.");
    const auto wrong_west_face = resumed("attach-west-wrong-face", "attach_hand_crank",
        {{"entity", V(slide_id)}, {"crank", V(second_id)},
         {"port", V(A{V(I{11}), V(I{0}), V(I{8})})},
         {"face", V(A{V(I{1}), V(I{0}), V(I{0})})}});
    check(!get<bool>(wrong_west_face, "accepted") &&
          get<std::string>(wrong_west_face, "reason") == "invalid_crank_face",
          "A west slide port cannot be fitted with the east-facing handle.");
    const auto west = resumed("attach-second-west", "attach_hand_crank",
        {{"entity", V(slide_id)}, {"crank", V(second_id)},
         {"port", V(A{V(I{11}), V(I{0}), V(I{8})})}});
    if (!get<bool>(west, "accepted"))
        throw std::runtime_error("West crank attachment refused: " +
            get<std::string>(west, "reason"));
    check(!factory::values::typed_difference(
              V(get<A>(get<O>(restored.projection(), "crank_items").at(second_id), "face")),
              V(A{V(I{-1}), V(I{0}), V(I{0})})),
          "The mirrored fitted slide reports its negative X face to the ordinary view.");
    const auto west_turn = resumed("turn-west", "turn_slide_crank",
        {{"entity", V(slide_id)},
         {"port", V(A{V(I{11}), V(I{0}), V(I{8})})}});
    if (!get<bool>(west_turn, "accepted"))
        throw std::runtime_error("West crank turn refused: " +
            get<std::string>(west_turn, "reason"));
    check(get<bool>(west, "accepted") &&
          get<bool>(west_turn, "accepted") &&
          get<I>(get<O>(restored.projection(), "slide_phases").at(slide_id), "subticks") == before_pulse,
          "Moving the crank to the opposite shaft end reverses the native slide rotation.");
    check(get<bool>(restored.publish_actor("Q", {V(4.8), V(1.0), V(3.3)}, 1), "accepted"),
          "A second authenticated worker can approach the shared fitted crank.");
    const auto q_command = [&](const char* request, const char* action, O extra) {
        O wire{{"context", V("crank-item-site")}, {"client", V("Q")},
            {"request", V(request)}, {"action", V(action)}};
        wire.merge(extra);
        return restored.command("Q", wire);
    };
    check(!get<bool>(q_command("q-steal-held", "attach_hand_crank",
              {{"entity", V(slide_id)}, {"crank", V(first_id)},
               {"port", V(A{V(I{13}), V(I{0}), V(I{8})})}}), "accepted") &&
          get<bool>(q_command("q-turn-attached", "turn_slide_crank",
              {{"entity", V(slide_id)},
               {"port", V(A{V(I{11}), V(I{0}), V(I{8})})}}), "accepted") &&
          get<bool>(q_command("q-detach", "detach_hand_crank",
              {{"entity", V(second_id)}}), "accepted") &&
          get<std::string>(get<O>(restored.projection(), "crank_items").at(second_id),
              "holder") == "Q" &&
          get<std::string>(get<O>(restored.projection(), "crank_items").at(first_id),
              "holder") == "P",
          "Another worker can turn and remove a shared fitted crank, but cannot place P's carried item.");
}
void fabricated_transmission_stock_is_finite() {
    Host host;
    initialized(host);
    const auto recipes = get<A>(host.projection(), "part_recipes");
    check(recipes.size() == 7 && std::any_of(recipes.begin(), recipes.end(), [](const V& entry) {
              const auto* recipe = std::get_if<O>(&entry.storage());
              return recipe && get<std::string>(V(*recipe), "kind") == "vertical_gearbox" &&
                  get<I>(V(*recipe), "timber") == 1 && get<I>(V(*recipe), "copper") == 1;
          }) && std::any_of(recipes.begin(), recipes.end(), [](const V& entry) {
              const auto* recipe = std::get_if<O>(&entry.storage());
              return recipe && get<std::string>(V(*recipe), "kind") == "gearbox" &&
                  get<I>(V(*recipe), "timber") == 1 && get<I>(V(*recipe), "copper") == 1;
          }), "Arrival offers finite horizontal and vertical relays without gifting their kits.");
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
    check(get<bool>(host.publish_actor("P", {V(5.8), V(1.0), V(3.3)}, 2), "accepted"),
          "The physical actor reaches the first finite tree.");
    for (int index = 0; index < 8; ++index) {
        const O cut{{"context", V("arrival-site")}, {"client", V("P")},
            {"request", V("timber-" + std::to_string(index))}, {"action", V("harvest_source")},
            {"target", V("tree-east-south")}};
        check(get<bool>(factory::godot_world::tests::complete_manual_cut(host, "P", cut), "accepted"),
              "Each route timber input comes from the finite visible tree.");
    }
    check(get<bool>(host.publish_actor("P", {V(-0.5), V(1.0), V(0.0)}, 3), "accepted"),
          "The actor reaches the finite copper outcrop.");
    for (int index = 0; index < 2; ++index) {
        const O cut{{"context", V("arrival-site")}, {"client", V("P")},
            {"request", V("ore-" + std::to_string(index))}, {"action", V("harvest_source")},
            {"target", V("opening-copper")}};
        check(get<bool>(factory::godot_world::tests::complete_manual_cut(host, "P", cut), "accepted"),
              "Each route clasp input comes from the finite native deposit.");
    }
    check(get<bool>(host.publish_actor("P", {V(3.3), V(1.0), V(4.8)}, 4), "accepted"),
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
void arrival_cog_sizes_use_real_cargo_and_restore() {
    Host host;
    initialized(host);
    const auto recipes = get<A>(host.projection(), "part_recipes");
    for (const auto& [teeth, timber] : {std::pair{I{2}, I{1}}, std::pair{I{4}, I{2}}}) {
        check(std::any_of(recipes.begin(), recipes.end(), [&](const V& entry) {
                  return get<std::string>(entry, "kind") == "gear" &&
                      get<I>(entry, "teeth") == teeth && get<I>(entry, "timber") == timber &&
                      get<I>(entry, "copper") == 1;
              }), "The normal arrival projects both separately priced cogwheel recipes.");
    }
    const auto craft = [](const std::string& request, I teeth) {
        return O{{"context", V("arrival-site")}, {"client", V("P")},
            {"request", V(request)}, {"action", V("craft_part")},
            {"entity", V("pod-fabrication-hub")}, {"role", V("gear")},
            {"teeth", V(teeth)}, {"half_span", V(I{0})}};
    };
    check(get<bool>(host.publish_actor("P", {V(3.3), V(1.0), V(4.8)}, 1), "accepted"),
          "The actor reaches the ordinary pod workshop.");
    auto missing_size = craft("missing-cog-size", 2);
    missing_size.erase("teeth");
    check(get<std::string>(host.command("P", missing_size), "reason") == "invalid_command" &&
          get<std::string>(host.command("P", craft("empty-cog", 2)), "reason") == "unavailable_input",
          "The Host rejects an ambiguous gear request and an unpaid sized recipe.");
    check(get<bool>(host.publish_actor("P", {V(5.8), V(1.0), V(3.3)}, 2), "accepted"),
          "The actor reaches the finite tree for cogwheel timber.");
    for (int index = 0; index < 3; ++index) {
        const O cut{{"context", V("arrival-site")}, {"client", V("P")},
            {"request", V("cog-timber-" + std::to_string(index))},
            {"action", V("harvest_source")}, {"target", V("tree-east-south")}};
        check(get<bool>(factory::godot_world::tests::complete_manual_cut(host, "P", cut), "accepted"),
              "A visible finite tree supplies each required timber input.");
    }
    check(get<bool>(host.publish_actor("P", {V(-0.5), V(1.0), V(0.0)}, 3), "accepted"),
          "The actor reaches the finite copper outcrop for both gear sizes.");
    for (int index = 0; index < 2; ++index) {
        const O cut{{"context", V("arrival-site")}, {"client", V("P")},
            {"request", V("cog-copper-" + std::to_string(index))},
            {"action", V("harvest_source")}, {"target", V("opening-copper")}};
        check(get<bool>(factory::godot_world::tests::complete_manual_cut(host, "P", cut), "accepted"),
              "The native outcrop supplies one copper input for each gear.");
    }
    check(get<bool>(host.publish_actor("P", {V(3.3), V(1.0), V(4.8)}, 4), "accepted"),
          "The actor returns to the workshop with finite gathered cargo.");
    for (I teeth : {I{2}, I{4}})
        check(get<bool>(host.command("P", craft("make-cog-" + std::to_string(teeth), teeth)), "accepted"),
              "The Host passes a selected size into the one native fabrication ledger.");
    const auto view = host.projection();
    const auto specifications = std::get<A>(get<O>(view, "part_specifications").at("P").storage());
    for (I teeth : {I{2}, I{4}})
        check(std::any_of(specifications.begin(), specifications.end(), [&](const V& entry) {
                  return get<std::string>(entry, "kind") == "gear" &&
                      get<I>(entry, "teeth") == teeth && get<I>(entry, "count") == 1;
              }), "The inventory projection carries an independent count for each crafted size.");
    const auto cargo = get<O>(view, "cargo").at("P");
    check(get<I>(cargo, "timber") == 0 && get<I>(cargo, "raw") == 0,
          "The two real recipes consume exactly three timber and two copper inputs.");
    const auto saved = host.checkpoint();
    check(get<bool>(host.validate_checkpoint(saved), "accepted"),
          "The native checkpoint validates the sized receipts and exact cargo bill.");
    Host reopened;
    initialized(reopened);
    check(get<bool>(reopened.restore_checkpoint(saved), "accepted") &&
          !factory::values::typed_difference(saved, reopened.checkpoint()),
          "A fresh Host restores both distinct cogwheel counts without creating stock.");
}
void crafted_foundation_extends_exhausted_kit() {
    Host host;
    initialized(host);
    const auto recipe = get<O>(host.projection(), "foundation_recipe");
    check(get<I>(V(recipe), "timber") == factory::world::foundation_timber_cost &&
          get<I>(V(recipe), "copper") == 0,
          "The ordinary projection exposes the finite floor recipe cost.");
    const O craft{{"context", V("arrival-site")}, {"client", V("P")},
        {"request", V("make-floor")}, {"action", V("craft_foundation")},
        {"entity", V("pod-fabrication-hub")}};
    check(get<bool>(host.publish_actor("P", {V(3.3), V(1.0), V(4.8)}, 1), "accepted"),
          "The actor can reach the real workshop with an empty pack.");
    auto empty_request = craft;
    empty_request.at("request") = V("empty-floor");
    const auto empty = host.command("P", empty_request);
    check(!get<bool>(empty, "accepted") && get<std::string>(empty, "reason") == "unavailable_input" &&
          get<I>(get<O>(host.projection(), "part_kits").at("P"), "foundation") == 15,
          "The floor recipe refuses missing timber without changing the supplied kit.");
    check(get<bool>(host.publish_actor("P", {V(5.8), V(1.0), V(3.3)}, 2), "accepted"),
          "The actor reaches a declared finite tree.");
    for (int index = 0; index < 2; ++index) {
        const O cut{{"context", V("arrival-site")}, {"client", V("P")},
            {"request", V("floor-wood-" + std::to_string(index))},
            {"action", V("harvest_source")}, {"target", V("tree-east-south")}};
        check(get<bool>(factory::godot_world::tests::complete_manual_cut(host, "P", cut), "accepted"),
              "Foundation inputs are harvested from the finite local tree.");
    }
    check(get<bool>(host.publish_actor("P", {V(3.3), V(1.0), V(4.8)}, 3), "accepted"),
          "The actor returns to the pod workshop.");
    check(get<bool>(host.command("P", craft), "accepted") &&
          get<I>(get<O>(host.projection(), "part_kits").at("P"), "foundation") == 16 &&
          get<I>(get<O>(host.projection(), "cargo").at("P"), "timber") == 0,
          "The bench exchanges exactly two carried timber for one foundation kit.");
    check(get<bool>(host.command("P", craft), "duplicate") &&
          get<I>(get<O>(host.projection(), "part_kits").at("P"), "foundation") == 16,
          "Repeating the crafting receipt cannot duplicate a foundation.");
    const O area{{"context", V("arrival-site")}, {"client", V("P")},
        {"request", V("spend-floor-kit")}, {"action", V("place_foundations")},
        {"cell", V(A{V(I{10}), V(I{10})})},
        {"end_cell", V(A{V(I{13}), V(I{13})})}, {"level", V(I{0})}};
    const auto placed = host.command("P", area);
    check(get<bool>(placed, "accepted") &&
          get<I>(get<O>(host.projection(), "part_kits").at("P"), "foundation") == 0,
          "An aligned four by four expansion exhausts every original and crafted floor part.");
    check(get<bool>(host.publish_actor("P", {V(5.8), V(1.0), V(3.3)}, 4), "accepted"),
          "The actor returns to the same finite tree after exhausting the kit.");
    for (int index = 2; index < 4; ++index) {
        const O cut{{"context", V("arrival-site")}, {"client", V("P")},
            {"request", V("floor-wood-" + std::to_string(index))},
            {"action", V("harvest_source")}, {"target", V("tree-east-south")}};
        check(get<bool>(factory::godot_world::tests::complete_manual_cut(host, "P", cut), "accepted"),
              "More floor inputs come from the declared remaining tree stock.");
    }
    check(get<bool>(host.publish_actor("P", {V(3.3), V(1.0), V(4.8)}, 5), "accepted"),
          "The actor can use the same workshop after the starter kit is empty.");
    auto later_craft = craft;
    later_craft.at("request") = V("make-floor-after-exhaustion");
    check(get<bool>(host.command("P", later_craft), "accepted") &&
          get<I>(get<O>(host.projection(), "part_kits").at("P"), "foundation") == 1,
          "An exhausted kit can gain exactly one locally crafted part.");
    const O extra{{"context", V("arrival-site")}, {"client", V("P")},
        {"request", V("extra-floor")}, {"action", V("place_foundation")},
        {"cell", V(A{V(I{3}), V(I{4})})}, {"level", V(I{0})}};
    const auto built = host.command("P", extra);
    check(get<bool>(built, "accepted") &&
          get<I>(get<O>(host.projection(), "part_kits").at("P"), "foundation") == 0,
          "The extra floor joins the common grid after starter stock is exhausted.");
    const O reclaim{{"context", V("arrival-site")}, {"client", V("P")},
        {"request", V("reclaim-extra-floor")}, {"action", V("remove")},
        {"entity", V(get<std::string>(built, "entity"))}};
    check(get<bool>(host.command("P", reclaim), "accepted") &&
          get<I>(get<O>(host.projection(), "part_kits").at("P"), "foundation") == 1,
          "Reclaim returns the same crafted foundation to the actor's finite kit.");
    const auto saved = host.checkpoint();
    check(get<bool>(host.validate_checkpoint(saved), "accepted"),
          "The crafted, placed and reclaimed floor has valid native history.");
    Host restored;
    initialized(restored);
    check(get<bool>(restored.restore_checkpoint(saved), "accepted") &&
          !factory::values::typed_difference(saved, restored.checkpoint()),
          "A fresh Host restores the expanded floors and reclaimed part without minting stock.");
}
}  // namespace

int main() {
    try {
        arrival_projection_contract();
        arrival_projection_and_restore();
        historical_initializer_keeps_its_fixture_kit();
        crafted_cranks_keep_distinct_identities_before_first_plate();
        fabricated_transmission_stock_is_finite();
        arrival_cog_sizes_use_real_cargo_and_restore();
        crafted_foundation_extends_exhausted_kit();
        std::cout << "arrival_host_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "arrival_host_test: " << error.what() << '\n';
        return 1;
    }
}
