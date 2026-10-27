#include "native/factory-godot-world/src/arrival_configuration.hpp"
#include "native/factory-godot-world/src/restore_site_validation.hpp"
#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <iostream>
#include <stdexcept>
#include <string_view>

namespace {
namespace native = factory::godot_world;
namespace restore = native::restore_site_validation;
namespace support = native::physical_support;
namespace world = factory::world;
using factory::mechanics::Axis;
using factory::mechanics::Kind;
using factory::stationary::Role;

int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

bool reason_is(const char* actual, std::string_view expected) {
    return actual && std::string_view(actual) == expected;
}

void restored_geometry() {
    const auto authored = native::make_arrival_configuration(false, false, {"P"});
    check(authored.has_value(), "The ordinary single-worker site has an authored native start.");
    const auto parsed = native::terrain_surface::parse(native::tests::flat_site(), authored->profile);
    check(parsed.binding.has_value(), "The same emitted flat terrain binds the native profile.");
    const auto& binding = *parsed.binding;
    auto actual = world::World::create("restored-physical-site", binding.profile, authored->seed);
    check(actual != nullptr, "A real World accepts the authored starting state.");
    const auto unchanged = actual->snapshot().state;
    const auto site = native::physical_site::Site{binding.profile, binding.surface};
    const auto validate = [&](const world::State& state, const support::Routes* routes = nullptr) {
        const auto supported = support::layout(native::physical_site::support_site(site), state, routes);
        return restore::geometry(binding.profile, binding.surface, state, supported, routes);
    };
    check(validate(unchanged) == nullptr && actual->snapshot().state == unchanged,
          "The authored starting site restores without changing its World state.");

    auto changed = unchanged;
    changed.topology.parts.push_back({{"shaft-a", Kind::shaft, {0, 4, 0}, Axis::x, 0, 3},
        1, Role::shaft});
    check(reason_is(validate(changed), "incompatible_geometry"),
          "A saved shaft with the wrong physical span is incompatible.");
    changed.topology.parts.front().geometry.half_span = 2;
    const auto supported = support::layout(native::physical_site::support_site(site), changed);
    check(supported.size() == 1 && supported.contains("shaft-a"),
          "One actual shaft has one selected native support route.");
    check(reason_is(restore::geometry(binding.profile, binding.surface, changed, {}, nullptr),
          "support_required"), "A restored shaft cannot silently lose its physical support.");
    const support::Routes saved{{"shaft-a", supported.at("shaft-a").route}};
    check(restore::geometry(binding.profile, binding.surface, changed, supported, &saved) == nullptr,
          "A saved native support route accepts the unchanged shaft and terrain.");
    const support::Routes wrong{{"shaft-a", supported.at("shaft-a").route + 1}};
    check(reason_is(restore::geometry(binding.profile, binding.surface, changed,
          supported, &wrong), "invalid_support_route"),
          "A saved route cannot be silently substituted by another layout.");
    const support::Routes empty_routes;
    check(reason_is(restore::geometry(binding.profile, binding.surface, changed,
          supported, &empty_routes), "invalid_support_route"),
          "A schema-four save must name every supported native part.");

    changed.topology.parts.front().geometry.kind = Kind::gear;
    changed.topology.parts.front().geometry.half_span = 0;
    changed.topology.parts.front().geometry.teeth = 3;
    changed.topology.parts.front().role = Role::gear;
    check(reason_is(validate(changed), "incompatible_geometry"),
          "A saved gear outside the accepted tooth sizes is incompatible.");
    changed = unchanged;
    changed.topology.belt_spans.push_back({{"orphan-belt", "missing-a", "missing-b"}, 1});
    check(reason_is(validate(changed), "invalid_belt_geometry"),
          "A saved belt cannot invent missing shaft endpoints.");
    check(actual->snapshot().state == unchanged,
          "Rejected readouts never mutate the actual native World.");
}
}  // namespace

int main() {
    try {
        restored_geometry();
        std::cout << "{\"status\":\"pass\",\"checks\":" << checks << "}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "{\"status\":\"fail\",\"reason\":\"" << error.what() << "\"}\n";
        return 1;
    }
}
