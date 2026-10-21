#include "factory/geared_scenarios.hpp"
#include "factory/repair_workbench.hpp"

#include <algorithm>
#include <array>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>

namespace r = factory::geared_scenarios;
namespace w = factory::world;
namespace a = factory::authority;
namespace s = factory::stationary;
namespace g = factory::mechanics;
using V = factory::values::Value;
using I = a::Integer;
namespace {
int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

struct Fixture {
    std::string context;
    w::Profile profile;
    std::unique_ptr<w::World> simulation;
    I request{};
};

Fixture fixture(const std::string& id, const std::string& suffix) {
    const auto content = r::make(id);
    check(content.has_value(), "Each authored catalogue name resolves to trusted new content.");
    const std::string context = id + '-' + suffix;
    Fixture result{context, content->profile, w::World::create(context, content->profile, content->seed)};
    if (!result.simulation || !w::validate(result.profile, result.simulation->snapshot()))
        throw std::runtime_error("The gear seed " + id + " fails native World initialization.");
    check(true, "Each complete gear seed passes the actual native World initializer.");
    const auto state = result.simulation->snapshot().state;
    check(state.material.initial_units == 16 && state.material.stock.source == 16 && state.material.cargo.at("P").products == 0,
          "Every new puzzle starts with original finite stock and no credited product.");
    const auto power = w::machine_power(state.topology);
    check(!power.collector && power.processor &&
          s::power_view(state.topology).mechanical.motion.at("pulley-first").state == g::MotionState::rotating,
          "Only the collector's geometric drive is incomplete.");
    return result;
}

a::Object send(Fixture& fixture, a::Object command, a::Point position) {
    command.emplace("context", V(fixture.context));
    command.emplace("client", V("gear-fixture"));
    command.emplace("actor", V("P"));
    command.emplace("request", V("action-" + std::to_string(++fixture.request)));
    // Explicit supplied fixture observations, not an engine body/Session or
    // ordinary player movement witness. World still derives and checks reach.
    const auto delivery = fixture.simulation->command({"P", "gear-fixture"}, command,
        [position](const std::string& actor) -> std::optional<a::ActorCut> {
            return a::ActorCut{actor, position, 1, true, 4};
        });
    check(delivery.completed(), "Each well-formed native command returns an original outcome.");
    check(w::validate(fixture.profile, fixture.simulation->snapshot()), "Accepted or refused commands preserve the complete finite World.");
    return *delivery.result;
}

bool accepted(const a::Object& result) { return std::get<bool>(result.at("accepted").storage()); }
std::string reason(const a::Object& result) { return std::get<std::string>(result.at("reason").storage()); }

a::Object place(Fixture& fixture, const char* role, g::Point point, const char* axis, I dimension, a::Point position) {
    return send(fixture, {{"action", V("place")}, {"role", V(role)},
        {"center", V(V::Array{V(point[0]), V(point[1]), V(point[2])})}, {"axis", V(axis)},
        {"teeth", V(std::string_view(role) == "gear" ? dimension : I{0})},
        {"half_span", V(std::string_view(role) == "shaft" ? dimension : I{0})}}, position);
}

void ticks(Fixture& fixture, int number) {
    for (int tick = 0; tick < number; ++tick) {
        check(fixture.simulation->tick().error == w::TransactionError::none &&
              w::validate(fixture.profile, fixture.simulation->snapshot()), "Native production stepping retains all finite invariants.");
    }
}

void paused(Fixture& fixture) {
    const auto material = fixture.simulation->snapshot().state.material;
    ticks(fixture, 8);
    check(fixture.simulation->snapshot().state.material == material,
          "Incomplete geometric drive cannot extract stock, fabricate output or advance a hidden process.");
}

void repair_power(Fixture& fixture, g::Rate rate) {
    const auto state = fixture.simulation->snapshot().state;
    const auto power = w::machine_power(state.topology);
    const auto motion = s::power_view(state.topology).mechanical;
    check(power.collector && power.processor && motion.motion.at("pulley-first").state == g::MotionState::rotating &&
          motion.motion.at("collector").rate == rate,
          "The repaired geometry supplies the exact expected signed rate and real local production power.");
    for (const auto& [specification, amount] : state.kits.at("P")) {
        (void)specification;
        check(amount == 0, "The completed repair consumes only the original carried parts.");
    }
}

void finish(Fixture& fixture) {
    const auto parts = fixture.simulation->snapshot().state.topology.parts;
    const auto press = std::find_if(parts.begin(), parts.end(), [](const auto& part) { return part.geometry.id == "processor"; });
    check(press != parts.end(), "The actual processor is present for retrieval.");
    const a::Point at{static_cast<double>(press->geometry.center[0]), static_cast<double>(press->geometry.center[1]),
                      static_cast<double>(press->geometry.center[2])};
    for (int tick = 0; tick < 64 && fixture.simulation->snapshot().state.material.cargo.at("P").products < 4; ++tick) {
        if (fixture.simulation->snapshot().state.material.stock.output > 0)
            check(accepted(send(fixture, {{"action", V("collect")}, {"target", V("processor")},
                {"generation", V(I{1})}, {"amount", V(I{1})}}, at)), "Nearby retrieval moves one actual finite product to the actor.");
        ticks(fixture, 1);
    }
    const auto saved = fixture.simulation->snapshot();
    check(saved.state.material.cargo.at("P").products == 4 && saved.state.material.cargo.at("Q").products == 0 &&
          saved.state.material.initial_units == 16 && saved.state.material.stock.source < 16,
          "The repaired collector makes four real carried plates from the original stock without shared or invented credit.");
    auto restored = w::World::restore(fixture.context, fixture.profile, saved);
    check(restored && restored->snapshot().state == saved.state,
          "Existing validated native restore retains new gear identities, kits and material; no file persistence is claimed.");
}

void remove_wrong(Fixture& fixture, a::Point position) {
    const auto before = fixture.simulation->snapshot().state.material;
    check(accepted(send(fixture, {{"action", V("remove")}, {"target", V("native-part-1")}, {"generation", V(I{1})}}, position)),
          "The misplaced empty part can be removed through ordinary native commands.");
    const auto state = fixture.simulation->snapshot().state;
    check(state.material == before && state.issued_entities.contains("native-part-1") && state.next_entity_serial == 2,
          "Refund retains all material and the issued historical identity instead of rewinding allocation.");
}

void idler() {
    auto world = fixture("gear-idler", "native");
    paused(world);
    const auto far = place(world, "gear", {-4, 0, 0}, "z", 2, {100, 0, 0});
    check(!accepted(far) && reason(far) == "out_of_reach", "A remote placement cannot spend the carried gear.");
    const auto unavailable = place(world, "gear", {-4, 0, 0}, "z", 3, {-4, 0, 0});
    check(!accepted(unavailable) && reason(unavailable) == "unavailable_part", "Changing the requested tooth count cannot transform finite inventory.");
    check(accepted(place(world, "gear", {-4, 4, 0}, "z", 2, {-4, 0, 0})), "A plausible but off-line placement is a real retained construction.");
    paused(world);
    remove_wrong(world, {-4, 0, 0});
    const auto repair = place(world, "gear", {-4, 0, 0}, "z", 2, {-4, 0, 0});
    check(accepted(repair) && std::get<std::string>(repair.at("entity").storage()) == "native-part-2",
          "Rebuilding the refunded gear uses a fresh identity rather than retargeting the removed part.");
    repair_power(world, {-1, 1});
    finish(world);
}

void bend(int direction) {
    auto world = fixture("gear-bend", direction > 0 ? "north" : "south");
    paused(world);
    const g::Point first = direction > 0 ? g::Point{-12, 0, 0} : g::Point{-8, 0, -4};
    const g::Point second = direction > 0 ? g::Point{-12, 0, 4} : g::Point{-8, 0, 0};
    check(accepted(place(world, "gear", first, "y", 2, {static_cast<double>(first[0]), 0, static_cast<double>(first[2])})),
          "The first carried cog can mesh along either mirrored route.");
    paused(world);
    check(accepted(place(world, "gear", second, "y", 2, {static_cast<double>(second[0]), 0, static_cast<double>(second[2])})),
          "The second cog completes the equal-gear route without arbitrary drive links.");
    repair_power(world, {1, 1});
    finish(world);
}

void riser() {
    auto world = fixture("gear-riser", "native");
    const auto initial = s::power_view(world.simulation->snapshot().state.topology).mechanical;
    check(initial.motion.at("gear-low").rate == g::Rate{1, 1} &&
          initial.motion.at("gear-high").state == g::MotionState::unpowered,
          "Coaxial gears on different vertical planes do not magically share rotation.");
    paused(world);
    check(accepted(place(world, "shaft", {-4, 4, 0}, "y", 2, {-4, 0, 0})), "A high shaft can be built but cannot span the lower plane.");
    paused(world);
    remove_wrong(world, {-4, 0, 0});
    check(accepted(place(world, "shaft", {-4, -4, 0}, "y", 2, {-4, 0, 0})), "Moving the same refunded shaft couples both planes within actual 3D reach.");
    const auto connected = s::power_view(world.simulation->snapshot().state.topology).mechanical;
    check(connected.motion.at("gear-high").rate == g::Rate{1, 1}, "The upper cog now derives rotation through the actual shared shaft.");
    repair_power(world, {-1, 1});
    finish(world);
}

struct Result { int code; std::string output, errors; };
Result run(std::string_view id, const std::string& commands) {
    const std::array<std::string_view, 2> arguments{"play", id};
    std::istringstream input(commands);
    std::ostringstream output, errors;
    const auto code = factory::repair_scenarios::workbench(arguments, input, output, errors);
    return {code, output.str(), errors.str()};
}

std::string plates() {
    std::string result;
    for (int plate = 0; plate < 4; ++plate) result += "wait 8\ncollect processor\n";
    return result;
}

void terminal() {
    const auto idler = run("gear-idler", "walk west 4\nplace gear -4 0 0 z 3\nplace gear -4 4 0 z 2\nwait 8\n"
        "remove native-part-1\nplace gear -4 0 0 z 2\ninspect\nwalk east 8\nwalk east 6\nwalk south 4\n" + plates());
    check(idler.code == 0 && idler.errors.empty() && idler.output.find("Held: unavailable_part") != std::string::npos &&
          idler.output.find("native-part-2 generation=2 gear at=-4,0,0 axis=z teeth=2 rotation=rotating rate=1/1") != std::string::npos,
          "Interactive gear construction exposes finite refusal, correction, fresh identity and actual derived motion.");
    const auto bend = run("gear-bend", "place gear -12 0 0 y 2\nwalk west 8\nwalk west 4\nplace gear -12 0 0 y 2\n"
        "wait 8\nplace gear -12 0 4 y 2\ninspect\nwalk east 8\nwalk east 8\nwalk north 4\n" + plates());
    check(bend.code == 0 && bend.errors.empty() && bend.output.find("Held: out_of_reach") != std::string::npos &&
          bend.output.find("collector generation=1 collector at=-8,4,4 axis=y rotation=rotating rate=1/1") != std::string::npos,
          "The terminal completes a real two-gear route after nearby construction, with signed rate inspection.");
    const auto riser = run("gear-riser", "walk west 4\nplace shaft -4 4 0 y 2\nwait 8\ninspect\nremove native-part-1\n"
        "place shaft -4 -4 0 y 2\ninspect\nwalk east 8\nwalk east 8\n" + plates());
    check(riser.code == 0 && riser.errors.empty() &&
          riser.output.find("gear-high generation=1 gear at=-4,0,0 axis=y teeth=2 rotation=unpowered rate=0/1") != std::string::npos &&
          riser.output.find("gear-high generation=1 gear at=-4,0,0 axis=y teeth=2 rotation=rotating rate=1/1") != std::string::npos,
          "Interactive inspection distinguishes the actual separated and coupled gear planes without idealized repair state.");
    for (const auto* result : {&idler, &bend, &riser})
        check(result->output.find("Cargo raw=0 products=4/4") != std::string::npos,
              "Each complete terminal solution retrieves the required real material.");
    check(run("gear-idler", "place gear -4 0 0 z 2\nquit\n").code == 1,
          "A repaired drive alone does not count as the four-plate production objective.");
    std::istringstream input;
    std::ostringstream output, errors;
    const std::array<std::string_view, 1> list{"list"};
    check(factory::repair_scenarios::workbench(list, input, output, errors) == 0 &&
          output.str().find("gear-riser:") != std::string::npos && output.str().find("coupling:") != std::string::npos,
          "The original and geared startup catalogues remain available through one existing caller.");
}
}  // namespace

int main() {
    try {
        check(r::catalogue().size() == 3 && !r::make("missing") && !r::make("coupling"), "The new catalogue has three explicit unique entries.");
        idler();
        bend(1);
        bend(-1);
        riser();
        terminal();
        std::cout << checks << " geared native repair checks, 0 failures.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL after " << checks << " checks: " << error.what() << '\n';
        return 1;
    }
}
