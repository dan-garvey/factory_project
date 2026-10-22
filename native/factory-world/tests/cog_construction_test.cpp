#include "factory/checkpoint.hpp"

#include <iostream>
#include <algorithm>
#include <array>
#include <stdexcept>
#include <string>

namespace w = factory::world;
namespace s = factory::stationary;
namespace m = factory::mechanics;
namespace a = factory::authority;
using V = factory::values::Value;
using I = V::Integer;
using O = V::Object;

namespace {
int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
template<class T> const T& field(const O& object, const char* key) {
    return std::get<T>(object.at(key).storage());
}
O place(const char* request, const m::Point& center, const char* axis, I teeth) {
    return {{"context", V("cog-world")}, {"client", V("P-session")}, {"request", V(request)},
        {"actor", V("P")}, {"action", V("place")}, {"role", V("gear")},
        {"center", V(V::Array{V(center[0]), V(center[1]), V(center[2])})},
        {"axis", V(axis)}, {"teeth", V(teeth)}, {"half_span", V(I{0})}};
}
O remove(const std::string& id, I generation, const char* request) {
    return {{"context", V("cog-world")}, {"client", V("Q-session")}, {"request", V(request)},
        {"actor", V("Q")}, {"action", V("remove")}, {"target", V(id)}, {"generation", V(generation)}};
}
w::Delivery send(w::World& world, const O& intent) {
    const auto actor = field<std::string>(intent, "actor");
    return world.command({actor, field<std::string>(intent, "client")}, intent,
        [](const std::string& who) -> std::optional<a::ActorCut> {
            return a::ActorCut{who, {0, 0, 0}, 1, true, 10};
        });
}
O accepted(const w::Delivery& delivery) {
    if (delivery.result && !field<bool>(*delivery.result, "accepted"))
        std::cerr << "Refusal " << field<std::string>(*delivery.result, "reason") << '\n';
    check(delivery.completed() && field<bool>(*delivery.result, "accepted"), "A finite World command must succeed.");
    return *delivery.result;
}
void construction(bool corner) {
    const m::Point input{0, 0, 0};
    const m::Point output = corner ? m::Point{4, 0, 4} : m::Point{4, 4, 0};
    const auto input_axis = corner ? m::Axis::x : m::Axis::z;
    const auto output_axis = m::Axis::z;
    const I input_teeth = corner ? 4 : 2;
    w::Profile profile;
    profile.material = {1, 1, 2};
    profile.initial_units = 1;
    profile.actors = {"P", "Q"};
    profile.meters_per_grid_unit = 0.1;
    profile.build_reach = 4;
    profile.finite_parts = {{{s::Role::waterwheel, 0, 0}, 1}, {{s::Role::processor, 0, 0}, 1},
                            {{s::Role::gear, 4, 0}, corner ? 2 : 1}};
    if (!corner) profile.finite_parts.emplace(s::PartSpec{s::Role::gear, 2, 0}, 1);
    w::State seed;
    seed.material.initial_units = 1;
    seed.material.stock.source = 1;
    seed.material.cargo = {{"P", {}}, {"Q", {}}};
    seed.kits = {{"P", {{{s::Role::gear, 4, 0}, corner ? 2 : 1}}}, {"Q", {}}};
    if (!corner) seed.kits.at("P").emplace(s::PartSpec{s::Role::gear, 2, 0}, 1);
    auto wheel = input;
    wheel[static_cast<std::size_t>(input_axis)] -= 4;
    auto press = output;
    press[static_cast<std::size_t>(output_axis)] += 4;
    seed.topology.parts = {
        {{"wheel", m::Kind::hub, wheel, input_axis, 0, 0}, 1, s::Role::waterwheel},
        {{"press", m::Kind::hub, press, output_axis, 0, 0}, 1, s::Role::processor},
    };
    seed.topology.sources = {{"wheel", {1, 1}}};
    seed.topology.drive_enabled = true;
    for (const auto& item : seed.topology.parts) seed.issued_entities.emplace(item.geometry.id, item.generation);
    auto world = w::World::create("cog-world", profile, seed);
    check(world != nullptr, "The finite two-actor fixture creates the single World.");
    const auto first_command = place("first", input, corner ? "x" : "z", input_teeth);
    const auto first = accepted(send(*world, first_command));
    auto invalid_history = world->snapshot();
    auto& placement = invalid_history.history.records.back();
    placement.intent.at("center") = V(V::Array{V(I{0}), V(I{1}), V(I{0})});
    placement.result.at("targets") = V(V::Array{V(V::Array{V(0.0), V(0.1), V(0.0)})});
    placement.result.at("distances_squared") = V(V::Array{V(0.1 * 0.1)});
    check(!w::World::restore("cog-world", profile, invalid_history),
          "Even a consistent historical receipt cannot restore an accepted off-grid cog placement.");
    check(!w::machine_power(world->snapshot().state.topology).processor, "One cog does not power the remote press.");
    const auto second_command = place("second", output, "z", 4);
    const auto second = accepted(send(*world, second_command));
    auto snapshot = world->snapshot();
    const auto view = s::power_view(snapshot.state.topology);
    const m::Rate expected = corner ? m::Rate{1, 1} : m::Rate{-1, 2};
    check(view.mechanical.motion.at("press") == m::Motion{m::MotionState::rotating, expected} &&
          w::machine_power(snapshot.state.topology).processor, "The actual World powers the press at the expected signed rate.");
    check(snapshot.state.kits.at("P").at({s::Role::gear, 4, 0}) == 0,
          "Construction consumes the exact large cog specifications.");
    const auto encoded = w::encode_checkpoint(profile, snapshot);
    check(std::holds_alternative<V>(encoded), "The built World encodes its full checkpoint.");
    const auto decoded = w::decode_checkpoint(profile, "cog-world", std::get<V>(encoded));
    check(std::holds_alternative<w::Snapshot>(decoded), "The constructed train decodes from its checkpoint.");
    auto restored = w::World::restore("cog-world", profile, std::get<w::Snapshot>(decoded));
    check(restored != nullptr && restored->snapshot().state == snapshot.state &&
          w::machine_power(restored->snapshot().state.topology).processor,
          "A fresh World retains constructed custody and its powered geometry.");
    const auto replay = send(*restored, first_command);
    check(replay.completed() && field<bool>(*replay.result, "duplicate") &&
          field<std::string>(*replay.result, "entity") == field<std::string>(first, "entity"),
          "A historical placement retry does not spend or create another part.");
    const auto id = field<std::string>(second, "entity");
    const auto generation = field<I>(second, "generation");
    accepted(send(*restored, remove(id, generation, "remove")));
    snapshot = restored->snapshot();
    check(!w::machine_power(snapshot.state.topology).processor &&
          snapshot.state.kits.at("Q").at({s::Role::gear, 4, 0}) == 1,
          "Q removes the large cog, disconnecting the press and receiving the exact refund.");
    auto rebuilt = second_command;
    rebuilt.at("client") = V("Q-session"); rebuilt.at("actor") = V("Q"); rebuilt.at("request") = V("rebuild");
    const auto replacement = accepted(send(*restored, rebuilt));
    check(field<std::string>(replacement, "entity") != id &&
          w::machine_power(restored->snapshot().state.topology).processor,
          "Q rebuilds a fresh identity and restores press power.");
}

void geared_processor(bool fast) {
    namespace mat = factory::materials;
    w::Profile profile;
    profile.material = {1, 1, 2};
    profile.initial_units = 2;
    profile.actors = {"P", "Q"};
    profile.meters_per_grid_unit = 0.1;
    profile.build_reach = 4;
    profile.finite_parts = {{{s::Role::waterwheel, 0, 0}, 1}, {{s::Role::processor, 0, 0}, 1},
        {{s::Role::gear, 2, 0}, 1}, {{s::Role::gear, 4, 0}, 1}};
    w::State seed;
    seed.material.initial_units = 2;
    seed.material.stock.output = 1;
    seed.material.processing = mat::WorkLot{1, {1, 2}, 2};
    seed.material.next_work_id = 2;
    seed.material.cargo = {{"P", {}}, {"Q", {}}};
    seed.kits = {{"P", {{{s::Role::gear, 2, 0}, 1}, {{s::Role::gear, 4, 0}, 1}}}, {"Q", {}}};
    seed.topology.parts = {
        {{"wheel", m::Kind::hub, {0, 0, -4}, m::Axis::z, 0, 0}, 1, s::Role::waterwheel},
        {{"press", m::Kind::hub, {4, 4, 4}, m::Axis::z, 0, 0}, 1, s::Role::processor}};
    seed.topology.sources = {{"wheel", {1, 1}}};
    seed.topology.drive_enabled = true;
    for (const auto& item : seed.topology.parts) seed.issued_entities.emplace(item.geometry.id, item.generation);
    auto world = w::World::create("cog-world", profile, seed);
    check(world != nullptr, "The geared press uses the existing World and finite part custody.");
    accepted(send(*world, place("speed-input", {0, 0, 0}, "z", fast ? 4 : 2)));
    accepted(send(*world, place("speed-output", {4, 4, 0}, "z", fast ? 2 : 4)));
    const auto drive = w::machine_power(world->snapshot().state.topology);
    check(drive.processor && drive.processor_work_per_tick ==
          (fast ? 2 * mat::work_subticks_per_tick : mat::work_subticks_per_tick / 2),
          "Actual mixed-size cogs set the processor work rate.");
    if (!fast) {
        auto third_profile = profile;
        third_profile.waterwheel_rate = {2, 3};
        auto third_state = world->snapshot().state;
        third_state.topology.sources.front().rate = {2, 3};
        auto third_world = w::World::create("third-cog", third_profile, third_state);
        check(third_world && third_world->tick().error == w::TransactionError::none &&
                  third_world->snapshot().state.material.processing->completed_subticks == 1365 &&
                  third_world->snapshot().state.material.processing->work_remainder == 1 &&
                  third_world->snapshot().state.material.processing->work_remainder_denominator == 3,
              "An actual geared one-third rate retains its fractional subtick.");
        const auto third_save = w::encode_checkpoint(third_profile, third_world->snapshot());
        check(std::holds_alternative<V>(third_save), "Fractional third-speed work checkpoints.");
        const auto third_decoded = w::decode_checkpoint(third_profile, "third-cog", std::get<V>(third_save));
        check(std::holds_alternative<w::Snapshot>(third_decoded), "Fractional third-speed work decodes.");
        auto recovery_world = w::World::restore("third-cog", third_profile, std::get<w::Snapshot>(third_decoded));
        O fractional_recover{{"context", V("third-cog")}, {"client", V("P-session")}, {"request", V("recover-third")},
            {"actor", V("P")}, {"action", V("recover")}, {"target", V("press")}, {"generation", V(I{1})}};
        check(recovery_world != nullptr, "The fractional work is available for recovery.");
        const auto fractional_receipt = accepted(send(*recovery_world, fractional_recover));
        const auto& fractional_lots = field<V::Array>(fractional_receipt, "moved_work");
        check(fractional_lots.size() == 1 && field<I>(std::get<O>(fractional_lots[0].storage()), "work_remainder") == 1 &&
                  field<I>(std::get<O>(fractional_lots[0].storage()), "work_remainder_denominator") == 3,
              "Recovery transfers the precise fractional progress with the workpiece.");
        const auto recovered_save = w::encode_checkpoint(third_profile, recovery_world->snapshot());
        check(std::holds_alternative<V>(recovered_save), "Recovered fractional work and receipt checkpoint.");
        const auto recovered_decoded = w::decode_checkpoint(third_profile, "third-cog", std::get<V>(recovered_save));
        check(std::holds_alternative<w::Snapshot>(recovered_decoded) &&
                  std::get<w::Snapshot>(recovered_decoded).state.material.cargo.at("P").work_lots.front().work_remainder == 1,
              "Recovered fractional work survives checkpoint decoding.");
        auto third_restored = w::World::restore("third-cog", third_profile, std::get<w::Snapshot>(third_decoded));
        check(third_restored && third_restored->tick().error == w::TransactionError::none &&
                  third_restored->tick().error == w::TransactionError::none &&
                  third_restored->snapshot().state.material.processing->remaining_ticks == 1 &&
                  third_restored->snapshot().state.material.processing->completed_subticks == 0 &&
                  third_restored->snapshot().state.material.processing->work_remainder == 0,
              "Two restored ticks complete exactly one work unit across three third-speed ticks.");
    }
    if (fast) {
        auto faster = world->snapshot().state.topology;
        for (const I source_rate : {I{10}, I{-10}}) {
            faster.sources.front().rate = {source_rate, 1};
            const auto power = w::machine_power(faster);
            check(power.processor && power.processor_work_per_tick == 20 * mat::work_subticks_per_tick,
                  "Either source direction lets the gears drive the press above the former sixteen-times cap.");
        }
        auto fast_profile = profile;
        fast_profile.material.cycle_ticks = 40;
        fast_profile.waterwheel_rate = {10, 1};
        auto fast_state = world->snapshot().state;
        fast_state.topology.sources.front().rate = {10, 1};
        fast_state.material.processing->recipe.cycle_ticks = 40;
        fast_state.material.processing->remaining_ticks = 40;
        auto fast_world = w::World::create("fast-cog", fast_profile, fast_state);
        check(fast_world && fast_world->tick().error == w::TransactionError::none &&
                  fast_world->snapshot().state.material.processing->remaining_ticks == 20,
              "The actual twenty-times geared press advances twenty units of work.");
        const auto encoded_fast = w::encode_checkpoint(fast_profile, fast_world->snapshot());
        check(std::holds_alternative<V>(encoded_fast), "High-speed partial work checkpoints.");
        const auto decoded_fast = w::decode_checkpoint(fast_profile, "fast-cog", std::get<V>(encoded_fast));
        check(std::holds_alternative<w::Snapshot>(decoded_fast), "High-speed partial work decodes.");
        auto resumed_fast = w::World::restore("fast-cog", fast_profile, std::get<w::Snapshot>(decoded_fast));
        check(resumed_fast && resumed_fast->tick().error == w::TransactionError::none &&
                  resumed_fast->snapshot().state.material.processing->remaining_ticks == 0 &&
                  resumed_fast->snapshot().state.material.stock.output == 1,
              "Restored high-speed work completes and waits behind the full output buffer.");
    }
    check(world->tick().changed, "The powered World advances the original workpiece.");
    const auto cut = world->snapshot();
    check(cut.state.material.processing && cut.state.material.stock.output == 1 &&
          cut.state.material.processing->remaining_ticks == (fast ? 0 : 2) &&
          cut.state.material.processing->completed_subticks == (fast ? 0 : mat::work_subticks_per_tick / 2),
          "Half and double rates change real work while the output remains full.");
    const auto encoded = w::encode_checkpoint(profile, cut);
    check(std::holds_alternative<V>(encoded), "Fractional and blocked work checkpoint encodes.");
    const auto decoded = w::decode_checkpoint(profile, "cog-world", std::get<V>(encoded));
    check(std::holds_alternative<w::Snapshot>(decoded), "Fractional and blocked work checkpoint decodes.");
    auto restored = w::World::restore("cog-world", profile, std::get<w::Snapshot>(decoded));
    check(restored && restored->snapshot().state == cut.state, "A fresh World retains exact work progress and cog custody.");
    O recover{{"context", V("cog-world")}, {"client", V("P-session")}, {"request", V("recover-speed")},
              {"actor", V("P")}, {"action", V("recover")}, {"target", V("press")}, {"generation", V(I{1})}};
    const auto receipt = accepted(send(*restored, recover));
    const auto& moved = field<V::Array>(receipt, "moved_work");
    check(moved.size() == 1 && field<I>(std::get<O>(moved[0].storage()), "completed_subticks") ==
          (fast ? 0 : mat::work_subticks_per_tick / 2), "Recovery receipt carries the original fractional progress.");
    const auto recovered = restored->snapshot();
    const auto saved = w::encode_checkpoint(profile, recovered);
    check(std::holds_alternative<V>(saved), "The receipt and carried work validate in a checkpoint.");
    const auto resumed = w::decode_checkpoint(profile, "cog-world", std::get<V>(saved));
    check(std::holds_alternative<w::Snapshot>(resumed), "The recovered checkpoint decodes.");
    auto fresh = w::World::restore("cog-world", profile, std::get<w::Snapshot>(resumed));
    check(fresh && fresh->snapshot().state == recovered.state,
          "A fresh World restores the carried work and recovery history.");
    const auto replay = send(*fresh, recover);
    check(replay.completed() && field<bool>(*replay.result, "duplicate") &&
          !factory::values::typed_difference(receipt.at("moved_work"), replay.result->at("moved_work")),
          "A retried recovery returns the same fractional receipt without moving anything twice.");
    O insert{{"context", V("cog-world")}, {"client", V("P-session")}, {"request", V("insert-speed")},
             {"actor", V("P")}, {"action", V("insert_work")}, {"target", V("press")},
             {"generation", V(I{1})}, {"work_id", V(I{1})}};
    accepted(send(*fresh, insert));
    for (int step = 0; step < (fast ? 1 : 3); ++step) check(fresh->tick().changed, "Reinserted work advances.");
    const auto finished = fresh->snapshot();
    check(!finished.state.material.processing && finished.state.material.stock.output == 1 &&
          finished.state.material.cargo.at("P").products == 1 && finished.state.material.next_work_id == 2,
          "The same recovered workpiece finishes once at its geared rate without resetting custody.");
}

void perpendicular_belt_line() {
    w::Profile profile;
    profile.material = {1, 1, 2}; profile.initial_units = 1;
    profile.actors = {"P", "Q"}; profile.meters_per_grid_unit = 0.1; profile.build_reach = 4;
    profile.finite_parts = {{{s::Role::waterwheel, 0, 0}, 1}, {{s::Role::collector, 0, 0}, 1},
        {{s::Role::belt, 0, 0}, 1}, {{s::Role::processor, 0, 0}, 1},
        {{s::Role::shaft, 0, 2}, 3}, {{s::Role::gear, 2, 0}, 7}};
    w::State seed; seed.material.initial_units = 1; seed.material.stock.source = 1;
    seed.material.cargo = {{"P", {}}, {"Q", {}}}; seed.kits = {{"P", profile.finite_parts}, {"Q", {}}};
    auto world = w::World::create("cog-world", profile, seed);
    check(world != nullptr, "The finite perpendicular-line World initializes.");
    auto shaft = [&](const char* request, const m::Point& center, const char* axis) {
        auto command = place(request, center, axis, 0);
        command.at("role") = V("shaft"); command.at("half_span") = V(I{2});
        return accepted(send(*world, command));
    };
    const auto first = shaft("first-shaft", {4, 0, 4}, "z");
    const auto wrong = shaft("wrong-shaft", {8, 0, 4}, "x");
    auto span = [&](const O& last, const char* request) {
        return O{{"context", V("cog-world")}, {"client", V("P-session")}, {"request", V(request)},
            {"actor", V("P")}, {"action", V("place_belt_span")}, {"target", first.at("entity")},
            {"generation", first.at("generation")}, {"to", last.at("entity")}, {"to_generation", last.at("generation")}};
    };
    const auto before = world->snapshot().state;
    const auto rejected = send(*world, span(wrong, "wrong-span"));
    check(rejected.completed() && !field<bool>(*rejected.result, "accepted") && world->snapshot().state == before,
          "A span between mismatched shaft axes is refused without consuming its part.");
    accepted(send(*world, remove(field<std::string>(wrong, "entity"), field<I>(wrong, "generation"), "remove-wrong-shaft")));
    const auto last = shaft("last-shaft", {8, 0, 4}, "z");
    accepted(send(*world, span(last, "belt-span")));
    const std::array<const char*, 3> roles{"waterwheel", "collector", "processor"};
    const std::array<I, 3> xs{-4, 0, 12};
    std::array<O, 3> hubs;
    for (std::size_t n = 0; n < roles.size(); ++n) {
        auto machine = place(("machine-" + std::to_string(n)).c_str(), {xs[n], 0, 4}, "z", 0);
        machine.at("role") = V(roles[n]);
        if (n != 0) machine.at("action") = V("place_connected");
        hubs[n] = accepted(send(*world, machine));
    }
    const std::array<m::Point, 7> centers{{{-4, 0, 8}, {0, 0, 8}, {4, 0, 8},
        {4, 0, 12}, {8, 0, 12}, {12, 0, 12}, {12, 0, 8}}};
    std::array<O, 7> cogs;
    for (std::size_t n = 0; n < centers.size(); ++n)
        cogs[n] = accepted(send(*world, place(("cog-" + std::to_string(n)).c_str(), centers[n], "z", 2)));
    O power{{"context", V("cog-world")}, {"client", V("P-session")}, {"request", V("power")},
        {"actor", V("P")}, {"action", V("set_drive")}, {"target", hubs[0].at("entity")},
        {"generation", hubs[0].at("generation")}, {"enabled", V(true)}};
    accepted(send(*world, power));
    const auto snapshot = world->snapshot();
    const auto view = s::power_view(snapshot.state.topology);
    const auto powered = w::machine_power(snapshot.state.topology);
    check(powered.collector && powered.processor && snapshot.state.topology.belt_spans.size() == 1 &&
          snapshot.state.topology.material_links.empty(),
          "The cog branch powers both machines and a physical perpendicular shaft span.");
    for (std::size_t n = 0; n < hubs.size(); ++n) {
        const auto id = field<std::string>(hubs[n], "entity");
        check(view.mechanical.motion.at(id) == m::Motion{m::MotionState::rotating, {n == 1 ? -1 : 1, 1}},
              "The cog branch gives each machine its expected signed rotation.");
    }
    for (const auto* shaft : {&first, &last})
        check(view.mechanical.motion.at(field<std::string>(*shaft, "entity")) == m::Motion{m::MotionState::rotating, {1, 1}},
              "Both span pulleys rotate together at the geared rate.");
    const auto encoded = w::encode_checkpoint(profile, snapshot);
    check(std::holds_alternative<V>(encoded), "The complete perpendicular route encodes.");
    const auto decoded = w::decode_checkpoint(profile, "cog-world", std::get<V>(encoded));
    check(std::holds_alternative<w::Snapshot>(decoded), "The complete perpendicular route decodes.");
    auto restored = w::World::restore("cog-world", profile, std::get<w::Snapshot>(decoded));
    check(restored && restored->snapshot().state == snapshot.state,
          "The exact constructed shaft span survives a fresh World restore.");
    accepted(send(*restored, remove(field<std::string>(cogs[2], "entity"), field<I>(cogs[2], "generation"), "remove-belt-cog")));
    const auto interrupted = s::power_view(restored->snapshot().state.topology);
    check(interrupted.mechanical.motion.at(field<std::string>(first, "entity")).state != m::MotionState::rotating &&
          interrupted.mechanical.motion.at(field<std::string>(last, "entity")).state != m::MotionState::rotating,
          "Removing the pulley cog interrupts both shafts without inventing a connection.");
}

void rotated_belt_line() {
    // Exercise all construction orders with a physical X-axis shaft span and
    // +Z top travel. A second cog row powers the press without forcing the
    // two belt pulleys to rotate in opposite directions.
    std::array<int, 3> order{0, 1, 2};
    do {
        for (const I source_rate : {I{1}, I{-1}}) {
            w::Profile profile;
            profile.material = {1, 1, 2}; profile.initial_units = 1;
            profile.actors = {"P", "Q"}; profile.meters_per_grid_unit = 0.1; profile.build_reach = 4;
            profile.waterwheel_rate = {source_rate, 1};
            profile.finite_parts = {{{s::Role::waterwheel, 0, 0}, 1}, {{s::Role::collector, 0, 0}, 1},
                {{s::Role::belt, 0, 0}, 1}, {{s::Role::processor, 0, 0}, 1},
                {{s::Role::shaft, 0, 2}, 2}, {{s::Role::gear, 2, 0}, 7}};
            w::State seed; seed.material.initial_units = 1; seed.material.stock.source = 1;
            seed.material.cargo = {{"P", {}}, {"Q", {}}}; seed.kits = {{"P", profile.finite_parts}, {"Q", {}}};
            auto world = w::World::create("cog-world", profile, seed);
            check(world != nullptr, "A rotated-belt World starts with finite parts.");
            auto wheel = place("rotated-wheel", {4, 0, -4}, "x", 0); wheel.at("role") = V("waterwheel");
            const auto source = accepted(send(*world, wheel));
            O first, last;
            for (const auto n : order) {
                if (n == 1) {
                    auto first_wire = place("rotated-first", {4, 0, 4}, "x", 0);
                    first_wire.at("role") = V("shaft"); first_wire.at("half_span") = V(I{2});
                    first = accepted(send(*world, first_wire));
                    auto last_wire = place("rotated-last", {4, 0, 8}, "x", 0);
                    last_wire.at("role") = V("shaft"); last_wire.at("half_span") = V(I{2});
                    last = accepted(send(*world, last_wire));
                    O span{{"context", V("cog-world")}, {"client", V("P-session")}, {"request", V("rotated-span")},
                        {"actor", V("P")}, {"action", V("place_belt_span")}, {"target", first.at("entity")},
                        {"generation", first.at("generation")}, {"to", last.at("entity")}, {"to_generation", last.at("generation")}};
                    accepted(send(*world, span));
                } else {
                    auto command = place(("rotated-machine-" + std::to_string(n)).c_str(), {4, 0, n == 0 ? 0 : 12}, "x", 0);
                    command.at("role") = V(n == 0 ? "collector" : "processor");
                    command.at("action") = V("place_connected");
                    accepted(send(*world, command));
                }
            }
            check(world->snapshot().state.topology.material_links.empty() && world->snapshot().state.topology.belt_spans.size() == 1,
                  "Each construction order retains a single physical +Z span.");
            const std::array<m::Point, 7> positions{{{0, 0, -4}, {0, 0, 0}, {0, 0, 4},
                                                     {-4, 0, 4}, {-4, 0, 8}, {-4, 0, 12}, {0, 0, 12}}};
            for (std::size_t n = 0; n < positions.size(); ++n)
                accepted(send(*world, place(("rotated-cog-" + std::to_string(n)).c_str(), positions[n], "x", 2)));
            O power{{"context", V("cog-world")}, {"client", V("P-session")}, {"request", V("rotated-power")},
                {"actor", V("P")}, {"action", V("set_drive")}, {"target", source.at("entity")},
                {"generation", source.at("generation")}, {"enabled", V(true)}};
            accepted(send(*world, power));
            const auto running = world->snapshot();
            const auto mechanical = w::machine_power(running.state.topology);
            const auto view = s::power_view(running.state.topology);
            const auto& first_motion = view.mechanical.motion.at(field<std::string>(first, "entity"));
            const auto& last_motion = view.mechanical.motion.at(field<std::string>(last, "entity"));
            check(mechanical.collector && mechanical.processor && first_motion.state == m::MotionState::rotating &&
                      first_motion.rate == m::Rate{source_rate, 1} && last_motion == first_motion,
                  "Both X-axis belt shafts and the press follow the signed cog geometry.");
            auto bad = running;
            for (auto& item : bad.state.topology.parts)
                if (item.geometry.id == field<std::string>(last, "entity")) item.geometry.axis = m::Axis::z;
            check(!w::World::restore("cog-world", profile, bad), "A saved span cannot use mismatched shaft axes.");
            auto restored = w::World::restore("cog-world", profile, running);
            check(restored && restored->snapshot().state == running.state, "Rotated belt and custody survive World restore.");

            auto stop = power; stop.at("request") = V("rotated-stop"); stop.at("enabled") = V(false);
            accepted(send(*restored, stop));
            const auto stopped_stock = restored->snapshot().state.material;
            check(restored->tick().error == w::TransactionError::none &&
                      restored->snapshot().state.material == stopped_stock,
                  "Stopping the rotated line prevents material motion.");
            auto restart = power; restart.at("request") = V("rotated-restart");
            accepted(send(*restored, restart));
            for (int n = 0; n < 12; ++n) check(restored->tick().error == w::TransactionError::none, "Rotated line ticks safely.");
            const auto state = restored->snapshot().state;
            if (source_rate > 0)
                check(state.material.stock.output == 1 && state.material.dropped_material.empty(), "Positive X rotation carries the blank to the press.");
            else {
                const auto span = state.topology.belt_spans.front();
                check(state.material.stock.output == 0 && state.material.dropped_material.empty() &&
                          state.material.belt_lanes.at(span.geometry.id).slots.front() == factory::materials::Cargo{1, 0, {}},
                      "Negative X rotation holds the blank at the collector-facing end.");
                auto reloaded = w::World::restore("cog-world", profile, restored->snapshot());
                check(reloaded != nullptr, "The blocked rotated belt survives restoration.");
                O pickup{{"context", V("cog-world")}, {"client", V("P-session")}, {"request", V("rotated-pickup")},
                    {"actor", V("P")}, {"action", V("recover_belt_slot")},
                    {"target", V(span.geometry.id)}, {"generation", V(span.generation)}, {"slot", V(I{0})},
                    {"expected", V(O{{"raw", V(I{1})}, {"products", V(I{0})}, {"work_lots", V(V::Array{})}})}};
                const auto received = accepted(send(*reloaded, pickup));
                check(field<I>(received, "moved_raw") == 1 && reloaded->snapshot().state.material.dropped_material.empty(),
                      "The blocked blank moves into the actor's finite cargo.");
                auto competing = pickup;
                competing.at("client") = V("Q-session"); competing.at("actor") = V("Q");
                competing.at("request") = V("rotated-competing-pickup");
                const auto refused = send(*reloaded, competing);
                check(refused.completed() && !field<bool>(*refused.result, "accepted") &&
                          field<std::string>(*refused.result, "reason") == "slot_changed",
                      "A competing actor cannot take the same blank twice.");
                check(w::World::restore("cog-world", profile, reloaded->snapshot()) != nullptr,
                      "The rotated pickup and competing refusal remain valid after restoration.");
            }
        }
    } while (std::next_permutation(order.begin(), order.end()));
}

void cross_axis_belt_line() {
    w::Profile profile;
    profile.material = {1, 1, 2};
    profile.initial_units = 1;
    profile.actors = {"P", "Q"};
    profile.meters_per_grid_unit = 0.1;
    profile.build_reach = 4;
    profile.finite_parts = {{{s::Role::waterwheel, 0, 0}, 1}, {{s::Role::collector, 0, 0}, 1},
        {{s::Role::belt, 0, 0}, 1}, {{s::Role::processor, 0, 0}, 1},
        {{s::Role::shaft, 0, 2}, 5},
        {{s::Role::gear, 2, 0}, 6}, {{s::Role::gear, 4, 0}, 2}};
    w::State seed;
    seed.material.initial_units = 1;
    seed.material.stock.source = 1;
    seed.material.cargo = {{"P", {}}, {"Q", {}}};
    seed.kits = {{"P", profile.finite_parts}, {"Q", {}}};
    auto world = w::World::create("cog-world", profile, seed);
    check(world != nullptr, "The cross-axis finite World initializes.");
    const std::array<const char*, 3> roles{"waterwheel", "collector", "processor"};
    std::array<O, 3> hubs;
    for (std::size_t n = 0; n < hubs.size(); ++n) {
        const I x = n == 0 ? -8 : n == 1 ? 0 : 12;
        auto command = place(("cross-machine-" + std::to_string(n)).c_str(),
                             {x, 0, 4}, n ? "z" : "x", 0);
        command.at("role") = V(roles[n]);
        if (n) command.at("action") = V("place_connected");
        hubs[n] = accepted(send(*world, command));
    }
    const auto input = accepted(send(*world, place("cross-input", {-12, 0, 4}, "x", 4)));
    const auto output = accepted(send(*world, place("cross-output", {-8, 0, 8}, "z", 4)));
    std::array<O, 6> small;
    for (std::size_t n = 0; n < small.size(); ++n)
        small[n] = accepted(send(*world, place(("cross-small-" + std::to_string(n)).c_str(),
                                               {static_cast<I>(n) * 4 - 8, 0, 12}, "z", 2)));
    for (const I x : {I{0}, I{4}, I{12}}) {
        auto shaft = place(("cross-machine-shaft-" + std::to_string(x)).c_str(), {x, 0, 8}, "z", 0);
        shaft.at("role") = V("shaft");
        shaft.at("half_span") = V(I{2});
        accepted(send(*world, shaft));
    }
    auto first_command = place("cross-first", {4, 0, 4}, "z", 0);
    first_command.at("role") = V("shaft"); first_command.at("half_span") = V(I{2});
    const auto first = accepted(send(*world, first_command));
    auto last_command = place("cross-last", {8, 0, 4}, "z", 0);
    last_command.at("role") = V("shaft"); last_command.at("half_span") = V(I{2});
    const auto last = accepted(send(*world, last_command));
    O belt{{"context", V("cog-world")}, {"client", V("P-session")}, {"request", V("cross-span")},
        {"actor", V("P")}, {"action", V("place_belt_span")}, {"target", first.at("entity")},
        {"generation", first.at("generation")}, {"to", last.at("entity")}, {"to_generation", last.at("generation")}};
    accepted(send(*world, belt));
    O power{{"context", V("cog-world")}, {"client", V("P-session")}, {"request", V("cross-power")},
        {"actor", V("P")}, {"action", V("set_drive")}, {"target", hubs[0].at("entity")},
        {"generation", hubs[0].at("generation")}, {"enabled", V(true)}};
    accepted(send(*world, power));
    const auto snapshot = world->snapshot();
    const auto view = s::power_view(snapshot.state.topology);
    const auto powered = w::machine_power(snapshot.state.topology);
    check(powered.collector && powered.processor && snapshot.state.topology.material_links.empty() &&
              snapshot.state.topology.belt_spans.size() == 1,
          "A right-angle large-cog transfer powers the collector, physical shaft span and press.");
    check(view.mechanical.motion.at(field<std::string>(hubs[1], "entity")) == m::Motion{m::MotionState::rotating, {1, 1}} &&
              view.mechanical.motion.at(field<std::string>(first, "entity")) == m::Motion{m::MotionState::rotating, {-1, 1}} &&
              view.mechanical.motion.at(field<std::string>(last, "entity")) == m::Motion{m::MotionState::rotating, {-1, 1}} &&
              view.mechanical.motion.at(field<std::string>(hubs[2], "entity")) == m::Motion{m::MotionState::rotating, {-1, 1}},
          "The corner, gear train and both belt pulleys retain their exact signed rotations.");
    const auto encoded = w::encode_checkpoint(profile, snapshot);
    check(std::holds_alternative<V>(encoded), "The cross-axis route encodes.");
    const auto decoded = w::decode_checkpoint(profile, "cog-world", std::get<V>(encoded));
    check(std::holds_alternative<w::Snapshot>(decoded), "The cross-axis route decodes.");
    auto restored = w::World::restore("cog-world", profile, std::get<w::Snapshot>(decoded));
    check(restored && restored->snapshot().state == snapshot.state &&
              s::power_view(restored->snapshot().state.topology).mechanical.motion.at(field<std::string>(last, "entity")).state == m::MotionState::rotating,
          "The right-angle route survives fresh World restoration.");
    accepted(send(*restored, remove(field<std::string>(output, "entity"), field<I>(output, "generation"), "cross-remove")));
    check(s::power_view(restored->snapshot().state.topology).mechanical.motion.at(field<std::string>(last, "entity")).state != m::MotionState::rotating,
          "Removing the right-angle output cog interrupts the belt.");
}
void geared_overload_and_recovery() {
    namespace mat = factory::materials;
    w::Profile profile;
    profile.material = {1, 1, 80}; profile.initial_units = 1; profile.actors = {"P", "Q"};
    profile.meters_per_grid_unit = 0.1; profile.build_reach = 4;
    profile.finite_parts = {{{s::Role::waterwheel, 0, 0}, 1}, {{s::Role::collector, 0, 0}, 1},
        {{s::Role::processor, 0, 0}, 1}, {{s::Role::gear, 2, 0}, 2}, {{s::Role::gear, 4, 0}, 2}};
    w::State state;
    state.material.initial_units = 1; state.material.stock.source = 0;
    state.material.processing = mat::WorkLot{1, {1, 80}, 80}; state.material.next_work_id = 2;
    state.material.cargo = {{"P", {}}, {"Q", {}}}; state.kits = {{"P", {}}, {"Q", {}}};
    state.topology.parts = {
        {{"wheel", m::Kind::hub, {0, 0, -4}, m::Axis::z, 0, 0}, 1, s::Role::waterwheel},
        {{"large1", m::Kind::gear, {0, 0, 0}, m::Axis::z, 4, 0}, 1, s::Role::gear},
        {{"small1", m::Kind::gear, {4, 4, 0}, m::Axis::z, 2, 0}, 1, s::Role::gear},
        {{"large2", m::Kind::gear, {4, 4, 4}, m::Axis::z, 4, 0}, 1, s::Role::gear},
        {{"small2", m::Kind::gear, {8, 8, 4}, m::Axis::z, 2, 0}, 1, s::Role::gear},
        {{"press", m::Kind::hub, {8, 8, 8}, m::Axis::z, 0, 0}, 1, s::Role::processor},
        {{"collector", m::Kind::hub, {8, 8, 12}, m::Axis::z, 0, 0}, 1, s::Role::collector}};
    state.topology.sources = {{"wheel", {1, 1}}}; state.topology.drive_enabled = true;
    for (const auto& item : state.topology.parts) state.issued_entities.emplace(item.geometry.id, 1);
    const auto stalled = w::drive_power(state.topology);
    check(stalled.mechanical.motion.at("press").state == m::MotionState::stalled &&
              stalled.load.at("press").overloaded && stalled.load.at("press").impact == 48 &&
              stalled.load.at("press").capacity == 32,
          "Two speed-doubling cog pairs overload the connected machines.");
    auto reverse = state.topology;
    reverse.sources[0].rate = {-1, 1};
    const auto reversed = w::drive_power(reverse);
    check(reversed.load.at("press").overloaded && reversed.load.at("press").impact == 48 &&
              reversed.load.at("press").capacity == 32,
          "Reverse rotation has the same load and capacity magnitudes.");
    auto extra = state.topology;
    extra.parts.push_back({{"wheel2", m::Kind::hub, {0, 0, -8}, m::Axis::z, 0, 0}, 1, s::Role::waterwheel});
    extra.sources.push_back({"wheel2", {1, 1}});
    const auto reinforced = w::drive_power(extra);
    check(reinforced.mechanical.motion.at("press").rate == m::Rate{4, 1} &&
              !reinforced.load.at("press").overloaded && reinforced.load.at("press").capacity == 64,
          "A second connected source contributes capacity and restores rotation.");
    auto world = w::World::create("cog-world", profile, state);
    check(world && world->tick().error == w::TransactionError::none && world->snapshot().state == state,
          "Overload pauses work without losing or modifying its material.");
    const auto overloaded_save = w::encode_checkpoint(profile, world->snapshot());
    check(std::holds_alternative<V>(overloaded_save), "The overloaded network checkpoints.");
    const auto overloaded_decoded = w::decode_checkpoint(profile, "cog-world", std::get<V>(overloaded_save));
    check(std::holds_alternative<w::Snapshot>(overloaded_decoded), "The overloaded checkpoint decodes.");
    auto overloaded_restored = w::World::restore("cog-world", profile, std::get<w::Snapshot>(overloaded_decoded));
    check(overloaded_restored && overloaded_restored->tick().error == w::TransactionError::none &&
              overloaded_restored->snapshot().state.material.processing->remaining_ticks == 80 &&
              w::drive_power(overloaded_restored->snapshot().state.topology).load.at("press").overloaded,
          "Restoring an overloaded network preserves the stalled work and recomputes overload.");
    accepted(send(*world, remove("collector", 1, "remove-overload")));
    const auto released = w::drive_power(world->snapshot().state.topology);
    check(!released.load.at("press").overloaded && released.load.at("press").impact == 32 &&
              world->tick().error == w::TransactionError::none &&
              world->snapshot().state.material.processing->remaining_ticks == 76,
          "Removing the excess load restores the geared press at equal capacity.");
    const auto encoded = w::encode_checkpoint(profile, world->snapshot());
    check(std::holds_alternative<V>(encoded), "The recovered network checkpoints.");
    const auto decoded = w::decode_checkpoint(profile, "cog-world", std::get<V>(encoded));
    check(std::holds_alternative<w::Snapshot>(decoded), "The recovered network checkpoint decodes.");
    auto restored = w::World::restore("cog-world", profile, std::get<w::Snapshot>(decoded));
    check(restored && restored->tick().error == w::TransactionError::none &&
              restored->snapshot().state.material.processing->remaining_ticks == 72,
          "A fresh World recomputes load and continues the same work.");
}
} // namespace

int main() {
    try {
        construction(false);
        construction(true);
        geared_processor(false);
        geared_processor(true);
        perpendicular_belt_line();
        rotated_belt_line();
        cross_axis_belt_line();
        geared_overload_and_recovery();
        std::cout << checks << " native World cog construction checks passed.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL after " << checks << " checks: " << error.what() << '\n';
        return 1;
    }
}
