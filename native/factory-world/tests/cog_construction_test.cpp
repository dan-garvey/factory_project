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
    profile.finite_parts = {{{s::Role::waterwheel, 0, 0}, 1}, {{s::Role::belt, 0, 0}, 1},
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
    auto belt = output;
    belt[static_cast<std::size_t>(output_axis)] += 4;
    seed.topology.parts = {
        {{"wheel", m::Kind::hub, wheel, input_axis, 0, 0}, 1, s::Role::waterwheel},
        {{"belt", m::Kind::hub, belt, output_axis, 0, 0}, 1, s::Role::belt},
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
    check(!w::machine_power(world->snapshot().state.topology).belt, "One cog does not power the remote belt.");
    const auto second_command = place("second", output, "z", 4);
    const auto second = accepted(send(*world, second_command));
    auto snapshot = world->snapshot();
    const auto view = s::power_view(snapshot.state.topology);
    const m::Rate expected = corner ? m::Rate{1, 1} : m::Rate{-1, 2};
    check(view.mechanical.motion.at("belt") == m::Motion{m::MotionState::rotating, expected} &&
          w::machine_power(snapshot.state.topology).belt, "The actual World powers the belt at the expected signed rate.");
    check(snapshot.state.kits.at("P").at({s::Role::gear, 4, 0}) == 0,
          "Construction consumes the exact large cog specifications.");
    const auto encoded = w::encode_checkpoint(profile, snapshot);
    check(std::holds_alternative<V>(encoded), "The built World encodes its full checkpoint.");
    const auto decoded = w::decode_checkpoint(profile, "cog-world", std::get<V>(encoded));
    check(std::holds_alternative<w::Snapshot>(decoded), "The constructed train decodes from its checkpoint.");
    auto restored = w::World::restore("cog-world", profile, std::get<w::Snapshot>(decoded));
    check(restored != nullptr && restored->snapshot().state == snapshot.state &&
          w::machine_power(restored->snapshot().state.topology).belt,
          "A fresh World retains constructed custody and its powered geometry.");
    const auto replay = send(*restored, first_command);
    check(replay.completed() && field<bool>(*replay.result, "duplicate") &&
          field<std::string>(*replay.result, "entity") == field<std::string>(first, "entity"),
          "A historical placement retry does not spend or create another part.");
    const auto id = field<std::string>(second, "entity");
    const auto generation = field<I>(second, "generation");
    accepted(send(*restored, remove(id, generation, "remove")));
    snapshot = restored->snapshot();
    check(!w::machine_power(snapshot.state.topology).belt &&
          snapshot.state.kits.at("Q").at({s::Role::gear, 4, 0}) == 1,
          "Q removes the large cog, disconnecting the belt and receiving the exact refund.");
    auto rebuilt = second_command;
    rebuilt.at("client") = V("Q-session"); rebuilt.at("actor") = V("Q"); rebuilt.at("request") = V("rebuild");
    const auto replacement = accepted(send(*restored, rebuilt));
    check(field<std::string>(replacement, "entity") != id &&
          w::machine_power(restored->snapshot().state.topology).belt,
          "Q rebuilds a fresh identity and restores belt power.");
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
    profile.material = {1, 1, 2};
    profile.initial_units = 1;
    profile.actors = {"P", "Q"};
    profile.meters_per_grid_unit = 0.1;
    profile.build_reach = 4;
    profile.finite_parts = {{{s::Role::waterwheel, 0, 0}, 1}, {{s::Role::collector, 0, 0}, 1},
        {{s::Role::belt, 0, 0}, 1}, {{s::Role::processor, 0, 0}, 1},
        {{s::Role::shaft, 0, 2}, 4}, {{s::Role::gear, 2, 0}, 4}};
    w::State seed;
    seed.material.initial_units = 1;
    seed.material.stock.source = 1;
    seed.material.cargo = {{"P", {}}, {"Q", {}}};
    seed.kits = {{"P", profile.finite_parts}, {"Q", {}}};
    auto world = w::World::create("cog-world", profile, seed);
    check(world != nullptr, "The finite perpendicular-line World initializes.");
    const auto before = world->snapshot().state;
    auto wrong = place("vertical-belt", {4, 0, 4}, "y", 0);
    wrong.at("role") = V("belt"); wrong.at("action") = V("place_connected");
    const auto rejected = send(*world, wrong);
    check(rejected.completed() && !field<bool>(*rejected.result, "accepted") &&
              field<std::string>(*rejected.result, "reason") == "invalid_belt_axis" && world->snapshot().state == before,
          "The authoritative World refuses a vertical belt spindle without consuming its part.");
    const std::array<const char*, 4> roles{"waterwheel", "collector", "belt", "processor"};
    std::array<O, 4> hubs, cogs;
    for (std::size_t n = 0; n < roles.size(); ++n) {
        const I x = static_cast<I>(n) * 4 - 4;
        auto machine = place(("machine-" + std::to_string(n)).c_str(), {x, 0, 4}, "z", 0);
        machine.at("role") = V(roles[n]);
        if (n != 0) machine.at("action") = V("place_connected");
        hubs[n] = accepted(send(*world, machine));
        cogs[n] = accepted(send(*world, place(("cog-" + std::to_string(n)).c_str(), {x, 0, 8}, "z", 2)));
    }
    O power{{"context", V("cog-world")}, {"client", V("P-session")}, {"request", V("power")},
        {"actor", V("P")}, {"action", V("set_drive")}, {"target", hubs[0].at("entity")},
        {"generation", hubs[0].at("generation")}, {"enabled", V(true)}};
    accepted(send(*world, power));
    const auto snapshot = world->snapshot();
    auto invalid_snapshot = snapshot;
    for (auto& part : invalid_snapshot.state.topology.parts)
        if (part.role == s::Role::belt) part.geometry.axis = m::Axis::y;
    check(!w::World::restore("cog-world", profile, invalid_snapshot),
          "A checkpoint cannot introduce a vertical belt spindle.");
    const auto view = s::power_view(snapshot.state.topology);
    const auto powered = w::machine_power(snapshot.state.topology);
    check(powered.collector && powered.belt && powered.processor && snapshot.state.topology.material_links.size() == 2,
          "Four adjacent small cogs and touching perpendicular axles power the full connected material line.");
    for (std::size_t n = 0; n < hubs.size(); ++n) {
        const auto id = field<std::string>(hubs[n], "entity");
        check(view.mechanical.motion.at(id) == m::Motion{m::MotionState::rotating, {n % 2 ? -1 : 1, 1}},
              "Each adjacent cog reverses the signed shaft rotation.");
    }
    const auto encoded = w::encode_checkpoint(profile, snapshot);
    check(std::holds_alternative<V>(encoded), "The complete perpendicular route encodes.");
    const auto decoded = w::decode_checkpoint(profile, "cog-world", std::get<V>(encoded));
    check(std::holds_alternative<w::Snapshot>(decoded), "The complete perpendicular route decodes.");
    auto restored = w::World::restore("cog-world", profile, std::get<w::Snapshot>(decoded));
    check(restored && restored->snapshot().state == snapshot.state && w::machine_power(restored->snapshot().state.topology).belt,
          "The exact constructed route survives a fresh World restore.");
    accepted(send(*restored, remove(field<std::string>(cogs[2], "entity"), field<I>(cogs[2], "generation"), "remove-belt-cog")));
    check(!w::machine_power(restored->snapshot().state.topology).belt,
          "Removing the belt's cog interrupts its power rather than inventing a connection.");
}

void rotated_belt_line() {
    // Each ordering exercises automatic material-port discovery when the belt
    // or either neighbor is placed last. The 3D layout uses an X axle and +Z
    // top travel, with one connected small cog per independently placed hub.
    std::array<int, 3> order{0, 1, 2};
    do {
        for (const I source_rate : {I{1}, I{-1}}) {
            w::Profile profile;
            profile.material = {1, 1, 2}; profile.initial_units = 1;
            profile.actors = {"P", "Q"}; profile.meters_per_grid_unit = 0.1; profile.build_reach = 4;
            profile.waterwheel_rate = {source_rate, 1};
            profile.finite_parts = {{{s::Role::waterwheel, 0, 0}, 1}, {{s::Role::collector, 0, 0}, 1},
                {{s::Role::belt, 0, 0}, 1}, {{s::Role::processor, 0, 0}, 1}, {{s::Role::gear, 2, 0}, 4}};
            w::State seed; seed.material.initial_units = 1; seed.material.stock.source = 1;
            seed.material.cargo = {{"P", {}}, {"Q", {}}}; seed.kits = {{"P", profile.finite_parts}, {"Q", {}}};
            auto world = w::World::create("cog-world", profile, seed);
            check(world != nullptr, "A rotated-belt World starts with finite parts.");
            auto wheel = place("rotated-wheel", {4, 0, -4}, "x", 0); wheel.at("role") = V("waterwheel");
            const auto source = accepted(send(*world, wheel));
            constexpr std::array<const char*, 3> roles{"collector", "belt", "processor"};
            for (const auto n : order) {
                auto command = place(("rotated-machine-" + std::to_string(n)).c_str(), {4, 0, n * 4}, "x", 0);
                command.at("role") = V(roles[n]); command.at("action") = V("place_connected");
                accepted(send(*world, command));
            }
            check(world->snapshot().state.topology.material_links.size() == 2,
                  "All construction orders connect only the adjacent +Z material ports.");
            for (int n = -1; n < 3; ++n)
                accepted(send(*world, place(("rotated-cog-" + std::to_string(n)).c_str(), {0, 0, n * 4}, "x", 2)));
            O power{{"context", V("cog-world")}, {"client", V("P-session")}, {"request", V("rotated-power")},
                {"actor", V("P")}, {"action", V("set_drive")}, {"target", source.at("entity")},
                {"generation", source.at("generation")}, {"enabled", V(true)}};
            accepted(send(*world, power));
            const auto running = world->snapshot();
            const auto mechanical = w::machine_power(running.state.topology);
            check(mechanical.collector && mechanical.belt && mechanical.processor && mechanical.belt_forward == (source_rate > 0),
                  "X-axis belt power and signed forward motion follow the actual cog geometry.");
            auto bad = running;
            for (auto& item : bad.state.topology.parts) if (item.role == s::Role::belt) item.geometry.axis = m::Axis::z;
            check(!w::World::restore("cog-world", profile, bad), "A saved +Z route cannot claim an X-travel belt.");
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
                check(state.material.stock.output == 0 && state.material.dropped_material.contains({4, 0, 2}),
                      "Negative X rotation deposits the blank at the -Z end.");
                auto reloaded = w::World::restore("cog-world", profile, restored->snapshot());
                check(reloaded != nullptr, "The rotated reverse drop survives restoration.");
                O pickup{{"context", V("cog-world")}, {"client", V("P-session")}, {"request", V("rotated-pickup")},
                    {"actor", V("P")}, {"action", V("pickup_material")},
                    {"center", V(V::Array{V(I{4}), V(I{0}), V(I{2})})},
                    {"expected", V(O{{"raw", V(I{1})}, {"products", V(I{0})}, {"work_lots", V(V::Array{})}})}};
                const auto received = accepted(send(*reloaded, pickup));
                check(field<I>(received, "moved_raw") == 1 && reloaded->snapshot().state.material.dropped_material.empty(),
                      "The reverse-end blank moves into the actor's finite cargo.");
                auto competing = pickup;
                competing.at("client") = V("Q-session"); competing.at("actor") = V("Q");
                competing.at("request") = V("rotated-competing-pickup");
                const auto refused = send(*reloaded, competing);
                check(refused.completed() && !field<bool>(*refused.result, "accepted") &&
                          field<std::string>(*refused.result, "reason") == "unavailable_drop",
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
        {{s::Role::shaft, 0, 2}, 3},
        {{s::Role::gear, 2, 0}, 5}, {{s::Role::gear, 4, 0}, 2}};
    w::State seed;
    seed.material.initial_units = 1;
    seed.material.stock.source = 1;
    seed.material.cargo = {{"P", {}}, {"Q", {}}};
    seed.kits = {{"P", profile.finite_parts}, {"Q", {}}};
    auto world = w::World::create("cog-world", profile, seed);
    check(world != nullptr, "The cross-axis finite World initializes.");
    const std::array<const char*, 4> roles{"waterwheel", "collector", "belt", "processor"};
    std::array<O, 4> hubs;
    for (std::size_t n = 0; n < hubs.size(); ++n) {
        const I x = n ? static_cast<I>(n) * 4 - 4 : -8;
        auto command = place(("cross-machine-" + std::to_string(n)).c_str(),
                             {x, 0, 4}, n ? "z" : "x", 0);
        command.at("role") = V(roles[n]);
        if (n) command.at("action") = V("place_connected");
        hubs[n] = accepted(send(*world, command));
    }
    const auto input = accepted(send(*world, place("cross-input", {-12, 0, 4}, "x", 4)));
    const auto output = accepted(send(*world, place("cross-output", {-8, 0, 8}, "z", 4)));
    std::array<O, 5> small;
    for (std::size_t n = 0; n < small.size(); ++n)
        small[n] = accepted(send(*world, place(("cross-small-" + std::to_string(n)).c_str(),
                                               {static_cast<I>(n) * 4 - 8, 0, 12}, "z", 2)));
    for (std::size_t n = 1; n < hubs.size(); ++n) {
        auto shaft = place(("cross-machine-shaft-" + std::to_string(n)).c_str(),
                           {static_cast<I>(n - 1) * 4, 0, 8}, "z", 0);
        shaft.at("role") = V("shaft");
        shaft.at("half_span") = V(I{2});
        accepted(send(*world, shaft));
    }
    O power{{"context", V("cog-world")}, {"client", V("P-session")}, {"request", V("cross-power")},
        {"actor", V("P")}, {"action", V("set_drive")}, {"target", hubs[0].at("entity")},
        {"generation", hubs[0].at("generation")}, {"enabled", V(true)}};
    accepted(send(*world, power));
    const auto snapshot = world->snapshot();
    const auto view = s::power_view(snapshot.state.topology);
    const auto powered = w::machine_power(snapshot.state.topology);
    check(powered.collector && powered.belt && powered.processor && snapshot.state.topology.material_links.size() == 2,
          "A right-angle large-cog transfer powers all three perpendicular-axis machines.");
    for (std::size_t n = 1; n < hubs.size(); ++n) {
        const auto id = field<std::string>(hubs[n], "entity");
        check(view.mechanical.motion.at(id) == m::Motion{m::MotionState::rotating, {n % 2 ? 1 : -1, 1}},
              "The right-angle transfer and small cog train retain their signed rotations.");
    }
    const auto encoded = w::encode_checkpoint(profile, snapshot);
    check(std::holds_alternative<V>(encoded), "The cross-axis route encodes.");
    const auto decoded = w::decode_checkpoint(profile, "cog-world", std::get<V>(encoded));
    check(std::holds_alternative<w::Snapshot>(decoded), "The cross-axis route decodes.");
    auto restored = w::World::restore("cog-world", profile, std::get<w::Snapshot>(decoded));
    check(restored && restored->snapshot().state == snapshot.state && w::machine_power(restored->snapshot().state.topology).belt,
          "The right-angle route survives fresh World restoration.");
    accepted(send(*restored, remove(field<std::string>(output, "entity"), field<I>(output, "generation"), "cross-remove")));
    check(!w::machine_power(restored->snapshot().state.topology).belt,
          "Removing the right-angle output cog interrupts the belt.");
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
        std::cout << checks << " native World cog construction checks passed.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL after " << checks << " checks: " << error.what() << '\n';
        return 1;
    }
}
