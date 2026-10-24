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
    const auto result = get<std::string>(V(wire), "action") == "harvest_source" ?
        factory::godot_world::tests::complete_manual_cut(host, "P", wire) : host.command("P", wire);
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

void drive_faces_meet(const O& placed, const std::string& first, const std::string& second) {
    const auto shaft_box = get<O>(V(placed.at(first)), "occupied");
    const auto cog_box = get<O>(V(placed.at(second)), "occupied");
    const auto shaft_center = get<A>(V(shaft_box), "center");
    const auto cog_center = get<A>(V(cog_box), "center");
    const auto shaft_half = get<A>(V(shaft_box), "half");
    const auto cog_half = get<A>(V(cog_box), "half");
    for (std::size_t axis : {std::size_t{0}, std::size_t{2}}) {
        const double distance = std::abs(std::get<double>(shaft_center[axis].storage()) -
                                         std::get<double>(cog_center[axis].storage()));
        if (distance < 1e-9) continue;
        check(std::abs(distance - std::get<double>(shaft_half[axis].storage()) -
                       std::get<double>(cog_half[axis].storage())) < 1e-9,
              "The separate press drive occupied faces meet on their common-grid axis.");
    }
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
        {"work_lots", V(A{})}, {"offcuts", V(I{0})}, {"sheets", V(I{0})}}));
    accepted(host, wire);
}

void recover_blank(Host& host, I x, I y, I z, const char* request_id) {
    auto wire = request(request_id, "pickup_material");
    wire.emplace("center", V(A{V(x), V(y), V(z)}));
    wire.emplace("expected", V(O{{"raw", V(I{1})}, {"products", V(I{0})},
        {"work_lots", V(A{})}, {"offcuts", V(I{0})}, {"sheets", V(I{0})}}));
    accepted(host, wire);
}

void pickup_offcut(Host& host, I x, I y, I z, const char* request_id) {
    auto wire = request(request_id, "pickup_material");
    wire.emplace("center", V(A{V(x), V(y), V(z)}));
    wire.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{0})},
        {"work_lots", V(A{})}, {"offcuts", V(I{1})}, {"sheets", V(I{0})}}));
    accepted(host, wire);
}

void conserved_copper(const Host& host) {
    const auto mass = get<O>(host.projection(), "material_mass");
    check(get<I>(V(mass), "accounted_mass") == 4096 * 4 &&
          get<I>(V(mass), "initial_mass") == 4096 * 4,
          "Every projected arrival holder accounts for the finite copper reserve.");
}

void guided_press_host_path() {
    Host host;
    check(get<bool>(host.initialize_arrival("press-site", {"P", "Q"}), "accepted") &&
          get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<A>(host.projection(), "guided_press_assemblies").empty(),
          "A fresh arrival has no guided press or gifted frame.");
    check(get<bool>(host.publish_actor("P", {V(5.8), V(1.0), V(3.3)}, 1), "accepted"),
          "The actor reaches finite timber for the five-part press.");
    for (int index = 0; index < 5; ++index) {
        auto cut = request("guided-wood-" + std::to_string(index), "harvest_source");
        cut.emplace("target", V("tree-east-south"));
        accepted(host, cut);
    }
    check(get<bool>(host.publish_actor("P", {V(-0.5), V(1.0), V(0.0)}, 2), "accepted"),
          "The actor reaches finite metal stock.");
    for (int index = 0; index < 5; ++index) {
        auto cut = request("guided-ore-" + std::to_string(index), "harvest_source");
        cut.emplace("target", V("opening-softmetal"));
        accepted(host, cut);
    }
    check(get<bool>(host.publish_actor("P", {V(1.65), V(1.0), V(6.6)}, 3), "accepted"),
          "The actor reaches the pod bench with guided-press parts and a temporary obstruction.");
    auto take = request("guided-take-crank", "take_hand_crank");
    take.emplace("entity", V("pod-hand-crank"));
    accepted(host, take);
    for (const auto* kind : {"anvil", "ram_face", "sliding_guide", "wooden_shaft", "wooden_cog",
                             "tool_mount"}) {
        auto craft = request(std::string("guided-craft-") + kind, "craft_component");
        craft.emplace("entity", V("pod-fabrication-hub"));
        craft.emplace("component", V(kind));
        accepted(host, craft);
    }
    check(get<bool>(host.publish_actor("P", {V(1.0), V(1.0), V(0.0)}, 4), "accepted"),
          "The actor reaches the selected workcell and its drive shaft.");
    const auto anvil = place(host, "anvil", 8, 0, 0, "guided-place-anvil");
    check(get<A>(host.projection(), "press_assemblies").empty() &&
          get<std::string>(get<A>(host.projection(), "guided_press_assemblies").front(), "status") ==
              "missing_ram",
          "An anvil is a guided candidate but does not masquerade as a framed press.");
    const auto ram = place(host, "ram_face", 8, 1, 0, "guided-place-ram");
    const auto guide = place(host, "sliding_guide", 8, 3, 0, "guided-place-guide");
    const auto placed_work = get<O>(host.projection(), "placed_components");
    const auto anvil_faces = vertical_faces(placed_work, anvil);
    const auto ram_faces = vertical_faces(placed_work, ram);
    check(std::abs(anvil_faces.second - 0.907) < 1e-9 &&
          std::abs(ram_faces.first - anvil_faces.second) < 1e-9,
          "The guided anvil and swept ram meet at the retained copper crown without overlapping.");
    const auto shaft = place(host, "wooden_shaft", 9, 4, 0, "guided-place-shaft");
    check(get<std::string>(get<A>(host.projection(), "guided_press_assemblies").front(), "status") ==
              "missing_cog", "A guided head still needs the actual drive cog.");
    check(!get<bool>(host.command("P", feed("guided-premature-feed", anvil, 9, 0, 0)),
              "accepted"), "An incomplete guided press refuses feed without consuming a blank.");
    Host shaft_first;
    check(get<bool>(shaft_first.initialize_arrival("press-site", {"P", "Q"}), "accepted") &&
          get<bool>(shaft_first.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(shaft_first.restore_checkpoint(host.checkpoint()), "accepted"),
          "The alternate construction order starts before the press cog is placed.");
    check(get<bool>(shaft_first.publish_actor("P", {V(5.8), V(1.0), V(3.3)}, 5), "accepted"),
          "The worker reaches finite timber for a transmission shaft.");
    auto early_wood = request("early-contact-wood", "harvest_source");
    early_wood.emplace("target", V("tree-east-south"));
    accepted(shaft_first, early_wood);
    check(get<bool>(shaft_first.publish_actor("P", {V(1.65), V(1.0), V(6.6)}, 6), "accepted"),
          "The worker reaches the original workshop to craft the shaft kit.");
    auto early_craft = request("early-contact-craft", "craft_part");
    early_craft.emplace("entity", V("pod-fabrication-hub"));
    early_craft.emplace("role", V("shaft"));
    early_craft.emplace("half_span", V(I{2}));
    accepted(shaft_first, early_craft);
    check(get<bool>(shaft_first.publish_actor("P", {V(2.0), V(1.0), V(0.0)}, 7), "accepted"),
          "The worker reaches the first press drive cell.");
    auto early_shaft = request("early-contact-place", "place_shaft");
    early_shaft.emplace("center", V(A{V(I{12}), V(I{4}), V(I{0})}));
    early_shaft.emplace("axis", V("x"));
    early_shaft.emplace("half_span", V(I{2}));
    const auto early_shaft_id = get<std::string>(accepted(shaft_first, early_shaft), "entity");
    const auto early_cog = place(shaft_first, "wooden_cog", 10, 4, 0,
        "early-contact-place-cog");
    const auto early_engagements = get<A>(shaft_first.projection(), "engagements");
    check(std::any_of(early_engagements.begin(), early_engagements.end(),
              [&](const V& edge) {
                  const auto first = get<std::string>(edge, "a");
                  const auto second = get<std::string>(edge, "b");
                  return (first == early_shaft_id && second == early_cog) ||
                      (second == early_shaft_id && first == early_cog);
              }) && get<bool>(shaft_first.validate_checkpoint(shaft_first.checkpoint()), "accepted"),
          "The cog can finish the same physical engagement after its shaft is placed first.");
    const auto cog = place(host, "wooden_cog", 10, 4, 0, "guided-place-cog");
    auto stroke_obstacle = request("guided-place-stroke-obstacle", "place_component");
    stroke_obstacle.emplace("component", V("tool_mount"));
    stroke_obstacle.emplace("center", V(A{V(I{8}), V(I{2}), V(I{0})}));
    const auto before_obstruction = host.projection();
    const auto refused_obstruction = host.command("P", stroke_obstacle);
    const auto after_obstruction = host.projection();
    check(!get<bool>(refused_obstruction, "accepted") &&
          get<std::string>(refused_obstruction, "reason") == "occupied" &&
          !factory::values::typed_difference(V(get<O>(before_obstruction, "cargo")),
              V(get<O>(after_obstruction, "cargo"))) &&
          !factory::values::typed_difference(V(get<O>(before_obstruction, "placed_components")),
              V(get<O>(after_obstruction, "placed_components"))) &&
          !factory::values::typed_difference(V(get<O>(before_obstruction, "material_mass")),
              V(get<O>(after_obstruction, "material_mass"))) &&
          get<std::string>(get<A>(after_obstruction, "guided_press_assemblies").front(),
              "status") == "ready",
          "Host records the physical refusal while retaining the same press and material custody.");
    const auto ready = get<A>(host.projection(), "guided_press_assemblies").front();
    const auto pieces = get<O>(ready, "parts");
    check(get<std::string>(ready, "status") == "ready" &&
          get<std::string>(ready, "anvil") == anvil &&
          get<std::string>(V(pieces), "anvil") == anvil &&
          get<std::string>(V(pieces), "ram") == ram &&
          get<std::string>(V(pieces), "guide") == guide &&
          get<std::string>(V(pieces), "shaft") == shaft &&
          get<std::string>(V(pieces), "drive_cog") == cog &&
          !pieces.contains("frame") && !pieces.contains("mount") &&
          get<A>(ready, "open_feeds").size() == 4,
          "The Host names exactly five issued working parts and four open feed directions.");
    Host contact;
    check(get<bool>(contact.initialize_arrival("press-site", {"P", "Q"}), "accepted") &&
          get<bool>(contact.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(contact.restore_checkpoint(host.checkpoint()), "accepted"),
          "The drive contact starts from the ordinary ready press, with no gifted shaft kit.");
    check(get<bool>(contact.publish_actor("P", {V(5.8), V(1.0), V(3.3)}, 5), "accepted"),
          "The worker reaches one more finite timber cut for the connecting shaft.");
    auto contact_wood = request("contact-wood", "harvest_source");
    contact_wood.emplace("target", V("tree-east-south"));
    accepted(contact, contact_wood);
    check(get<bool>(contact.publish_actor("P", {V(1.65), V(1.0), V(6.6)}, 6), "accepted"),
          "The worker returns to the ordinary workshop with the shaft bill.");
    auto craft_shaft = request("contact-craft-shaft", "craft_part");
    craft_shaft.emplace("entity", V("pod-fabrication-hub"));
    craft_shaft.emplace("role", V("shaft"));
    craft_shaft.emplace("half_span", V(I{2}));
    accepted(contact, craft_shaft);
    check(get<bool>(contact.publish_actor("P", {V(2.0), V(1.0), V(0.0)}, 7), "accepted"),
          "The worker reaches the press cog and its intended transmission cell.");
    auto connecting_shaft = request("contact-place-shaft", "place_shaft");
    connecting_shaft.emplace("center", V(A{V(I{12}), V(I{4}), V(I{0})}));
    connecting_shaft.emplace("axis", V("x"));
    connecting_shaft.emplace("half_span", V(I{2}));
    auto obstructed = connecting_shaft;
    obstructed.at("request") = V("contact-obstructed-shaft");
    obstructed.at("center") = V(A{V(I{8}), V(I{4}), V(I{0})});
    const auto before_contact = contact.projection();
    const auto obstructed_result = contact.command("P", obstructed);
    check(!get<bool>(obstructed_result, "accepted") &&
          get<std::string>(obstructed_result, "reason") == "occupied",
          "The mating-face allowance does not admit a shaft through the guide.");
    const auto after_refusal = contact.projection();
    check(!factory::values::typed_difference(
              V(get<O>(before_contact, "cargo")), V(get<O>(after_refusal, "cargo"))) &&
          !factory::values::typed_difference(
              V(get<O>(before_contact, "part_kits")), V(get<O>(after_refusal, "part_kits"))) &&
          !factory::values::typed_difference(
              V(get<O>(before_contact, "placed_components")),
              V(get<O>(after_refusal, "placed_components"))),
          "A refused guide collision preserves stock, kit and placed components.");
    const auto connecting_id = get<std::string>(accepted(contact, connecting_shaft), "entity");
    const auto engagements = get<A>(contact.projection(), "engagements");
    check(std::any_of(engagements.begin(), engagements.end(), [&](const V& edge) {
              const auto first = get<std::string>(edge, "a");
              const auto second = get<std::string>(edge, "b");
              return (first == connecting_id && second == cog) ||
                  (second == connecting_id && first == cog);
          }) && get<bool>(contact.validate_checkpoint(contact.checkpoint()), "accepted"),
          "The placed one-tile shaft engages the press cog and survives native validation.");
    Host with_tray;
    check(get<bool>(with_tray.initialize_arrival("press-site", {"P", "Q"}), "accepted") &&
          get<bool>(with_tray.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(with_tray.restore_checkpoint(host.checkpoint()), "accepted"),
          "A separate Host restores the same ready guided press before fitting its receiver.");
    check(get<bool>(with_tray.publish_actor("P", {V(5.8), V(1.0), V(3.3)}, 5), "accepted"),
          "The worker reaches the remaining finite timber for a receiver tray.");
    for (int index = 0; index < 2; ++index) {
        auto cut = request("guided-tray-wood-" + std::to_string(index), "harvest_source");
        cut.emplace("target", V("tree-east-south"));
        accepted(with_tray, cut);
    }
    check(get<bool>(with_tray.publish_actor("P", {V(1.65), V(1.0), V(6.6)}, 6), "accepted"),
          "The worker returns to the real workshop with the tray bill.");
    auto craft_tray = request("guided-craft-offcut-tray", "craft_component");
    craft_tray.emplace("entity", V("pod-fabrication-hub"));
    craft_tray.emplace("component", V("receiver_tray"));
    accepted(with_tray, craft_tray);
    check(get<bool>(with_tray.publish_actor("P", {V(1.0), V(1.0), V(0.0)}, 7), "accepted"),
          "The worker reaches the side discharge position.");
    place(with_tray, "receiver_tray", 8, 0, 1, "guided-place-offcut-tray");
    const auto routed = get<A>(with_tray.projection(), "guided_press_assemblies").front();
    check(get<std::string>(routed, "status") == "ready" &&
          !factory::values::typed_difference(V(get<A>(routed, "offcut_receiver")),
              V(A{V(I{8}), V(I{0}), V(I{1})})) &&
          get<I>(routed, "offcut_count") == 0 &&
          get<I>(routed, "offcut_capacity") == 4 &&
          get<A>(routed, "open_feeds").size() == 2,
          "Host projects the side receiver, finite capacity and two valid feed openings.");
    Host tray_reopened;
    const auto tray_saved = with_tray.checkpoint();
    check(get<bool>(tray_reopened.initialize_arrival("press-site", {"P", "Q"}), "accepted") &&
          get<bool>(tray_reopened.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(tray_reopened.restore_checkpoint(tray_saved), "accepted") &&
          !factory::values::typed_difference(tray_saved, tray_reopened.checkpoint()) &&
          !factory::values::typed_difference(
              V(get<A>(with_tray.projection(), "guided_press_assemblies")),
              V(get<A>(tray_reopened.projection(), "guided_press_assemblies"))),
          "The finite receiver remains projected after a fresh Host restores its placed parts.");
    accepted(host, feed("guided-feed", anvil, 9, 0, 0));
    check(!get<bool>(host.command("P", turn("guided-wrong-drive", anvil, cog, 7, 0, 0)),
              "accepted"), "A nearby cog cannot impersonate the guided press drive shaft.");
    for (int index = 0; index < 3; ++index)
        accepted(host, turn("guided-turn-" + std::to_string(index), anvil, shaft, 7, 0, 0));
    const auto drops = get<A>(host.projection(), "dropped_material");
    check(std::any_of(drops.begin(), drops.end(), [](const V& drop) {
              return !factory::values::typed_difference(V(get<A>(drop, "center")),
                  V(A{V(I{7}), V(I{0}), V(I{0})})) && get<I>(drop, "products") == 1;
          }) && std::any_of(drops.begin(), drops.end(), [](const V& drop) {
              return !factory::values::typed_difference(V(get<A>(drop, "center")),
                  V(A{V(I{8}), V(I{0}), V(I{0})})) && get<I>(drop, "offcuts") == 1;
          }), "The ordinary Host wire makes a real plate and retained offcut without a frame.");
    conserved_copper(host);
    const auto saved = host.checkpoint();
    Host restored;
    check(get<bool>(restored.initialize_arrival("press-site", {"P", "Q"}), "accepted") &&
          get<bool>(restored.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(restored.restore_checkpoint(saved), "accepted") &&
          !factory::values::typed_difference(saved, restored.checkpoint()) &&
          get<std::string>(get<A>(restored.projection(), "guided_press_assemblies").front(),
              "status") == "ready",
          "A fresh Host resumes the exact guided assembly and conserved copper worksite.");
    check(get<bool>(restored.publish_actor("P", {V(1.0), V(1.0), V(0.0)}, 5), "accepted"),
          "The restored worker resumes at the physical press before recovering its output.");
    for (int index = 0; index < 4; ++index) {
        if (index > 0) {
            check(get<bool>(restored.publish_actor("P", {V(-0.5), V(1.0), V(0.0)},
                    5 + index * 2 - 1), "accepted"),
                  "The worker returns to the finite ore deposit for another real blank.");
            auto harvest = request("guided-recycle-ore-" + std::to_string(index), "harvest_source");
            harvest.emplace("target", V("opening-softmetal"));
            accepted(restored, harvest);
            check(get<bool>(restored.publish_actor("P", {V(1.0), V(1.0), V(0.0)},
                    5 + index * 2), "accepted"),
                  "The worker brings that blank back within reach of the selected press.");
            accepted(restored, feed("guided-recycle-feed-" + std::to_string(index),
                                    anvil, 9, 0, 0));
            for (int tick = 0; tick < 3; ++tick)
                accepted(restored, turn("guided-recycle-turn-" + std::to_string(index) +
                    "-" + std::to_string(tick), anvil, shaft, 7, 0, 0));
        }
        pickup_offcut(restored, 8, 0, 0,
                      ("guided-recycle-offcut-" + std::to_string(index)).c_str());
        pickup_product(restored, 7, 0, 0,
                       ("guided-recycle-plate-" + std::to_string(index)).c_str());
    }
    conserved_copper(restored);
    check(get<I>(get<O>(restored.projection(), "cargo").at("P"), "offcuts") == 4 &&
          get<I>(get<O>(restored.projection(), "cargo").at("P"), "products") == 4,
          "Four physical guided strokes leave four recoverable plates and four offcuts.");
    auto compact = request("guided-compact", "compact_offcuts");
    compact.emplace("entity", V(anvil));
    compact.emplace("entry", V(A{V(I{9}), V(I{0}), V(I{0})}));
    compact.emplace("drive", V(shaft));
    auto wrong_drive = compact;
    wrong_drive.at("request") = V("guided-compact-wrong-drive");
    wrong_drive.at("drive") = V(cog);
    check(!get<bool>(restored.command("P", wrong_drive), "accepted") &&
          get<I>(get<O>(restored.projection(), "cargo").at("P"), "offcuts") == 4,
          "An unrelated cog cannot compact or consume the actor's offcuts.");
    const auto compact_result = accepted(restored, compact);
    const auto recycled_drops = get<A>(restored.projection(), "dropped_material");
    check(get<I>(compact_result, "moved_offcuts") == 4 &&
          get<I>(compact_result, "formed_raw") == 1 &&
          get<I>(get<O>(restored.projection(), "cargo").at("P"), "offcuts") == 0 &&
          std::any_of(recycled_drops.begin(), recycled_drops.end(), [](const V& drop) {
                  return get<I>(drop, "raw") == 1 &&
                      !factory::values::typed_difference(V(get<A>(drop, "center")),
                          V(A{V(I{8}), V(I{0}), V(I{0})}));
              }), "The ordinary Host wire places one recycled blank at the clear work face.");
    const auto compacted = restored.checkpoint();
    check(get<bool>(restored.command("P", compact), "duplicate") &&
          !factory::values::typed_difference(compacted, restored.checkpoint()),
          "An exact compacting retry does not duplicate the recycled blank.");
    Host fresh;
    check(get<bool>(fresh.initialize_arrival("press-site", {"P", "Q"}), "accepted") &&
          get<bool>(fresh.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(fresh.restore_checkpoint(compacted), "accepted") &&
          !factory::values::typed_difference(compacted, fresh.checkpoint()),
          "A fresh Host restores the exact recycled blank and custody receipt.");
    check(get<bool>(fresh.publish_actor("Q", {V(1.0), V(1.0), V(0.0)}, 1), "accepted"),
          "The second actor reaches the compacted blank through ordinary pose authority.");
    auto q_pickup = request("guided-q-recycled-blank", "pickup_material");
    q_pickup.at("client") = V("Q");
    q_pickup.emplace("center", V(A{V(I{8}), V(I{0}), V(I{0})}));
    q_pickup.emplace("expected", V(O{{"raw", V(I{1})}, {"products", V(I{0})},
        {"work_lots", V(A{})}, {"offcuts", V(I{0})}, {"sheets", V(I{0})}}));
    check(get<bool>(fresh.command("Q", q_pickup), "accepted") &&
          get<I>(get<O>(fresh.projection(), "cargo").at("Q"), "raw") == 1 &&
          get<I>(get<O>(fresh.projection(), "cargo").at("P"), "products") == 4,
          "A second actor physically recovers the saved blank without moving P's plates.");
    conserved_copper(fresh);
}

void placed_press_projection() {
    Host host;
    check(get<bool>(host.initialize_arrival("press-site", {"P", "Q"}), "accepted") &&
          get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<A>(host.projection(), "press_assemblies").empty(),
          "A fresh arrival has no gifted press assembly.");
    conserved_copper(host);
    check(get<bool>(host.publish_actor("P", {V(5.8), V(1.0), V(3.3)}, 1), "accepted"),
          "The actor approaches the finite timber site outside the pod deck.");
    for (int index = 0; index < 8; ++index) {
        auto cut = request("wood-" + std::to_string(index), "harvest_source");
        cut.emplace("target", V("tree-east-south"));
        accepted(host, cut);
    }
    check(get<bool>(host.publish_actor("P", {V(-0.5), V(1.0), V(0.0)}, 2), "accepted"),
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
    drive_faces_meet(placed, shaft, cog);
    drive_faces_meet(placed, mount, shaft);
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
    drive_faces_meet(get<O>(host.projection(), "placed_components"), mirrored_shaft, mirrored_cog);
    drive_faces_meet(get<O>(host.projection(), "placed_components"), mount, mirrored_shaft);
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
    Host resumed_work;
    check(get<bool>(resumed_work.initialize_arrival("press-site", {"P", "Q"}), "accepted") &&
          get<bool>(resumed_work.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(resumed_work.restore_checkpoint(pending), "accepted") &&
          get<bool>(resumed_work.publish_actor("P", {V(1.0), V(1.0), V(0.0)}, 5), "accepted"),
          "A fresh Host resumes the one-turn partial press work near its frame.");
    const auto held_drop = std::get<O>(get<A>(resumed_work.projection(), "dropped_material").front().storage());
    const auto held_lot = std::get<O>(get<A>(V(held_drop), "work_lots").front().storage());
    const auto held_id = get<I>(V(held_lot), "id");
    auto recover_work = request("recover-partial-work", "pickup_material");
    recover_work.emplace("center", held_drop.at("center"));
    recover_work.emplace("expected", V(O{{"raw", held_drop.at("raw")},
        {"products", held_drop.at("products")}, {"work_lots", held_drop.at("work_lots")},
        {"offcuts", held_drop.at("offcuts")}, {"sheets", held_drop.at("sheets")}}));
    accepted(resumed_work, recover_work);
    auto hand_refeed = request("hand-refeed-partial", "refeed_press_work");
    hand_refeed.emplace("entity", V(frame));
    hand_refeed.emplace("entry", V(A{V(I{9}), V(I{1}), V(I{0})}));
    hand_refeed.emplace("work_id", V(held_id));
    auto wrong_id = hand_refeed;
    wrong_id.at("request") = V("hand-refeed-wrong-id");
    wrong_id.at("work_id") = V(held_id + 1);
    const auto wrong_result = resumed_work.command("P", wrong_id);
    check(!get<bool>(wrong_result, "accepted") &&
          get<std::string>(wrong_result, "reason") == "unavailable_work",
          "The wire command rejects an uncarried WorkLot identity.");
    accepted(resumed_work, hand_refeed);
    const auto reinserted_work = resumed_work.checkpoint();
    check(get<bool>(resumed_work.command("P", hand_refeed), "duplicate") &&
          !factory::values::typed_difference(reinserted_work, resumed_work.checkpoint()) &&
          get<A>(get<O>(resumed_work.projection(), "cargo").at("P"), "work_lots").empty(),
          "Host hand refeed moves the exact partial lot once from actor custody into the press.");
    check(get<bool>(resumed_work.publish_actor("P", {V(-0.5), V(1.0), V(0.0)}, 6), "accepted"),
          "P walks to the ore deposit for a separate busy-feed control blank.");
    auto harvest_busy_blank = request("harvest-busy-control-blank", "harvest_source");
    harvest_busy_blank.emplace("target", V("opening-softmetal"));
    accepted(resumed_work, harvest_busy_blank);
    check(get<bool>(resumed_work.publish_actor("P", {V(1.0), V(1.0), V(0.0)}, 7), "accepted"),
          "P returns to the occupied press with one genuinely carried blank.");
    const auto busy_projection = resumed_work.projection();
    const auto busy_feed = resumed_work.command("P", feed("feed-occupied-reinserted-work", frame, 9, 1, 0));
    check(!get<bool>(busy_feed, "accepted") && get<std::string>(busy_feed, "reason") == "input_full" &&
          !factory::values::typed_difference(V(get<O>(busy_projection, "cargo")),
              V(get<O>(resumed_work.projection(), "cargo"))) &&
          !factory::values::typed_difference(V(get<A>(busy_projection, "dropped_material")),
              V(get<A>(resumed_work.projection(), "dropped_material"))),
          "A busy reinserted press cannot consume another carried blank.");
    Host restored_work;
    check(get<bool>(restored_work.initialize_arrival("press-site", {"P", "Q"}), "accepted") &&
          get<bool>(restored_work.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(restored_work.restore_checkpoint(reinserted_work), "accepted") &&
          get<bool>(restored_work.publish_actor("P", {V(1.0), V(1.0), V(0.0)}, 6), "accepted"),
          "Fresh Host restore retains the manually reinserted partial WorkLot.");
    accepted(restored_work, turn("advance-reinserted-work", frame, mirrored_shaft, 7, 1, 0));
    accepted(restored_work, turn("finish-reinserted-work", frame, mirrored_shaft, 7, 1, 0));
    pickup_product(restored_work, 7, 1, 0, "pickup-reinserted-product");
    check(get<I>(get<O>(restored_work.projection(), "cargo").at("P"), "products") == 1,
          "The recovered partial WorkLot produces one pickable plate after fresh Host restore.");
    Host final_work;
    check(get<bool>(final_work.initialize_arrival("press-site", {"P", "Q"}), "accepted") &&
          get<bool>(final_work.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(final_work.restore_checkpoint(restored_work.checkpoint()), "accepted") &&
          get<I>(get<O>(final_work.projection(), "cargo").at("P"), "products") == 1,
          "Fresh Host recovery preserves the finished plate in P's cargo.");
    accepted(host, turn("advance-mirrored-work", frame, mirrored_shaft, 7, 1, 0));
    accepted(host, turn("finish-mirrored-work", frame, mirrored_shaft, 7, 1, 0));
    const auto finished_drops = get<A>(host.projection(), "dropped_material");
    check(finished_drops.size() == 2 &&
          std::any_of(finished_drops.begin(), finished_drops.end(), [](const V& drop) {
              return get<I>(drop, "products") == 1;
          }) &&
          std::any_of(finished_drops.begin(), finished_drops.end(), [](const V& drop) {
              return get<I>(drop, "offcuts") == 1;
          }),
          "One plate exits while its one-unit copper offcut remains at the work point.");
    conserved_copper(host);
    pickup_product(host, 7, 1, 0, "pickup-mirrored-product");
    pickup_offcut(host, 8, 1, 0, "pickup-mirrored-offcut");
    check(get<I>(get<O>(host.projection(), "cargo").at("P"), "products") == 1,
          "The formed product enters the same actor cargo ledger after pickup.");
    check(get<I>(get<O>(host.projection(), "cargo").at("P"), "offcuts") == 1 &&
          get<A>(host.projection(), "dropped_material").empty(),
          "The distinct offcut is recoverable into actor custody without moving the plate again.");
    conserved_copper(host);
    const auto saved = host.checkpoint();
    auto hub_obstruction = factory::godot_world::tests::flat_site();
    hub_obstruction.at("obstacles") = V(A{V(A{
        V(A{V(2.64), V(2.45), V(-0.03)}),
        V(A{V(2.66), V(2.50), V(0.03)})})});
    Host obstructed_hub;
    check(get<bool>(obstructed_hub.initialize_arrival("press-site", {"P", "Q"}), "accepted") &&
          get<bool>(obstructed_hub.configure_terrain(hub_obstruction), "accepted") &&
          !get<bool>(obstructed_hub.restore_checkpoint(saved), "accepted"),
          "A solid in the newly occupied cog hub refuses the saved press instead of clipping its axle.");
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
    const auto workshop = raised_restored.projection();
    const auto completed = get<A>(workshop, "workshop_completed_actors");
    check(completed.size() == 1 && std::get<std::string>(completed.front().storage()) == "P" &&
          get<I>(get<O>(workshop, "cargo").at("P"), "products") == 2 &&
          get<I>(get<O>(workshop, "cargo").at("Q"), "products") == 0 &&
          !std::get<O>(workshop.storage()).contains("freight_beacon"),
          "P's collected plates complete only P's workshop without a shipment entity or debit.");
    const auto completed_saved = raised_restored.checkpoint();
    auto forged_world = get<O>(completed_saved, "world");
    auto forged_state = get<O>(V(forged_world), "state");
    forged_state.at("workshop_completed_actors") = V(A{});
    forged_world.at("state") = V(std::move(forged_state));
    auto forged_host = std::get<O>(completed_saved.storage());
    forged_host.at("world") = V(std::move(forged_world));
    check(!get<bool>(raised_restored.validate_checkpoint(V(std::move(forged_host))), "accepted"),
          "A checkpoint cannot erase P's witnessed first plate pickup.");
    Host completed_restored;
    check(get<bool>(completed_restored.initialize_arrival("press-site", {"P", "Q"}), "accepted") &&
          get<bool>(completed_restored.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(completed_restored.restore_checkpoint(completed_saved), "accepted") &&
          !factory::values::typed_difference(completed_saved, completed_restored.checkpoint()) &&
          get<A>(completed_restored.projection(), "workshop_completed_actors").size() == 1,
          "A fresh Host preserves P's local workshop completion and both carried plates.");
    auto retired_delivery = request("retired-first-delivery", "deliver_first_plate");
    retired_delivery.emplace("entity", V("first-freight-beacon"));
    const auto rejected = completed_restored.command("P", retired_delivery);
    check(!get<bool>(rejected, "accepted") &&
          get<std::string>(rejected, "reason") == "unsupported_action" &&
          get<I>(get<O>(completed_restored.projection(), "cargo").at("P"), "products") == 2,
          "The retired shipment command cannot remove either plate from inventory.");
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
    observe(-0.5, 0.0);
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
    V previous = host.projection();
    for (int n = 0; n < 32 && !fed; ++n) {
        const auto changes = host.advance_tick_fields();
        O merged = std::get<O>(previous.storage());
        for (const auto& [key, value] : std::get<O>(changes.storage()))
            merged.insert_or_assign(key, value);
        const auto full = host.projection();
        check(!factory::values::typed_difference(V(std::move(merged)), full),
              "A live modular belt and press tick must reconstruct the exact full Host view.");
        previous = full;
        const auto drops = get<A>(full, "dropped_material");
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
    pickup_product(fresh, -1, 5, 0, "inlet-host-first-plate-pickup");
    check(get<I>(get<O>(fresh.projection(), "cargo").at("P"), "products") == 1 &&
          get<A>(fresh.projection(), "workshop_completed_actors").size() == 1,
          "The actor first completes the workshop by collecting the formed plate.");
    check(get<bool>(fresh.publish_actor("P", {V(2.475), V(1.0), V(0.0)}, ++epoch), "accepted"),
          "The plate holder reaches the now-empty inlet belt slot.");
    auto load_plate = load;
    load_plate.at("request") = V("inlet-host-use-collected-plate");
    load_plate.at("item") = V("product");
    accepted(fresh, load_plate);
    const auto after_use = fresh.projection();
    check(get<I>(get<O>(after_use, "cargo").at("P"), "products") == 0 &&
          get<A>(after_use, "workshop_completed_actors").size() == 1 &&
          std::get<std::string>(get<A>(after_use, "workshop_completed_actors").front().storage()) == "P" &&
          get<I>(get<O>(after_use, "cargo").at("Q"), "products") == 0,
          "Using the only plate on a belt does not erase P's completed workshop or credit Q.");
    conserved_copper(fresh);
    const auto used_saved = fresh.checkpoint();
    Host used_restored;
    check(get<bool>(used_restored.initialize_arrival("press-site", {"P", "Q"}), "accepted") &&
          get<bool>(used_restored.configure_terrain(site), "accepted") &&
          get<bool>(used_restored.restore_checkpoint(used_saved), "accepted") &&
          get<A>(used_restored.projection(), "workshop_completed_actors").size() == 1 &&
          get<I>(get<O>(used_restored.projection(), "cargo").at("P"), "products") == 0,
          "P's completed goal survives a fresh Host restore after the plate leaves inventory.");
}
} // namespace

int main() {
    try {
        guided_press_host_path();
        placed_press_projection();
        belt_fed_press_projection();
        std::cout << "press_assembly_host_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "press_assembly_host_test: " << error.what() << '\n';
        return 1;
    }
}
