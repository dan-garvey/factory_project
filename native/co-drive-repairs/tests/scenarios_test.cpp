#include "factory/co_drive_scenarios.hpp"
#include "factory/repair_workbench.hpp"

#include <algorithm>
#include <array>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>

namespace c = factory::co_drive_scenarios;
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
    std::unique_ptr<w::World> world;
    I request{};
};
void conserved(const Fixture& fixture) {
    const auto saved = fixture.world->snapshot();
    check(w::validate(fixture.profile, saved), "The actual World validates all material, finite parts, identities and history.");
    auto totals = fixture.profile.finite_parts;
    for (auto& [spec, count] : totals) { (void)spec; count = 0; }
    for (const auto& part : saved.state.topology.parts) ++totals.at({part.role, part.geometry.teeth, part.geometry.half_span});
    for (const auto& [actor, kit] : saved.state.kits) {
        (void)actor;
        for (const auto& [spec, count] : kit) totals.at(spec) += count;
    }
    check(totals == fixture.profile.finite_parts && saved.state.material.initial_units == 16,
          "Every original part and all sixteen initial material units remain accounted for by the sole World.");
}
Fixture fresh(const std::string& suffix) {
    const auto content = c::make("co-drive");
    check(content.has_value(), "The explicit new catalogue name resolves without a fallback.");
    const auto context = "co-drive-" + suffix;
    Fixture fixture{context, content->profile, w::World::create(context, content->profile, content->seed)};
    check(fixture.world != nullptr, "The real World accepts the two-source stalled seed.");
    conserved(fixture);
    const auto state = fixture.world->snapshot().state;
    const auto progress = c::inspect(state);
    const auto power = s::power_view(state.topology).mechanical;
    factory::materials::Quantity parts{};
    for (const auto& [spec, count] : fixture.profile.finite_parts) { (void)spec; parts += count; }
    check(parts == 9 && state.material.stock.source == 16 && progress.sources == 2 && progress.products == 0 &&
          progress.mode == c::Mode::stalled && power.motion.at("wheel-left").state == g::MotionState::stalled &&
          power.motion.at("wheel-right").state == g::MotionState::stalled, "Two equal-rate sources through one reversal actually stall their shared finite line.");
    return fixture;
}
bool accepted(const a::Object& result) { return std::get<bool>(result.at("accepted").storage()); }
a::Object send(Fixture& fixture, a::Object intent, a::Point position) {
    intent.emplace("context", V(fixture.context)); intent.emplace("actor", V("P"));
    intent.emplace("client", V("co-drive-fixture")); intent.emplace("request", V("action-" + std::to_string(++fixture.request)));
    const auto delivery = fixture.world->command({"P", "co-drive-fixture"}, intent,
        [position](const std::string& actor) -> std::optional<a::ActorCut> { return a::ActorCut{actor, position, 1, true, 4}; });
    check(delivery.completed(), "An actual native command returns its original accepted or refused outcome.");
    conserved(fixture);
    return *delivery.result;
}
a::Object remove(Fixture& fixture, const std::string& id, a::Point position) {
    const auto state = fixture.world->snapshot().state;
    const auto found = std::find_if(state.topology.parts.begin(), state.topology.parts.end(), [&](const auto& part) { return part.geometry.id == id; });
    check(found != state.topology.parts.end(), "Removal resolves a current real identity/generation.");
    return send(fixture, {{"action", V("remove")}, {"target", V(id)}, {"generation", V(found->generation)}}, position);
}
a::Object gear(Fixture& fixture, g::Point point, I teeth, a::Point position) {
    return send(fixture, {{"action", V("place")}, {"role", V("gear")},
        {"center", V(V::Array{V(point[0]), V(point[1]), V(point[2])})}, {"axis", V("z")}, {"teeth", V(teeth)}, {"half_span", V(I{0})}}, position);
}
a::Object wheel(Fixture& fixture, g::Point point, a::Point position) {
    return send(fixture, {{"action", V("place")}, {"role", V("waterwheel")},
        {"center", V(V::Array{V(point[0]), V(point[1]), V(point[2])})}, {"axis", V("z")},
        {"teeth", V(I{0})}, {"half_span", V(I{0})}}, position);
}
void move_left_and_replace_gears(Fixture& fixture) {
    check(accepted(remove(fixture, "gear-left", {-4, 0, 0})) && accepted(remove(fixture, "gear-right", {0, 0, 0})),
          "Both original cogs can be refunded through native stationary removal.");
    check(accepted(remove(fixture, "wheel-left", {-4, 0, -4})) &&
          accepted(wheel(fixture, {-8, 0, -4}, {-8, 0, -4})),
          "The original left wheel is moved one whole tile and receives a fresh identity.");
    check(accepted(gear(fixture, {-8, 0, 0}, 2, {-8, 0, 0})) &&
          accepted(gear(fixture, {0, 0, 0}, 2, {0, 0, 0})),
          "The two carried small cogs occupy separate source tiles.");
}
void ticks(Fixture& fixture, int number) {
    for (int n = 0; n < number; ++n) {
        check(fixture.world->tick().error == w::TransactionError::none, "The owning native World advances production without a client tick command.");
        conserved(fixture);
    }
}
bool same_cut(const w::Snapshot& left, const w::Snapshot& right) {
    if (left.state != right.state || left.revision != right.revision || left.history.context != right.history.context ||
        left.history.order != right.history.order || left.history.records.size() != right.history.records.size()) return false;
    for (std::size_t n = 0; n < left.history.records.size(); ++n) {
        if (factory::values::typed_difference(V(left.history.records[n].intent), V(right.history.records[n].intent)) ||
            factory::values::typed_difference(V(left.history.records[n].result), V(right.history.records[n].result))) return false;
    }
    return true;
}
void restore(Fixture& fixture) {
    const auto cut = fixture.world->snapshot();
    auto resumed = w::World::restore(fixture.context, fixture.profile, cut);
    check(resumed && same_cut(cut, resumed->snapshot()), "A fresh native World retains the full typed state, revision, original requests and outcomes.");
    fixture.world = std::move(resumed);
}
void produce(Fixture& fixture) {
    for (int step = 0; step < 64 && fixture.world->snapshot().state.material.cargo.at("P").products < 4; ++step) {
        if (fixture.world->snapshot().state.material.stock.output > 0) {
            check(accepted(send(fixture, {{"action", V("collect")}, {"target", V("processor")},
                {"generation", V(I{1})}, {"amount", V(I{1})}}, {0, 0, 12})), "A nearby actor retrieves one actual native plate into individual cargo.");
        }
        ticks(fixture, 1);
    }
    const auto state = fixture.world->snapshot().state;
    check(state.material.cargo.at("P").products == 4 && state.material.cargo.at("Q").products == 0 && state.material.stock.source < 16,
          "Four individually held plates come from the original source, with no shared or invented credit.");
}
void retirement(bool left) {
    auto fixture = fresh(left ? "retire-left" : "retire-right");
    const auto material = fixture.world->snapshot().state.material;
    ticks(fixture, 8);
    check(fixture.world->snapshot().state.material == material, "The stalled drivetrain cannot extract or process hidden material while waiting.");
    const auto before = fixture.world->snapshot().state;
    const auto far = remove(fixture, left ? "wheel-left" : "wheel-right", {100, 0, 0});
    check(!accepted(far) && std::get<std::string>(far.at("reason").storage()) == "out_of_reach" &&
          fixture.world->snapshot().state == before, "A distant request cannot remove a source or spend/refund parts.");
    check(accepted(remove(fixture, left ? "wheel-left" : "wheel-right", {left ? -4.0 : 0.0, 0, -4})),
          "Either wheel can be retired without disabling the global drive.");
    const auto state = fixture.world->snapshot().state;
    const auto progress = c::inspect(state);
    const auto motion = s::power_view(state.topology).mechanical;
    check(progress.mode == c::Mode::isolated && progress.ready() == left && state.topology.drive_enabled &&
          state.material == material && state.kits.at("P").at({s::Role::waterwheel, 0, 0}) == 1 &&
          motion.motion.at("processor").rate == g::Rate{left ? -1 : 1, 1},
          "Retirement refunds the exact wheel, preserves material and derives the remaining signed line rate.");
    restore(fixture);
    if (!left) {
        ticks(fixture, 4);
        check(!fixture.world->snapshot().state.material.dropped_raw.empty() && !c::inspect(fixture.world->snapshot().state).ready(),
              "Retiring the right wheel reverses the belt and leaves recoverable blanks.");
        move_left_and_replace_gears(fixture);
        check(accepted(gear(fixture, {-4, 4, 0}, 4, {-4, 0, 0})),
              "The idler route restores forward belt motion with one source.");
        check(c::inspect(fixture.world->snapshot().state).ready(), "The repaired single source now drives the belt forward.");
    }
    produce(fixture);
    check(c::inspect(fixture.world->snapshot().state).complete(), "The retired-source arrangement completes the same finite production goal.");
}
void smaller_sources(Fixture& fixture) {
    const auto material = fixture.world->snapshot().state.material;
    move_left_and_replace_gears(fixture);
    const auto state = fixture.world->snapshot().state;
    check(state.material == material && state.topology.drive_enabled && c::inspect(state).mode == c::Mode::choose_source &&
          state.kits.at("P").at({s::Role::gear, 4, 0}) == 2 && state.kits.at("P").at({s::Role::gear, 2, 0}) == 0,
          "Two separated live sources leave an explicit unresolved choice, not a fabricated shared drive.");
}
void coherent(const Fixture& fixture, const std::string& idler) {
    const auto state = fixture.world->snapshot().state;
    const auto progress = c::inspect(state);
    const auto motion = s::power_view(state.topology).mechanical;
    check(progress.mode == c::Mode::co_driven && progress.sources == 2 && progress.ready() &&
          motion.motion.at("native-part-1").rate == g::Rate{-1, 1} && motion.motion.at("wheel-right").rate == g::Rate{-1, 1} &&
          motion.motion.at(idler).rate == g::Rate{1, 2} && motion.motion.at("processor").rate == g::Rate{-1, 1},
          "Two diagonal small-to-large meshes coherently share the line with the expected rational idler rate.");
}
void misplaced_and_current_goal() {
    auto fixture = fresh("wrong-plane");
    smaller_sources(fixture);
    const auto wrong = gear(fixture, {-4, 4, 4}, 4, {-4, 0, 4});
    check(accepted(wrong) && std::get<std::string>(wrong.at("entity").storage()) == "native-part-4",
          "A plausible wrong-plane idler is a real finite retained construction at the ground actor's reach boundary.");
    produce(fixture);
    auto state = fixture.world->snapshot().state;
    check(c::inspect(state).mode == c::Mode::choose_source && !c::inspect(state).complete(),
          "Four real carried plates cannot hide two sources that have not been coupled or retired.");
    const auto material = state.material;
    check(accepted(remove(fixture, "native-part-4", {-4, 0, 4})), "The wrong idler can be refunded with all actual product and work retained.");
    const auto correct = gear(fixture, {-4, 4, 0}, 4, {-4, 0, 0});
    check(accepted(correct) && std::get<std::string>(correct.at("entity").storage()) == "native-part-5",
          "Reusing the same returned cog allocates a fresh identity at the correct plane.");
    state = fixture.world->snapshot().state;
    check(state.material == material && state.issued_entities.contains("native-part-4") && state.next_entity_serial == 6 &&
          c::inspect(state).complete(), "Correction changes only the real mechanical arrangement, retaining old outcomes, work and four plates.");
    coherent(fixture, "native-part-5");
    const auto read_cut = fixture.world->snapshot();
    check(!c::inspect(read_cut.state, "Q").complete() && !c::inspect(read_cut.state, "unknown").known_actor &&
          same_cut(read_cut, fixture.world->snapshot()), "Read-only eligibility gives no cross-actor credit or participant/history mutation.");
    restore(fixture);
    const auto off = send(fixture, {{"action", V("set_drive")}, {"target", V("wheel-right")},
        {"generation", V(I{1})}, {"enabled", V(false)}}, {0, 0, 0});
    check(accepted(off) && c::inspect(fixture.world->snapshot().state).mode == c::Mode::drive_off &&
          !c::inspect(fixture.world->snapshot().state).complete() && fixture.world->snapshot().state.material == material,
          "Current drive facts are reread even after the individual count is satisfied; no cached progress authorizes it.");
}
void source_service(bool left) {
    auto fixture = fresh(left ? "service-left" : "service-right");
    smaller_sources(fixture);
    check(accepted(gear(fixture, {-4, 4, 0}, 4, {-4, 0, 0})), "One refunded large cog completes the finite higher bridge.");
    coherent(fixture, "native-part-4");
    for (int n = 0; n < 16 && !fixture.world->snapshot().state.material.processing; ++n) ticks(fixture, 1);
    const auto cut = fixture.world->snapshot().state.material;
    check(cut.processing && cut.processing->remaining_ticks > 0, "The retained continuation cut contains actual partially processed work.");
    restore(fixture);
    check(accepted(remove(fixture, left ? "native-part-1" : "wheel-right", {left ? -8.0 : 0.0, 0, -4})),
          "Either coherently coupled source can be serviced through the native powered removal rule.");
    check(fixture.world->snapshot().state.material == cut && c::inspect(fixture.world->snapshot().state).mode == c::Mode::isolated,
          "The remaining source powers the original partial work without resetting it.");
    produce(fixture);
    check(c::inspect(fixture.world->snapshot().state).complete(), "Both source-service variants continue to four individually retrieved plates.");
}

std::string plates() {
    std::string commands;
    for (int n = 0; n < 4; ++n) commands += "wait 8\ncollect processor\n";
    return commands;
}
void actual_parser() {
    auto run = [&](const std::string& commands, int expected, const std::string& marker) {
        const std::array<std::string_view, 2> args{"play", "co-drive"};
        std::istringstream input(commands); std::ostringstream output, errors;
        const auto code = factory::repair_scenarios::workbench(args, input, output, errors);
        check(code == expected && errors.str().empty() && output.str().find(marker) != std::string::npos,
              "The actual native stdin caller preserves the expected source arrangement and finite production outcome.");
        return output.str();
    };
    run("remove wheel-right\nwalk north 8\nwalk north 4\n" + plates() + "inspect\nquit\n", 1, "Source arrangement: isolated");
    run("walk west 4\nwalk south 4\nremove wheel-left\nwalk east 4\nwalk north 8\nwalk north 8\n" + plates(), 0, "Source arrangement: isolated");
    const std::string smaller = "walk west 4\nremove gear-left\nremove wheel-left\nwalk west 4\nwalk south 4\n"
        "place machine waterwheel -8 0 -4 z\nwalk north 4\nplace gear -8 0 0 z 2\n"
        "walk east 8\nremove gear-right\nplace gear 0 0 0 z 2\nwalk west 4\n";
    run(smaller + "place gear -4 4 0 z 4\nwalk east 4\nwalk north 8\nwalk north 4\n" + plates(), 0, "Source arrangement: co_driven");
    const std::string wrong = smaller + "walk north 4\nplace gear -4 4 4 z 4\nwalk east 4\nwalk north 8\n" + plates();
    run(wrong + "inspect\nquit\n", 1, "Cargo raw=0 products=4/4");
    const auto corrected = run(wrong + "inspect\nwalk south 8\nwalk west 4\nremove native-part-4\nwalk south 4\nplace gear -4 4 0 z 4\n", 0,
                               "Accepted: ok (native-part-5)");
    check(corrected.find("Source arrangement: choose_source") != std::string::npos && corrected.find("Source arrangement: co_driven") != std::string::npos,
          "The same terminal run diagnoses and repairs the wrong plane with the original carried products.");
    run("wait 32\ninspect\nquit\n", 1, "Stock source=16 collector=0 belt=0 input=0 output=0");
}
}  // namespace

int main() {
    try {
        check(c::catalogue().size() == 1 && !c::make("missing") && !c::make("gear-idler"), "The new initializer has one explicit unique content name.");
        retirement(true); retirement(false); misplaced_and_current_goal(); source_service(true); source_service(false); actual_parser();
        std::cout << checks << " native co-drive checks, 0 failures; engine_calls=0, physical_producers=0.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL after " << checks << " checks: " << error.what() << '\n'; return 1;
    }
}
