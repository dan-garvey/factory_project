#include "factory/recovery.hpp"
#include "factory/stationary.hpp"

#include <algorithm>
#include <iostream>
#include <stdexcept>
#include <string>
#include <utility>

namespace {
namespace s = factory::stationary;
namespace m = factory::materials;
namespace g = factory::mechanics;
int checks{};
const m::Config config{2, 2, 4};

void check(bool value, const char* message) {
    ++checks;
    if (!value) throw std::runtime_error(message);
}

s::PlacedPart hub(std::string id, s::Role role, g::Point point) {
    return {{std::move(id), g::Kind::hub, point, g::Axis::z, 0, 0}, 1, role};
}

s::Topology topology() {
    return {{
        hub("wheel-A", s::Role::waterwheel, {0, 0, 0}),
        {{"shaft-A", g::Kind::shaft, {0, 0, 3}, g::Axis::z, 0, 3}, 1, s::Role::shaft},
        hub("processor-1", s::Role::processor, {0, 0, 4}),
        hub("wheel-B", s::Role::waterwheel, {10, 0, 0}),
        {{"shaft-B", g::Kind::shaft, {10, 0, 2}, g::Axis::z, 0, 2}, 1, s::Role::shaft},
        hub("collector-1", s::Role::collector, {10, 0, 4}),
    }, {}, {{"wheel-A", {1, 1}}, {"wheel-B", {2, 1}}}, true};
}

m::State state(m::Stock stock, std::optional<m::WorkLot> work = {},
               m::WorkId next = 1) {
    return {16, stock, {{"P", {}}, {"Q", {}}}, work, next};
}

m::Path path(const s::Topology& t) {
    const auto has = [&](s::Role role) {
        return std::any_of(t.parts.begin(), t.parts.end(),
            [&](const auto& part) { return part.role == role; });
    };
    // This literal bad-route fixture has no material links. Its sources remain
    // enabled throughout. The material library still has one power flag; this
    // does not claim per-component frequency or live World power adoption.
    return {has(s::Role::collector), false, has(s::Role::processor),
            false, false, t.drive_enabled};
}

m::ResolvedTarget target(const s::Topology& t, const char* id, m::Holder holder) {
    const auto part = std::find_if(t.parts.begin(), t.parts.end(),
        [&](const auto& value) { return value.geometry.id == id; });
    check(part != t.parts.end(), "The literal target resolves to a current physical part.");
    const auto role = holder == m::Holder::collector ? s::Role::collector : s::Role::processor;
    check(part->role == role, "The resolved material holder matches that physical part.");
    return {{id, part->generation}, holder, path(t),
            holder == m::Holder::processor
                ? std::optional<m::RecipeSignature>{m::RecipeSignature{2, 4}} : std::nullopt};
}

template<class T, class Variant>
const T& prepared(const Variant& plan) {
    const auto* result = std::get_if<T>(&plan);
    check(result != nullptr, "The real module must return a complete prepared candidate.");
    return *result;
}

void rotating(const s::Topology& t, const char* id, g::Rate rate) {
    const auto view = s::power_view(t);
    check(view.mechanical.accepted(), "The composed mechanical fixture is valid.");
    check(view.mechanical.motion.at(id) == g::Motion{g::MotionState::rotating, rate},
          "The separate literal geometric branch retains its exact rate.");
}

void occupied(const s::Topology& t, const s::Kit& kit, const m::State& material,
              const char* id, std::int64_t generation = 1) {
    const auto plan = s::prepare_removal(t, kit, material, {{id, generation}});
    const auto* refusal = std::get_if<s::RemovalRefusal>(&plan);
    check(refusal && refusal->reason == s::RemovalError::occupied_target,
          "Actual canonical contents refuse removal without a drive-stop rule.");
}

void raw_bad_route() {
    auto t = topology();
    s::Kit kit;
    auto material = state({14, 2, 0, 0, 0});
    const auto original = material;
    check(m::validate(material, config, path(t)) == m::Error::none,
          "The literal incomplete-route raw state conserves sixteen units.");
    occupied(t, kit, material, "collector-1");
    const auto recovered = m::prepare_recovery(material, config,
        {"P", target(t, "collector-1", m::Holder::collector)});
    material = prepared<m::PreparedTransfer>(recovered).candidate;
    auto expected = state({14, 0, 0, 0, 0});
    expected.cargo.at("P").raw_units = 2;
    check(material == expected, "Real recovery moves raw units to P without a press route.");

    const auto removed = s::prepare_removal(t, kit, material, {{"collector-1", 1}});
    const auto& removal = prepared<s::PreparedRemoval>(removed);
    t = removal.candidate;
    kit = removal.candidate_kit;
    check(m::validate(material, config, path(t)) == m::Error::none,
          "Recovered material remains valid when the empty collector is absent.");
    rotating(t, "processor-1", {1, 1});

    auto collector = hub("collector-2", s::Role::collector, {10, 0, 4});
    collector.generation = 2; // World-supplied fresh identity, not allocated here.
    const auto rebuilt = s::prepare_placement(t, kit, material, {collector, std::nullopt});
    const auto& replacement = prepared<s::PreparedPlacement>(rebuilt);
    t = replacement.candidate;
    kit = replacement.candidate_kit;
    rotating(t, "collector-2", {2, 1});
    rotating(t, "processor-1", {1, 1});

    const auto inserted = m::prepare_insertion(material, config,
        {"P", target(t, "collector-2", m::Holder::collector), m::RawInsertion{2}});
    material = prepared<m::PreparedTransfer>(inserted).candidate;
    check(material == original && material.stock.source == 14,
          "The real raw round trip preserves all sixteen units and never refills the seam.");
    check(kit.at({s::Role::collector, 0, 0}) == 0 && t.drive_enabled,
          "The one returned collector is consumed once without stopping the drive.");
}

void work_recovery_and_continuation() {
    auto t = topology();
    s::Kit kit;
    auto material = state({10, 0, 0, 2, 1}, m::WorkLot{7, {2, 4}, 3}, 8);
    check(m::validate(material, config, path(t)) == m::Error::none,
          "The partial-work, input and output fixture conserves sixteen raw units.");
    occupied(t, kit, material, "processor-1");

    const auto recovered = m::prepare_recovery(material, config,
        {"P", target(t, "processor-1", m::Holder::processor)});
    material = prepared<m::PreparedTransfer>(recovered).candidate;
    auto expected = state({10, 0, 0, 0, 0}, {}, 8);
    expected.cargo.at("P") = {2, 1, {{7, {2, 4}, 3}}};
    check(material == expected,
          "Real recovery preserves raw, products and the whole original partial-work lot.");

    const auto removed = s::prepare_removal(t, kit, material, {{"processor-1", 1}});
    const auto& removal = prepared<s::PreparedRemoval>(removed);
    t = removal.candidate;
    kit = removal.candidate_kit;
    check(m::validate(material, config, path(t)) == m::Error::none,
          "Carried work does not occupy the removed processor.");
    rotating(t, "collector-1", {2, 1});

    auto processor = hub("processor-2", s::Role::processor, {0, 0, 4});
    processor.generation = 2;
    const auto rebuilt = s::prepare_placement(t, kit, material, {processor, std::nullopt});
    const auto& replacement = prepared<s::PreparedPlacement>(rebuilt);
    t = replacement.candidate;
    kit = replacement.candidate_kit;
    rotating(t, "processor-2", {1, 1});
    rotating(t, "collector-1", {2, 1});

    const auto inserted = m::prepare_insertion(material, config,
        {"P", target(t, "processor-2", m::Holder::processor), m::WorkInsertion{7}});
    material = prepared<m::PreparedTransfer>(inserted).candidate;
    check(material.processing == m::WorkLot{7, {2, 4}, 3} &&
          material.next_work_id == 8,
          "Reinsertion preserves the original serial, recipe and positive remaining work.");
    const auto raw = m::prepare_insertion(material, config,
        {"P", target(t, "processor-2", m::Holder::processor), m::RawInsertion{2}});
    material = prepared<m::PreparedTransfer>(raw).candidate;

    for (int tick = 0; tick < 3; ++tick)
        check(m::step(material, config, path(t)) == m::Error::none,
              "The real canonical material implementation advances the restored work.");
    expected = state({8, 2, 0, 0, 1}, m::WorkLot{8, {2, 4}, 4}, 9);
    expected.cargo.at("P").products = 1;
    check(material == expected,
          "Exactly three old ticks finish lot seven; queued raw starts only fresh lot eight.");

    for (int tick = 0; tick < 4; ++tick)
        check(m::step(material, config, path(t)) == m::Error::none,
              "The second real lot reaches blocked ready work without losing custody.");
    expected.processing->remaining_ticks = 0;
    check(material == expected, "Full output retains the exact ready lot at zero ticks.");
    occupied(t, kit, material, "processor-2", 2);
    check(m::retrieve(material, config, path(t), "Q", 1) == m::Error::none,
          "Q retrieves only the first outlet product.");
    check(material.processing == m::WorkLot{8, {2, 4}, 0},
          "Retrieval does not consume or reset the ready lot.");
    check(m::step(material, config, path(t)) == m::Error::none,
          "One later tick releases the original ready lot exactly once.");
    check(m::retrieve(material, config, path(t), "P", 1) == m::Error::none,
          "P retrieves the second outlet product.");

    expected = state({8, 2, 0, 0, 0}, {}, 9);
    expected.cargo.at("P").products = 2;
    expected.cargo.at("Q").products = 1;
    check(material == expected && m::validate(material, config, path(t)) == m::Error::none,
          "Final source, raw and individual products conserve exactly sixteen units.");
    check(kit.at({s::Role::processor, 0, 0}) == 0 && t.drive_enabled,
          "The processor part is returned and rebuilt once with the drive still enabled.");
    rotating(t, "collector-1", {2, 1});
}

}  // namespace

int main() {
    try {
        raw_bad_route();
        work_recovery_and_continuation();
        std::cout << "{\"status\":\"pass\",\"evidence\":\"invented_recovery_rebuild_integration\","
                     "\"checks\":" << checks << "}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "recovery_rebuild_test: " << error.what() << '\n';
        return 1;
    }
}
