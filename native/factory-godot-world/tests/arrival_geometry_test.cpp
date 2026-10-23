#include "factory/arrival_geometry.hpp"
#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <cmath>
#include <iostream>
#include <stdexcept>

namespace {
using V = factory::values::Value;
using O = V::Object;
using A = V::Array;
using I = V::Integer;
int checks{};

void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

void floor_and_custody_geometry() {
    using namespace factory;
    constexpr double step = 1.65 / 4;
    world::State state;
    state.landing_pod = world::LandingPod{"landing-pod", {4, 0, 16}, 1};
    state.fabrication_hub = world::FabricationHub{"pod-fabrication-hub", {8, 0, 16}, 1};
    const auto original = godot_world::arrival_geometry::supplied(state, step);
    check(original.size() == 20, "The deployed supplied meshes have one finite derived solid roster.");
    for (const auto& [id, solid] : original) {
        check(!id.empty() && solid.generation == 1, "Every body retains its native entity and generation.");
        for (std::size_t axis = 0; axis < 3; ++axis)
            check(std::isfinite(solid.bounds.center[axis]) && solid.bounds.half[axis] > 0,
                  "The emitted occupied boxes are finite and nonempty.");
    }
    check(original.at("landing-pod/foot-west-front").bounds.center[1] -
          original.at("landing-pod/foot-west-front").bounds.half[1] == 0,
          "The pod feet meet the foundation floor without the spindle offset.");
    const auto top = original.at("pod-fabrication-hub/worktop").bounds;
    check(std::abs(top.center[0] - 3.3) < 1e-12 && std::abs(top.center[1] - 0.74) < 1e-12,
          "The workshop top follows its separate east-deck floor anchor.");
    state.landing_pod->center[1] = -4;
    state.fabrication_hub->center[1] = -4;
    const auto lowered = godot_world::arrival_geometry::supplied(state, step);
    for (const auto& [id, solid] : lowered)
        check(std::abs(solid.bounds.center[1] - original.at(id).bounds.center[1] + 1.65) < 1e-12,
              "Independent supplied solids use the same negative common-grid elevation.");
    state.fabrication_hub->holder = "P";
    check(godot_world::arrival_geometry::supplied(state, step).size() == 10,
          "Stowing removes only the workshop solids.");
    state.fabrication_hub->holder.reset();
    state.fabrication_hub->center = {0, 4, 12};
    state.fabrication_hub->generation = 2;
    const auto moved = godot_world::arrival_geometry::supplied(state, step);
    check(moved.at("landing-pod/lower-hull").bounds.center == lowered.at("landing-pod/lower-hull").bounds.center,
          "Relocating the workshop never moves the fixed pod.");
    check(moved.at("pod-fabrication-hub/worktop").generation == 2 &&
          std::abs(moved.at("pod-fabrication-hub/worktop").bounds.center[1] - (1.65 + 0.74)) < 1e-12,
          "A relocated workshop retains native identity and the shared height unit.");
}

void actual_host_projection() {
    factory::godot_world::Host host;
    const auto initialized = std::get<O>(host.initialize_arrival("supplied-solids", {"P"}).storage());
    check(std::get<bool>(initialized.at("accepted").storage()), "Arrival initializes its native state.");
    const auto view = std::get<O>(host.projection().storage());
    check(view.contains("supplied_hardware_boxes"),
          "Native arrival must project the occupied hardware consumed by ActorWorld.");
    const auto& boxes = std::get<O>(view.at("supplied_hardware_boxes").storage());
    check(boxes.size() == 20, "The real Host projects the full deployed supplied roster.");
}

void construction_and_restore() {
    using Host = factory::godot_world::Host;
    Host host;
    const auto accepted = [](const V& result) {
        return std::get<bool>(std::get<O>(result.storage()).at("accepted").storage());
    };
    check(accepted(host.initialize_arrival("supplied-construction", {"P"})), "The native construction fixture initializes.");
    check(accepted(host.configure_terrain(factory::godot_world::tests::flat_site())), "Synthetic floor binds.");
    I epoch{};
    const auto pose = [&](double x, double z) {
        check(accepted(host.publish_actor("P", A{V(x), V(1.0), V(z)}, ++epoch)), "The synthetic actor cut publishes.");
    };
    int sequence{};
    const auto command = [&](const char* action, O extra) {
        extra.emplace("context", V("supplied-construction"));
        extra.emplace("client", V("P"));
        extra.emplace("request", V("solid-" + std::to_string(++sequence)));
        extra.emplace("action", V(action));
        return host.command("P", extra);
    };
    const auto material = [&]() {
        return std::get<O>(std::get<O>(std::get<O>(host.checkpoint().storage()).at("world").storage())
            .at("state").storage()).at("material");
    };
    pose(3.3, 4.8);
    const auto before_floor = material();
    const auto blocked_floor = command("place_foundation", {{"cell", V(A{V(I{1}), V(I{4})})}, {"level", V(I{2})}});
    check(!accepted(blocked_floor) && std::get<std::string>(std::get<O>(blocked_floor.storage()).at("reason").storage()) == "occupied",
          "A vertically adjoining foundation cannot bury the supplied pod hull.");
    check(!factory::values::typed_difference(before_floor, material()), "The occupied foundation refusal conserves all material.");
    check(accepted(command("place_foundation", {{"cell", V(A{V(I{4}), V(I{4})})}, {"level", V(I{0})}})),
          "Ordinary expansion away from the pod remains possible.");
    pose(6.6, 3.3);
    for (int count = 0; count < 3; ++count)
        check(accepted(command("harvest_source", {{"target", V("tree-east-south")}})),
              "The C++ fixture obtains finite timber through the native command.");
    pose(3.3, 4.8);
    check(accepted(command("craft_component", {{"entity", V("pod-fabrication-hub")}, {"component", V("wooden_frame")}})),
          "The fixture crafts one conserved component at the issued workshop.");
    const auto before_frame = material();
    const auto blocked_frame = command("place_component", {{"component", V("wooden_frame")},
        {"center", V(A{V(I{4}), V(I{0}), V(I{16})})}});
    check(!accepted(blocked_frame), "A crafted frame cannot occupy the pod pallet.");
    check(!factory::values::typed_difference(before_frame, material()), "The component refusal leaves its carried component intact.");
    check(accepted(command("place_component", {{"component", V("wooden_frame")},
        {"center", V(A{V(I{0}), V(I{0}), V(I{12})})}})), "A separate deck tile remains usable for the same component.");
    check(accepted(command("stow_fabrication_hub", {{"entity", V("pod-fabrication-hub")}})), "The issued workshop stows normally.");
    check(std::get<O>(std::get<O>(host.projection().storage()).at("supplied_hardware_boxes").storage()).size() == 10,
          "The actual native projection removes the carried workshop solids.");
    check(accepted(command("deploy_fabrication_hub", {{"entity", V("pod-fabrication-hub")},
        {"center", V(A{V(I{0}), V(I{0}), V(I{16})})}})), "The same workshop redeploys on an independent common-grid tile.");
    const auto saved = host.checkpoint();
    Host restored;
    check(accepted(restored.initialize_arrival("fresh-consumer", {"P"})), "The independent consumer initializes.");
    check(accepted(restored.configure_terrain(factory::godot_world::tests::flat_site())), "The consumer binds the same synthetic site.");
    check(accepted(restored.restore_checkpoint(saved)), "A fresh native owner restores the clear saved actor and relocated workshop.");
    const auto restored_view = std::get<O>(restored.projection().storage());
    check(!factory::values::typed_difference(std::get<O>(host.projection().storage()).at("supplied_hardware_boxes"),
          restored_view.at("supplied_hardware_boxes")), "Restoration derives the same occupied geometry without storing another model.");
    auto obstructed = std::get<O>(saved.storage());
    auto obstructed_actors = std::get<O>(obstructed.at("actors").storage());
    obstructed_actors.at("P") = V(A{V(0.0), V(0.9), V(6.6)});
    obstructed.insert_or_assign("actors", V(std::move(obstructed_actors)));
    Host blocked;
    check(accepted(blocked.initialize_arrival("refusal-consumer", {"P"})), "The refusal consumer starts fresh.");
    check(accepted(blocked.configure_terrain(factory::godot_world::tests::flat_site())), "The refusal consumer binds terrain.");
    const auto unchanged = blocked.checkpoint();
    const auto refused = blocked.restore_checkpoint(V(obstructed));
    check(!accepted(refused) && std::get<std::string>(std::get<O>(refused.storage()).at("reason").storage()) == "actor_inside_supplied_hardware",
          "An actor seed inside the workshop is refused rather than grandfathered.");
    check(!factory::values::typed_difference(unchanged, blocked.checkpoint()), "A refused physical restore preserves the original owner.");
}
}

int main() {
    try {
        floor_and_custody_geometry();
        actual_host_projection();
        construction_and_restore();
        std::cout << "ARRIVAL_GEOMETRY_PASS " << checks << '\n';
    } catch (const std::exception& error) {
        std::cerr << "ARRIVAL_GEOMETRY_FAIL after " << checks << " checks: " << error.what() << '\n';
        return 1;
    }
}
