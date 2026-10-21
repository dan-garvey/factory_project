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
bool accepted(const V& value) { return get<bool>(value, "accepted"); }
void outcome(const V& value, bool success, const char* reason) {
    if (accepted(value) != success || get<std::string>(value, "reason") != reason)
        std::cerr << "At check " << checks + 1 << ": expected " << reason << " accepted=" << success
                  << ", got " << get<std::string>(value, "reason") << " accepted=" << accepted(value) << '\n';
    check(accepted(value) == success && get<std::string>(value, "reason") == reason, reason);
}
O request(const char* action, const std::string& id, const char* actor = "P") {
    return {{"context", V("foundation-case")}, {"client", V(actor)}, {"request", V(id)}, {"action", V(action)}};
}
O foundation(const std::string& id, I x, I z, I level) {
    auto wire = request("place_foundation", id);
    wire.emplace("cell", V(A{V(x), V(z)})); wire.emplace("level", V(level));
    return wire;
}
O area(const std::string& id, I x, I z, I end_x, I end_z, I level) {
    auto wire = foundation(id, x, z, level);
    wire.at("action") = V("place_foundations");
    wire.emplace("end_cell", V(A{V(end_x), V(end_z)}));
    return wire;
}
O machine(const std::string& id, const char* kind, I x, I z, I level) {
    auto wire = request("place", id);
    wire.emplace("kind", V(kind)); wire.emplace("cell", V(A{V(x), V(z)})); wire.emplace("level", V(level));
    return wire;
}
O removal(const std::string& id, const std::string& entity) {
    auto wire = request("remove", id); wire.emplace("entity", V(entity)); return wire;
}
I carried(const Host& host, const char* actor = "P") {
    return get<I>(V(get<O>(V(get<O>(host.projection(), "part_kits")), actor)), "foundation");
}
void initialize(Host& host, O site = factory::godot_world::tests::flat_site()) {
    outcome(host.initialize("foundation-case", {"P", "Q"}), true, "initialized");
    outcome(host.configure_terrain(site), true, "terrain_bound");
}

void construction_and_custody() {
    Host host; initialize(host);
    outcome(host.publish_actor("P", {V(9.0), V(1.5), V(6.0)}, 1), true, "actor_published");
    check(carried(host) == 24 && carried(host, "Q") == 0, "The finite kit is assigned once, not shared or manufactured.");
    outcome(host.publish_actor("Q", {V(9.0), V(1.5), V(6.0)}, 1), true, "actor_published");
    auto no_kit = foundation("no-kit", 7, 2, 1); no_kit.at("client") = V("Q");
    outcome(host.command("Q", no_kit), false, "no_part");
    auto remote = foundation("far", 60, 2, 1);
    outcome(host.command("P", remote), false, "out_of_reach");
    check(carried(host) == 24, "A far refusal leaves construction custody unchanged.");
    outcome(host.command("P", machine("unsupported", "belt", 5, 2, 1)), false, "foundation_required");
    const auto a_wire = foundation("island-a", 5, 2, 1);
    const auto a = host.command("P", a_wire); outcome(a, true, "ok");
    const auto b = host.command("P", foundation("island-b", 6, 2, 1)); outcome(b, true, "ok");
    const auto a_id = get<std::string>(a, "entity"), b_id = get<std::string>(b, "entity");
    const auto islands = get<O>(host.projection(), "foundations");
    check(get<I>(islands.at(a_id), "level") == 1 && get<I>(islands.at(b_id), "level") == 1,
          "Independent construction retains one absolute height grid.");
    const auto retry = host.command("P", a_wire);
    check(accepted(retry) && get<bool>(retry, "duplicate") && carried(host) == 22, "An exact retry never consumes another block.");
    auto changed = a_wire; changed.at("level") = V(I{2});
    check(!accepted(host.command("P", changed)) && carried(host) == 22, "Changed reuse cannot reinterpret a prior request.");
    outcome(host.command("P", foundation("overlap", 5, 2, 2)), false, "occupied");
    const auto belt = host.command("P", machine("belt", "belt", 5, 2, 1)); outcome(belt, true, "ok");
    const auto press = host.command("P", machine("press", "processor", 6, 2, 1)); outcome(press, true, "ok");
    const auto entities = get<O>(host.projection(), "entities");
    check(std::get<I>(get<A>(entities.at(get<std::string>(belt, "entity")), "center")[1].storage()) == 1,
          "Machine height uses the same native integer level as its foundation.");
    check(get<A>(host.projection(), "links").size() == 1, "Independent same-height foundations preserve aligned material ports.");
    outcome(host.command("P", removal("loaded-base", a_id)), false, "foundation_in_use");
    const auto saved = host.checkpoint();
    outcome(host.validate_checkpoint(saved), true, "valid");
    Host restored; initialize(restored);
    outcome(restored.restore_checkpoint(saved), true, "restored");
    check(!factory::values::typed_difference(saved, restored.checkpoint()), "Current-format persistence retains exact custody, geometry and request history.");
    check(get<bool>(restored.command("P", a_wire), "duplicate") && carried(restored) == 22,
          "A saved exact retry resolves before new body readiness without refilling stock.");
    outcome(host.command("P", removal("remove-belt", get<std::string>(belt, "entity"))), true, "ok");
    outcome(host.command("P", removal("remove-press", get<std::string>(press, "entity"))), true, "ok");
    outcome(host.command("P", removal("reclaim-a", a_id)), true, "ok");
    outcome(host.command("P", removal("reclaim-b", b_id)), true, "ok");
    check(carried(host) == 24 && get<O>(host.projection(), "foundations").empty(), "Reclamation returns the exact carried supply.");
    const auto bare = host.command("P", machine("bare-global", "belt", 5, 2, 0)); outcome(bare, true, "ok");
    outcome(host.command("P", removal("bare-refund", get<std::string>(bare, "entity"))), true, "ok");
    check(get<I>(V(get<O>(host.projection(), "stock")), "source") == 4096, "Construction never consumes or replenishes the mineral source.");
}

void terrain_and_stacking() {
    Host host; initialize(host);
    outcome(host.publish_actor("P", {V(9.0), V(2.8), V(6.0)}, 1), true, "actor_published");
    const auto lower = host.command("P", foundation("lower", 5, 2, 1)); outcome(lower, true, "ok");
    outcome(host.command("P", foundation("overlapping-height", 5, 2, 2)), false, "occupied");
    const auto upper = host.command("P", foundation("upper", 5, 2, 3)); outcome(upper, true, "ok");
    check(carried(host) == 22, "Vertical attachment uses two common height units and consumes two blocks.");
    outcome(host.validate_checkpoint(host.checkpoint()), true, "valid");
    outcome(host.command("P", removal("lower-refund", get<std::string>(lower, "entity"))), true, "ok");
    outcome(host.validate_checkpoint(host.checkpoint()), true, "valid");
    outcome(host.command("P", removal("upper-refund", get<std::string>(upper, "entity"))), true, "ok");
    Host peak;
    A heights(25, V(-0.02)); heights[12] = V(0.3);
    O site{{"axis", V(A{V(-128.0), V(7.4), V(8.25), V(9.1), V(128.0)})},
        {"heights", V(std::move(heights))},
        {"obstacles", V(A{})}};
    initialize(peak, site);
    outcome(peak.publish_actor("P", {V(9.0), V(1.5), V(9.0)}, 1), true, "actor_published");
    outcome(peak.command("P", foundation("interior-peak", 5, 5, 0)), true, "ok");
    check(carried(peak) == 23, "Foundations can intersect a terrain peak without a support rule.");
    Host blocked;
    auto solid = factory::godot_world::tests::flat_site();
    solid.at("obstacles") = V(A{V(A{V(A{V(8.0), V(-0.1), V(3.0)}), V(A{V(8.5), V(0.2), V(3.6)})})});
    initialize(blocked, solid);
    outcome(blocked.publish_actor("P", {V(9.0), V(1.5), V(6.0)}, 1), true, "actor_published");
    outcome(blocked.command("P", foundation("rock", 5, 2, 1)), true, "ok");
    outcome(blocked.publish_actor("P", {V(11.55), V(3.5), V(6.0)}, 2), true, "actor_published");
    outcome(blocked.command("P", foundation("floating", 7, 2, 9)), true, "ok");
    outcome(blocked.publish_actor("P", {V(11.55), V(1.5), V(6.0)}, 3), true, "actor_published");
    outcome(blocked.command("P", foundation("buried", 7, 2, -1)), true, "ok");
    outcome(blocked.validate_checkpoint(blocked.checkpoint()), true, "valid");
    Host relocated; initialize(relocated, site);
    outcome(relocated.restore_checkpoint(blocked.checkpoint()), true, "restored");
    outcome(blocked.configure_terrain(solid), false, "terrain_already_bound");
    auto malformed = foundation("float-level", 5, 2, 1); malformed.at("level") = V(1.0);
    outcome(host.command("P", malformed), false, "invalid_cell");
}
void rectangular_placement() {
    Host host; initialize(host);
    auto wire = area("rectangle", 60, 20, 62, 21, 17);
    outcome(host.command("P", area("unready", 60, 20, 62, 21, 17)), false, "actor_unready");
    outcome(host.publish_actor("P", {V(0.0), V(1.5), V(0.0)}, 1), true, "actor_published");
    // The entire rectangle is far beyond ordinary reach and floats over terrain.
    const auto result = host.command("P", wire); outcome(result, true, "ok");
    check(get<I>(result, "count") == 6 && carried(host) == 18, "One area consumes exactly six carried foundations.");
    const auto saved = host.checkpoint();
    outcome(host.validate_checkpoint(saved), true, "valid");
    Host restored; initialize(restored);
    outcome(restored.restore_checkpoint(saved), true, "restored");
    check(!factory::values::typed_difference(saved, restored.checkpoint()), "Area history and custody restore exactly.");
    check(get<bool>(restored.command("P", wire), "duplicate") && carried(restored) == 18,
          "Saved area replay needs no fresh body cut and never spends parts twice.");
    auto reused = wire; reused.at("end_cell") = V(A{V(I{63}), V(I{21})});
    check(!accepted(host.command("P", reused)) && carried(host) == 18, "Changed area replay is refused.");
    outcome(host.command("P", area("late-overlap", 59, 20, 60, 20, 17)), false, "occupied");
    check(carried(host) == 18 && get<O>(host.projection(), "foundations").size() == 6,
          "A later overlap rolls back the entire rectangle, not just the occupied tile.");
    outcome(host.command("P", area("too-many-parts", 70, 20, 74, 24, 17)), false, "no_part");
    outcome(host.command("P", area("too-large", 0, 0, 256, 0, 17)), false, "invalid_area");
    auto malformed = area("float-corner", 70, 20, 71, 21, 17);
    malformed.at("end_cell") = V(A{V(71.0), V(I{21})});
    outcome(host.command("P", malformed), false, "invalid_cell");
    outcome(host.command("P", area("actor-blocked", 0, 0, 1, 0, 4)), false, "actor_occupied");
    outcome(host.command("P", machine("machine-still-far", "belt", 60, 20, 17)), false, "out_of_reach");
    outcome(host.command("P", area("reverse-stack", 62, 21, 60, 20, 21)), true, "ok");
    check(carried(host) == 12 && get<O>(host.projection(), "foundations").size() == 12,
          "Reversed corners produce the same aligned footprint exactly one block above.");
    outcome(host.validate_checkpoint(host.checkpoint()), true, "valid");
}

void import_checks_current_machine_site() {
    Host original; initialize(original);
    outcome(original.publish_actor("P", {V(9.0), V(1.5), V(6.0)}, 1), true, "actor_published");
    outcome(original.command("P", machine("ground-belt", "belt", 5, 2, 0)), true, "ok");
    const auto saved = original.checkpoint();
    Host same_site; initialize(same_site);
    outcome(same_site.restore_checkpoint(saved), true, "restored");
    check(!factory::values::typed_difference(saved, same_site.checkpoint()),
          "An unchanged valid ground-machine checkpoint preserves its complete typed state and history.");

    const auto rejects = [&](O site, const char* name, const char* reason) {
        Host placement; initialize(placement, site);
        outcome(placement.publish_actor("P", {V(9.0), V(1.5), V(6.0)}, 1), true, "actor_published");
        outcome(placement.command("P", machine("new-ground-belt", "belt", 5, 2, 0)), false, reason);

        Host loading; initialize(loading, std::move(site));
        const auto before = loading.checkpoint();
        const auto validation = loading.validate_checkpoint(saved);
        std::cout << "{\"site_case\":\"" << name << "\",\"import_accepted\":"
                  << (accepted(validation) ? "true" : "false") << ",\"reason\":\""
                  << get<std::string>(validation, "reason") << "\"}\n";
        outcome(validation, false, reason);
        outcome(loading.restore_checkpoint(saved), false, reason);
        check(!factory::values::typed_difference(before, loading.checkpoint()),
              "A site-invalid import leaves the fresh Host's full state and history unchanged.");
    };
    auto raised = factory::godot_world::tests::flat_site();
    raised.at("heights") = V(A(4, V(0.3)));
    rejects(std::move(raised), "raised", "foundation_required");
    auto lowered = factory::godot_world::tests::flat_site();
    lowered.at("heights") = V(A(4, V(-1.0)));
    rejects(std::move(lowered), "lowered", "foundation_required");
    auto absent = factory::godot_world::tests::flat_site();
    absent.at("axis") = V(A{V(-2.0), V(2.0)});
    rejects(std::move(absent), "absent", "terrain_unavailable");
    auto occupied = factory::godot_world::tests::flat_site();
    occupied.at("obstacles") = V(A{V(A{V(A{V(8.0), V(0.1), V(3.0)}), V(A{V(8.5), V(0.8), V(3.6)})})});
    rejects(std::move(occupied), "occupied", "site_occupied");
}

void machine_clearance_on_free_foundations() {
    Host buried; initialize(buried);
    outcome(buried.publish_actor("P", {V(9.0), V(1.5), V(6.0)}, 1), true, "actor_published");
    outcome(buried.command("P", foundation("buried-support", 5, 2, -4)), true, "ok");
    outcome(buried.validate_checkpoint(buried.checkpoint()), true, "valid");
    const auto placement = buried.command("P", machine("buried-machine", "belt", 5, 2, -4));
    std::cout << "{\"case\":\"machine_on_buried_foundation\",\"accepted\":"
              << (accepted(placement) ? "true" : "false") << ",\"reason\":\""
              << get<std::string>(placement, "reason") << "\"}\n";
    outcome(placement, false, "foundation_required");
    check(get<O>(buried.projection(), "entities").empty() && carried(buried) == 23,
          "The allowed buried foundation stays present, without admitting a machine into terrain.");

    Host elevated; initialize(elevated);
    outcome(elevated.publish_actor("P", {V(9.0), V(2.8), V(6.0)}, 1), true, "actor_published");
    outcome(elevated.command("P", foundation("raised-support", 5, 2, 4)), true, "ok");
    outcome(elevated.command("P", machine("raised-machine", "belt", 5, 2, 4)), true, "ok");
    outcome(elevated.validate_checkpoint(elevated.checkpoint()), true, "valid");

    auto low_site = factory::godot_world::tests::flat_site();
    low_site.at("heights") = V(A(4, V(-2.0)));
    Host low; initialize(low, low_site);
    outcome(low.publish_actor("P", {V(9.0), V(-0.5), V(6.0)}, 1), true, "actor_published");
    outcome(low.command("P", foundation("low-support", 5, 2, -4)), true, "ok");
    outcome(low.command("P", machine("low-machine", "belt", 5, 2, -4)), true, "ok");
    const auto saved = low.checkpoint();
    Host same; initialize(same, low_site);
    outcome(same.restore_checkpoint(saved), true, "restored");
    check(!factory::values::typed_difference(saved, same.checkpoint()),
          "A valid machine on a low foundation restores exactly when current terrain remains clear.");
    Host intruded; initialize(intruded);
    const auto before = intruded.checkpoint();
    outcome(intruded.validate_checkpoint(saved), false, "foundation_required");
    outcome(intruded.restore_checkpoint(saved), false, "foundation_required");
    check(!factory::values::typed_difference(before, intruded.checkpoint()),
          "The same supporting foundation cannot bypass current terrain clearance during restore.");
}
}
int main() {
    try {
        construction_and_custody(); terrain_and_stacking(); rectangular_placement(); import_checks_current_machine_site();
        machine_clearance_on_free_foundations();
        std::cout << "{\"status\":\"pass\",\"checks\":" << checks << ",\"evidence\":\"synthetic_native_foundation_rules\",\"engine_calls\":0}\n";
        return 0;
    } catch (const std::exception& failure) {
        std::cerr << failure.what() << '\n'; return 1;
    }
}
