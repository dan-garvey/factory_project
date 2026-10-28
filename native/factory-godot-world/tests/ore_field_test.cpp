#include "factory/checkpoint.hpp"
#include "factory/godot_world.hpp"
#include "factory/mineral_site.hpp"
#include "native/factory-godot-world/src/arrival_configuration.hpp"
#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <cmath>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {
namespace a = factory::authority;
namespace m = factory::mineral_site;
namespace w = factory::world;
using V = factory::values::Value;
using I = V::Integer;
int checks{};

void check(bool value, const char* message) {
    ++checks;
    if (!value) throw std::runtime_error(message);
}

I source(const w::World& world) { return world.snapshot().state.material.stock.source; }

w::ObserveActor standing(const w::Profile& profile, const std::string& target) {
    a::Point point{};
    if (const auto region = w::ore_region_index(profile, target)) {
        const auto bounds = w::ore_region_contact_bounds(profile, *region);
        point = {(bounds->first[0] + bounds->second[0]) / 2,
            (bounds->first[1] + bounds->second[1]) / 2,
            (bounds->first[2] + bounds->second[2]) / 2};
    } else {
        const auto& center = profile.material.manual_ore->center;
        point = {center[0] * profile.meters_per_grid_unit + profile.anchor_offset[0],
            profile.anchor_offset[1],
            center[2] * profile.meters_per_grid_unit + profile.anchor_offset[2]};
    }
    return [point](const std::string& actor) -> std::optional<a::ActorCut> {
        return a::ActorCut{actor, point, 1, true, 3.0};
    };
}

void cut(w::World& world, const w::Profile& profile, const std::string& target,
        const std::string& request, const std::string& context) {
    const a::Object wire{{"context", V(context)}, {"client", V("field-client")},
        {"request", V(request)}, {"actor", V("P")},
        {"action", V("harvest_source")}, {"target", V(target)}};
    const auto observe = standing(profile, target);
    const auto started = world.command({"P", "field-client"}, wire, observe);
    check(started.completed() && started.result &&
        std::get<bool>(started.result->at("accepted").storage()),
        "The region cut starts at its native contact.");
    for (I tick = 0; tick < w::manual_cut_ticks; ++tick)
        check(world.tick(observe).error == w::TransactionError::none,
            "The native clock advances a held region cut.");
    auto finish = wire;
    finish.erase("target");
    finish.at("action") = V("finish_harvest");
    finish.at("request") = V(request + "-finish");
    const auto result = world.command({"P", "field-client"}, finish, observe);
    check(result.completed() && result.result &&
        std::get<bool>(result.result->at("accepted").storage()),
        "A region cut finishes through the native timed hand-harvest path.");
}

void field_cuts_and_checkpoint() {
    auto content = factory::godot_world::make_arrival_configuration(true, false, {"P"});
    check(content.has_value() && content->profile.ore_field && content->seed.ore_field,
        "Arrival seeds one finite field in the native World.");
    auto& profile = content->profile;
    auto world = w::World::create("ore-field", profile, content->seed);
    check(world != nullptr, "The ten by ten arrival field validates.");
    const auto first = w::ore_region_id(profile, 0);
    const auto other = w::ore_region_id(profile, 5);
    const auto initial = *content->seed.ore_field;
    cut(*world, profile, first, "first", "ore-field");
    check(source(*world) == m::opening_reserve - 1 &&
        world->snapshot().state.ore_field->remaining[0] == initial.remaining[0] - 1 &&
        world->snapshot().state.ore_field->remaining[5] == initial.remaining[5],
        "The first cut debits exactly its addressed region and the aggregate once.");
    cut(*world, profile, other, "other", "ore-field");
    check(source(*world) == m::opening_reserve - 2 &&
        world->snapshot().state.ore_field->remaining[0] == initial.remaining[0] - 1 &&
        world->snapshot().state.ore_field->remaining[5] == initial.remaining[5] - 1,
        "A second cut at distant ground leaves the first region unchanged.");
    const auto saved = w::encode_checkpoint(profile, world->snapshot());
    check(std::holds_alternative<V>(saved), "Local ore stock encodes in a native checkpoint.");
    const auto& checkpoint = std::get<V>(saved);
    const auto& root = std::get<V::Object>(checkpoint.storage());
    check(std::get<I>(root.at("schema").storage()) == 23,
        "Field checkpoints carry the new stock schema.");
    const auto decoded = w::decode_checkpoint(profile, "ore-field", checkpoint);
    check(std::holds_alternative<w::Snapshot>(decoded) &&
        std::get<w::Snapshot>(decoded).state.ore_field == world->snapshot().state.ore_field,
        "Save and rejoin preserve each exact local balance.");
    auto corrupt = root;
    auto state = std::get<V::Object>(corrupt.at("state").storage());
    auto regions = std::get<V::Array>(state.at("ore_regions").storage());
    regions[0] = V(std::get<I>(regions[0].storage()) + 1);
    state.at("ore_regions") = V(std::move(regions));
    corrupt.at("state") = V(std::move(state));
    check(std::holds_alternative<w::CheckpointRefusal>(
        w::decode_checkpoint(profile, "ore-field", V(std::move(corrupt)))),
        "A checkpoint cannot mint a unit by editing one region.");
}

void pooled_save_transition() {
    auto content = factory::godot_world::make_arrival_configuration(true, false, {"P"});
    auto legacy = content->profile;
    legacy.ore_field = false;
    legacy.collector_faces.clear();
    for (const auto& cell : m::opening_cells)
        for (I level = 0; level <= m::extraction_depth_steps; level += 4)
            legacy.collector_faces.push_back({{4 * cell.x, level, 4 * cell.z}, {-1, 0, 0}});
    auto state = content->seed;
    state.ore_field.reset();
    auto old_world = w::World::create("pooled-save", legacy, state);
    check(old_world != nullptr, "The previous pooled opening profile is a valid migration source.");
    cut(*old_world, legacy, legacy.material.manual_ore->id, "legacy-cut", "pooled-save");
    const auto old_save = w::encode_checkpoint(legacy, old_world->snapshot());
    check(std::holds_alternative<V>(old_save), "The previous checkpoint schema remains readable.");
    const auto migrated = w::decode_checkpoint(content->profile, "pooled-save", std::get<V>(old_save));
    check(std::holds_alternative<w::Snapshot>(migrated),
        "A pooled save with hand-cut history transitions to the field profile.");
    const auto& snapshot = std::get<w::Snapshot>(migrated);
    check(snapshot.state.ore_field == m::allocate_field(m::opening_reserve - 1) &&
        source(*old_world) == m::field_total(*snapshot.state.ore_field),
        "Migration conserves all remaining units with a deterministic local split.");
}

void host_region_route() {
    factory::godot_world::Host host;
    const auto accepted = [](const V& value) {
        return std::get<bool>(std::get<V::Object>(value.storage()).at("accepted").storage());
    };
    check(accepted(host.initialize_arrival("host-field", {"P"})) &&
        accepted(host.configure_terrain(factory::godot_world::tests::flat_site())),
        "The field binds to the actual native Host terrain adapter.");
    const auto region = std::string("opening-copper-region-0");
    const auto before = std::get<V::Object>(host.projection().storage());
    const auto& sources = std::get<V::Object>(before.at("hand_sources").storage());
    const auto& source_view = std::get<V::Object>(sources.at(region).storage());
    const auto& position = std::get<V::Array>(source_view.at("position").storage());
    const auto& contact = std::get<V::Array>(source_view.at("contact_bounds").storage());
    const auto& low = std::get<V::Array>(contact[0].storage());
    const auto& high = std::get<V::Array>(contact[1].storage());
    check(std::abs(std::get<double>(high[0].storage()) -
            std::get<double>(low[0].storage()) - 1.10) < 1e-9 &&
        std::abs(std::get<double>(high[1].storage()) -
            std::get<double>(low[1].storage()) - 0.20) < 1e-9,
        "The Host projects a compact terrain-bound exposure, not an entire region as hand contact.");
    const auto& deposit = std::get<V::Object>(before.at("source_deposit").storage());
    check(std::get<V::Array>(deposit.at("cells").storage()).size() == 100 &&
        std::get<V::Array>(deposit.at("cell_regions").storage()).size() == 100,
        "Each field cell carries its native region address for scene presentation.");
    check(accepted(host.publish_actor("P", {position[0], V(1.0), position[2]}, 1)),
        "An actor can stand near a distant projected region.");
    const V::Object wire{{"context", V("host-field")}, {"client", V("P")},
        {"request", V("host-region-cut")}, {"action", V("harvest_source")},
        {"target", V(region)}};
    check(accepted(host.command("P", wire)),
        "A Host hand cut selects the projected region through physical path admission.");
    for (I tick = 0; tick < w::manual_cut_ticks; ++tick)
        check(std::get<V::Object>(host.advance().storage()).contains("revision"),
            "The Host settles a timed field cut on the native clock.");
    const auto after = std::get<V::Object>(host.projection().storage());
    const auto& after_sources = std::get<V::Object>(after.at("hand_sources").storage());
    check(std::get<I>(std::get<V::Object>(after_sources.at(region).storage()).at("remaining").storage()) ==
        std::get<I>(source_view.at("remaining").storage()) - 1 &&
        std::get<I>(std::get<V::Object>(after.at("stock").storage()).at("source").storage()) ==
            m::opening_reserve - 1,
        "The Host projection reports one regional and aggregate unit removed.");
    factory::godot_world::Host restored;
    check(accepted(restored.initialize_arrival("host-field", {"P"})) &&
        accepted(restored.configure_terrain(factory::godot_world::tests::flat_site())) &&
        accepted(restored.restore_checkpoint(host.checkpoint())),
        "A fresh Host restores local depletion for a shared rejoin.");
    const auto resumed = std::get<V::Object>(restored.projection().storage());
    check(!factory::values::typed_difference(after.at("hand_sources"), resumed.at("hand_sources")) &&
        !factory::values::typed_difference(after.at("stock"), resumed.at("stock")),
        "The restored Host projects the same region balances and aggregate stock.");
}
}  // namespace

int main() {
    try {
        field_cuts_and_checkpoint();
        pooled_save_transition();
        host_region_route();
        std::cout << "ORE_FIELD_PASS " << checks << '\n';
    } catch (const std::exception& error) {
        std::cerr << "ORE_FIELD_FAIL " << error.what() << '\n';
        return 1;
    }
}
