#include "factory/checkpoint.hpp"

#include <iostream>
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
    check(delivery.completed() && field<bool>(*delivery.result, "accepted"), "A finite World command must succeed.");
    return *delivery.result;
}
void construction(bool corner) {
    const m::Point input{0, 0, 0};
    const m::Point output = corner ? m::Point{4, 0, 4} : m::Point{4, 4, 0};
    const auto output_axis = corner ? m::Axis::x : m::Axis::z;
    const I input_teeth = corner ? 4 : 2;
    w::Profile profile;
    profile.material = {1, 1, 2};
    profile.initial_units = 1;
    profile.actors = {"P", "Q"};
    profile.meters_per_grid_unit = 0.1;
    profile.build_reach = 4;
    profile.finite_parts = {{{s::Role::waterwheel, 0, 0}, 1}, {{s::Role::belt, 0, 0}, 1},
                            {{s::Role::shaft, 0, 1}, 2}, {{s::Role::gear, 4, 0}, corner ? 2 : 1}};
    if (!corner) profile.finite_parts.emplace(s::PartSpec{s::Role::gear, 2, 0}, 1);
    w::State seed;
    seed.material.initial_units = 1;
    seed.material.stock.source = 1;
    seed.material.cargo = {{"P", {}}, {"Q", {}}};
    seed.kits = {{"P", {{{s::Role::gear, 4, 0}, corner ? 2 : 1}}}, {"Q", {}}};
    if (!corner) seed.kits.at("P").emplace(s::PartSpec{s::Role::gear, 2, 0}, 1);
    seed.topology.parts = {
        {{"wheel", m::Kind::hub, input, m::Axis::z, 0, 0}, 1, s::Role::waterwheel},
        {{"in-shaft", m::Kind::shaft, input, m::Axis::z, 0, 1}, 1, s::Role::shaft},
        {{"belt", m::Kind::hub, output, output_axis, 0, 0}, 1, s::Role::belt},
        {{"out-shaft", m::Kind::shaft, output, output_axis, 0, 1}, 1, s::Role::shaft},
    };
    seed.topology.sources = {{"wheel", {1, 1}}};
    seed.topology.drive_enabled = true;
    for (const auto& item : seed.topology.parts) seed.issued_entities.emplace(item.geometry.id, item.generation);
    auto world = w::World::create("cog-world", profile, seed);
    check(world != nullptr, "The finite two-actor fixture creates the single World.");
    const auto first_command = place("first", input, "z", input_teeth);
    const auto first = accepted(send(*world, first_command));
    check(!w::machine_power(world->snapshot().state.topology).belt, "One cog does not power the remote belt.");
    const auto second_command = place("second", output, corner ? "x" : "z", 4);
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
    const std::array<const char*, 4> roles{"waterwheel", "collector", "belt", "processor"};
    std::array<O, 4> hubs, cogs;
    for (std::size_t n = 0; n < roles.size(); ++n) {
        const I x = static_cast<I>(n) * 4 - 4;
        auto machine = place(("machine-" + std::to_string(n)).c_str(), {x, 0, 4}, "z", 0);
        machine.at("role") = V(roles[n]);
        if (n != 0) machine.at("action") = V("place_connected");
        hubs[n] = accepted(send(*world, machine));
        cogs[n] = accepted(send(*world, place(("cog-" + std::to_string(n)).c_str(), {x, 0, 8}, "z", 2)));
        O shaft{{"context", V("cog-world")}, {"client", V("P-session")},
            {"request", V("shaft-" + std::to_string(n))}, {"actor", V("P")}, {"action", V("shaft_between")},
            {"target", hubs[n].at("entity")}, {"generation", hubs[n].at("generation")},
            {"to", cogs[n].at("entity")}, {"to_generation", cogs[n].at("generation")}};
        accepted(send(*world, shaft));
    }
    O power{{"context", V("cog-world")}, {"client", V("P-session")}, {"request", V("power")},
        {"actor", V("P")}, {"action", V("set_drive")}, {"target", hubs[0].at("entity")},
        {"generation", hubs[0].at("generation")}, {"enabled", V(true)}};
    accepted(send(*world, power));
    const auto snapshot = world->snapshot();
    const auto view = s::power_view(snapshot.state.topology);
    const auto powered = w::machine_power(snapshot.state.topology);
    check(powered.collector && powered.belt && powered.processor && snapshot.state.topology.material_links.size() == 2,
          "Four adjacent small cogs and four perpendicular shafts power the full connected material line.");
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
} // namespace

int main() {
    try {
        construction(false);
        construction(true);
        perpendicular_belt_line();
        std::cout << checks << " native World cog construction checks passed.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL after " << checks << " checks: " << error.what() << '\n';
        return 1;
    }
}
