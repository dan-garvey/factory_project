#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <algorithm>
#include <cmath>
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

O cut(const char* client, const char* request, const char* target) {
    return {{"context", V("harvest-site")}, {"client", V(client)}, {"request", V(request)},
        {"action", V("harvest_source")}, {"target", V(target)}};
}

O conveniences(const char* client, const char* request, bool enabled) {
    return {{"context", V("fast-site")}, {"client", V(client)}, {"request", V(request)},
        {"action", V("set_developer_conveniences")}, {"enabled", V(enabled)}};
}

O fast_site_cut(const char* client, const char* request, const char* target) {
    return {{"context", V("fast-site")}, {"client", V(client)}, {"request", V(request)},
        {"action", V("harvest_source")}, {"target", V(target)}};
}

void one_piece_slide_custody() {
    Host host;
    check(get<bool>(host.initialize_arrival_advanced_fixture("slide-body-site", {"P"}), "accepted") &&
          get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(host.publish_actor("P", {V(5.8), V(1.0), V(3.3)}, 1), "accepted"),
          "One real arrival actor can reach a finite tree for a slide body.");
    const auto command = [&](const char* request, const char* action, O extra) {
        O wire{{"context", V("slide-body-site")}, {"client", V("P")},
            {"request", V(request)}, {"action", V(action)}};
        wire.merge(extra);
        return host.command("P", wire);
    };
    check(get<bool>(command("fast", "set_developer_conveniences", {{"enabled", V(true)}}), "accepted"),
          "Native test mode shortens only the fixture's three real manual cuts.");
    for (const char* request : {"tree-1", "tree-2", "tree-3"})
        check(get<bool>(command(request, "harvest_source", {{"target", V("tree-east-south")}}), "accepted"),
              "Three finite timber units move into the actor's native cargo.");
    const auto shaped = command("shape-slide", "field_craft", {{"component", V("wooden_slide")}});
    check(get<bool>(shaped, "accepted") &&
          get<I>(get<O>(host.projection(), "cargo").at("P"), "timber") == 0 &&
          get<I>(V(get<O>(get<O>(host.projection(), "cargo").at("P"), "components")), "wooden_slide") == 1,
          "The slide and its integral shaft are one finite crafted cargo item.");
    const O place{{"component", V("wooden_slide")},
        {"center", V(A{V(I{12}), V(I{0}), V(I{8})})}};
    const auto installed = command("place-slide", "place_component", place);
    check(get<bool>(installed, "accepted") &&
          get<O>(host.projection(), "placed_components").contains(get<std::string>(installed, "entity")) &&
          get<O>(get<O>(host.projection(), "cargo").at("P"), "components").empty(),
          "The Host places the owned slide once inside its fixed native volume.");
    const auto slide_id = get<std::string>(installed, "entity");
    const auto placed = get<O>(host.projection(), "placed_components").at(slide_id);
    const auto occupied = get<O>(placed, "occupied");
    const auto half = get<A>(V(occupied), "half");
    const auto input_ports = get<A>(V(placed), "input_ports");
    check(get<std::string>(placed, "component") == "wooden_slide" &&
          input_ports.size() == 2 &&
          !factory::values::typed_difference(input_ports.front(),
              V(A{V(I{11}), V(I{0}), V(I{8})})) &&
          !factory::values::typed_difference(input_ports.back(),
              V(A{V(I{13}), V(I{0}), V(I{8})})) &&
          std::abs(std::get<double>(half[0].storage()) - 0.21) < 1e-8 &&
          std::abs(std::get<double>(half[1].storage()) - 0.4125) < 1e-8 &&
          get<std::string>(V(get<O>(host.projection(), "motion").at(slide_id)), "state") == "unpowered",
          "The placed slide publishes one fixed collision volume and its actual idle drive state.");
    const auto initial_phase = get<O>(host.projection(), "slide_phases").at(slide_id);
    check(get<I>(initial_phase, "subticks") == 0 &&
          get<I>(initial_phase, "remainder") == 0 &&
          get<I>(initial_phase, "denominator") == 1 &&
          get<I>(initial_phase, "cycle_subticks") == factory::world::slide_cycle_subticks,
          "The new slide projects an exact zero carriage phase from native state.");
    for (int tick = 0; tick < 3; ++tick) {
        const auto advanced = host.advance();
        check(get<O>(advanced, "slide_phases").contains(slide_id),
              "The authority tick retains the placed slide projection.");
    }
    check(!factory::values::typed_difference(get<O>(host.projection(), "slide_phases").at(slide_id),
              initial_phase),
          "An unloaded slide without input power holds its carriage phase over authority ticks.");
    const auto thin_tick = host.advance_tick_fields();
    const auto& thin_fields = std::get<O>(thin_tick.storage());
    check(thin_fields.contains("slide_phases") &&
          !factory::values::typed_difference(
              std::get<O>(thin_fields.at("slide_phases").storage()).at(slide_id),
              initial_phase),
          "The tick-delta API carries the slide phase used by the ordinary scene presenter.");
    const auto saved = host.checkpoint();
    check(get<bool>(host.validate_checkpoint(saved), "accepted") &&
          get<bool>(command("place-slide", "place_component", place), "duplicate"),
          "The placed slide validates and a retried request cannot spend it again.");
    auto forged = std::get<O>(saved.storage());
    auto native = std::get<O>(forged.at("world").storage());
    auto state = std::get<O>(native.at("state").storage());
    auto phases = std::get<O>(state.at("slide_phases").storage());
    auto phase = std::get<O>(phases.at(slide_id).storage());
    phase.at("subticks") = V(I{1});
    phases.at(slide_id) = V(std::move(phase));
    state.at("slide_phases") = V(std::move(phases));
    native.at("state") = V(std::move(state));
    forged.at("world") = V(std::move(native));
    check(!get<bool>(host.validate_checkpoint(V(std::move(forged))), "accepted"),
          "History validation rejects invented carriage motion on an unpowered slide.");
    Host restored;
    check(get<bool>(restored.initialize_arrival_advanced_fixture("slide-body-site", {"P"}), "accepted") &&
          get<bool>(restored.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(restored.restore_checkpoint(saved), "accepted") &&
          !factory::values::typed_difference(saved, restored.checkpoint()),
          "The exact single-piece slide survives a fresh Host rejoin.");
    const auto resumed = [&](const char* request, const char* action, O extra) {
        O wire{{"context", V("slide-body-site")}, {"client", V("P")},
            {"request", V(request)}, {"action", V(action)}};
        wire.merge(extra);
        return restored.command("P", wire);
    };
    const O turn{{"entity", V(slide_id)},
        {"port", V(A{V(I{13}), V(I{0}), V(I{8})})}};
    check(!get<bool>(resumed("no-crank", "turn_slide_crank", turn), "accepted"),
          "A worker without the issued crank cannot turn the slide's integral input.");
    check(get<bool>(restored.publish_actor("P", {V(1.65), V(1.0), V(5.8)}, 2), "accepted") &&
          get<bool>(resumed("take-crank", "take_hand_crank",
              {{"entity", V("pod-hand-crank")}}), "accepted") &&
          get<bool>(restored.publish_actor("P", {V(4.2), V(1.0), V(3.3)}, 3), "accepted"),
          "The same actor takes the finite issued crank and approaches the placed input port.");
    check(!get<bool>(resumed("wrong-port", "turn_slide_crank",
              {{"entity", V(slide_id)},
               {"port", V(A{V(I{12}), V(I{1}), V(I{8})})}}), "accepted"),
          "The slide's top face is not a rotary input.");
    const auto turned = resumed("turn-slide", "turn_slide_crank", turn);
    if (!get<bool>(turned, "accepted"))
        throw std::runtime_error("Manual slide turn refused: " + get<std::string>(turned, "reason"));
    check(get<I>(get<O>(restored.projection(), "slide_phases").at(slide_id), "subticks") ==
              factory::materials::work_subticks_per_tick &&
          get<O>(restored.projection(), "placed_components").contains(slide_id),
          "One accepted crank turn advances the same placed slide's native phase by one shaft revolution.");
    const auto turned_saved = restored.checkpoint();
    Host turned_restored;
    check(get<bool>(turned_restored.initialize_arrival_advanced_fixture("slide-body-site", {"P"}), "accepted") &&
          get<bool>(turned_restored.configure_terrain(factory::godot_world::tests::flat_site()), "accepted"),
          "A fresh Host can reconstruct the same arrival site before manual-turn restore.");
    const auto turn_restore = turned_restored.restore_checkpoint(turned_saved);
    if (!get<bool>(turn_restore, "accepted"))
        throw std::runtime_error("Manual slide checkpoint refused: " +
            get<std::string>(turn_restore, "reason"));
    check(get<bool>(turn_restore, "accepted") &&
          !factory::values::typed_difference(turned_saved, turned_restored.checkpoint()),
          "Checkpoint replay verifies the actor-held crank and exact slide phase after a manual input.");
    auto forged_turn = std::get<O>(turned_saved.storage());
    auto forged_world = get<O>(V(forged_turn), "world");
    auto forged_history = get<O>(V(forged_world), "history");
    auto forged_records = get<A>(V(forged_history), "records");
    auto forged_record = std::get<O>(forged_records.back().storage());
    auto forged_result = get<O>(V(forged_record), "result");
    auto forged_phase = get<O>(V(forged_result), "slide_phase");
    forged_phase.at("subticks") = V(I{0});
    forged_result.at("slide_phase") = V(std::move(forged_phase));
    forged_record.at("result") = V(std::move(forged_result));
    forged_records.back() = V(std::move(forged_record));
    forged_history.at("records") = V(std::move(forged_records));
    forged_world.at("history") = V(std::move(forged_history));
    forged_turn.at("world") = V(std::move(forged_world));
    check(!get<bool>(turned_restored.validate_checkpoint(V(std::move(forged_turn))), "accepted") &&
          !factory::values::typed_difference(turned_saved, turned_restored.checkpoint()),
          "A forged successful turn cannot invent a different carriage phase on restore.");
}

void flat_head_host_custody() {
    Host host;
    check(get<bool>(host.initialize_arrival("flat-head-site", {"P", "Q"}), "accepted") &&
          get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(host.publish_actor("P", {V(-1.2375), V(1.0), V(0.0)}, 1), "accepted"),
          "The physical actor begins beside a finite copper deposit.");
    const auto command = [&](const char* request, const char* action, O extra) {
        O wire{{"context", V("flat-head-site")}, {"client", V("P")},
            {"request", V(request)}, {"action", V(action)}};
        wire.merge(extra);
        return host.command("P", wire);
    };
    check(get<bool>(command("fast", "set_developer_conveniences", {{"enabled", V(true)}}), "accepted") &&
          get<bool>(command("cut", "harvest_source", {{"target", V("opening-copper")}}), "accepted") &&
          get<I>(get<O>(host.projection(), "cargo").at("P"), "raw") == 1,
          "One real copper source unit enters native custody before fabrication.");
    check(get<bool>(host.publish_actor("P", {V(3.3), V(1.0), V(4.8)}, 2), "accepted"),
          "The actor approaches the pod bench before shaping the copper head.");
    const auto shaped = command("craft", "craft_component",
        {{"entity", V("pod-fabrication-hub")}, {"component", V("flat_head")}});
    if (!get<bool>(shaped, "accepted"))
        throw std::runtime_error("Flat head craft refused: " + get<std::string>(shaped, "reason"));
    check(get<bool>(shaped, "accepted") &&
          get<I>(get<O>(host.projection(), "cargo").at("P"), "raw") == 0 &&
          get<I>(V(get<O>(get<O>(host.projection(), "cargo").at("P"), "components")),
              "flat_head") == 1,
          "The separate flat head spends exactly one finite copper unit at the pod bench.");
    check(get<bool>(host.publish_actor("P", {V(4.2), V(1.0), V(3.3)}, 3), "accepted"),
          "The actor walks into physical reach of a clear build site.");
    const auto installed = command("place", "place_component",
        {{"component", V("flat_head")}, {"center", V(A{V(I{12}), V(I{1}), V(I{8})})}});
    check(get<bool>(installed, "accepted"),
          "The flat head can be placed at work height without a named press assembly.");
    const auto id = get<std::string>(installed, "entity");
    const auto placed = get<O>(host.projection(), "placed_components").at(id);
    const auto occupied = get<O>(placed, "occupied");
    const auto center = get<A>(V(occupied), "center");
    const auto half = get<A>(V(occupied), "half");
    const auto low = std::get<double>(center[1].storage()) - std::get<double>(half[1].storage());
    const auto high = std::get<double>(center[1].storage()) + std::get<double>(half[1].storage());
    check(get<std::string>(placed, "component") == "flat_head" &&
          std::abs(low - 0.928125) < 1e-8 && std::abs(high - 1.44375) < 1e-8 &&
          std::abs(std::get<double>(half[0].storage()) - 0.14) < 1e-8,
          "The projected die reserves its downward sweep above the passive work surface.");
    check(get<bool>(host.publish_actor("P", {V(5.8), V(1.0), V(3.3)}, 4), "accepted"),
          "The actor can leave the placed die to gather a finite slide bill.");
    for (const char* request : {"slide-tree-1", "slide-tree-2", "slide-tree-3"})
        check(get<bool>(command(request, "harvest_source", {{"target", V("tree-east-south")}}),
                "accepted"),
              "The wooden slide consumes three distinct finite timber cuts.");
    check(get<bool>(command("shape-slide", "field_craft", {{"component", V("wooden_slide")}}),
            "accepted") &&
          get<bool>(host.publish_actor("P", {V(4.2), V(1.0), V(3.3)}, 5), "accepted"),
          "The actor shapes a separate slide and returns to the same physical build site.");
    const auto slide = command("place-slide", "place_component",
        {{"component", V("wooden_slide")}, {"center", V(A{V(I{12}), V(I{2}), V(I{8})})}});
    check(get<bool>(slide, "accepted") &&
          get<O>(host.projection(), "placed_components").size() == 2,
          "The slide fits over the previously placed head without consuming another shaft.");
    const auto slide_id = get<std::string>(slide, "entity");
    const auto saved = host.checkpoint();
    Host restored;
    check(get<bool>(restored.initialize_arrival("flat-head-site", {"P", "Q"}), "accepted") &&
          get<bool>(restored.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(restored.restore_checkpoint(saved), "accepted") &&
          !factory::values::typed_difference(saved, restored.checkpoint()),
          "The placed head, slide and spent raw stock persist through an exact fresh Host restore.");
    check(get<bool>(restored.publish_actor("P", {V(4.2), V(1.0), V(3.3)}, 6), "accepted"),
          "The restored actor can reach the same placed die.");
    const auto reclaimed = restored.command("P", O{{"context", V("flat-head-site")},
        {"client", V("P")}, {"request", V("reclaim")},
        {"action", V("reclaim_component")}, {"entity", V(id)}});
    check(get<bool>(reclaimed, "accepted") &&
          get<O>(restored.projection(), "placed_components").size() == 1 &&
          get<I>(V(get<O>(get<O>(restored.projection(), "cargo").at("P"), "components")),
              "flat_head") == 1,
          "Reclaim returns the head to carried custody while the slide remains in place.");
    const auto replaced = restored.command("P", O{{"context", V("flat-head-site")},
        {"client", V("P")}, {"request", V("replace-head")},
        {"action", V("place_component")}, {"component", V("flat_head")},
        {"center", V(A{V(I{12}), V(I{1}), V(I{8})})}});
    check(get<bool>(replaced, "accepted") &&
          get<O>(restored.projection(), "placed_components").contains(slide_id) &&
          get<O>(restored.projection(), "placed_components").size() == 2,
          "The head also fits after a slide is already placed at the matching grid center.");
    const auto resumed = [&](const char* request, const char* action, O extra) {
        O wire{{"context", V("flat-head-site")}, {"client", V("P")},
            {"request", V(request)}, {"action", V(action)}};
        wire.merge(extra);
        return restored.command("P", wire);
    };
    check(get<bool>(restored.publish_actor("P", {V(-1.2375), V(1.0), V(0.0)}, 7), "accepted") &&
          get<bool>(resumed("support-ore-1", "harvest_source",
              {{"target", V("opening-copper")}}), "accepted") &&
          get<bool>(resumed("support-ore-2", "harvest_source",
              {{"target", V("opening-copper")}}), "accepted") &&
          get<bool>(restored.publish_actor("P", {V(3.3), V(1.0), V(4.8)}, 8), "accepted") &&
          get<bool>(resumed("support-craft", "craft_component",
              {{"entity", V("pod-fabrication-hub")}, {"component", V("anvil")}}), "accepted") &&
          get<bool>(restored.publish_actor("P", {V(4.2), V(1.0), V(3.3)}, 9), "accepted"),
          "Two more finite copper cuts produce the separate passive work support.");
    const auto support = resumed("support-place", "place_component",
        {{"component", V("anvil")}, {"center", V(A{V(I{12}), V(I{0}), V(I{8})})}});
    check(get<bool>(support, "accepted"),
          "The passive anvil fits directly beneath the already placed die and slide.");
    const auto assemblies = get<A>(restored.projection(), "sliding_press_assemblies");
    check(assemblies.size() == 1, "One passive support projects one candidate sliding press.");
    const auto press = std::get<O>(assemblies.front().storage());
    const auto fitted = get<O>(V(press), "parts");
    check(get<std::string>(V(press), "status") == "ready" &&
          get<std::string>(V(fitted), "anvil") == get<std::string>(support, "entity") &&
          get<std::string>(V(fitted), "head") == get<std::string>(replaced, "entity") &&
          get<std::string>(V(fitted), "slide") == slide_id &&
          get<A>(V(press), "open_feeds").size() == 2,
          "Ordinary Host projection names the three finite parts and both open X-axis routes.");
    check(get<bool>(restored.publish_actor("P", {V(1.65), V(1.0), V(5.8)}, 10), "accepted") &&
          get<bool>(resumed("take-press-crank", "take_hand_crank",
              {{"entity", V("pod-hand-crank")}}), "accepted") &&
          get<bool>(restored.publish_actor("P", {V(4.2), V(1.0), V(3.3)}, 11), "accepted"),
          "The worker takes the issued crank and returns within reach of the loaded slide.");
    const auto loaded_turn = resumed("loaded-slide-turn", "turn_slide_crank",
        {{"entity", V(slide_id)},
         {"port", V(A{V(I{13}), V(I{2}), V(I{8})})}});
    if (!get<bool>(loaded_turn, "accepted"))
        throw std::runtime_error("Loaded slide turn refused: " +
            get<std::string>(loaded_turn, "reason"));
    check(get<I>(get<O>(restored.projection(), "slide_phases").at(slide_id), "subticks") ==
              factory::materials::work_subticks_per_tick &&
          get<O>(restored.projection(), "placed_components").size() == 3,
          "The unchanged integral slide cycles with the fitted head and passive anvil in place.");
    const auto loaded_saved = restored.checkpoint();
    Host loaded_restored;
    check(get<bool>(loaded_restored.initialize_arrival("flat-head-site", {"P", "Q"}), "accepted") &&
          get<bool>(loaded_restored.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(loaded_restored.restore_checkpoint(loaded_saved), "accepted") &&
          !factory::values::typed_difference(loaded_saved, loaded_restored.checkpoint()),
          "The actual finite head, slide and anvil retain their identities and manual phase through restore.");
    check(get<bool>(restored.publish_actor("P", {V(-1.2375), V(1.0), V(0.0)}, 12), "accepted") &&
          get<bool>(resumed("route-ore", "harvest_source",
              {{"target", V("opening-copper")}}), "accepted") &&
          get<bool>(restored.publish_actor("P", {V(4.2), V(1.0), V(3.3)}, 13), "accepted"),
          "A further finite copper unit reaches the fitted press as an actor-held blank.");
    const auto feed = resumed("feed-slide-west", "feed_press",
        {{"entity", V(get<std::string>(support, "entity"))},
         {"entry", V(A{V(I{11}), V(I{0}), V(I{8})})}});
    if (!get<bool>(feed, "accepted"))
        throw std::runtime_error("Sliding press feed refused: " + get<std::string>(feed, "reason"));
    const auto fed_press = std::get<O>(get<A>(restored.projection(),
        "sliding_press_assemblies").front().storage());
    check(!factory::values::typed_difference(V(get<A>(V(fed_press), "selected_exit")),
              V(A{V(I{13}), V(I{0}), V(I{8})})) &&
          get<I>(get<O>(restored.projection(), "cargo").at("P"), "raw") == 0,
          "One native blank is on the anvil with its chosen east outlet retained.");
    const auto route_saved = restored.checkpoint();
    Host route_restored;
    check(get<bool>(route_restored.initialize_arrival("flat-head-site", {"P", "Q"}), "accepted") &&
          get<bool>(route_restored.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(route_restored.restore_checkpoint(route_saved), "accepted") &&
          !factory::values::typed_difference(route_saved, route_restored.checkpoint()),
          "Checkpoint replay retains the finite blank and its exact selected outlet.");
    auto forged_route = std::get<O>(route_saved.storage());
    auto forged_world = get<O>(V(forged_route), "world");
    auto forged_state = get<O>(V(forged_world), "state");
    auto routes = get<A>(V(forged_state), "slide_press_routes");
    auto forged_entry = std::get<O>(routes.front().storage());
    forged_entry.at("exit") = V(A{V(I{11}), V(I{0}), V(I{8})});
    routes.front() = V(std::move(forged_entry));
    forged_state.at("slide_press_routes") = V(std::move(routes));
    forged_world.at("state") = V(std::move(forged_state));
    forged_route.at("world") = V(std::move(forged_world));
    check(!get<bool>(route_restored.validate_checkpoint(V(std::move(forged_route))), "accepted"),
          "History replay rejects an outlet rewritten after the actor selected its physical feed.");
    auto shared_drop = std::get<O>(get<A>(route_restored.projection(),
        "dropped_material").front().storage());
    shared_drop.erase("center");
    check(get<bool>(route_restored.publish_actor("Q", {V(4.2), V(1.0), V(3.3)}, 1), "accepted"),
          "The second worker has an independent physical sample beside the restored press.");
    const auto shared_pickup = route_restored.command("Q", O{
        {"context", V("flat-head-site")}, {"client", V("Q")},
        {"request", V("shared-slide-pickup")}, {"action", V("pickup_material")},
        {"center", V(A{V(I{12}), V(I{0}), V(I{8})})}, {"expected", V(shared_drop)}});
    check(get<bool>(shared_pickup, "accepted") &&
          get<I>(get<O>(route_restored.projection(), "cargo").at("Q"), "raw") == 1 &&
          get<I>(get<O>(route_restored.projection(), "cargo").at("P"), "raw") == 0 &&
          !std::get<O>(get<A>(route_restored.projection(),
              "sliding_press_assemblies").front().storage()).contains("selected_exit"),
          "A second client recovers the first worker's blank after restore and clears the shared route.");
    check(!get<bool>(resumed("reclaim-loaded-anvil", "reclaim_component",
              {{"entity", V(get<std::string>(support, "entity"))}}), "accepted"),
          "The work support cannot be reclaimed while it owns a selected route and blank.");
    auto drop = std::get<O>(get<A>(restored.projection(), "dropped_material").front().storage());
    drop.erase("center");
    const auto picked = resumed("recover-slide-blank", "pickup_material",
        {{"center", V(A{V(I{12}), V(I{0}), V(I{8})})}, {"expected", V(drop)}});
    check(get<bool>(picked, "accepted") &&
          !std::get<O>(get<A>(restored.projection(),
              "sliding_press_assemblies").front().storage()).contains("selected_exit") &&
          get<I>(get<O>(restored.projection(), "cargo").at("P"), "raw") == 1,
          "Recovering the untouched blank clears its route and returns exactly one raw unit.");
    check(!get<bool>(resumed("blocked-slide-entry", "feed_press",
              {{"entity", V(get<std::string>(support, "entity"))},
               {"entry", V(A{V(I{12}), V(I{0}), V(I{9})})}}), "accepted") &&
          get<I>(get<O>(restored.projection(), "cargo").at("P"), "raw") == 1,
          "A non-feed direction cannot spend the recovered blank or select an outlet.");
    const auto opposite = resumed("feed-slide-east", "feed_press",
        {{"entity", V(get<std::string>(support, "entity"))},
         {"entry", V(A{V(I{13}), V(I{0}), V(I{8})})}});
    check(get<bool>(opposite, "accepted") &&
          !factory::values::typed_difference(
              V(get<A>(V(std::get<O>(get<A>(restored.projection(),
                  "sliding_press_assemblies").front().storage())), "selected_exit")),
              V(A{V(I{11}), V(I{0}), V(I{8})})),
          "The same native blank can select the opposite clear outlet after recovery.");
    check(!get<bool>(resumed("old-press-bypass", "turn_press_crank",
              {{"entity", V(get<std::string>(support, "entity"))},
               {"drive", V(slide_id)},
               {"exit", V(A{V(I{11}), V(I{0}), V(I{8})})}}), "accepted") &&
          get<I>(get<O>(restored.projection(), "slide_phases").at(slide_id), "subticks") ==
              factory::materials::work_subticks_per_tick,
          "The old anvil crank cannot bypass the unchanged slide phase and advance the blank.");
    const auto lifted = resumed("exchange-loaded-head", "reclaim_component",
        {{"entity", V(get<std::string>(replaced, "entity"))}});
    check(get<bool>(lifted, "accepted") &&
          get<I>(get<O>(restored.projection(), "cargo").at("P"), "raw") == 0,
          "The interchangeable die can be reclaimed without returning or spending work on its anvil.");
    const auto refitted = resumed("refit-loaded-head", "place_component",
        {{"component", V("flat_head")},
         {"center", V(A{V(I{12}), V(I{1}), V(I{8})})}});
    check(get<bool>(refitted, "accepted") &&
          get<A>(V(std::get<O>(get<A>(restored.projection(),
              "sliding_press_assemblies").front().storage())), "open_feeds").size() == 2 &&
          !factory::values::typed_difference(
              V(get<A>(V(std::get<O>(get<A>(restored.projection(),
                  "sliding_press_assemblies").front().storage())), "selected_exit")),
              V(A{V(I{11}), V(I{0}), V(I{8})})),
          "Refitting the head restores a ready assembly while the chosen output remains fixed.");
    const auto first_contact = resumed("first-slide-contact", "turn_slide_crank",
        {{"entity", V(slide_id)}, {"port", V(A{V(I{13}), V(I{2}), V(I{8})})}});
    if (!get<bool>(first_contact, "accepted"))
        throw std::runtime_error("First slide contact refused: " +
            get<std::string>(first_contact, "reason"));
    const auto partial_drop = get<A>(restored.projection(), "dropped_material");
    const auto partial_work = std::get<O>(partial_drop.front().storage());
    const auto partial_lots = get<A>(V(partial_work), "work_lots");
    check(get<bool>(first_contact, "contact") && partial_lots.size() == 1 &&
          get<I>(V(partial_work), "raw") == 0 &&
          get<I>(V(std::get<O>(partial_lots.front().storage())), "remaining") > 0,
          "The bottom crossing converts one native blank into identified, unfinished plate work.");
    const auto partial_saved = restored.checkpoint();
    Host partial_restored;
    check(get<bool>(partial_restored.initialize_arrival("flat-head-site", {"P", "Q"}), "accepted") &&
          get<bool>(partial_restored.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(partial_restored.restore_checkpoint(partial_saved), "accepted") &&
          !factory::values::typed_difference(partial_saved, partial_restored.checkpoint()),
          "A fresh Host replays the exact first physical contact, partial work identity and slide phase.");
    auto forged_contact = std::get<O>(partial_saved.storage());
    auto contact_world = get<O>(V(forged_contact), "world");
    auto contact_history = get<O>(V(contact_world), "history");
    auto contact_records = get<A>(V(contact_history), "records");
    auto contact_record = std::get<O>(contact_records.back().storage());
    auto contact_result = get<O>(V(contact_record), "result");
    auto contact_lots = get<A>(V(contact_result), "work_lots");
    auto forged_lot = std::get<O>(contact_lots.front().storage());
    forged_lot.at("remaining_ticks") = V(I{0});
    contact_lots.front() = V(std::move(forged_lot));
    contact_result.at("work_lots") = V(std::move(contact_lots));
    contact_record.at("result") = V(std::move(contact_result));
    contact_records.back() = V(std::move(contact_record));
    contact_history.at("records") = V(std::move(contact_records));
    contact_world.at("history") = V(std::move(contact_history));
    forged_contact.at("world") = V(std::move(contact_world));
    check(!get<bool>(partial_restored.validate_checkpoint(V(std::move(forged_contact))), "accepted"),
          "History replay refuses a forged work reduction at the first slide contact.");
    check(get<bool>(partial_restored.publish_actor("Q", {V(6.0), V(1.0), V(3.3)}, 1), "accepted"),
          "A second worker can approach the saved partial work from a separate actor sample.");
    auto shared_work = std::get<O>(get<A>(partial_restored.projection(),
        "dropped_material").front().storage());
    shared_work.erase("center");
    const auto shared_work_id = get<I>(V(std::get<O>(get<A>(V(shared_work),
        "work_lots").front().storage())), "id");
    const auto second_pickup = partial_restored.command("Q", O{
        {"context", V("flat-head-site")}, {"client", V("Q")},
        {"request", V("shared-partial-pickup")}, {"action", V("pickup_material")},
        {"center", V(A{V(I{12}), V(I{0}), V(I{8})})}, {"expected", V(shared_work)}});
    check(get<bool>(second_pickup, "accepted") &&
          get<A>(get<O>(partial_restored.projection(), "cargo").at("Q"), "work_lots").size() == 1,
          "Q recovers P's identified unfinished work without converting it back to raw stock.");
    const auto second_refeed = partial_restored.command("Q", O{
        {"context", V("flat-head-site")}, {"client", V("Q")},
        {"request", V("shared-partial-refeed")}, {"action", V("refeed_press_work")},
        {"entity", V(get<std::string>(support, "entity"))},
        {"entry", V(A{V(I{13}), V(I{0}), V(I{8})})}, {"work_id", V(shared_work_id)}});
    check(get<bool>(second_refeed, "accepted") &&
          get<A>(get<O>(partial_restored.projection(), "cargo").at("Q"), "work_lots").empty(),
          "Q returns the same unfinished WorkId to the retained west-exit route.");
    const auto shared_partial_saved = partial_restored.checkpoint();
    check(get<bool>(partial_restored.validate_checkpoint(shared_partial_saved), "accepted"),
          "The second client's pickup and refeed preserve one exact native work identity.");
    check(get<bool>(partial_restored.publish_actor("P", {V(6.0), V(1.0), V(3.3)}, 1), "accepted"),
          "The original crank holder can resume the second client's reinserted work.");
    for (int index = 0; index < 4; ++index) {
        const auto shared_stroke = partial_restored.command("P", O{
            {"context", V("flat-head-site")}, {"client", V("P")},
            {"request", V("shared-resume-" + std::to_string(index))},
            {"action", V("turn_slide_crank")}, {"entity", V(slide_id)},
            {"port", V(A{V(I{13}), V(I{2}), V(I{8})})}});
        check(get<bool>(shared_stroke, "accepted") &&
              get<bool>(shared_stroke, "contact") == (index == 3),
              "The shared partial lot advances only on the next actual lower crossing.");
    }
    check(get<I>(V(std::get<O>(get<A>(V(std::get<O>(get<A>(
              partial_restored.projection(), "dropped_material").front().storage())),
              "work_lots").front().storage())), "id") == shared_work_id &&
          get<bool>(partial_restored.validate_checkpoint(partial_restored.checkpoint()), "accepted"),
          "The same WorkId survives a second-client refeed, resumed stroke and replay.");
    auto forged_progress = std::get<O>(partial_restored.checkpoint().storage());
    auto progress_world = get<O>(V(forged_progress), "world");
    auto progress_history = get<O>(V(progress_world), "history");
    auto progress_records = get<A>(V(progress_history), "records");
    auto progress_record = std::get<O>(progress_records.back().storage());
    auto progress_result = get<O>(V(progress_record), "result");
    auto progress_lots = get<A>(V(progress_result), "prior_work_lots");
    auto progress_lot = std::get<O>(progress_lots.front().storage());
    progress_lot.at("remaining_ticks") = V(get<I>(V(progress_lot), "remaining_ticks") - 1);
    progress_lots.front() = V(std::move(progress_lot));
    progress_result.at("prior_work_lots") = V(std::move(progress_lots));
    progress_record.at("result") = V(std::move(progress_result));
    progress_records.back() = V(std::move(progress_record));
    progress_history.at("records") = V(std::move(progress_records));
    progress_world.at("history") = V(std::move(progress_history));
    forged_progress.at("world") = V(std::move(progress_world));
    check(!get<bool>(partial_restored.validate_checkpoint(V(std::move(forged_progress))), "accepted"),
          "Replay rejects a saved slide contact that skips an unwitnessed work reduction.");
    check(get<bool>(restored.publish_actor("P", {V(5.8), V(1.0), V(3.3)}, 14), "accepted"),
          "The crank holder can walk to a finite timber site without losing the work lot.");
    for (const char* request : {"blocker-tree-1", "blocker-tree-2", "blocker-tree-3"})
        check(get<bool>(resumed(request, "harvest_source",
                  {{"target", V("tree-east-south")}}), "accepted"),
              "Three more finite timber units supply an actual output obstruction.");
    check(get<bool>(resumed("shape-exit-blocker", "field_craft",
              {{"component", V("wooden_slide")}}), "accepted") &&
          get<bool>(restored.publish_actor("P", {V(6.0), V(1.0), V(3.3)}, 15), "accepted"),
          "The worker brings one starter slide back to obstruct the selected outlet.");
    const auto blocker = resumed("block-slide-exit", "place_component",
        {{"component", V("wooden_slide")},
         {"center", V(A{V(I{11}), V(I{0}), V(I{8})})}});
    if (!get<bool>(blocker, "accepted"))
        throw std::runtime_error("Slide outlet blocker refused: " +
            get<std::string>(blocker, "reason"));
    const auto turn = [&](const std::string& request) {
        return resumed(request.c_str(), "turn_slide_crank",
            {{"entity", V(slide_id)}, {"port", V(A{V(I{13}), V(I{2}), V(I{8})})}});
    };
    for (int index = 0; index < 3; ++index) {
        const auto idle_turn = turn("blocked-approach-" + std::to_string(index));
        check(get<bool>(idle_turn, "accepted") && !get<bool>(idle_turn, "contact") &&
              get<A>(V(std::get<O>(get<A>(restored.projection(),
                  "dropped_material").front().storage())), "work_lots").size() == 1,
              "Only a lower crossing can change the retained copper work.");
    }
    const auto phase_before_blocked = get<O>(restored.projection(), "slide_phases").at(slide_id);
    const auto blocked = turn("blocked-slide-contact");
    check(!get<bool>(blocked, "accepted") &&
          get<std::string>(blocked, "reason") == "blocked_exit" &&
          !factory::values::typed_difference(phase_before_blocked,
              get<O>(restored.projection(), "slide_phases").at(slide_id)) &&
          get<A>(V(std::get<O>(get<A>(restored.projection(),
              "dropped_material").front().storage())), "work_lots").size() == 1,
          "A real blocked outlet refuses the impact without moving phase or spending partial work.");
    check(get<bool>(resumed("clear-slide-exit", "reclaim_component",
              {{"entity", V(get<std::string>(blocker, "entity"))}}), "accepted"),
          "Reclaiming the blocker reopens the originally selected physical outlet.");
    const auto resumed_contact = turn("resume-slide-contact");
    check(get<bool>(resumed_contact, "accepted") && get<bool>(resumed_contact, "contact"),
          "The same pending downstroke advances the retained work after its outlet clears.");
    const auto remaining = get<I>(V(std::get<O>(partial_lots.front().storage())), "remaining");
    for (I cycle = 1; cycle < remaining; ++cycle) {
        for (int turn_index = 0; turn_index < 4; ++turn_index) {
            const auto stroke = turn("form-slide-" + std::to_string(cycle) + "-" +
                std::to_string(turn_index));
            if (!get<bool>(stroke, "accepted"))
                throw std::runtime_error("Sliding plate stroke refused: " +
                    get<std::string>(stroke, "reason"));
            check(get<bool>(stroke, "contact") == (turn_index == 3),
                  "Each four-turn cycle has exactly one native lower contact.");
        }
    }
    const auto formed = get<A>(restored.projection(), "dropped_material");
    check(formed.size() == 2 &&
          std::any_of(formed.begin(), formed.end(), [](const V& value) {
              const auto& item = std::get<O>(value.storage());
              return get<I>(V(item), "products") == 1 &&
                  get<A>(V(item), "center").size() == 3;
          }) && !std::get<O>(get<A>(restored.projection(),
              "sliding_press_assemblies").front().storage()).contains("selected_exit"),
          "Repeated actual downstrokes form one native plate and release the feed route.");
    const auto finished_saved = restored.checkpoint();
    Host finished_restored;
    check(get<bool>(finished_restored.initialize_arrival("flat-head-site", {"P", "Q"}), "accepted") &&
          get<bool>(finished_restored.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(finished_restored.restore_checkpoint(finished_saved), "accepted") &&
          !factory::values::typed_difference(finished_saved, finished_restored.checkpoint()),
          "Fresh replay retains the formed plate, offcut and exact slide phase with no live route.");
    const auto product = std::find_if(formed.begin(), formed.end(), [](const V& value) {
        return get<I>(value, "products") == 1;
    });
    auto plate_expected = std::get<O>(product->storage());
    plate_expected.erase("center");
    check(get<bool>(finished_restored.publish_actor("Q", {V(6.0), V(1.0), V(3.3)}, 1), "accepted"),
          "The second worker reaches the actual completed plate after restore.");
    const auto plate_pickup = finished_restored.command("Q", O{
        {"context", V("flat-head-site")}, {"client", V("Q")},
        {"request", V("shared-slide-plate")}, {"action", V("pickup_material")},
        {"center", V(A{V(I{11}), V(I{0}), V(I{8})})}, {"expected", V(plate_expected)}});
    check(get<bool>(plate_pickup, "accepted") &&
          get<I>(get<O>(finished_restored.projection(), "cargo").at("Q"), "products") == 1 &&
          get<I>(get<O>(finished_restored.projection(), "cargo").at("P"), "products") == 0 &&
          get<bool>(finished_restored.validate_checkpoint(finished_restored.checkpoint()), "accepted"),
          "A different actor picks up the saved first plate without duplicating its native identity.");
    const auto completed = get<A>(finished_restored.projection(), "workshop_completed_actors");
    const auto attempt_cog = [&](const char* actor, const char* request) {
        return finished_restored.command(actor, O{{"context", V("flat-head-site")},
            {"client", V(actor)}, {"request", V(request)}, {"action", V("field_craft")},
            {"component", V("wooden_cog")}});
    };
    const auto still_locked = attempt_cog("P", "first-plate-p-still-locked");
    const auto newly_unlocked = attempt_cog("Q", "first-plate-q-unlocked");
    check(completed.size() == 1 && std::get<std::string>(completed.front().storage()) == "Q" &&
          !get<bool>(still_locked, "accepted") &&
          get<std::string>(still_locked, "reason") == "first_plate_required" &&
          get<std::string>(newly_unlocked, "reason") != "first_plate_required",
          "Only the worker who physically carries the first plate may start advanced crafting.");
    const auto unlocked_saved = finished_restored.checkpoint();
    Host unlocked_restored;
    check(get<bool>(unlocked_restored.initialize_arrival("flat-head-site", {"P", "Q"}), "accepted") &&
          get<bool>(unlocked_restored.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(unlocked_restored.restore_checkpoint(unlocked_saved), "accepted") &&
          !factory::values::typed_difference(unlocked_saved, unlocked_restored.checkpoint()),
          "Fresh replay preserves the actor-specific first-plate unlock and carried plate.");
}

void shared_fast_setting_and_restore() {
    Host host;
    check(get<bool>(host.initialize_arrival_advanced_fixture("fast-site", {"P", "Q"}), "accepted") &&
          get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(host.publish_actor("P", {V(5.8), V(1.0), V(3.3)}, 1), "accepted") &&
          get<bool>(host.publish_actor("Q", {V(-1.2375), V(1.0), V(0.0)}, 1), "accepted") &&
          !get<bool>(V(get<O>(host.projection(), "options")), "developer_conveniences"),
          "Both actors begin in the same timed native arrival session.");
    check(get<bool>(host.command("P", fast_site_cut("P", "ordinary-start", "tree-east-south")), "accepted") &&
          get<O>(host.projection(), "manual_cuts").contains("P"),
          "Normal Host harvesting starts the timed cut before F3 mode is enabled.");
    check(get<bool>(host.command("Q", conveniences("Q", "enable-fast", true)), "accepted") &&
          get<bool>(V(get<O>(host.projection(), "options")), "developer_conveniences") &&
          get<O>(host.projection(), "manual_cuts").empty() &&
          get<I>(get<O>(host.projection(), "hand_sources").at("tree-east-south"), "remaining") == 8,
          "The one shared setting cancels P's unfinished cut without transferring timber.");
    const auto first = host.command("P", fast_site_cut("P", "fast-tree", "tree-east-south"));
    check(get<bool>(first, "accepted") && get<O>(host.projection(), "manual_cuts").empty() &&
          get<I>(get<O>(host.projection(), "cargo").at("P"), "timber") == 1 &&
          get<I>(get<O>(host.projection(), "hand_sources").at("tree-east-south"), "remaining") == 7,
          "The normal client wire receives one immediate native timber transfer while mode is on.");
    check(get<bool>(host.command("P", fast_site_cut("P", "fast-tree", "tree-east-south")), "duplicate") &&
          get<I>(get<O>(host.projection(), "cargo").at("P"), "timber") == 1,
          "An exact Host retry cannot duplicate fast timber.");
    check(get<bool>(host.command("Q", fast_site_cut("Q", "fast-ore", "opening-copper")), "accepted") &&
          get<I>(get<O>(host.projection(), "cargo").at("Q"), "raw") == 1 &&
          get<I>(get<O>(host.projection(), "hand_sources").at("opening-copper"), "remaining") ==
              get<I>(V(get<O>(host.projection(), "source_deposit")), "initial_units") - 1,
          "Q's immediate ore cut spends the same finite native reserve.");
    const auto saved = host.checkpoint();
    check(get<bool>(host.validate_checkpoint(saved), "accepted"),
          "The shared fast setting and mixed native harvest history validate before save.");
    Host restored;
    check(get<bool>(restored.initialize_arrival_advanced_fixture("fast-site", {"P", "Q"}), "accepted") &&
          get<bool>(restored.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(restored.restore_checkpoint(saved), "accepted") &&
          get<bool>(V(get<O>(restored.projection(), "options")), "developer_conveniences"),
          "Fresh Host restore exposes the same authoritative fast setting to both actors.");
    check(get<bool>(restored.publish_actor("P", {V(5.8), V(1.0), V(3.3)}, 2), "accepted") &&
          get<bool>(restored.publish_actor("Q", {V(-1.2375), V(1.0), V(0.0)}, 2), "accepted") &&
          get<bool>(restored.command("Q", conveniences("Q", "disable-fast", false)), "accepted") &&
          !get<bool>(V(get<O>(restored.projection(), "options")), "developer_conveniences"),
          "Either actor can turn the restored shared setting off.");
    check(get<bool>(restored.command("P", fast_site_cut("P", "ordinary-again", "tree-east-south")), "accepted") &&
          get<O>(restored.projection(), "manual_cuts").contains("P") &&
          get<I>(get<O>(restored.projection(), "hand_sources").at("tree-east-south"), "remaining") == 7,
          "Turning the setting off restores ordinary timed harvesting without early payout.");
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

V complete_cut(Host& host, const std::string& actor, const O& wire) {
    const auto target = std::get<std::string>(wire.at("target").storage());
    const auto before = host.projection();
    const auto source_before = get<I>(get<O>(before, "hand_sources").at(target), "remaining");
    const auto ore = get<std::string>(get<O>(before, "hand_sources").at(target), "kind") == "ore_deposit";
    const auto cargo_before = get<I>(get<O>(before, "cargo").at(actor), ore ? "raw" : "timber");
    const auto started = host.command(actor, wire);
    if (!get<bool>(started, "accepted") || get<bool>(started, "duplicate")) return started;
    for (I index = 0; index < factory::world::manual_cut_ticks; ++index) {
        const auto projection = host.advance();
        if (index + 1 < factory::world::manual_cut_ticks &&
            !get<O>(projection, "manual_cuts").contains(actor))
            throw std::runtime_error("The trusted Host lost the active cut before contact.");
    }
    const auto after = host.projection();
    if (get<O>(after, "manual_cuts").contains(actor) ||
        get<I>(get<O>(after, "hand_sources").at(target), "remaining") != source_before - 1 ||
        get<I>(get<O>(after, "cargo").at(actor), ore ? "raw" : "timber") != cargo_before + 1)
        throw std::runtime_error("The trusted Host did not complete one finite cut at contact.");
    return started;
}

void cutter_reach_is_shorter_than_build_reach() {
    Host host;
    check(get<bool>(host.initialize_arrival_advanced_fixture("harvest-site", {"P"}), "accepted") &&
          get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(host.publish_actor("P", {V(4.0), V(1.0), V(3.3)}, 1), "accepted"),
          "The actor is inside construction reach but beyond the held blade's bark contact.");
    const auto capabilities = get<O>(get<O>(host.projection(), "actors").at("P"), "capabilities");
    check(get<double>(V(capabilities), "build_reach") == 4.0 &&
          get<double>(V(capabilities), "harvest_reach") == 2.55,
          "The projection exposes the distinct native construction and harvesting limits.");
    const auto distant = host.command("P", cut("P", "too-far-for-tool", "tree-east-south"));
    check(!get<bool>(distant, "accepted") && get<std::string>(distant, "reason") == "out_of_reach" &&
          get<O>(host.projection(), "manual_cuts").empty() &&
          get<I>(get<O>(host.projection(), "hand_sources").at("tree-east-south"), "remaining") == 8,
          "Construction reach cannot begin or consume a physical source cut.");
    check(get<bool>(host.publish_actor("P", {V(4.1), V(1.0), V(3.3)}, 2), "accepted") &&
          get<bool>(host.command("P", cut("P", "near-bark", "tree-east-south")), "accepted"),
          "The same actor can start one cut from the blade's contact range.");
    check(get<bool>(host.publish_actor("P", {V(4.0), V(1.0), V(3.3)}, 3), "accepted") &&
          get<O>(host.projection(), "manual_cuts").empty() &&
          get<I>(get<O>(host.projection(), "cargo").at("P"), "timber") == 0,
          "Moving outside blade reach interrupts the held cut before payout.");
    check(get<bool>(host.publish_actor("P", {V(4.1), V(1.0), V(3.3)}, 4), "accepted") &&
          get<bool>(complete_cut(host, "P", cut("P", "back-at-bark", "tree-east-south")), "accepted") &&
          get<bool>(host.validate_checkpoint(host.checkpoint()), "accepted"),
          "A fresh close cut transfers exactly one timber and retains valid history.");
    const O enable{{"context", V("harvest-site")}, {"client", V("P")},
        {"request", V("enable-fast-reach")}, {"action", V("set_developer_conveniences")},
        {"enabled", V(true)}};
    check(get<bool>(host.command("P", enable), "accepted") &&
          get<bool>(host.publish_actor("P", {V(4.0), V(1.0), V(3.3)}, 5), "accepted"),
          "F3 convenience mode preserves the same physical actor sample.");
    const auto fast_far = host.command("P", cut("P", "fast-far", "tree-east-south"));
    check(!get<bool>(fast_far, "accepted") && get<std::string>(fast_far, "reason") == "out_of_reach",
          "F3 cannot harvest beyond the ordinary native cut boundary.");
    check(get<bool>(host.publish_actor("P", {V(4.1), V(1.0), V(3.3)}, 6), "accepted") &&
          get<bool>(host.command("P", cut("P", "fast-near", "tree-east-south")), "accepted") &&
          get<I>(get<O>(host.projection(), "cargo").at("P"), "timber") == 2 &&
          get<bool>(host.validate_checkpoint(host.checkpoint()), "accepted"),
          "F3 moves one finite timber immediately inside the same cut boundary.");
}

void harvest_path_respects_obstacles_and_interrupts() {
    auto site = factory::godot_world::tests::flat_site();
    site.insert_or_assign("obstacles", V(A{
        V(A{V(A{V(6.3), V(0.0), V(3.0)}), V(A{V(6.9), V(2.0), V(3.6)})}),
        V(A{V(A{V(5.0), V(0.0), V(3.0)}), V(A{V(5.2), V(2.0), V(3.6)})})}));
    site.emplace("tree_obstacles", V(O{{"tree-east-south", V(I{0})}}));
    Host host;
    check(get<bool>(host.initialize_arrival_advanced_fixture("harvest-site", {"P"}), "accepted") &&
          get<bool>(host.configure_terrain(site), "accepted") &&
          get<bool>(host.publish_actor("P", {V(4.1), V(1.0), V(3.3)}, 1), "accepted"),
          "A trusted source hull and intervening wall bind before the actor cuts.");
    const auto blocked = host.command("P", cut("P", "wall-blocked", "tree-east-south"));
    const auto actor = std::get<O>(get<O>(host.projection(), "actors").at("P").storage());
    check(!get<bool>(blocked, "accepted") && get<std::string>(blocked, "reason") == "source_occluded" &&
          !get<bool>(V(get<O>(V(actor), "harvest_clear")), "tree-east-south") &&
          !get<bool>(V(get<O>(host.actor_projection("P"), "harvest_clear")), "tree-east-south") &&
          get<O>(host.projection(), "manual_cuts").empty(),
          "The visible radial target cannot start through the wall; the prompt receives the same refusal.");
    check(get<bool>(host.publish_actor("P", {V(5.7), V(1.0), V(3.3)}, 2), "accepted") &&
          get<bool>(V(get<O>(get<O>(host.projection(), "actors").at("P"), "harvest_clear")),
              "tree-east-south") &&
          get<bool>(V(get<O>(host.actor_projection("P"), "harvest_clear")),
              "tree-east-south") &&
          get<bool>(host.command("P", cut("P", "clear-bark", "tree-east-south")), "accepted"),
          "The selected tree's own hull does not falsely block contact from the clear side.");
    check(get<bool>(host.publish_actor("P", {V(4.1), V(1.0), V(3.3)}, 3), "accepted") &&
          get<O>(host.projection(), "manual_cuts").empty() &&
          get<I>(get<O>(host.projection(), "cargo").at("P"), "timber") == 0,
          "Moving behind a wall interrupts an active timed cut without giving stock.");
    const O enable{{"context", V("harvest-site")}, {"client", V("P")},
        {"request", V("enable-fast-wall")}, {"action", V("set_developer_conveniences")},
        {"enabled", V(true)}};
    check(get<bool>(host.command("P", enable), "accepted"), "F3 is enabled for the wall admission test.");
    const auto fast_blocked = host.command("P", cut("P", "fast-wall", "tree-east-south"));
    check(!get<bool>(fast_blocked, "accepted") &&
          get<std::string>(fast_blocked, "reason") == "source_occluded" &&
          get<I>(get<O>(host.projection(), "hand_sources").at("tree-east-south"), "remaining") == 8,
          "F3 cannot move finite timber through the same wall.");
    Host restored;
    check(get<bool>(restored.initialize_arrival_advanced_fixture("harvest-site", {"P"}), "accepted") &&
          get<bool>(restored.configure_terrain(site), "accepted") &&
          get<bool>(restored.restore_checkpoint(host.checkpoint()), "accepted") &&
          get<bool>(restored.publish_actor("P", {V(5.7), V(1.0), V(3.3)}, 4), "accepted") &&
          get<bool>(restored.command("P", cut("P", "fast-clear", "tree-east-south")), "accepted") &&
          get<I>(get<O>(restored.projection(), "cargo").at("P"), "timber") == 1 &&
          get<bool>(restored.validate_checkpoint(restored.checkpoint()), "accepted"),
          "A clear F3 cut after restore spends exactly one tree unit with valid history.");
}

void ore_outcrop_has_a_standing_cut_boundary() {
    Host host;
    auto site = factory::godot_world::tests::flat_site();
    site.insert_or_assign("obstacles", V(A{V(A{
        V(A{V(-1.4), V(0.0), V(-1.2)}),
        V(A{V(-0.9), V(1.2), V(1.2)})})}));
    site.emplace("source_obstacle", V(I{0}));
    check(get<bool>(host.initialize_arrival_advanced_fixture("harvest-site", {"P"}), "accepted") &&
          get<bool>(host.configure_terrain(site), "accepted") &&
          get<bool>(host.publish_actor("P", {V(-1.2375), V(0.825), V(3.76)}, 1), "accepted"),
          "The actor samples a standing point outside the opening ore reach.");
    const auto projected = get<O>(host.projection(), "hand_sources").at("opening-copper");
    check(!factory::values::typed_difference(V(get<A>(projected, "contact_bounds")),
          V(A{V(A{V(-1.4), V(0.0), V(-1.2)}), V(A{V(-0.9), V(1.2), V(1.2)})})),
          "The ore projection carries its trusted visible obstacle bounds to the pointed prompt.");
    const auto far = host.command("P", cut("P", "ore-far", "opening-copper"));
    check(!get<bool>(far, "accepted") && get<std::string>(far, "reason") == "out_of_reach" &&
          get<I>(get<O>(host.projection(), "hand_sources").at("opening-copper"), "remaining") == 4096,
          "An out-of-range ore pick cannot consume finite source stock.");
    check(get<bool>(host.publish_actor("P", {V(-1.2375), V(0.825), V(3.74)}, 2), "accepted") &&
          get<bool>(host.command("P", cut("P", "ore-near", "opening-copper")), "accepted"),
          "The same actor starts a timed cut 2.54 m beyond the visible ore hull end.");
    check(get<bool>(host.publish_actor("P", {V(-1.2375), V(0.825), V(3.76)}, 3), "accepted") &&
          get<O>(host.projection(), "manual_cuts").empty() &&
          get<I>(get<O>(host.projection(), "hand_sources").at("opening-copper"), "remaining") == 4096,
          "Leaving the hull-relative cut range interrupts before any ore payout.");
    check(get<bool>(host.publish_actor("P", {V(-1.2375), V(0.825), V(3.74)}, 4), "accepted") &&
          get<bool>(complete_cut(host, "P", cut("P", "ore-standing", "opening-copper")), "accepted") &&
          get<I>(get<O>(host.projection(), "cargo").at("P"), "raw") == 1 &&
          get<bool>(host.validate_checkpoint(host.checkpoint()), "accepted"),
          "A standing ore cut near the visible outcrop transfers one blank with valid history.");
    Host restored;
    check(get<bool>(restored.initialize_arrival_advanced_fixture("harvest-site", {"P"}), "accepted") &&
          get<bool>(restored.configure_terrain(site), "accepted") &&
          get<bool>(restored.restore_checkpoint(host.checkpoint()), "accepted") &&
          get<I>(get<O>(restored.projection(), "cargo").at("P"), "raw") == 1,
          "A fresh Host restores the surface-relative harvest history and finite cargo.");
    auto forged = get<O>(host.checkpoint(), "world");
    auto profile = get<O>(V(forged), "profile");
    auto bounds = get<A>(V(profile), "manual_ore_contact_bounds");
    auto high = std::get<A>(bounds[1].storage());
    high[2] = V(1.3);
    bounds[1] = V(std::move(high));
    profile.at("manual_ore_contact_bounds") = V(std::move(bounds));
    forged.at("profile") = V(std::move(profile));
    auto altered = std::get<O>(host.checkpoint().storage());
    altered.at("world") = V(std::move(forged));
    check(!get<bool>(host.validate_checkpoint(V(std::move(altered))), "accepted"),
          "A saved ore contact surface cannot be enlarged without invalidating the native profile.");
    auto walled = site;
    auto obstacles = std::get<A>(walled.at("obstacles").storage());
    obstacles.emplace_back(A{V(A{V(-1.4), V(0.0), V(2.0)}),
        V(A{V(-0.9), V(2.0), V(2.2)})});
    walled.at("obstacles") = V(std::move(obstacles));
    Host behind_wall;
    check(get<bool>(behind_wall.initialize_arrival_advanced_fixture("harvest-site", {"P"}), "accepted") &&
          get<bool>(behind_wall.configure_terrain(walled), "accepted") &&
          get<bool>(behind_wall.publish_actor("P", {V(-1.2375), V(0.825), V(3.74)}, 1), "accepted"),
          "The ore hull and a separate wall bind to the same native terrain producer.");
    const auto occluded = behind_wall.command("P", cut("P", "ore-behind-wall", "opening-copper"));
    check(!get<bool>(occluded, "accepted") &&
          get<std::string>(occluded, "reason") == "source_occluded" &&
          !get<bool>(V(get<O>(get<O>(behind_wall.projection(), "actors").at("P"),
              "harvest_clear")), "opening-copper") &&
          get<I>(get<O>(behind_wall.projection(), "cargo").at("P"), "raw") == 0,
          "Ore contact ignores its own hull but refuses an intervening wall without paying raw stock.");
}

void field_wood_uses_physical_actor_and_one_ledger() {
    Host host;
    check(get<bool>(host.initialize_arrival_advanced_fixture("field-site", {"P", "Q"}), "accepted") &&
          get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(host.publish_actor("P", {V(5.8), V(1.0), V(3.3)}, 1), "accepted") &&
          get<bool>(host.publish_actor("Q", {V(3.3), V(1.0), V(8.25)}, 1), "accepted"),
          "Two physical actors initialize, with P beyond the pod bench's reach.");
    for (int index = 0; index < 4; ++index) {
        const auto request = "field-cut-" + std::to_string(index);
        const auto outcome = complete_cut(host, "P", field_cut(request.c_str()));
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
    check(get<bool>(restored.initialize_arrival_advanced_fixture("field-site", {"P", "Q"}), "accepted") &&
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
    check(get<bool>(host.initialize_arrival_advanced_fixture("harvest-site", {"P"}), "accepted") &&
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
            const auto result = complete_cut(host, "P", cut("P", request.c_str(), source));
            if (!get<bool>(result, "accepted"))
                throw std::runtime_error(std::string("Harvest refused at ") + source + " after " +
                    std::to_string(cuts) + " cuts: " + get<std::string>(result, "reason"));
        }
    }
    check(cuts > 24 && get<I>(get<O>(host.projection(), "cargo").at("P"), "timber") == cuts &&
          get<bool>(host.validate_checkpoint(host.checkpoint()), "accepted"),
          "The actor carries more than the former bag limit without minting or losing timber.");
    Host reopened;
    check(get<bool>(reopened.initialize_arrival_advanced_fixture("harvest-site", {"P"}), "accepted") &&
          get<bool>(reopened.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(reopened.restore_checkpoint(host.checkpoint()), "accepted") &&
          !factory::values::typed_difference(host.checkpoint(), reopened.checkpoint()) &&
          get<I>(get<O>(reopened.projection(), "cargo").at("P"), "timber") == cuts,
          "Save and rejoin retain all carried timber and depleted source stock.");
}

void shared_harvest() {
    Host host;
    check(get<bool>(host.initialize_arrival_advanced_fixture("harvest-site", {"P", "Q"}), "accepted") &&
          get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()), "accepted"),
          "The trusted arrival site initializes one native source roster.");
    const auto initial = host.projection();
    const auto sources = get<O>(initial, "hand_sources");
    check(sources.size() == 13 && get<I>(sources.at("tree-east-south"), "remaining") == 8 &&
          get<I>(sources.at("broadleaf_00"), "remaining") == 8 &&
          get<I>(sources.at("fir_05"), "remaining") == 8 &&
          get<I>(sources.at("opening-copper"), "remaining") == 4096,
          "The four starter pines, eight mature bank trees and ore reserve share native custody.");
    check(get<bool>(host.publish_actor("P", {V(5.8), V(1.0), V(3.3)}, 1), "accepted") &&
          get<bool>(host.publish_actor("Q", {V(3.3), V(1.0), V(8.25)}, 1), "accepted"),
          "P walks to the clear east timber site while Q remains on the deployed deck.");
    const auto p_cut = cut("P", "tree-first", "tree-east-south");
    check(get<bool>(complete_cut(host, "P", p_cut), "accepted") &&
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
    check(get<bool>(host.publish_actor("Q", {V(-0.5), V(1.0), V(0.0)}, 2), "accepted"),
          "Q can reach the ore side of the site with a new physical observation.");
    check(get<bool>(complete_cut(host, "Q", cut("Q", "ore-first", "opening-copper")), "accepted") &&
          get<I>(get<O>(host.projection(), "hand_sources").at("opening-copper"), "remaining") == 4095 &&
          get<I>(get<O>(host.projection(), "cargo").at("Q"), "raw") == 1,
          "Manual ore mining debits the same source that feeds a future collector.");
    const auto bench = get<O>(host.projection(), "fabrication_hub");
    check(get<std::string>(V(bench), "id") == "pod-fabrication-hub" &&
          get<I>(V(bench), "generation") == 1,
          "One native bench identity is shared by both actors.");
    check(get<bool>(host.publish_actor("P", {V(3.3), V(1.0), V(4.8)}, 2), "accepted"),
          "P walks from the bark to the pod bench before shaping its timber.");
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
    check(get<bool>(host.publish_actor("P", {V(1.65), V(1.0), V(4.8)}, 3), "accepted"),
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
    check(get<bool>(restored.initialize_arrival_advanced_fixture("harvest-site", {"P", "Q"}), "accepted") &&
          get<bool>(restored.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(restored.restore_checkpoint(saved), "accepted") &&
          !factory::values::typed_difference(saved, restored.checkpoint()),
          "A fresh Host restores both actors and all finite source balances.");
}

void mature_bank_tree_stock_survives_shared_restore() {
    Host host;
    check(get<bool>(host.initialize_arrival_advanced_fixture("mature-bank", {"P", "Q"}), "accepted") &&
          get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()), "accepted"),
          "The mature bank tree roster initializes inside the one native arrival profile.");
    const auto sources = get<O>(host.projection(), "hand_sources");
    check(sources.size() == 13 && get<I>(sources.at("broadleaf_00"), "initial") == 8 &&
          get<I>(sources.at("fir_00"), "initial") == 8,
          "Mature broadleaf and fir instances have separate finite source identities.");
    const auto wire = [](const char* actor, const std::string& request, const char* action, O extra) {
        O command{{"context", V("mature-bank")}, {"client", V(actor)},
            {"request", V(request)}, {"action", V(action)}};
        command.merge(extra);
        return command;
    };
    check(get<bool>(host.publish_actor("P", {V(3.3), V(1.0), V(-2.8875)}, 1), "accepted") &&
          get<bool>(host.publish_actor("Q", {V(0.0), V(1.0), V(0.0)}, 1), "accepted") &&
          get<bool>(host.command("P", wire("P", "fast", "set_developer_conveniences",
              {{"enabled", V(true)}})), "accepted"),
          "Native actor samples and fast-mode setup remain shared by both clients.");
    for (int cut_index = 0; cut_index < 8; ++cut_index) {
        const auto request = "broadleaf-" + std::to_string(cut_index);
        check(get<bool>(host.command("P", wire("P", request, "harvest_source",
                  {{"target", V("broadleaf_00")}})), "accepted"),
              "Each broadleaf cut transfers one real finite timber unit.");
    }
    check(get<I>(get<O>(host.projection(), "hand_sources").at("broadleaf_00"), "remaining") == 0 &&
          get<I>(get<O>(host.projection(), "hand_sources").at("fir_00"), "remaining") == 8 &&
          get<I>(get<O>(host.projection(), "cargo").at("P"), "timber") == 8 &&
          get<I>(get<O>(host.projection(), "cargo").at("Q"), "timber") == 0,
          "Depletion of one visual tree cannot alter its neighbor or another actor's custody.");
    const auto saved = host.checkpoint();
    Host restored;
    check(get<bool>(host.validate_checkpoint(saved), "accepted") &&
          get<bool>(restored.initialize_arrival_advanced_fixture("mature-bank", {"P", "Q"}), "accepted") &&
          get<bool>(restored.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(restored.restore_checkpoint(saved), "accepted") &&
          !factory::values::typed_difference(saved, restored.checkpoint()),
          "A fresh Host replays the exact mature-tree stock and shared material history.");
    check(get<bool>(restored.publish_actor("Q", {V(3.3), V(1.0), V(-2.8875)}, 2), "accepted"),
          "A second actor can observe the restored broadleaf site.");
    const auto exhausted = restored.command("Q", wire("Q", "depleted", "harvest_source",
        {{"target", V("broadleaf_00")}}));
    check(!get<bool>(exhausted, "accepted") &&
          get<std::string>(exhausted, "reason") == "unavailable_source" &&
          get<I>(get<O>(restored.projection(), "hand_sources").at("broadleaf_00"), "remaining") == 0 &&
          get<I>(get<O>(restored.projection(), "cargo").at("P"), "timber") == 8 &&
          get<I>(get<O>(restored.projection(), "cargo").at("Q"), "timber") == 0,
          "Neither rejoin nor a second actor can respawn or duplicate the depleted broadleaf.");
}

void placed_bench_preserves_two_actor_custody() {
    Host host;
    check(get<bool>(host.initialize_arrival_advanced_fixture("bench-site", {"P", "Q"}), "accepted") &&
          get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(host.publish_actor("P", {V(5.8), V(1.0), V(3.3)}, 1), "accepted") &&
          get<bool>(host.publish_actor("Q", {V(-0.5), V(1.0), V(0.0)}, 1), "accepted"),
          "Two actors initialize beside different finite material sources.");
    for (int index = 0; index < 4; ++index) {
        const O cut_wood{{"context", V("bench-site")}, {"client", V("P")},
            {"request", V("bench-timber-" + std::to_string(index))},
            {"action", V("harvest_source")}, {"target", V("tree-east-south")}};
        check(get<bool>(complete_cut(host, "P", cut_wood), "accepted"),
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
        {"target", V("opening-copper")}};
    check(get<bool>(complete_cut(host, "Q", mine), "accepted"),
          "Q mines one copper blank from the same finite source used by collectors.");
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
    check(get<bool>(host.publish_actor("P", {V(5.8), V(1.0), V(3.3)}, 3), "accepted"),
          "P returns to the timber site while Q's crafted edge remains in Q's cargo.");
    auto fifth_wood = O{{"context", V("bench-site")}, {"client", V("P")},
        {"request", V("bench-fifth-timber")}, {"action", V("harvest_source")},
        {"target", V("tree-east-south")}};
    check(get<bool>(complete_cut(host, "P", fifth_wood), "accepted"),
          "P harvests one more finite timber for a powered route kit.");
    const O craft_shaft{{"context", V("bench-site")}, {"client", V("P")},
        {"request", V("placed-bench-shaft")}, {"action", V("craft_part")},
        {"entity", V(bench_id)}, {"role", V("shaft")}, {"half_span", V(I{2})}};
    check(get<bool>(host.command("P", craft_shaft), "accepted"),
          "The player-built bench also replaces the pod for finite stationary shaft kits.");
    check(get<bool>(host.publish_actor("P", {V(6.6), V(1.0), V(3.3)}, 4), "accepted"),
          "P returns from the bark to the foundation worksite.");
    const O raised_floor{{"context", V("bench-site")}, {"client", V("P")},
        {"request", V("raised-pod-workshop-floor")}, {"action", V("place_foundation")},
        {"cell", V(A{V(I{6}), V(I{2})})}, {"level", V(I{2})}};
    const auto raised = host.command("P", raised_floor);
    if (!get<bool>(raised, "accepted"))
        throw std::runtime_error("P cannot seat the second foundation: " +
            get<std::string>(raised, "reason"));
    const auto saved = host.checkpoint();
    check(get<bool>(host.command("Q", local_craft), "duplicate") &&
          !factory::values::typed_difference(saved, host.checkpoint()),
          "A repeated craft wire does not mint another metal component.");
    Host restored;
    check(get<bool>(restored.initialize_arrival_advanced_fixture("bench-site", {"P", "Q"}), "accepted") &&
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

void cut_interrupts_on_actor_sample_before_next_tick() {
    Host host;
    check(get<bool>(host.initialize_arrival_advanced_fixture("sample-cut", {"P", "Q"}), "accepted") &&
          get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(host.publish_actor("P", {V(5.8), V(1.0), V(3.3)}, 1), "accepted") &&
          get<bool>(host.publish_actor("Q", {V(5.8), V(1.0), V(3.3)}, 1), "accepted"),
          "Both trusted actors can reach the same finite tree.");
    O reserved{{"context", V("sample-cut")}, {"client", V("P")},
        {"request", V("native-cut-finish-P-1")}, {"action", V("harvest_source")},
        {"target", V("tree-east-south")}};
    check(!get<bool>(host.command("P", reserved), "accepted") &&
          get<std::string>(host.command("P", reserved), "reason") == "reserved_request" &&
          get<O>(host.projection(), "manual_cuts").empty(),
          "A client cannot reserve the server's cut-completion identity.");
    O first = reserved;
    first.at("request") = V("first-cut");
    check(get<bool>(host.command("P", first), "accepted") &&
          get<I>(get<O>(host.projection(), "hand_sources").at("tree-east-south"), "remaining") == 8,
          "Starting the cut holds the tree without collecting timber.");
    O competing = first;
    competing.at("client") = V("Q");
    competing.at("request") = V("competing-cut");
    check(!get<bool>(host.command("Q", competing), "accepted") &&
          get<std::string>(host.command("Q", competing), "reason") == "source_busy",
          "A second actor cannot take the source while P is cutting.");
    check(get<bool>(host.publish_actor("P", {V(20.0), V(1.0), V(20.0)}, 2), "accepted") &&
          get<O>(host.projection(), "manual_cuts").empty() &&
          get<I>(get<O>(host.projection(), "hand_sources").at("tree-east-south"), "remaining") == 8,
          "A trusted far sample cancels the cut before another native time tick.");
    check(get<bool>(host.publish_actor("P", {V(5.8), V(1.0), V(3.3)}, 3), "accepted"),
          "Returning to the same tree cannot resume the canceled cut.");
    for (I tick = 0; tick < factory::world::manual_cut_ticks; ++tick)
        check(get<O>(host.advance(), "manual_cuts").empty(),
              "Unrelated trusted ticks cannot restart a canceled cut.");
    check(get<I>(get<O>(host.projection(), "cargo").at("P"), "timber") == 0,
          "A canceled cut cannot mint timber after enough unrelated ticks.");
    O second = first;
    second.at("request") = V("second-cut");
    check(get<bool>(complete_cut(host, "P", second), "accepted") &&
          get<I>(get<O>(host.projection(), "cargo").at("P"), "timber") == 1,
          "A fresh reachable cut completes once on trusted Host time.");
    O q_cut = competing;
    q_cut.at("request") = V("q-rejoin-cut");
    check(get<bool>(host.command("Q", q_cut), "accepted"),
          "Q can start a separate finite cut after P releases the source.");
    for (I tick = 0; tick < 1; ++tick)
        check(get<O>(host.advance(), "manual_cuts").contains("Q"),
              "Q's source stays reserved before contact.");
    const auto saved = host.checkpoint();
    Host restored;
    check(get<bool>(restored.initialize_arrival_advanced_fixture("sample-cut", {"P", "Q"}), "accepted") &&
          get<bool>(restored.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(restored.restore_checkpoint(saved), "accepted") &&
          !factory::values::typed_difference(saved, restored.checkpoint()),
          "Both actors and the unfinished native cut rejoin from one exact checkpoint.");
    check(get<bool>(restored.publish_actor("P", {V(5.8), V(1.0), V(3.3)}, 1), "accepted") &&
          get<O>(restored.projection(), "manual_cuts").contains("Q") &&
          get<bool>(restored.publish_actor("Q", {V(5.8), V(1.0), V(3.3)}, 1), "accepted"),
          "P's earlier rejoin does not cancel Q's unfinished cut.");
    for (I tick = 1; tick < factory::world::manual_cut_ticks; ++tick)
        check(get<O>(restored.advance(), "cargo").contains("Q"),
              "The restored Host advances Q's remaining trusted cut time.");
    check(get<I>(get<O>(restored.projection(), "cargo").at("Q"), "timber") == 1 &&
          get<I>(get<O>(restored.projection(), "cargo").at("P"), "timber") == 1 &&
          get<I>(get<O>(restored.projection(), "hand_sources").at("tree-east-south"), "remaining") == 6 &&
          get<O>(restored.projection(), "manual_cuts").empty(),
          "Q's restored cut transfers exactly one timber without changing P's prior custody.");
}
}  // namespace

int main() {
    try {
        shared_fast_setting_and_restore();
        one_piece_slide_custody();
        flat_head_host_custody();
        cutter_reach_is_shorter_than_build_reach();
        harvest_path_respects_obstacles_and_interrupts();
        ore_outcrop_has_a_standing_cut_boundary();
        shared_harvest();
        mature_bank_tree_stock_survives_shared_restore();
        field_wood_uses_physical_actor_and_one_ledger();
        opening_actor_carries_finite_site_across_restore();
        placed_bench_preserves_two_actor_custody();
        cut_interrupts_on_actor_sample_before_next_tick();
        std::cout << "harvest_host_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "harvest_host_test: " << error.what() << '\n';
        return 1;
    }
}
