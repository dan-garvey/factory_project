#include "arrival_configuration.hpp"

#include "factory/mineral_site.hpp"
#include "factory/site_geometry_contract.hpp"

#include <cstddef>

namespace factory::godot_world {
namespace {
using stationary::Role;
using values::Value;
using Integer = Value::Integer;
}  // namespace

std::optional<ArrivalConfiguration> make_arrival_configuration(
        bool arrival, bool advanced_fixture, const std::vector<std::string>& actors) {
    if (actors.empty() || actors.size() > 2 || actors.front() != "P") return std::nullopt;
    for (const auto& actor : actors)
        if (actor != "P" && actor != "Q") return std::nullopt;
    if (actors.size() == 2 && actors[1] != "Q") return std::nullopt;

    ArrivalConfiguration content;
    auto& profile = content.profile;
    auto& seed = content.seed;
    // Reversible opening content, with enough buffer to recover finite ore in
    // batches. All reserve and carried quantities remain in this one World.
    profile.material = {1, 32, 2};
    profile.initial_units = mineral_site::opening_reserve;
    profile.meters_per_grid_unit = site_geometry::pitch / 4.0;
    profile.anchor_offset = {0, site_geometry::anchor_height, 0};
    profile.wheel_radius = site_geometry::wheel_radius_hundredths;
    profile.wheel_axle_offset = site_geometry::wheel_axle_offset_hundredths;
    profile.build_reach = site_geometry::base_reach;
    if (arrival) profile.manual_cut_reach = 2.55;
    profile.foundation_parts = 24;
    // East of the river and clear of the exposed ore deposit. This is a
    // reversible authored site anchor, expressed in the one quarter-tile grid.
    if (arrival) {
        profile.landing_pod_center = mechanics::Point{4, 0, 16};
        profile.first_plate_unlock = !advanced_fixture;
        profile.material.manual_ore = materials::OreSite{"opening-copper", {-3, 0, 0}};
        profile.material.raw_mass = 4;
        profile.material.plate_mass = 3;
        profile.material.sheet_mass = 12;
        for (const auto& cell : mineral_site::opening_cells)
            for (Integer level = 0; level <= mineral_site::extraction_depth_steps; level += 4)
                profile.collector_faces.push_back({{4 * cell.x, level, 4 * cell.z}, {-1, 0, 0}});
        profile.material.timber_sites = {
            {"tree-east-south", {{16, 0, 8}, 8}},
            {"tree-east-north", {{16, 0, 28}, 8}},
            {"tree-north", {{0, 0, 28}, 8}},
            {"tree-east-upstream", {{16, 0, -4}, 8}},
            // Mature bank trees have stable native identities. The scene
            // matches each prepared mesh root to these quarter-tile centers.
            {"fir_00", {{-28, 0, -44}, 8}},
            {"fir_01", {{-31, 0, -11}, 8}},
            {"fir_02", {{-51, 0, 37}, 8}},
            {"fir_03", {{29, 0, -24}, 8}},
            {"fir_04", {{32, 0, -2}, 8}},
            {"fir_05", {{44, 0, 15}, 8}},
            {"broadleaf_00", {{15, 1, -46}, 8}},
            {"broadleaf_01", {{-46, 0, -34}, 8}}};
        // Zero means no carried-count limit. Finite sources and native custody
        // still bound the material that can exist in the opening.
        profile.material.hand_carry_capacity = 0;
        profile.material.component_capacity = 0;
        // Reversible cold-workshop costs for a real powered receiver route.
        // Every kit remains in the one World inventory and history ledger.
        profile.fabrication_parts = {{{Role::shaft, 0, 2}, {1, 0, 1}},
            {{Role::belt, 0, 0}, {2, 1}}, {{Role::waterwheel, 0, 0}, {2, 1}},
            {{Role::gear, 2, 0}, {1, 0, 1}}, {{Role::gear, 4, 0}, {2, 0, 1}},
            {{Role::gearbox, 0, 0}, {1, 1}},
            {{Role::vertical_gearbox, 0, 0}, {1, 1}}};
    } else {
        profile.finite_parts = {{{Role::collector, 0, 0}, 1}, {{Role::belt, 0, 0}, 2},
            {{Role::processor, 0, 0}, 1}, {{Role::waterwheel, 0, 0}, 1}, {{Role::shaft, 0, 2}, 8},
            {{Role::gear, 2, 0}, 8}, {{Role::gear, 4, 0}, 2},
            {{Role::gearbox, 0, 0}, 2}, {{Role::vertical_gearbox, 0, 0}, 2},
            {{Role::chain_drive, 0, 0}, 8}};
    }
    seed.topology.drive_enabled = true;
    seed.material.initial_units = profile.initial_units;
    seed.material.stock.source = profile.initial_units;
    for (const auto& [id, site] : profile.material.timber_sites)
        seed.material.timber_remaining.emplace(id, site.initial);
    if (arrival) {
        const auto& center = *profile.landing_pod_center;
        seed.landing_pod = world::LandingPod{"landing-pod", center, 1};
        seed.issued_entities.emplace("landing-pod", 1);
        seed.fabrication_hub = world::FabricationHub{"pod-fabrication-hub", world::landing_hub_center(center), 1};
        seed.issued_entities.emplace(seed.fabrication_hub->id, 1);
        const auto deck = world::landing_deck_centers(center);
        for (std::size_t index = 0; index < deck.size(); ++index) {
            const auto id = "pod-floor-" + std::to_string(index);
            seed.foundations.emplace(id, world::Foundation{deck[index], 1});
            seed.issued_entities.emplace(id, 1);
        }
    }
    for (const auto& actor : actors) {
        profile.actors.insert(actor);
        seed.material.cargo.emplace(actor, materials::Cargo{});
        seed.kits.emplace(actor, actor == "P" ? profile.finite_parts : stationary::Kit{});
        seed.foundation_kits.emplace(actor, actor == "P" ?
            profile.foundation_parts - (arrival ? world::landing_deck_parts : 0) : 0);
        profile.starting_foundation_kits.emplace(actor, seed.foundation_kits.at(actor));
        // Start on the unfolded front deck, clear of the rear pressure shell,
        // side doors and threshold. Both capsules remain near the local bench.
        content.actor_starts.emplace_back(actor, arrival ?
            authority::Point{(actor == "P" ? 1.0 : 0.5) * site_geometry::pitch, 1.0, 4.8} :
            authority::Point{-site_geometry::pitch, 1.0,
                (actor == "P" ? 2.0 : 3.0) * site_geometry::pitch});
    }
    return content;
}

}  // namespace factory::godot_world
