#include "native/factory-godot-world/tests/site_fixture.hpp"

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
    check(get<bool>(host.publish_actor("P", {V(1.65), V(1.0), V(6.6)}, 1), "accepted"),
          "The actor is near the finite timber site.");
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
    recover_blank(host, 8, 1, 0, "recover-mirrored");
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
}
} // namespace

int main() {
    try {
        placed_press_projection();
        std::cout << "press_assembly_host_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "press_assembly_host_test: " << error.what() << '\n';
        return 1;
    }
}
