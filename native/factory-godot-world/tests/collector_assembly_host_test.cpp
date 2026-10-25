#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <cmath>
#include <iostream>
#include <stdexcept>
#include <string>
#include <utility>

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

O source_contact_site(bool other_obstacle = false, bool foot_obstacle = false) {
    auto terrain = factory::godot_world::tests::flat_site();
    A obstacles{V(A{V(A{V(-1.05), V(0.35), V(-0.2)}),
                    V(A{V(-0.75), V(0.95), V(1.8)})})};
    if (other_obstacle)
        obstacles.emplace_back(A{V(A{V(-0.96), V(0.70), V(-0.10)}),
                                  V(A{V(-0.88), V(0.90), V(0.10)})});
    if (foot_obstacle)
        obstacles.emplace_back(A{V(A{V(-0.10), V(0.02), V(-0.10)}),
                                  V(A{V(0.10), V(0.20), V(0.10)})});
    terrain.at("obstacles") = V(std::move(obstacles));
    terrain.emplace("source_obstacle", V(I{0}));
    return terrain;
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
    if (!get<bool>(response, "accepted"))
        std::cerr << "place_component " << kind << " at [" << x << ',' << y << ',' << z
                  << "] refused: " << get<std::string>(response, "reason") << '\n';
    check(get<bool>(response, "accepted"), "A crafted component installs through the ordinary Host command.");
    return get<std::string>(response, "entity");
}

void collector_readiness_tracks_real_parts() {
    Host host;
    check(get<bool>(host.initialize_arrival("assembly-site", {"P", "Q"}), "accepted") &&
          get<bool>(host.configure_terrain(source_contact_site()), "accepted"),
          "The experimental arrival binds one native resource and construction authority.");
    check(get<std::string>(ground_inspection(host), "status") == "missing_frame",
          "An empty ore workcell has no collector.");
    check(get<bool>(host.publish_actor("P", {V(5.8), V(1.0), V(3.3)}, 1), "accepted"),
          "The actor reaches the nearby timber site outside the pod deck.");
    for (int index = 0; index < 7; ++index) {
        auto wire = request("timber-" + std::to_string(index), "harvest_source");
        wire.emplace("target", V("tree-east-south"));
        check(get<bool>(factory::godot_world::tests::complete_manual_cut(host, "P", wire), "accepted"), "Real timber is harvested for the first collector.");
    }
    check(get<bool>(host.publish_actor("P", {V(-0.5), V(1.0), V(0.0)}, 2), "accepted"),
          "The actor moves to the ore deposit.");
    auto ore = request("one-ore", "harvest_source");
    ore.emplace("target", V("opening-copper"));
    check(get<bool>(factory::godot_world::tests::complete_manual_cut(host, "P", ore), "accepted"),
          "A cutting edge consumes one real ore blank from the shared deposit.");
    check(get<bool>(host.publish_actor("P", {V(1.65), V(1.0), V(6.6)}, 3), "accepted"),
          "The actor returns to the pod bench.");
    for (const auto* name : {"wooden_frame", "tool_mount", "cutting_edge", "receiver_tray"}) {
        auto wire = request(std::string("craft-") + name, "craft_component");
        wire.emplace("entity", V("pod-fabrication-hub"));
        wire.emplace("component", V(name));
        check(get<bool>(host.command("P", wire), "accepted"), "The bench crafts one typed collector component.");
    }
    const auto crafted_cargo = get<O>(host.projection(), "cargo").at("P");
    const auto crafted_components = get<O>(V(crafted_cargo), "components");
    check(get<I>(V(crafted_cargo), "timber") == 0 &&
          !crafted_components.contains("wooden_shaft"),
          "The integral wooden input spends its timber without creating a loose shaft.");
    check(get<bool>(host.publish_actor("P", {V(2.0), V(1.0), V(0.0)}, 4), "accepted"),
          "The actor approaches the deposit-facing workcell without occupying it.");
    const auto prepared_layout = host.checkpoint();
    const auto frame = place(host, "wooden_frame", 0, 0, 0, "frame");
    const auto frame_occupied = get<O>(V(get<O>(host.projection(), "placed_components").at(frame)), "occupied");
    const auto frame_center = get<A>(V(frame_occupied), "center");
    const auto frame_half = get<A>(V(frame_occupied), "half");
    check(std::get<double>(frame_center[1].storage()) == 0.45 &&
          std::get<double>(frame_half[1].storage()) == 0.45 &&
          std::get<double>(frame_half[0].storage()) == 0.2025,
          "The frame publishes one load-bearing envelope from the floor to the installed bed.");
    auto overlapping_deck = request("deck-through-frame", "place_foundation");
    overlapping_deck.emplace("cell", V(A{V(I{0}), V(I{0})}));
    overlapping_deck.emplace("level", V(I{2}));
    const auto blocked_deck = host.command("P", overlapping_deck);
    check(!get<bool>(blocked_deck, "accepted") &&
          get<std::string>(blocked_deck, "reason") == "occupied",
          "A later foundation cannot pass through the frame's grounded support.");
    auto overlapping_machine = request("machine-through-frame", "place");
    overlapping_machine.emplace("kind", V("processor"));
    overlapping_machine.emplace("cell", V(A{V(I{0}), V(I{0})}));
    const auto blocked_machine = host.command("P", overlapping_machine);
    check(!get<bool>(blocked_machine, "accepted") &&
          get<std::string>(blocked_machine, "reason") == "occupied",
          "A later complete machine cannot cover a placed component.");
    check(get<std::string>(ground_inspection(host), "status") == "missing_mount",
          "A frame alone does not become a machine.");
    const auto mount = place(host, "tool_mount", -1, 0, 0, "mount");
    auto wrong_source_part = request("wrong-source-part", "place_component");
    wrong_source_part.emplace("component", V("receiver_tray"));
    wrong_source_part.emplace("center", V(A{V(I{-2}), V(I{0}), V(I{0})}));
    const auto wrong_source_result = host.command("P", wrong_source_part);
    check(!get<bool>(wrong_source_result, "accepted") &&
          get<std::string>(wrong_source_result, "reason") == "site_occupied" &&
          get<O>(host.projection(), "placed_components").size() == 2,
          "A non-cutting component cannot occupy the tagged ore source.");
    const auto edge = place(host, "cutting_edge", -2, 0, 0, "edge");
    const auto placed_tools = get<O>(host.projection(), "placed_components");
    const auto mount_box = get<O>(V(placed_tools.at(mount)), "occupied");
    const auto edge_box = get<O>(V(placed_tools.at(edge)), "occupied");
    const auto mount_center = get<A>(V(mount_box), "center");
    const auto mount_half = get<A>(V(mount_box), "half");
    const auto edge_center = get<A>(V(edge_box), "center");
    const auto edge_half = get<A>(V(edge_box), "half");
    const auto component_face = [](const A& center, const A& half, int axis, int side) {
        return std::get<double>(center[axis].storage()) +
            side * std::get<double>(half[axis].storage());
    };
    check(std::abs(component_face(mount_center, mount_half, 1, -1)) < 1e-9 &&
          std::abs(component_face(edge_center, edge_half, 1, -1)) < 1e-9 &&
          std::abs(component_face(mount_center, mount_half, 0, 1) + 0.2025) < 1e-9 &&
          std::abs(component_face(mount_center, mount_half, 0, -1) -
              component_face(edge_center, edge_half, 0, 1)) < 1e-9,
          "Trusted collector tool boxes meet the floor, frame and each other without overlap.");
    const auto receiver = place(host, "receiver_tray", 0, 0, 1, "receiver");
    const auto ready = ground_inspection(host);
    const auto parts = get<O>(ready, "parts");
    check(get<std::string>(ready, "status") == "ready" &&
          get<std::string>(V(parts), "frame") == frame &&
          get<std::string>(V(parts), "mount") == mount &&
          get<std::string>(V(parts), "edge") == edge &&
          get<std::string>(V(parts), "receiver") == receiver &&
          get<std::string>(V(parts), "shaft") == mount,
          "Readiness exposes the mounted cutter's input without an extra local shaft.");
    auto turn = request("first-turn", "turn_hand_crank");
    turn.emplace("entity", V(mount));
    auto premature_turn = turn;
    premature_turn.at("request") = V("no-crank-turn");
    const auto no_crank = host.command("P", premature_turn);
    check(!get<bool>(no_crank, "accepted") &&
          get<std::string>(no_crank, "reason") == "not_crank_holder",
          "A valid assembly cannot cut ore without the finite pod crank.");
    check(get<bool>(host.publish_actor("P", {V(1.65), V(1.0), V(6.6)}, 5), "accepted"),
          "The actor returns physically to the pod.");
    auto take = request("take-crank", "take_hand_crank");
    take.emplace("entity", V("pod-hand-crank"));
    check(get<bool>(host.command("P", take), "accepted"),
          "The actor takes the one identified crank from the pod tray.");
    auto remote_turn = turn;
    remote_turn.at("request") = V("remote-turn");
    const auto far = host.command("P", remote_turn);
    check(!get<bool>(far, "accepted") && get<std::string>(far, "reason") == "out_of_reach",
          "Holding the crank does not grant camera-distance ore extraction.");
    check(get<bool>(host.publish_actor("P", {V(2.0), V(1.0), V(0.0)}, 6), "accepted") &&
          get<bool>(host.publish_actor("Q", {V(2.5), V(1.0), V(0.0)}, 1), "accepted"),
          "Both actors observe the assembled collector input nearby.");
    auto other_turn = turn;
    other_turn.at("client") = V("Q");
    other_turn.at("request") = V("other-turn");
    const auto other = host.command("Q", other_turn);
    check(!get<bool>(other, "accepted") &&
          get<std::string>(other, "reason") == "not_crank_holder",
          "Q cannot turn P's held crank.");
    const auto extracted = host.command("P", turn);
    check(get<bool>(extracted, "accepted") &&
          get<I>(extracted, "source_remaining") == 4094 &&
          get<I>(extracted, "receiver_raw") == 1 &&
          get<I>(get<O>(host.projection(), "hand_sources").at("opening-copper"), "remaining") == 4094,
          "One physical crank turn cuts exactly one finite ore blank into the receiver.");
    const auto after_turn = host.checkpoint();
    check(get<bool>(host.command("P", turn), "duplicate") &&
          !factory::values::typed_difference(after_turn, host.checkpoint()),
          "Exact retry cannot debit ore or duplicate the receiver item.");
    auto full_turn = turn;
    full_turn.at("request") = V("full-turn");
    const auto full = host.command("P", full_turn);
    check(!get<bool>(full, "accepted") &&
          get<std::string>(full, "reason") == "receiver_full" &&
          get<I>(get<O>(host.projection(), "hand_sources").at("opening-copper"), "remaining") == 4094,
          "The full receiver stops extraction before another ore debit.");
    const auto saved = host.checkpoint();
    check(get<bool>(host.validate_checkpoint(saved), "accepted"),
          "A complete component layout validates as an ordinary native checkpoint.");
    Host restored;
    check(get<bool>(restored.initialize_arrival("assembly-site", {"P", "Q"}), "accepted") &&
          get<bool>(restored.configure_terrain(source_contact_site()), "accepted") &&
          get<bool>(restored.restore_checkpoint(saved), "accepted") &&
          get<std::string>(ground_inspection(restored), "status") == "ready" &&
          get<I>(get<O>(restored.projection(), "hand_sources").at("opening-copper"), "remaining") == 4094,
          "A fresh Host derives the same collector and conserved source after restore.");
    Host obstructed;
    check(get<bool>(obstructed.initialize_arrival("assembly-site", {"P", "Q"}), "accepted") &&
          get<bool>(obstructed.configure_terrain(source_contact_site(true)), "accepted"),
          "A distinct obstruction binds to the fresh Host beside the trusted source.");
    const auto obstructed_restore = obstructed.restore_checkpoint(saved);
    check(!get<bool>(obstructed_restore, "accepted") &&
          get<std::string>(obstructed_restore, "reason") == "site_occupied" &&
          get<O>(obstructed.projection(), "placed_components").empty(),
          "A second obstacle at the cutter refuses checkpoint import without installing parts.");
    Host foot_obstructed;
    check(get<bool>(foot_obstructed.initialize_arrival("assembly-site", {"P", "Q"}), "accepted") &&
          get<bool>(foot_obstructed.configure_terrain(source_contact_site(false, true)), "accepted"),
          "A small independent ground obstacle binds below the saved frame.");
    const auto foot_restore = foot_obstructed.restore_checkpoint(saved);
    check(!get<bool>(foot_restore, "accepted") &&
          get<std::string>(foot_restore, "reason") == "site_occupied" &&
          get<O>(foot_obstructed.projection(), "placed_components").empty(),
          "Fresh import rejects a foot-level obstruction that the old anchor cube would miss.");
    check(get<bool>(restored.publish_actor("P", {V(2.0), V(1.0), V(0.0)}, 7), "accepted"),
          "The restored actor publishes a current physical pose before edits.");
    auto pickup = request("pickup-first", "pickup_material");
    pickup.emplace("center", V(A{V(I{0}), V(I{0}), V(I{1})}));
    pickup.emplace("expected", V(O{{"raw", V(I{1})}, {"products", V(I{0})},
        {"work_lots", V(A{})}, {"offcuts", V(I{0})}, {"sheets", V(I{0})}}));
    check(get<bool>(restored.command("P", pickup), "accepted") &&
          get<I>(get<O>(restored.projection(), "cargo").at("P"), "raw") == 1,
          "The actor can recover the actual receiver item after restore.");
    auto take_mount = request("take-mount", "reclaim_component");
    take_mount.emplace("entity", V(mount));
    check(get<bool>(restored.command("P", take_mount), "accepted") &&
          get<std::string>(ground_inspection(restored), "status") == "missing_mount" &&
          get<I>(get<O>(restored.projection(), "cargo").at("P"), "raw") == 1 &&
          !get<O>(get<O>(restored.projection(), "cargo").at("P"), "components")
              .contains("wooden_shaft"),
          "Reclaiming the embodied input removes drive readiness without creating loose shaft stock.");
    const auto remount = place(restored, "tool_mount", -1, 0, 0, "remount");
    auto take_tray = request("take-tray", "reclaim_component");
    take_tray.emplace("entity", V(receiver));
    check(get<bool>(restored.command("P", take_tray), "accepted"),
          "The original receiver is recovered without losing its material.");
    auto no_tray_turn = request("no-tray-turn", "turn_hand_crank");
    no_tray_turn.emplace("entity", V(remount));
    const auto incomplete = restored.command("P", no_tray_turn);
    check(!get<bool>(incomplete, "accepted") &&
          get<std::string>(incomplete, "reason") == "incomplete_assembly",
          "A driven mount without a receiver cannot debit ore.");
    const auto mirrored_tray = place(restored, "receiver_tray", 0, 0, -1, "mirrored-tray");
    const auto mirrored = ground_inspection(restored);
    check(get<std::string>(mirrored, "status") == "ready" &&
          get<std::string>(V(get<O>(mirrored, "parts")), "receiver") == mirrored_tray &&
          get<std::string>(V(get<O>(mirrored, "parts")), "shaft") == remount,
          "The same conserved input supports a mirrored receiver layout.");
    auto second_turn = request("second-layout-turn", "turn_hand_crank");
    second_turn.emplace("entity", V(remount));
    check(get<bool>(restored.command("P", second_turn), "accepted") &&
          get<I>(get<O>(restored.projection(), "hand_sources").at("opening-copper"), "remaining") == 4093,
          "The mirrored layout extracts from the same finite source.");
    check(get<bool>(restored.publish_actor("P", {V(5.8), V(1.0), V(-1.65)}, 8), "accepted"),
          "The actor reaches a second finite timber site for a competing receiver.");
    for (int index = 0; index < 2; ++index) {
        auto timber = request("alternate-timber-" + std::to_string(index), "harvest_source");
        timber.emplace("target", V("tree-east-upstream"));
        check(get<bool>(factory::godot_world::tests::complete_manual_cut(restored, "P", timber), "accepted"),
              "A second receiver uses two real timber pieces, not fixture stock.");
    }
    check(get<bool>(restored.publish_actor("P", {V(1.65), V(1.0), V(6.6)}, 9), "accepted"),
          "The actor returns to the pod bench with the additional timber.");
    auto extra_craft = request("alternate-tray-craft", "craft_component");
    extra_craft.emplace("entity", V("pod-fabrication-hub"));
    extra_craft.emplace("component", V("receiver_tray"));
    check(get<bool>(restored.command("P", extra_craft), "accepted") &&
          get<bool>(restored.publish_actor("P", {V(2.0), V(1.0), V(0.0)}, 10), "accepted"),
          "The actor fabricates the competing receiver from finite stock.");
    const auto extra_tray = place(restored, "receiver_tray", 0, 0, 1, "alternate-tray");
    check(get<std::string>(ground_inspection(restored), "status") == "ambiguous",
          "Two valid receiver routes cannot be selected silently.");
    auto ambiguous_turn = request("ambiguous-turn", "turn_hand_crank");
    ambiguous_turn.emplace("entity", V(remount));
    const auto ambiguous = restored.command("P", ambiguous_turn);
    check(!get<bool>(ambiguous, "accepted") &&
          get<std::string>(ambiguous, "reason") == "ambiguous_assembly" &&
          get<I>(get<O>(restored.projection(), "hand_sources").at("opening-copper"), "remaining") == 4093,
          "An ambiguous assembly refuses a turn without spending ore.");
    auto remove_extra = request("remove-extra-tray", "reclaim_component");
    remove_extra.emplace("entity", V(extra_tray));
    check(get<bool>(restored.command("P", remove_extra), "accepted") &&
          get<std::string>(ground_inspection(restored), "status") == "ready",
          "Removing the alternate route restores the unique valid collector.");
    auto take_mirrored_tray = request("take-mirrored-tray", "reclaim_component");
    take_mirrored_tray.emplace("entity", V(mirrored_tray));
    check(get<bool>(restored.command("P", take_mirrored_tray), "accepted"),
          "Dismantling a full receiver preserves its separately owned raw item.");
    auto recover_loose = request("pickup-after-dismantle", "pickup_material");
    recover_loose.emplace("center", V(A{V(I{0}), V(I{0}), V(I{-1})}));
    recover_loose.emplace("expected", V(O{{"raw", V(I{1})}, {"products", V(I{0})},
        {"work_lots", V(A{})}, {"offcuts", V(I{0})}, {"sheets", V(I{0})}}));
    check(get<bool>(restored.command("P", recover_loose), "accepted") &&
          get<I>(get<O>(restored.projection(), "cargo").at("P"), "raw") == 2,
          "The output remains recoverable after its collector tray is removed.");
    auto support_site = source_contact_site();
    auto support_obstacles = std::get<A>(support_site.at("obstacles").storage());
    support_obstacles.emplace_back(A{V(A{V(-0.55), V(0.05), V(-0.10)}),
                                     V(A{V(-0.35), V(0.25), V(0.10)})});
    support_site.at("obstacles") = V(std::move(support_obstacles));
    Host blocked_support;
    check(get<bool>(blocked_support.initialize_arrival("assembly-site", {"P", "Q"}), "accepted") &&
          get<bool>(blocked_support.configure_terrain(support_site), "accepted") &&
          get<bool>(blocked_support.restore_checkpoint(prepared_layout), "accepted"),
          "A fresh Host retains the prepared kit beside a distinct low obstruction.");
    check(get<bool>(blocked_support.publish_actor("P", {V(2.0), V(1.0), V(0.0)}, 1), "accepted"),
          "The restored actor supplies a fresh native cut before testing support clearance.");
    auto blocked_mount = request("blocked-mount-support", "place_component");
    blocked_mount.emplace("component", V("tool_mount"));
    blocked_mount.emplace("center", V(A{V(I{-1}), V(I{0}), V(I{0})}));
    const auto blocked_mount_result = blocked_support.command("P", blocked_mount);
    check(!get<bool>(blocked_mount_result, "accepted") &&
          get<std::string>(blocked_mount_result, "reason") == "site_occupied",
          "A floor-level obstruction refuses the installed mount's visible support volume.");
    Host upper_tools;
    check(get<bool>(upper_tools.initialize_arrival("assembly-site", {"P", "Q"}), "accepted") &&
          get<bool>(upper_tools.configure_terrain(source_contact_site()), "accepted") &&
          get<bool>(upper_tools.restore_checkpoint(prepared_layout), "accepted"),
          "A fresh Host retains the real crafted kit before a one-step raised cutter layout.");
    check(get<bool>(upper_tools.publish_actor("P", {V(2.0), V(1.0), V(0.0)}, 1), "accepted"),
          "The restored actor supplies a fresh native cut before building the raised layout.");
    place(upper_tools, "wooden_frame", 0, 0, 0, "upper-frame");
    const auto upper_mount = place(upper_tools, "tool_mount", -1, 1, 0, "upper-mount");
    const auto upper_edge = place(upper_tools, "cutting_edge", -2, 1, 0, "upper-edge");
    const auto upper_parts = get<O>(upper_tools.projection(), "placed_components");
    const auto upper_mount_box = get<O>(V(upper_parts.at(upper_mount)), "occupied");
    const auto upper_edge_box = get<O>(V(upper_parts.at(upper_edge)), "occupied");
    const auto upper_mount_center = get<A>(V(upper_mount_box), "center");
    const auto upper_mount_half = get<A>(V(upper_mount_box), "half");
    const auto upper_edge_center = get<A>(V(upper_edge_box), "center");
    const auto upper_edge_half = get<A>(V(upper_edge_box), "half");
    check(std::abs(component_face(upper_mount_center, upper_mount_half, 1, -1)) < 1e-9 &&
          std::abs(component_face(upper_edge_center, upper_edge_half, 1, -1)) < 1e-9 &&
          std::abs(component_face(upper_mount_center, upper_mount_half, 0, -1) -
              component_face(upper_edge_center, upper_edge_half, 0, 1)) < 1e-9,
          "A one-step raised cutter still has separately occupied supports down to its frame floor.");
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
