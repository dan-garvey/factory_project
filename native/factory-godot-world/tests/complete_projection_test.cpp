#include "native/factory-godot-world/src/arrival_configuration.hpp"
#include "native/factory-godot-world/src/complete_projection.hpp"
#include "native/factory-godot-world/tests/site_fixture.hpp"
#include "factory/projection_contract.hpp"
#include "factory/site_geometry_contract.hpp"

#include <iostream>
#include <stdexcept>
#include <string>
#include <variant>

namespace {
using Value = factory::values::Value;
using Object = Value::Object;
using Array = Value::Array;
using Integer = Value::Integer;
namespace view = factory::godot_world::complete_projection;
namespace world = factory::world;

int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

template<class T> const T& field(const Object& object, const char* name) {
    return std::get<T>(object.at(name).storage());
}

bool accepted(const Value& value) {
    return field<bool>(std::get<Object>(value.storage()), "accepted");
}

void complete_native_readout() {
    const auto arrival = factory::godot_world::make_arrival_configuration(
        true, false, {"P", "Q"});
    check(arrival.has_value(), "The ordinary two-worker arrival has a native profile and starting World.");
    const auto terrain_input = factory::godot_world::tests::flat_site();
    auto parsed = factory::godot_world::terrain_surface::parse(terrain_input, arrival->profile);
    check(parsed.binding.has_value(), "The same trusted flat terrain can bind to a direct native readout.");
    const auto& binding = *parsed.binding;
    auto native = world::World::create("complete-view", binding.profile, arrival->seed);
    check(native != nullptr, "The World accepts the authored arrival with that terrain profile.");

    factory::godot_world::Host host;
    check(accepted(host.initialize_arrival("complete-view", {"P", "Q"})) &&
          accepted(host.configure_terrain(terrain_input)),
          "The Host consumer starts from the identical authored profile and terrain.");
    view::Actors actors;
    for (const auto& [id, position] : arrival->actor_starts)
        actors.emplace(id, view::ActorObservation{position, 0, false});
    const auto initial = native->snapshot();
    const auto initial_view = view::build(binding.profile, initial, binding.surface, {}, actors);
    check(initial_view.has_value() &&
          factory::godot_world::projection_contract::complete(*initial_view) &&
          !factory::values::typed_difference(*initial_view, host.projection()) &&
          native->snapshot().state == initial.state,
          "One complete readout matches the Host exactly without changing native state.");
    const auto& initial_fields = std::get<Object>(initial_view->storage());
    const auto& initial_actors = field<Object>(initial_fields, "actors");
    const auto& deposit = field<Object>(initial_fields, "source_deposit");
    const auto& geometry = field<Object>(initial_fields, "adapter_profile");
    check(field<std::string>(deposit, "id") == binding.profile.material.manual_ore->id &&
          field<Integer>(deposit, "initial_units") == binding.profile.initial_units &&
          field<double>(geometry, "pitch") == factory::godot_world::site_geometry::pitch &&
          field<Object>(initial_fields, "foundations").size() == initial.state.foundations.size() &&
          initial_fields.contains("transmission_parts"),
          "The view exposes the authored copper source, site scale and native structures.");
    check(field<Object>(std::get<Object>(initial_actors.at("P").storage()), "harvest_clear").empty() &&
          field<Object>(std::get<Object>(initial_actors.at("Q").storage()), "harvest_clear").empty(),
          "Unready actors disclose no hand-source clearance before a trusted pose arrives.");

    const auto position = actors.at("P").position;
    check(accepted(host.publish_actor("P", Array{Value(position[0]), Value(position[1]),
          Value(position[2])}, 1)),
          "One trusted worker pose becomes ready without a separate actor store.");
    actors.at("P").epoch = 1;
    actors.at("P").ready = true;
    const auto ready_view = view::build(binding.profile, initial, binding.surface, {}, actors);
    check(ready_view.has_value() &&
          !factory::values::typed_difference(*ready_view, host.projection()),
          "The complete readout keeps ready actor reach and source visibility aligned with Host.");
    const auto& ready_actors = field<Object>(std::get<Object>(ready_view->storage()), "actors");
    const auto& ready_p = std::get<Object>(ready_actors.at("P").storage());
    const auto& ready_q = std::get<Object>(ready_actors.at("Q").storage());
    const auto direct_actor = host.actor_projection("P");
    const auto& direct_p = std::get<Object>(direct_actor.storage());
    check(field<bool>(ready_p, "ready") && field<Integer>(ready_p, "native_epoch") == 1 &&
          !field<bool>(ready_q, "ready") &&
          !field<Object>(ready_p, "harvest_clear").empty() &&
          field<Object>(ready_q, "harvest_clear").empty() &&
          !factory::values::typed_difference(ready_p.at("harvest_clear"),
              direct_p.at("harvest_clear")),
          "Full and direct actor views share the same native source-clearance values.");

    check(field<Object>(std::get<Object>(host.advance().storage()), "actors").size() == 2,
          "One real native tick retains both actor records.");
    const auto saved = std::get<Object>(host.checkpoint().storage());
    auto decoded = world::decode_checkpoint(binding.profile, "complete-view", saved.at("world"));
    check(std::holds_alternative<world::Snapshot>(decoded),
          "The World checkpoint yields the same post-tick state used by Host.");
    const auto& after = std::get<world::Snapshot>(decoded);
    const auto after_state = after.state;
    const auto after_view = view::build(binding.profile, after, binding.surface, {}, actors);
    check(after_view.has_value() &&
          !factory::values::typed_difference(*after_view, host.projection()) &&
          after.state == after_state &&
          field<Object>(std::get<Object>(after_view->storage()), "actors").size() == 2,
          "A later real World revision still projects exactly without a shadow simulation.");
}
}  // namespace

int main() {
    try {
        complete_native_readout();
        std::cout << "{\"status\":\"pass\",\"checks\":" << checks << "}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "{\"status\":\"fail\",\"reason\":\"" << error.what() << "\"}\n";
        return 1;
    }
}
