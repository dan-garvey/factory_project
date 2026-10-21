#include "factory/repair_scenarios.hpp"

#include <iostream>
#include <stdexcept>

namespace r = factory::repair_scenarios;
namespace w = factory::world;
namespace a = factory::authority;
namespace m = factory::materials;
namespace s = factory::stationary;
using V = factory::values::Value;
using I = a::Integer;
namespace {
int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

a::Object request(const std::string& context, const char* action, const std::string& id) {
    return {{"context", V(context)}, {"client", V("repair-session")}, {"actor", V("P")},
            {"request", V(id)}, {"action", V(action)}};
}

a::Object target(const std::string& context, const char* action, const std::string& id, const char* entity) {
    auto command = request(context, action, id);
    command.emplace("target", V(entity));
    command.emplace("generation", V(I{1}));
    return command;
}

w::Delivery send(w::World& world, const a::Object& command, a::Point position, int& observations) {
    // Explicit invented native admission cut. No engine body, camera, transport
    // or player observation is claimed by these unit inputs.
    auto delivery = world.command({"P", "repair-session"}, command,
        [&observations, position](const std::string& actor) -> std::optional<a::ActorCut> {
            ++observations;
            return a::ActorCut{actor, position, 1, true, 1000000};
        });
    check(delivery.completed(), "Each well-formed fixture command must return an original or cached outcome.");
    return delivery;
}

bool accepted(const w::Delivery& delivery) {
    return std::get<bool>(delivery.result->at("accepted").storage());
}

void ticks(w::World& world, int count, const w::Profile& profile) {
    for (int i = 0; i < count; ++i) {
        check(world.tick().error == w::TransactionError::none, "Native ticks must preserve the complete canonical World.");
        check(w::validate(profile, world.snapshot()), "Every resulting native snapshot remains conserved and valid.");
    }
}

void finish(w::World& world, const std::string& context, const w::Profile& profile, int& observations) {
    for (int i = 0; i < 64 && world.snapshot().state.material.cargo.at("P").products < 4; ++i) {
        if (world.snapshot().state.material.stock.output > 0) {
            auto collect = target(context, "collect", "plate-" + std::to_string(i), "processor");
            collect.emplace("amount", V(I{1}));
            check(accepted(send(world, collect, {12, 0, 8}, observations)), "A nearby admitted actor can retrieve one real plate.");
        }
        ticks(world, 1, profile);
    }
    const auto material = world.snapshot().state.material;
    check(material.cargo.at("P").products == 4 && material.cargo.at("Q").products == 0,
          "Each repair reaches exactly four carried products without team-credit assumptions.");
    check(material.initial_units == 16 && material.stock.source < 16,
          "The products came from the original finite material, with no seed reset or refill.");
}

void scenario(const r::Definition& definition) {
    auto content = r::make(definition.id);
    check(content.has_value() && content->definition == &definition, "Each catalogue entry creates its exact trusted startup content.");
    const std::string context = "repair-" + std::string(definition.id);
    auto world = w::World::create(context, content->profile, content->seed);
    check(world != nullptr, "Every authored repair seed passes the real World initializer.");
    check(content->profile.build_reach == 4 && content->profile.meters_per_grid_unit == 1,
          "Repair content preserves a finite physical reach and explicit grid scale.");
    auto separate = r::make(definition.id);
    separate->seed.material.stock.source = 0;
    check(world->snapshot().state == content->seed, "Editing another unused seed cannot affect the sole World.");
    int observations{};
    if (definition.id == "coupling") {
        const auto power = w::machine_power(world->snapshot().state.topology);
        check(!power.collector && power.processor &&
              s::power_view(world->snapshot().state.topology).mechanical.motion.at("pulley-first").state == factory::mechanics::MotionState::rotating, "Only the cutter is disconnected from its rotating drive.");
        ticks(*world, 8, content->profile);
        check(world->snapshot().state.material == content->seed.material,
              "Waiting cannot extract a blank through a missing coupling.");
        auto place = request(context, "place", "replace-coupling");
        place.emplace("role", V("shaft"));
        place.emplace("center", V(V::Array{V(I{0}), V(I{0}), V(I{4})}));
        place.emplace("axis", V("z"));
        place.emplace("teeth", V(I{0}));
        place.emplace("half_span", V(I{2}));
        check(accepted(send(*world, place, {0, 0, 0}, observations)), "Placing the carried shaft repairs the actual geometry.");
        const auto repaired = world->snapshot().state;
        m::Quantity remaining_parts{};
        for (const auto& item : repaired.kits.at("P")) remaining_parts += item.second;
        check(remaining_parts == 0, "The repair consumes the one original carried coupling.");
        const auto before_replay = observations;
        const auto duplicate = send(*world, place, {100, 0, 100}, observations);
        check(accepted(duplicate) && std::get<bool>(duplicate.result->at("duplicate").storage()) &&
              observations == before_replay && world->snapshot().state == repaired,
              "Retrying the same repair neither observes a new pose nor consumes or builds another shaft.");
    } else if (definition.id == "link") {
        ticks(*world, 8, content->profile);
        check(world->snapshot().state.material.stock == m::Stock{15, 1, 0, 0, 0},
              "The missing span leaves one blank in the collector and the press empty.");
        auto link = target(context, "place_belt_span", "restore-handoff", "pulley-first");
        link.emplace("to", V("pulley-last")); link.emplace("to_generation", V(I{1}));
        const auto stock = world->snapshot().state.material;
        check(accepted(send(*world, link, {6, 0, 8}, observations)), "Both shafts are reachable while restoring the span.");
        auto repaired = world->snapshot().state.material;
        repaired.belt_lanes.clear();
        check(repaired == stock, "Building a span creates an empty lane without consuming or replacing held blanks.");
    } else {
        ticks(*world, 8, content->profile);
        const auto blocked = world->snapshot().state.material;
        check(blocked.stock.input == 1 && blocked.stock.output == 1 && blocked.processing == content->seed.material.processing &&
              blocked.belt_lanes.at("belt").slots.back() == m::Cargo{1, 0, {}} && w::validate(content->profile, world->snapshot()),
              "The full output preserves ready work and the blocked upstream belt item.");
        const auto refusal = send(*world, target(context, "remove", "cannot-delete-billet", "processor"), {12, 0, 8}, observations);
        check(!accepted(refusal) && world->snapshot().state.material.processing == content->seed.material.processing,
              "Dismantling occupied machinery cannot solve the puzzle by discarding the billet.");
        auto collect = target(context, "collect", "free-output", "processor");
        collect.emplace("amount", V(I{1}));
        check(accepted(send(*world, collect, {12, 0, 8}, observations)), "Collecting the existing output frees the real buffer.");
        check(world->snapshot().state.material.processing == m::WorkLot{7, {1, 2}, 0},
              "Retrieval preserves the waiting lot's exact identity, recipe and completed progress.");
        ticks(*world, 1, content->profile);
        const auto continued = world->snapshot().state.material;
        check(continued.stock.output == 1 && continued.processing && continued.processing->id == 8 &&
              continued.next_work_id == 9 && continued.cargo.at("P").products == 1,
              "The original ready lot releases once and the next real input starts as a fresh lot.");
    }
    finish(*world, context, content->profile, observations);
    const auto saved = world->snapshot();
    auto restored = w::World::restore(context, content->profile, saved);
    check(restored && restored->snapshot().state == saved.state,
          "The scenario's canonical result can resume through the existing validated snapshot boundary.");
}
}  // namespace

int main() {
    try {
        check(r::catalogue().size() == 3 && !r::make("missing"), "Unknown content cannot silently select a fresh default seed.");
        for (const auto& definition : r::catalogue()) scenario(definition);
        std::cout << checks << " native repair content checks, 0 failures.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL after " << checks << " checks: " << error.what() << '\n';
        return 1;
    }
}
