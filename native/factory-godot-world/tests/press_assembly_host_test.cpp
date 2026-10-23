#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <algorithm>
#include <cmath>
#include <iostream>
#include <stdexcept>
#include <string>
#include <tuple>
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
    return {{"context", V("press-site")}, {"client", V("P")},
        {"request", V(id)}, {"action", V(action)}};
}

V accepted(Host& host, const O& wire) {
    const auto result = host.command("P", wire);
    if (!get<bool>(result, "accepted"))
        throw std::runtime_error("Request " + get<std::string>(V(wire), "request") +
            " refused: " + get<std::string>(result, "reason"));
    ++checks;
    return result;
}

V inspection(const Host& host) {
    const auto presses = get<A>(host.projection(), "press_assemblies");
    check(presses.size() == 1, "Exactly the one installed frame is a press candidate.");
    return presses.front();
}

std::pair<double, double> vertical_faces(const O& placed, const std::string& id) {
    const auto occupied = get<O>(V(placed.at(id)), "occupied");
    const auto center = get<A>(V(occupied), "center");
    const auto half = get<A>(V(occupied), "half");
    const double y = std::get<double>(center[1].storage());
    const double extent = std::get<double>(half[1].storage());
    check(std::abs(std::get<double>(half[0].storage()) - 0.14) < 1e-9 &&
          std::abs(std::get<double>(half[2].storage()) - 0.14) < 1e-9,
          "Press fittings retain their narrow feed and exit clearance.");
    return {y - extent, y + extent};
}

std::string place(Host& host, const char* name, I x, I y, I z, const char* id) {
    auto wire = request(id, "place_component");
    wire.emplace("component", V(name));
    wire.emplace("center", V(A{V(x), V(y), V(z)}));
    return get<std::string>(accepted(host, wire), "entity");
}

void reclaim(Host& host, const std::string& id, const char* request_id) {
    auto wire = request(request_id, "reclaim_component");
    wire.emplace("entity", V(id));
    accepted(host, wire);
}

O feed(const std::string& request_id, const std::string& frame, I x, I y, I z) {
    auto wire = request(request_id, "feed_press");
    wire.emplace("entity", V(frame));
    wire.emplace("entry", V(A{V(x), V(y), V(z)}));
    return wire;
}

O turn(const std::string& request_id, const std::string& frame,
       const std::string& shaft, I x, I y, I z) {
    auto wire = request(request_id, "turn_press_crank");
    wire.emplace("entity", V(frame));
    wire.emplace("drive", V(shaft));
    wire.emplace("exit", V(A{V(x), V(y), V(z)}));
    return wire;
}

void pickup_product(Host& host, I x, I y, I z, const char* request_id) {
    auto wire = request(request_id, "pickup_material");
    wire.emplace("center", V(A{V(x), V(y), V(z)}));
    wire.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{1})},
        {"work_lots", V(A{})}}));
    accepted(host, wire);
}

void recover_blank(Host& host, I x, I y, I z, const char* request_id) {
    auto wire = request(request_id, "pickup_material");
    wire.emplace("center", V(A{V(x), V(y), V(z)}));
    wire.emplace("expected", V(O{{"raw", V(I{1})}, {"products", V(I{0})},
        {"work_lots", V(A{})}}));
    accepted(host, wire);
}

void placed_press_projection() {
    Host host;
    check(get<bool>(host.initialize_arrival("press-site", {"P", "Q"}), "accepted") &&
          get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<A>(host.projection(), "press_assemblies").empty(),
          "A fresh arrival has no gifted press assembly.");
    check(get<bool>(host.publish_actor("P", {V(3.3), V(1.0), V(4.95)}, 1), "accepted"),
          "The actor approaches the finite timber site outside the pod deck.");
    for (int index = 0; index < 8; ++index) {
        auto cut = request("wood-" + std::to_string(index), "harvest_source");
        cut.emplace("target", V("tree-east-south"));
        accepted(host, cut);
    }
    check(get<bool>(host.publish_actor("P", {V(0.0), V(1.0), V(1.65)}, 2), "accepted"),
          "The actor approaches the ore deposit.");
    for (int index = 0; index < 6; ++index) {
        auto cut = request("ore-" + std::to_string(index), "harvest_source");
        cut.emplace("target", V("opening-softmetal"));
        accepted(host, cut);
    }
    check(get<bool>(host.publish_actor("P", {V(1.65), V(1.0), V(6.6)}, 3), "accepted"),
          "The actor returns with the first press bill and two real feed blanks.");
    auto take = request("take-pod-crank", "take_hand_crank");
    take.emplace("entity", V("pod-hand-crank"));
    accepted(host, take);
    for (const auto* name : {"wooden_frame", "anvil", "ram_face", "sliding_guide",
                              "tool_mount", "wooden_shaft", "wooden_cog"}) {
        auto craft = request(std::string("craft-") + name, "craft_component");
        craft.emplace("entity", V("pod-fabrication-hub"));
        craft.emplace("component", V(name));
        accepted(host, craft);
    }
    check(get<bool>(host.publish_actor("P", {V(1.0), V(1.0), V(0.0)}, 4), "accepted"),
          "The actor approaches a distinct press workcell.");
    const auto frame = place(host, "wooden_frame", 8, 0, 0, "place-frame");
    check(get<std::string>(inspection(host), "status") == "missing_anvil",
          "A frame alone is not a press.");
    check(!std::get<O>(inspection(host).storage()).contains("parts"),
          "An incomplete frame has no ready component identities.");
    const auto anvil = place(host, "anvil", 8, 1, 0, "place-anvil");
    const auto ram = place(host, "ram_face", 8, 2, 0, "place-ram");
    const auto guide = place(host, "sliding_guide", 8, 3, 0, "place-guide");
    const auto mount = place(host, "tool_mount", 8, 4, 0, "place-mount");
    const auto shaft = place(host, "wooden_shaft", 9, 4, 0, "place-shaft");
    check(get<std::string>(inspection(host), "status") == "missing_cog",
          "A mounted ram still needs the actual drive cog.");
    const auto cog = place(host, "wooden_cog", 10, 4, 0, "place-cog");
    const auto ready = inspection(host);
    const auto parts = get<O>(ready, "parts");
    const auto feeds = get<A>(ready, "open_feeds");
    const auto placed = get<O>(host.projection(), "placed_components");
    const auto frame_box = get<O>(V(placed.at(frame)), "occupied");
    const auto frame_center = get<A>(V(frame_box), "center");
    const auto frame_half = get<A>(V(frame_box), "half");
    const double frame_top = std::get<double>(frame_center[1].storage()) +
        std::get<double>(frame_half[1].storage());
    const auto anvil_faces = vertical_faces(placed, anvil);
    const auto ram_faces = vertical_faces(placed, ram);
    const auto guide_faces = vertical_faces(placed, guide);
    const auto mount_box = get<O>(V(placed.at(mount)), "occupied");
    const auto mount_center = get<A>(V(mount_box), "center");
    const auto mount_half = get<A>(V(mount_box), "half");
    const double mount_bottom = std::get<double>(mount_center[1].storage()) -
        std::get<double>(mount_half[1].storage());
    check(std::abs(frame_top - anvil_faces.first) < 1e-9 &&
          std::abs(anvil_faces.second - ram_faces.first) < 1e-9 &&
          std::abs(ram_faces.second - guide_faces.first) < 1e-9 &&
          std::abs(guide_faces.second - mount_bottom) < 1e-9,
          "Seven separately owned press parts meet at physical frame, anvil, ram, guide and crown faces.");
    check(get<std::string>(ready, "status") == "ready" &&
          get<std::string>(V(parts), "frame") == frame &&
          get<std::string>(V(parts), "anvil") == anvil &&
          get<std::string>(V(parts), "ram") == ram &&
          get<std::string>(V(parts), "guide") == guide &&
          get<std::string>(V(parts), "mount") == mount &&
          get<std::string>(V(parts), "shaft") == shaft &&
          get<std::string>(V(parts), "drive_cog") == cog &&
          get<std::string>(ready, "shaft_material") == "wooden_shaft" &&
          get<std::string>(ready, "cog_material") == "wooden_cog" &&
          feeds.size() == 4 &&
          !factory::values::typed_difference(feeds.front(), V(O{
              {"entry", V(A{V(I{9}), V(I{1}), V(I{0})})},
              {"exit", V(A{V(I{7}), V(I{1}), V(I{0})})}})),
          "The Host names seven real placed identities and four clear feed directions.");
    const auto first_feed = feed("feed-lower", frame, 9, 1, 0);
    auto other_feed = first_feed;
    other_feed.at("client") = V("Q");
    other_feed.at("request") = V("feed-other-actor");
    check(get<bool>(host.publish_actor("Q", {V(2.0), V(1.0), V(0.0)}, 1), "accepted"),
          "The second actor observes the same press feed point.");
    const auto other_result = host.command("Q", other_feed);
    check(!get<bool>(other_result, "accepted") &&
          get<std::string>(other_result, "reason") == "unavailable_input",
          "A nearby second actor cannot spend P's carried blank.");
    check(get<bool>(accepted(host, first_feed), "accepted") &&
          get<A>(host.projection(), "dropped_material").size() == 1 &&
          get<I>(get<O>(host.projection(), "cargo").at("P"), "raw") == 1,
          "One real blank moves from actor cargo to the exact press work point.");
    const auto fed_checkpoint = host.checkpoint();
    check(get<bool>(host.command("P", first_feed), "duplicate") &&
          !factory::values::typed_difference(fed_checkpoint, host.checkpoint()),
          "An exact feed retry cannot create another blank.");
    auto full_feed = feed("feed-full", frame, 9, 1, 0);
    const auto full_result = host.command("P", full_feed);
    check(!get<bool>(full_result, "accepted") &&
          get<std::string>(full_result, "reason") == "input_full",
          "A second feed cannot overwrite the first blank in the work point.");
    reclaim(host, shaft, "remove-shaft");
    reclaim(host, cog, "remove-cog");
    check(get<std::string>(inspection(host), "status") == "missing_shaft",
          "Removing the drive immediately changes derived readiness.");
    recover_blank(host, 8, 1, 0, "recover-after-drive-removal");
    check(get<A>(host.projection(), "dropped_material").empty() &&
          get<I>(get<O>(host.projection(), "cargo").at("P"), "raw") == 2,
          "Dismantling does not erase work-point cargo; pickup returns the exact blank.");
    const auto mirrored_shaft = place(host, "wooden_shaft", 7, 4, 0, "mirror-shaft");
    const auto mirrored_cog = place(host, "wooden_cog", 6, 4, 0, "mirror-cog");
    const auto mirrored = inspection(host);
    const auto mirrored_parts = get<O>(mirrored, "parts");
    check(get<std::string>(mirrored, "status") == "ready" &&
          get<std::string>(V(mirrored_parts), "shaft") == mirrored_shaft &&
          get<std::string>(V(mirrored_parts), "drive_cog") == mirrored_cog &&
          !factory::values::typed_difference(V(get<A>(mirrored, "shaft_center")),
              V(A{V(I{7}), V(I{4}), V(I{0})})),
          "The same conserved pieces form a second real drive route.");
    accepted(host, feed("feed-mirrored", frame, 9, 1, 0));
    const auto mirrored_turn = turn("start-mirrored-work", frame, mirrored_shaft, 7, 1, 0);
    accepted(host, mirrored_turn);
    const auto pending = host.checkpoint();
    check(get<bool>(host.command("P", mirrored_turn), "duplicate") &&
          !factory::values::typed_difference(pending, host.checkpoint()),
          "A shared Host retry cannot advance the mirrored press twice.");
    accepted(host, turn("advance-mirrored-work", frame, mirrored_shaft, 7, 1, 0));
    accepted(host, turn("finish-mirrored-work", frame, mirrored_shaft, 7, 1, 0));
    check(get<A>(host.projection(), "dropped_material").size() == 1,
          "The alternate drive makes one real product at its chosen lower exit.");
    pickup_product(host, 7, 1, 0, "pickup-mirrored-product");
    check(get<I>(get<O>(host.projection(), "cargo").at("P"), "products") == 1,
          "The formed product enters the same actor cargo ledger after pickup.");
    const auto saved = host.checkpoint();
    Host restored;
    check(get<bool>(restored.initialize_arrival("press-site", {"P", "Q"}), "accepted") &&
          get<bool>(restored.configure_terrain(factory::godot_world::tests::flat_site()), "accepted"),
          "The fresh Host binds the same arrival site before restore.");
    const auto restored_result = restored.restore_checkpoint(saved);
    if (!get<bool>(restored_result, "accepted"))
        throw std::runtime_error("Mirrored press restore refused: " +
            get<std::string>(restored_result, "reason"));
    check(
          !factory::values::typed_difference(saved, restored.checkpoint()) &&
          !factory::values::typed_difference(mirrored, inspection(restored)),
          "Fresh Host restore derives the same press status and item identities.");
    auto obstructed_site = factory::godot_world::tests::flat_site();
    obstructed_site.at("obstacles") = V(A{V(A{
        V(A{V(3.63), V(1.15), V(-0.08)}),
        V(A{V(3.79), V(1.32), V(0.08)})})});
    Host obstructed;
    check(get<bool>(obstructed.initialize_arrival("press-site", {"P", "Q"}), "accepted") &&
          get<bool>(obstructed.configure_terrain(obstructed_site), "accepted") &&
          get<bool>(obstructed.restore_checkpoint(saved), "accepted"),
          "The saved press can load with a new obstacle limited to one feed mouth.");
    check(get<bool>(obstructed.publish_actor("P", {V(2.0), V(1.0), V(0.0)}, 100), "accepted"),
          "The restored actor provides a fresh physical observation for the new worksite.");
    const auto blocked_rock = obstructed.command("P", feed("blocked-rock", frame, 9, 1, 0));
    check(!get<bool>(blocked_rock, "accepted") &&
          get<std::string>(blocked_rock, "reason") == "site_occupied" &&
          get<A>(obstructed.projection(), "dropped_material").empty(),
          "A scenery obstacle at the chosen mouth refuses feed without losing stock.");
    accepted(obstructed, feed("alternate-clear-face", frame, 7, 1, 0));
    check(get<A>(obstructed.projection(), "dropped_material").size() == 1,
          "The same press remains usable from another physically clear face.");
    const auto rock_turn = obstructed.command("P", turn("blocked-rock-exit", frame, mirrored_shaft, 9, 1, 0));
    check(!get<bool>(rock_turn, "accepted") && get<std::string>(rock_turn, "reason") == "site_occupied" &&
          get<A>(obstructed.projection(), "dropped_material").size() == 1,
          "A scenery rock blocks product exit without destroying the fed blank.");
    for (const auto& [id, request_id] : {
             std::pair{mirrored_cog, "reclaim-mirrored-cog"},
             std::pair{mirrored_shaft, "reclaim-mirrored-shaft"},
             std::pair{mount, "reclaim-mount"},
             std::pair{guide, "reclaim-guide"},
             std::pair{ram, "reclaim-ram"},
             std::pair{anvil, "reclaim-anvil"},
             std::pair{frame, "reclaim-frame"}})
        reclaim(host, id, request_id);
    auto foundation = request("raised-press-floor", "place_foundation");
    foundation.emplace("cell", V(A{V(I{2}), V(I{0})}));
    foundation.emplace("level", V(I{4}));
    accepted(host, foundation);
    check(get<bool>(host.publish_actor("P", {V(2.0), V(1.0), V(0.0)}, 5), "accepted"),
          "The actor stands within reach of the raised press foundation.");
    place(host, "wooden_frame", 8, 4, 0, "raised-frame");
    place(host, "anvil", 8, 5, 0, "raised-anvil");
    place(host, "ram_face", 8, 6, 0, "raised-ram");
    place(host, "sliding_guide", 8, 7, 0, "raised-guide");
    place(host, "tool_mount", 8, 8, 0, "raised-mount");
    place(host, "wooden_shaft", 9, 8, 0, "raised-shaft");
    place(host, "wooden_cog", 10, 8, 0, "raised-cog");
    const auto raised = inspection(host);
    check(get<std::string>(raised, "status") == "ready" &&
          !factory::values::typed_difference(V(get<A>(raised, "center")),
              V(A{V(I{8}), V(I{4}), V(I{0})})) &&
          !factory::values::typed_difference(V(get<A>(raised, "work_center")),
              V(A{V(I{8}), V(I{5}), V(I{0})})),
          "Reclaimed parts rebuild a working-height candidate on an independently placed foundation.");
    const auto raised_frame = get<std::string>(raised, "frame");
    const auto raised_shaft = get<std::string>(V(get<O>(raised, "parts")), "shaft");
    accepted(host, feed("feed-raised", raised_frame, 9, 5, 0));
    check(get<A>(host.projection(), "dropped_material").size() == 1,
          "The elevated press accepts the same conserved feed rule.");
    const auto raised_saved = host.checkpoint();
    Host raised_restored;
    check(get<bool>(raised_restored.initialize_arrival("press-site", {"P", "Q"}), "accepted") &&
          get<bool>(raised_restored.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(raised_restored.restore_checkpoint(raised_saved), "accepted") &&
          !factory::values::typed_difference(raised, inspection(raised_restored)) &&
          !factory::values::typed_difference(raised_saved, raised_restored.checkpoint()),
          "The raised foundation and fed press cargo survive a fresh Host restore.");
    check(get<bool>(raised_restored.publish_actor("P", {V(2.0), V(1.0), V(0.0)}, 100), "accepted"),
          "The restored actor provides a fresh pose at the elevated press.");
    accepted(raised_restored, turn("start-raised-work", raised_frame, raised_shaft, 7, 5, 0));
    accepted(raised_restored, turn("advance-raised-work", raised_frame, raised_shaft, 7, 5, 0));
    accepted(raised_restored, turn("finish-raised-work", raised_frame, raised_shaft, 7, 5, 0));
    pickup_product(raised_restored, 7, 5, 0, "pickup-raised-product");
    check(get<I>(get<O>(raised_restored.projection(), "cargo").at("P"), "products") == 2,
          "The elevated arrangement forms and retrieves a second product from finite ore.");
    auto delivery = request("first-plate-delivery", "deliver_first_plate");
    delivery.emplace("entity", V("first-freight-beacon"));
    const auto distant = raised_restored.command("P", delivery);
    check(!get<bool>(distant, "accepted") && get<std::string>(distant, "reason") == "out_of_reach" &&
          get<I>(get<O>(raised_restored.projection(), "cargo").at("P"), "products") == 2,
          "The camera or a remote workcell cannot deliver a plate from outside actor reach.");
    check(get<bool>(raised_restored.publish_actor("Q", {V(9.9), V(1.0), V(6.6)}, 101), "accepted"),
          "A second actor can approach the one world-space beacon.");
    auto q_delivery = delivery;
    q_delivery.at("client") = V("Q");
    q_delivery.at("request") = V("empty-hand-delivery");
    const auto empty = raised_restored.command("Q", q_delivery);
    check(!get<bool>(empty, "accepted") && get<std::string>(empty, "reason") == "no_plate" &&
          !get<bool>(V(get<O>(raised_restored.projection(), "freight_beacon")), "order_complete"),
          "The nearby teammate cannot ship another actor's plate or complete the order empty handed.");
    check(get<bool>(raised_restored.publish_actor("P", {V(9.9), V(1.0), V(6.6)}, 102), "accepted"),
          "The plate holder reaches the freight receiver physically.");
    auto repeat_delivery = request("repeat-before-first", "deliver_repeat_plate");
    repeat_delivery.emplace("entity", V("first-freight-beacon"));
    const auto premature = raised_restored.command("P", repeat_delivery);
    check(!get<bool>(premature, "accepted") &&
          get<std::string>(premature, "reason") == "first_order_open" &&
          get<I>(get<O>(raised_restored.projection(), "cargo").at("P"), "products") == 2,
          "The later commission cannot consume a plate before the first shipment.");
    auto successful = delivery;
    successful.at("request") = V("ship-carried-plate");
    const auto sent = accepted(raised_restored, successful);
    check(get<I>(sent, "shipped_products") == 1 &&
          get<I>(get<O>(raised_restored.projection(), "cargo").at("P"), "products") == 1 &&
          get<bool>(V(get<O>(raised_restored.projection(), "freight_beacon")), "order_complete"),
          "Exactly one actually formed plate leaves P's cargo and completes the finite order.");
    const auto shipped_checkpoint = raised_restored.checkpoint();
    auto forged = get<O>(shipped_checkpoint, "world");
    auto forged_state = get<O>(V(forged), "state");
    auto forged_material = get<O>(V(forged_state), "material");
    forged_material.at("shipped_products") = V(I{0});
    forged_state.at("material") = V(std::move(forged_material));
    forged.at("state") = V(std::move(forged_state));
    auto forged_host = std::get<O>(shipped_checkpoint.storage());
    forged_host.at("world") = V(std::move(forged));
    check(!get<bool>(raised_restored.validate_checkpoint(V(std::move(forged_host))), "accepted"),
          "A checkpoint cannot erase the shipment receipt while the delivered plate has left cargo.");
    check(get<bool>(raised_restored.command("P", successful), "duplicate") &&
          !factory::values::typed_difference(shipped_checkpoint, raised_restored.checkpoint()),
          "A repeated delivery request returns its cached receipt without another debit.");
    auto second = delivery;
    second.at("request") = V("ship-again");
    const auto full = raised_restored.command("P", second);
    check(!get<bool>(full, "accepted") && get<std::string>(full, "reason") == "order_filled" &&
          get<I>(get<O>(raised_restored.projection(), "cargo").at("P"), "products") == 1,
          "A fresh request cannot spend the other plate after the first order is filled.");
    Host freight_restored;
    check(get<bool>(freight_restored.initialize_arrival("press-site", {"P", "Q"}), "accepted") &&
          get<bool>(freight_restored.configure_terrain(factory::godot_world::tests::flat_site()), "accepted"),
          "The fresh freight Host initializes its trusted site.");
    const auto freight_restore_result = freight_restored.restore_checkpoint(shipped_checkpoint);
    if (!get<bool>(freight_restore_result, "accepted"))
        throw std::runtime_error("Freight restore refused: " + get<std::string>(freight_restore_result, "reason"));
    check(
          get<bool>(V(get<O>(freight_restored.projection(), "freight_beacon")), "order_complete") &&
          get<I>(get<O>(freight_restored.projection(), "cargo").at("P"), "products") == 1,
          "A fresh shared Host and late join retain the same receipt and remaining product.");
    check(get<bool>(freight_restored.command("P", successful), "duplicate") &&
          !factory::values::typed_difference(shipped_checkpoint, freight_restored.checkpoint()),
          "The original successful request remains retry safe after checkpoint restore.");
    check(get<bool>(freight_restored.publish_actor("P", {V(9.9), V(1.0), V(6.6)}, 103), "accepted"),
          "The restored actor can approach the follow-up receiver.");
    repeat_delivery.at("request") = V("ship-repeat-two");
    const auto second_sent = accepted(freight_restored, repeat_delivery);
    const auto second_beacon = get<O>(freight_restored.projection(), "freight_beacon");
    check(get<I>(second_sent, "shipped_products") == 2 &&
          get<I>(V(second_beacon), "repeat_order_shipped") == 1 &&
          get<I>(V(second_beacon), "repeat_order_target") == 3 &&
          get<bool>(V(second_beacon), "order_complete") &&
          !get<bool>(V(second_beacon), "repeat_order_complete") &&
          get<I>(get<O>(freight_restored.projection(), "cargo").at("P"), "products") == 0,
          "The second physical plate starts a separate three-plate commission.");
    const auto repeat_checkpoint = freight_restored.checkpoint();
    check(get<bool>(freight_restored.command("P", repeat_delivery), "duplicate") &&
          !factory::values::typed_difference(repeat_checkpoint, freight_restored.checkpoint()),
          "A retried repeat shipment keeps the same one-plate debit.");
    auto forged_repeat = get<O>(repeat_checkpoint, "world");
    auto forged_repeat_state = get<O>(V(forged_repeat), "state");
    auto forged_repeat_material = get<O>(V(forged_repeat_state), "material");
    forged_repeat_material.at("shipped_products") = V(I{3});
    forged_repeat_state.at("material") = V(std::move(forged_repeat_material));
    forged_repeat.at("state") = V(std::move(forged_repeat_state));
    auto forged_repeat_host = std::get<O>(repeat_checkpoint.storage());
    forged_repeat_host.at("world") = V(std::move(forged_repeat));
    check(!get<bool>(freight_restored.validate_checkpoint(V(std::move(forged_repeat_host))), "accepted"),
          "The checkpoint cannot invent an extra follow-up shipment without its receipt.");
    Host repeat_restored;
    check(get<bool>(repeat_restored.initialize_arrival("press-site", {"P", "Q"}), "accepted") &&
          get<bool>(repeat_restored.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(repeat_restored.restore_checkpoint(repeat_checkpoint), "accepted") &&
          get<I>(V(get<O>(repeat_restored.projection(), "freight_beacon")), "repeat_order_shipped") == 1,
          "A fresh Host projects the same follow-up receipt to a late joining actor.");
    check(get<bool>(repeat_restored.publish_actor("Q", {V(9.9), V(1.0), V(6.6)}, 104), "accepted"),
          "A second actor approaches the shared follow-up receiver.");
    auto q_repeat = repeat_delivery;
    q_repeat.at("client") = V("Q");
    q_repeat.at("request") = V("empty-repeat-from-q");
    const auto q_empty = repeat_restored.command("Q", q_repeat);
    check(!get<bool>(q_empty, "accepted") && get<std::string>(q_empty, "reason") == "no_plate" &&
          get<I>(V(get<O>(repeat_restored.projection(), "freight_beacon")), "repeat_order_shipped") == 1,
          "A nearby teammate cannot ship a plate from another actor's empty cargo.");
    check(get<bool>(repeat_restored.publish_actor("P", {V(0.0), V(1.0), V(1.65)}, 105), "accepted"),
          "The worker returns to the finite ore deposit for two more blanks.");
    for (int index = 0; index < 2; ++index) {
        auto cut = request("repeat-ore-" + std::to_string(index), "harvest_source");
        cut.emplace("target", V("opening-softmetal"));
        accepted(repeat_restored, cut);
    }
    check(get<bool>(repeat_restored.publish_actor("P", {V(2.0), V(1.0), V(0.0)}, 106), "accepted"),
          "The worker reaches the same reconfigurable raised press.");
    for (int index = 0; index < 2; ++index) {
        const auto suffix = std::to_string(index);
        accepted(repeat_restored, feed("repeat-feed-" + suffix, raised_frame, 9, 5, 0));
        accepted(repeat_restored, turn("repeat-start-" + suffix, raised_frame, raised_shaft, 7, 5, 0));
        accepted(repeat_restored, turn("repeat-advance-" + suffix, raised_frame, raised_shaft, 7, 5, 0));
        accepted(repeat_restored, turn("repeat-finish-" + suffix, raised_frame, raised_shaft, 7, 5, 0));
        pickup_product(repeat_restored, 7, 5, 0, ("repeat-pickup-" + suffix).c_str());
    }
    check(get<I>(get<O>(repeat_restored.projection(), "cargo").at("P"), "products") == 2 &&
          get<I>(V(get<O>(repeat_restored.projection(), "freight_beacon")), "repeat_order_shipped") == 1,
          "Two further products are formed from actual local ore without changing the order receipt.");
    auto remote_repeat = repeat_delivery;
    remote_repeat.at("request") = V("remote-repeat");
    const auto remote = repeat_restored.command("P", remote_repeat);
    check(!get<bool>(remote, "accepted") && get<std::string>(remote, "reason") == "out_of_reach" &&
          get<I>(get<O>(repeat_restored.projection(), "cargo").at("P"), "products") == 2,
          "Remote delivery cannot spend the two new plates.");
    check(get<bool>(repeat_restored.publish_actor("P", {V(9.9), V(1.0), V(6.6)}, 107), "accepted"),
          "The worker carries both plates to the real freight beacon.");
    repeat_delivery.at("request") = V("ship-repeat-three");
    check(get<I>(accepted(repeat_restored, repeat_delivery), "shipped_products") == 3,
          "The third plate increments the physical shipment count once.");
    repeat_delivery.at("request") = V("ship-repeat-four");
    const auto fourth_sent = accepted(repeat_restored, repeat_delivery);
    const auto completed_beacon = get<O>(repeat_restored.projection(), "freight_beacon");
    check(get<I>(fourth_sent, "shipped_products") == 4 &&
          get<I>(V(completed_beacon), "repeat_order_shipped") == 3 &&
          get<bool>(V(completed_beacon), "repeat_order_complete") &&
          get<I>(get<O>(repeat_restored.projection(), "cargo").at("P"), "products") == 0,
          "The finite second commission closes after three further conserved plates.");
    const auto completed_repeat = repeat_restored.checkpoint();
    Host completed_restored;
    check(get<bool>(completed_restored.initialize_arrival("press-site", {"P", "Q"}), "accepted") &&
          get<bool>(completed_restored.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(completed_restored.restore_checkpoint(completed_repeat), "accepted") &&
          get<bool>(V(get<O>(completed_restored.projection(), "freight_beacon")), "repeat_order_complete"),
          "A fresh Host and late observer see the fully shipped second commission.");
    repeat_delivery.at("request") = V("ship-repeat-five");
    const auto overfill = repeat_restored.command("P", repeat_delivery);
    check(!get<bool>(overfill, "accepted") && get<std::string>(overfill, "reason") == "order_filled" &&
          get<I>(V(get<O>(repeat_restored.projection(), "freight_beacon")), "shipped_products") == 4 &&
          get<I>(get<O>(repeat_restored.projection(), "cargo").at("P"), "products") == 0,
          "A fifth fresh shipment refuses without changing the completed finite order.");
}

void belt_fed_press_projection() {
    A heights;
    for (int row = 0; row < 4; ++row) {
        heights.emplace_back(-0.02); heights.emplace_back(-0.02);
        heights.emplace_back(row < 2 ? -1.65 : -0.02);
        heights.emplace_back(row < 2 ? -1.65 : -0.02);
    }
    const O site{{"axis", V(A{V(-128.0), V(1.0), V(1.8), V(128.0)})},
        {"heights", V(std::move(heights))}, {"obstacles", V(A{})},
        {"water", V(A{V(A{V(I{8}), V(I{-8}), V(I{-20}), V(I{-400}), V(I{200}), V(I{0})})})}};
    Host host;
    check(get<bool>(host.initialize_arrival("press-site", {"P", "Q"}), "accepted"),
          "A detached arrival Host initializes its actual opening roster.");
    const auto configured = host.configure_terrain(site);
    if (!get<bool>(configured, "accepted"))
        throw std::runtime_error("Synthetic wet site refused: " + get<std::string>(configured, "reason"));
    check(get<bool>(configured, "accepted"),
          "A detached arrival Host binds a synthetic wet worksite for the physical inlet route.");
    I epoch{};
    const auto observe = [&](double x, double z) {
        check(get<bool>(host.publish_actor("P", {V(x), V(1.0), V(z)}, ++epoch), "accepted"),
              "The actor reports a physical pose before construction or harvest.");
    };
    observe(6.6, 3.3);
    for (int n = 0; n < 8; ++n) {
        auto cut = request("inlet-host-wood-south-" + std::to_string(n), "harvest_source");
        cut.emplace("target", V("tree-east-south"));
        accepted(host, cut);
    }
    observe(6.6, 11.55);
    for (int n = 0; n < 8; ++n) {
        auto cut = request("inlet-host-wood-north-" + std::to_string(n), "harvest_source");
        cut.emplace("target", V("tree-east-north"));
        accepted(host, cut);
    }
    observe(0, 1.65);
    for (int n = 0; n < 7; ++n) {
        auto cut = request("inlet-host-ore-" + std::to_string(n), "harvest_source");
        cut.emplace("target", V("opening-softmetal"));
        accepted(host, cut);
    }
    observe(1.65, 6.6);
    for (const auto* name : {"wooden_frame", "anvil", "ram_face", "sliding_guide",
                              "tool_mount", "wooden_shaft", "wooden_cog"}) {
        auto craft = request(std::string("inlet-host-craft-") + name, "craft_component");
        craft.emplace("entity", V("pod-fabrication-hub"));
        craft.emplace("component", V(name));
        accepted(host, craft);
    }
    for (const auto& [name, role, span] : {
             std::tuple{"shaft-a", "shaft", I{2}}, std::tuple{"shaft-b", "shaft", I{2}},
             std::tuple{"shaft-c", "shaft", I{2}}, std::tuple{"belt", "belt", I{0}},
             std::tuple{"wheel", "waterwheel", I{0}}}) {
        auto craft = request(std::string("inlet-host-fabricate-") + name, "craft_part");
        craft.emplace("entity", V("pod-fabrication-hub"));
        craft.emplace("role", V(role));
        craft.emplace("half_span", V(span));
        accepted(host, craft);
    }
    observe(1.4, 0);
    auto foundation = request("inlet-host-foundation", "place_foundation");
    foundation.emplace("cell", V(A{V(I{0}), V(I{0})}));
    foundation.emplace("level", V(I{4}));
    accepted(host, foundation);
    std::string frame;
    for (const auto& [name, center] : {
             std::pair{"wooden_frame", A{V(I{0}), V(I{4}), V(I{0})}},
             std::pair{"anvil", A{V(I{0}), V(I{5}), V(I{0})}},
             std::pair{"ram_face", A{V(I{0}), V(I{6}), V(I{0})}},
             std::pair{"sliding_guide", A{V(I{0}), V(I{7}), V(I{0})}},
             std::pair{"tool_mount", A{V(I{0}), V(I{8}), V(I{0})}},
             std::pair{"wooden_shaft", A{V(I{1}), V(I{8}), V(I{0})}},
             std::pair{"wooden_cog", A{V(I{2}), V(I{8}), V(I{0})}}}) {
        auto place = request(std::string("inlet-host-place-") + name, "place_component");
        place.emplace("component", V(name));
        place.emplace("center", V(center));
        const auto result = accepted(host, place);
        if (std::string(name) == "wooden_frame") frame = get<std::string>(result, "entity");
    }
    check(get<std::string>(inspection(host), "status") == "ready" &&
          get<std::string>(inspection(host), "frame") == frame,
          "The raised press is recognized from its seven placed parts before belt installation.");
    observe(3.3, 0);
    auto wheel = request("inlet-host-wheel", "place");
    wheel.emplace("kind", V("wheel"));
    wheel.emplace("cell", V(A{V(I{2}), V(I{-2})}));
    wheel.emplace("level", V(I{4}));
    wheel.emplace("axis", V("z"));
    const auto wheel_id = get<std::string>(accepted(host, wheel), "entity");
    std::string outside, mouth;
    for (const auto& [name, center] : {
             std::pair{"drive", A{V(I{8}), V(I{4}), V(I{-4})}},
             std::pair{"outside", A{V(I{8}), V(I{4}), V(I{0})}},
             std::pair{"mouth", A{V(I{4}), V(I{4}), V(I{0})}}}) {
        observe(std::get<I>(center[0].storage()) * 0.4125,
            std::get<I>(center[2].storage()) * 0.4125);
        auto shaft = request(std::string("inlet-host-shaft-") + name, "place_shaft");
        shaft.emplace("center", V(center));
        shaft.emplace("axis", V("z"));
        shaft.emplace("half_span", V(I{2}));
        const auto id = get<std::string>(accepted(host, shaft), "entity");
        if (std::string(name) == "outside") outside = id;
        if (std::string(name) == "mouth") mouth = id;
    }
    observe(2.475, 0);
    auto install = request("inlet-host-belt", "place_belt_span");
    install.emplace("from", V(outside));
    install.emplace("to", V(mouth));
    const auto belt = get<std::string>(accepted(host, install), "entity");
    check(get<I>(V(get<O>(host.projection(), "motion").at(wheel_id)), "numerator") != 0,
          "The placed wet wheel actually rotates the raised belt shafts.");
    auto load = request("inlet-host-load", "load_belt_slot");
    load.emplace("entity", V(belt));
    load.emplace("slot", V(I{0}));
    load.emplace("item", V("raw"));
    load.emplace("work_id", V(I{0}));
    accepted(host, load);
    bool fed = false;
    for (int n = 0; n < 32 && !fed; ++n) {
        (void)host.advance();
        const auto drops = get<A>(host.projection(), "dropped_material");
        fed = std::any_of(drops.begin(), drops.end(), [](const V& drop) {
            return !factory::values::typed_difference(V(get<A>(drop, "center")),
                V(A{V(I{0}), V(I{5}), V(I{0})})) && get<I>(drop, "raw") == 1;
        });
    }
    check(fed && get<A>(inspection(host), "open_feeds").size() == 4,
          "The detached Host projects the real powered belt blank at the raised press work point.");
    const auto saved = host.checkpoint();
    Host fresh;
    check(get<bool>(fresh.initialize_arrival("press-site", {"P", "Q"}), "accepted") &&
          get<bool>(fresh.configure_terrain(site), "accepted") &&
          get<bool>(fresh.restore_checkpoint(saved), "accepted") &&
          !factory::values::typed_difference(saved, fresh.checkpoint()),
          "A fresh Host restores the same belt-fed press work and physical site.");
    check(get<bool>(fresh.publish_actor("P", {V(1.65), V(1.0), V(6.6)}, ++epoch), "accepted"),
          "The actor returns to the pod for the manual press crank.");
    auto take = request("inlet-host-take-crank", "take_hand_crank");
    take.emplace("entity", V("pod-hand-crank"));
    accepted(fresh, take);
    check(get<bool>(fresh.publish_actor("P", {V(1.4), V(1.0), V(0.0)}, ++epoch), "accepted"),
          "The crank holder reaches the belt-fed raised press.");
    const auto press_shaft = get<std::string>(V(get<O>(inspection(fresh), "parts")), "shaft");
    for (int n = 0; n < 3; ++n)
        accepted(fresh, turn("inlet-host-turn-" + std::to_string(n), frame, press_shaft, -1, 5, 0));
    const auto products = get<A>(fresh.projection(), "dropped_material");
    check(std::any_of(products.begin(), products.end(), [](const V& drop) {
              return !factory::values::typed_difference(V(get<A>(drop, "center")),
                  V(A{V(I{-1}), V(I{5}), V(I{0})})) && get<I>(drop, "products") == 1;
          }) && get<bool>(fresh.validate_checkpoint(fresh.checkpoint()), "accepted"),
          "The restored belt-fed blank becomes one physical plate through the normal press crank.");
}
} // namespace

int main() {
    try {
        placed_press_projection();
        belt_fed_press_projection();
        std::cout << "press_assembly_host_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "press_assembly_host_test: " << error.what() << '\n';
        return 1;
    }
}
