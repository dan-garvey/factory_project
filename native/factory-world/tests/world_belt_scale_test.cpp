#include "factory/checkpoint.hpp"

#include <algorithm>
#include <chrono>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace w = factory::world;
namespace g = factory::mechanics;
namespace s = factory::stationary;
namespace m = factory::materials;

int main(int argc, char** argv) {
    constexpr std::size_t belt_count = 500;
    w::Profile profile;
    profile.material = {1, 32, 2};
    profile.material.manual_ore = m::OreSite{"ore", {-3, 0, 0}};
    profile.initial_units = 1;
    profile.actors = {"P"};
    profile.build_reach = 100;
    profile.finite_parts = {{{s::Role::waterwheel, 0, 0}, belt_count},
        {{s::Role::shaft, 0, 2}, belt_count * 2}, {{s::Role::belt, 0, 0}, belt_count}};
    w::State seed;
    seed.material.initial_units = 1;
    seed.material.stock.source = 1;
    seed.material.cargo.emplace("P", m::Cargo{});
    seed.kits.emplace("P", s::Kit{});
    seed.topology.drive_enabled = true;
    for (std::size_t index = 0; index < belt_count; ++index) {
        const auto name = "scale-belt-" + std::to_string(index);
        const auto first = name + "-first";
        const auto last = name + "-last";
        const auto wheel = name + "-wheel";
        const g::Integer z = static_cast<g::Integer>(index) * 16;
        const g::Point wheel_center{0, 0, z - 4};
        const factory::waterwheel::Sample sample{0, -1000, 200, 0};
        const auto rate = factory::waterwheel::rate(121, 600, g::Axis::z, sample);
        if (!rate || rate->numerator == 0)
            throw std::runtime_error("The trusted water sample did not turn a wheel.");
        profile.water.emplace(std::array<g::Integer, 2>{wheel_center[0], wheel_center[2]}, sample);
        seed.topology.parts.push_back({{wheel, g::Kind::hub, wheel_center,
            g::Axis::z, 0, 0}, 1, s::Role::waterwheel});
        seed.topology.parts.push_back({{first, g::Kind::shaft, {0, 0, z},
            g::Axis::z, 0, 2}, 1, s::Role::shaft});
        seed.topology.parts.push_back({{last, g::Kind::shaft, {76, 0, z},
            g::Axis::z, 0, 2}, 1, s::Role::shaft});
        seed.topology.sources.push_back({wheel, *rate});
        seed.topology.belt_spans.push_back({{name, first, last}, 1});
        seed.material.belt_lanes.emplace(name, m::BeltLane{std::vector<std::optional<m::Cargo>>(20)});
        for (const auto& id : {name, first, last, wheel}) seed.issued_entities.emplace(id, 1);
    }
    auto world = w::World::create("many-powered-belts", profile, seed);
    if (!world) throw std::runtime_error("The conserved multi-belt World seed was rejected.");
    const auto original = world->snapshot();
    const auto drive = w::drive_power(profile, original.state);
    if (!drive.mechanical.accepted() || drive.mechanical.motion.size() != belt_count * 3 ||
        drive.mechanical.engagements.size() < belt_count * 2)
        throw std::runtime_error("The World lost an independently powered belt route.");
    for (const auto& source : original.state.topology.sources)
        if (drive.mechanical.motion.at(source.hub).state != g::MotionState::rotating)
            throw std::runtime_error("A trusted site wheel stopped in the scale fixture.");
    const auto first_tick = world->tick();
    if (first_tick.error != w::TransactionError::none || world->snapshot().state != original.state)
        throw std::runtime_error("A still-empty powered belt tick changed conserved custody.");
    using V = factory::values::Value;
    const w::ObserveActor nearby = [](const std::string& actor) -> std::optional<factory::authority::ActorCut> {
        return factory::authority::ActorCut{actor, {0, 0, 0}, 1, true, 100};
    };
    const auto issue = [&](const V::Object& intent) {
        const auto result = world->command({"P", "P-client"}, intent, nearby);
        return result.completed() && result.result &&
            std::get<bool>(result.result->at("accepted").storage());
    };
    if (!issue({{"context", V("many-powered-belts")}, {"client", V("P-client")},
            {"request", V("harvest-one")}, {"actor", V("P")},
            {"action", V("harvest_source")}, {"target", V("ore")}}))
        throw std::runtime_error("The fixture actor could not harvest one conserved raw blank.");
    if (!issue({{"context", V("many-powered-belts")}, {"client", V("P-client")},
            {"request", V("load-one")}, {"actor", V("P")},
            {"action", V("load_belt_slot")}, {"target", V("scale-belt-0")},
            {"generation", V(g::Integer{1})}, {"slot", V(g::Integer{0})},
            {"item", V("raw")}, {"work_id", V(g::Integer{0})}}))
        throw std::runtime_error("The fixture actor could not load one conserved belt slot.");
    const auto loaded = world->snapshot();
    if (!loaded.state.material.belt_lanes.at("scale-belt-0").slots[0] ||
        loaded.state.material.belt_lanes.at("scale-belt-0").slots[0]->raw_units != 1)
        throw std::runtime_error("The native route lost its actor-loaded raw blank.");
    const auto encoded = w::encode_checkpoint(profile, loaded);
    if (!std::holds_alternative<factory::values::Value>(encoded))
        throw std::runtime_error("The many-belt checkpoint could not encode.");
    const auto decoded = w::decode_checkpoint(profile, "many-powered-belts",
        std::get<factory::values::Value>(encoded));
    if (!std::holds_alternative<w::Snapshot>(decoded) ||
        std::get<w::Snapshot>(decoded).state != loaded.state)
        throw std::runtime_error("The many-belt checkpoint lost a lane or power identity.");
    if (world->tick().error != w::TransactionError::none ||
        !w::validate(profile, world->snapshot()))
        throw std::runtime_error("The loaded powered belt did not retain one valid World after ticking.");
    if (argc > 1 && std::string(argv[1]) == "--benchmark") {
        const auto measure = [&](const char* stage, auto&& operation) {
            std::vector<double> samples;
            samples.reserve(20);
            for (int sample = 0; sample < 20; ++sample) {
                const auto start = std::chrono::steady_clock::now();
                operation();
                samples.push_back(std::chrono::duration<double, std::milli>(
                    std::chrono::steady_clock::now() - start).count());
            }
            std::sort(samples.begin(), samples.end());
            std::cout << "WORLD_BELT_STAGE name=" << stage << " belts=" << belt_count
                      << " wheels=" << belt_count << " shafts=" << belt_count * 2
                      << " samples=" << samples.size() << " median_ms=" << samples[10]
                      << " p95_ms=" << samples[19] << '\n';
        };
        measure("stationary_power_view", [&] {
            if (!s::power_view(loaded.state.topology).mechanical.accepted())
                throw std::runtime_error("The measured stationary graph was rejected.");
        });
        measure("drive_power", [&] {
            if (!w::drive_power(profile, loaded.state).mechanical.accepted())
                throw std::runtime_error("The measured World graph was rejected.");
        });
        measure("validate", [&] {
            if (!w::validate(profile, loaded))
                throw std::runtime_error("The measured World validation failed.");
        });
        std::vector<double> samples;
        samples.reserve(20);
        for (int sample = 0; sample < 20; ++sample) {
            auto fresh = w::World::restore("many-powered-belts", profile, loaded);
            if (!fresh) throw std::runtime_error("A measured World could not restore the loaded cut.");
            const auto start = std::chrono::steady_clock::now();
            if (fresh->tick().error != w::TransactionError::none)
                throw std::runtime_error("The measured World tick failed.");
            samples.push_back(std::chrono::duration<double, std::milli>(
                std::chrono::steady_clock::now() - start).count());
        }
        std::sort(samples.begin(), samples.end());
        std::cout << "WORLD_BELT_STAGE name=tick belts=" << belt_count << " wheels=" << belt_count
                  << " shafts=" << belt_count * 2 << " samples=" << samples.size()
                  << " median_ms=" << samples[10] << " p95_ms=" << samples[19] << '\n';
    }
    std::cout << "WORLD_BELT_SCALE_CHECK belts=" << belt_count << " powered=passed\n";
}
